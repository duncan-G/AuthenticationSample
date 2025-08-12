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
