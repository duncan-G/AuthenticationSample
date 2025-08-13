# =============================================================================
# Route 53 DNS — Public Records (Multi-AZ)
# =============================================================================
# Publishes ALIAS A/AAAA records for `auth` to the public NLB and
# publishes `api` to CloudFront distribution created in this module.
# =============================================================================

locals {
  hosted_zone_id   = var.route53_hosted_zone_id
  hosted_zone_name = data.aws_route53_zone.this.name
  fqdn_api         = "${var.api_subdomain}.${var.domain_name}"
  fqdn_auth        = "${var.auth_subdomain}.${var.domain_name}"
}

data "aws_route53_zone" "this" {
  zone_id = var.route53_hosted_zone_id
}

resource "aws_route53_record" "api_alias_a" {
  zone_id = local.hosted_zone_id
  name    = local.fqdn_api
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.api.domain_name
    zone_id                = aws_cloudfront_distribution.api.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "api_alias_aaaa" {
  zone_id = local.hosted_zone_id
  name    = local.fqdn_api
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.api.domain_name
    zone_id                = aws_cloudfront_distribution.api.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "auth_alias_a" {
  zone_id = local.hosted_zone_id
  name    = local.fqdn_auth
  type    = "A"
  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "auth_alias_aaaa" {
  zone_id = local.hosted_zone_id
  name    = local.fqdn_auth
  type    = "AAAA"
  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = false
  }
}

output "api_domain_url" {
  value       = "https://${local.fqdn_api}"
  description = "API subdomain URL"
}

output "auth_domain_url" {
  value       = "https://${local.fqdn_auth}"
  description = "Auth subdomain URL"
}


