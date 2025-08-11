locals { cd_bucket = "${var.project_name}-codedeploy-${var.bucket_suffix}" }

resource "aws_s3_bucket" "codedeploy" {
  bucket = local.cd_bucket
}
resource "aws_s3_bucket_versioning" "codedeploy" {
  bucket = aws_s3_bucket.codedeploy.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "codedeploy" {
  bucket = aws_s3_bucket.codedeploy.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_public_access_block" "codedeploy" {
  bucket                  = aws_s3_bucket.codedeploy.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_codedeploy_app" "platform" {
  name             = "${var.project_name}-${var.env}"
  compute_platform = "Server"
}

output "codedeploy_bucket_name" { value = aws_s3_bucket.codedeploy.bucket }
output "codedeploy_app_name" { value = aws_codedeploy_app.platform.name }


