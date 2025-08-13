## Infrastructure System Design

This folder contains operational assets (Docker, Envoy, OTEL, Terraform, CodeDeploy, scripts). See `terraform/README.md` for Terraform-specific details. High-level design:

- Docker Swarm cluster on EC2, separated into public and private tiers within a dualstack VPC.
- Network Load Balancer (dualstack) forwards TCP/80 to public worker ASG.
- Route53 publishes A/AAAA ALIAS records for selected subdomains to the NLB.
- CodeDeploy deploys microservices to EC2 instances identified by tags.
- OpenTelemetry + CloudWatch for logs/metrics; minimal IAM scope.
- Vercel hosts the Next.js client; backend URL is exposed via environment variables.

Environments are managed via Terraform workspaces (`terraform-stage`, `terraform-prod`) driven by the GitHub Actions workflow `infrastructure-release.yml`.

