variable "domain_name" {
  description = "Primary domain (e.g., example.com)"
  type        = string

  validation {
    condition     = length(var.domain_name) > 0
    error_message = "Domain name must not be empty"
  }
}

# SES / Route53
variable "route53_hosted_zone_id" {
  description = "Hosted zone ID for Route53 (used for SES verification records)"
  type        = string
}
