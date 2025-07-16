########################
# IAM Identity Center (SSO) Configuration
########################

# Data source for existing SSO instance
data "aws_ssoadmin_instances" "sso" {}

# Permission set for developer role
resource "aws_ssoadmin_permission_set" "developer" {
  name             = "developer"
  description      = "Developer permission set with Secret Manager access"
  instance_arn     = tolist(data.aws_ssoadmin_instances.sso.arns)[0]
  session_duration = "PT12H"

  tags = {
    Name        = "${var.app_name}-developer-permission-set"
    Environment = var.environment
    Purpose     = "Developer Access"
  }
}

# Custom policy for developer Secret Manager access
resource "aws_iam_policy" "developer_secret_manager_policy" {
  name        = "${var.app_name}-developer-secret-manager-policy"
  description = "Developer permissions for Secret Manager with restricted access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GetSecretValue"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.app_name}-secrets-development*"
        ]
      },
      {
        Sid    = "ModifySecretValue"
        Effect = "Allow"
        Action = [
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.app_name}-secrets-development*"
        ]
      },
      {
        Sid    = "CreateSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "secretsmanager:Name" = "${var.app_name}-secrets-development*"
          }
        }
      },
      {
        Sid    = "ListSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyDelete"
        Effect = "Deny"
        Action = [
          "secretsmanager:DeleteSecret",
          "secretsmanager:ScheduleDeleteSecret",
          "secretsmanager:CancelDeleteSecret"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-developer-secret-manager-policy"
    Environment = var.environment
    Purpose     = "Developer Secret Manager Access"
  }
}

# Attach the custom policy to the permission set
resource "aws_ssoadmin_permission_set_inline_policy" "developer_secret_manager_inline_policy" {
  inline_policy      = aws_iam_policy.developer_secret_manager_policy.policy
  instance_arn       = tolist(data.aws_ssoadmin_instances.sso.arns)[0]
  permission_set_arn = aws_ssoadmin_permission_set.developer.arn
}

# Additional read-only permissions for basic AWS services
resource "aws_ssoadmin_managed_policy_attachment" "developer_readonly_access" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.sso.arns)[0]
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  permission_set_arn = aws_ssoadmin_permission_set.developer.arn
}

########################
# Secret Manager Configuration
########################

# Create the main development secrets
resource "aws_secretsmanager_secret" "app_secrets_development" {
  name        = "${var.app_name}-secrets-development"
  description = "Development secrets for ${var.app_name}"

  tags = {
    Name        = "${var.app_name}-secrets-development"
    Environment = "development"
    Purpose     = "Application Development Secrets"
  }
}

# Initial secret value (can be updated by developers)
resource "aws_secretsmanager_secret_version" "app_secrets_development" {
  secret_id = aws_secretsmanager_secret.app_secrets_development.id
  secret_string = jsonencode({
    database_url = "placeholder-database-url"
    api_key      = "placeholder-api-key"
    jwt_secret   = "placeholder-jwt-secret"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

########################
# Outputs
########################

output "developer_permission_set_arn" {
  description = "ARN of the developer permission set"
  value       = aws_ssoadmin_permission_set.developer.arn
}

output "developer_secret_manager_policy_arn" {
  description = "ARN of the developer Secret Manager policy"
  value       = aws_iam_policy.developer_secret_manager_policy.arn
}

output "app_secrets_development_arn" {
  description = "ARN of the development secrets"
  value       = aws_secretsmanager_secret.app_secrets_development.arn
}

output "app_secrets_development_name" {
  description = "Name of the development secrets"
  value       = aws_secretsmanager_secret.app_secrets_development.name
}

output "sso_instance_arn" {
  description = "ARN of the SSO instance"
  value       = tolist(data.aws_ssoadmin_instances.sso.arns)[0]
} 