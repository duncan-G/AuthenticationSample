locals {
  cognito_domain    = var.cognito_domain_prefix == "" ? null : "${var.cognito_domain_prefix}-${var.bucket_suffix}"
  auth_environments = toset([var.env, "dev"])
  social_idp_names  = length(var.idps) > 0 ? [for k in keys(var.idps) : k == "google" ? "Google" : "SignInWithApple"] : []
  redirect_uri      = length(var.auth_callback) > 0 ? var.auth_callback[0] : ""
}

# =============================================================================
# Cognito User Pools (Prod + Dev)
# =============================================================================
resource "aws_cognito_user_pool" "this" {
  for_each = local.auth_environments # ensure both prod/stage and dev exist

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
}

resource "aws_cognito_user_pool_domain" "this" {
  for_each     = local.auth_environments
  domain       = "${var.project_name}-${each.value}-${var.bucket_suffix}"
  user_pool_id = aws_cognito_user_pool.this[each.value].id
}

# =============================================================================
# Cognito User Pool Clients (web + backend)
# =============================================================================
resource "aws_cognito_user_pool_client" "web" {
  for_each = local.auth_environments

  name         = "${var.project_name}-web-${each.value}"
  user_pool_id = aws_cognito_user_pool.this[each.value].id

  generate_secret        = false
  refresh_token_validity = 3650
  access_token_validity  = 1440
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

  depends_on = [aws_cognito_identity_provider.social]
}

resource "aws_cognito_user_pool_client" "backend" {
  for_each = local.auth_environments

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

# =============================================================================
# Cognito Identity Pool (Prod only) + Provider mapping
# =============================================================================
resource "aws_cognito_identity_pool" "this" {
  identity_pool_name               = "${var.project_name}-identity-${var.env}"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    provider_name           = aws_cognito_user_pool.this[var.env].endpoint
    client_id               = aws_cognito_user_pool_client.web[var.env].id
    server_side_token_check = false
  }
}

# Outputs similar to the non-HA module for parity
output "cognito_user_pool_id" { value = aws_cognito_user_pool.this[var.env].id }
output "cognito_user_pool_arn" { value = aws_cognito_user_pool.this[var.env].arn }
output "cognito_user_pool_endpoint" { value = aws_cognito_user_pool.this[var.env].endpoint }
output "cognito_user_pool_domain" { value = aws_cognito_user_pool_domain.this[var.env].domain }
output "cognito_user_pool_client_id_web" { value = aws_cognito_user_pool_client.web[var.env].id }
output "cognito_user_pool_client_id_back" { value = aws_cognito_user_pool_client.backend[var.env].id }
output "cognito_identity_pool_id" { value = aws_cognito_identity_pool.this.id }

output "cognito_auth_url" {
  value = length(local.redirect_uri) > 0 ? "https://${aws_cognito_user_pool_domain.this[var.env].domain}.auth.${var.region}.amazoncognito.com/oauth2/authorize?response_type=code&client_id=${aws_cognito_user_pool_client.web[var.env].id}&redirect_uri=${local.redirect_uri}" : ""
}

# Dev outputs for convenience
output "cognito_user_pool_id_dev" { value = aws_cognito_user_pool.this["dev"].id }
output "cognito_user_pool_arn_dev" { value = aws_cognito_user_pool.this["dev"].arn }
output "cognito_user_pool_endpoint_dev" { value = aws_cognito_user_pool.this["dev"].endpoint }
output "cognito_user_pool_domain_dev" { value = aws_cognito_user_pool_domain.this["dev"].domain }
output "cognito_user_pool_client_id_web_dev" { value = aws_cognito_user_pool_client.web["dev"].id }
output "cognito_user_pool_client_id_back_dev" { value = aws_cognito_user_pool_client.backend["dev"].id }

output "cognito_auth_url_dev" {
  value = length(local.redirect_uri) > 0 ? "https://${aws_cognito_user_pool_domain.this["dev"].domain}.auth.${var.region}.amazoncognito.com/oauth2/authorize?response_type=code&client_id=${aws_cognito_user_pool_client.web["dev"].id}&redirect_uri=${local.redirect_uri}" : ""
}

