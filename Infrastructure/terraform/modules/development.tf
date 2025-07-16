########################
# Developer Secret Manager and SSO Configuration
########################

# Data sources
data "aws_ssoadmin_instances" "sso" {}

data "aws_identitystore_identity_store" "identity_store" {
  identity_store_id = tolist(data.aws_ssoadmin_instances.sso.identity_store_ids)[0]
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

########################
# SSO Permission Set Configuration
########################

# Developer permission set
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

# Attach the custom policy to the permission set
resource "aws_ssoadmin_permission_set_inline_policy" "developer_secret_manager_inline_policy" {
  inline_policy = templatefile("${path.module}/developer-policy.json", {
    region     = var.region
    account_id = data.aws_caller_identity.current.account_id
    app_name   = var.app_name
  })
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
# SSO Group Configuration
########################

# Create SSO group "Developers"
resource "aws_identitystore_group" "developers" {
  identity_store_id = data.aws_identitystore_identity_store.identity_store.identity_store_id

  display_name = "Developers"
  description  = "Development team with access to development secrets"
}

# Note: Users should be created manually and assigned to groups manually
# for better security and user lifecycle management

########################
# Outputs
########################

output "app_secrets_development_arn" {
  description = "ARN of the development secrets"
  value       = aws_secretsmanager_secret.app_secrets_development.arn
}

output "app_secrets_development_name" {
  description = "Name of the development secrets"
  value       = aws_secretsmanager_secret.app_secrets_development.name
}

output "developer_permission_set_arn" {
  description = "ARN of the developer permission set"
  value       = aws_ssoadmin_permission_set.developer.arn
}

output "developer_group_id" {
  description = "ID of the Developers SSO group"
  value       = aws_identitystore_group.developers.group_id
}

output "sso_instance_arn" {
  description = "ARN of the SSO instance"
  value       = tolist(data.aws_ssoadmin_instances.sso.arns)[0]
} 