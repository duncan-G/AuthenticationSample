"" ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
variable "idps" {
  description = "SOCIAL / OIDC IdPs (keys: google | apple)"
  type = map(object({
    client_id     = string
    client_secret = string
    scopes        = string
  }))
  default = {}
  validation {
    condition = alltrue([ for k, _ in var.idps : contains(["google", "apple"], k) ])
    error_message = "Only 'google' and 'apple' providers are supported"
  }
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------

data "aws_route53_zone" "this" {
  id = var.route53_hosted_zone_id
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# SES – domain verification & DKIM
# ---------------------------------------------------------------------------

resource "aws_ses_domain_identity" "this" {
  domain = var.domain_name
}

resource "aws_route53_record" "ses_verification" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = "_amazonses.${aws_ses_domain_identity.this.domain}"
  type    = "TXT"
  ttl     = 600
  records = [aws_ses_domain_identity.this.verification_token]
}

resource "aws_ses_domain_identity_verification" "this" {
  domain     = aws_ses_domain_identity.this.domain
  depends_on = [aws_route53_record.ses_verification]
}

resource "aws_ses_domain_dkim" "this" {
  domain = aws_ses_domain_identity.this.domain
}

resource "aws_route53_record" "dkim" {
  count   = 3
  zone_id = data.aws_route53_zone.this.zone_id
  name    = "${aws_ses_domain_dkim.this.dkim_tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_ses_domain_dkim.this.dkim_tokens[count.index]}.dkim.amazonses.com"]
}

# ---------------------------------------------------------------------------
# Cognito – User Pool & domain
# ---------------------------------------------------------------------------

resource "aws_cognito_user_pool" "this" {
  name = "${var.app_name}-user-pool-${var.environment}"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = false
  }

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  email_configuration {
    email_sending_account = "DEVELOPER"
    from_email_address    = "no-reply@${var.domain_name}"
    source_arn            = aws_ses_domain_identity.this.arn
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your ${var.app_name} verification code"
    email_message        = "Your verification code is {####}"
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  device_configuration {
    challenge_required_on_new_device      = true
    device_only_remembered_on_user_prompt = false
  }

  schema {
    name        = "email"
    attribute_data_type = "String"
    mutable      = true
    required     = true
    string_attribute_constraints { min_length = 1  max_length = 256 }
  }

  schema {
    name        = "name"
    attribute_data_type = "String"
    mutable      = true
    required     = false
    string_attribute_constraints { min_length = 1  max_length = 256 }
  }

  tags = { Environment = var.environment }
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.app_name}-${var.environment}-${var.bucket_suffix}"
  user_pool_id = aws_cognito_user_pool.this.id
}

# ---------------------------------------------------------------------------
# Development User Pool (separate from environment-based pool)
# ---------------------------------------------------------------------------

resource "aws_cognito_user_pool" "dev" {
  name = "${var.app_name}-user-pool-dev"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = false
  }

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  email_configuration {
    email_sending_account = "DEVELOPER"
    from_email_address    = "no-reply@${var.domain_name}"
    source_arn            = aws_ses_domain_identity.this.arn
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your ${var.app_name} verification code"
    email_message        = "Your verification code is {####}"
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  device_configuration {
    challenge_required_on_new_device      = true
    device_only_remembered_on_user_prompt = false
  }

  schema {
    name        = "email"
    attribute_data_type = "String"
    mutable      = true
    required     = true
    string_attribute_constraints { min_length = 1  max_length = 256 }
  }

  schema {
    name        = "name"
    attribute_data_type = "String"
    mutable      = true
    required     = false
    string_attribute_constraints { min_length = 1  max_length = 256 }
  }

  tags = { Environment = "dev" }
}

resource "aws_cognito_user_pool_domain" "dev" {
  domain       = "${var.app_name}-dev-${var.bucket_suffix}"
  user_pool_id = aws_cognito_user_pool.dev.id
}

# ---------------------------------------------------------------------------
# Social / OIDC Identity Providers (Google & Apple)
# ---------------------------------------------------------------------------

resource "aws_cognito_identity_provider" "social" {
  for_each = var.idps

  user_pool_id  = aws_cognito_user_pool.this.id
  provider_name = each.key == "google" ? "Google" : "SignInWithApple"
  provider_type = provider_name

  provider_details = {
    client_id        = each.value.client_id
    client_secret    = each.value.client_secret
    authorize_scopes = each.value.scopes
  }

  attribute_mapping = {
    email          = "email"
    email_verified = "email_verified"
    name           = "name"
  }
}

# ---------------------------------------------------------------------------
# Dev Social / OIDC Identity Providers (Google & Apple)
# ---------------------------------------------------------------------------

resource "aws_cognito_identity_provider" "social_dev" {
  for_each = var.idps

  user_pool_id  = aws_cognito_user_pool.dev.id
  provider_name = each.key == "google" ? "Google" : "SignInWithApple"
  provider_type = provider_name

  provider_details = {
    client_id        = each.value.client_id
    client_secret    = each.value.client_secret
    authorize_scopes = each.value.scopes
  }

  attribute_mapping = {
    email          = "email"
    email_verified = "email_verified"
    name           = "name"
  }
}

# ---------------------------------------------------------------------------
# User‑pool clients
# ---------------------------------------------------------------------------

locals {
  social_idp_names = length(var.idps) > 0 ? [for k in keys(var.idps) : k == "google" ? "Google" : "SignInWithApple"] : []
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.app_name}-web-${var.environment}"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret        = false
  refresh_token_validity = 3650  # days
  access_token_validity  = 1440  # minutes (24h)
  id_token_validity      = 1440
  token_validity_units {
    refresh_token = "days"
    access_token  = "minutes"
    id_token      = "minutes"
  }

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  callback_urls = var.auth_callback
  logout_urls   = var.auth_logout

  supported_identity_providers = concat(["COGNITO"], local.social_idp_names)

  explicit_auth_flows = [
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_USER_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  prevent_user_existence_errors = "ENABLED"

  read_attributes  = ["email", "email_verified", "name", "preferred_username"]
  write_attributes = ["email", "name", "preferred_username"]

  depends_on = [aws_cognito_identity_provider.social]
}

resource "aws_cognito_user_pool_client" "backend" {
  name         = "${var.app_name}-backend-${var.environment}"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret        = true
  refresh_token_validity = 3650
  access_token_validity  = 1440
  id_token_validity      = 1440
  token_validity_units {
    refresh_token = "days"
    access_token  = "minutes"
    id_token      = "minutes"
  }

  explicit_auth_flows = [
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_USER_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  prevent_user_existence_errors = "ENABLED"
}

# ---------------------------------------------------------------------------
# Identity Pool + roles
# ---------------------------------------------------------------------------

resource "aws_cognito_identity_pool" "this" {
  identity_pool_name               = "${var.app_name}-identity-${var.environment}"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    provider_name           = aws_cognito_user_pool.this.endpoint
    client_id               = aws_cognito_user_pool_client.web.id
    server_side_token_check = false
  }

  tags = { Environment = var.environment }
}

data "aws_iam_policy_document" "auth_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = ["cognito-identity.amazonaws.com"]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "cognito-identity.amazonaws.com:aud"
      values   = [aws_cognito_identity_pool.this.id]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "cognito-identity.amazonaws.com:amr"
      values   = ["authenticated"]
    }
  }
}

resource "aws_iam_role" "auth_users" {
  name               = "${var.app_name}-auth-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.auth_assume.json
}

locals {
  user_content_bucket = "${var.app_name}-user-content-${var.environment}-${var.bucket_suffix}"
}

resource "aws_iam_policy" "auth_users" {
  name        = "${var.app_name}-auth-policy-${var.environment}"
  description = "Permissions for authenticated Cognito users"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["cognito-sync:*", "cognito-identity:*"],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
        Resource = "arn:aws:s3:::${local.user_content_bucket}/users/$${cognito-identity.amazonaws.com:sub}/*"
      },
      {
        Effect   = "Allow",
        Action   = ["s3:ListBucket"],
        Resource = "arn:aws:s3:::${local.user_content_bucket}",
        Condition = {
          StringLike = { "s3:prefix" : ["users/$${cognito-identity.amazonaws.com:sub}/*"] }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "auth_users" {
  role       = aws_iam_role.auth_users.name
  policy_arn = aws_iam_policy.auth_users.arn
}

resource "aws_cognito_identity_pool_roles_attachment" "this" {
  identity_pool_id = aws_cognito_identity_pool.this.id

  roles = {
    authenticated = aws_iam_role.auth_users.arn
  }

  role_mapping {
    identity_provider         = "${aws_cognito_user_pool.this.endpoint}:${aws_cognito_user_pool_client.web.id}"
    ambiguous_role_resolution = "AuthenticatedRole"
    type                      = "Token"
  }
}

# ---------------------------------------------------------------------------
# Groups (optional convenience)
# ---------------------------------------------------------------------------

resource "aws_cognito_user_pool_group" "user" {
  name         = "user"
  user_pool_id = aws_cognito_user_pool.this.id
  precedence   = 1
  description  = "Standard users"
}

# ---------------------------------------------------------------------------
# Dev User-pool clients
# ---------------------------------------------------------------------------

resource "aws_cognito_user_pool_client" "web_dev" {
  name         = "${var.app_name}-web-dev"
  user_pool_id = aws_cognito_user_pool.dev.id

  generate_secret        = false
  refresh_token_validity = 3650  # days
  access_token_validity  = 1440  # minutes (24h)
  id_token_validity      = 1440
  token_validity_units {
    refresh_token = "days"
    access_token  = "minutes"
    id_token      = "minutes"
  }

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  callback_urls = var.auth_callback
  logout_urls   = var.auth_logout

  supported_identity_providers = concat(["COGNITO"], local.social_idp_names)

  explicit_auth_flows = [
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_USER_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  prevent_user_existence_errors = "ENABLED"

  read_attributes  = ["email", "email_verified", "name", "preferred_username"]
  write_attributes = ["email", "name", "preferred_username"]

  depends_on = [aws_cognito_identity_provider.social_dev]
}

resource "aws_cognito_user_pool_client" "backend_dev" {
  name         = "${var.app_name}-backend-dev"
  user_pool_id = aws_cognito_user_pool.dev.id

  generate_secret        = true
  refresh_token_validity = 3650
  access_token_validity  = 1440
  id_token_validity      = 1440
  token_validity_units {
    refresh_token = "days"
    access_token  = "minutes"
    id_token      = "minutes"
  }

  explicit_auth_flows = [
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_USER_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  prevent_user_existence_errors = "ENABLED"
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "cognito_user_pool_id"              { value = aws_cognito_user_pool.this.id }
output "cognito_user_pool_arn"             { value = aws_cognito_user_pool.this.arn }
output "cognito_user_pool_endpoint"        { value = aws_cognito_user_pool.this.endpoint }
output "cognito_user_pool_domain"          { value = aws_cognito_user_pool_domain.this.domain }
output "cognito_user_pool_client_id_web"   { value = aws_cognito_user_pool_client.web.id }
output "cognito_user_pool_client_id_back"  { value = aws_cognito_user_pool_client.backend.id }
output "cognito_identity_pool_id"          { value = aws_cognito_identity_pool.this.id }
output "authenticated_role_arn"            { value = aws_iam_role.auth_users.arn }
output "cognito_auth_url" {
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${var.region}.amazoncognito.com"
  description = "Hosted UI URL"
}

# ---------------------------------------------------------------------------
# Dev Outputs
# ---------------------------------------------------------------------------

output "cognito_user_pool_id_dev"              { value = aws_cognito_user_pool.dev.id }
output "cognito_user_pool_arn_dev"             { value = aws_cognito_user_pool.dev.arn }
output "cognito_user_pool_endpoint_dev"        { value = aws_cognito_user_pool.dev.endpoint }
output "cognito_user_pool_domain_dev"          { value = aws_cognito_user_pool_domain.dev.domain }
output "cognito_user_pool_client_id_web_dev"   { value = aws_cognito_user_pool_client.web_dev.id }
output "cognito_user_pool_client_id_back_dev"  { value = aws_cognito_user_pool_client.backend_dev.id }
output "cognito_auth_url_dev" {
  value       = "https://${aws_cognito_user_pool_domain.dev.domain}.auth.${var.region}.amazoncognito.com"
  description = "Dev Hosted UI URL"
}
