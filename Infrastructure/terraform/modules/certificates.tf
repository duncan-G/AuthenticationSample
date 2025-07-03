########################
# SSL Certificates Management
########################

########################
# CloudWatch Log Group for Certificate Management
########################

# CloudWatch Log Group for certificate management (consolidated)
resource "aws_cloudwatch_log_group" "certificate_manager" {
  name              = "/aws/ec2/${var.app_name}-certificate-manager"
  retention_in_days = 30

  tags = {
    Name        = "${var.app_name}-certificate-manager-logs"
    Environment = var.environment
  }
}

# Data source for existing hosted zone (for certbot DNS challenges)
data "aws_route53_zone" "existing" {
  zone_id = var.route53_hosted_zone_id
}

########################
# AWS Secrets Manager Access Policy
########################

# IAM policy for AWS Secrets Manager access
resource "aws_iam_policy" "secrets_manager_access_policy" {
  name        = "${var.app_name}-secrets-manager-access"
  description = "Allow access to AWS Secrets Manager for certificate configuration"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.app_name}-secrets*"
        ]
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-secrets-manager-access"
    Environment = var.environment
  }
}

# Attach Secrets Manager access policy to private instance role
resource "aws_iam_role_policy_attachment" "private_secrets_manager_access" {
  role       = aws_iam_role.private_instance_role.name
  policy_arn = aws_iam_policy.secrets_manager_access_policy.arn
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

# AWS Secrets Manager outputs
output "certificate_renewal_secret_name" {
  value       = "${var.app_name}-secrets"
  description = "Name of the AWS Secrets Manager secret for certificate renewal configuration"
}

output "certificate_renewal_secret_arn" {
  value       = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.app_name}-secrets"
  description = "ARN of the AWS Secrets Manager secret for certificate renewal configuration"
}

########################
# EBS Volume for Let's Encrypt Certificates
########################

variable "certbot_ebs_volume_id" {
  description = "ID of the existing EBS volume to attach for Let's Encrypt certificates"
  type        = string

  validation {
    condition     = length(var.certbot_ebs_volume_id) > 0
    error_message = "EBS volume ID must not be empty."
  }
}

# Policy for EBS volume operations
resource "aws_iam_policy" "ebs_volume_access" {
  name        = "${var.app_name}-letsencrypt-persistent"
  description = "Allow EC2 instances to manage EBS volumes for Let's Encrypt certificates"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumeStatus",
          "ec2:DescribeInstances",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:CreateVolume",
          "ec2:DeleteVolume"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-letsencrypt-persistent"
    Environment = var.environment
  }
}

# Attach EBS volume access policy to public instance role
resource "aws_iam_role_policy_attachment" "public_ebs_volume_access" {
  role       = aws_iam_role.public_instance_role.name
  policy_arn = aws_iam_policy.ebs_volume_access.arn
}

########################
# EBS Volume Attachment for Let's Encrypt Certificates
########################

resource "aws_volume_attachment" "certbot_ebs_attachment" {
  device_name = "/dev/sdf"
  volume_id   = var.certbot_ebs_volume_id
  instance_id = aws_instance.public.id

  # Wait for the instance to be running before attaching
  depends_on = [aws_instance.public]
}

########################
# EBS Volume Outputs
########################

output "certbot_ebs_attachment_status" {
  value       = "Attached to public instance as /dev/sdf"
  description = "Status of the EBS volume attachment for Let's Encrypt certificates"
}
