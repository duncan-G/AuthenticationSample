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
