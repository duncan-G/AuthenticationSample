terraform {
  backend "s3" {
    # pass bucket, region via -backend-config on init
    key     = "terraform.tfstate"
    encrypt = true
  }
}

