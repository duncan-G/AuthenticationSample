###############################################################
# Terraform configuration for AWS application infrastructure
###############################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    # Partial configuration (because variables are not allowed in backend config) -
    # bucket will be provided via command line during terraform init.
    # See .github/workflows/infrastructure-release.yml for more details.
    key     = "terraform.tfstate"
    encrypt = true
  }
}

provider "aws" {
  region = var.region
}

########################
# Variables
########################

variable "region" {
  description = "AWS region for all resources (Set via TF_VAR_region environment variable)"
  type        = string
}

variable "public_instance_type" {
  description = "EC2 instance type for the public instance"
  type        = string
  default     = "t4g.micro"
}

variable "private_instance_type" {
  description = "EC2 instance type for the private instance"
  type        = string
  default     = "t4g.small"
}

variable "app_name" {
  description = "Application name used as a prefix for resources."
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., staging, production)."
  type        = string
}

variable "deployment_bucket" {
  description = "S3 bucket name for deployment artifacts."
  type        = string
  default     = ""
}

variable "github_repository" {
  description = "GitHub repository in format 'owner/repo' for OIDC trust policy."
  type        = string
  default     = ""
}

variable "staging_environment_name" {
  description = "Staging environment name for GitHub Actions OIDC trust policy."
  type        = string
  default     = "staging"
}

variable "production_environment_name" {
  description = "Production environment name for GitHub Actions OIDC trust policy."
  type        = string
  default     = "production"
}

variable "domain_name" {
  description = "Domain name for the application (e.g., example.com)"
  type        = string

  validation {
    condition     = length(var.domain_name) > 0
    error_message = "Domain name must not be empty."
  }
}

variable "subdomains" {
  description = "Subdomains for the application (e.g., api,admin,portal)"
  type        = list(string)
}

variable "route53_hosted_zone_id" {
  description = "Route53 hosted zone ID for DNS management"
  type        = string

  validation {
    condition     = length(var.route53_hosted_zone_id) > 0
    error_message = "Route53 hosted zone ID must not be empty."
  }
}

variable "bucket_suffix" {
  description = "Suffix to make S3 bucket names unique across environments"
  type        = string
}

########################
# Data sources
########################

# aws_availability_zones: Fetches the list of Availability Zones (AZs) in the current region
# This allows us to reference AZs dynamically rather than hardcoding them
# Used when creating subnets to ensure they are placed in valid AZs
# NOTE: We will currently only deploy to 1 AZ. If High Availability is needed,
# this will need to update to use multiple AZs.

# aws_ami: Queries for the latest Amazon Linux 2023 AMI in the current region
# Filters for x86_64 architecture and only AMIs owned by Amazon
# This ensures we always get the latest patched Amazon Linux 2023 base image
# Used as the base image when launching EC2 instances

# aws_caller_identity: Fetches the current AWS account ID
# Used to dynamically reference the current account ID in IAM policies
# This ensures that the policies are applied to the correct account

########################

data "aws_availability_zones" "available" {}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name = "name"
    # Match regular AMIs only (not minimal) - regular AMIs follow pattern: al2023-ami-2023.*
    values = ["al2023-ami-2023*"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

data "aws_caller_identity" "current" {}

# Data source for existing certbot ECR repository (not managed by Terraform)
data "aws_ecr_repository" "certbot" {
  name = "${var.app_name}/certbot"
}

########################
# Networking
########################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "${var.app_name}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.app_name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "${var.app_name}-public-subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "${var.app_name}-private-subnet"
  }
}

# Public routing
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.app_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Private route table with NAT
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${var.app_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags = {
    Name = "${var.app_name}-nat-eip"
  }
}

# NAT Gateway in the public subnet
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.igw]
  tags = {
    Name = "${var.app_name}-nat-gateway"
  }
}

########################
# Security group
########################

resource "aws_security_group" "instance" {
  name_prefix = "${var.app_name}-instance-sg-"
  description = "Allow HTTP, HTTPS, and Docker Swarm communication"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Docker Swarm communication within VPC
  ingress {
    description = "Docker Swarm Management"
    from_port   = 2377
    to_port     = 2377
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Docker Swarm Node Communication TCP"
    from_port   = 7946
    to_port     = 7946
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Docker Swarm Node Communication UDP"
    from_port   = 7946
    to_port     = 7946
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Docker Overlay Network"
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-instance-sg"
  }
}

########################
# IAM Roles for EC2 Instances
########################

# Public Instance Role (Web server, public-facing)
resource "aws_iam_role" "public_instance_role" {
  name = "${var.app_name}-ec2-public-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-ec2-public-instance-role"
    Environment = var.environment
    Tier        = "public"
  }
}

# Private Instance Role (Backend services, database access)
resource "aws_iam_role" "private_instance_role" {
  name = "${var.app_name}-ec2-private-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-ec2-private-instance-role"
    Environment = var.environment
    Tier        = "private"
  }
}

# Policy Attachments for Public Instance
resource "aws_iam_role_policy_attachment" "public_session_manager" {
  role       = aws_iam_role.public_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "public_cloudwatch_agent" {
  role       = aws_iam_role.public_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Combined policy for worker instance consolidating ECR pull, SSM parameters, Secrets Manager, S3 certificates, Route53, and EBS permissions
resource "aws_iam_policy" "public_worker_core" {
  name        = "${var.app_name}-worker-core-access"
  description = "Combined core permissions for worker EC2 instance"

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
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/docker/swarm/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.app_name}-secrets*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumeStatus",
          "ec2:DescribeInstances",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:CreateVolume",
          "ec2:DeleteVolume"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-worker-core-access"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "public_worker_core" {
  role       = aws_iam_role.public_instance_role.name
  policy_arn = aws_iam_policy.public_worker_core.arn
}

# Policy Attachments for Private Instance
resource "aws_iam_role_policy_attachment" "private_session_manager" {
  role       = aws_iam_role.private_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "private_cloudwatch_agent" {
  role       = aws_iam_role.private_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Combined policy for manager instance consolidating ECR pull, EC2 describe, SSM send command permissions
resource "aws_iam_policy" "private_manager_core" {
  name        = "${var.app_name}-manager-core-access"
  description = "Combined core permissions for manager EC2 instance"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation",
          "ssm:UpdateInstanceInformation",
          "ssm:DescribeInstanceAssociationsStatus",
          "ssm:DescribeEffectiveInstanceAssociations"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/docker/swarm/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.app_name}-secrets*"
        ]
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-manager-core-access"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "private_manager_core" {
  role       = aws_iam_role.private_instance_role.name
  policy_arn = aws_iam_policy.private_manager_core.arn
}


# Instance Profiles
resource "aws_iam_instance_profile" "public_instance_profile" {
  name = "${var.app_name}-ec2-public-instance-profile"
  role = aws_iam_role.public_instance_role.name
}

resource "aws_iam_instance_profile" "private_instance_profile" {
  name = "${var.app_name}-ec2-private-instance-profile"
  role = aws_iam_role.private_instance_role.name
}

########################
# CloudWatch Log Groups for Docker Setup Scripts
########################

# CloudWatch Log Groups for Docker setup scripts (consolidated)
resource "aws_cloudwatch_log_group" "docker_manager" {
  name              = "/aws/ec2/${var.app_name}-docker-manager"
  retention_in_days = 30

  tags = {
    Name        = "${var.app_name}-docker-manager-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "docker_worker" {
  name              = "/aws/ec2/${var.app_name}-docker-worker"
  retention_in_days = 30

  tags = {
    Name        = "${var.app_name}-docker-worker-logs"
    Environment = var.environment
  }
}

########################
# CloudWatch Agent Configuration
########################

# CloudWatch agent configuration using templatefile() function
locals {
  cloudwatch_agent_config_manager = templatefile("${path.module}/cloudwatch-agent-config.json", {
    app_name      = var.app_name
    instance_type = "manager"
  })

  cloudwatch_agent_config_worker = templatefile("${path.module}/cloudwatch-agent-config.json", {
    app_name      = var.app_name
    instance_type = "worker"
  })
}

########################
# EC2 instances
########################

resource "aws_instance" "public" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.public_instance_type
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.instance.id]
  iam_instance_profile        = aws_iam_instance_profile.public_instance_profile.name

  tags = {
    Name        = "${var.app_name}-public-instance-worker"
    Environment = var.environment
    Tier        = "public"
  }

  depends_on = [
    aws_iam_instance_profile.public_instance_profile,
    aws_iam_role_policy_attachment.public_session_manager,
    aws_iam_role_policy_attachment.public_cloudwatch_agent,
    aws_iam_role_policy_attachment.public_worker_core
  ]
}

resource "aws_instance" "private" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.private_instance_type
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.instance.id]
  iam_instance_profile        = aws_iam_instance_profile.private_instance_profile.name

  tags = {
    Name        = "${var.app_name}-private-instance-manager"
    Environment = var.environment
    Tier        = "private"
  }

  depends_on = [
    aws_iam_instance_profile.private_instance_profile,
    aws_iam_role_policy_attachment.private_session_manager,
    aws_iam_role_policy_attachment.private_cloudwatch_agent,
    aws_iam_role_policy_attachment.private_manager_core
  ]
}



########################
# Outputs
########################

output "public_instance_ip" {
  value       = aws_instance.public.public_ip
  description = "Public IP of the public subnet instance"
}

output "private_instance_ip" {
  value       = aws_instance.private.private_ip
  description = "Private IP of the private subnet instance"
}


