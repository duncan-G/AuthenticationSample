# =============================================================================
# Route 53 DNS — Public Records
# =============================================================================
# Publishes ALIAS A/AAAA records for `public_subdomains` to the public NLB and
# an SPF TXT record at the zone apex.
# =============================================================================

#region Configuration

# Variables
variable "public_subdomains" {
  description = "List of public subdomains that should resolve to the public load balancer (e.g., [\"api\"])"
  type        = list(string)
  default     = []
}

// ACME validation records are not managed in this module

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