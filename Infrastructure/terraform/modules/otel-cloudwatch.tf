########################
# CloudWatch Resources for OpenTelemetry
########################

# CloudWatch Log Group for OpenTelemetry Application Logs
resource "aws_cloudwatch_log_group" "otel_application_logs" {
  name              = "/aws/otel/application-logs"
  retention_in_days = 30

  tags = {
    Name        = "${var.app_name}-otel-application-logs"
    Environment = var.environment
  }
}

# CloudWatch Log Group for OpenTelemetry Collector Logs
resource "aws_cloudwatch_log_group" "otel_collector_logs" {
  name              = "/aws/otel/collector"
  retention_in_days = 14

  tags = {
    Name        = "${var.app_name}-otel-collector-logs"
    Environment = var.environment
  }
}

# IAM Role for OpenTelemetry Collector
resource "aws_iam_role" "otel_collector_role" {
  name = "${var.app_name}-otel-collector-role"

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
    Name        = "${var.app_name}-otel-collector-role"
    Environment = var.environment
  }
}

# IAM Policy for OpenTelemetry Collector CloudWatch Access
resource "aws_iam_policy" "otel_collector_cloudwatch_policy" {
  name        = "${var.app_name}-otel-collector-cloudwatch-policy"
  description = "Policy for OpenTelemetry Collector to write to CloudWatch"

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
          aws_cloudwatch_log_group.otel_application_logs.arn,
          "${aws_cloudwatch_log_group.otel_application_logs.arn}:*",
          aws_cloudwatch_log_group.otel_collector_logs.arn,
          "${aws_cloudwatch_log_group.otel_collector_logs.arn}:*"
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
            "cloudwatch:namespace" = "AuthenticationSample/OpenTelemetry"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-otel-collector-cloudwatch-policy"
    Environment = var.environment
  }
}

# IAM Policy for OpenTelemetry Collector X-Ray Access
resource "aws_iam_policy" "otel_collector_xray_policy" {
  name        = "${var.app_name}-otel-collector-xray-policy"
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
    Name        = "${var.app_name}-otel-collector-xray-policy"
    Environment = var.environment
  }
}

# Attach CloudWatch policy to role
resource "aws_iam_role_policy_attachment" "otel_collector_cloudwatch_attachment" {
  role       = aws_iam_role.otel_collector_role.name
  policy_arn = aws_iam_policy.otel_collector_cloudwatch_policy.arn
}

# Attach X-Ray policy to role
resource "aws_iam_role_policy_attachment" "otel_collector_xray_attachment" {
  role       = aws_iam_role.otel_collector_role.name
  policy_arn = aws_iam_policy.otel_collector_xray_policy.arn
}

# Instance profile for OpenTelemetry Collector
resource "aws_iam_instance_profile" "otel_collector_instance_profile" {
  name = "${var.app_name}-otel-collector-instance-profile"
  role = aws_iam_role.otel_collector_role.name

  tags = {
    Name        = "${var.app_name}-otel-collector-instance-profile"
    Environment = var.environment
  }
}

# Update the existing instance profile to include OpenTelemetry permissions
resource "aws_iam_role_policy_attachment" "private_instance_otel_cloudwatch_attachment" {
  role       = aws_iam_role.private_instance_role.name
  policy_arn = aws_iam_policy.otel_collector_cloudwatch_policy.arn
}

resource "aws_iam_role_policy_attachment" "private_instance_otel_xray_attachment" {
  role       = aws_iam_role.private_instance_role.name
  policy_arn = aws_iam_policy.otel_collector_xray_policy.arn
} 