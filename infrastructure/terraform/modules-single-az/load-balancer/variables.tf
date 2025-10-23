# ---------------------------------------------------------------------------
# Shared Variables
# ---------------------------------------------------------------------------
# Variables used across the stack.

variable "project_name" {
  description = "Project name for resource naming"
  type        = string

  validation {
    condition     = length(var.project_name) > 0
    error_message = "Project name must not be empty"
  }
}

variable "env" {
  description = "Environment name (e.g. stage, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.env)
    error_message = "Environment must be one of: dev, stage, prod"
  }
}

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

# Inputs from other modules
variable "public_subnet_id" {
  description = "ID of the public subnet where the NLB will be placed"
  type        = string
}

variable "tls_certificate_arn" {
  description = "ACM certificate ARN for TLS listener"
  type        = string
}

variable "target_group_arn" {
  description = "Target group ARN to forward traffic to"
  type        = string
}
