# =============================================================================
# Main Terraform Configuration
# =============================================================================
# This file calls the modules-single-az module to deploy the complete infrastructure
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    vercel = {
      source  = "vercel/vercel"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    # Bucket is passed via -backend-config during terraform init
    key     = "terraform.tfstate"
    encrypt = true
  }
}

# ---------------------------------------------------------------------------
# Providers
# ---------------------------------------------------------------------------

provider "aws" {
  region = var.region
}

provider "vercel" {
  api_token = var.vercel_api_token
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-1"
}

variable "project_name" {
  description = "Project name used as a resource prefix"
  type        = string
}

variable "env" {
  description = "Environment name (e.g. stage, prod)"
  type        = string
  default     = "stage"
}

variable "domain_name" {
  description = "Primary domain (e.g., example.com)"
  type        = string
}

variable "api_subdomain" {
  description = "API subdomain label (e.g., 'api')"
  type        = string
  default     = "api"
}

variable "auth_subdomain" {
  description = "Auth subdomain label (e.g., 'auth')"
  type        = string
  default     = "auth"
}

variable "route53_hosted_zone_id" {
  description = "Route53 hosted-zone ID"
  type        = string
}

variable "vercel_api_token" {
  description = "Vercel API token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "bucket_suffix" {
  description = "Suffix for S3 bucket names"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository (owner/repo)"
  type        = string
}

variable "vercel_root_directory" {
  description = "Root directory for the Vercel app"
  type        = string
  default     = "clients/auth-sample"
}

variable "codedeploy_bucket_name" {
  description = "Name of the pre-existing S3 bucket used for CodeDeploy artifacts"
  type        = string
}

variable "microservices" {
  description = "List of microservices to deploy"
  type        = list(string)
  default     = ["auth"]
}

variable "microservices_with_logs" {
  description = "List of microservices that should have CloudWatch logs"
  type        = list(string)
  default     = ["auth"]
}

variable "staging_environment_name" {
  description = "Name of the staging environment"
  type        = string
  default     = "stage"
}

variable "production_environment_name" {
  description = "Name of the production environment"
  type        = string
  default     = "prod"
}

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

# ---------------------------------------------------------------------------
# Module Calls
# ---------------------------------------------------------------------------

module "infrastructure" {
  source = "./modules-single-az"

  # Core configuration
  region        = var.region
  project_name  = var.project_name
  env           = var.env
  domain_name   = var.domain_name
  api_subdomain = var.api_subdomain
  auth_subdomain = var.auth_subdomain
  route53_hosted_zone_id = var.route53_hosted_zone_id
  bucket_suffix = var.bucket_suffix

  # Authentication configuration
  idps          = var.idps
  auth_callback = var.auth_callback
  auth_logout   = var.auth_logout

  # Vercel configuration
  vercel_api_token = var.vercel_api_token
  github_repository = var.github_repository
  vercel_root_directory = var.vercel_root_directory

  # CodeDeploy configuration
  codedeploy_bucket_name = var.codedeploy_bucket_name
  microservices = var.microservices
  microservices_with_logs = var.microservices_with_logs
  staging_environment_name = var.staging_environment_name
  production_environment_name = var.production_environment_name
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "cognito_user_pool_id" {
  value = module.infrastructure.cognito_user_pool_id
}

output "cognito_user_pool_arn" {
  value = module.infrastructure.cognito_user_pool_arn
}

output "cognito_user_pool_endpoint" {
  value = module.infrastructure.cognito_user_pool_endpoint
}

output "cognito_user_pool_domain" {
  value = module.infrastructure.cognito_user_pool_domain
}

output "cognito_user_pool_client_id_web" {
  value = module.infrastructure.cognito_user_pool_client_id_web
}

output "cognito_user_pool_client_id_back" {
  value = module.infrastructure.cognito_user_pool_client_id_back
}

output "cognito_identity_pool_id" {
  value = module.infrastructure.cognito_identity_pool_id
}

output "cognito_auth_url" {
  value = module.infrastructure.cognito_auth_url
}

output "ses_domain_identity_arn" {
  value = module.infrastructure.ses_domain_identity_arn
}

output "ses_domain_identity_domain" {
  value = module.infrastructure.ses_domain_identity_domain
}
