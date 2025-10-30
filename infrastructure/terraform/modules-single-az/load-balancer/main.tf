# =============================================================================
# ACM Certificate for Public TLS (API and Auth subdomains)
# =============================================================================
// Issues a single certificate with SANs for api.<domain> and auth.<domain>
// and validates it via Route53 DNS records.
# =============================================================================

#region TLS Certificate

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

  zone_id         = var.route53_hosted_zone_id
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

# =============================================================================
# Network Load Balancer
# =============================================================================
# Internet-facing dualstack NLB in the public subnet that terminates TLS on 443
# and forwards to the worker target group over TCP/80.
# =============================================================================

#region Resources

# Network Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-nlb-${var.env}"
  internal           = false
  load_balancer_type = var.load_balancer_type

  # Enable IPv4/IPv6
  ip_address_type = "dualstack"

  # Place in public subnet for internet-facing access
  subnets = [var.public_subnet_id]

  # Security and operational settings
  enable_deletion_protection       = var.enable_deletion_protection
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing

  # Access logs can be enabled if an S3 bucket is provided

  tags = {
    Environment = var.env
    Type        = "network"
    IpVersion   = "dualstack"
    Purpose     = "Dualstack load balancer for Docker Swarm workers"
  }
}

# TLS Listener (Port 443)
resource "aws_lb_listener" "tls" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "TLS"
  certificate_arn   = aws_acm_certificate_validation.public.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = var.target_group_arn
  }

  tags = {
    Name        = "${var.project_name}-nlb-tls-listener-${var.env}"
    Environment = var.env
    Protocol    = "TLS"
  }
}

#endregion
