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

# Cache EC2 instance variables
variable "cache_instance_type" {
  description = "EC2 instance type for cache instance"
  type        = string
  default     = "t4g.small"
}

variable "cache_instance_volume_size" {
  description = "Size of the EBS volume for cache instance (in GB)"
  type        = number
  default     = 20
}

variable "cache_instance_volume_type" {
  description = "Type of EBS volume for cache instance"
  type        = string
  default     = "gp3"
}

# Instance networking and image
variable "ami_id" {
  description = "AMI ID for the cache EC2 instance"
  type        = string
}

variable "private_subnet_id" {
  description = "Private subnet ID where the cache instance will be launched"
  type        = string
}

variable "instance_security_group_id" {
  description = "Security group ID to attach to the cache instance"
  type        = string
}

# IAM instance profile to reuse worker permissions from compute module
variable "worker_iam_instance_profile_name" {
  description = "IAM instance profile name providing worker permissions"
  type        = string
}

# Optional: S3 bucket and key for certificate-manager.sh distribution
variable "codedeploy_bucket_name" {
  description = "S3 bucket name hosting certificate-manager.sh"
  type        = string
  default     = ""
}

variable "swarm_lock_table" {
  description = "Name of the DynamoDB table used for swarm lock"
  type        = string
}
