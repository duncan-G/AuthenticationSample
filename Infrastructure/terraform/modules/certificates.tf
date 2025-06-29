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

# S3 bucket for SSL certificate storage
resource "aws_s3_bucket" "ssl_certificates_bucket" {
  bucket = "${var.app_name}-ssl-certificates-${var.bucket_suffix}"

  tags = {
    Name        = "${var.app_name}-ssl-certificates-bucket"
    Environment = var.environment
  }

  lifecycle {
    prevent_destroy = true
  }
}

# S3 bucket versioning for SSL certificate history
resource "aws_s3_bucket_versioning" "ssl_certificates_bucket" {
  bucket = aws_s3_bucket.ssl_certificates_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "ssl_certificates_bucket" {
  bucket = aws_s3_bucket.ssl_certificates_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "ssl_certificates_bucket" {
  bucket = aws_s3_bucket.ssl_certificates_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle policy
resource "aws_s3_bucket_lifecycle_configuration" "ssl_certificates_bucket" {
  bucket = aws_s3_bucket.ssl_certificates_bucket.id

  rule {
    id     = "ssl_certificate_cleanup"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    expiration {
      days = 365
    }
  }
}

# IAM policy for SSL certificate bucket access
resource "aws_iam_policy" "ssl_certificates_bucket_access_policy" {
  name        = "${var.app_name}-ssl-certificates-bucket-access"
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
          aws_s3_bucket.ssl_certificates_bucket.arn,
          "${aws_s3_bucket.ssl_certificates_bucket.arn}/*"
        ]
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-ssl-certificates-bucket-access"
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
  name        = "${var.app_name}-ssl-certificates-bucket-readonly"
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
          aws_s3_bucket.ssl_certificates_bucket.arn,
          "${aws_s3_bucket.ssl_certificates_bucket.arn}/*"
        ]
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-ssl-certificates-bucket-readonly"
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
  value       = aws_s3_bucket.ssl_certificates_bucket.bucket
  description = "Name of the S3 bucket for SSL certificate storage"
}

output "ssl_certificates_bucket_arn" {
  value       = aws_s3_bucket.ssl_certificates_bucket.arn
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

# S3 bucket for certbot artifacts (Docker image tarballs)
resource "aws_s3_bucket" "certbot_artifacts" {
  bucket = "${var.app_name}-certbot-${var.bucket_suffix}"

  tags = {
    Name        = "${var.app_name}-certbot-artifacts-bucket"
    Environment = var.environment
  }
}

# S3 bucket versioning for certbot artifacts
resource "aws_s3_bucket_versioning" "certbot_artifacts" {
  bucket = aws_s3_bucket.certbot_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption for certbot artifacts
resource "aws_s3_bucket_server_side_encryption_configuration" "certbot_artifacts" {
  bucket = aws_s3_bucket.certbot_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block for certbot artifacts
resource "aws_s3_bucket_public_access_block" "certbot_artifacts" {
  bucket = aws_s3_bucket.certbot_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Output for certbot artifacts bucket
output "certbot_artifacts_bucket_name" {
  value       = aws_s3_bucket.certbot_artifacts.bucket
  description = "Name of the S3 bucket for certbot artifacts"
}

# ECR repository for certbot image
resource "aws_ecr_repository" "certbot" {
  name                 = "${var.app_name}/certbot"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

# Output for ECR repo URI
output "certbot_ecr_repo_url" {
  value       = aws_ecr_repository.certbot.repository_url
  description = "ECR repository URL for certbot image"
}

# S3 bucket lifecycle policy for deployment artifacts cleanup
resource "aws_s3_bucket_lifecycle_configuration" "certbot_artifacts" {
  bucket = aws_s3_bucket.certbot_artifacts.id

  rule {
    id     = "certbot_artifacts_cleanup"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    expiration {
      days = 90
    }
  }
} 