# Cognito (current environment only)
output "cognito_user_pool_id" { value = aws_cognito_user_pool.this.id }
output "cognito_user_pool_arn" { value = aws_cognito_user_pool.this.arn }
output "cognito_user_pool_endpoint" { value = aws_cognito_user_pool.this.endpoint }
output "cognito_user_pool_web_client_id" { value = aws_cognito_user_pool_client.web.id }
output "cognito_user_pool_user_pool_endpoint" { value = aws_cognito_user_pool.this.endpoint }
output "cognito_identity_pool_id" { value = aws_cognito_identity_pool.this.id }

# IAM
output "authenticated_role_arn" {
  value       = aws_iam_role.auth_users.arn
  description = "ARN of the IAM role for authenticated Cognito users"
}
