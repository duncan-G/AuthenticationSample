# =============================================================================
# EC2 Compute Infrastructure
# =============================================================================
# This file manages all EC2 compute infrastructure components:
# 
# • IAM roles and policies for EC2 instances
# • Instance profiles for role attachment
# • EC2 instances (public workers, private workers, managers)
# • Dependencies and security configurations
# 
# Instance Types:
# - Public Workers: Handle external traffic, certificate renewal
# - Private Workers: Internal application workloads
# - Managers: Docker Swarm management and orchestration
# =============================================================================

#region Configuration

# Variables
variable "public_worker_instance_type" {
  description = "EC2 instance type for public worker nodes"
  type        = string
  default     = "t4g.micro"
}

variable "private_worker_instance_type" {
  description = "EC2 instance type for private worker nodes"
  type        = string
  default     = "t4g.small"
}

variable "manager_instance_type" {
  description = "EC2 instance type for manager nodes"
  type        = string
  default     = "t4g.micro"
}

# ASG Configuration Variables
variable "public_worker_min_size" {
  description = "Minimum number of public worker instances"
  type        = number
  default     = 1
}

variable "public_worker_max_size" {
  description = "Maximum number of public worker instances"
  type        = number
  default     = 3
}

variable "public_worker_desired_capacity" {
  description = "Desired number of public worker instances"
  type        = number
  default     = 1
}

variable "private_worker_min_size" {
  description = "Minimum number of private worker instances"
  type        = number
  default     = 1
}

variable "private_worker_max_size" {
  description = "Maximum number of private worker instances"
  type        = number
  default     = 5
}

variable "private_worker_desired_capacity" {
  description = "Desired number of private worker instances"
  type        = number
  default     = 2
}

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
  account_id         = data.aws_caller_identity.current.account_id
  swarm_param_arn    = "arn:aws:ssm:${var.region}:${local.account_id}:parameter/docker/swarm/*"
  secrets_prefix_arn = "arn:aws:secretsmanager:${var.region}:${local.account_id}:secret:${var.project_name}-secrets*"
}

#endregion

#region IAM Roles

# Public worker role
resource "aws_iam_role" "public_worker" {
  name = "${var.project_name}-ec2-public-worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name        = "${var.project_name}-ec2-public-worker-role"
    Environment = var.environment
    Tier        = "public"
  }
}

# Private worker role
resource "aws_iam_role" "private_worker" {
  name = "${var.project_name}-ec2-private-worker-role"

  assume_role_policy = aws_iam_role.public_worker.assume_role_policy

  tags = {
    Name        = "${var.project_name}-ec2-private-worker-role"
    Environment = var.environment
    Tier        = "private"
  }
}

# Manager role
resource "aws_iam_role" "manager" {
  name = "${var.project_name}-ec2-manager-role"

  assume_role_policy = aws_iam_role.public_worker.assume_role_policy

  tags = {
    Name        = "${var.project_name}-ec2-manager-role"
    Environment = var.environment
    Tier        = "private"
  }
}

# Public Worker Instance Profile
resource "aws_iam_instance_profile" "public_worker" {
  name = "${var.project_name}-ec2-public-worker-profile"
  role = aws_iam_role.public_worker.name

  tags = {
    Name        = "${var.project_name}-ec2-public-worker-profile"
    Environment = var.environment
    Purpose     = "Public Worker EC2 Instance Profile"
  }
}

# Private Worker Instance Profile
resource "aws_iam_instance_profile" "private_worker" {
  name = "${var.project_name}-ec2-private-worker-profile"
  role = aws_iam_role.private_worker.name

  tags = {
    Name        = "${var.project_name}-ec2-private-worker-profile"
    Environment = var.environment
    Purpose     = "Private Worker EC2 Instance Profile"
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
        Resource = local.swarm_param_arn
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
resource "aws_iam_role_policy_attachment" "ssm_public_worker" {
  role       = aws_iam_role.public_worker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_public_worker" {
  role       = aws_iam_role.public_worker.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_role_policy_attachment" "ssm_private_worker" {
  role       = aws_iam_role.private_worker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_private_worker" {
  role       = aws_iam_role.private_worker.name
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
resource "aws_iam_role_policy_attachment" "worker_core_public" {
  role       = aws_iam_role.public_worker.name
  policy_arn = aws_iam_policy.worker_core.arn
}

resource "aws_iam_role_policy_attachment" "worker_core_private" {
  role       = aws_iam_role.private_worker.name
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

# Launch Template for Public Workers
resource "aws_launch_template" "public_worker" {
  name_prefix   = "${var.project_name}-public-worker-"
  description   = "Launch template for public worker nodes"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.public_worker_instance_type

  vpc_security_group_ids = [aws_security_group.instance.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.public_worker.name
  }

  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
    device_index                = 0
    ipv6_address_count          = 1
    security_groups             = [aws_security_group.instance.id]
  }

  user_data = base64encode(file("${path.module}/../install-docker-worker.sh"))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-public-worker"
      Environment = var.environment
      Role        = "worker"
      Type        = "public"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm_public_worker,
    aws_iam_role_policy_attachment.cw_public_worker,
    aws_iam_role_policy_attachment.worker_core_public
  ]
}

# Launch Template for Private Workers
resource "aws_launch_template" "private_worker" {
  name_prefix   = "${var.project_name}-private-worker-"
  description   = "Launch template for private worker nodes"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.private_worker_instance_type

  vpc_security_group_ids = [aws_security_group.instance.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.private_worker.name
  }

  user_data = base64encode(file("${path.module}/../install-docker-worker.sh"))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-private-worker"
      Environment = var.environment
      Role        = "worker"
      Type        = "private"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm_private_worker,
    aws_iam_role_policy_attachment.cw_private_worker,
    aws_iam_role_policy_attachment.worker_core_private
  ]
}

# Launch Template for Managers
resource "aws_launch_template" "manager" {
  name_prefix   = "${var.project_name}-manager-"
  description   = "Launch template for manager nodes"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.manager_instance_type

  vpc_security_group_ids = [aws_security_group.instance.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.manager.name
  }

  user_data = base64encode(file("${path.module}/../install-docker-manager.sh"))

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

# Auto Scaling Group for Public Workers
resource "aws_autoscaling_group" "public_workers" {
  name                = "${var.project_name}-public-workers-asg"
  vpc_zone_identifier = [aws_subnet.public.id]
  target_group_arns = [
    aws_lb_target_group.public_workers.arn,
    aws_lb_target_group.public_workers_https.arn
  ]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  min_size         = var.public_worker_min_size
  max_size         = var.public_worker_max_size
  desired_capacity = var.public_worker_desired_capacity

  launch_template {
    id      = aws_launch_template.public_worker.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-public-worker-asg"
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

  tag {
    key                 = "Type"
    value               = "public"
    propagate_at_launch = true
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }
}

# Auto Scaling Group for Private Workers
resource "aws_autoscaling_group" "private_workers" {
  name                      = "${var.project_name}-private-workers-asg"
  vpc_zone_identifier       = [aws_subnet.private.id]
  health_check_type         = "EC2"
  health_check_grace_period = 300

  min_size         = var.private_worker_min_size
  max_size         = var.private_worker_max_size
  desired_capacity = var.private_worker_desired_capacity

  launch_template {
    id      = aws_launch_template.private_worker.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-private-worker-asg"
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

  tag {
    key                 = "Type"
    value               = "private"
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

# Target Group for Public Workers (for Load Balancer)
resource "aws_lb_target_group" "public_workers" {
  name     = "${var.project_name}-public-workers-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.project_name}-public-workers-target-group"
    Environment = var.environment
  }
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "public_worker_scale_up" {
  name                   = "${var.project_name}-public-worker-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.public_workers.name
}

resource "aws_autoscaling_policy" "public_worker_scale_down" {
  name                   = "${var.project_name}-public-worker-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.public_workers.name
}

resource "aws_autoscaling_policy" "private_worker_scale_up" {
  name                   = "${var.project_name}-private-worker-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.private_workers.name
}

resource "aws_autoscaling_policy" "private_worker_scale_down" {
  name                   = "${var.project_name}-private-worker-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.private_workers.name
}

# CloudWatch Alarms for Auto Scaling
resource "aws_cloudwatch_metric_alarm" "public_worker_cpu_high" {
  alarm_name          = "${var.project_name}-public-worker-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.public_worker_scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.public_workers.name
  }
}

resource "aws_cloudwatch_metric_alarm" "public_worker_cpu_low" {
  alarm_name          = "${var.project_name}-public-worker-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "10"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.public_worker_scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.public_workers.name
  }
}

resource "aws_cloudwatch_metric_alarm" "private_worker_cpu_high" {
  alarm_name          = "${var.project_name}-private-worker-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.private_worker_scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.private_workers.name
  }
}

resource "aws_cloudwatch_metric_alarm" "private_worker_cpu_low" {
  alarm_name          = "${var.project_name}-private-worker-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "10"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.private_worker_scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.private_workers.name
  }
}

#endregion

#region Outputs

# Auto Scaling Group outputs
output "public_worker_asg_name" {
  description = "Name of the public worker Auto Scaling Group"
  value       = aws_autoscaling_group.public_workers.name
}

output "private_worker_asg_name" {
  description = "Name of the private worker Auto Scaling Group"
  value       = aws_autoscaling_group.private_workers.name
}

output "manager_asg_name" {
  description = "Name of the manager Auto Scaling Group"
  value       = aws_autoscaling_group.managers.name
}

output "public_worker_asg_arn" {
  description = "ARN of the public worker Auto Scaling Group"
  value       = aws_autoscaling_group.public_workers.arn
}

output "private_worker_asg_arn" {
  description = "ARN of the private worker Auto Scaling Group"
  value       = aws_autoscaling_group.private_workers.arn
}

output "manager_asg_arn" {
  description = "ARN of the manager Auto Scaling Group"
  value       = aws_autoscaling_group.managers.arn
}

# Launch Template outputs
output "public_worker_launch_template_id" {
  description = "ID of the public worker launch template"
  value       = aws_launch_template.public_worker.id
}

output "private_worker_launch_template_id" {
  description = "ID of the private worker launch template"
  value       = aws_launch_template.private_worker.id
}

output "manager_launch_template_id" {
  description = "ID of the manager launch template"
  value       = aws_launch_template.manager.id
}

# Target Group outputs
output "public_worker_target_group_arn" {
  description = "ARN of the public worker HTTP target group"
  value       = aws_lb_target_group.public_workers.arn
}

# IAM Role outputs
output "public_worker_role_arn" {
  description = "ARN of the public worker IAM role"
  value       = aws_iam_role.public_worker.arn
}

output "private_worker_role_arn" {
  description = "ARN of the private worker IAM role"
  value       = aws_iam_role.private_worker.arn
}

output "manager_role_arn" {
  description = "ARN of the manager IAM role"
  value       = aws_iam_role.manager.arn
}

# Instance Profile outputs
output "public_worker_instance_profile_name" {
  description = "Name of the public worker instance profile"
  value       = aws_iam_instance_profile.public_worker.name
}

output "private_worker_instance_profile_name" {
  description = "Name of the private worker instance profile"
  value       = aws_iam_instance_profile.private_worker.name
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