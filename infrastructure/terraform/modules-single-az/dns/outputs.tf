output "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  value       = local.hosted_zone_id
}

output "hosted_zone_name" {
  description = "Route53 hosted zone name"
  value       = local.hosted_zone_name
}

# Domain URL outputs
output "main_domain_url" {
  description = "Main domain URL"
  value       = "https://${var.domain_name}"
}

output "api_domain_url" {
  description = "API subdomain URL"
  value       = "https://${var.api_subdomain}.${var.domain_name}"
}

output "auth_domain_url" {
  description = "Auth subdomain URL"
  value       = "https://${var.auth_subdomain}.${var.domain_name}"
}
