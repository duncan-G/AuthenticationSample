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
  default     = ""

  validation {
    condition     = var.env == "prod" ? length(var.domain_name) > 0 : true
    error_message = "Domain name must not be empty in prod environment"
  }
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
}

variable "auth_logout" {
  description = "Cognito logout URLs"
  type        = list(string)
}

# IAM policy attachment for authenticated users
variable "authenticated_policy_arn" {
  description = "If provided, attaches this policy ARN to the authenticated Cognito role"
  type        = string
  default     = ""
}

variable "ses_domain_identity_arn" {
  description = "SES domain identity ARN used by Cognito email configuration in prod"
  type        = string
  default     = ""
}
