locals {
  cognito_domain = var.cognito_domain_prefix == "" ? null : "${var.cognito_domain_prefix}-${var.bucket_suffix}"
}

resource "aws_cognito_user_pool" "this" {
  name = "${var.project_name}-${var.env}-users"
}

resource "aws_cognito_user_pool_client" "this" {
  name         = "${var.project_name}-${var.env}-web"
  user_pool_id = aws_cognito_user_pool.this.id
  callback_urls = var.auth_callback
  logout_urls   = var.auth_logout
  generate_secret = false
  allowed_oauth_flows       = ["code"]
  allowed_oauth_scopes      = ["email","openid","profile"]
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers = ["COGNITO"]
}

resource "aws_cognito_identity_pool" "this" {
  identity_pool_name               = "${var.project_name}-${var.env}"
  allow_unauthenticated_identities = false
}

resource "aws_cognito_user_pool_domain" "this" {
  count       = local.cognito_domain == null ? 0 : 1
  domain      = local.cognito_domain
  user_pool_id = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_id" { value = aws_cognito_user_pool.this.id }
output "cognito_user_pool_client_id" { value = aws_cognito_user_pool_client.this.id }
output "cognito_identity_pool_id" { value = aws_cognito_identity_pool.this.id }


