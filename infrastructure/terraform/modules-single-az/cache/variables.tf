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

# Cache EC2 instance variables
variable "cache_instance_type" {
  description = "EC2 instance type for cache instance"
  type        = string
  default     = "t4g.small"
}

variable "cache_instance_volume_size" {
  description = "Size of the EBS volume for cache instance (in GB)"
  type        = number
  default     = 20
}

variable "cache_instance_volume_type" {
  description = "Type of EBS volume for cache instance"
  type        = string
  default     = "gp3"
}
