locals {
  fqdn_api = "${var.api_subdomain}.${var.domain_name}"
}

# WAFv2 Web ACL
resource "aws_wafv2_web_acl" "this" {
  name        = "${var.project_name}-web-acl-${var.env}"
  description = "Managed rules for API edge"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 0
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-common-${var.env}"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf-${var.env}"
    sampled_requests_enabled   = true
  }
}

# Origin request policy to forward auth header and shared secret to origin
resource "aws_cloudfront_origin_request_policy" "api" {
  name = "${var.project_name}-api-origin-policy-${var.env}"
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["X-Edge-Auth", "Authorization", "X-Forwarded-For", "X-Forwarded-Proto"]
    }
  }
  cookies_config {
    cookie_behavior = "none"
  }
  query_strings_config {
    query_string_behavior = "all"
  }
}

resource "aws_cloudfront_cache_policy" "api" {
  name = "${var.project_name}-api-cache-${var.env}"
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
    headers_config { header_behavior = "none" }
    cookies_config { cookie_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
  }
  min_ttl     = 0
  default_ttl = 0
  max_ttl     = 1
}

resource "aws_cloudfront_cache_policy" "jwks" {
  name = "${var.project_name}-jwks-cache-${var.env}"
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
    headers_config { header_behavior = "none" }
    cookies_config { cookie_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
  }
  min_ttl     = 60
  default_ttl = var.jwks_ttl_seconds
  max_ttl     = 300
}

resource "aws_cloudfront_distribution" "api" {
  enabled         = true
  comment         = "${var.project_name}-${var.env} API"
  is_ipv6_enabled = true
  http_version    = "http3"
  web_acl_id      = aws_wafv2_web_acl.this.arn

  aliases = [local.fqdn_api]

  origin {
    domain_name = aws_lb.this.dns_name
    origin_id   = "nlb-origin"
    custom_origin_config {
      origin_protocol_policy = "https-only"
      https_port             = 443
      http_port              = 80
      origin_ssl_protocols   = ["TLSv1.2"]
    }
    origin_shield {
      enabled              = var.enable_origin_shield
      origin_shield_region = var.region
    }
    custom_header {
      name  = "X-Edge-Auth"
      value = var.edge_shared_secret
    }
  }

  default_cache_behavior {
    target_origin_id         = "nlb-origin"
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = aws_cloudfront_cache_policy.api.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.api.id
  }

  ordered_cache_behavior {
    path_pattern             = "/.well-known/jwks.json"
    target_origin_id         = "nlb-origin"
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = aws_cloudfront_cache_policy.jwks.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.api.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_route53_record" "api_alias" {
  zone_id = var.route53_hosted_zone_id
  name    = local.fqdn_api
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.api.domain_name
    zone_id                = aws_cloudfront_distribution.api.hosted_zone_id
    evaluate_target_health = false
  }
}



