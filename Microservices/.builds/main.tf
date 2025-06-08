###############################################################
# Terraform configuration for AWS application infrastructure
###############################################################

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
} 

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "key_name" {
  description = "Name of the EC2 key pair for SSH"
  type        = string
}

###############################################################
# Networking
###############################################################

data "aws_availability_zones" "available" {}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "app-vpc"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "app-gw"
  }
}

# Public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

# Private subnet
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "private-subnet"
  }
}

# Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

###############################################################
# Security groups
###############################################################
resource "aws_security_group" "public_sg" {
  name        = "public-ec2-sg"
  description = "Allow SSH (22), HTTP (80), and HTTPS (443)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "public-ec2-sg"
  }
}

resource "aws_security_group" "private_sg" {
  name        = "private-ec2-sg"
  description = "Allow SSH from within VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "private-ec2-sg"
  }
}

###############################################################
# ECR Repositories (two)
###############################################################
resource "aws_ecr_repository" "service" {
  count = 2
  name  = "service-${count.index + 1}"
  image_tag_mutability = "MUTABLE"

  tags = {
    Name = "service-${count.index + 1}"
  }
}

###############################################################
# Secrets Manager
###############################################################
resource "aws_secretsmanager_secret" "app_secret" {
  name = "app/secret"
  recovery_window_in_days = 0
}

###############################################################
# IAM roles & policies
###############################################################

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# Private EC2 role with permission to read secret
resource "aws_iam_role" "private_ec2_role" {
  name               = "private-ec2-secret-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_policy" "secret_reader" {
  name = "secret-reader-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["secretsmanager:GetSecretValue"],
        Effect   = "Allow",
        Resource = aws_secretsmanager_secret.app_secret.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "private_secret_attach" {
  role       = aws_iam_role.private_ec2_role.name
  policy_arn = aws_iam_policy.secret_reader.arn
}

resource "aws_iam_instance_profile" "private_profile" {
  name = "private-instance-profile"
  role = aws_iam_role.private_ec2_role.name
}

###############################################################
# AMI lookup (Amazon Linux 2023)
###############################################################

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

###############################################################
# EC2 instances
###############################################################
resource "aws_instance" "public_ec2" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.public_sg.id]
  key_name                    = var.key_name

  tags = {
    Name = "public-ec2"
  }
}

resource "aws_instance" "private_ec2" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.private_sg.id]
  key_name                    = var.key_name
  iam_instance_profile        = aws_iam_instance_profile.private_profile.name

  tags = {
    Name = "private-ec2"
  }
}

###############################################################
# Deployment pipeline scaffold (CodePipeline + CodeBuild + CodeDeploy)
###############################################################
# Random string for unique bucket name
resource "random_string" "suffix" {
  length  = 8
  special = false
}

# S3 bucket for pipeline artifacts
resource "aws_s3_bucket" "artifacts" {
  bucket        = "app-artifacts-${random_string.suffix.result}"
  force_destroy = true
}

# CodeCommit repository (source)
resource "aws_codecommit_repository" "src_repo" {
  repository_name = "app-src"
  description     = "Source repository for application"
}

# IAM role for CodePipeline
data "aws_iam_policy_document" "codepipeline_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name               = "codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume.json
}

resource "aws_iam_role_policy_attachment" "codepipeline_full_access" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodePipelineFullAccess"
}

# IAM role for CodeBuild
data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "codebuild_role" {
  name               = "codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
}

resource "aws_iam_role_policy_attachment" "codebuild_admin" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# CodeBuild project
resource "aws_codebuild_project" "build" {
  name         = "app-build"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true # needed for Docker builds
  }

  source {
    type            = "CODECOMMIT"
    location        = aws_codecommit_repository.src_repo.clone_url_http
    buildspec       = "buildspec.yml"
  }
}

# IAM role for CodeDeploy
data "aws_iam_policy_document" "codedeploy_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["codedeploy.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "codedeploy_role" {
  name               = "codedeploy-role"
  assume_role_policy = data.aws_iam_policy_document.codedeploy_assume.json
}

resource "aws_iam_role_policy_attachment" "codedeploy_full" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

# CodeDeploy application
resource "aws_codedeploy_app" "app" {
  name              = "ec2-app"
  compute_platform  = "Server"
}

# Deployment group targeting public EC2 instance
resource "aws_codedeploy_deployment_group" "ec2_group" {
  app_name              = aws_codedeploy_app.app.name
  deployment_group_name = "ec2-group"
  service_role_arn      = aws_iam_role.codedeploy_role.arn

  ec2_tag_set {
    ec2_tag_filter {
      key   = "Name"
      type  = "KEY_AND_VALUE"
      value = "public-ec2"
    }
  }

  deployment_style {
    deployment_option = "WITHOUT_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }
}

# CodePipeline
resource "aws_codepipeline" "pipeline" {
  name     = "ec2-deploy-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artifacts.bucket
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        RepositoryName = aws_codecommit_repository.src_repo.repository_name
        BranchName     = "main"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      input_artifacts = ["build_output"]
      version         = "1"

      configuration = {
        ApplicationName     = aws_codedeploy_app.app.name
        DeploymentGroupName = aws_codedeploy_deployment_group.ec2_group.deployment_group_name
      }
    }
  }
}

###############################################################
# Outputs
###############################################################

output "public_instance_public_ip" {
  description = "Public IP of the public EC2 instance"
  value       = aws_instance.public_ec2.public_ip
}

output "private_instance_id" {
  description = "Instance ID of the private EC2 instance"
  value       = aws_instance.private_ec2.id
} 