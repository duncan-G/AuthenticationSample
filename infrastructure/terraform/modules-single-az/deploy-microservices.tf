# =============================================================================
# AWS CodeDeploy Infrastructure
# =============================================================================
# This file manages all infrastructure components required for AWS CodeDeploy:
# 
# • CodeDeploy applications and deployment groups for microservices
# • S3 bucket referencefor deployment artifacts
# • IAM role and policy for Github Actions to deploy via CodeDeploy
# • IAM role and policy for EC2 instances to work with CodeDeploy
# • CloudWatch logging for deployment operations
# • Instance profiles and policy attachments

# Note: See ./.github/workflows/deploy-microservices.yml for deployment details
# =============================================================================

#region Configuration

variable "bucket_suffix" {
  description = "Suffix to ensure unique S3 bucket names across envs"
  type        = string
}

variable "microservices" {
  description = "List of microservices to deploy/build (also used to create ECR repos)"
  type        = list(string)
  default     = []
}

variable "microservices_with_logs" {
  description = "Subset of microservices that should have CloudWatch logs collected via CodeDeploy"
  type        = list(string)
  default     = []
}

variable "github_repository" {
  description = "GitHub repo in 'owner/repo' format for OIDC trust policy"
  type        = string
  default     = ""
}

variable "staging_environment_name" {
  description = "GitHub Actions staging environment name"
  type        = string
  default     = "stage"
}

variable "production_environment_name" {
  description = "GitHub Actions production environment name"
  type        = string
  default     = "prod"
}

#endregion

#region Resources

# S3 bucket for CodeDeploy artifacts (managed by Terraform)
resource "aws_s3_bucket" "codedeploy" {
  bucket = "${var.project_name}-codedeploy-${var.bucket_suffix}"
}

resource "aws_s3_bucket_versioning" "codedeploy" {
  bucket = aws_s3_bucket.codedeploy.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "codedeploy" {
  bucket = aws_s3_bucket.codedeploy.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "codedeploy" {
  bucket                  = aws_s3_bucket.codedeploy.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "codedeploy" {
  bucket = aws_s3_bucket.codedeploy.id

  rule {
    id     = "deployment_cleanup"
    status = "Enabled"
    filter {
      prefix = ""
    }

    noncurrent_version_expiration { noncurrent_days = 30 }
    expiration { days = 90 }
  }
}

resource "aws_s3_bucket" "codedeploy_tags" {
  bucket = aws_s3_bucket.codedeploy.id
  tags = {
    Name        = "${var.project_name}-codedeploy-${var.env}"
    Environment = var.env
  }
}

# CodeDeploy Applications
resource "aws_codedeploy_app" "microservices" {
  for_each = toset(var.microservices)

  name = "${var.project_name}-${each.key}-${var.env}"

  compute_platform = "Server"

  tags = {
    Name        = "${var.project_name}-${each.key}-${var.env}"
    Environment = var.env
    Service     = each.key
  }
}

# CodeDeploy Deployment Groups
resource "aws_codedeploy_deployment_group" "microservices" {
  for_each = toset(var.microservices_with_logs)

  app_name              = aws_codedeploy_app.microservices[each.key].name
  deployment_group_name = "${var.project_name}-${each.key}-${var.env}-deployment-group"
  service_role_arn      = aws_iam_role.codedeploy_service_role.arn

  # Deployment configuration
  deployment_config_name = "CodeDeployDefault.OneAtATime"

  # EC2 instances (using tags to identify instances)
  ec2_tag_set {
    ec2_tag_filter {
      key   = "Environment"
      type  = "KEY_AND_VALUE"
      value = var.env
    }
  }

  # Tag group 2: restrict deployment to manager role instances only
  ec2_tag_set {
    ec2_tag_filter {
      key   = "Role"
      type  = "KEY_AND_VALUE"
      value = "manager"
    }
  }

  tags = {
    Name        = "${var.project_name}-${each.key}-${var.env}-deployment-group"
    Environment = var.env
    Service     = each.key
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "codedeploy_logs" {
  for_each = toset(var.microservices_with_logs)

  name              = "/aws/codedeploy/${var.project_name}-${each.key}-${var.env}"
  retention_in_days = 14

  tags = {
    Name        = "${var.project_name}-${each.key}-codedeploy-logs-${var.env}"
    Environment = var.env
    Service     = each.key
  }
}

#endregion

#region IAM Roles

# CodeDeploy Service Role for Github Actions to deploy microservices
resource "aws_iam_role" "codedeploy_service_role" {
  name = "${var.project_name}-codedeploy-service-role-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-codedeploy-service-role-${var.env}"
    Environment = var.env
  }
}

# GitHub Actions CodeDeploy Role for GitHub Actions to deploy via CodeDeploy
resource "aws_iam_role" "github_actions_codedeploy" {
  name = "${var.project_name}-github-actions-role-codedeploy-${var.env}"

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
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com",
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
    Name        = "${var.project_name}-github-actions-role-codedeploy-${var.env}"
    Environment = var.env
    Purpose     = "GitHub Actions CodeDeploy Deployments"
  }
}

# EC2 CodeDeploy Role for EC2 instances to work with CodeDeploy
resource "aws_iam_role" "ec2_codedeploy_role" {
  name = "${var.project_name}-ec2-codedeploy-role-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-ec2-codedeploy-role-${var.env}"
    Environment = var.env
  }
}

#endregion

#region IAM Policies

# GitHub Actions CodeDeploy Policy for GitHub Actions to deploy via CodeDeploy
resource "aws_iam_policy" "github_actions_codedeploy_policy" {
  name        = "${var.project_name}-github-actions-policy-codedeploy-${var.env}"
  description = "Policy for GitHub Actions to deploy via AWS CodeDeploy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuthorizationToken"
        Effect = "Allow"
        Action = [
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
          "arn:aws:ecr:*:*:repository/${var.project_name}*"
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
          aws_s3_bucket.codedeploy.arn,
          "${aws_s3_bucket.codedeploy.arn}/*"
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
    Name        = "${var.project_name}-github-actions-policy-codedeploy-${var.env}"
    Environment = var.env
    Purpose     = "GitHub Actions CodeDeploy Deployments"
  }
}

# Policy for EC2 instances to work with CodeDeploy
resource "aws_iam_policy" "ec2_codedeploy_policy" {
  name        = "${var.project_name}-ec2-codedeploy-policy-${var.env}"
  description = "Policy for EC2 instances to work with CodeDeploy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:PutObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-codedeploy-${var.bucket_suffix}",
          "arn:aws:s3:::${var.project_name}-codedeploy-${var.bucket_suffix}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-ec2-codedeploy-policy-${var.env}"
    Environment = var.env
  }
}

#endregion

#region IAM Policy Attachments

# CodeDeploy Service Role Policy Attachment
resource "aws_iam_role_policy_attachment" "codedeploy_service_role_policy" {
  role       = aws_iam_role.codedeploy_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

# GitHub Actions CodeDeploy Policy Attachment
resource "aws_iam_role_policy_attachment" "github_actions_codedeploy_policy_attachment" {
  role       = aws_iam_role.github_actions_codedeploy.name
  policy_arn = aws_iam_policy.github_actions_codedeploy_policy.arn
}

# EC2 CodeDeploy Policy Attachment
resource "aws_iam_role_policy_attachment" "ec2_codedeploy_policy_attachment" {
  role       = aws_iam_role.ec2_codedeploy_role.name
  policy_arn = aws_iam_policy.ec2_codedeploy_policy.arn
}

# Manager Instance CodeDeploy Policy Attachment
resource "aws_iam_role_policy_attachment" "manager_codedeploy_policy_attachment" {
  role       = aws_iam_role.manager.name
  policy_arn = aws_iam_policy.ec2_codedeploy_policy.arn
}

# EC2 CodeDeploy Instance Profile
resource "aws_iam_instance_profile" "ec2_codedeploy_profile" {
  name = "${var.project_name}-ec2-codedeploy-profile-${var.env}"
  role = aws_iam_role.ec2_codedeploy_role.name
}

#endregion

#region Outputs

# CodeDeploy S3 Bucket Outputs
output "codedeploy_bucket_name" {
  value       = "${var.project_name}-codedeploy-${var.bucket_suffix}"
  description = "Name of the S3 bucket for CodeDeploy deployment artifacts"
}

output "codedeploy_bucket_arn" {
  value       = "arn:aws:s3:::${var.project_name}-codedeploy-${var.bucket_suffix}"
  description = "ARN of the S3 bucket for CodeDeploy deployment artifacts"
}

# GitHub Actions CodeDeploy Role Output
output "github_actions_codedeploy_role_arn" {
  description = "ARN of the GitHub Actions CodeDeploy deployment role"
  value       = aws_iam_role.github_actions_codedeploy.arn
}

#endregion 