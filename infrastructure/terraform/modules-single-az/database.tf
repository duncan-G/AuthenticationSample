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
  role       = aws_iam_role.worker.name
  policy_arn = aws_iam_policy.refresh_tokens_rw.arn
}

# Outputs
output "refresh_tokens_table_name" {
  description = "Name of the DynamoDB table for refresh tokens"
  value       = aws_dynamodb_table.refresh_tokens.name
}

output "refresh_tokens_table_arn" {
  description = "ARN of the DynamoDB table for refresh tokens"
  value       = aws_dynamodb_table.refresh_tokens.arn
}

