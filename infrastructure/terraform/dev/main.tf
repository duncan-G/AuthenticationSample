module "auth" {
  source = "../modules-single-az/auth"

  region       = var.region
  project_name = var.project_name
  env          = var.env

  idps                     = var.idps
  auth_callback            = var.auth_callback
  auth_logout              = var.auth_logout
  authenticated_policy_arn = var.authenticated_policy_arn
}

