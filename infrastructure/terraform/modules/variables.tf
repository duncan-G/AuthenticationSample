# ---------------------------------------------------------------------------
# Shared Variables
# ---------------------------------------------------------------------------
// This file contains variables used across the stack.

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

variable "environment" {
  description = "Environment name (e.g., dev, stage, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "Environment must be one of: dev, stage, prod"
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
  default     = "stage"
}

variable "production_environment_name" {
  description = "GitHub Actions production environment name"
  type        = string
  default     = "prod"
}

variable "domain_name" {
  description = "Primary domain (e.g., example.com)"
  type        = string

  validation {
    condition     = length(var.domain_name) > 0
    error_message = "Domain name must not be empty"
  }
}

variable "route53_hosted_zone_id" {
  description = "Route53 hosted-zone ID"
  type        = string

  validation {
    condition     = length(var.route53_hosted_zone_id) > 0
    error_message = "Hosted-zone ID must not be empty"
  }
}

variable "api_subdomain" {
  description = "Public API subdomain prefix (viewer) served by CloudFront (e.g., 'api')"
  type        = string
  default     = "api"
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

variable "az_count" {
  description = "Number of Availability Zones to use"
  type        = number
  default     = 3
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

variable "on_demand_base" {
  description = "Base number of On-Demand instances before using Spot"
  type        = number
  default     = 1
}

variable "spot_max_price" {
  description = "Optional max price for Spot instances (e.g., '0.08'). Empty uses on-demand price cap"
  type        = string
  default     = ""
}

variable "enable_origin_shield" {
  description = "Enable CloudFront Origin Shield"
  type        = bool
  default     = false
}

variable "waf_rule_set" {
  description = "List of AWS Managed WAF rule group identifiers to enable"
  type        = list(string)
  default = [
    "AWSManagedRulesCommonRuleSet",
    "AWSManagedRulesKnownBadInputsRuleSet",
    "AWSManagedRulesAmazonIpReputationList"
  ]
}

variable "jwks_ttl_seconds" {
  description = "TTL to cache /.well-known/jwks.json at CloudFront"
  type        = number
  default     = 120
}

variable "edge_shared_secret" {
  description = "Secret header value set by CloudFront to prevent origin bypass"
  type        = string
  sensitive   = true
}
