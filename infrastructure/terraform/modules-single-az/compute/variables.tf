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

variable "domain_name" {
  description = "Primary domain (e.g., example.com)"
  type        = string

  validation {
    condition     = length(var.domain_name) > 0
    error_message = "Domain name must not be empty"
  }
}

# CodeDeploy artifact bucket name (pre-existing)
variable "codedeploy_bucket_name" {
  description = "Name of the S3 bucket where CodeDeploy artifacts are stored"
  type        = string
}

# S3 key for certificate-manager.sh within the CodeDeploy bucket
variable "certificate_manager_s3_key" {
  description = "S3 key (path) to certificate-manager.sh in the CodeDeploy bucket"
  type        = string
  default     = "infrastructure/certificate-manager.sh"
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

# ---------------------------------------------------------------------------
# Compute Module-specific Variables
# ---------------------------------------------------------------------------

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
  default     = 1
}

variable "min_workers" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "max_workers" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3
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

variable "route53_hosted_zone_id" {
  description = "Hosted zone ID for Route53 (used for ACM DNS validation records)"
  type        = string
}
