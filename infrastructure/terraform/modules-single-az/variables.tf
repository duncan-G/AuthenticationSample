# ---------------------------------------------------------------------------
# Shared Variables
# ---------------------------------------------------------------------------
# Variables used across the stack.

variable "region" {
  description = "AWS region for all resources (set via TF_VAR_region)"
  type        = string
}

variable "project_name" {
  description = "Project name used as a resource prefix"
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
