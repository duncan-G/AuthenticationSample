locals {
  vercel_env = {
    PROJECT_NAME = var.project_name
    API_BASE_URL = "https://${var.api_subdomain}.${var.domain_name}"
  }
}

resource "vercel_project" "client" {
  name      = var.vercel_project_name
  framework = "nextjs"
}

resource "vercel_project_domain" "client_domain" {
  project_id = vercel_project.client.id
  domain     = "${var.vercel_project_name}.vercel.app"
}

# For GitOps, prefer building/deploying from CI. Keep a minimal deployment placeholder;
# remove attributes not supported by the provider here.
resource "vercel_deployment" "client" {
  project_id = vercel_project.client.id
  production = true
}


