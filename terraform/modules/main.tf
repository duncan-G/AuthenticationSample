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
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

provider "aws" {
  region = var.region
}

########################
# Variables
########################

variable "region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-1"
}

variable "public_instance_type" {
  description = "EC2 instance type for the public instance"
  type        = string
  default     = "t3.micro"
}

variable "private_instance_type" {
  description = "EC2 instance type for the private instance"
  type        = string
  default     = "t4g.small"
}

########################
# Data sources
# aws_availability_zones: Fetches the list of Availability Zones (AZs) in the current region
# This allows us to reference AZs dynamically rather than hardcoding them
# Used when creating subnets to ensure they are placed in valid AZs

# aws_ami: Queries for the latest Amazon Linux 2023 AMI in the current region
# Filters for x86_64 architecture and only AMIs owned by Amazon
# This ensures we always get the latest patched Amazon Linux 2023 base image
# Used as the base image when launching EC2 instances

########################

data "aws_availability_zones" "available" {}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64-*"]
  }
}

########################
# Networking
########################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "main-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "public-subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "private-subnet"
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
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Private subnet uses default VPC route table (no internet access)

########################
# Security group
########################

resource "aws_security_group" "instance" {
  name_prefix = "instance-sg-"
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
    Name = "instance-sg"
  }
}

########################
# IAM Roles for EC2 Instances
########################

# Public Instance Role (Web server, public-facing)
resource "aws_iam_role" "public_instance_role" {
  name = "EC2-Public-Instance-Role"

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
    Name        = "EC2-Public-Instance-Role"
    Environment = "public"
  }
}

# Private Instance Role (Backend services, database access)
resource "aws_iam_role" "private_instance_role" {
  name = "EC2-Private-Instance-Role"

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
    Name        = "EC2-Private-Instance-Role"
    Environment = "private"
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


# Custom policy for public instance to read Docker swarm SSM parameters
resource "aws_iam_policy" "public_ssm_docker_access" {
  name        = "PublicInstanceDockerSSMAccess"
  description = "Allow read access to Docker swarm SSM parameters for public instance"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:${var.region}:*:parameter/docker/swarm/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "public_ssm_docker_access" {
  role       = aws_iam_role.public_instance_role.name
  policy_arn = aws_iam_policy.public_ssm_docker_access.arn
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

# Custom policy for private instance to write Docker swarm SSM parameters
resource "aws_iam_policy" "private_ssm_docker_access" {
  name        = "PrivateInstanceDockerSSMAccess"
  description = "Allow write access to Docker swarm SSM parameters for private instance"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:${var.region}:*:parameter/docker/swarm/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "private_ssm_docker_access" {
  role       = aws_iam_role.private_instance_role.name
  policy_arn = aws_iam_policy.private_ssm_docker_access.arn
}

# Instance Profiles
resource "aws_iam_instance_profile" "public_instance_profile" {
  name = "EC2-Public-Instance-Profile"
  role = aws_iam_role.public_instance_role.name
}

resource "aws_iam_instance_profile" "private_instance_profile" {
  name = "EC2-Private-Instance-Profile"
  role = aws_iam_role.private_instance_role.name
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

  user_data = file("${path.module}/../install-docker-worker.sh")

  tags = {
    Name        = "public-instance-worker"
    Environment = "public"
  }
}

resource "aws_instance" "private" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.private_instance_type
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.instance.id]
  iam_instance_profile        = aws_iam_instance_profile.private_instance_profile.name

  user_data = file("${path.module}/../install-docker-manager.sh")

  tags = {
    Name        = "private-instance-manager"
    Environment = "private"
  }
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
