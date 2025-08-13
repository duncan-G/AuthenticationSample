# =============================================================================
# ACM Certificate for Public TLS (API and Auth subdomains)
# =============================================================================
// Issues a single certificate with SANs for api.<domain> and auth.<domain>
// and validates it via Route53 DNS records.

#region Resources

resource "aws_acm_certificate" "public" {
  domain_name = "${var.api_subdomain}.${var.domain_name}"
  subject_alternative_names = [
    "${var.auth_subdomain}.${var.domain_name}"
  ]
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-public-cert-${var.env}"
    Environment = var.env
  }
}

# Create DNS validation records for each domain on the certificate
resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.public.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = local.hosted_zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

# Wait for DNS validation to complete and the certificate to be ISSUED
resource "aws_acm_certificate_validation" "public" {
  certificate_arn         = aws_acm_certificate.public.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

#endregion

#region Outputs

output "public_acm_certificate_arn" {
  description = "ARN of the issued ACM certificate for api/auth subdomains"
  value       = aws_acm_certificate.public.arn
}

#endregion


