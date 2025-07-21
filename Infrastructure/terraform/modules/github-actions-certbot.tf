# IAM Role for GitHub Actions Certbot workflow
resource "aws_iam_role" "github_actions_certbot" {
  name = "${var.app_name}-github-actions-role-certbot"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:${var.github_repository}:environment:${var.staging_environment_name}",
              "repo:${var.github_repository}:environment:${var.production_environment_name}"
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-github-actions-role-certbot"
    Environment = var.environment
    Purpose     = "GitHub Actions Certbot Workflow"
  }
}

# IAM Policy for GitHub Actions Certbot workflow
resource "aws_iam_policy" "github_actions_certbot_policy" {
  name        = "${var.app_name}-github-actions-policy-certbot"
  description = "Policy for GitHub Actions to build and push certbot Docker image"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRGetAuthorizationToken"
        Effect   = "Allow"
        Action   = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRRepositoryAccess"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = [
          "arn:aws:ecr:*:*:repository/${var.app_name}*",
          "arn:aws:ecr:*:*:repository/${var.app_name}/certbot"
        ]
      },
      {
        Sid    = "S3CertbotArtifactsAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.app_name}-certbot-${var.bucket_suffix}",
          "arn:aws:s3:::${var.app_name}-certbot-${var.bucket_suffix}/*"
        ]
      },
      {
        Sid    = "STSAssumeRole"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-github-actions-policy-certbot"
    Environment = var.environment
    Purpose     = "GitHub Actions Certbot Workflow"
  }
}

# Attach policy to certbot role
resource "aws_iam_role_policy_attachment" "github_actions_certbot_policy_attachment" {
  role       = aws_iam_role.github_actions_certbot.name
  policy_arn = aws_iam_policy.github_actions_certbot_policy.arn
}

# Output the certbot role ARN
output "github_actions_certbot_role_arn" {
  description = "ARN of the GitHub Actions certbot workflow role"
  value       = aws_iam_role.github_actions_certbot.arn
} 