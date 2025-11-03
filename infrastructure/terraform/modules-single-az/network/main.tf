# =============================================================================
# Network Infrastructure
# =============================================================================
# VPC with dual-stack IPv4/IPv6, one public subnet (workers, NLB) and one
# private subnet (managers, internal workloads), with IGW and route tables.
# =============================================================================

#region Resources

# Current region and EC2 Instance Connect IP ranges
data "aws_region" "current" {}

data "aws_ec2_managed_prefix_list" "ec2_instance_connect_v6" {
  name = "com.amazonaws.${data.aws_region.current.id}.ipv6.ec2-instance-connect"
}

# Main VPC with dual-stack IPv4/IPv6 support
resource "aws_vpc" "main" {
  cidr_block                       = "10.0.0.0/16"
  assign_generated_ipv6_cidr_block = true
  enable_dns_hostnames             = true
  enable_dns_support               = true

  tags = {
    Name        = "${var.project_name}-vpc-${var.env}"
    Environment = var.env
    Purpose     = "Main VPC for Docker Swarm infrastructure"
  }
}

# Internet Gateway for external connectivity
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw-${var.env}"
    Environment = var.env
    Purpose     = "Internet Gateway for public access"
  }
}

# NAT Gateway for IPv4 egress from private subnet
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name        = "${var.project_name}-nat-eip-${var.env}"
    Environment = var.env
    Purpose     = "Elastic IP for NAT Gateway"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name        = "${var.project_name}-nat-${var.env}"
    Environment = var.env
    Purpose     = "NAT Gateway for private subnet IPv4 egress"
  }

  depends_on = [aws_internet_gateway.this]
}

# Public subnet for external-facing resources
resource "aws_subnet" "public" {
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = "10.0.1.0/24"
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 1)
  map_public_ip_on_launch         = true
  assign_ipv6_address_on_creation = true
  availability_zone               = var.availability_zone

  tags = {
    Name        = "${var.project_name}-public-subnet-${var.env}"
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
  availability_zone               = var.availability_zone

  tags = {
    Name        = "${var.project_name}-private-subnet-${var.env}"
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
    Name        = "${var.project_name}-public-rt-${var.env}"
    Environment = var.env
    Type        = "public"
    Purpose     = "Public route table with internet access"
  }
}

# Private route table with IPv6 internet access
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # IPv6 egress via IGW
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.this.id
  }

  # IPv4 egress via NAT Gateway
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name        = "${var.project_name}-private-rt-${var.env}"
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

# ---------------------------------------------------------------------------
# Network Security
# ---------------------------------------------------------------------------

resource "aws_security_group" "instance" {
  name_prefix = "${var.project_name}-sg-${var.env}-"
  description = "Allow HTTP/HTTPS + Docker Swarm"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-instance-sg-${var.env}"
    Environment = var.env
  }
}

# Ingress rules
locals {
  docker_swarm_rules = [
    {
      name     = "mgmt"
      port     = 2377
      protocol = "tcp"
    },
    {
      name     = "docker-client"
      port     = 2376
      protocol = "tcp"
    },
    {
      name     = "swarm-tcp"
      port     = 7946
      protocol = "tcp"
    },
    {
      name     = "swarm-udp"
      port     = 7946
      protocol = "udp"
    },
    {
      name     = "vxlan"
      port     = 4789
      protocol = "udp"
    }
  ]
}

# HTTP/HTTPS
resource "aws_security_group_rule" "http" {
  type              = "ingress"
  security_group_id = aws_security_group.instance.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  description       = "HTTPS"
}

# SSH for EC2 Instance Connect (restricted to AWS managed prefix list)
resource "aws_security_group_rule" "ssh_ec2_instance_connect" {
  type              = "ingress"
  security_group_id = aws_security_group.instance.id
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  description       = "SSH for EC2 Instance Connect"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.ec2_instance_connect_v6.id]
}

# Docker Swarm ingress (loop to avoid repetition)
resource "aws_security_group_rule" "docker_swarm" {
  for_each = { for r in local.docker_swarm_rules : r.name => r }

  type              = "ingress"
  security_group_id = aws_security_group.instance.id
  from_port         = each.value.port
  to_port           = each.value.port
  protocol          = each.value.protocol
  cidr_blocks       = [aws_vpc.main.cidr_block]
  ipv6_cidr_blocks  = [aws_vpc.main.ipv6_cidr_block]
  description       = "Docker Swarm ${each.value.name}"
}

# All egress
resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.instance.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  description       = "Allow all outbound"
}
