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
  description = "Name of the IAM role for manager nodes (optional)"
  type        = string
  default     = ""
}
