# =============================================================================
# ACM Certificates — Multi-AZ
# =============================================================================
// 1) Regional certificate for the NLB (api/auth SANs) with DNS validation
// 2) Us-east-1 certificate for CloudFront (api host) with DNS validation

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

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.public.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = var.route53_hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

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

# =============================================================================
# CloudFront certificate in us-east-1
# =============================================================================

resource "aws_acm_certificate" "edge" {
  provider                  = aws.us_east_1
  domain_name               = "${var.api_subdomain}.${var.domain_name}"
  validation_method         = "DNS"
  subject_alternative_names = []

  lifecycle { create_before_destroy = true }

  tags = {
    Name        = "${var.project_name}-edge-cert-${var.env}"
    Environment = var.env
  }
}

resource "aws_route53_record" "edge_acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.edge.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = var.route53_hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "edge" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.edge.arn
  validation_record_fqdns = [for record in aws_route53_record.edge_acm_validation : record.fqdn]
}


