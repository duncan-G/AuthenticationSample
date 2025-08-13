# Infrastructure

This directory contains the Terraform code for the Auth Sample application. It provisions a production-ready baseline on AWS with networking, compute, CI/CD, monitoring, DNS, and frontend hosting.

## System Design

- VPC with public/private subnets, IPv4 and IPv6 enabled.
- Security group permits 80/443 (IPv4 and IPv6) plus Docker Swarm ports. Egress is open to the internet (IPv4/IPv6).
- Network Load Balancer (dualstack) fronts worker nodes on TCP/80. TLS termination is handled by downstream Envoy or application layer as needed. NLB listeners are TCP.
- Auto Scaling Groups: workers (private) and managers (private, Swarm control plane). Rolling instance refresh is enabled.
- CodeDeploy integrates with EC2 via tags to deploy microservices. Artifacts stored in a private S3 bucket.
- OpenTelemetry + CloudWatch for logs/metrics/traces with minimal IAM granting.
- Route53 publishes A/AAAA ALIAS records for `auth_subdomain` to the NLB. If `api_cdn_domain_name` is set, publishes `api_subdomain` to the CDN.
- ECR hosts per-service repositories.
- Vercel deploys the Next.js client; the app receives environment variables for backend URLs.

### High-level topology

```
Internet → NLB (TCP/80, dualstack)
             └── Target Group (TCP/80) → ASG (Workers)

VPC (10.0.0.0/16, IPv6)
  ├─ Public Subnet  (10.0.1.0/24) → NLB
  └─ Private Subnet (10.0.2.0/24) → Managers, Private Workers
```

## Getting Started

1) Backend state bucket in S3.
2) Export required TF_VARs (see below) or use a `.tfvars` file.
3) Initialize, plan, and apply from `infrastructure/terraform/modules`.

### Required TF variables

```bash
export TF_VAR_region="us-west-1"
export TF_VAR_project_name="auth-sample"
export TF_VAR_environment="stage"   # stage|prod
export TF_VAR_domain_name="example.com"
export TF_VAR_route53_hosted_zone_id="Z123..."
export TF_VAR_bucket_suffix="unique-suffix"
export TF_VAR_vercel_api_token="vercel-token"
export TF_VAR_vercel_root_directory="clients/auth-sample"
export TF_VAR_auth_subdomain="auth"
export TF_VAR_api_subdomain="api"
```

### Optional

```bash
export TF_VAR_deployment_bucket="deployment-artifacts-bucket"
export TF_VAR_github_repository="org/repo"
export TF_VAR_staging_environment_name="terraform-stage"
export TF_VAR_production_environment_name="terraform-prod"

export TF_VAR_instance_types_workers='["t4g.small","m6g.medium"]'
export TF_VAR_instance_type_managers="t4g.small"
export TF_VAR_min_workers=3
export TF_VAR_desired_workers=3
export TF_VAR_max_workers=9

# If fronting API with CloudFront, provide its domain to alias API DNS:
export TF_VAR_api_cdn_domain_name="dxxxxx.cloudfront.net"
```

### Apply

```bash
cd infrastructure/terraform/modules
terraform init -backend-config="bucket=your-tf-state-bucket" -backend-config="region=us-west-1"
terraform plan
terraform apply
```

## Module Layout

- `providers.tf`: Terraform + providers and S3 backend (bucket provided at init).
- `variables.tf`: Shared variables for region, project, environment, etc.
- `data.tf`: AMI and availability zones.
- `network.tf`: VPC, subnets, route tables, associations.
- `network-security.tf`: Security group + rules.
- `compute.tf`: IAM roles/policies, launch templates, ASGs, target groups.
- `load-balancer.tf`: NLB and TCP listeners.
- `dns.tf`: Route53 ALIAS records for API/Auth subdomains and SPF.
- `container-registry.tf`: ECR repos and lifecycle policies.
- `deploy-microservices.tf`: CodeDeploy app, groups, roles, and S3 bucket.
- `otel-collector.tf`: IAM policies for CloudWatch/X-Ray; attachments to roles.
- `client.tf`: Vercel project configuration.
- `auth-email-delivery.tf`: SES identity + DKIM records.

## Notes and assumptions

- NLB + TCP: Target group protocol and listener are TCP; health check uses TCP to avoid HTTP-only assumptions.
- IPv6: Public and private subnets are IPv6-enabled; security group allows v4/v6 for web ports.
- Workspaces: The GitHub workflow selects workspaces `terraform-stage` and `terraform-prod` and sets `TF_VAR_environment` accordingly (`stage`/`prod`).
- Subdomains: Provide `TF_VAR_auth_subdomain` and optionally `TF_VAR_api_cdn_domain_name` for API fronted by CloudFront. `TF_VAR_api_subdomain` controls the label for API DNS.

## Troubleshooting

- Confirm the state backend S3 bucket exists and is accessible by the workflow role.
- If the workflow fails to apply, ensure the plan artifact was created and downloaded; or run a fresh plan+apply.
- For ASG target registration, verify instances are healthy in the NLB target group (TCP health checks).