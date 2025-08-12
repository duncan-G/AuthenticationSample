resource "aws_ssm_parameter" "swarm_manager_addr" {
  name        = "/swarm/manager-addr"
  type        = "String"
  value       = ""
  overwrite   = true
  description = "Swarm manager advertise address (ip:2377). To be set post-init"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "swarm_manager_token" {
  name        = "/swarm/manager-token"
  type        = "String"
  value       = ""
  overwrite   = true
  description = "Swarm join token for managers. Set after first manager init"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "swarm_worker_token" {
  name        = "/swarm/worker-token"
  type        = "String"
  value       = ""
  overwrite   = true
  description = "Swarm join token for workers. Set after first manager init"
  lifecycle { ignore_changes = [value] }
}


