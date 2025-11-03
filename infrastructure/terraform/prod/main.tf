# =============================================================================
# Root: prod — wire all modules
# =============================================================================

# Network (VPC, subnets, SG)
module "network" {
  source = "../modules-single-az/network"

  project_name      = var.project_name
  env               = var.env
  availability_zone = data.aws_availability_zones.this.names[0]
}

# Compute (IAM roles, ASGs, ACM, TG, etc.)
module "compute" {
  source = "../modules-single-az/compute"

  region                     = var.region
  project_name               = var.project_name
  env                        = var.env
  domain_name                = var.domain_name
  api_subdomain              = var.api_subdomain
  auth_subdomain             = var.auth_subdomain
  codedeploy_bucket_name     = var.codedeploy_bucket_name
  route53_hosted_zone_id     = var.route53_hosted_zone_id
  vpc_id                     = module.network.vpc_id
  ami_id                     = data.aws_ami.amazon_linux.id
  account_id                 = data.aws_caller_identity.current.account_id
  instance_security_group_id = module.network.instance_security_group_id
  private_subnet_id          = module.network.private_subnet_id
  swarm_lock_table           = module.database.swarm_cluster_lock_table_name
}

# Load Balancer (NLB + TLS)
module "load_balancer" {
  source = "../modules-single-az/load-balancer"

  project_name           = var.project_name
  env                    = var.env
  public_subnet_id       = module.network.public_subnet_id
  domain_name            = var.domain_name
  api_subdomain          = var.api_subdomain
  auth_subdomain         = var.auth_subdomain
  route53_hosted_zone_id = var.route53_hosted_zone_id
  target_group_arn       = module.compute.worker_target_group_arn
}

# DNS (api/auth aliases to NLB)
module "dns" {
  source = "../modules-single-az/dns"

  project_name           = var.project_name
  env                    = var.env
  domain_name            = var.domain_name
  api_subdomain          = var.api_subdomain
  auth_subdomain         = var.auth_subdomain
  load_balancer_dns_name = module.load_balancer.load_balancer_dns_name
  load_balancer_zone_id  = module.load_balancer.load_balancer_zone_id
  route53_hosted_zone_id = var.route53_hosted_zone_id
}

# Database (DynamoDB table + IAM attach to compute roles)
module "database" {
  source = "../modules-single-az/database"

  project_name      = var.project_name
  env               = var.env
  worker_role_name  = module.compute.worker_role_name
  manager_role_name = module.compute.manager_role_name
}

# Cache (single EC2 + EBS) — optional; shares compute IAM and network
module "cache" {
  source = "../modules-single-az/cache"

  region                           = var.region
  project_name                     = var.project_name
  env                              = var.env
  ami_id                           = data.aws_ami.amazon_linux.id
  private_subnet_id                = module.network.private_subnet_id
  instance_security_group_id       = module.network.instance_security_group_id
  worker_iam_instance_profile_name = module.compute.worker_iam_instance_profile_name
  swarm_lock_table                 = module.database.swarm_cluster_lock_table_name
}

# CI/CD (ECR, CodeDeploy, IAM)
module "ci_cd" {
  source = "../modules-single-az/ci_cd"

  region                  = var.region
  project_name            = var.project_name
  env                     = var.env
  bucket_suffix           = var.bucket_suffix
  codedeploy_bucket_name  = var.codedeploy_bucket_name
  github_repository       = var.github_repository
  microservices           = var.microservices
  microservices_with_logs = var.microservices_with_logs
  account_id              = data.aws_caller_identity.current.account_id
  manager_role_name       = module.compute.manager_role_name
}

# Observability (IAM policies attached to compute roles)
module "observability" {
  source = "../modules-single-az/observability"

  region            = var.region
  project_name      = var.project_name
  env               = var.env
  worker_role_name  = module.compute.worker_role_name
  manager_role_name = module.compute.manager_role_name
}

# Frontend (Vercel project)
module "client" {
  source = "../modules-single-az/client"

  project_name          = var.project_name
  env                   = var.env
  domain_name           = var.domain_name
  github_repository     = var.github_repository
  vercel_root_directory = var.vercel_root_directory
  authority             = module.auth.cognito_user_pool_endpoint
  client_id             = module.auth.cognito_user_pool_web_client_id
  redirect_uri          = var.auth_callback[0]
}

# Auth Delivery (SES)
module "auth_delivery" {
  source = "../modules-single-az/auth-delivery"

  domain_name            = var.domain_name
  route53_hosted_zone_id = var.route53_hosted_zone_id
}

# Auth (Cognito)
module "auth" {
  source = "../modules-single-az/auth"

  region                  = var.region
  project_name            = var.project_name
  env                     = var.env
  domain_name             = var.domain_name
  ses_domain_identity_arn = module.auth_delivery.ses_domain_identity_arn

  idps          = var.idps
  auth_callback = var.auth_callback
  auth_logout   = var.auth_logout
}

