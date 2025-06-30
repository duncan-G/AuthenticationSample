########################
# SSL Certificates Management
########################

# Data source for existing hosted zone (for certbot DNS challenges)
data "aws_route53_zone" "existing" {
  zone_id = var.route53_hosted_zone_id
}

########################
# SSL Certificate Store (S3)
########################

# The SSL certificate bucket is created and configured by the infrastructure setup script.
# This file contains only the IAM policies and outputs that reference the bucket.
# The bucket name follows the pattern: ${var.app_name}-certificate-store-${var.bucket_suffix}

locals {
  certificate_bucket_name = "${var.app_name}-certificate-store-${var.bucket_suffix}"
  certificate_bucket_arn  = "arn:aws:s3:::${local.certificate_bucket_name}"
}

# IAM policy for SSL certificate bucket access
resource "aws_iam_policy" "ssl_certificates_bucket_access_policy" {
  name        = "${var.app_name}-certificate-store-bucket-access"
  description = "Allow access to SSL certificate storage S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          local.certificate_bucket_arn,
          "${local.certificate_bucket_arn}/*"
        ]
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-certificate-store-bucket-access"
    Environment = var.environment
  }
}

# Attach SSL certificate bucket policy to public instance role
resource "aws_iam_role_policy_attachment" "public_ssl_certificates_bucket_access" {
  role       = aws_iam_role.public_instance_role.name
  policy_arn = aws_iam_policy.ssl_certificates_bucket_access_policy.arn
}

# IAM policy for SSL certificate bucket read-only access (private instances)
resource "aws_iam_policy" "ssl_certificates_bucket_readonly_policy" {
  name        = "${var.app_name}-certificate-store-bucket-readonly"
  description = "Allow read-only access to SSL certificate storage S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          local.certificate_bucket_arn,
          "${local.certificate_bucket_arn}/*"
        ]
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-certificate-store-bucket-readonly"
    Environment = var.environment
  }
}

# Attach SSL certificate bucket read-only policy to private instance role
resource "aws_iam_role_policy_attachment" "private_ssl_certificates_bucket_readonly" {
  role       = aws_iam_role.private_instance_role.name
  policy_arn = aws_iam_policy.ssl_certificates_bucket_readonly_policy.arn
}

########################
# Certbot Route53 DNS Challenge Policy
########################

# IAM policy for certbot Route53 DNS challenge access
resource "aws_iam_policy" "certbot_route53_dns_challenge_policy" {
  name        = "${var.app_name}-certbot-route53-dns-challenge"
  description = "Allow certbot to perform Route53 DNS challenges for SSL certificate validation"

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "certbot-route53-dns-challenge-policy"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:GetChange"
        ]
        Resource = [
          "*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = [
          "arn:aws:route53:::hostedzone/${data.aws_route53_zone.existing.zone_id}"
        ]
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-certbot-route53-dns-challenge"
    Environment = var.environment
  }
}

# Attach certbot Route53 DNS challenge policy to public instance role
resource "aws_iam_role_policy_attachment" "public_certbot_route53_dns_challenge" {
  role       = aws_iam_role.public_instance_role.name
  policy_arn = aws_iam_policy.certbot_route53_dns_challenge_policy.arn
}

########################
# Outputs
########################

# SSL certificate bucket outputs
output "ssl_certificates_bucket_name" {
  value       = local.certificate_bucket_name
  description = "Name of the S3 bucket for SSL certificate storage"
}

output "ssl_certificates_bucket_arn" {
  value       = local.certificate_bucket_arn
  description = "ARN of the S3 bucket for SSL certificate storage"
}

output "ssl_certificates_bucket_readonly_policy_arn" {
  value       = aws_iam_policy.ssl_certificates_bucket_readonly_policy.arn
  description = "ARN of the SSL certificate bucket read-only policy"
}

# Certbot outputs
output "certbot_route53_dns_challenge_policy_arn" {
  value       = aws_iam_policy.certbot_route53_dns_challenge_policy.arn
  description = "ARN of the certbot Route53 DNS challenge policy"
}

output "route53_hosted_zone_id" {
  value       = data.aws_route53_zone.existing.zone_id
  description = "Route53 hosted zone ID for certbot DNS challenges"
}
