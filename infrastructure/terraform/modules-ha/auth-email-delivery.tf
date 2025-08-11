# =============================================================================
# AWS SES Email Delivery Infrastructure (HA)
# =============================================================================
# - SES domain identity and verification
# - DKIM setup
# - Route53 DNS records for verification and DKIM
# =============================================================================

#region Data Sources
data "aws_route53_zone" "this" {
  id = var.route53_hosted_zone_id
}
#endregion

#region Resources
resource "aws_ses_domain_identity" "this" {
  domain = var.domain_name
}

resource "aws_route53_record" "ses_verification" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = "_amazonses.${aws_ses_domain_identity.this.domain}"
  type    = "TXT"
  ttl     = 600
  records = [aws_ses_domain_identity.this.verification_token]
}

resource "aws_ses_domain_identity_verification" "this" {
  domain     = aws_ses_domain_identity.this.domain
  depends_on = [aws_route53_record.ses_verification]
}

resource "aws_ses_domain_dkim" "this" {
  domain = aws_ses_domain_identity.this.domain
}

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


