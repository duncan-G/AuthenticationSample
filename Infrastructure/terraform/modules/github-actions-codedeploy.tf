# GitHub Actions OIDC Provider for CodeDeploy deployments
resource "aws_iam_openid_connect_provider" "github_actions_codedeploy" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = {
    Name        = "${var.app_name}-github-actions-oidc-codedeploy"
    Environment = var.environment
    Purpose     = "GitHub Actions CodeDeploy Deployments"
  }
}

# IAM Policy for GitHub Actions CodeDeploy deployments
resource "aws_iam_policy" "github_actions_codedeploy_policy" {
  name        = "${var.app_name}-github-actions-policy-codedeploy"
  description = "Policy for GitHub Actions to deploy via AWS CodeDeploy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = [
          "arn:aws:ecr:*:*:repository/${var.app_name}*"
        ]
      },
      {
        Sid    = "S3DeploymentBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.deployment_bucket}",
          "arn:aws:s3:::${var.deployment_bucket}/*"
        ]
      },
      {
        Sid    = "CodeDeployAccess"
        Effect = "Allow"
        Action = [
          "codedeploy:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
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
    Name        = "${var.app_name}-github-actions-policy-codedeploy"
    Environment = var.environment
    Purpose     = "GitHub Actions CodeDeploy Deployments"
  }
}

# IAM Role for GitHub Actions CodeDeploy deployments
resource "aws_iam_role" "github_actions_codedeploy" {
  name = "${var.app_name}-github-actions-role-codedeploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions_codedeploy.arn
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:${var.github_repository}:environment:${var.staging_environment}",
              "repo:${var.github_repository}:environment:${var.production_environment}"
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-github-actions-role-codedeploy"
    Environment = var.environment
    Purpose     = "GitHub Actions CodeDeploy Deployments"
  }
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "github_actions_codedeploy_policy_attachment" {
  role       = aws_iam_role.github_actions_codedeploy.name
  policy_arn = aws_iam_policy.github_actions_codedeploy_policy.arn
}

# Output the role ARN
output "github_actions_codedeploy_role_arn" {
  description = "ARN of the GitHub Actions CodeDeploy deployment role"
  value       = aws_iam_role.github_actions_codedeploy.arn
} 