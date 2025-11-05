# =============================================================================
# CI/CD Infrastructure (ECR Repos, CodeDeploy, IAM)
# =============================================================================
#
# This module provisions:
# • ECR repositories and lifecycle policies for microservices
# • CodeDeploy apps, deployment groups, and CloudWatch log groups
# • IAM roles/policies and attachments for CodeDeploy and GitHub Actions
# • Instance profile for CodeDeploy on EC2
# =============================================================================

#region ECR Repositories (from container-registry.tf)

resource "aws_ecr_repository" "microservices" {
  for_each = toset(var.microservices_with_container_repos)

  name                 = "${var.project_name}/${each.key}-${var.env}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = var.env
    Service     = each.key
  }
}

resource "aws_ecr_lifecycle_policy" "microservices" {
  for_each   = aws_ecr_repository.microservices
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = ["v"]
        countType     = "imageCountMoreThan"
        countNumber   = 10
      }
      action = { type = "expire" }
    }]
  })
}

#endregion

# =============================================================================
# AWS CodeDeploy Infrastructure
# =============================================================================
# This file manages all infrastructure components required for AWS CodeDeploy:
#
# • CodeDeploy applications and deployment groups for microservices
# • S3 bucket reference for deployment artifacts
# • IAM role and policy for Github Actions to deploy via CodeDeploy
# • IAM role and policy for EC2 instances to work with CodeDeploy
# • CloudWatch logging for deployment operations
# • Instance profiles and policy attachments

# Note: See ./.github/workflows/deploy-microservices.yml for deployment details
# =============================================================================

#region CodeDeploy

# CodeDeploy Applications
resource "aws_codedeploy_app" "microservices" {
  for_each = toset(var.microservices)

  name = "${var.project_name}-${each.key}-${var.env}"

  compute_platform = "Server"

  tags = {
    Environment = var.env
    Service     = each.key
  }
}

# CodeDeploy Deployment Groups
resource "aws_codedeploy_deployment_group" "microservices" {
  for_each = toset(var.microservices)

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

  # Tag group 3: restrict deployment to deployment-manager instances only
  ec2_tag_set {
    ec2_tag_filter {
      key   = "DeploymentManager"
      type  = "KEY_AND_VALUE"
      value = "true"
    }
  }

  tags = {
    Environment = var.env
    Service     = each.key
  }
}

#endregion

#region IAM Roles and Policies (from deploy-microservices.tf)

# CodeDeploy Service Role for AWS CodeDeploy service
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
    Environment = var.env
  }
}

# GitHub Actions CodeDeploy Role (OIDC)
resource "aws_iam_role" "github_actions_codedeploy" {
  name = "${var.project_name}-github-actions-codedeploy-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"
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
    Environment = var.env
    Purpose     = "GitHub Actions CodeDeploy Deployments"
  }
}

# EC2 CodeDeploy Role for instances
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
    Environment = var.env
  }
}

# GitHub Actions CodeDeploy Policy
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
          "arn:aws:s3:::${var.codedeploy_bucket_name}",
          "arn:aws:s3:::${var.codedeploy_bucket_name}/*"
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
          "arn:aws:s3:::${var.codedeploy_bucket_name}",
          "arn:aws:s3:::${var.codedeploy_bucket_name}/*"
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
    Environment = var.env
  }
}

# Policy Attachments
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

resource "aws_iam_role_policy_attachment" "manager_codedeploy_policy_attachment" {
  role       = var.manager_role_name
  policy_arn = aws_iam_policy.ec2_codedeploy_policy.arn
}

#endregion
