# CodeDeploy Application and Deployment Groups for Microservices

# CodeDeploy Application
resource "aws_codedeploy_app" "microservices" {
  for_each = toset(["authentication"])  # Add more services as needed
  
  name = "${each.key}-${var.environment}"
  
  compute_platform = "Server"
  
  tags = {
    Name        = "${var.app_name}-${each.key}-${var.environment}"
    Environment = var.environment
    Service     = each.key
  }
}

# CodeDeploy Deployment Group
resource "aws_codedeploy_deployment_group" "microservices" {
  for_each = toset(["authentication"])  # Add more services as needed
  
  app_name               = aws_codedeploy_app.microservices[each.key].name
  deployment_group_name  = "${each.key}-${var.environment}-deployment-group"
  service_role_arn       = aws_iam_role.codedeploy_service_role.arn
  
  # Deployment configuration
  deployment_config_name = "CodeDeployDefault.OneAtATime"
  
  # Auto Scaling groups (if using ASG)
  # autoscaling_groups = [aws_autoscaling_group.microservice.name]
  
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
  
  # Load balancer configuration (if using ALB)
  # load_balancer_info {
  #   target_group_info {
  #     name = aws_lb_target_group.microservice.name
  #   }
  # }
  
  # Blue/Green deployment configuration
  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
    
    green_fleet_provisioning_option {
      action = "COPY_AUTO_SCALING_GROUP"
    }
    
    terminate_blue_instances_on_deployment_success {
      action = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }
  
  # Auto rollback configuration
  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }
  
  # Alarm configuration
  alarm_configuration {
    enabled = true
    alarms  = ["${var.app_name}-${each.key}-deployment-alarm"]
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
          "arn:aws:s3:::${var.deployment_bucket}",
          "arn:aws:s3:::${var.deployment_bucket}/*"
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

# S3 Bucket for deployment artifacts
resource "aws_s3_bucket" "deployment_bucket" {
  bucket = "${var.app_name}-deployment-${var.environment}-${random_string.bucket_suffix.result}"
  
  tags = {
    Name        = "${var.app_name}-deployment-bucket"
    Environment = var.environment
  }
}

# Random string for bucket name uniqueness
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "deployment_bucket_versioning" {
  bucket = aws_s3_bucket.deployment_bucket.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "deployment_bucket_encryption" {
  bucket = aws_s3_bucket.deployment_bucket.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket lifecycle policy
resource "aws_s3_bucket_lifecycle_configuration" "deployment_bucket_lifecycle" {
  bucket = aws_s3_bucket.deployment_bucket.id
  
  rule {
    id     = "cleanup_old_deployments"
    status = "Enabled"
    
    expiration {
      days = 30
    }
    
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# CloudWatch Log Group for CodeDeploy
resource "aws_cloudwatch_log_group" "codedeploy_logs" {
  for_each = toset(["authentication"])  # Add more services as needed
  
  name              = "/aws/codedeploy/${each.key}-${var.environment}"
  retention_in_days = 14
  
  tags = {
    Name        = "${var.app_name}-${each.key}-codedeploy-logs"
    Environment = var.environment
    Service     = each.key
  }
}

# CloudWatch Alarm for deployment failures
resource "aws_cloudwatch_metric_alarm" "deployment_failure" {
  for_each = toset(["authentication"])  # Add more services as needed
  
  alarm_name          = "${var.app_name}-${each.key}-deployment-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FailedDeployments"
  namespace           = "AWS/CodeDeploy"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors deployment failures for ${each.key}"
  
  dimensions = {
    ApplicationName = aws_codedeploy_app.microservices[each.key].name
    DeploymentGroupName = aws_codedeploy_deployment_group.microservices[each.key].deployment_group_name
  }
  
  tags = {
    Name        = "${var.app_name}-${each.key}-deployment-alarm"
    Environment = var.environment
    Service     = each.key
  }
} 