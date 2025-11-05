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

# Subdomain labels
variable "api_subdomain" {
  description = "API subdomain label (e.g., 'api')"
  type        = string
}

variable "auth_subdomain" {
  description = "Auth subdomain label (e.g., 'auth')"
  type        = string
}

# Cognito Social IdPs
variable "idps" {
  description = "SOCIAL / OIDC IdPs (keys: google | apple)"
  type = map(object({
    client_id     = string
    client_secret = string
    scopes        = string
    provider_name = string
    provider_type = string
  }))
  default = {}

  validation {
    condition     = alltrue([for k, _ in var.idps : contains(["google", "apple"], k)])
    error_message = "Only 'google' and 'apple' providers are supported"
  }
}

variable "auth_callback" {
  description = "Cognito callback URLs"
  type        = list(string)
  default     = []
}

variable "auth_logout" {
  description = "Cognito logout URLs"
  type        = list(string)
  default     = []
}

# CI/CD
variable "github_repository" {
  description = "GitHub repo in 'owner/repo' format"
  type        = string
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

variable "microservices" {
  description = "List of microservices to deploy/build"
  type        = list(string)
  default     = []
}

variable "microservices_with_container_repos" {
  description = "Subset of microservices that should have container repositories created in ECR"
  type        = list(string)
  default     = []
}

variable "route53_hosted_zone_id" {
  description = "Route53 hosted-zone ID"
  type        = string
}

# Route53 hosted zone for DNS records
data "aws_route53_zone" "hosted_zone" {
  zone_id = var.route53_hosted_zone_id
}
