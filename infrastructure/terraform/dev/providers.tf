# ---------------------------------------------------
# Terraform configuration and providers
# ---------------------------------------------------

terraform {
  required_version = ">= 1.12.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.18.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Providers
# ---------------------------------------------------------------------------


provider "aws" {
  region = var.region
}
