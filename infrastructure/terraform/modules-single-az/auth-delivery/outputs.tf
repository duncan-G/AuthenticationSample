output "ses_domain_identity_arn" {
  value       = aws_ses_domain_identity.this.arn
  description = "ARN of the SES domain identity"
}

output "ses_domain_identity_domain" {
  value       = aws_ses_domain_identity.this.domain
  description = "Domain name for SES identity"
}
