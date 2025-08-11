# =============================================================================
# Route 53 DNS — Public Records Infrastructure
# =============================================================================
# This file manages Route 53 DNS records needed by the platform.
#
# What this module publishes:
# • A/AAAA ALIAS records for each host in `public_subdomains`, pointing to the NLB/ALB (`aws_lb.main`)
# • A TXT SPF record at the apex for outbound email
#
# What this module intentionally does NOT publish:
# • No apex (root) A/AAAA records
# • No `www` record
# • No internal/staging hostnames or direct IPs
#
# Operational notes:
# • Let’s Encrypt DNS-01 works via IAM updates to the `_acme-challenge.*` TXT records
# • IPv6 is assumed; if your load balancer isn’t dual-stack, disable AAAA or gate it with a variable
# =============================================================================

#region Configuration

# Variables
variable "public_subdomains" {
  description = "List of public subdomains that should resolve to the public load balancer (e.g., [\"api\"])"
  type        = list(string)
  default     = []
}

// ACME validation subdomains removed

# Local values to reference the hosted zone (data source defined in data.tf)
locals {
  hosted_zone_id   = data.aws_route53_zone.hosted_zone.zone_id
  hosted_zone_name = data.aws_route53_zone.hosted_zone.name
}

#endregion

#region Resources

resource "aws_route53_record" "subdomains" {
  for_each = toset(var.public_subdomains)

  zone_id = local.hosted_zone_id
  name    = "${each.value}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "subdomains_ipv6" {
  for_each = toset(var.public_subdomains)

  zone_id = local.hosted_zone_id
  name    = "${each.value}.${var.domain_name}"
  type    = "AAAA"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = false
  }
}

# SPF record for email authentication
resource "aws_route53_record" "spf" {
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = "300"

  records = ["\"v=spf1 include:_spf.google.com ~all\""]
}

#endregion

#region Outputs

# Hosted Zone outputs
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

output "subdomain_urls" {
  description = "Public sub-domain URLs"
  value       = [for subdomain in var.public_subdomains : "https://${subdomain}.${var.domain_name}"]
}

#endregion