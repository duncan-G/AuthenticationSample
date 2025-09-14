# API Gateway Configuration

## Overview

The system uses Envoy Proxy as an API Gateway to handle routing, protocol translation, security, and observability for all client-to-service communication. Envoy sits between the frontend clients and backend gRPC services, providing a unified entry point with advanced traffic management capabilities.

## Architecture

### Gateway Role

```text
Frontend Clients → Envoy Proxy → Backend Services
                 ←             ←
```

**Key Responsibilities:**
- **Protocol Translation**: gRPC-Web ↔ gRPC
- **Load Balancing**: Distribute requests across service instances
- **Security**: Authentication, authorization, rate limiting
- **Observability**: Logging, tracing, metrics
- **CORS Handling**: Cross-origin request management

### Configuration Structure

Envoy uses dynamic configuration with separate files for different concerns:

```text
infrastructure/envoy/
├── envoy.yaml              # Main configuration
├── envoy.cds.yaml         # Cluster Discovery Service
├── envoy.rds.yaml         # Route Discovery Service
├── envoy.sds.yaml         # Secret Discovery Service
└── envoy.stack.debug.yaml # Docker Swarm deployment
```

## Main Configuration

### Listener Configuration

Envoy listens on multiple protocols:

```yaml
# envoy.yaml
static_resources:
  listeners:
  - name: http_listener
    address:
      socket_address: { address: 0.0.0.0, port_value: 443 }
    filter_chains:
      filters:
        - name: envoy.filters.network.http_connection_manager
          typed_config:
            "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
            codec_type: auto  # Supports HTTP/1.1 and HTTP/2
            stat_prefix: ingress_http
```

### HTTP/3 Support

Additional listener for QUIC/HTTP3:

```yaml
  - name: quic_listener
    address:
      socket_address: { protocol: UDP, address: 0.0.0.0, port_value: 443 }
    udp_listener_config:
      quic_options: {}
    filter_chains:
      filters:
        - name: envoy.filters.network.http_connection_manager
          typed_config:
            codec_type: HTTP3
```

### TLS Configuration

Secure communication with automatic certificate management:

```yaml
      transport_socket:
        name: envoy.transport_sockets.tls
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.DownstreamTlsContext
          common_tls_context:
            alpn_protocols: ["h2", "http/1.1"]
            tls_certificate_sds_secret_configs:
            - name: tls_sds
              sds_config:
                path_config_source: { path: /etc/envoy/discovery/envoy.sds.yaml }
```

## HTTP Filters

### Filter Chain Order

Filters are processed in order - order matters for functionality:

```yaml
            http_filters:
              - name: envoy.filters.http.cors           # CORS handling
              - name: envoy.filters.http.grpc_web       # gRPC-Web translation
              - name: envoy.filters.http.ext_authz      # External authorization
              - name: envoy.filters.http.local_ratelimit # Rate limiting
              - name: envoy.filters.http.router         # Request routing
```

### CORS Filter

Handles cross-origin requests from web browsers:

```yaml
              - name: envoy.filters.http.cors
                typed_config:
                  "@type": type.googleapis.com/envoy.extensions.filters.http.cors.v3.Cors
```

CORS policies are defined per-route in the RDS configuration.

### gRPC-Web Filter

Translates between gRPC-Web and native gRPC:

```yaml
              - name: envoy.filters.http.grpc_web
                typed_config:
                  "@type": type.googleapis.com/envoy.extensions.filters.http.grpc_web.v3.GrpcWeb
```

**Features:**
- Protocol translation (gRPC-Web ↔ gRPC)
- Binary and text format support
- Streaming support for server-side streaming

### External Authorization Filter

Integrates with the Auth service for request authorization:

```yaml
              - name: envoy.filters.http.ext_authz
                typed_config:
                  "@type": type.googleapis.com/envoy.extensions.filters.http.ext_authz.v3.ExtAuthz
                  transport_api_version: V3
                  failure_mode_allow: false
                  grpc_service:
                    google_grpc:
                      target_uri: "$AUTH_HOST:$AUTH_PORT"
                      channel_credentials:
                        ssl_credentials:
                          root_certs:
                            filename: /etc/envoy/certs/ca.crt
```

### Rate Limiting Filter

Provides request rate limiting capabilities:

```yaml
              - name: envoy.filters.http.local_ratelimit
                typed_config:
                  "@type": type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3.LocalRateLimit
                  stat_prefix: http_local_rate_limiter
```

Rate limiting policies are configured per-route.

## Routing Configuration

### Route Discovery Service (RDS)

Dynamic routing configuration in `envoy.rds.yaml`:

```yaml
resources:
- "@type": type.googleapis.com/envoy.config.route.v3.RouteConfiguration
  name: service_routes
  virtual_hosts:
    - name: service_routes_virtual_host
      domains: [$ALLOWED_HOSTS]
```

### Service Routes

#### Auth Service Routes

```yaml
      routes:
        - match:
            prefix: "/auth/auth.SignUpService/"
          route:
            cluster: auth_cluster
            prefix_rewrite: "/auth.SignUpService/"
            timeout: 0s
            max_stream_duration:
              grpc_timeout_header_max: 0s
```

**Route Features:**
- **Prefix matching**: Routes based on URL path
- **Cluster routing**: Directs to appropriate backend cluster
- **Path rewriting**: Transforms URLs for backend services
- **Timeout configuration**: Request timeout settings

#### Greeter Service Routes

```yaml
        - match:
            prefix: "/greet/"
          route:
            cluster: greeter_cluster
            prefix_rewrite: "/"
            timeout: 0s
```

### Per-Route Configuration

#### CORS Policy

Route-specific CORS configuration:

```yaml
      typed_per_filter_config:
        envoy.filters.http.cors:
          "@type": type.googleapis.com/envoy.extensions.filters.http.cors.v3.CorsPolicy
          allow_origin_string_match: $PROCESSED_ORIGINS
          allow_methods: "GET,POST,PUT,DELETE,OPTIONS"
          allow_headers: "keep-alive,user-agent,cache-control,content-type,content-transfer-encoding,authorization,x-accept-content-transfer-encoding,x-accept-response-streaming,x-user-agent,x-grpc-web,grpc-timeout,traceparent,tracestate,b3,baggage"
          expose_headers: "grpc-status,grpc-message,grpc-messages,error-code,error-codes,retry-after-seconds"
          max_age: "1728000"
          allow_credentials: true
```

#### Rate Limiting Policy

Route-specific rate limiting:

```yaml
          typed_per_filter_config:
            envoy.filters.http.local_ratelimit:
              "@type": type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3.LocalRateLimit
              stat_prefix: http_local_rate_limiter
              token_bucket:
                max_tokens: 50
                tokens_per_fill: 50
                fill_interval: 1s
              filter_enabled:
                default_value:
                  numerator: 100
                  denominator: HUNDRED
```

#### Authorization Policy

Disable authorization for public endpoints:

```yaml
            envoy.filters.http.ext_authz:
              "@type": type.googleapis.com/envoy.extensions.filters.http.ext_authz.v3.ExtAuthzPerRoute
              disabled: true
```

## Cluster Configuration

### Cluster Discovery Service (CDS)

Backend service cluster definitions in `envoy.cds.yaml`:

```yaml
resources:
  - "@type": type.googleapis.com/envoy.config.cluster.v3.Cluster
    name: auth_cluster
    connect_timeout: 1s
    type: logical_dns
    dns_lookup_family: V4_ONLY
    lb_policy: round_robin
```

### Service Discovery

#### Static Service Discovery

For development environments:

```yaml
    load_assignment:
      cluster_name: auth_cluster
      endpoints:
      - lb_endpoints:
        - endpoint:
            address: { socket_address: { address: $AUTH_HOST, port_value: $AUTH_PORT } }
```

#### Health Checking

Optional health checks for service instances:

```yaml
    health_checks:
    - timeout: 1s
      interval: 5s
      unhealthy_threshold: 2
      healthy_threshold: 2
      grpc_health_check:
        service_name: "auth.SignUpService"
```

### TLS Configuration for Upstream

Secure communication with backend services:

```yaml
    transport_socket:
      name: envoy.transport_sockets.tls
      typed_config:
        "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
        sni: "localhost"
        common_tls_context:
          alpn_protocols: ["h2"]
          validation_context:
            trusted_ca:
              filename: /etc/envoy/certs/ca.crt
            match_typed_subject_alt_names:
            - san_type: DNS
              matcher:
                exact: "localhost"
```

## Observability

### Access Logging

Structured access logs with OpenTelemetry integration:

```yaml
            access_log:
            - name: envoy.access_loggers.open_telemetry
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.access_loggers.open_telemetry.v3.OpenTelemetryAccessLogConfig
                common_config:
                  grpc_service:
                    envoy_grpc:
                      cluster_name: otel_collector_grpc_cluster
                body:
                  string_value: |
                    [%START_TIME%] %REQ(:METHOD)% %REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%
                    -> %RESPONSE_CODE% flags=%RESPONSE_FLAGS%
```

### Distributed Tracing

OpenTelemetry tracing configuration:

```yaml
            tracing:
              provider:
                name: envoy.tracers.opentelemetry
                typed_config:
                  "@type": type.googleapis.com/envoy.config.trace.v3.OpenTelemetryConfig
                  service_name: "ReverseProxy"
                  grpc_service:
                    envoy_grpc:
                      cluster_name: "otel_collector_grpc_cluster"
```

### Metrics Collection

Stats sink for metrics export:

```yaml
stats_sinks:
- name: envoy.stat_sinks.open_telemetry
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.stat_sinks.open_telemetry.v3.SinkConfig
    grpc_service:
      envoy_grpc:
        cluster_name: otel_collector_grpc_cluster
```

### Admin Interface

Management and debugging interface:

```yaml
admin:
  access_log_path: /tmp/admin_access.log
  address:
    socket_address: { address: 0.0.0.0, port_value: 9901 }
```

**Available endpoints:**
- `/stats`: Runtime statistics
- `/clusters`: Cluster status
- `/config_dump`: Current configuration
- `/ready`: Readiness check

## Security Features

### Authentication Integration

External authorization with the Auth service:

```yaml
                  grpc_service:
                    google_grpc:
                      target_uri: "$AUTH_HOST:$AUTH_PORT"
                      stat_prefix: ext_authz
```

**Flow:**
1. Client request arrives at Envoy
2. Envoy calls Auth service for authorization
3. Auth service validates JWT tokens from cookies
4. Request proceeds or is rejected based on auth result

### Rate Limiting

Multiple rate limiting strategies:

#### Global Rate Limiting
```yaml
              token_bucket:
                max_tokens: 50
                tokens_per_fill: 50
                fill_interval: 1s
```

#### Per-Route Rate Limiting
Different limits for different endpoints based on sensitivity.

### CORS Security

Comprehensive CORS policy:

```yaml
          allow_origin_string_match: $PROCESSED_ORIGINS
          allow_methods: "GET,POST,PUT,DELETE,OPTIONS"
          allow_credentials: true
          max_age: "1728000"
```

## Deployment

### Docker Swarm Configuration

Envoy deployment in Docker Swarm:

```yaml
# envoy.stack.debug.yaml
services:
  app:
    image: envoyproxy/envoy:v1.34-latest
    networks:
      - net
    ports:
      - "11000:443"  # HTTPS
      - "4000:9901"  # Admin interface
    configs:
      - source: envoy_config
        target: /etc/envoy/envoy.yaml
      - source: envoy_clusters
        target: /etc/envoy/discovery/envoy.cds.yaml
      - source: envoy_routes
        target: /etc/envoy/discovery/envoy.rds.yaml
```

### Configuration Management

Dynamic configuration updates:

```bash
# Update route configuration
docker config create envoy_routes_v2 envoy.rds.yaml
docker service update --config-rm envoy_routes_v1 --config-add source=envoy_routes_v2,target=/etc/envoy/discovery/envoy.rds.yaml envoy_app
```

### Environment Variables

Configuration templating with environment variables:

```yaml
# In envoy.rds.yaml
domains: [$ALLOWED_HOSTS]
allow_origin_string_match: $PROCESSED_ORIGINS

# In envoy.cds.yaml
address: { socket_address: { address: $AUTH_HOST, port_value: $AUTH_PORT } }
```

## Performance Tuning

### Connection Management

HTTP/2 connection settings:

```yaml
    typed_extension_protocol_options:
      envoy.extensions.upstreams.http.v3.HttpProtocolOptions:
        "@type": type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions
        explicit_http_config:
          http2_protocol_options:
            max_concurrent_streams: 100
            initial_stream_window_size: 65536
```

### Load Balancing

Round-robin load balancing with health checking:

```yaml
    lb_policy: round_robin
    health_checks:
    - timeout: 1s
      interval: 5s
      unhealthy_threshold: 2
      healthy_threshold: 2
```

### Circuit Breaking

Protect backend services from overload:

```yaml
    circuit_breakers:
      thresholds:
      - priority: DEFAULT
        max_connections: 1024
        max_pending_requests: 1024
        max_requests: 1024
        max_retries: 3
```

## Troubleshooting

### Common Issues

#### Configuration Errors
- **Invalid YAML**: Validate configuration syntax
- **Missing references**: Ensure all referenced clusters/routes exist
- **Type mismatches**: Verify protobuf type URLs

#### Connectivity Issues
- **Certificate problems**: Check TLS certificate configuration
- **DNS resolution**: Verify service discovery settings
- **Port conflicts**: Ensure ports are available and correctly mapped

#### Performance Problems
- **High latency**: Check upstream service health
- **Connection limits**: Review circuit breaker settings
- **Memory usage**: Monitor Envoy resource consumption

### Debugging Tools

#### Admin Interface
Access debugging information:

```bash
# View current configuration
curl http://localhost:9901/config_dump

# Check cluster status
curl http://localhost:9901/clusters

# View runtime statistics
curl http://localhost:9901/stats
```

#### Logging Configuration

Enhanced logging for debugging:

```yaml
# Add to envoy.yaml for debug logging
static_resources:
  listeners:
  - name: http_listener
    # ... other config
    access_log:
    - name: envoy.access_loggers.file
      typed_config:
        "@type": type.googleapis.com/envoy.extensions.access_loggers.file.v3.FileAccessLog
        path: "/tmp/access.log"
        format: |
          [%START_TIME%] "%REQ(:METHOD)% %REQ(X-ENVOY-ORIGINAL-PATH?:PATH)% %PROTOCOL%"
          %RESPONSE_CODE% %RESPONSE_FLAGS% %BYTES_RECEIVED% %BYTES_SENT%
          %DURATION% %RESP(X-ENVOY-UPSTREAM-SERVICE-TIME)% "%REQ(X-FORWARDED-FOR)%"
          "%REQ(USER-AGENT)%" "%REQ(X-REQUEST-ID)%" "%REQ(:AUTHORITY)%" "%UPSTREAM_HOST%"
```

### Monitoring and Alerting

Key metrics to monitor:

- **Request rate**: Requests per second
- **Error rate**: 4xx/5xx response percentage
- **Latency**: Response time percentiles
- **Upstream health**: Backend service availability
- **Connection count**: Active connections

## Related Features

- [gRPC Services](grpc-services.md) - Backend service implementation
- [gRPC-Web Client Integration](grpc-web-client.md) - Frontend client setup
- [Rate Limiting](../security/rate-limiting.md) - Request rate limiting
- [CORS Configuration](../security/cors-configuration.md) - Cross-origin setup
- [JWT Validation](../security/jwt-validation.md) - Authentication integration