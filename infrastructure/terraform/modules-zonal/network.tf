# =============================================================================
# Network Infrastructure
# =============================================================================
# This file manages all network infrastructure components:
# 
# • VPC with IPv4 and IPv6 support
# • Public and private subnets
# • Internet Gateway for external connectivity
# • Route tables and associations
# • Network configuration for Docker Swarm
# 
# Network Design:
# - VPC: 10.0.0.0/16 with IPv6 support
# - Public Subnet: 10.0.1.0/24 (for public workers, load balancers)
# - Private Subnet: 10.0.2.0/24 (for private workers, managers, databases)
# =============================================================================

#region Resources

# Main VPC with dual-stack IPv4/IPv6 support
resource "aws_vpc" "main" {
  cidr_block                       = "10.0.0.0/16"
  assign_generated_ipv6_cidr_block = true
  enable_dns_hostnames             = true
  enable_dns_support               = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.env
    Purpose     = "Main VPC for Docker Swarm infrastructure"
  }
}

# Internet Gateway for external connectivity
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.env
    Purpose     = "Internet Gateway for public access"
  }
}

# Public subnet for external-facing resources
resource "aws_subnet" "public" {
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = "10.0.1.0/24"
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 1)
  map_public_ip_on_launch         = true
  assign_ipv6_address_on_creation = true
  availability_zone               = data.aws_availability_zones.this.names[0]

  tags = {
    Name        = "${var.project_name}-public-subnet"
    Environment = var.env
    Type        = "public"
    Purpose     = "Public subnet for external-facing resources"
  }
}

# Private subnet for internal resources
resource "aws_subnet" "private" {
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = "10.0.2.0/24"
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 2)
  assign_ipv6_address_on_creation = true
  availability_zone               = data.aws_availability_zones.this.names[0]

  tags = {
    Name        = "${var.project_name}-private-subnet"
    Environment = var.env
    Type        = "private"
    Purpose     = "Private subnet for internal resources"
  }
}

# Public route table with internet access
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # IPv4 route to internet
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  # IPv6 route to internet
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.this.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.env
    Type        = "public"
    Purpose     = "Public route table with internet access"
  }
}

# Private route table with IPv6 internet access (no NAT needed for IPv6)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # IPv6 egress via IGW (no NAT needed for IPv6)
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.this.id
  }

  tags = {
    Name        = "${var.project_name}-private-rt"
    Environment = var.env
    Type        = "private"
    Purpose     = "Private route table with IPv6 internet access"
  }
}

# Associate public subnet with public route table
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Associate private subnet with private route table
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

#endregion

#region Outputs

# Only outputs that are actually used by other modules
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_ipv6_cidr_block" {
  description = "IPv6 CIDR block of the VPC"
  value       = aws_vpc.main.ipv6_cidr_block
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private.id
}

#endregion