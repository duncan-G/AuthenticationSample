variable "region" {
  description = "AWS region for all resources (set via TF_VAR_region)"
  type        = string
}

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

variable "worker_role_name" {
  description = "Name of the IAM role for worker nodes"
  type        = string
}

variable "manager_role_name" {
  description = "Name of the IAM role for manager nodes"
  type        = string
}

variable "log_retention_in_days" {
  description = "CloudWatch Logs retention in days for OTEL log group"
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_in_days >= 1 && var.log_retention_in_days <= 3653
    error_message = "Retention must be between 1 and 3653 days."
  }
}
