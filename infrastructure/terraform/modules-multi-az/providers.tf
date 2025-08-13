terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
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

provider "aws" {
  region = var.region
}

# Us-east-1 provider for CloudFront ACM certificates.
# CloudFront requires certificates to be in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

provider "vercel" {
  api_token = var.vercel_api_token
}


