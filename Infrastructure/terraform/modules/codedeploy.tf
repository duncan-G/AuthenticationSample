# CodeDeploy Application and Deployment Groups for Microservices

# CodeDeploy Application
resource "aws_codedeploy_app" "microservices" {
  for_each = toset(["authentication"]) # Add more services as needed

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
  for_each = toset(["authentication"]) # Add more services as needed

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

    ec2_tag_filter {
      key   = "Service"
      type  = "KEY_AND_VALUE"
      value = each.key
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
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.codedeploy.arn,
          "${aws_s3_bucket.codedeploy.arn}/*"
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

# Instance profile for EC2 CodeDeploy role
resource "aws_iam_instance_profile" "ec2_codedeploy_profile" {
  name = "${var.app_name}-ec2-codedeploy-profile"
  role = aws_iam_role.ec2_codedeploy_role.name
}

# CloudWatch Log Group for CodeDeploy
resource "aws_cloudwatch_log_group" "codedeploy_logs" {
  for_each = toset(["authentication"]) # Add more services as needed

  name              = "/aws/codedeploy/${var.app_name}-${each.key}-${var.environment}"
  retention_in_days = 14

  tags = {
    Name        = "${var.app_name}-${each.key}-codedeploy-logs"
    Environment = var.environment
    Service     = each.key
  }
}

########################
# CodeDeploy S3 Bucket
########################

# S3 bucket for CodeDeploy deployment artifacts
resource "aws_s3_bucket" "codedeploy" {
  bucket = "${var.app_name}-codedeploy-${var.bucket_suffix}"

  tags = {
    Name        = "${var.app_name}-codedeploy-bucket"
    Environment = var.environment
  }

  lifecycle {
    prevent_destroy = true
  }
}

# S3 bucket versioning for deployment history
resource "aws_s3_bucket_versioning" "codedeploy" {
  bucket = aws_s3_bucket.codedeploy.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "codedeploy" {
  bucket = aws_s3_bucket.codedeploy.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "codedeploy" {
  bucket = aws_s3_bucket.codedeploy.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle policy for deployment artifacts cleanup
resource "aws_s3_bucket_lifecycle_configuration" "codedeploy" {
  bucket = aws_s3_bucket.codedeploy.id

  rule {
    id     = "deployment_cleanup"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    expiration {
      days = 90
    }
  }
}

########################
# Outputs
########################

output "codedeploy_bucket_name" {
  value       = aws_s3_bucket.codedeploy.bucket
  description = "Name of the S3 bucket for CodeDeploy deployment artifacts"
}

output "codedeploy_bucket_arn" {
  value       = aws_s3_bucket.codedeploy.arn
  description = "ARN of the S3 bucket for CodeDeploy deployment artifacts"
} 