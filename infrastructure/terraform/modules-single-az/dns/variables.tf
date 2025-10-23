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

variable "domain_name" {
  description = "Primary domain (e.g., example.com)"
  type        = string

  validation {
    condition     = length(var.domain_name) > 0
    error_message = "Domain name must not be empty"
  }
}

# Subdomain labels
variable "api_subdomain" {
  description = "API subdomain label (e.g., 'api')"
  type        = string
}

variable "auth_subdomain" {
  description = "Auth subdomain label (e.g., 'auth')"
  type        = string
}

# Inputs from load balancer module
variable "load_balancer_dns_name" {
  description = "DNS name of the public load balancer to alias to"
  type        = string
}

variable "load_balancer_zone_id" {
  description = "Hosted zone ID of the public load balancer"
  type        = string
}
