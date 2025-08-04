# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------

data "aws_availability_zones" "this" {}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*"] # regular AL2023 AMIs
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

data "aws_caller_identity" "current" {}
