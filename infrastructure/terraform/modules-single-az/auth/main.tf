# =============================================================================
# AWS Cognito OIDC Provider Infrastructure
# =============================================================================
# Manages Cognito components for authentication:
#
# • Cognito User Pools
# • Social Identity Providers (Google, Apple)
# • User Pool Clients (web and backend)
# • Identity Pool for authenticated users (for the primary environment `var.env`)
# =============================================================================

#region Cognito OIDC Provider

# Locals
locals {
  # Social IDP Names
  social_idp_names = length(var.idps) > 0 ? [for k in keys(var.idps) : k == "google" ? "Google" : "SignInWithApple"] : []
}

# User Pool
resource "aws_cognito_user_pool" "this" {

  name = "${var.project_name}-user-pool-${var.env}"

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

  dynamic "email_configuration" {
    for_each = var.env == "prod" ? [1] : []
    content {
      email_sending_account = "DEVELOPER"
      from_email_address    = "no-reply@${var.domain_name}"
      source_arn            = var.ses_domain_identity_arn
    }
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your ${var.project_name} verification code"
    email_message        = <<-HTML
		  <html>
		    <body style="margin:0;padding:24px;background:#f7f7f8;color:#111;font-family:system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
		      <div style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:12px;padding:28px;">
		        <h1 style="margin:0 0 12px;font-size:20px;line-height:1.2;">Verify your email</h1>
		        <p style="margin:0 0 18px;line-height:1.6;">Enter this one-time code to verify your email address:</p>
		        <div style="font-size:28px;letter-spacing:6px;font-weight:700;background:#111;color:#fff;display:inline-block;padding:10px 14px;border-radius:10px;">
		          {####}
		        </div>
		        <p style="margin:18px 0 0;color:#555;font-size:13px;line-height:1.6;">
		          This code expires soon. If you didn’t request it, you can ignore this email.
		        </p>
		      </div>
		    </body>
		  </html>
		HTML
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  sign_in_policy {
    allowed_first_auth_factors = ["PASSWORD", "EMAIL_OTP", "WEB_AUTHN"]
  }

  tags = { Environment = var.env }
}

# Social Identity Providers
resource "aws_cognito_identity_provider" "social" {
  for_each = var.idps

  user_pool_id  = aws_cognito_user_pool.this.id
  provider_name = each.value.provider_name
  provider_type = each.value.provider_type

  provider_details = {
    client_id        = each.value.client_id
    client_secret    = each.value.client_secret
    authorize_scopes = each.value.scopes
  }

  attribute_mapping = {
    email    = "email"
    username = "sub"
  }
}

# Web Client
resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.project_name}-web-${var.env}"
  user_pool_id = aws_cognito_user_pool.this.id

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

  supported_identity_providers = local.social_idp_names

  explicit_auth_flows = [
    "ALLOW_USER_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  prevent_user_existence_errors = "ENABLED"

  read_attributes  = ["email", "email_verified", "name", "preferred_username"]
  write_attributes = ["email", "name", "preferred_username"]

  depends_on = [aws_cognito_identity_provider.social]
}

# Backend Client
resource "aws_cognito_user_pool_client" "backend" {

  name         = "${var.project_name}-backend-${var.env}"
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

# Cognito Identity Pool
resource "aws_cognito_identity_pool" "this" {
  identity_pool_name               = "${var.project_name}-identity-${var.env}"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    provider_name           = aws_cognito_user_pool.this.endpoint
    client_id               = aws_cognito_user_pool_client.web.id
    server_side_token_check = false
  }

  tags = { Environment = var.env }
}

#endregion

# =============================================================================
# AWS Cognito IAM Infrastructure
# =============================================================================
# This file manages all IAM components required for AWS Cognito users:
#
# • IAM roles for authenticated Cognito users
# • IAM policies for user permissions
# • Role attachments and policy assignments
# • Identity pool role mappings
# =============================================================================

#region Cognito IAM

# IAM Role for Authenticated Users
resource "aws_iam_role" "auth_users" {
  name               = "${var.project_name}-auth-${var.env}"
  assume_role_policy = data.aws_iam_policy_document.auth_assume.json
}

# IAM Policy Document for Authenticated Users
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
      test     = "ForAnyValue:StringEquals"
      variable = "cognito-identity.amazonaws.com:amr"
      values   = ["authenticated"]
    }
  }
}

# IAM Role Policy Attachment
resource "aws_iam_role_policy_attachment" "auth_users" {
  count      = var.authenticated_policy_arn == "" ? 0 : 1
  role       = aws_iam_role.auth_users.name
  policy_arn = var.authenticated_policy_arn
}

# Cognito Identity Pool Roles Attachment
resource "aws_cognito_identity_pool_roles_attachment" "this" {
  identity_pool_id = aws_cognito_identity_pool.this.id

  roles = {
    authenticated = aws_iam_role.auth_users.arn
  }
}

#endregion
