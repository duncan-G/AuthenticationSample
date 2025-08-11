# ---------------------------------------------------
#  Terraform configuration for AWS application stack
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
    # Bucket is passed via `-backend-config="bucket=…"` during `terraform init`
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

data "aws_availability_zones" "this" {}

provider "vercel" {
  api_token = var.vercel_api_token
}
