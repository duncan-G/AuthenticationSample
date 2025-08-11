locals {
  name_prefix = "${var.project_name}-${var.env}"
}

# Target group in instance mode pointing to proxy (Envoy) 8080 on instances
resource "aws_lb_target_group" "proxy" {
  name        = substr(replace("${local.name_prefix}-proxy", "/", "-"), 0, 32)
  port        = 8080
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.this.id

  health_check {
    enabled             = true
    port                = "8080"
    protocol            = "TCP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }
}

resource "aws_lb" "this" {
  name                             = substr(replace("${local.name_prefix}-nlb", "/", "-"), 0, 32)
  internal                         = false
  load_balancer_type               = "network"
  enable_cross_zone_load_balancing = false

  dynamic "subnet_mapping" {
    for_each = aws_subnet.public
    content {
      subnet_id = subnet_mapping.value.id
    }
  }

  tags = { Name = "${local.name_prefix}-nlb" }
}

resource "aws_lb_listener" "tls_443" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "TLS"
  certificate_arn   = var.acm_certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.proxy.arn
  }
}

output "nlb_dns_name" { value = aws_lb.this.dns_name }
output "nlb_zone_id" { value = aws_lb.this.zone_id }
output "tg_proxy_arn" { value = aws_lb_target_group.proxy.arn }


