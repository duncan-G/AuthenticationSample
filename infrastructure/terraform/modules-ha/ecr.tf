variable "microservices" {
  description = "List of microservice repository names to create in ECR"
  type        = list(string)
  default     = []
}

resource "aws_ecr_repository" "svc" {
  for_each             = toset(var.microservices)
  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration { scan_on_push = true }

  tags = {
    Name        = "${var.project_name}-${each.key}-repo"
    Environment = var.env
  }
}

resource "aws_ecr_lifecycle_policy" "svc" {
  for_each   = aws_ecr_repository.svc
  repository = each.value.name
  policy     = jsonencode({ rules = [{ rulePriority = 1, description = "Keep last 10 images", selection = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }, action = { type = "expire" } }] })
}

output "ecr_repositories" {
  value       = { for k, r in aws_ecr_repository.svc : k => r.repository_url }
  description = "ECR repository URLs"
}



