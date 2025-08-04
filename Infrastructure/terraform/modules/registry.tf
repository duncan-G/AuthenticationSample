# ---------------------------------------------------------------------------
# Container Registry
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "microservices" {
  for_each = toset(["authentication"])

  name                 = "${var.app_name}/${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "${var.app_name}-${each.key}-repository"
    Environment = var.environment
    Service     = each.key
  }
}

resource "aws_ecr_lifecycle_policy" "microservices" {
  for_each   = aws_ecr_repository.microservices
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection    = {
        tagStatus     = "tagged"
        tagPrefixList = ["v"]
        countType     = "imageCountMoreThan"
        countNumber   = 10
      }
      action = { type = "expire" }
    }]
  })
}
