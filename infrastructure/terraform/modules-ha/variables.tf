variable "project_name" {
  type = string
}

variable "env" {
  type = string
}

variable "region" {
  type = string
}

variable "az_count" {
  type    = number
  default = 3
}

variable "domain_name" {
  type = string
}

variable "api_subdomain" {
  type    = string
  default = "api"
}


variable "route53_hosted_zone_id" {
  type = string
}

variable "instance_type_managers" {
  type    = string
  default = "t4g.small"
}

variable "instance_types_workers" {
  type    = list(string)
  default = ["t4g.small", "m6g.medium"]
}

variable "desired_workers" {
  type    = number
  default = 3
}

variable "min_workers" {
  type    = number
  default = 1
}

variable "max_workers" {
  type    = number
  default = 9
}

variable "enable_spot" {
  type    = bool
  default = false
}

variable "on_demand_base" {
  type    = number
  default = 1
}

variable "spot_max_price" {
  type    = string
  default = ""
}

variable "enable_origin_shield" {
  type    = bool
  default = false
}

variable "waf_rule_set" {
  type    = list(string)
  default = [
    "AWSManagedRulesCommonRuleSet",
    "AWSManagedRulesKnownBadInputsRuleSet",
    "AWSManagedRulesAmazonIpReputationList"
  ]
}

variable "jwks_ttl_seconds" {
  type    = number
  default = 120
}

variable "edge_shared_secret" {
  type      = string
  sensitive = true
}

variable "acm_certificate_arn" {
  type    = string
  default = ""
}

variable "allowed_cloudfront_cidrs" {
  description = "Optional list of CloudFront egress CIDR ranges to restrict Envoy 8443 ingress"
  type        = list(string)
  default     = []
}

variable "vercel_api_token" {
  description = "Vercel API token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vercel_project_name" {
  description = "Vercel project name for the Next.js app"
  type        = string
  default     = "authentication-sample"
}

variable "vercel_root_directory" {
  description = "Relative path to the Next.js app root"
  type        = string
  default     = "clients/authentication-sample"
}

variable "bucket_suffix" {
  description = "Random/unique suffix for global resource names"
  type        = string
  default     = ""
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

variable "cognito_domain_prefix" {
  description = "Optional domain prefix for Cognito Hosted UI (leave empty to skip)"
  type        = string
  default     = ""
}


