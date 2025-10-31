# =============================================================================
# Cache EC2 Infrastructure
# =============================================================================
# Single EC2 instance for cache services with external EBS volume
# =============================================================================


#region Resources

# EBS Volume for Cache Instance
resource "aws_ebs_volume" "cache_instance" {
  availability_zone = aws_subnet.private.availability_zone
  size              = var.cache_instance_volume_size
  type              = var.cache_instance_volume_type
  encrypted         = true

  tags = {
    Name        = "${var.project_name}-cache-instance-volume-${var.env}"
    Environment = var.env
    Purpose     = "Cache Instance External Storage"
  }
}

# Cache EC2 Instance (not part of ASG)
resource "aws_instance" "cache_worker" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.cache_instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.instance.id]

  iam_instance_profile = aws_iam_instance_profile.worker.name

  # Bootstrap using userdata script; prefix environment variables
  user_data = base64encode(join("\n", [
    "#!/usr/bin/env bash",
    "export PROJECT_NAME=\"${var.project_name}-${var.env}\"",
    "export AWS_REGION=\"${var.region}\"",
    file("${path.module}/userdata/worker.sh")
  ]))

  tags = {
    Name        = "${var.project_name}-cache-worker-${var.env}"
    Environment = var.env
    Role        = "worker"
    Type        = "private"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm_worker,
    aws_iam_role_policy_attachment.cw_worker,
    aws_iam_role_policy_attachment.worker_core
  ]
}

# Attach EBS Volume to Cache Instance
resource "aws_volume_attachment" "cache_worker_volume" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.cache_instance.id
  instance_id = aws_instance.cache_worker.id

  depends_on = [aws_instance.cache_worker]
}

#endregion
