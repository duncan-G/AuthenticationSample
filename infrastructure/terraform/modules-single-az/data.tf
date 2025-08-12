# =============================================================================
# Data Sources
# =============================================================================
# Common data sources used across the module (AZs, AMI, caller identity, zone).
# =============================================================================

data "aws_availability_zones" "this" {}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

data "aws_caller_identity" "current" {}

variable "route53_hosted_zone_id" {
  description = "Route53 hosted-zone ID"
  type        = string
}

# Route53 hosted zone for DNS records
data "aws_route53_zone" "hosted_zone" {
  zone_id = var.route53_hosted_zone_id
}
