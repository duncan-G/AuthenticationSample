# 📚 Terraform Modules Documentation

This document provides detailed information about each module in the Terraform configuration.

---

## 📋 Table of Contents

- [Core Infrastructure (`main.tf`)](#core-infrastructure-maintf)
- [Authentication (`cognito.tf`)](#authentication-cognitotf)
- [Certificate Management (`certificates.tf`)](#certificate-management-certificatestf)
- [Deployment Automation (`codedeploy.tf`)](#deployment-automation-codedeploytf)
- [DNS Management (`route53.tf`)](#dns-management-route53tf)
- [CI/CD Integration](#cicd-integration)
- [Monitoring (`otel-cloudwatch.tf`)](#monitoring-otel-cloudwatchtf)
- [Scripts & Automation (`scripts.tf`)](#scripts--automation-scriptstf)

---

## 🏗️ Core Infrastructure (`main.tf`)

### Purpose
Provisions the foundational AWS infrastructure including VPC, EC2 instances, security groups, and IAM roles for the Docker Swarm cluster.

### Key Resources

#### Networking
```hcl
# VPC with public and private subnets
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# Public subnet for load balancers
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.this.names[0]
}

# Private subnet for application servers
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.this.names[1]
}
```

#### Compute Resources
```hcl
# Public worker instances (load balancers)
resource "aws_instance" "public_workers" {
  count = var.public_worker_count
  
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.public_worker_instance_type
  subnet_id     = aws_subnet.public.id
  
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.public.name
}

# Private worker instances (application servers)
resource "aws_instance" "private_workers" {
  count = var.private_worker_count
  
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.private_worker_instance_type
  subnet_id     = aws_subnet.private.id
  
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.private.name
}

# Manager instances (Docker Swarm managers)
resource "aws_instance" "managers" {
  count = var.manager_count
  
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.manager_instance_type
  subnet_id     = aws_subnet.private.id
  
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.manager.name
}
```

#### Security Groups
```hcl
# Main security group for all instances
resource "aws_security_group" "instance" {
  name_prefix = "${var.app_name}-instance-"
  vpc_id      = aws_vpc.main.id
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# HTTP access
resource "aws_security_group_rule" "http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.instance.id
}

# HTTPS access
resource "aws_security_group_rule" "https_tcp" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.instance.id
}

# Docker Swarm communication
resource "aws_security_group_rule" "docker_swarm" {
  type              = "ingress"
  from_port         = 2377
  to_port           = 2377
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.instance.id
}
```

#### IAM Roles and Policies
```hcl
# Public worker role
resource "aws_iam_role" "public" {
  name = "${var.app_name}-public-worker-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Core worker policy
resource "aws_iam_policy" "worker_core" {
  name = "${var.app_name}-worker-core-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/aws/ec2/${var.app_name}*"
      }
    ]
  })
}
```

### Outputs
```hcl
output "public_worker_ips" {
  description = "Public IP addresses of worker instances"
  value       = aws_instance.public_workers[*].public_ip
}

output "private_worker_ips" {
  description = "Private IP addresses of worker instances"
  value       = aws_instance.private_workers[*].private_ip
}

output "manager_ips" {
  description = "Private IP addresses of manager instances"
  value       = aws_instance.managers[*].private_ip
}
```

---

## 🔐 Authentication (`cognito.tf`)

### Purpose
Manages AWS Cognito User Pool for user authentication, including social login providers and email configuration.

### Key Resources

#### SES Email Configuration
```hcl
# SES domain identity for email sending
resource "aws_ses_domain_identity" "this" {
  domain = var.domain_name
}

# Domain verification record
resource "aws_route53_record" "ses_verification" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = "_amazonses.${aws_ses_domain_identity.this.domain}"
  type    = "TXT"
  ttl     = 600
  records = [aws_ses_domain_identity.this.verification_token]
}

# DKIM configuration
resource "aws_ses_domain_dkim" "this" {
  domain = aws_ses_domain_identity.this.domain
}

# DKIM records
resource "aws_route53_record" "dkim" {
  count   = 3
  zone_id = data.aws_route53_zone.this.zone_id
  name    = "${aws_ses_domain_dkim.this.dkim_tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_ses_domain_dkim.this.dkim_tokens[count.index]}.dkim.amazonses.com"]
}
```

#### Cognito User Pool
```hcl
# Main user pool
resource "aws_cognito_user_pool" "this" {
  name = "${var.app_name}-user-pool-${var.environment}"
  
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = false
  }
  
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
  
  email_configuration {
    email_sending_account = "DEVELOPER"
    from_email_address    = "no-reply@${var.domain_name}"
    source_arn            = aws_ses_domain_identity.this.arn
  }
  
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your ${var.app_name} verification code"
    email_message        = "Your verification code is {####}"
  }
}
```

#### Identity Providers
```hcl
# Google OAuth provider
resource "aws_cognito_user_pool_identity_provider" "google" {
  for_each = var.idps
  
  user_pool_id = aws_cognito_user_pool.this.id
  provider_name = each.key
  provider_type = "Google"
  
  provider_details = {
    client_id        = each.value.client_id
    client_secret    = each.value.client_secret
    authorize_scopes = each.value.scopes
  }
  
  attribute_mapping = {
    email    = "email"
    username = "sub"
    name     = "name"
  }
}

# User pool client
resource "aws_cognito_user_pool_client" "this" {
  name         = "${var.app_name}-client-${var.environment}"
  user_pool_id = aws_cognito_user_pool.this.id
  
  generate_secret = false
  
  callback_urls = [var.auth_callback]
  logout_urls   = ["https://${var.domain_name}"]
  
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["phone", "email", "openid", "profile"]
  
  supported_identity_providers = concat(
    ["COGNITO"],
    [for k, _ in var.idps : upper(k)]
  )
}
```

### Outputs
```hcl
output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_client_id" {
  description = "Cognito User Pool Client ID"
  value       = aws_cognito_user_pool_client.this.id
}

output "user_pool_domain" {
  description = "Cognito User Pool Domain"
  value       = aws_cognito_user_pool_domain.this.domain
}
```

---

## 🔒 Certificate Management (`certificates.tf`)

### Purpose
Manages SSL certificates with automated renewal using Let's Encrypt and certbot.

### Key Resources

#### Certificate Storage
```hcl
# S3 bucket for certificate storage
locals {
  certificate_bucket_name = "${var.app_name}-certificate-store-${var.bucket_suffix}"
  certificate_bucket_arn  = "arn:aws:s3:::${local.certificate_bucket_name}"
}

# IAM policy for certificate bucket access
resource "aws_iam_policy" "ssl_certificates_bucket_access_policy" {
  name = "${var.app_name}-certificate-store-bucket-access"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        local.certificate_bucket_arn,
        "${local.certificate_bucket_arn}/*"
      ]
    }]
  })
}
```

#### Certbot Integration
```hcl
# IAM policy for Route53 DNS challenges
resource "aws_iam_policy" "certbot_route53_dns_challenge_policy" {
  name = "${var.app_name}-certbot-route53-dns-challenge"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "route53:GetChange",
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets"
      ]
      Resource = [
        "arn:aws:route53:::change/*",
        "arn:aws:route53:::hostedzone/${var.route53_hosted_zone_id}"
      ]
    }]
  })
}

# EBS volume for certificate persistence
resource "aws_volume_attachment" "certbot_ebs_attachment" {
  device_name = "/dev/sdf"
  volume_id   = var.certbot_ebs_volume_id
  instance_id = aws_instance.public_workers[0].id
}
```

#### Secrets Management
```hcl
# Secrets for certificate renewal
resource "aws_secretsmanager_secret" "certificate_renewal" {
  name = "${var.app_name}-certificate-renewal-${var.environment}"
  
  description = "Secrets for certificate renewal automation"
  
  tags = {
    Name        = "${var.app_name}-certificate-renewal"
    Environment = var.environment
  }
}

# Secret for certificate renewal trigger
resource "aws_secretsmanager_secret_version" "certificate_renewal" {
  secret_id = aws_secretsmanager_secret.certificate_renewal.id
  
  secret_string = jsonencode({
    domain_name = var.domain_name
    email       = "admin@${var.domain_name}"
    staging     = var.environment == "staging"
  })
}
```

### Outputs
```hcl
output "ssl_certificates_bucket_name" {
  description = "S3 bucket name for SSL certificates"
  value       = local.certificate_bucket_name
}

output "certificate_renewal_secret_name" {
  description = "Secrets Manager secret name for certificate renewal"
  value       = aws_secretsmanager_secret.certificate_renewal.name
}

output "certbot_ebs_attachment_status" {
  description = "Status of EBS volume attachment for certbot"
  value       = aws_volume_attachment.certbot_ebs_attachment.attachment_id
}
```

---

## 🚀 Deployment Automation (`codedeploy.tf`)

### Purpose
Automates deployment of microservices to the Docker Swarm cluster using AWS CodeDeploy.

### Key Resources

#### CodeDeploy Applications
```hcl
# CodeDeploy applications for each microservice
resource "aws_codedeploy_app" "microservices" {
  for_each = toset(["authentication", "envoy", "otel-collector"])
  
  name = "${var.app_name}-${each.key}-${var.environment}"
  
  compute_platform = "Server"
  
  tags = {
    Name        = "${var.app_name}-${each.key}-${var.environment}"
    Environment = var.environment
    Service     = each.key
  }
}
```

#### Deployment Groups
```hcl
# Deployment groups for each microservice
resource "aws_codedeploy_deployment_group" "microservices" {
  for_each = toset(["authentication", "envoy", "otel-collector"])
  
  app_name              = aws_codedeploy_app.microservices[each.key].name
  deployment_group_name = "${var.app_name}-${each.key}-${var.environment}-deployment-group"
  service_role_arn      = aws_iam_role.codedeploy_service_role.arn
  
  deployment_config_name = "CodeDeployDefault.OneAtATime"
  
  # Target manager and private tier instances
  ec2_tag_set {
    ec2_tag_filter {
      key   = "Environment"
      type  = "KEY_AND_VALUE"
      value = var.environment
    }
  }
  
  ec2_tag_set {
    ec2_tag_filter {
      key   = "Tier"
      type  = "KEY_AND_VALUE"
      value = "private"
    }
  }
}
```

#### IAM Roles
```hcl
# CodeDeploy service role
resource "aws_iam_role" "codedeploy_service_role" {
  name = "${var.app_name}-codedeploy-service-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "codedeploy.amazonaws.com"
      }
    }]
  })
}

# EC2 instance role for CodeDeploy
resource "aws_iam_role" "ec2_codedeploy_role" {
  name = "${var.app_name}-ec2-codedeploy-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# CodeDeploy policy for EC2 instances
resource "aws_iam_policy" "ec2_codedeploy_policy" {
  name = "${var.app_name}-ec2-codedeploy-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = [
          "arn:aws:s3:::${var.deployment_bucket}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/aws/codedeploy/*"
      }
    ]
  })
}
```

### Outputs
```hcl
output "codedeploy_bucket_name" {
  description = "S3 bucket name for CodeDeploy artifacts"
  value       = var.deployment_bucket
}

output "codedeploy_app_names" {
  description = "Names of CodeDeploy applications"
  value       = [for app in aws_codedeploy_app.microservices : app.name]
}
```

---

## 🌐 DNS Management (`route53.tf`)

### Purpose
Manages DNS records for the application domain and subdomains.

### Key Resources

#### Domain Records
```hcl
# Main domain A record
resource "aws_route53_record" "main_domain" {
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = "300"
  
  records = [aws_instance.public_workers[0].public_ip]
}

# Main domain AAAA record (IPv6)
resource "aws_route53_record" "main_domain_ipv6" {
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "AAAA"
  ttl     = "300"
  
  records = aws_instance.public_workers[0].ipv6_addresses
}
```

#### Subdomain Records
```hcl
# A records for subdomains
resource "aws_route53_record" "subdomains" {
  for_each = toset(var.subdomains)
  
  zone_id = local.hosted_zone_id
  name    = "${each.value}.${var.domain_name}"
  type    = "A"
  ttl     = "300"
  
  records = [aws_instance.public_workers[0].public_ip]
}

# AAAA records for subdomains (IPv6)
resource "aws_route53_record" "subdomains_ipv6" {
  for_each = toset(var.subdomains)
  
  zone_id = local.hosted_zone_id
  name    = "${each.value}.${var.domain_name}"
  type    = "AAAA"
  ttl     = "300"
  
  records = aws_instance.public_workers[0].ipv6_addresses
}
```

#### Email Records
```hcl
# SPF record for email authentication
resource "aws_route53_record" "spf" {
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = "300"
  
  records = [
    "v=spf1 include:_spf.google.com ~all"
  ]
}

# CNAME for www subdomain
resource "aws_route53_record" "www_subdomain" {
  zone_id = local.hosted_zone_id
  name    = "www.${var.domain_name}"
  type    = "CNAME"
  ttl     = "300"
  
  records = [var.domain_name]
}
```

### Outputs
```hcl
output "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  value       = local.hosted_zone_id
}

output "main_domain_url" {
  description = "Main domain URL"
  value       = "https://${var.domain_name}"
}

output "subdomain_urls" {
  description = "Subdomain URLs"
  value       = [for subdomain in var.subdomains : "https://${subdomain}.${var.domain_name}"]
}
```

---

## 🔄 CI/CD Integration

### GitHub Actions (`github-actions-certbot.tf`)

#### Purpose
Provides IAM roles and policies for GitHub Actions to manage certificates and build Docker images.

#### Key Resources
```hcl
# GitHub Actions OIDC role for certbot
resource "aws_iam_role" "github_actions_certbot" {
  name = "${var.app_name}-github-actions-role-certbot"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
      }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringEquals = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.github_repository}:environment:${var.staging_environment_name}",
            "repo:${var.github_repository}:environment:${var.production_environment_name}"
          ]
        }
      }
    }]
  })
}

# Policy for certbot workflow
resource "aws_iam_policy" "github_actions_certbot_policy" {
  name = "${var.app_name}-github-actions-policy-certbot"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuthorizationToken"
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRRepositoryAccess"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = ["arn:aws:ecr:*:*:repository/${var.app_name}*"]
      },
      {
        Sid    = "S3CertbotArtifactsAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.app_name}-certbot-${var.bucket_suffix}",
          "arn:aws:s3:::${var.app_name}-certbot-${var.bucket_suffix}/*"
        ]
      }
    ]
  })
}
```

### Vercel Integration (`vercel.tf`)

#### Purpose
Configures Vercel for frontend deployment with automatic deployments from GitHub.

#### Key Resources
```hcl
# Vercel project for frontend
resource "vercel_project" "frontend" {
  name      = var.app_name
  framework = "nextjs"
  
  git_repository = {
    type = "github"
    repo = var.github_repository
  }
  
  root_directory = var.vercel_root_directory
  
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
}
```

---

## 📊 Monitoring (`otel-cloudwatch.tf`)

### Purpose
Configures OpenTelemetry for comprehensive monitoring and observability.

### Key Resources

#### IAM Roles for OpenTelemetry
```hcl
# OpenTelemetry collector role
resource "aws_iam_role" "otel_collector_role" {
  name = "${var.app_name}-otel-collector-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# CloudWatch policy for OpenTelemetry
resource "aws_iam_policy" "otel_collector_cloudwatch_policy" {
  name = "${var.app_name}-otel-collector-cloudwatch-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = [
        "arn:aws:logs:*:*:log-group:/aws/otel/*",
        "arn:aws:logs:*:*:log-group:/aws/otel/*:*"
      ]
    }]
  })
}

# X-Ray policy for OpenTelemetry
resource "aws_iam_policy" "otel_collector_xray_policy" {
  name = "${var.app_name}-otel-collector-xray-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords"
      ]
      Resource = "*"
    }]
  })
}
```

#### Instance Profile
```hcl
# Instance profile for OpenTelemetry
resource "aws_iam_instance_profile" "otel_collector_instance_profile" {
  name = "${var.app_name}-otel-collector-instance-profile"
  role = aws_iam_role.otel_collector_role.name
}
```

---

## 🤖 Scripts & Automation (`scripts.tf`)

### Purpose
Manages SSM documents and automation scripts for Docker Swarm setup and certificate management.

### Key Resources

#### SSM Documents
```hcl
# Docker manager setup document
resource "aws_ssm_document" "docker_manager_setup" {
  name            = "${var.app_name}-docker-manager-setup"
  document_type   = "Command"
  document_format = "JSON"
  
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Bootstrap Docker Swarm manager"
    mainSteps = [{
      name   = "RunManagerSetup"
      action = "aws:runShellScript"
      inputs = {
        runCommand = [
          "cat <<'EOF' > /tmp/install-docker-manager.sh",
          "${indent(2, file("${path.module}/../install-docker-manager.sh"))}",
          "EOF",
          "chmod +x /tmp/install-docker-manager.sh",
          "/tmp/install-docker-manager.sh"
        ]
        timeoutSeconds = "1800"
      }
    }]
  })
}

# Certificate manager setup document
resource "aws_ssm_document" "certificate_manager_setup" {
  name            = "${var.app_name}-certificate-manager-setup"
  document_type   = "Command"
  document_format = "JSON"
  
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install and configure certificate manager daemon service"
    mainSteps = [{
      name   = "InstallCertificateManager"
      action = "aws:runShellScript"
      inputs = {
        runCommand = [
          "cat <<'EOF' > /etc/systemd/system/certificate-manager.service",
          "${indent(2, file("${path.module}/../../certbot/certificate-manager.service"))}",
          "EOF",
          "systemctl daemon-reload",
          "systemctl enable certificate-manager.service",
          "systemctl start certificate-manager.service"
        ]
        timeoutSeconds = "600"
      }
    }]
  })
}
```

#### SSM Associations
```hcl
# Associate manager setup with manager instances
resource "aws_ssm_association" "docker_manager_setup" {
  name = aws_ssm_document.docker_manager_setup.name
  
  targets {
    key    = "tag:Name"
    values = ["${var.app_name}-manager-${var.environment}"]
  }
}

# Associate certificate manager with public instances
resource "aws_ssm_association" "certificate_manager_setup" {
  name = aws_ssm_document.certificate_manager_setup.name
  
  targets {
    key    = "tag:Name"
    values = ["${var.app_name}-public-worker-${var.environment}"]
  }
}
```

#### SSM Parameters
```hcl
# Docker Swarm worker token
resource "aws_ssm_parameter" "docker_swarm_worker_token" {
  name  = "/${var.app_name}/${var.environment}/docker-swarm-worker-token"
  type  = "SecureString"
  value = "placeholder"  # Will be updated by manager setup script
}

# Docker Swarm manager IP
resource "aws_ssm_parameter" "docker_swarm_manager_ip" {
  name  = "/${var.app_name}/${var.environment}/docker-swarm-manager-ip"
  type  = "String"
  value = "placeholder"  # Will be updated by manager setup script
}

# Docker Swarm network name
resource "aws_ssm_parameter" "docker_swarm_network_name" {
  name  = "/${var.app_name}/${var.environment}/docker-swarm-network-name"
  type  = "String"
  value = "${var.app_name}-overlay-network"
}
```

---

## 📚 Related Documentation

- [Main README](./README.md) - Complete infrastructure documentation
- [Variables Reference](./VARIABLES.md) - All variables with descriptions
- [Security Guide](./SECURITY.md) - Security best practices
- [Deployment Guide](./DEPLOYMENT.md) - Deployment procedures

---

*Last updated: $(date)* 