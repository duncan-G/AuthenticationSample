# =============================================================================
# Cache EC2 Infrastructure
# =============================================================================
# Single EC2 instance for cache services with external EBS volume
# =============================================================================


#region Resources

# EBS Volume for Cache Instance
resource "aws_ebs_volume" "cache_instance" {
  availability_zone = aws_instance.cache_worker.availability_zone
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
  ami                    = var.ami_id
  instance_type          = var.cache_instance_type
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.instance_security_group_id]

  iam_instance_profile = var.worker_iam_instance_profile_name

  # Bootstrap using userdata script; prefix environment variables
  user_data_base64 = base64encode(join("\n", [
    "#!/usr/bin/env bash",
    "export PROJECT_NAME=\"${var.project_name}-${var.env}\"",
    "export AWS_REGION=\"${var.region}\"",
    # Domain and certificate manager settings for worker certificate service
    "export DOMAIN_NAME=\"${var.domain_name}\"",
    "export CODEDEPLOY_BUCKET_NAME=\"${var.codedeploy_bucket_name}\"",
    "export WORKER_TYPE=\"cache\"",
    "export SWARM_LOCK_TABLE=\"${var.swarm_lock_table}\"",
    file("${path.module}/../compute/userdata/worker.sh")
  ]))

  tags = {
    Name        = "${var.project_name}-cache-worker-${var.env}"
    Environment = var.env
    Role        = "worker"
    Type        = "private"
  }

}

# Attach EBS Volume to Cache Instance
resource "aws_volume_attachment" "cache_worker_volume" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.cache_instance.id
  instance_id = aws_instance.cache_worker.id

  depends_on = [aws_instance.cache_worker]
}

#endregion
