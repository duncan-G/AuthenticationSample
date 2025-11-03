# =============================================================================
# DynamoDB - Refresh Tokens
# =============================================================================
# Provides a table used by the Auth microservice to persist refresh tokens.
# Schema matches the application code in `DynamoDbRefreshTokenStore.cs`:
#   - Partition key:  pk (e.g., "RTID#<rtId>")
#   - Sort key:       sk (fixed version string, currently "v1")
# Additional item attributes include userSub, userEmail, refreshToken,
# issuedAtUtc, expiresAtUtc. We use on-demand capacity and enable encryption
# and PITR for resilience.
# =============================================================================

locals {
  refresh_tokens_table_name = "${var.project_name}_${var.env}_RefreshTokens"
}

resource "aws_dynamodb_table" "refresh_tokens" {
  name         = local.refresh_tokens_table_name
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "pk"
  range_key = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Environment = var.env
    Project     = var.project_name
    Purpose     = "Refresh tokens storage"
  }
}

# Minimal IAM policy to allow services to read/write the refresh tokens table
data "aws_iam_policy_document" "refresh_tokens_rw" {
  statement {
    sid    = "RefreshTokensReadWrite"
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable"
    ]

    resources = [
      aws_dynamodb_table.refresh_tokens.arn
    ]
  }
}

resource "aws_iam_policy" "refresh_tokens_rw" {
  name        = "${var.project_name}-refresh-tokens-rw-${var.env}"
  description = "Read/Write access to refresh tokens DynamoDB table"
  policy      = data.aws_iam_policy_document.refresh_tokens_rw.json
}

# Attach to worker instance role so microservices hosted there can access the table
resource "aws_iam_role_policy_attachment" "worker_refresh_tokens_rw" {
  role       = var.worker_role_name
  policy_arn = aws_iam_policy.refresh_tokens_rw.arn
}



# =============================================================================
# DynamoDB - Swarm Cluster Lock
# =============================================================================
# Table used by the Swarm manager to coordinate cluster leadership and share
# optional join tokens. Single-item per cluster keyed by cluster_name.
# Item attributes (non-keys) may include:
#   - manager_instance_id (S)
#   - manager_private_ip  (S)
#   - lease_expires_at    (S; ISO8601)
#   - manager_join_token  (S; optional)
#   - worker_join_token   (S; optional)
# =============================================================================

locals {
  swarm_cluster_lock_table_name = "${var.project_name}-${var.env}-swarm-cluster-lock"
}

resource "aws_dynamodb_table" "swarm_cluster_lock" {
  name         = local.swarm_cluster_lock_table_name
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "cluster_name"

  attribute {
    name = "cluster_name"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Environment = var.env
    Project     = var.project_name
    Purpose     = "Swarm cluster lock and join tokens"
  }
}

# Manager RW policy for the cluster lock table
data "aws_iam_policy_document" "swarm_cluster_lock_rw" {
  statement {
    sid    = "SwarmClusterLockReadWrite"
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable"
    ]

    resources = [
      aws_dynamodb_table.swarm_cluster_lock.arn
    ]
  }
}

resource "aws_iam_policy" "swarm_cluster_lock_rw" {
  name        = "${var.project_name}-swarm-cluster-lock-rw-${var.env}"
  description = "Read/Write access to Swarm cluster lock DynamoDB table"
  policy      = data.aws_iam_policy_document.swarm_cluster_lock_rw.json
}

# Attach RW to manager role if provided
resource "aws_iam_role_policy_attachment" "manager_swarm_cluster_lock_rw" {
  count      = length(var.manager_role_name) > 0 ? 1 : 0
  role       = var.manager_role_name
  policy_arn = aws_iam_policy.swarm_cluster_lock_rw.arn
}

# Worker RO policy for the cluster lock table (to read join tokens)
data "aws_iam_policy_document" "swarm_cluster_lock_ro" {
  statement {
    sid    = "SwarmClusterLockReadOnly"
    effect = "Allow"

    actions = [
      "dynamodb:GetItem",
      "dynamodb:DescribeTable"
    ]

    resources = [
      aws_dynamodb_table.swarm_cluster_lock.arn
    ]
  }
}

resource "aws_iam_policy" "swarm_cluster_lock_ro" {
  name        = "${var.project_name}-swarm-cluster-lock-ro-${var.env}"
  description = "Read-only access to Swarm cluster lock DynamoDB table"
  policy      = data.aws_iam_policy_document.swarm_cluster_lock_ro.json
}

resource "aws_iam_role_policy_attachment" "worker_swarm_cluster_lock_ro" {
  role       = var.worker_role_name
  policy_arn = aws_iam_policy.swarm_cluster_lock_ro.arn
}
