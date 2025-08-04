# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "public_worker_ips" {
  value       = aws_instance.public_workers[*].public_ip
  description = "Public IPv4 addresses of public worker nodes"
}

output "public_worker_ipv6" {
  value       = aws_instance.public_workers[*].ipv6_addresses
  description = "Public IPv6 addresses of public worker nodes"
}

output "private_worker_ips" {
  value       = aws_instance.private_workers[*].private_ip
  description = "Private IPv4 addresses of private worker nodes"
}

output "manager_ips" {
  value       = aws_instance.managers[*].private_ip
  description = "Private IPv4 addresses of manager nodes"
}

# --- Cognito (placeholder – module expected elsewhere) ---
# output "cognito_user_pool_id"         { value = module.cognito.user_pool_id }
# output "cognito_user_pool_arn"        { value = module.cognito.user_pool_arn }
# output "cognito_user_pool_client_id"  { value = module.cognito.web_client_id }
# output "cognito_backend_client_id"    { value = module.cognito.backend_client_id }
# output "cognito_identity_pool_id"     { value = module.cognito.identity_pool_id }
# output "cognito_auth_url"             { value = module.cognito.auth_url }
# output "cognito_user_pool_domain"     { value = module.cognito.domain }
