# Load Balancing with Network Load Balancer and SSL Termination

## Overview

The authentication system uses an AWS Network Load Balancer (NLB) for high-performance traffic distribution with SSL/TLS termination. The load balancer provides Layer 4 load balancing with dual-stack IPv4/IPv6 support, automatic health checks, and seamless integration with Auto Scaling Groups for dynamic scaling.

## Implementation

### Network Load Balancer Architecture

#### Core Components
- **Internet-facing NLB**: Distributes traffic across multiple worker nodes
- **Target Groups**: Health-checked backend instances running Docker Swarm workers
- **TLS Listeners**: SSL/TLS termination with ACM-managed certificates
- **Health Checks**: TCP-based health monitoring on port 80
- **Cross-Zone Load Balancing**: Even traffic distribution across availability zones

#### Load Balancer Configuration

```hcl
# Network Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-nlb-${var.env}"
  internal           = false
  load_balancer_type = "network"
  
  # Enable IPv4/IPv6 dual-stack
  ip_address_type = "dualstack"
  
  # Place in public subnet for internet access
  subnets = [aws_subnet.public.id]
  
  # Operational settings
  enable_deletion_protection       = var.enable_deletion_protection
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing
  
  tags = {
    Environment = var.env
    Type        = "network"
    IpVersion   = "dualstack"
    Purpose     = "Dualstack load balancer for Docker Swarm workers"
  }
}
```

#### TLS Listener Configuration

```hcl
# TLS Listener (Port 443)
resource "aws_lb_listener" "tls" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "TLS"
  certificate_arn   = aws_acm_certificate_validation.public.certificate_arn
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.workers.arn
  }
  
  tags = {
    Name        = "${var.project_name}-nlb-tls-listener-${var.env}"
    Environment = var.env
    Protocol    = "TLS"
  }
}
```

### Target Group Configuration

#### Worker Target Group

```hcl
# Target Group for Workers
resource "aws_lb_target_group" "workers" {
  name     = "${var.project_name}-worker-tg-${var.env}"
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
    timeout             = 10
  }
  
  tags = {
    Environment = var.env
    Purpose     = "Worker nodes target group"
  }
}
```

#### Auto Scaling Integration

```hcl
# Auto Scaling Group with Target Group attachment
resource "aws_autoscaling_group" "workers" {
  name                      = "${var.project_name}-workers-asg-${var.env}"
  vpc_zone_identifier       = [aws_subnet.private.id]
  target_group_arns         = [aws_lb_target_group.workers.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300
  
  min_size         = var.min_workers
  max_size         = var.max_workers
  desired_capacity = var.desired_workers
  
  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }
}
```

### SSL/TLS Certificate Management

#### ACM Certificate

```hcl
# ACM Certificate for domain
resource "aws_acm_certificate" "public" {
  domain_name               = var.domain_name
  subject_alternative_names = [
    "*.${var.domain_name}",
    "${var.api_subdomain}.${var.domain_name}",
    "${var.auth_subdomain}.${var.domain_name}"
  ]
  validation_method = "DNS"
  
  lifecycle {
    create_before_destroy = true
  }
  
  tags = {
    Environment = var.env
    Purpose     = "SSL certificate for load balancer"
  }
}
```

#### DNS Validation

```hcl
# Route53 records for certificate validation
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.public.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.hosted_zone.zone_id
}

# Certificate validation
resource "aws_acm_certificate_validation" "public" {
  certificate_arn         = aws_acm_certificate.public.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
  
  timeouts {
    create = "5m"
  }
}
```

### DNS Configuration

#### Route53 Records

```hcl
# A record for IPv4
resource "aws_route53_record" "api_ipv4" {
  zone_id = data.aws_route53_zone.hosted_zone.zone_id
  name    = "${var.api_subdomain}.${var.domain_name}"
  type    = "A"
  
  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# AAAA record for IPv6
resource "aws_route53_record" "api_ipv6" {
  zone_id = data.aws_route53_zone.hosted_zone.zone_id
  name    = "${var.api_subdomain}.${var.domain_name}"
  type    = "AAAA"
  
  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}
```

### Health Check Configuration

#### Target Health Monitoring

The load balancer performs TCP health checks on port 80:

```yaml
# Health check configuration
health_check:
  enabled: true
  interval: 30              # Check every 30 seconds
  port: 80                  # Health check port
  protocol: TCP             # TCP health check
  healthy_threshold: 3      # 3 successful checks = healthy
  unhealthy_threshold: 3    # 3 failed checks = unhealthy
  timeout: 10               # 10 second timeout
```

#### Application Health Endpoint

The application provides a health endpoint for monitoring:

```csharp
// Health check endpoint in ASP.NET Core
app.MapHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = UIResponseWriter.WriteHealthCheckUIResponse,
    ResultStatusCodes =
    {
        [HealthStatus.Healthy] = StatusCodes.Status200OK,
        [HealthStatus.Degraded] = StatusCodes.Status200OK,
        [HealthStatus.Unhealthy] = StatusCodes.Status503ServiceUnavailable
    }
});

// Add health checks
builder.Services.AddHealthChecks()
    .AddNpgSql(connectionString, name: "database")
    .AddRedis(redisConnectionString, name: "redis")
    .AddCheck<CustomHealthCheck>("custom");
```

### Traffic Routing

#### Envoy Proxy Integration

The load balancer forwards traffic to Envoy proxy running on worker nodes:

```yaml
# Envoy listener configuration
static_resources:
  listeners:
  - name: listener_0
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 80
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          route_config:
            name: local_route
            virtual_hosts:
            - name: backend
              domains: ["*"]
              routes:
              - match:
                  prefix: "/auth/"
                route:
                  cluster: auth_service
              - match:
                  prefix: "/api/"
                route:
                  cluster: greeter_service
```

## Configuration

### Load Balancer Variables

```hcl
# Load balancer configuration variables
variable "enable_deletion_protection" {
  description = "Enable deletion protection for the load balancer"
  type        = bool
  default     = false
}

variable "enable_cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing"
  type        = bool
  default     = true
}

variable "load_balancer_type" {
  description = "Type of load balancer (network or application)"
  type        = string
  default     = "network"
  
  validation {
    condition     = contains(["network", "application"], var.load_balancer_type)
    error_message = "Load balancer type must be either 'network' or 'application'."
  }
}
```

### Health Check Tuning

```hcl
# Health check configuration
variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 10
}

variable "healthy_threshold" {
  description = "Number of consecutive successful health checks"
  type        = number
  default     = 3
}

variable "unhealthy_threshold" {
  description = "Number of consecutive failed health checks"
  type        = number
  default     = 3
}
```

### SSL/TLS Configuration

```bash
# Certificate configuration
export TF_VAR_domain_name="example.com"
export TF_VAR_api_subdomain="api"
export TF_VAR_auth_subdomain="auth"

# Certificate validation timeout
export TF_VAR_cert_validation_timeout="5m"
```

## Usage

### Development Environment

#### Local Load Balancing

For development, Docker Swarm provides built-in load balancing:

```bash
# Deploy services with replicas
docker service create \
  --name auth-service \
  --replicas 3 \
  --network app-network \
  --publish 5001:5001 \
  auth-sample/auth-grpc:latest

# Check service distribution
docker service ps auth-service
```

#### Testing Load Distribution

```bash
# Test load balancing with multiple requests
for i in {1..10}; do
  curl -H "Host: api.example.com" http://localhost/health
  echo "Request $i completed"
done

# Monitor service logs to verify distribution
docker service logs -f auth-service
```

### Production Operations

#### Load Balancer Management

```bash
# Check load balancer status
aws elbv2 describe-load-balancers --names auth-sample-nlb-prod

# View target group health
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/auth-sample-worker-tg-prod/1234567890abcdef

# Monitor load balancer metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/NetworkELB \
  --metric-name ActiveFlowCount \
  --dimensions Name=LoadBalancer,Value=net/auth-sample-nlb-prod/1234567890abcdef \
  --start-time 2023-01-01T00:00:00Z \
  --end-time 2023-01-01T01:00:00Z \
  --period 300 \
  --statistics Average
```

#### Certificate Management

```bash
# Check certificate status
aws acm describe-certificate --certificate-arn arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012

# List certificates
aws acm list-certificates --certificate-statuses ISSUED

# Request certificate renewal (automatic)
aws acm resend-validation-email --certificate-arn arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012
```

#### DNS Management

```bash
# Check DNS records
aws route53 list-resource-record-sets --hosted-zone-id Z1234567890ABC

# Test DNS resolution
nslookup api.example.com
dig api.example.com A
dig api.example.com AAAA
```

## Testing

### Load Balancer Testing

1. **Connectivity Testing**:
   ```bash
   # Test HTTP connectivity
   curl -I http://api.example.com/health
   
   # Test HTTPS connectivity
   curl -I https://api.example.com/health
   
   # Test IPv6 connectivity
   curl -6 -I https://api.example.com/health
   ```

2. **SSL Certificate Testing**:
   ```bash
   # Test SSL certificate
   openssl s_client -connect api.example.com:443 -servername api.example.com
   
   # Check certificate chain
   openssl s_client -connect api.example.com:443 -showcerts
   
   # Verify certificate expiration
   echo | openssl s_client -connect api.example.com:443 2>/dev/null | openssl x509 -noout -dates
   ```

3. **Load Distribution Testing**:
   ```bash
   # Load test with multiple connections
   ab -n 1000 -c 10 https://api.example.com/health
   
   # Monitor target distribution
   watch -n 1 'aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:... --query "TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]" --output table'
   ```

### Health Check Testing

1. **Target Health Validation**:
   ```bash
   # Check all targets are healthy
   aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:... --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`]'
   
   # Test health endpoint directly
   curl http://worker-node-ip/health
   ```

2. **Failover Testing**:
   ```bash
   # Stop service on one node
   docker service update --replicas 2 auth-service
   
   # Verify traffic continues to flow
   while true; do curl -s https://api.example.com/health && echo " - $(date)"; sleep 1; done
   ```

## Troubleshooting

### Common Issues

#### 1. Unhealthy Targets

```bash
# Check target health details
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:...

# Check security group rules
aws ec2 describe-security-groups --group-ids sg-1234567890abcdef0

# Test connectivity from load balancer subnet
aws ec2 run-instances --image-id ami-12345678 --instance-type t3.micro --subnet-id subnet-12345678 --security-group-ids sg-1234567890abcdef0
```

#### 2. SSL Certificate Issues

```bash
# Check certificate validation status
aws acm describe-certificate --certificate-arn arn:aws:acm:...

# Verify DNS validation records
aws route53 list-resource-record-sets --hosted-zone-id Z1234567890ABC --query 'ResourceRecordSets[?Type==`CNAME`]'

# Test certificate chain
openssl s_client -connect api.example.com:443 -verify_return_error
```

#### 3. DNS Resolution Problems

```bash
# Check Route53 records
aws route53 list-resource-record-sets --hosted-zone-id Z1234567890ABC

# Test DNS propagation
dig @8.8.8.8 api.example.com
dig @1.1.1.1 api.example.com

# Check load balancer DNS name
aws elbv2 describe-load-balancers --names auth-sample-nlb-prod --query 'LoadBalancers[0].DNSName'
```

#### 4. Load Balancer Connectivity

```bash
# Check load balancer status
aws elbv2 describe-load-balancers --names auth-sample-nlb-prod --query 'LoadBalancers[0].State'

# Test load balancer directly
curl -H "Host: api.example.com" http://$(aws elbv2 describe-load-balancers --names auth-sample-nlb-prod --query 'LoadBalancers[0].DNSName' --output text)/health
```

### Performance Optimization

#### Connection Tuning

```hcl
# Optimize target group settings
resource "aws_lb_target_group" "workers" {
  # Reduce health check interval for faster detection
  health_check {
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  
  # Enable connection draining
  deregistration_delay = 30
}
```

#### Auto Scaling Integration

```hcl
# Optimize Auto Scaling for load balancer
resource "aws_autoscaling_group" "workers" {
  # Reduce health check grace period
  health_check_grace_period = 180
  
  # Use ELB health checks
  health_check_type = "ELB"
  
  # Enable instance refresh
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 300
    }
  }
}
```

### Monitoring and Alerting

```bash
# Create CloudWatch alarms
aws cloudwatch put-metric-alarm \
  --alarm-name "NLB-UnhealthyTargets" \
  --alarm-description "NLB has unhealthy targets" \
  --metric-name "UnHealthyHostCount" \
  --namespace "AWS/NetworkELB" \
  --statistic "Average" \
  --period 300 \
  --threshold 1 \
  --comparison-operator "GreaterThanOrEqualToThreshold" \
  --dimensions Name=LoadBalancer,Value=net/auth-sample-nlb-prod/1234567890abcdef \
  --evaluation-periods 2

# Monitor connection metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/NetworkELB \
  --metric-name NewFlowCount \
  --dimensions Name=LoadBalancer,Value=net/auth-sample-nlb-prod/1234567890abcdef \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Sum
```

## Related Features

- [AWS Deployment](aws-deployment.md) - Complete infrastructure deployment
- [Docker Containerization](docker-containerization.md) - Backend service orchestration
- [Terraform Infrastructure Deployment](terraform-deployment.md) - Infrastructure as Code
- [Monitoring and Observability](monitoring-observability.md) - Load balancer monitoring