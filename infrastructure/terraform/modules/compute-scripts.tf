//#region Configuration

variable "enable_ssm_associations" {
  description = "Enable SSM associations to bootstrap docker and cloudwatch on instances"
  type        = bool
  default     = false
}

//#endregion

# SSM Documents for Docker Swarm Setup

# Docker Manager Setup SSM Document
resource "aws_ssm_document" "docker_manager_setup" {
  name            = "${var.project_name}-docker-manager-setup"
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
    Name        = "${var.project_name}-docker-manager-setup"
    Environment = var.environment
  }
}

# Docker Worker Setup SSM Document
resource "aws_ssm_document" "docker_worker_setup" {
  name            = "${var.project_name}-docker-worker-setup"
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
    Name        = "${var.project_name}-docker-worker-setup"
    Environment = var.environment
  }
}

# CloudWatch Agent Setup SSM Document for Manager (Logs Only)
resource "aws_ssm_document" "cloudwatch_agent_setup_manager" {
  name            = "${var.project_name}-cloudwatch-agent-setup-manager"
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
          "${indent(2, replace(replace(file("${path.module}/cloudwatch-agent-config.json"), "$${project_name}", "${var.project_name}"), "$${environment}", "${var.environment}"))}",
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
    Name        = "${var.project_name}-cloudwatch-agent-setup-manager"
    Environment = var.environment
  }
}

# CloudWatch Agent Setup SSM Document for Worker (Logs Only)
resource "aws_ssm_document" "cloudwatch_agent_setup_worker" {
  name            = "${var.project_name}-cloudwatch-agent-setup-worker"
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
          "${indent(2, replace(replace(file("${path.module}/cloudwatch-agent-config.json"), "$${project_name}", "${var.project_name}"), "$${environment}", "${var.environment}"))}",
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
    Name        = "${var.project_name}-cloudwatch-agent-setup-worker"
    Environment = var.environment
  }
}

# SSM Associations for Manager Instance
# First: Install CloudWatch agent (logs only)
resource "aws_ssm_association" "cloudwatch_agent_manager" {
  count = var.enable_ssm_associations ? 1 : 0
  name  = aws_ssm_document.cloudwatch_agent_setup_manager.name

  targets {
    key    = "tag:Role"
    values = ["manager"]
  }
}

# Then: Run Docker manager setup (depends on CloudWatch agent)
resource "aws_ssm_association" "docker_manager_setup" {
  count = var.enable_ssm_associations ? 1 : 0
  name  = aws_ssm_document.docker_manager_setup.name

  targets {
    key    = "tag:Role"
    values = ["manager"]
  }

  depends_on = [aws_ssm_association.cloudwatch_agent_manager, aws_ssm_parameter.docker_swarm_worker_token, aws_ssm_parameter.docker_swarm_manager_ip, aws_ssm_parameter.docker_swarm_network_name]
}

# SSM Associations for Worker Instance
# First: Install CloudWatch agent (logs only)
resource "aws_ssm_association" "cloudwatch_agent_worker" {
  count = var.enable_ssm_associations ? 1 : 0
  name  = aws_ssm_document.cloudwatch_agent_setup_worker.name

  targets {
    key    = "tag:Role"
    values = ["worker"]
  }
}

# Then: Run Docker worker setup (depends on CloudWatch agent and Docker manager setup)
resource "aws_ssm_association" "docker_worker_setup" {
  count = var.enable_ssm_associations ? 1 : 0
  name  = aws_ssm_document.docker_worker_setup.name

  targets {
    key    = "tag:Role"
    values = ["worker"]
  }

  depends_on = [aws_ssm_association.cloudwatch_agent_worker, aws_ssm_association.docker_manager_setup]
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
    Name        = "${var.project_name}-docker-swarm-worker-token"
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
    Name        = "${var.project_name}-docker-swarm-manager-ip"
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
    Name        = "${var.project_name}-docker-swarm-network-name"
    Environment = var.environment
  }
} 