resource "aws_iam_policy" "otel_permissions" {
  name        = "${var.project_name}-${var.env}-otel"
  description = "Permissions for OTEL to push logs/metrics/traces"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "logs:DescribeLogGroups"], Resource = "arn:aws:logs:*:*:*" },
      { Effect = "Allow", Action = ["cloudwatch:PutMetricData"], Resource = "*" },
      { Effect = "Allow", Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"], Resource = "*" }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "otel_to_ec2" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.otel_permissions.arn
}



