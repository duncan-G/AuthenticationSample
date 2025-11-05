###############################
# AWS CodeDeploy (Multi-AZ)
###############################

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

variable "microservices_with_container_repos" {
  description = "Subset of microservices that should have container repositories created in ECR"
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

# Name of existing S3 bucket for CodeDeploy artifacts
variable "codedeploy_bucket_name" {
  description = "Name of the pre-existing S3 bucket used for CodeDeploy artifacts"
  type        = string
}

# Needed for trust policy
data "aws_caller_identity" "current" {}

#endregion

#region Resources

# CodeDeploy Applications
resource "aws_codedeploy_app" "microservices" {
  for_each = toset(var.microservices)

  name             = "${var.project_name}-${each.key}-${var.env}"
  compute_platform = "Server"

  tags = {
    Environment = var.env
    Service     = each.key
  }
}

#region IAM Roles

# CodeDeploy Service Role
resource "aws_iam_role" "codedeploy_service_role" {
  name = "${var.project_name}-codedeploy-service-role-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.env
  }
}

# GitHub Actions CodeDeploy Role
resource "aws_iam_role" "github_actions_codedeploy" {
  name = "${var.project_name}-github-actions-role-codedeploy-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity",
        Effect = "Allow",
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
        },
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
    Environment = var.env
    Purpose     = "GitHub Actions CodeDeploy Deployments"
  }
}

# EC2 CodeDeploy Role
resource "aws_iam_role" "ec2_codedeploy_role" {
  name = "${var.project_name}-ec2-codedeploy-role-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.env
  }
}

#endregion

#region IAM Policies

# GitHub Actions CodeDeploy Policy
resource "aws_iam_policy" "github_actions_codedeploy_policy" {
  name        = "${var.project_name}-github-actions-policy-codedeploy-${var.env}"
  description = "Policy for GitHub Actions to deploy via AWS CodeDeploy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "ECRAuthorizationToken",
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken"
        ],
        Resource = "*"
      },
      {
        Sid    = "ECRRepositoryAccess",
        Effect = "Allow",
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ],
        Resource = [
          "arn:aws:ecr:*:*:repository/${var.project_name}*"
        ]
      },
      {
        Sid    = "S3DeploymentBucketAccess",
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::${var.codedeploy_bucket_name}",
          "arn:aws:s3:::${var.codedeploy_bucket_name}/*"
        ]
      },
      {
        Sid    = "CodeDeployAccess",
        Effect = "Allow",
        Action = [
          "codedeploy:*"
        ],
        Resource = "*"
      },
      {
        Sid    = "STSAssumeRole",
        Effect = "Allow",
        Action = [
          "sts:GetCallerIdentity"
        ],
        Resource = "*"
      }
    ]
  })

  tags = {
    Environment = var.env
    Purpose     = "GitHub Actions CodeDeploy Deployments"
  }
}

# Policy for EC2 instances to work with CodeDeploy
resource "aws_iam_policy" "ec2_codedeploy_policy" {
  name        = "${var.project_name}-ec2-codedeploy-policy-${var.env}"
  description = "Policy for EC2 instances to work with CodeDeploy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:PutObject"
        ],
        Resource = [
          "arn:aws:s3:::${var.codedeploy_bucket_name}",
          "arn:aws:s3:::${var.codedeploy_bucket_name}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })

  tags = {
    Environment = var.env
  }
}

#endregion

#region IAM Policy Attachments

resource "aws_iam_role_policy_attachment" "codedeploy_service_role_policy" {
  role       = aws_iam_role.codedeploy_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

resource "aws_iam_role_policy_attachment" "github_actions_codedeploy_policy_attachment" {
  role       = aws_iam_role.github_actions_codedeploy.name
  policy_arn = aws_iam_policy.github_actions_codedeploy_policy.arn
}

resource "aws_iam_role_policy_attachment" "ec2_codedeploy_policy_attachment" {
  role       = aws_iam_role.ec2_codedeploy_role.name
  policy_arn = aws_iam_policy.ec2_codedeploy_policy.arn
}

# Attach the policy to the compute EC2 role defined in this module
resource "aws_iam_role_policy_attachment" "compute_ec2_codedeploy_policy_attachment" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.ec2_codedeploy_policy.arn
}

# Optional instance profile for dedicated CodeDeploy EC2 role
resource "aws_iam_instance_profile" "ec2_codedeploy_profile" {
  name = "${var.project_name}-ec2-codedeploy-profile-${var.env}"
  role = aws_iam_role.ec2_codedeploy_role.name
}

#endregion

#region Outputs

output "github_actions_codedeploy_role_arn" {
  description = "ARN of the GitHub Actions CodeDeploy deployment role"
  value       = aws_iam_role.github_actions_codedeploy.arn
}

output "codedeploy_bucket_name" {
  description = "Name of the S3 bucket for CodeDeploy deployment artifacts"
  value       = var.codedeploy_bucket_name
}

output "codedeploy_bucket_arn" {
  description = "ARN of the S3 bucket for CodeDeploy deployment artifacts"
  value       = "arn:aws:s3:::${var.codedeploy_bucket_name}"
}

#endregion


