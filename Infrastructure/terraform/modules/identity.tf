# ---------------------------------------------------------------------------
# Identity & Access
# ---------------------------------------------------------------------------

locals {
  account_id = data.aws_caller_identity.current.account_id
}

#  Helper to build ARNs
locals {
  swarm_param_arn    = "arn:aws:ssm:${var.region}:${local.account_id}:parameter/docker/swarm/*"
  secrets_prefix_arn = "arn:aws:secretsmanager:${var.region}:${local.account_id}:secret:${var.app_name}-secrets*"
}

# Public worker role
resource "aws_iam_role" "public" {
  name = "${var.app_name}-ec2-public-role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name        = "${var.app_name}-ec2-public-role"
    Environment = var.environment
    Tier        = "public"
  }
}

# Private manager role
resource "aws_iam_role" "private" {
  name = "${var.app_name}-ec2-private-role"

  assume_role_policy = aws_iam_role.public.assume_role_policy

  tags = {
    Name        = "${var.app_name}-ec2-private-role"
    Environment = var.environment
    Tier        = "private"
  }
}

# Managed policy attachments (SSM + CloudWatch)
resource "aws_iam_role_policy_attachment" "ssm_public" {
  role       = aws_iam_role.public.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_public" {
  role       = aws_iam_role.public.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_role_policy_attachment" "ssm_private" {
  role       = aws_iam_role.private.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_private" {
  role       = aws_iam_role.private.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# Inline/managed combo policies
resource "aws_iam_policy" "worker_core" {
  name        = "${var.app_name}-worker-core"
  description = "Core permissions for public worker node"

  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
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
        Effect   = "Allow",
        Action   = [
          "ec2:Describe*",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:CreateVolume",
          "ec2:DeleteVolume",
          "ec2:CreateTags"
        ],
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-worker-core-policy"
    Environment = var.environment
    Purpose     = "Worker Core Permissions"
  }
}

resource "aws_iam_role_policy_attachment" "worker_core" {
  role       = aws_iam_role.public.name
  policy_arn = aws_iam_policy.worker_core.arn
}

resource "aws_iam_policy" "manager_core" {
  name        = "${var.app_name}-manager-core"
  description = "Core permissions for private manager node"

  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = concat(
      aws_iam_policy.worker_core.policy.Statement,
      [
        {
          Effect   = "Allow",
          Action   = [
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
        }
      ]
    )
  })

  tags = {
    Name        = "${var.app_name}-manager-core-policy"
    Environment = var.environment
    Purpose     = "Manager Core Permissions"
  }
}

resource "aws_iam_role_policy_attachment" "manager_core" {
  role       = aws_iam_role.private.name
  policy_arn = aws_iam_policy.manager_core.arn
}

# Instance profiles
resource "aws_iam_instance_profile" "public" {
  name = "${var.app_name}-ec2-public-profile"
  role = aws_iam_role.public.name

  tags = {
    Name        = "${var.app_name}-ec2-public-profile"
    Environment = var.environment
    Purpose     = "Public EC2 Instance Profile"
  }
}

resource "aws_iam_instance_profile" "private" {
  name = "${var.app_name}-ec2-private-profile"
  role = aws_iam_role.private.name

  tags = {
    Name        = "${var.app_name}-ec2-private-profile"
    Environment = var.environment
    Purpose     = "Private EC2 Instance Profile"
  }
}
