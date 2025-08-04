# SSM Documents for Docker Swarm Setup

# Docker Manager Setup SSM Document
resource "aws_ssm_document" "docker_manager_setup" {
  name            = "${var.app_name}-docker-manager-setup"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Bootstrap Docker Swarm manager"
    mainSteps = [{
      name   = "RunManagerSetup"
      action = "aws:runShellScript"
      inputs = {
        runCommand = [
          # Write the existing manager setup script to disk
          "cat <<'EOF' > /tmp/install-docker-manager.sh",
          # Pre-emptively create ECR cache directory for the ec2-user with correct permissions.
          # This is necessary because a systemd service with readonly home directory permissions will
          # use the ecr-login credential helper which will attempt to create this directory and fail.
          "mkdir -p /home/ec2-user/.ecr",
          "chown ec2-user:ec2-user /home/ec2-user/.ecr",
          "chmod 0700 /home/ec2-user/.ecr",
          "${indent(2, file("${path.module}/../install-docker-manager.sh"))}",
          "EOF",
          "chmod +x /tmp/install-docker-manager.sh",
          # Execute it
          "/tmp/install-docker-manager.sh"
        ]
        timeoutSeconds = "1800" # 30 minutes timeout
      }
    }]
  })

  tags = {
    Name        = "${var.app_name}-docker-manager-setup"
    Environment = var.environment
  }
}

# Certificate Manager Setup SSM Document
resource "aws_ssm_document" "certificate_manager_setup" {
  name            = "${var.app_name}-certificate-manager-setup"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install and configure certificate manager daemon service"
    mainSteps = [{
      name   = "InstallCertificateManager"
      action = "aws:runShellScript"
      inputs = {
        runCommand = [
          # Write the certificate manager daemon service file
          "cat <<'EOF' > /etc/systemd/system/certificate-manager.service",
          "${indent(2, file("${path.module}/../../certbot/certificate-manager.service"))}",
          "EOF",

          # Write the certificate manager script to /usr/local/bin
          "cat <<'EOF' > /usr/local/bin/certificate-manager.sh",
          "${indent(2, file("${path.module}/../../certbot/certificate-manager.sh"))}",
          "EOF",
          # Write the trigger script to /usr/local/bin
          "cat <<'EOF' > /usr/local/bin/trigger-certificate-renewal.sh",
          "${indent(2, file("${path.module}/../../certbot/trigger-certificate-renewal.sh"))}",
          "EOF",
          # Add environment variable to the trigger script
          "sed -i '1a export AWS_SECRET_NAME=\"${var.app_name}-secrets\"' /usr/local/bin/trigger-certificate-renewal.sh",
          # Make the scripts executable
          "chmod +x /usr/local/bin/certificate-manager.sh",
          "chmod +x /usr/local/bin/trigger-certificate-renewal.sh",
          # systemd creates /run/certificate-manager via the RuntimeDirectory directive.
          # The other directories required by the service need to be created manually.
          "mkdir -p /var/lib/certificate-manager",
          "mkdir -p /run/certificate-manager",
          "mkdir -p /var/log/certificate-manager",
          # Set proper ownership for systemd directories
          "chown ec2-user:ec2-user /var/lib/certificate-manager",
          "chown ec2-user:ec2-user /run/certificate-manager",
          "chown ec2-user:ec2-user /var/log/certificate-manager",
          # Create and set permissions for the log file
          "touch /var/log/certificate-manager/certificate-manager.log",
          "chown ec2-user:ec2-user /var/log/certificate-manager/certificate-manager.log",
          "chmod 644 /var/log/certificate-manager/certificate-manager.log",
          # Reload systemd and enable the service
          "systemctl daemon-reload",
          "systemctl enable certificate-manager.service",
          # Wait for Docker to be ready before starting the service
          "echo 'Waiting for Docker to be ready...'",
          "until systemctl is-active --quiet docker; do",
          "  echo 'Docker not ready yet, waiting...'",
          "  sleep 5",
          "done",
          "echo 'Docker is ready, starting certificate-manager service'",
          "systemctl start certificate-manager.service"
        ]
        timeoutSeconds = "600" # 10 minutes timeout
      }
    }]
  })

  tags = {
    Name        = "${var.app_name}-certificate-manager-setup"
    Environment = var.environment
  }
}

# EBS Volume Setup SSM Document
resource "aws_ssm_document" "ebs_volume_setup" {
  name            = "${var.app_name}-ebs-volume-setup"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Setup EBS volume for Let's Encrypt certificates and certbot directories"
    mainSteps = [{
      name   = "SetupEBSVolume"
      action = "aws:runShellScript"
      inputs = {
        runCommand = [
          # Setup certificate manager log directory for EBS volume setup logs
          "mkdir -p /var/log/certificate-manager",
          "chown ec2-user:ec2-user /var/log/certificate-manager",
          "chmod 755 /var/log/certificate-manager",
          # Create certbot directories (required by renew-certificate.sh)
          "mkdir -p /var/lib/letsencrypt",
          "mkdir -p /var/log/letsencrypt",
          "chown ec2-user:ec2-user /var/lib/letsencrypt /var/log/letsencrypt",
          "chmod 755 /var/lib/letsencrypt /var/log/letsencrypt",
          # Write the EBS volume setup script to disk
          "cat <<'EOF' > /tmp/setup-ebs-volume.sh",
          "${indent(2, file("${path.module}/../../certbot/setup-ebs-volume.sh"))}",
          "EOF",
          "chmod +x /tmp/setup-ebs-volume.sh",
          # Execute the EBS volume setup script
          "/tmp/setup-ebs-volume.sh",
          # Clean up the temporary script
          "rm -f /tmp/setup-ebs-volume.sh"
        ]
        timeoutSeconds = "300" # 5 minutes timeout
      }
    }]
  })

  tags = {
    Name        = "${var.app_name}-ebs-volume-setup"
    Environment = var.environment
  }
}

# Docker Worker Setup SSM Document
resource "aws_ssm_document" "docker_worker_setup" {
  name            = "${var.app_name}-docker-worker-setup"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Bootstrap Docker Swarm worker"
    mainSteps = [{
      name   = "RunWorkerSetup"
      action = "aws:runShellScript"
      inputs = {
        runCommand = [
          # Write the existing worker setup script to disk
          "cat <<'EOF' > /tmp/install-docker-worker.sh",
          # Pre-emptively create ECR cache directory for the ec2-user with correct permissions.
          # This is necessary because a systemd service with readonly home directory permissions will
          # use the ecr-login credential helper which will attempt to create this directory and fail.
          "mkdir -p /home/ec2-user/.ecr",
          "chown ec2-user:ec2-user /home/ec2-user/.ecr",
          "chmod 0700 /home/ec2-user/.ecr",
          "${indent(2, file("${path.module}/../install-docker-worker.sh"))}",
          "EOF",
          "chmod +x /tmp/install-docker-worker.sh",
          # Execute it
          "/tmp/install-docker-worker.sh"
        ]
        timeoutSeconds = "1800" # 30 minutes timeout
      }
    }]
  })

  tags = {
    Name        = "${var.app_name}-docker-worker-setup"
    Environment = var.environment
  }
}

# CloudWatch Agent Setup SSM Document for Manager (Logs Only)
resource "aws_ssm_document" "cloudwatch_agent_setup_manager" {
  name            = "${var.app_name}-cloudwatch-agent-setup-manager"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install and configure CloudWatch agent for manager (logs only)"
    mainSteps = [{
      name   = "InstallCloudWatchAgent"
      action = "aws:runShellScript"
      inputs = {
        runCommand = [
          # Install CloudWatch agent using yum
          "yum install -y amazon-cloudwatch-agent",
          # Write the CloudWatch agent configuration
          "cat <<'EOF' > /opt/aws/amazon-cloudwatch-agent/bin/config.json",
          "${indent(2, local.cloudwatch_agent_config_manager)}",
          "EOF",
          # Start and enable the agent
          "/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json",
          "systemctl enable amazon-cloudwatch-agent"
        ]
        timeoutSeconds = "600" # 10 minutes timeout
      }
    }]
  })

  tags = {
    Name        = "${var.app_name}-cloudwatch-agent-setup-manager"
    Environment = var.environment
  }
}

# CloudWatch Agent Setup SSM Document for Worker (Logs Only)
resource "aws_ssm_document" "cloudwatch_agent_setup_worker" {
  name            = "${var.app_name}-cloudwatch-agent-setup-worker"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install and configure CloudWatch agent for worker (logs only)"
    mainSteps = [{
      name   = "InstallCloudWatchAgent"
      action = "aws:runShellScript"
      inputs = {
        runCommand = [
          # Install CloudWatch agent using yum
          "yum install -y amazon-cloudwatch-agent",
          # Write the CloudWatch agent configuration
          "cat <<'EOF' > /opt/aws/amazon-cloudwatch-agent/bin/config.json",
          "${indent(2, local.cloudwatch_agent_config_worker)}",
          "EOF",
          # Start and enable the agent
          "/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json",
          "systemctl enable amazon-cloudwatch-agent"
        ]
        timeoutSeconds = "600" # 10 minutes timeout
      }
    }]
  })

  tags = {
    Name        = "${var.app_name}-cloudwatch-agent-setup-worker"
    Environment = var.environment
  }
}

# SSM Associations for Manager Instance
# First: Install CloudWatch agent (logs only)
resource "aws_ssm_association" "cloudwatch_agent_manager" {
  name = aws_ssm_document.cloudwatch_agent_setup_manager.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.private.id]
  }

  depends_on = [aws_instance.private]
}

# Then: Run Docker manager setup (depends on CloudWatch agent)
resource "aws_ssm_association" "docker_manager_setup" {
  name = aws_ssm_document.docker_manager_setup.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.private.id]
  }

  depends_on = [aws_ssm_association.cloudwatch_agent_manager, aws_ssm_parameter.docker_swarm_worker_token, aws_ssm_parameter.docker_swarm_manager_ip, aws_ssm_parameter.docker_swarm_network_name]
}

# Then: Install certificate manager (depends on Docker manager setup and Docker worker setup)
resource "aws_ssm_association" "certificate_manager_setup" {
  name = aws_ssm_document.certificate_manager_setup.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.private.id]
  }

  depends_on = [aws_ssm_association.docker_manager_setup, aws_ssm_association.docker_worker_setup]
}

# SSM Associations for Worker Instance
# First: Install CloudWatch agent (logs only)
resource "aws_ssm_association" "cloudwatch_agent_worker" {
  name = aws_ssm_document.cloudwatch_agent_setup_worker.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.public.id]
  }

  depends_on = [aws_instance.public]
}

# Then: Run Docker worker setup (depends on CloudWatch agent and Docker manager setup)
resource "aws_ssm_association" "docker_worker_setup" {
  name = aws_ssm_document.docker_worker_setup.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.public.id]
  }

  depends_on = [aws_ssm_association.cloudwatch_agent_worker, aws_ssm_association.docker_manager_setup]
}

# Then: Setup EBS volume and certbot directories (depends on Docker worker setup and EBS volume attachment)
resource "aws_ssm_association" "ebs_volume_setup" {
  name = aws_ssm_document.ebs_volume_setup.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.public.id]
  }

  depends_on = [aws_ssm_association.docker_worker_setup, aws_volume_attachment.certbot_ebs_attachment]
}

# SSM Parameters for Docker Swarm Configuration
# These parameters are created by Terraform first with placeholder values
# Then the install-docker-manager.sh script overwrites them with actual values

resource "aws_ssm_parameter" "docker_swarm_worker_token" {
  name        = "/docker/swarm/worker-token"
  description = "Docker Swarm worker join token"
  type        = "String"
  value       = "placeholder" # Will be updated by the script
  overwrite   = true

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Name        = "${var.app_name}-docker-swarm-worker-token"
    Environment = var.environment
  }
}

resource "aws_ssm_parameter" "docker_swarm_manager_ip" {
  name        = "/docker/swarm/manager-ip"
  description = "Docker Swarm manager IP address"
  type        = "String"
  value       = "placeholder" # Will be updated by the script
  overwrite   = true

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Name        = "${var.app_name}-docker-swarm-manager-ip"
    Environment = var.environment
  }
}

resource "aws_ssm_parameter" "docker_swarm_network_name" {
  name        = "/docker/swarm/network-name"
  description = "Docker Swarm overlay network name"
  type        = "String"
  value       = "placeholder" # Will be updated by the script
  overwrite   = true

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Name        = "${var.app_name}-docker-swarm-network-name"
    Environment = var.environment
  }
} 