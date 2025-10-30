output "worker_target_group_arn" {
  description = "ARN of the worker target group"
  value       = aws_lb_target_group.workers.arn
}

output "workers_asg_name" {
  description = "Name of the workers Auto Scaling Group"
  value       = aws_autoscaling_group.workers.name
}

output "managers_asg_name" {
  description = "Name of the managers Auto Scaling Group"
  value       = aws_autoscaling_group.managers.name
}

output "worker_iam_instance_profile_name" {
  description = "IAM instance profile name for worker nodes"
  value       = aws_iam_instance_profile.worker.name
}

output "manager_iam_instance_profile_name" {
  description = "IAM instance profile name for manager nodes"
  value       = aws_iam_instance_profile.manager.name
}

output "manager_role_name" {
  description = "Name of the IAM role for manager nodes"
  value       = aws_iam_role.manager.name
}

output "worker_role_name" {
  description = "Name of the IAM role for worker nodes"
  value       = aws_iam_role.worker.name
}
