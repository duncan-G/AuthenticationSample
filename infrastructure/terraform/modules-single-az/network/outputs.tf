output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private.id
}

output "instance_security_group_id" {
  description = "ID of the instance security group"
  value       = aws_security_group.instance.id
}

output "vpc_ipv6_cidr_block" {
  description = "The IPv6 CIDR block for the VPC"
  value       = aws_vpc.main.ipv6_cidr_block
}

