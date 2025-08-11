# =============================================================================
# AWS ECR Repository Infrastructure
# =============================================================================
# This file manages all ECR repositories required for the application:
# 
# • ECR repositories for microservices
# • Lifecycle policies for image retention
# =============================================================================

#region Resources

resource "aws_ecr_repository" "microservices" {
  for_each = toset(var.microservices)

  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "${var.project_name}-${each.key}-repository"
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
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = ["v"]
        countType     = "imageCountMoreThan"
        countNumber   = 10
      }
      action = { type = "expire" }
    }]
  })
}

#endregion