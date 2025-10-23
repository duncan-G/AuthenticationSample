# =============================================================================
# Vercel Frontend Deployment
# =============================================================================
# Manages a Vercel project for the Next.js frontend and its configuration:
# 
# • GitHub repo integration
# • Environment variables (production and preview)
# • Root directory and project settings
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
  name      = "${var.project_name}-${var.env}"
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
      key    = "NEXT_PUBLIC_AUTH_SERVICE_URL"
      value  = "https://api.${var.domain_name}/auth"
      target = ["production", "preview"]
    },
    {
      key    = "NEXT_PUBLIC_GREETER_SERVICE_URL"
      value  = "https://api.${var.domain_name}/greeter"
      target = ["production", "preview"]
    },
    {
      key    = "NODE_ENV"
      value  = "production"
      target = ["production"]
    }
  ]
}

resource "vercel_deployment" "client" {
  project_id = vercel_project.frontend.id
  production = true
  ref        = "main"
}

#endregion
