# CodeDeploy S3 Bucket Outputs
output "codedeploy_bucket_name" {
  value       = "${var.project_name}-codedeploy-${var.bucket_suffix}"
  description = "Name of the S3 bucket for CodeDeploy deployment artifacts"
}

output "codedeploy_bucket_arn" {
  value       = "arn:aws:s3:::${var.project_name}-codedeploy-${var.bucket_suffix}"
  description = "ARN of the S3 bucket for CodeDeploy deployment artifacts"
}

# GitHub Actions CodeDeploy Role Output
output "github_actions_codedeploy_role_arn" {
  description = "ARN of the GitHub Actions CodeDeploy deployment role"
  value       = aws_iam_role.github_actions_codedeploy.arn
}
