# Envoy Proxy Configuration Documentation

## What is Envoy and Why We Use It

Envoy is a modern, high-performance edge and service proxy that acts as a "universal data plane" for our microservices architecture. We use it because:

1. **Protocol Support**: It natively supports multiple protocols (HTTP/1.1, HTTP/2, HTTP/3, gRPC-Web) simultaneously, allowing us to gradually adopt newer protocols without breaking existing clients. The gRPC-Web support enables browser-based applications to communicate with gRPC services.

2. **Advanced Load Balancing**: Unlike simpler proxies, Envoy provides sophisticated load balancing algorithms and health checking, crucial for maintaining high availability in our microservices.

3. **Observability**: Built-in support for distributed tracing, metrics, and logging helps us understand and debug our system's behavior in production.

4. **Dynamic Configuration**: Envoy's discovery services (CDS, RDS, SDS) allow us to update routing and service discovery without restarting the proxy, reducing downtime.

## How Our Configuration Works

### Configuration Architecture

We split our configuration into multiple files for specific reasons:

1. `envoy.yaml` - Contains static configuration that rarely changes:
   - Listener definitions (where Envoy accepts traffic)
   - Filter chains (how traffic is processed)
   - Basic cluster definitions (where traffic is routed to)
   - Admin interface settings

2. `discovery/` directory - Contains dynamic configurations that can change without restart:
   - `envoy.cds.yaml` - Defines upstream services (clusters) that Envoy can route to
   - `envoy.rds.yaml` - Defines how requests are routed to different services
   - `envoy.sds.yaml` - Manages TLS certificates and secrets

This separation allows us to:
- Update service endpoints without restarting Envoy
- Modify routing rules on the fly
- Rotate TLS certificates without downtime

### Port Configuration Explained

Our port setup is designed for both security and development convenience:

```
443 (HTTPS) → 10000 (dev)
```
- Port 443 is the standard HTTPS port, but we map it to 10000 in development to avoid requiring root privileges
- This port handles HTTP/1.1, HTTP/2, and HTTP/3 traffic, with automatic protocol detection
- TLS termination happens here, meaning all internal traffic can be unencrypted for better performance

```
9901 (Admin) → 4000 (dev)
```
- The admin interface provides real-time insights into Envoy's operation
- We map it to 4000 in development to avoid conflicts
- This interface should be secured in production as it provides sensitive operational data

```
20000 (Aspire) → 4001 (dev)
```
- Dedicated port for the Aspire dashboard to isolate its traffic
- Uses HTTP/1.1 because Aspire's client doesn't support HTTP/2
- Configured with no timeout (0s) because Aspire maintains long-lived connections for real-time updates
- This isolation prevents Aspire's traffic patterns from affecting other services

```
20001 (PgAdmin) → 4002 (dev)
```
- Separate port for PgAdmin to maintain security isolation
- Uses HTTP/1.1 as PgAdmin's web interface doesn't require HTTP/2
- Includes detailed access logging for database administration auditing

### Understanding Our Listeners

#### HTTP/HTTPS Listener (Port 443)
This is our main traffic ingress point. Here's how it works:

1. **TLS Termination**:
   ```yaml
   transport_socket:
     name: envoy.transport_sockets.tls
     typed_config:
       "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.DownstreamTlsContext
   ```
   - Decrypts incoming HTTPS traffic
   - Supports both HTTP/1.1 and HTTP/2 via ALPN negotiation
   - Certificates are managed through SDS for dynamic updates

2. **Protocol Support**:
   ```yaml
   codec_type: auto
   ```
   - Automatically detects and handles HTTP/1.1 and HTTP/2
   - Uses ALPN to negotiate the best protocol with clients
   - Maintains backward compatibility while enabling modern protocols

3. **gRPC-Web Support**:
   ```yaml
   - name: envoy.filters.http.grpc_web
   ```
   - Allows browser clients to make gRPC calls
   - Translates between HTTP/1.1 and gRPC protocols
   - Essential for our microservices that use gRPC internally

4. **CORS Configuration**:
   ```yaml
   - name: envoy.filters.http.cors
   ```
   - Enables cross-origin requests from our frontend
   - Configures allowed methods, headers, and origins
   - Critical for our web application's functionality

#### QUIC Listener (Port 443 UDP)
Our HTTP/3 implementation:

1. **Why HTTP/3**:
   - Uses QUIC protocol for improved performance
   - Better handling of network changes and packet loss
   - Reduced latency for mobile clients

2. **Configuration**:
   ```yaml
   udp_listener_config:
     quic_options: {}
   ```
   - Shares the same routing rules as HTTP/HTTPS
   - Uses the same TLS certificates
   - Enables gradual adoption of HTTP/3

### Cluster Configuration Deep Dive

#### Authentication Cluster
```yaml
name: authentication_cluster
type: logical_dns
lb_policy: round_robin
```
- Uses `logical_dns` for DNS-based service discovery
- Round-robin load balancing distributes traffic evenly
- HTTP/2 enabled for better performance with gRPC
- TLS enabled for secure service-to-service communication

#### Aspire Dashboard Cluster
```yaml
name: aspire_dashboard_cluster
type: strict_dns
```
- `strict_dns` ensures immediate DNS resolution
- No timeout (0s) to support long-lived connections
- HTTP/1.1 as Aspire's client doesn't support HTTP/2

### Routing Logic Explained

Our routing configuration (`envoy.rds.yaml`) implements:

1. **Virtual Hosts**:
   ```yaml
   virtual_hosts:
     - name: service_routes_virtual_host
       domains: ["localhost", "localhost:10000"]
   ```
   - Defines which domains this configuration applies to
   - Allows different routing rules for different domains

2. **CORS Policy**:
   ```yaml
   allow_origin_string_match:
     - prefix: "https://localhost:3000"
   allow_methods: "GET,POST,PUT,DELETE,OPTIONS"
   ```
   - Restricts access to our frontend application
   - Enables necessary HTTP methods
   - Configures preflight request handling

3. **Route Rules**:
   ```yaml
   routes:
     - match:
         prefix: "/authentication/"
       route:
         cluster: authentication_cluster
         prefix_rewrite: "/"
   ```
   - Matches URL patterns to services
   - Rewrites paths as needed
   - Configures timeouts and retry policies

### Security Implementation

1. **TLS Management**:
   ```yaml
   tls_certificate_sds_secret_configs:
     - name: tls_sds
   ```
   - Certificates managed through Docker secrets
   - Dynamic updates without restart
   - Separate certificates for different domains

2. **CORS Security**:
   - Strict origin checking
   - Limited set of allowed methods
   - Specific header restrictions

### Observability Stack

1. **OpenTelemetry Integration**:
   ```yaml
   tracing:
     provider:
       name: envoy.tracers.opentelemetry
   ```
   - Distributed tracing across services
   - Correlation of requests across the system
   - Performance monitoring

2. **Access Logging**:
   ```yaml
   access_log:
     - name: envoy.access_loggers.open_telemetry
   ```
   - Structured logging for better analysis
   - Includes request/response details
   - Helps with debugging and monitoring

## Development and Deployment

### Development Environment
The `envoy.stack.debug.yaml` provides:

1. **Resource Limits**:
   ```yaml
   resources:
     limits:
       cpus: '0.50'
       memory: 1024M
   ```
   - Prevents development environment from consuming too many resources
   - Simulates production constraints

2. **Update Strategy**:
   ```yaml
   update_config:
     parallelism: 1
     failure_action: rollback
   ```
   - Safe updates with rollback capability
   - Prevents service disruption during updates

### Production Considerations

1. **Resource Planning**:
   - Monitor CPU and memory usage
   - Adjust limits based on traffic patterns
   - Consider horizontal scaling for high traffic

2. **Security Hardening**:
   - Secure admin interface
   - Regular certificate rotation
   - Strict CORS policies

3. **Monitoring Setup**:
   - Alert on error rates
   - Monitor latency
   - Track resource usage

## Troubleshooting Guide

### Common Issues and Solutions

1. **TLS Certificate Issues**:
   - Check certificate expiration
   - Verify certificate chain
   - Ensure proper SDS configuration

2. **Routing Problems**:
   - Verify virtual host configuration
   - Check cluster health
   - Review access logs

3. **Performance Issues**:
   - Monitor resource usage
   - Check for connection limits
   - Review timeout settings

### Debugging Tools

1. **Admin Interface** (port 9901):
   - `/clusters` - View cluster health
   - `/listeners` - Check listener status
   - `/config_dump` - Export current configuration

2. **Access Logs**:
   - Review request patterns
   - Identify error sources
   - Monitor performance

## Future Roadmap

1. **Protocol Evolution**:
   - Monitor HTTP/3 adoption
   - Plan for new protocol versions
   - Consider WebSocket support

2. **Security Enhancements**:
   - Implement mTLS
   - Add rate limiting
   - Enhance CORS policies

3. **Observability Improvements**:
   - Enhanced metrics
   - Better tracing integration
   - Custom logging formats
