# =============================================================================
# EC2 Compute Infrastructure
# =============================================================================
# This file manages all EC2 compute infrastructure components:
# 
# • IAM roles and policies for EC2 instances
# • Instance profiles for role attachment
# • EC2 instances (workers, managers)
# • Dependencies and security configurations
# 
# Instance Types:
# - Workers: Application workloads (internet-facing via NLB)
# - Managers: Docker Swarm management and orchestration
# =============================================================================

#region Configuration

variable "instance_type_managers" {
  description = "EC2 instance type for Swarm managers"
  type        = string
  default     = "t4g.small"
}

variable "instance_types_workers" {
  description = "List of instance types for workers"
  type        = list(string)
  default     = ["t4g.small", "m6g.medium"]
}

variable "desired_workers" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}

variable "min_workers" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 3
}

variable "max_workers" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 9
}

# ASG Configuration Variables (Managers)

variable "manager_min_size" {
  description = "Minimum number of manager instances (should be odd for quorum)"
  type        = number
  default     = 1
}

variable "manager_max_size" {
  description = "Maximum number of manager instances"
  type        = number
  default     = 3
}

variable "manager_desired_capacity" {
  description = "Desired number of manager instances"
  type        = number
  default     = 1
}


# Data Sources
data "aws_caller_identity" "current" {}

# Locals for IAM ARNs
locals {
  account_id = data.aws_caller_identity.current.account_id
  swarm_param_arns = [
    "arn:aws:ssm:${var.region}:${local.account_id}:parameter/docker/swarm/*",
    "arn:aws:ssm:${var.region}:${local.account_id}:parameter/swarm/*"
  ]
  secrets_prefix_arn = "arn:aws:secretsmanager:${var.region}:${local.account_id}:secret:${var.project_name}-secrets*"
}

#endregion

#region IAM Roles

# Worker role
resource "aws_iam_role" "worker" {
  name = "${var.project_name}-ec2-worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name        = "${var.project_name}-ec2-worker-role"
    Environment = var.environment
  }
}

# Manager role
resource "aws_iam_role" "manager" {
  name = "${var.project_name}-ec2-manager-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name        = "${var.project_name}-ec2-manager-role"
    Environment = var.environment
    Tier        = "private"
  }
}

# Public Worker Instance Profile
resource "aws_iam_instance_profile" "worker" {
  name = "${var.project_name}-ec2-worker-profile"
  role = aws_iam_role.worker.name

  tags = {
    Name        = "${var.project_name}-ec2-worker-profile"
    Environment = var.environment
    Purpose     = "Worker EC2 Instance Profile"
  }
}

# Manager Instance Profile
resource "aws_iam_instance_profile" "manager" {
  name = "${var.project_name}-ec2-manager-profile"
  role = aws_iam_role.manager.name

  tags = {
    Name        = "${var.project_name}-ec2-manager-profile"
    Environment = var.environment
    Purpose     = "Manager EC2 Instance Profile"
  }
}

#endregion

#region IAM Policies

# Worker core permissions policy
resource "aws_iam_policy" "worker_core" {
  name        = "${var.project_name}-worker-core"
  description = "Core permissions for worker nodes"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = ["ssm:GetParameter", "ssm:GetParameters"],
        Resource = local.swarm_param_arns
      },
      {
        Effect   = "Allow",
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue"],
        Resource = local.secrets_prefix_arn
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:Describe*",
          "ec2:CreateTags"
        ],
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-worker-core-policy"
    Environment = var.environment
    Purpose     = "Worker Core Permissions"
  }
}

# Manager core permissions policy (includes worker permissions + management capabilities)
resource "aws_iam_policy" "manager_core" {
  name        = "${var.project_name}-manager-core"
  description = "Core permissions for manager nodes"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = concat(
      jsondecode(aws_iam_policy.worker_core.policy).Statement,
      [
        {
          Effect   = "Allow",
          Action   = ["ssm:PutParameter"],
          Resource = local.swarm_param_arns
        },
        {
          Effect = "Allow",
          Action = [
            "ssm:SendCommand",
            "ssm:GetCommandInvocation",
            "ssm:ListCommands",
            "ssm:ListCommandInvocations",
            "ssm:DescribeInstanceInformation",
            "ssm:UpdateInstanceInformation",
            "ssm:DescribeInstanceAssociationsStatus",
            "ssm:DescribeEffectiveInstanceAssociations"
          ],
          Resource = "*"
        },
        {
          Effect = "Allow",
          Action = [
            "ec2:RunInstances",
            "ec2:TerminateInstances",
            "ec2:CreateTags",
            "ec2:DescribeInstances",
            "ec2:DescribeInstanceStatus"
          ],
          Resource = "*"
        }
      ]
    )
  })

  tags = {
    Name        = "${var.project_name}-manager-core-policy"
    Environment = var.environment
    Purpose     = "Manager Core Permissions"
  }
}

#endregion

#region IAM Policy Attachments

# Managed policy attachments (SSM + CloudWatch)
resource "aws_iam_role_policy_attachment" "ssm_worker" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_worker" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_role_policy_attachment" "ssm_manager" {
  role       = aws_iam_role.manager.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_manager" {
  role       = aws_iam_role.manager.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# Custom policy attachments
resource "aws_iam_role_policy_attachment" "worker_core" {
  role       = aws_iam_role.worker.name
  policy_arn = aws_iam_policy.worker_core.arn
}

resource "aws_iam_role_policy_attachment" "manager_core" {
  role       = aws_iam_role.manager.name
  policy_arn = aws_iam_policy.manager_core.arn
}

#endregion

#region Resources

# CloudWatch Log Groups for EC2 instances
resource "aws_cloudwatch_log_group" "manager" {
  name              = "/aws/ec2/${var.project_name}-docker-manager"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-docker-manager-logs"
    Environment = var.environment
    Purpose     = "Docker Manager Logs"
  }
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/aws/ec2/${var.project_name}-docker-worker"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-docker-worker-logs"
    Environment = var.environment
    Purpose     = "Docker Worker Logs"
  }
}

# Launch Template for Workers (no user_data; bootstrap via SSM associations)
resource "aws_launch_template" "worker" {
  name_prefix   = "${var.project_name}-worker-"
  description   = "Launch template for worker nodes"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = element(var.instance_types_workers, 0)

  vpc_security_group_ids = [aws_security_group.instance.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.worker.name
  }

  # Bootstrap using userdata (modules-ha methodology)
  user_data = base64encode(templatefile("${path.module}/userdata/worker.sh", {
    region       = var.region,
    project_name = var.project_name
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-worker"
      Environment = var.environment
      Role        = "worker"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm_worker,
    aws_iam_role_policy_attachment.cw_worker,
    aws_iam_role_policy_attachment.worker_core
  ]
}

# Launch Template for Managers
resource "aws_launch_template" "manager" {
  name_prefix   = "${var.project_name}-manager-"
  description   = "Launch template for manager nodes"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type_managers

  vpc_security_group_ids = [aws_security_group.instance.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.manager.name
  }

  # Bootstrap using userdata (modules-ha methodology)
  user_data = base64encode(templatefile("${path.module}/userdata/manager.sh", {
    region       = var.region,
    project_name = var.project_name
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-manager"
      Environment = var.environment
      Role        = "manager"
      Type        = "private"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm_manager,
    aws_iam_role_policy_attachment.cw_manager,
    aws_iam_role_policy_attachment.manager_core
  ]
}

# Auto Scaling Group for Workers (single group)
resource "aws_autoscaling_group" "workers" {
  name                      = "${var.project_name}-workers-asg"
  vpc_zone_identifier       = [aws_subnet.public.id]
  target_group_arns         = [aws_lb_target_group.public_workers.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  min_size         = var.min_workers
  max_size         = var.max_workers
  desired_capacity = var.desired_workers

  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-worker-asg"
    propagate_at_launch = false
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "worker"
    propagate_at_launch = true
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }
}

# Auto Scaling Group for Managers
resource "aws_autoscaling_group" "managers" {
  name                      = "${var.project_name}-managers-asg"
  vpc_zone_identifier       = [aws_subnet.private.id]
  health_check_type         = "EC2"
  health_check_grace_period = 600 # Longer grace period for manager initialization

  min_size         = var.manager_min_size
  max_size         = var.manager_max_size
  desired_capacity = var.manager_desired_capacity

  launch_template {
    id      = aws_launch_template.manager.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-manager-asg"
    propagate_at_launch = false
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "manager"
    propagate_at_launch = true
  }

  tag {
    key                 = "Type"
    value               = "private"
    propagate_at_launch = true
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 600
    }
  }
}

# Target Group for Workers (for Load Balancer)
resource "aws_lb_target_group" "public_workers" {
  name     = "${var.project_name}-public-workers-tg"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    interval            = 30
    port                = 80
    protocol            = "TCP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name        = "${var.project_name}-public-workers-target-group"
    Environment = var.environment
  }
}

# Auto Scaling Policies (Workers)
resource "aws_autoscaling_policy" "worker_scale_up" {
  name                   = "${var.project_name}-worker-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.workers.name
}

resource "aws_autoscaling_policy" "worker_scale_down" {
  name                   = "${var.project_name}-worker-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.workers.name
}

# CloudWatch Alarms for Auto Scaling
resource "aws_cloudwatch_metric_alarm" "worker_cpu_high" {
  alarm_name          = "${var.project_name}-worker-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.worker_scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.workers.name
  }
}

resource "aws_cloudwatch_metric_alarm" "worker_cpu_low" {
  alarm_name          = "${var.project_name}-worker-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "10"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.worker_scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.workers.name
  }
}

#endregion

#region Outputs

# Auto Scaling Group outputs
output "worker_asg_name" {
  description = "Name of the worker Auto Scaling Group"
  value       = aws_autoscaling_group.workers.name
}

output "manager_asg_name" {
  description = "Name of the manager Auto Scaling Group"
  value       = aws_autoscaling_group.managers.name
}

output "worker_asg_arn" {
  description = "ARN of the worker Auto Scaling Group"
  value       = aws_autoscaling_group.workers.arn
}

output "manager_asg_arn" {
  description = "ARN of the manager Auto Scaling Group"
  value       = aws_autoscaling_group.managers.arn
}

# Launch Template outputs
output "worker_launch_template_id" {
  description = "ID of the worker launch template"
  value       = aws_launch_template.worker.id
}

output "manager_launch_template_id" {
  description = "ID of the manager launch template"
  value       = aws_launch_template.manager.id
}

# Target Group outputs
output "worker_target_group_arn" {
  description = "ARN of the worker HTTP target group"
  value       = aws_lb_target_group.public_workers.arn
}

# IAM Role outputs
output "worker_role_arn" {
  description = "ARN of the worker IAM role"
  value       = aws_iam_role.worker.arn
}

output "manager_role_arn" {
  description = "ARN of the manager IAM role"
  value       = aws_iam_role.manager.arn
}

# Instance Profile outputs
output "worker_instance_profile_name" {
  description = "Name of the worker instance profile"
  value       = aws_iam_instance_profile.worker.name
}

output "manager_instance_profile_name" {
  description = "Name of the manager instance profile"
  value       = aws_iam_instance_profile.manager.name
}

# CloudWatch Log Group outputs
output "manager_log_group_name" {
  description = "Name of the manager CloudWatch log group"
  value       = aws_cloudwatch_log_group.manager.name
}

output "worker_log_group_name" {
  description = "Name of the worker CloudWatch log group"
  value       = aws_cloudwatch_log_group.worker.name
}

#endregion