# SSM Documents for Docker Swarm Setup

# Docker Manager Setup SSM Document
resource "aws_ssm_document" "docker_manager_setup" {
  name            = "${var.app_name}-docker-manager-setup"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Bootstrap Docker Swarm manager with CloudWatch logging"
    mainSteps = [{
      name   = "RunManagerSetup"
      action = "aws:runShellScript"
      inputs = {
        runCommand = [
          # Write the existing manager setup script to disk
          "cat <<'EOF' > /tmp/install-docker-manager.sh",
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

# Docker Worker Setup SSM Document
resource "aws_ssm_document" "docker_worker_setup" {
  name            = "${var.app_name}-docker-worker-setup"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Bootstrap Docker Swarm worker with CloudWatch logging"
    mainSteps = [{
      name   = "RunWorkerSetup"
      action = "aws:runShellScript"
      inputs = {
        runCommand = [
          # Write the existing worker setup script to disk
          "cat <<'EOF' > /tmp/install-docker-worker.sh",
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

# CloudWatch Agent Setup SSM Document
resource "aws_ssm_document" "cloudwatch_agent_setup" {
  name            = "${var.app_name}-cloudwatch-agent-setup"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install and configure CloudWatch agent"
    mainSteps = [{
      name   = "InstallCloudWatchAgent"
      action = "aws:runShellScript"
      inputs = {
        runCommand = [
          # Install CloudWatch agent using yum
          "yum install -y amazon-cloudwatch-agent",
          # Write the CloudWatch agent configuration
          "cat <<'EOF' > /opt/aws/amazon-cloudwatch-agent/bin/config.json",
          "${indent(2, data.template_file.cloudwatch_agent_config_manager.rendered)}",
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
    Name        = "${var.app_name}-cloudwatch-agent-setup"
    Environment = var.environment
  }
}

# SSM Associations for Manager Instance
# First: Install CloudWatch agent
resource "aws_ssm_association" "cloudwatch_agent_manager" {
  name = aws_ssm_document.cloudwatch_agent_setup.name

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

  depends_on = [aws_ssm_association.cloudwatch_agent_manager]
}

# SSM Associations for Worker Instance
# First: Install CloudWatch agent
resource "aws_ssm_association" "cloudwatch_agent_worker" {
  name = aws_ssm_document.cloudwatch_agent_setup.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.public.id]
  }

  depends_on = [aws_instance.public]
}

# Then: Run Docker worker setup (depends on CloudWatch agent)
resource "aws_ssm_association" "docker_worker_setup" {
  name = aws_ssm_document.docker_worker_setup.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.public.id]
  }

  depends_on = [aws_ssm_association.cloudwatch_agent_worker]
} 