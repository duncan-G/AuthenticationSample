# 📋 Terraform Variables Reference

This document provides a comprehensive reference for all variables used in the Terraform configuration.

---

## 🔧 Core Variables

### Application Configuration

| Variable | Type | Default | Description | Example |
|----------|------|---------|-------------|---------|
| `app_name` | `string` | - | Application name used as resource prefix | `"my-auth-app"` |
| `environment` | `string` | - | Environment name (staging/production) | `"staging"` |
| `region` | `string` | - | AWS region for all resources | `"us-west-1"` |

### Instance Configuration

| Variable | Type | Default | Description | Example |
|----------|------|---------|-------------|---------|
| `public_worker_instance_type` | `string` | `"t4g.micro"` | EC2 instance type for public worker nodes | `"t4g.small"` |
| `private_worker_instance_type` | `string` | `"t4g.small"` | EC2 instance type for private worker nodes | `"t4g.medium"` |
| `manager_instance_type` | `string` | `"t4g.micro"` | EC2 instance type for manager nodes | `"t4g.small"` |
| `public_worker_count` | `number` | `1` | Number of public worker instances | `2` |
| `private_worker_count` | `number` | `1` | Number of private worker instances | `3` |
| `manager_count` | `number` | `1` | Number of manager instances | `2` |

### Domain & DNS Configuration

| Variable | Type | Default | Description | Example |
|----------|------|---------|-------------|---------|
| `domain_name` | `string` | - | Primary domain name | `"example.com"` |
| `subdomains` | `list(string)` | `[]` | List of subdomains to create | `["api", "admin"]` |
| `route53_hosted_zone_id` | `string` | - | Route53 hosted zone ID | `"Z1234567890"` |
| `auth_callback` | `string` | - | Authentication callback URL | `"https://example.com/auth/callback"` |

### Deployment Configuration

| Variable | Type | Default | Description | Example |
|----------|------|---------|-------------|---------|
| `deployment_bucket` | `string` | - | S3 bucket for deployment artifacts | `"my-app-deployments"` |
| `github_repository` | `string` | - | GitHub repository (format: owner/repo) | `"myorg/my-app"` |
| `staging_environment_name` | `string` | `"terraform-staging"` | GitHub environment name for staging | `"staging"` |
| `production_environment_name` | `string` | `"terraform-production"` | GitHub environment name for production | `"production"` |

### Vercel Configuration

| Variable | Type | Default | Description | Example |
|----------|------|---------|-------------|---------|
| `vercel_api_token` | `string` | - | Vercel API token for deployments | `"vercel_token_123"` |
| `vercel_root_directory` | `string` | `"Clients/authentication-sample"` | Root directory for Vercel deployment | `"frontend"` |

### Certificate Management

| Variable | Type | Default | Description | Example |
|----------|------|---------|-------------|---------|
| `bucket_suffix` | `string` | - | Suffix for certificate storage bucket | `"prod"` |
| `certbot_ebs_volume_id` | `string` | - | EBS volume ID for certificate storage | `"vol-1234567890"` |

---

## 🔐 Authentication Variables

### Cognito Configuration

| Variable | Type | Default | Description | Example |
|----------|------|---------|-------------|---------|
| `idps` | `map(object)` | `{}` | Social/OIDC Identity Providers | See example below |

### Identity Provider Configuration Example

```hcl
variable "idps" {
  description = "Social/OIDC Identity Providers"
  type = map(object({
    client_id     = string
    client_secret = string
    scopes        = string
  }))
  default = {
    google = {
      client_id     = "your-google-client-id.apps.googleusercontent.com"
      client_secret = "your-google-client-secret"
      scopes        = "openid email profile"
    }
    apple = {
      client_id     = "com.your.app.service"
      client_secret = "your-apple-client-secret"
      scopes        = "openid email"
    }
  }
}
```

---

## 🌐 Network Configuration

### VPC Configuration

The VPC is automatically configured with the following settings:

| Setting | Value | Description |
|---------|-------|-------------|
| CIDR Block | `10.0.0.0/16` | Main VPC CIDR |
| Public Subnet | `10.0.1.0/24` | Public subnet for load balancers |
| Private Subnet | `10.0.2.0/24` | Private subnet for application servers |
| Availability Zone | Auto-detected | Based on selected region |

### Security Group Rules

| Rule | Port | Protocol | Source | Purpose |
|------|------|----------|--------|---------|
| HTTP | 80 | TCP | 0.0.0.0/0 | Web traffic |
| HTTPS | 443 | TCP | 0.0.0.0/0 | Secure web traffic |
| Docker Swarm | 2377, 7946, 4789 | TCP/UDP | VPC CIDR | Cluster communication |
| SSH | 22 | TCP | 0.0.0.0/0 | Remote access |

---

## 📊 Monitoring Configuration

### CloudWatch Configuration

| Setting | Value | Description |
|---------|-------|-------------|
| Log Retention | 30 days | Default log retention period |
| Metrics Namespace | `{app_name}/OpenTelemetry` | Custom metrics namespace |
| Log Groups | Auto-created | Per-service log groups |

### OpenTelemetry Configuration

| Component | Purpose | Configuration |
|-----------|---------|---------------|
| Collector | Telemetry collection | Auto-configured on instances |
| CloudWatch Exporter | Logs and metrics | Enabled by default |
| X-Ray Exporter | Distributed tracing | Enabled by default |

---

## 🔧 Advanced Configuration

### Custom Instance Types

```hcl
# For high-performance workloads
variable "public_worker_instance_type" {
  description = "EC2 instance type for public worker nodes"
  type        = string
  default     = "c6g.medium"  # Compute optimized
}

# For memory-intensive workloads
variable "private_worker_instance_type" {
  description = "EC2 instance type for private worker nodes"
  type        = string
  default     = "r6g.medium"  # Memory optimized
}
```

### Custom Instance Counts

```hcl
# High availability setup
variable "public_worker_count" {
  description = "Number of public worker instances"
  type        = number
  default     = 3  # Minimum for HA
}

variable "manager_count" {
  description = "Number of manager instances"
  type        = number
  default     = 3  # Odd number for quorum
}
```

### Custom Domain Configuration

```hcl
# Multiple subdomains
variable "subdomains" {
  description = "List of subdomains to create"
  type        = list(string)
  default     = ["api", "admin", "docs", "status"]
}

# Custom authentication callback
variable "auth_callback" {
  description = "Authentication callback URL"
  type        = string
  default     = "https://app.example.com/auth/callback"
}
```

---

## 🚀 Environment-Specific Variables

### Staging Environment

```bash
export TF_VAR_environment="staging"
export TF_VAR_app_name="my-app-staging"
export TF_VAR_public_worker_count=1
export TF_VAR_private_worker_count=1
export TF_VAR_manager_count=1
```

### Production Environment

```bash
export TF_VAR_environment="production"
export TF_VAR_app_name="my-app-prod"
export TF_VAR_public_worker_count=3
export TF_VAR_private_worker_count=5
export TF_VAR_manager_count=3
```

---

## 📝 Variable Validation

### Built-in Validations

| Variable | Validation | Purpose |
|----------|------------|---------|
| `app_name` | Non-empty string | Ensures resource naming |
| `environment` | Must be "staging" or "production" | Environment consistency |
| `region` | Valid AWS region | Infrastructure location |

### Custom Validation Examples

```hcl
variable "public_worker_count" {
  description = "Number of public worker instances"
  type        = number
  default     = 1
  
  validation {
    condition     = var.public_worker_count >= 1
    error_message = "At least one public worker is required."
  }
}

variable "domain_name" {
  description = "Primary domain name"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}$", var.domain_name))
    error_message = "Domain name must be a valid domain format."
  }
}
```

---

## 🔍 Variable Discovery

### List All Variables

```bash
# Show all variables in the configuration
terraform variables

# Show variables with descriptions
terraform variables -json | jq '.[] | {name: .name, description: .description, type: .type}'
```

### Variable Dependencies

```bash
# Show variable dependencies
terraform graph | grep -E "(var\.|variable)"
```

---

## 📚 Related Documentation

- [Main README](./README.md) - Complete infrastructure documentation
- [Module Documentation](./MODULES.md) - Detailed module reference
- [Security Guide](./SECURITY.md) - Security best practices
- [Deployment Guide](./DEPLOYMENT.md) - Deployment procedures

---

*Last updated: $(date)* 