# =============================================================================
# Route 53 DNS — Public Records
# =============================================================================
# Publishes ALIAS records for API and Auth subdomains to the public NLB
# and an SPF TXT record at the zone apex.
# =============================================================================

#region Configuration

# Variables
variable "api_subdomain" {
  description = "API subdomain label (e.g., 'api')"
  type        = string
  default     = "api"
}

variable "auth_subdomain" {
  description = "Auth subdomain label (e.g., 'auth')"
  type        = string
  default     = "auth"
}

// ACME validation records are not managed in this module

# Local values to reference the hosted zone (data source defined in providers.tf)
locals {
  hosted_zone_id   = data.aws_route53_zone.hosted_zone.zone_id
  hosted_zone_name = data.aws_route53_zone.hosted_zone.name
}

#endregion

#region Resources

# API subdomain → Public Load Balancer
resource "aws_route53_record" "api_a" {
  zone_id = local.hosted_zone_id
  name    = "${var.api_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "api_aaaa" {
  zone_id = local.hosted_zone_id
  name    = "${var.api_subdomain}.${var.domain_name}"
  type    = "AAAA"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = false
  }
}

# Auth subdomain → Public Load Balancer
resource "aws_route53_record" "auth_a" {
  zone_id = local.hosted_zone_id
  name    = "${var.auth_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "auth_aaaa" {
  zone_id = local.hosted_zone_id
  name    = "${var.auth_subdomain}.${var.domain_name}"
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

output "api_domain_url" {
  description = "API subdomain URL"
  value       = "https://${var.api_subdomain}.${var.domain_name}"
}

output "auth_domain_url" {
  description = "Auth subdomain URL"
  value       = "https://${var.auth_subdomain}.${var.domain_name}"
}

#endregion