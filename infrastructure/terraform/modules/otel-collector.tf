# =============================================================================
# OpenTelemetry Collector Infrastructure
# =============================================================================
# This file manages OpenTelemetry Collector infrastructure components:
# 
# • IAM roles and policies for OpenTelemetry Collector
# • CloudWatch logging permissions
# • X-Ray tracing permissions
# • Instance profile for collector deployment
# • Policy attachments to existing compute roles
# 
# The OpenTelemetry Collector handles:
# - Metrics collection and forwarding to CloudWatch
# - Distributed tracing via AWS X-Ray
# - Log aggregation and forwarding
# - Telemetry data processing and filtering
# =============================================================================

#region IAM Roles

# IAM Role for OpenTelemetry Collector
resource "aws_iam_role" "otel_collector_role" {
  name = "${var.project_name}-otel-collector-role"

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
    Name        = "${var.project_name}-otel-collector-role"
    Environment = var.environment
    Purpose     = "OpenTelemetry Collector IAM Role"
  }
}

# Instance profile for OpenTelemetry Collector
resource "aws_iam_instance_profile" "otel_collector_instance_profile" {
  name = "${var.project_name}-otel-collector-instance-profile"
  role = aws_iam_role.otel_collector_role.name

  tags = {
    Name        = "${var.project_name}-otel-collector-instance-profile"
    Environment = var.environment
    Purpose     = "OpenTelemetry Collector Instance Profile"
  }
}

#endregion

#region IAM Policies

# IAM Policy for OpenTelemetry Collector CloudWatch Access
resource "aws_iam_policy" "otel_collector_cloudwatch_policy" {
  name        = "${var.project_name}-otel-collector-cloudwatch-policy"
  description = "Policy for OpenTelemetry Collector to create and write to CloudWatch log groups"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:*:*:log-group:/aws/otel/*",
          "arn:aws:logs:*:*:log-group:/aws/otel/*:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "${var.project_name}/OpenTelemetry"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-otel-collector-cloudwatch-policy"
    Environment = var.environment
    Purpose     = "OpenTelemetry CloudWatch Permissions"
  }
}

# IAM Policy for OpenTelemetry Collector X-Ray Access
resource "aws_iam_policy" "otel_collector_xray_policy" {
  name        = "${var.project_name}-otel-collector-xray-policy"
  description = "Policy for OpenTelemetry Collector to write to X-Ray"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-otel-collector-xray-policy"
    Environment = var.environment
    Purpose     = "OpenTelemetry X-Ray Permissions"
  }
}

#endregion

#region IAM Policy Attachments

# Attach CloudWatch policy to collector role
resource "aws_iam_role_policy_attachment" "otel_collector_cloudwatch_attachment" {
  role       = aws_iam_role.otel_collector_role.name
  policy_arn = aws_iam_policy.otel_collector_cloudwatch_policy.arn
}

# Attach X-Ray policy to collector role
resource "aws_iam_role_policy_attachment" "otel_collector_xray_attachment" {
  role       = aws_iam_role.otel_collector_role.name
  policy_arn = aws_iam_policy.otel_collector_xray_policy.arn
}

# Attach OpenTelemetry permissions to existing compute roles
resource "aws_iam_role_policy_attachment" "worker_otel_cloudwatch_attachment" {
  role       = aws_iam_role.worker.name
  policy_arn = aws_iam_policy.otel_collector_cloudwatch_policy.arn
}

resource "aws_iam_role_policy_attachment" "worker_otel_xray_attachment" {
  role       = aws_iam_role.worker.name
  policy_arn = aws_iam_policy.otel_collector_xray_policy.arn
}

resource "aws_iam_role_policy_attachment" "manager_otel_cloudwatch_attachment" {
  role       = aws_iam_role.manager.name
  policy_arn = aws_iam_policy.otel_collector_cloudwatch_policy.arn
}

resource "aws_iam_role_policy_attachment" "manager_otel_xray_attachment" {
  role       = aws_iam_role.manager.name
  policy_arn = aws_iam_policy.otel_collector_xray_policy.arn
}

#endregion

#region Outputs

# IAM Role outputs
output "otel_collector_role_arn" {
  description = "ARN of the OpenTelemetry Collector IAM role"
  value       = aws_iam_role.otel_collector_role.arn
}

output "otel_collector_instance_profile_name" {
  description = "Name of the OpenTelemetry Collector instance profile"
  value       = aws_iam_instance_profile.otel_collector_instance_profile.name
}

# Policy outputs
output "otel_collector_cloudwatch_policy_arn" {
  description = "ARN of the OpenTelemetry CloudWatch policy"
  value       = aws_iam_policy.otel_collector_cloudwatch_policy.arn
}

output "otel_collector_xray_policy_arn" {
  description = "ARN of the OpenTelemetry X-Ray policy"
  value       = aws_iam_policy.otel_collector_xray_policy.arn
}

#endregion