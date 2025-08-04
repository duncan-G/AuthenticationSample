# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "region" {
  description = "AWS region for all resources (set via TF_VAR_region)"
  type        = string
}

variable "public_worker_instance_type" {
  description = "EC2 instance type for public worker nodes"
  type        = string
  default     = "t4g.micro"
}

variable "private_worker_instance_type" {
  description = "EC2 instance type for private worker nodes"
  type        = string
  default     = "t4g.small"
}

variable "manager_instance_type" {
  description = "EC2 instance type for manager nodes"
  type        = string
  default     = "t4g.micro"
}

variable "public_worker_count" {
  description = "Number of public worker instances"
  type        = number
  default     = 1
}

variable "private_worker_count" {
  description = "Number of private worker instances"
  type        = number
  default     = 1
}

variable "manager_count" {
  description = "Number of manager instances"
  type        = number
  default     = 1
}

variable "app_name" {
  description = "Application name used as a resource prefix"
  type        = string
  
  validation {
    condition     = length(var.app_name) > 0
    error_message = "Application name must not be empty"
  }
}

variable "environment" {
  description = "Environment name (e.g., staging, production)"
  type        = string
  
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be one of: staging, production"
  }
}

variable "deployment_bucket" {
  description = "S3 bucket name for deployment artifacts"
  type        = string
  default     = ""
}

variable "github_repository" {
  description = "GitHub repo in 'owner/repo' format for OIDC trust policy"
  type        = string
  default     = ""
}

variable "staging_environment_name" {
  description = "GitHub Actions staging environment name"
  type        = string
  default     = "staging"
}

variable "production_environment_name" {
  description = "GitHub Actions production environment name"
  type        = string
  default     = "production"
}

variable "domain_name" {
  description = "Root domain for the application (e.g., example.com)"
  type        = string

  validation {
    condition     = length(var.domain_name) > 0
    error_message = "Domain name must not be empty"
  }
}

variable "auth_callback" {
  description = "Cognito callback URLs"
  type        = list(string)
}

variable "subdomains" {
  description = "List of subdomains (e.g., [\"api\", \"admin\"])"
  type        = list(string)
}

variable "route53_hosted_zone_id" {
  description = "Route53 hosted-zone ID"
  type        = string

  validation {
    condition     = length(var.route53_hosted_zone_id) > 0
    error_message = "Hosted-zone ID must not be empty"
  }
}

variable "bucket_suffix" {
  description = "Suffix to ensure unique S3 bucket names across envs"
  type        = string
  
  validation {
    condition     = length(var.bucket_suffix) > 0
    error_message = "Bucket suffix must not be empty"
  }
}

variable "vercel_api_token" {
  description = "Vercel API token"
  type        = string
  sensitive   = true
}

variable "vercel_root_directory" {
  description = "Root directory for the Vercel app"
  type        = string
}
