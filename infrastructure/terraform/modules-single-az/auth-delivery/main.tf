# =============================================================================
# Authentication Email Delivery Infrastructure (SES)
# =============================================================================
#
# This module provisions:
# • SES domain identity, DKIM and Route53 verification records
#
# NOTE: In the future this module can be merged into a communication module.
# =============================================================================

#region SES Email Delivery (from auth-email-delivery.tf)

# Data Sources
data "aws_route53_zone" "this" {
  zone_id = var.route53_hosted_zone_id
}

# SES Domain Identity for Email Delivery
resource "aws_ses_domain_identity" "this" {
  domain = var.domain_name
}

# Route53 Record for SES Domain Verification
resource "aws_route53_record" "ses_verification" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = "_amazonses.${aws_ses_domain_identity.this.domain}"
  type    = "TXT"
  ttl     = 600
  records = [aws_ses_domain_identity.this.verification_token]
}

# SES Domain Identity Verification
resource "aws_ses_domain_identity_verification" "this" {
  domain     = aws_ses_domain_identity.this.domain
  depends_on = [aws_route53_record.ses_verification]
}

# SES Domain DKIM Configuration
resource "aws_ses_domain_dkim" "this" {
  domain = aws_ses_domain_identity.this.domain
}

# Route53 DKIM Records
resource "aws_route53_record" "dkim" {
  count   = 3
  zone_id = data.aws_route53_zone.this.zone_id
  name    = "${aws_ses_domain_dkim.this.dkim_tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_ses_domain_dkim.this.dkim_tokens[count.index]}.dkim.amazonses.com"]
}

#endregion
