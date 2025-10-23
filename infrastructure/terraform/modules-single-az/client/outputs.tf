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
  value       = "https://${vercel_project.frontend.name}.vercel.app"
}

