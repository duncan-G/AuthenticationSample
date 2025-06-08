# Envoy Proxy Configuration

This directory contains the configuration files for Envoy proxy, which acts as an API gateway and service mesh for the microservices. The configuration supports HTTP/1.1, HTTP/2, and HTTP/3 (QUIC) protocols, with TLS encryption and modern features like gRPC-Web.

## Configuration Files

### 1. `envoy.yaml` (Main Configuration)
The primary configuration file that sets up the proxy's core functionality:

- **Admin Interface**
  - Port: 9901 (default Envoy admin port)
  - Access logs: `/tmp/admin_access.log`
  - Used for monitoring and runtime management

- **Listeners**
  - HTTP/1.1 and HTTP/2 (TLS) on TCP port 10000
  - HTTP/3 (QUIC) on UDP port 10000
  - Aspire Dashboard on port 20000
  - pgAdmin on port 20001
  - All listeners share the same routing and filter configuration
  - Supports automatic protocol detection
  - Includes HTTP/3 support advertisement via Alt-Svc header

- **Security**
  - TLS configuration for both HTTP/2 and HTTP/3
  - Uses Secret Discovery Service (SDS) for certificate management
  - ALPN protocols: "h2", "http/1.1" for HTTP/2, "h3" for HTTP/3

- **HTTP Filters** (in order)
  1. gRPC-Web filter for handling gRPC-web traffic
  2. CORS filter for cross-origin requests
  3. Router filter (must be last)

- **Observability**
  - OpenTelemetry integration for tracing and logging
  - Custom access logging format
  - Service name and instance ID tracking

### 2. `discovery/envoy.rds.yaml` (Routing Configuration)
Defines how incoming requests are routed to backend services:

- **Virtual Host**
  - Name: `service_routes_virtual_host`
  - Domains: `localhost`, `localhost:10000`
  - Routes:
    - `/authentication/` → `authentication_cluster` with prefix rewrite

- **CORS Configuration**
  - Allowed origin: `https://localhost:3000`
  - Methods: GET, POST, PUT, DELETE, OPTIONS
  - Headers: Standard HTTP headers + gRPC-web specific headers
  - Preflight cache: 20 days (1,728,000 seconds)
  - Exposed headers: gRPC status and message headers

### 3. `discovery/envoy.cds.yaml` (Cluster Configuration)
Defines upstream service clusters:

- **Authentication Cluster**
  - Name: `authentication_cluster`
  - Type: Logical DNS
  - Load balancing: Round-robin
  - Protocol: HTTP/2
  - Endpoint: `authentication_app:10000`
  - Connection timeout: 1 second

### 4. `discovery/envoy.sds.yaml` (TLS Configuration)
Manages TLS certificates using Envoy's Secret Discovery Service (SDS):

- **Secret Resource**
  - Name: `tls_sds`
  - Type: TLS certificate
  - Certificate chain: `/etc/envoy/certs/cert.pem`
  - Private key: `/etc/envoy/certs/cert.key`

## Features

- **Protocol Support**
  - HTTP/1.1
  - HTTP/2 (with TLS)
  - HTTP/3 (QUIC)
  - gRPC-Web

- **Security**
  - TLS encryption
  - CORS protection
  - Secret management via SDS

- **Performance**
  - HTTP/2 and HTTP/3 support
  - Connection pooling
  - Load balancing
  - Long-lived connections

- **Monitoring**
  - Admin interface
  - OpenTelemetry integration
  - Access logging
  - Statistics

## Usage

1. Ensure TLS certificates are in place at `/etc/envoy/certs/`
2. Start Envoy with the main configuration:
   ```bash
   envoy -c /etc/envoy/envoy.yaml
   ```

## Notes

- The configuration is designed for a microservices architecture
- All services are expected to run on port 10000 by default
- CORS is configured for web applications running on `https://localhost:3000`
- gRPC-Web support is included for modern microservices
- No timeouts are set for gRPC streams to support long-running operations
- OpenTelemetry integration provides comprehensive observability
- Additional services (Aspire Dashboard, pgAdmin) are exposed on ports 20000 and 20001 respectively 