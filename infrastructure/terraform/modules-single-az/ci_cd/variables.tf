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

variable "bucket_suffix" {
  description = "Suffix to ensure unique S3 bucket names across envs"
  type        = string
}

# CodeDeploy artifact bucket name (pre-existing)
variable "codedeploy_bucket_name" {
  description = "Name of the S3 bucket where CodeDeploy artifacts are stored"
  type        = string
}

variable "microservices" {
  description = "List of microservices to deploy/build (also used to create ECR repos)"
  type        = list(string)
  default     = []
}

variable "microservices_with_logs" {
  description = "Subset of microservices that should have CloudWatch logs collected via CodeDeploy"
  type        = list(string)
  default     = []
}

variable "github_repository" {
  description = "GitHub repo in 'owner/repo' format for OIDC trust policy"
  type        = string
  default     = ""
}

variable "staging_environment_name" {
  description = "GitHub Actions staging environment name"
  type        = string
  default     = "stage"
}

variable "production_environment_name" {
  description = "GitHub Actions production environment name"
  type        = string
  default     = "prod"
}

variable "account_id" {
  description = "AWS account ID for constructing ARNs"
  type        = string
}

variable "manager_role_name" {
  description = "Name of the IAM role for manager instances"
  type        = string
}
