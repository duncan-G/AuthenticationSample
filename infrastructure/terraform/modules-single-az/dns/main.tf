# =============================================================================
# Route 53 DNS — Public Records
# =============================================================================
# Publishes ALIAS records for API and Auth subdomains to the public NLB
# and an SPF TXT record at the zone apex.
# =============================================================================

#region Configuration

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
    name                   = var.load_balancer_dns_name
    zone_id                = var.load_balancer_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "api_aaaa" {
  zone_id = local.hosted_zone_id
  name    = "${var.api_subdomain}.${var.domain_name}"
  type    = "AAAA"

  alias {
    name                   = var.load_balancer_dns_name
    zone_id                = var.load_balancer_zone_id
    evaluate_target_health = false
  }
}

# Auth subdomain → Public Load Balancer
resource "aws_route53_record" "auth_a" {
  zone_id = local.hosted_zone_id
  name    = "${var.auth_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.load_balancer_dns_name
    zone_id                = var.load_balancer_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "auth_aaaa" {
  zone_id = local.hosted_zone_id
  name    = "${var.auth_subdomain}.${var.domain_name}"
  type    = "AAAA"

  alias {
    name                   = var.load_balancer_dns_name
    zone_id                = var.load_balancer_zone_id
    evaluate_target_health = false
  }
}

# SPF record for email authentication
resource "aws_route53_record" "spf" {
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = "300"

  # TXT values must be quoted once by Route 53; do not double-quote
  records = ["v=spf1 include:amazonses.com include:_spf.google.com ~all"]
}

#endregion

#endregion
