# ---------------------------------------------------------------------------
# Shared Variables
# ---------------------------------------------------------------------------
# Variables used across the stack.

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

variable "bucket_suffix" {
  description = "Suffix to ensure unique S3 bucket names across envs"
  type        = string
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
