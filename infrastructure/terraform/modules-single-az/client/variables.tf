# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

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

variable "github_repository" {
  description = "GitHub repo in 'owner/repo' format"
  type        = string
}

variable "authority" {
  description = "Cognito client authority URL"
  type        = string
  validation {
    condition     = length(var.authority) > 0
    error_message = "Authority must not be empty"
  }
}

variable "client_id" {
  description = "Cognito client ID"
  type        = string
  validation {
    condition     = length(var.client_id) > 0
    error_message = "Client ID must not be empty"
  }
}

variable "redirect_uri" {
  description = "Cognito client redirect URI"
  type        = string
  validation {
    condition     = length(var.redirect_uri) > 0
    error_message = "Redirect URI must not be empty"
  }
}
