# =============================================================================
# AWS Cognito OIDC Provider Infrastructure
# =============================================================================
# Manages Cognito components for authentication:
# 
# • Cognito User Pools (prod and dev)
# • Social Identity Providers (Google, Apple)
# • User Pool Clients (web and backend)
# • Identity Pool for authenticated users (for the primary environment `var.env`)
# =============================================================================

#region Configuration

# Variables
variable "idps" {
  description = "SOCIAL / OIDC IdPs (keys: google | apple)"
  type = map(object({
    client_id     = string
    client_secret = string
    scopes        = string
    provider_name = string
    provider_type = string
  }))
  default = {}

  validation {
    condition     = alltrue([for k, _ in var.idps : contains(["google", "apple"], k)])
    error_message = "Only 'google' and 'apple' providers are supported"
  }
}

variable "auth_callback" {
  description = "Cognito callback URLs"
  type        = list(string)
}

variable "auth_logout" {
  description = "Cognito logout URLs"
  type        = list(string)
}

# Locals
locals {
  # Define environments to create user pools for
  environments = [var.env, "dev"]

  # Social IDP Names
  social_idp_names = length(var.idps) > 0 ? [for k in keys(var.idps) : k == "google" ? "Google" : "SignInWithApple"] : []
}

#endregion

#region Resources

# User Pools (Production and Development)
resource "aws_cognito_user_pool" "this" {
  for_each = toset(local.environments)

  name = "${var.project_name}-user-pool-${each.value}"

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
    email_subject        = "Your ${var.project_name} verification code"
    email_message        = "Your verification code is {####}"
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  tags = { Environment = each.value }
}

# User Pool Domains
resource "aws_cognito_user_pool_domain" "this" {
  for_each = toset(local.environments)

  domain       = "${var.project_name}-${each.value}-${var.bucket_suffix}"
  user_pool_id = aws_cognito_user_pool.this[each.value].id
}

# Social Identity Providers
resource "aws_cognito_identity_provider" "social" {
  for_each = {
    for pair in setproduct(keys(var.idps), local.environments) : "${pair[0]}-${pair[1]}" => {
      idp_key = pair[0]
      env     = pair[1]
    }
  }

  user_pool_id  = aws_cognito_user_pool.this[each.value.env].id
  provider_name = var.idps[each.value.idp_key].provider_name
  provider_type = var.idps[each.value.idp_key].provider_type

  provider_details = {
    client_id        = var.idps[each.value.idp_key].client_id
    client_secret    = var.idps[each.value.idp_key].client_secret
    authorize_scopes = var.idps[each.value.idp_key].scopes
  }

  attribute_mapping = {
    email    = "email"
    username = "sub"
  }
}

# Web Clients
resource "aws_cognito_user_pool_client" "web" {
  for_each = toset(local.environments)

  name         = "${var.project_name}-web-${each.value}"
  user_pool_id = aws_cognito_user_pool.this[each.value].id

  generate_secret        = false
  refresh_token_validity = 3650 # days
  access_token_validity  = 1440 # minutes (24h)
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

# Backend Clients
resource "aws_cognito_user_pool_client" "backend" {
  for_each = toset(local.environments)

  name         = "${var.project_name}-backend-${each.value}"
  user_pool_id = aws_cognito_user_pool.this[each.value].id

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

# Cognito Identity Pool (only for prod environment)
resource "aws_cognito_identity_pool" "this" {
  identity_pool_name               = "${var.project_name}-identity-${var.env}"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    provider_name           = aws_cognito_user_pool.this[var.env].endpoint
    client_id               = aws_cognito_user_pool_client.web[var.env].id
    server_side_token_check = false
  }

  tags = { Environment = var.env }
}

#endregion

#region Outputs

# Production Environment Outputs
output "cognito_user_pool_id" { value = aws_cognito_user_pool.this[var.env].id }
output "cognito_user_pool_arn" { value = aws_cognito_user_pool.this[var.env].arn }
output "cognito_user_pool_endpoint" { value = aws_cognito_user_pool.this[var.env].endpoint }
output "cognito_user_pool_domain" { value = aws_cognito_user_pool_domain.this[var.env].domain }
output "cognito_user_pool_client_id_web" { value = aws_cognito_user_pool_client.web[var.env].id }
output "cognito_user_pool_client_id_back" { value = aws_cognito_user_pool_client.backend[var.env].id }
output "cognito_identity_pool_id" { value = aws_cognito_identity_pool.this.id }
output "cognito_auth_url" {
  value = "https://${aws_cognito_user_pool_domain.this[var.env].domain}.auth.${var.region}.amazoncognito.com/oauth2/authorize?response_type=code&client_id=${aws_cognito_user_pool_client.web[var.env].id}&redirect_uri=${var.auth_callback[0]}"
}

# Development Environment Outputs
output "cognito_user_pool_id_dev" { value = aws_cognito_user_pool.this["dev"].id }
output "cognito_user_pool_arn_dev" { value = aws_cognito_user_pool.this["dev"].arn }
output "cognito_user_pool_endpoint_dev" { value = aws_cognito_user_pool.this["dev"].endpoint }
output "cognito_user_pool_domain_dev" { value = aws_cognito_user_pool_domain.this["dev"].domain }
output "cognito_user_pool_client_id_web_dev" { value = aws_cognito_user_pool_client.web["dev"].id }
output "cognito_user_pool_client_id_back_dev" { value = aws_cognito_user_pool_client.backend["dev"].id }
output "cognito_auth_url_dev" {
  value = "https://${aws_cognito_user_pool_domain.this["dev"].domain}.auth.${var.region}.amazoncognito.com/oauth2/authorize?response_type=code&client_id=${aws_cognito_user_pool_client.web["dev"].id}&redirect_uri=${var.auth_callback[0]}"
}

#endregion