# CodeDeploy Application and Deployment Groups for Microservices

# CodeDeploy Application
resource "aws_codedeploy_app" "microservices" {
  for_each = toset(["authentication", "envoy"]) # Added envoy microservice

  name = "${var.app_name}-${each.key}-${var.environment}"

  compute_platform = "Server"

  tags = {
    Name        = "${var.app_name}-${each.key}-${var.environment}"
    Environment = var.environment
    Service     = each.key
  }
}

# CodeDeploy Deployment Group
resource "aws_codedeploy_deployment_group" "microservices" {
  for_each = toset(["authentication", "envoy"]) # Added envoy microservice

  app_name              = aws_codedeploy_app.microservices[each.key].name
  deployment_group_name = "${var.app_name}-${each.key}-${var.environment}-deployment-group"
  service_role_arn      = aws_iam_role.codedeploy_service_role.arn

  # Deployment configuration
  deployment_config_name = "CodeDeployDefault.OneAtATime"

  # EC2 instances (using tags to identify instances)
  ec2_tag_set {
    ec2_tag_filter {
      key   = "Environment"
      type  = "KEY_AND_VALUE"
      value = var.environment
    }
  }

  # Tag group 2: restrict deployment to manager/private tier instances only
  ec2_tag_set {
    ec2_tag_filter {
      key   = "Tier"
      type  = "KEY_AND_VALUE"
      value = "private"
    }
  }

  tags = {
    Name        = "${var.app_name}-${each.key}-${var.environment}-deployment-group"
    Environment = var.environment
    Service     = each.key
  }
}

# IAM Role for CodeDeploy Service
resource "aws_iam_role" "codedeploy_service_role" {
  name = "${var.app_name}-codedeploy-service-role"

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
    Name        = "${var.app_name}-codedeploy-service-role"
    Environment = var.environment
  }
}

# Attach CodeDeploy service role policy
resource "aws_iam_role_policy_attachment" "codedeploy_service_role_policy" {
  role       = aws_iam_role.codedeploy_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

# IAM Role for EC2 instances to work with CodeDeploy
resource "aws_iam_role" "ec2_codedeploy_role" {
  name = "${var.app_name}-ec2-codedeploy-role"

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
    Name        = "${var.app_name}-ec2-codedeploy-role"
    Environment = var.environment
  }
}

# Policy for EC2 instances to work with CodeDeploy
resource "aws_iam_policy" "ec2_codedeploy_policy" {
  name        = "${var.app_name}-ec2-codedeploy-policy"
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
          "arn:aws:s3:::${var.app_name}-codedeploy-${var.bucket_suffix}",
          "arn:aws:s3:::${var.app_name}-codedeploy-${var.bucket_suffix}/*"
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
    Name        = "${var.app_name}-ec2-codedeploy-policy"
    Environment = var.environment
  }
}

# Attach policy to EC2 CodeDeploy role
resource "aws_iam_role_policy_attachment" "ec2_codedeploy_policy_attachment" {
  role       = aws_iam_role.ec2_codedeploy_role.name
  policy_arn = aws_iam_policy.ec2_codedeploy_policy.arn
}

# Attach same CodeDeploy policy to the manager (private) instance role
resource "aws_iam_role_policy_attachment" "private_instance_codedeploy_policy_attachment" {
  role       = aws_iam_role.private_instance_role.name
  policy_arn = aws_iam_policy.ec2_codedeploy_policy.arn
}

# Instance profile for EC2 CodeDeploy role
resource "aws_iam_instance_profile" "ec2_codedeploy_profile" {
  name = "${var.app_name}-ec2-codedeploy-profile"
  role = aws_iam_role.ec2_codedeploy_role.name
}

# CloudWatch Log Group for CodeDeploy
resource "aws_cloudwatch_log_group" "codedeploy_logs" {
  for_each = toset(["authentication", "envoy"]) # Added envoy microservice

  name              = "/aws/codedeploy/${var.app_name}-${each.key}-${var.environment}"
  retention_in_days = 14

  tags = {
    Name        = "${var.app_name}-${each.key}-codedeploy-logs"
    Environment = var.environment
    Service     = each.key
  }
}

########################
# CodeDeploy S3 Bucket - Managed by Setup Script
########################

# The CodeDeploy S3 bucket is created and configured by the infrastructure setup script.
# This file contains only the IAM policies and outputs that reference the bucket.
# The bucket name follows the pattern: ${var.app_name}-codedeploy-${var.bucket_suffix}

########################
# Outputs
########################

output "codedeploy_bucket_name" {
  value       = "${var.app_name}-codedeploy-${var.bucket_suffix}"
  description = "Name of the S3 bucket for CodeDeploy deployment artifacts"
}

output "codedeploy_bucket_arn" {
  value       = "arn:aws:s3:::${var.app_name}-codedeploy-${var.bucket_suffix}"
  description = "ARN of the S3 bucket for CodeDeploy deployment artifacts"
} 