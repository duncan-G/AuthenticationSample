# =============================================================================
# Network Load Balancer
# =============================================================================
# Internet-facing dualstack NLB in the public subnet that forwards TCP/80 to
# the public worker target group. HTTPS/TLS is intentionally not managed here.
# =============================================================================

#region Configuration


# Load Balancer Configuration
variable "enable_deletion_protection" {
  description = "Enable deletion protection for the load balancer"
  type        = bool
  default     = false
}

variable "enable_cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing"
  type        = bool
  default     = true
}

variable "load_balancer_type" {
  description = "Type of load balancer (network or application)"
  type        = string
  default     = "network"

  validation {
    condition     = contains(["network", "application"], var.load_balancer_type)
    error_message = "Load balancer type must be either 'network' or 'application'."
  }
}

#endregion

#region Resources

# Network Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-nlb-${var.env}"
  internal           = false
  load_balancer_type = var.load_balancer_type

  # Enable IPv4/IPv6
  ip_address_type = "dualstack"

  # Place in public subnet for internet-facing access
  subnets = [aws_subnet.public.id]

  # Security and operational settings
  enable_deletion_protection       = var.enable_deletion_protection
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing

  # Access logs can be enabled if an S3 bucket is provided

  tags = {
    Environment = var.env
    Type        = "network"
    IpVersion   = "dualstack"
    Purpose     = "Dualstack load balancer for Docker Swarm public workers"
  }
}

# HTTP Listener (Port 80)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public_workers.arn
  }

  tags = {
    Name        = "${var.project_name}-nlb-http-listener-${var.env}"
    Environment = var.env
    Protocol    = "HTTP"
  }
}

// HTTPS listener and target group removed – TLS not managed here

#endregion

#region Outputs

# Load Balancer outputs
output "load_balancer_id" {
  description = "ID of the load balancer"
  value       = aws_lb.main.id
}

output "load_balancer_arn" {
  description = "ARN of the load balancer"
  value       = aws_lb.main.arn
}

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}

output "load_balancer_zone_id" {
  description = "Canonical hosted zone ID of the load balancer"
  value       = aws_lb.main.zone_id
}

# Listener outputs
output "http_listener_arn" {
  description = "ARN of the HTTP listener"
  value       = aws_lb_listener.http.arn
}

#endregion
