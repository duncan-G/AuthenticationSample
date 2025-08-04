########################
# Route53 DNS Configuration
########################

# Local value to reference the hosted zone (data source defined in certificates.tf)
locals {
  hosted_zone_id   = data.aws_route53_zone.existing.zone_id
  hosted_zone_name = data.aws_route53_zone.existing.name
}

# A record for the main domain pointing to the first public worker instance
resource "aws_route53_record" "main_domain" {
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = "300"

  records = [aws_instance.public_workers[0].public_ip]
}

# AAAA record for the main domain pointing to the first public worker instance (IPv6)
resource "aws_route53_record" "main_domain_ipv6" {
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "AAAA"
  ttl     = "300"

  records = aws_instance.public_workers[0].ipv6_addresses
}

# A records for each subdomain pointing to the first public worker instance
resource "aws_route53_record" "subdomains" {
  for_each = toset(var.subdomains)

  zone_id = local.hosted_zone_id
  name    = "${each.value}.${var.domain_name}"
  type    = "A"
  ttl     = "300"

  records = [aws_instance.public_workers[0].public_ip]
}

# AAAA records for each subdomain pointing to the first public worker instance (IPv6)
resource "aws_route53_record" "subdomains_ipv6" {
  for_each = toset(var.subdomains)

  zone_id = local.hosted_zone_id
  name    = "${each.value}.${var.domain_name}"
  type    = "AAAA"
  ttl     = "300"

  records = aws_instance.public_workers[0].ipv6_addresses
}

# CNAME record for www subdomain (optional)
resource "aws_route53_record" "www_subdomain" {
  zone_id = local.hosted_zone_id
  name    = "www.${var.domain_name}"
  type    = "CNAME"
  ttl     = "300"

  records = [var.domain_name]
}

resource "aws_route53_record" "spf" {
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = "300"

  records = [
    "v=spf1 include:_spf.google.com ~all"
  ]
}

# Outputs
output "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  value       = local.hosted_zone_id
}

output "hosted_zone_name" {
  description = "Route53 hosted zone name"
  value       = local.hosted_zone_name
}

output "main_domain_url" {
  description = "Main domain URL"
  value       = "https://${var.domain_name}"
}

output "subdomain_urls" {
  description = "Subdomain URLs"
  value       = [for subdomain in var.subdomains : "https://${subdomain}.${var.domain_name}"]
} 