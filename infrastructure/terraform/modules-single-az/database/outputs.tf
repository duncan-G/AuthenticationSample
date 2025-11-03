output "refresh_tokens_table_name" {
  description = "Name of the DynamoDB table for refresh tokens"
  value       = aws_dynamodb_table.refresh_tokens.name
}

output "refresh_tokens_table_arn" {
  description = "ARN of the DynamoDB table for refresh tokens"
  value       = aws_dynamodb_table.refresh_tokens.arn
}

output "swarm_cluster_lock_table_name" {
  description = "Name of the DynamoDB table for swarm cluster lock"
  value       = aws_dynamodb_table.swarm_cluster_lock.name
}

output "swarm_cluster_lock_table_arn" {
  description = "ARN of the DynamoDB table for swarm cluster lock"
  value       = aws_dynamodb_table.swarm_cluster_lock.arn
}
