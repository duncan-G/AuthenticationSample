# =============================================================================
# Network Infrastructure
# =============================================================================
# VPC with dual-stack IPv4/IPv6, one public subnet (workers, NLB) and one
# private subnet (managers, internal workloads), with IGW and route tables.
# =============================================================================

#region Resources

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

# Public subnet for external-facing resources
resource "aws_subnet" "public" {
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = "10.0.1.0/24"
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 1)
  map_public_ip_on_launch         = true
  assign_ipv6_address_on_creation = true
  availability_zone               = data.aws_availability_zones.this.names[0]

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
  availability_zone               = data.aws_availability_zones.this.names[0]

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

# Private route table with IPv6 internet access (no NAT needed for IPv6)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # IPv6 egress via IGW (no NAT needed for IPv6)
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.this.id
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
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  description       = "HTTP"
}

# Docker Swarm ingress (loop to avoid repetition)
resource "aws_security_group_rule" "docker_swarm" {
  for_each = { for r in local.docker_swarm_rules : r.name => r }

  type              = "ingress"
  security_group_id = aws_security_group.instance.id
  from_port         = each.value.port
  to_port           = each.value.port
  protocol          = each.value.protocol
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
