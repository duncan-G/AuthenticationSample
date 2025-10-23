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
  certificate_arn   = var.tls_certificate_arn

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
