data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.project_name}-ec2-role-${var.env}"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "ssm_params" {
  name = "${var.project_name}-ssm-params-${var.env}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["ssm:GetParameter", "ssm:GetParameters", "ssm:PutParameter"], Resource = "arn:${data.aws_partition.current.partition}:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/swarm/*" },
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"], Resource = "*" }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_params" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.ssm_params.arn
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile-${var.env}"
  role = aws_iam_role.ec2.name
}

locals {
  manager_userdata = base64encode(templatefile("${path.module}/userdata/manager.sh", {
    region       = var.region,
    project_name = var.project_name
  }))
  worker_userdata = base64encode(templatefile("${path.module}/userdata/worker.sh", {
    region       = var.region,
    project_name = var.project_name
  }))
}

resource "aws_launch_template" "manager" {
  name_prefix            = "${var.project_name}-mgr-${var.env}-"
  image_id               = data.aws_ami.al2023.id
  instance_type          = var.instance_type_managers
  update_default_version = true
  iam_instance_profile { name = aws_iam_instance_profile.ec2.name }
  vpc_security_group_ids = [aws_security_group.instances.id, aws_security_group.nlb_to_envoy.id]
  user_data              = local.manager_userdata
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      encrypted   = true
      volume_size = 30
      volume_type = "gp3"
    }
  }
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-manager-${var.env}"
      Role = "manager"
    }
  }
}

resource "aws_launch_template" "worker" {
  name_prefix            = "${var.project_name}-wkr-${var.env}-"
  image_id               = data.aws_ami.al2023.id
  instance_type          = var.instance_types_workers[0]
  update_default_version = true
  iam_instance_profile { name = aws_iam_instance_profile.ec2.name }
  vpc_security_group_ids = [aws_security_group.instances.id, aws_security_group.nlb_to_envoy.id]
  user_data              = local.worker_userdata
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      encrypted   = true
      volume_size = 30
      volume_type = "gp3"
    }
  }
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-worker-${var.env}"
      Role = "worker"
    }
  }
}

# Managers: 3 nodes, one per AZ, scale-in protection on, On-Demand only
resource "aws_autoscaling_group" "managers" {
  name                      = "${var.project_name}-managers-${var.env}"
  vpc_zone_identifier       = [for s in aws_subnet.private : s.id]
  desired_capacity          = 3
  min_size                  = 3
  max_size                  = 3
  protect_from_scale_in     = true
  health_check_type         = "EC2"
  health_check_grace_period = 300
  capacity_rebalance        = false

  launch_template {
    id      = aws_launch_template.manager.id
    version = "$Latest"
  }

  placement_group    = null
  availability_zones = [for i in range(var.az_count) : data.aws_availability_zones.available.names[i]]

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 66
      instance_warmup        = 180
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-manager-${var.env}"
    propagate_at_launch = true
  }
}

# Workers: desired/min/max, Mixed policy with optional Spot, Warm Pool
resource "aws_autoscaling_group" "workers" {
  name                      = "${var.project_name}-workers-${var.env}"
  vpc_zone_identifier       = [for s in aws_subnet.private : s.id]
  desired_capacity          = var.desired_workers
  min_size                  = var.min_workers
  max_size                  = var.max_workers
  health_check_type         = "EC2"
  health_check_grace_period = 300
  capacity_rebalance        = var.enable_spot

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.worker.id
        version            = "$Latest"
      }
      dynamic "override" {
        for_each = var.instance_types_workers
        content {
          instance_type = override.value
        }
      }
    }
    instances_distribution {
      on_demand_base_capacity                  = var.on_demand_base
      on_demand_percentage_above_base_capacity = var.enable_spot ? 0 : 100
      spot_allocation_strategy                 = "capacity-optimized-prioritized"
      spot_max_price                           = var.spot_max_price == "" ? null : var.spot_max_price
    }
  }

  warm_pool {
    pool_state = "Hibernated"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 66
      instance_warmup        = 120
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-worker-${var.env}"
    propagate_at_launch = true
  }
}

# Attach instances to Envoy target group (instance mode)
# Attach the managers ASG too, if Envoy tasks might run on managers. Default: workers only.

resource "aws_autoscaling_attachment" "workers_to_proxy" {
  autoscaling_group_name = aws_autoscaling_group.workers.name
  lb_target_group_arn    = aws_lb_target_group.proxy.arn
}

output "asg_managers_name" { value = aws_autoscaling_group.managers.name }
output "asg_workers_name" { value = aws_autoscaling_group.workers.name }


