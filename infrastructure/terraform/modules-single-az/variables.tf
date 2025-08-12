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

variable "instance_type_managers" {
  description = "EC2 instance type for Swarm managers"
  type        = string
  default     = "t4g.small"
}

variable "instance_types_workers" {
  description = "List of instance types for workers (used for MixedInstancesPolicy if spot enabled)"
  type        = list(string)
  default     = ["t4g.small", "m6g.medium"]
}

variable "desired_workers" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}

variable "min_workers" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 3
}

variable "max_workers" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 9
}

variable "enable_spot" {
  description = "Whether to use Spot capacity for workers"
  type        = bool
  default     = false
}

# Toggle SSM association-based bootstrapping (declared in compute-scripts.tf)

variable "authenticated_policy_arn" {
  description = "If provided, attaches this policy ARN to the authenticated Cognito role"
  type        = string
  default     = ""
}

variable "manager_min_size" {
  description = "Minimum number of manager instances (should be odd for quorum)"
  type        = number
  default     = 1
}

variable "manager_max_size" {
  description = "Maximum number of manager instances"
  type        = number
  default     = 3
}

variable "manager_desired_capacity" {
  description = "Desired number of manager instances"
  type        = number
  default     = 1
}


