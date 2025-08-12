# =============================================================================
# Network Load Balancer Infrastructure
# =============================================================================
# This file manages all load balancer infrastructure components:
# 
# • Network Load Balancer for high-performance traffic distribution
# • Listeners for HTTP and HTTPS traffic
# • Integration with Auto Scaling Group target groups
# • Health checks and monitoring
# 
# Load Balancer Design:
# - Internet-facing NLB in public subnet
# - IPv6-only traffic support
# - Forwards traffic to public worker ASG
# - High availability and fault tolerance
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
  name               = "${var.project_name}-nlb"
  internal           = false
  load_balancer_type = var.load_balancer_type

  # Enable IPv6-only traffic
  ip_address_type = "dualstack"

  # Place in public subnet for internet-facing access
  subnets = [aws_subnet.public.id]

  # Security and operational settings
  enable_deletion_protection       = var.enable_deletion_protection
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing

  # Enable access logs (optional - requires S3 bucket)
  # access_logs {
  #   bucket  = aws_s3_bucket.lb_logs.bucket
  #   prefix  = "access-logs"
  #   enabled = true
  # }

  tags = {
    Name        = "${var.project_name}-network-load-balancer"
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
    Name        = "${var.project_name}-nlb-http-listener"
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
