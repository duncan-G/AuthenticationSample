resource "aws_vpc" "this" {
  cidr_block           = "10.80.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc-${var.env}"
  }
}

locals {
  # Limit AZ usage to those actually available in the region
  az_names = slice(
    data.aws_availability_zones.available.names,
    0,
    min(length(data.aws_availability_zones.available.names), var.az_count)
  )
  effective_az_count = length(local.az_names)
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project_name}-igw-${var.env}" }
}

resource "aws_eip" "nat" {
  count  = local.effective_az_count
  domain = "vpc"
  tags = {
    Name = "${var.project_name}-nat-eip-${count.index}-${var.env}"
  }
}

resource "aws_subnet" "public" {
  count                   = local.effective_az_count
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 4, count.index)
  map_public_ip_on_launch = true
  availability_zone       = local.az_names[count.index]
  tags = {
    Name = "${var.project_name}-public-${count.index}-${var.env}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  count  = local.effective_az_count
  vpc_id = aws_vpc.this.id
  # Use non-overlapping subnets within /16 by carving /20s (newbits=4). Valid netnum range: 0..15.
  # Public uses 0..(N-1); private uses 8..(8+N-1) to avoid overlap and stay within range.
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 4, 8 + count.index)
  availability_zone = local.az_names[count.index]
  tags = {
    Name = "${var.project_name}-private-${count.index}-${var.env}"
    Tier = "private"
  }
}

resource "aws_nat_gateway" "this" {
  count         = local.effective_az_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${var.project_name}-nat-${count.index}-${var.env}" }
  depends_on    = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.project_name}-rt-public-${var.env}" }
}

resource "aws_route_table_association" "public" {
  count          = local.effective_az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = local.effective_az_count
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }
  tags = { Name = "${var.project_name}-rt-private-${count.index}-${var.env}" }
}

resource "aws_route_table_association" "private" {
  count          = local.effective_az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

output "vpc_id" { value = aws_vpc.this.id }
output "public_subnet_ids" { value = [for s in aws_subnet.public : s.id] }
output "private_subnet_ids" { value = [for s in aws_subnet.private : s.id] }
output "az_names" { value = data.aws_availability_zones.available.names }


