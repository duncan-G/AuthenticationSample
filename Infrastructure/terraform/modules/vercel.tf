########################
# Vercel Frontend Deployment
########################

# Vercel project for the frontend application
resource "vercel_project" "frontend" {
  name      = "${var.app_name}"
  framework = "nextjs"

  git_repository = {
    type = "github"
    repo = var.github_repository
  }

  # Root directory for the frontend
  root_directory = "Clients/authentication-sample"

  # Environment variables for the project
  environment = [
    {
      key    = "NEXT_PUBLIC_AUTHENTICATION_SERVICE_URL"
      value  = "https://api.${var.domain_name}"
      target = ["production", "preview"]
    },
    {
      key    = "NODE_ENV"
      value  = "production"
      target = ["production"]
    }
  ]
}

# Deployment configuration
resource "vercel_deployment" "frontend" {
  project_id = vercel_project.frontend.id
  
  # Use the main branch for production, feature branches for staging
  ref = var.environment == "production" ? "main" : var.environment

  # Force a new deployment when configuration changes
  production = var.environment == "production"
}

########################
# Outputs
########################

output "vercel_project_id" {
  description = "Vercel project ID"
  value       = vercel_project.frontend.id
}

output "vercel_project_url" {
  description = "Vercel project URL (default domain)"
  value       = "https://${vercel_project.frontend.name}.vercel.app"
}

output "vercel_deployment_url" {
  description = "Vercel deployment URL"
  value       = vercel_deployment.frontend.url
} 