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

#region IAM Roles

# IAM Role for Authenticated Users
resource "aws_iam_role" "auth_users" {
  name               = "${var.project_name}-auth-${var.env}"
  assume_role_policy = data.aws_iam_policy_document.auth_assume.json
}

#endregion

#region IAM Policies

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

# IAM Policy for Authenticated Users
# resource "aws_iam_policy" "auth_users" {
#   name        = "${var.project_name}-auth-users-${var.env}"
#   description = "Policy for authenticated Cognito users"

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#         ]
#         Resource = "*"
#       }
#     ]
#   })
# }

#endregion

#region IAM Policy Attachments

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

#region Outputs

output "authenticated_role_arn" {
  value       = aws_iam_role.auth_users.arn
  description = "ARN of the IAM role for authenticated Cognito users"
}

#endregion 