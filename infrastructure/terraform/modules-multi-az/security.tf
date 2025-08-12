# SG for instances (managers/workers) – private only, no public ingress. Egress all.
resource "aws_security_group" "instances" {
  name        = "${var.project_name}-instances-${var.env}"
  description = "Instances private SG"
  vpc_id      = aws_vpc.this.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-instances-${var.env}" }
}

# SG for NLB-related ingress on instances (when target type is instance).
# Note: NLB does not use SG; this SG is applied to instances to restrict who can reach Envoy.
resource "aws_security_group" "nlb_to_envoy" {
  name        = "${var.project_name}-nlb-to-envoy-${var.env}"
  description = "Allow 8443 only from CloudFront (via NLB)"
  vpc_id      = aws_vpc.this.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-nlb-to-envoy-${var.env}" }
}

# Allow only NLB to Envoy port 8443 on instances. We will later attach this SG to ASGs.
resource "aws_security_group_rule" "envoy_8080_from_nlb" {
  type              = "ingress"
  security_group_id = aws_security_group.nlb_to_envoy.id
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = length(var.allowed_cloudfront_cidrs) > 0 ? var.allowed_cloudfront_cidrs : [for s in aws_subnet.public : s.cidr_block]
  description       = "Only CloudFront/NLB ranges can reach Envoy 8080"
}

# Docker Swarm intra-cluster ports (only within VPC)
resource "aws_security_group_rule" "swarm_mgmt" {
  type              = "ingress"
  security_group_id = aws_security_group.instances.id
  from_port         = 2377
  to_port           = 2377
  protocol          = "tcp"
  cidr_blocks       = [aws_vpc.this.cidr_block]
  description       = "Swarm manager TCP"
}
resource "aws_security_group_rule" "swarm_tcp" {
  type              = "ingress"
  security_group_id = aws_security_group.instances.id
  from_port         = 7946
  to_port           = 7946
  protocol          = "tcp"
  cidr_blocks       = [aws_vpc.this.cidr_block]
  description       = "Swarm gossip TCP"
}
resource "aws_security_group_rule" "swarm_udp" {
  type              = "ingress"
  security_group_id = aws_security_group.instances.id
  from_port         = 7946
  to_port           = 7946
  protocol          = "udp"
  cidr_blocks       = [aws_vpc.this.cidr_block]
  description       = "Swarm gossip UDP"
}
resource "aws_security_group_rule" "vxlan" {
  type              = "ingress"
  security_group_id = aws_security_group.instances.id
  from_port         = 4789
  to_port           = 4789
  protocol          = "udp"
  cidr_blocks       = [aws_vpc.this.cidr_block]
  description       = "Swarm overlay VXLAN"
}

output "sg_instances_id" { value = aws_security_group.instances.id }
output "sg_nlb_to_envoy_id" { value = aws_security_group.nlb_to_envoy.id }


