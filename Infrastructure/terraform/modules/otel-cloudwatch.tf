########################
# IAM Resources for OpenTelemetry
########################



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
    Purpose     = "OpenTelemetry Collector IAM Role"
  }
}

# IAM Policy for OpenTelemetry Collector CloudWatch Access
resource "aws_iam_policy" "otel_collector_cloudwatch_policy" {
  name        = "${var.app_name}-otel-collector-cloudwatch-policy"
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
            "cloudwatch:namespace" = "${var.app_name}/OpenTelemetry"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-otel-collector-cloudwatch-policy"
    Environment = var.environment
    Purpose     = "OpenTelemetry CloudWatch Permissions"
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
    Purpose     = "OpenTelemetry X-Ray Permissions"
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
    Purpose     = "OpenTelemetry Collector Instance Profile"
  }
}

# Update the existing private instance role to include OpenTelemetry permissions
resource "aws_iam_role_policy_attachment" "private_instance_otel_cloudwatch_attachment" {
  role       = aws_iam_role.private.name
  policy_arn = aws_iam_policy.otel_collector_cloudwatch_policy.arn
}

resource "aws_iam_role_policy_attachment" "private_instance_otel_xray_attachment" {
  role       = aws_iam_role.private.name
  policy_arn = aws_iam_policy.otel_collector_xray_policy.arn
} 
} 