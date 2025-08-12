# ---------------------------------------------------
# Terraform configuration and providers
# ---------------------------------------------------

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

variable "vercel_api_token" {
  description = "Vercel API token"
  type        = string
  sensitive   = true
}

provider "aws" {
  region = var.region
}

provider "vercel" {
  api_token = var.vercel_api_token
}
