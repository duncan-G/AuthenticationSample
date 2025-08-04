# ---------------------------------------------------------------------------
# EC2 instances
# ---------------------------------------------------------------------------

# Public Worker Instances
resource "aws_instance" "public_workers" {
  count                       = var.public_worker_count
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.public_worker_instance_type
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  ipv6_address_count          = 1

  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.public.name

  tags = {
    Name        = "${var.app_name}-public-worker-${count.index + 1}"
    Environment = var.environment
    Role        = "worker"
    Type        = "public"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm_public,
    aws_iam_role_policy_attachment.cw_public,
    aws_iam_role_policy_attachment.worker_core
  ]
}

# Private Worker Instances
resource "aws_instance" "private_workers" {
  count         = var.private_worker_count
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.private_worker_instance_type
  subnet_id     = aws_subnet.private.id

  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.private.name

  tags = {
    Name        = "${var.app_name}-private-worker-${count.index + 1}"
    Environment = var.environment
    Role        = "worker"
    Type        = "private"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm_private,
    aws_iam_role_policy_attachment.cw_private,
    aws_iam_role_policy_attachment.worker_core
  ]
}

# Manager Instances
resource "aws_instance" "managers" {
  count         = var.manager_count
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.manager_instance_type
  subnet_id     = aws_subnet.private.id

  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.private.name

  tags = {
    Name        = "${var.app_name}-manager-${count.index + 1}"
    Environment = var.environment
    Role        = "manager"
    Type        = "private"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm_private,
    aws_iam_role_policy_attachment.cw_private,
    aws_iam_role_policy_attachment.manager_core
  ]
}
