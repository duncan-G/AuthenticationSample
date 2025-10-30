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

# Certificate and DNS configuration (now managed within this module)
variable "domain_name" {
  description = "Root domain name (e.g. example.com)"
  type        = string

  validation {
    condition     = length(var.domain_name) > 0
    error_message = "domain_name must not be empty"
  }
}

variable "api_subdomain" {
  description = "Subdomain for the API (left side of the root domain)"
  type        = string
  default     = "api"
}

variable "auth_subdomain" {
  description = "Subdomain for the Auth service (left side of the root domain)"
  type        = string
  default     = "auth"
}

variable "route53_hosted_zone_id" {
  description = "Hosted zone ID for Route53 DNS validation records"
  type        = string

  validation {
    condition     = length(var.route53_hosted_zone_id) > 0
    error_message = "route53_hosted_zone_id must not be empty"
  }
}

variable "target_group_arn" {
  description = "Target group ARN to forward traffic to"
  type        = string
}
