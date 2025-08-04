# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "manager" {
  name              = "/aws/ec2/${var.app_name}-docker-manager"
  retention_in_days = 30

  tags = {
    Name        = "${var.app_name}-docker-manager-logs"
    Environment = var.environment
    Purpose     = "Docker Manager Logs"
  }
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/aws/ec2/${var.app_name}-docker-worker"
  retention_in_days = 30

  tags = {
    Name        = "${var.app_name}-docker-worker-logs"
    Environment = var.environment
    Purpose     = "Docker Worker Logs"
  }
}
