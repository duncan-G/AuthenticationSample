# =============================================================================
# Vercel Frontend Deployment
# =============================================================================
# This file manages Vercel deployment infrastructure components:
# 
# • Vercel project configuration for Next.js frontend
# • Git repository integration with GitHub
# • Environment variables for production and preview
# • Project settings and deployment configuration
# 
# Deployment Structure:
# - Framework: Next.js with TypeScript
# - Repository: GitHub integration for automatic deployments
# - Environment: Production and preview environment variables
# - API Integration: Backend service URL configuration
# =============================================================================

#region Configuration

# Variables
variable "vercel_root_directory" {
  description = "Root directory for the Vercel app"
  type        = string
}

#endregion

#region Resources

# Vercel project for the frontend application
resource "vercel_project" "frontend" {
  name      = var.project_name
  framework = "nextjs"

  git_repository = {
    type = "github"
    repo = var.github_repository
  }

  # Root directory for the frontend application
  root_directory = var.vercel_root_directory

  # Environment variables for the project
  environment = [
    {
      key    = "NEXT_PUBLIC_AUTHENTICATION_SERVICE_URL"
      value  = "https://api.${var.domain_name}/authentication"
      target = ["production", "preview"]
    },
    {
      key    = "NODE_ENV"
      value  = "production"
      target = ["production"]
    }
  ]

  # Project settings
  build_command    = null # Use framework default
  dev_command      = null # Use framework default
  install_command  = null # Use framework default
  output_directory = null # Use framework default
}

#endregion

#region Outputs

# Vercel project outputs
output "vercel_project_id" {
  description = "Vercel project ID"
  value       = vercel_project.frontend.id
}

output "vercel_project_name" {
  description = "Vercel project name"
  value       = vercel_project.frontend.name
}

output "vercel_project_url" {
  description = "Vercel project URL (default domain)"
  value       = "https://${vercel_project.frontend.name}.vercel.app"
}

output "vercel_production_url" {
  description = "Vercel production URL"
  value       = "https://${var.project_name}.vercel.app"
}

#endregion