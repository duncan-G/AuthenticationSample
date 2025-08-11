# =============================================================================
# AWS SES Email Delivery Infrastructure
# =============================================================================
# This file manages all infrastructure components required for AWS SES:
# 
# • SES domain verification and DKIM configuration for email delivery
# • Route53 DNS records for SES verification
# • Email delivery configuration for applications
# =============================================================================

#region Configuration

# Data Sources
data "aws_route53_zone" "this" {
  id = var.route53_hosted_zone_id
}

#endregion

#region Resources

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

#region Outputs

output "ses_domain_identity_arn" {
  value       = aws_ses_domain_identity.this.arn
  description = "ARN of the SES domain identity"
}

output "ses_domain_identity_domain" {
  value       = aws_ses_domain_identity.this.domain
  description = "Domain name for SES identity"
}

#endregion 