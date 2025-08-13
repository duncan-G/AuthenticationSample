output "cloudfront_domain" {
  value       = aws_cloudfront_distribution.api.domain_name
  description = "CloudFront domain name"
}

output "nlb_dns" {
  value       = aws_lb.this.dns_name
  description = "NLB DNS name"
}

output "web_acl_arn" {
  value       = aws_wafv2_web_acl.this.arn
  description = "WAFv2 Web ACL ARN"
}
