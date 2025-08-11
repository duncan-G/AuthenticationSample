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

variable "public_subdomains" {
  description = "List of public subdomains that should resolve to the public load balancer"
  type        = list(string)
  default     = ["api"]
}


variable "bucket_suffix" {
  description = "Suffix to ensure unique S3 bucket names across envs"
  type        = string

  validation {
    condition     = length(var.bucket_suffix) > 0
    error_message = "Bucket suffix must not be empty"
  }
}


# Microservice lists used by ECR and CodeDeploy modules
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

# Toggle SSM association-based bootstrapping (set false when using userdata)
variable "enable_ssm_associations" {
  description = "Enable SSM associations to bootstrap docker and cloudwatch on instances"
  type        = bool
  default     = false
}


