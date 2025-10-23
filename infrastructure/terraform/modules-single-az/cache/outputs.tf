output "cache_instance_id" {
  description = "ID of the cache EC2 instance"
  value       = aws_instance.cache_worker.id
}

output "cache_instance_arn" {
  description = "ARN of the cache EC2 instance"
  value       = aws_instance.cache_worker.arn
}

output "cache_instance_private_ip" {
  description = "Private IP address of the cache EC2 instance"
  value       = aws_instance.cache_worker.private_ip
}

output "cache_instance_public_ip" {
  description = "Public IP address of the cache EC2 instance"
  value       = aws_instance.cache_worker.public_ip
}

output "cache_instance_volume_id" {
  description = "ID of the EBS volume attached to the cache instance"
  value       = aws_ebs_volume.cache_instance.id
}

output "cache_instance_volume_attachment_id" {
  description = "ID of the volume attachment for the cache instance"
  value       = aws_volume_attachment.cache_worker_volume.id
}

