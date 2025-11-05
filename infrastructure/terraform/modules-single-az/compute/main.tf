# =============================================================================
# EC2 Compute Infrastructure
# =============================================================================
# IAM roles/policies, instance profiles, launch templates and ASGs for
# workers (private) and managers (private), including CloudWatch log groups
# and scaling alarms.
# =============================================================================

#region EC2 Compute

# Locals for IAM ARNs
locals {
  swarm_param_arns = [
    "arn:aws:ssm:${var.region}:${var.account_id}:parameter/docker/swarm/*",
    "arn:aws:ssm:${var.region}:${var.account_id}:parameter/swarm/*"
  ]
  secrets_prefix_arn             = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.project_name}-secrets-${var.env}*"
  certificate_manager_object_arn = "arn:aws:s3:::${var.codedeploy_bucket_name}/*/certificate-manager*"
  worker_manager_object_arn = "arn:aws:s3:::${var.codedeploy_bucket_name}/*/worker-manager*"
}

# Worker role
resource "aws_iam_role" "worker" {
  name = "${var.project_name}-ec2-worker-role-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Environment = var.env
  }
}

# Manager role
resource "aws_iam_role" "manager" {
  name = "${var.project_name}-ec2-manager-role-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Environment = var.env
    Tier        = "private"
  }
}

# Worker Instance Profile
resource "aws_iam_instance_profile" "worker" {
  name = "${var.project_name}-ec2-worker-profile-${var.env}"
  role = aws_iam_role.worker.name

  tags = {
    Environment = var.env
    Purpose     = "Worker EC2 Instance Profile"
  }
}

# Manager Instance Profile
resource "aws_iam_instance_profile" "manager" {
  name = "${var.project_name}-ec2-manager-profile-${var.env}"
  role = aws_iam_role.manager.name

  tags = {
    Environment = var.env
    Purpose     = "Manager EC2 Instance Profile"
  }
}

# Worker core permissions policy
resource "aws_iam_policy" "worker_core" {
  name        = "${var.project_name}-worker-core-${var.env}"
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
      },
      {
        Effect   = "Allow",
        Action   = ["ec2-instance-connect:SendSSHPublicKey"],
        Resource = "arn:aws:ec2:${var.region}:${var.account_id}:instance/*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject"
        ],
        Resource = [
          local.certificate_manager_object_arn,
          local.worker_manager_object_arn
        ]
      }
    ]
  })

  tags = {
    Environment = var.env
    Purpose     = "Worker Core Permissions"
  }
}

# Manager core permissions policy
resource "aws_iam_policy" "manager_core" {
  name        = "${var.project_name}-manager-core-${var.env}"
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
        },
        {
          Effect   = "Allow",
          Action   = ["ec2-instance-connect:SendSSHPublicKey"],
          Resource = "arn:aws:ec2:${var.region}:${var.account_id}:instance/*"
        },
        {
          Effect = "Allow",
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ],
          Resource = "arn:aws:logs:*:*:*"
        }
      ]
    )
  })

  tags = {
    Environment = var.env
    Purpose     = "Manager Core Permissions"
  }
}

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

# CloudWatch Log Groups for EC2 instances
resource "aws_cloudwatch_log_group" "manager" {
  name              = "/logs/${var.project_name}/swarm-manager-${var.env}"
  retention_in_days = 30

  tags = {
    Environment = var.env
    Purpose     = "Docker Manager Logs"
  }
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/logs/${var.project_name}/swarm-worker-${var.env}"
  retention_in_days = 30

  tags = {
    Environment = var.env
    Purpose     = "Docker Worker Logs"
  }
}

resource "aws_cloudwatch_log_group" "leader_manager" {
  name              = "/logs/${var.project_name}/leader-manager-${var.env}"
  retention_in_days = 30

  tags = {
    Environment = var.env
    Purpose     = "Leader Manager Service Logs"
  }
}

resource "aws_cloudwatch_log_group" "certificate_manager" {
  name              = "/logs/${var.project_name}/certificate-manager-${var.env}"
  retention_in_days = 30

  tags = {
    Environment = var.env
    Purpose     = "Certificate Manager Service Logs"
  }
}

# CloudWatch Log Group for worker-manager service (env-suffixed, used by worker.sh)
resource "aws_cloudwatch_log_group" "worker_manager" {
  name              = "/logs/${var.project_name}/worker-manager-${var.env}"
  retention_in_days = 30

  tags = {
    Environment = var.env
    Purpose     = "Worker Manager Service Logs"
  }
}

# Launch Template for Workers
resource "aws_launch_template" "worker" {
  name_prefix   = "${var.project_name}-worker-${var.env}-"
  description   = "Launch template for worker nodes"
  image_id      = var.ami_id
  instance_type = element(var.instance_types_workers, 0)

  vpc_security_group_ids = [var.instance_security_group_id]

  iam_instance_profile {
    name = aws_iam_instance_profile.worker.name
  }

  # Bootstrap using userdata script; prefix environment variables
  user_data = base64encode(join("\n", [
    "#!/usr/bin/env bash",
    "# shellcheck shell=bash",
    "export PROJECT_NAME=\"${var.project_name}\"",
    "export ENV=\"${var.env}\"",
    "export AWS_REGION=\"${var.region}\"",
    "export CODEDEPLOY_BUCKET_NAME=\"${var.codedeploy_bucket_name}\"",
    "export SWARM_LOCK_TABLE=\"${var.swarm_lock_table}\"",
    "export WORKER_TYPE=\"compute\"",
    file("${path.module}/userdata/worker.sh")
  ]))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-worker-${var.env}"
      Environment = var.env
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
  name_prefix   = "${var.project_name}-manager-${var.env}-"
  description   = "Launch template for manager nodes"
  image_id      = var.ami_id
  instance_type = var.instance_type_managers

  vpc_security_group_ids = [var.instance_security_group_id]

  iam_instance_profile {
    name = aws_iam_instance_profile.manager.name
  }

  # Bootstrap using userdata script; prefix environment variables
  user_data = base64encode(join("\n", [
    "#!/usr/bin/env bash",
    "# shellcheck shell=bash",
    "export PROJECT_NAME=\"${var.project_name}\"",
    "export ENV=\"${var.env}\"",
    "export AWS_REGION=\"${var.region}\"",
    "export AWS_SECRET_NAME=\"${var.project_name}-secrets-${var.env}\"",
    "export DOMAIN_NAME=\"${var.domain_name}\"",
    "export CODEDEPLOY_BUCKET_NAME=\"${var.codedeploy_bucket_name}\"",
    "export SWARM_LOCK_TABLE=\"${var.swarm_lock_table}\"",
    file("${path.module}/userdata/manager.sh")
  ]))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-manager-${var.env}"
      Environment = var.env
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

# Auto Scaling Group for Workers
resource "aws_autoscaling_group" "workers" {
  name                      = "${var.project_name}-workers-asg-${var.env}"
  vpc_zone_identifier       = [var.private_subnet_id]
  target_group_arns         = [aws_lb_target_group.workers.arn]
  health_check_type         = "EC2"
  health_check_grace_period = 300

  min_size         = var.min_workers
  max_size         = var.max_workers
  desired_capacity = var.desired_workers

  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }

  depends_on = [aws_autoscaling_group.managers]

  tag {
    key                 = "Environment"
    value               = var.env
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
  name                      = "${var.project_name}-managers-asg-${var.env}"
  vpc_zone_identifier       = [var.private_subnet_id]
  health_check_type         = "EC2"
  health_check_grace_period = 600

  min_size         = var.manager_min_size
  max_size         = var.manager_max_size
  desired_capacity = var.manager_desired_capacity

  launch_template {
    id      = aws_launch_template.manager.id
    version = "$Latest"
  }

  tag {
    key                 = "Environment"
    value               = var.env
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
resource "aws_lb_target_group" "workers" {
  name     = "${var.project_name}-worker-tg-${var.env}"
  port     = 443
  protocol = "TLS"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    interval            = 30
    port                = 443
    protocol            = "TCP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Environment = var.env
  }
}

# Auto Scaling Policies (Workers)
resource "aws_autoscaling_policy" "worker_scale_up" {
  name                   = "${var.project_name}-worker-scale-up-${var.env}"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.workers.name
}

resource "aws_autoscaling_policy" "worker_scale_down" {
  name                   = "${var.project_name}-worker-scale-down-${var.env}"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.workers.name
}

# CloudWatch Alarms for Auto Scaling
resource "aws_cloudwatch_metric_alarm" "worker_cpu_high" {
  alarm_name          = "${var.project_name}-worker-cpu-high-${var.env}"
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
  alarm_name          = "${var.project_name}-worker-cpu-low-${var.env}"
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
