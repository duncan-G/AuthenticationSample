# Features Documentation

This section contains detailed documentation for all features implemented in the authentication system, organized by functional area.

## Feature Categories

### 🔐 [Authentication Features](authentication/)
Core authentication functionality including user registration, login, and session management.

- [User Signup](authentication/user-signup.md) - User registration with password and passwordless options
- [User Signin](authentication/user-signin.md) - Multiple authentication methods (Google, Apple, email, passkey)
- [Verification Codes](authentication/verification-codes.md) - Email verification system with resend functionality
- [Session Management](authentication/session-management.md) - JWT tokens and refresh token handling
- [Social Authentication](authentication/social-authentication.md) - Google and Apple OAuth integration

### 🛡️ [Security Features](security/)
Security mechanisms and protective measures implemented throughout the system.

- [Rate Limiting](security/rate-limiting.md) - Redis-based sliding and fixed window algorithms
- [JWT Validation](security/jwt-validation.md) - Token security and validation mechanisms
- [Error Handling](security/error-handling.md) - Comprehensive error handling with friendly messages
- [CORS Configuration](security/cors-configuration.md) - Cross-origin resource sharing policies

### 🏗️ [Infrastructure Features](infrastructure/)
Infrastructure components and deployment configurations.

- [Terraform Deployment](infrastructure/terraform-deployment.md) - Infrastructure as Code with single-AZ configuration
- [Docker Containerization](infrastructure/docker-containerization.md) - Container orchestration with Docker Swarm
- [Monitoring & Observability](infrastructure/monitoring-observability.md) - OpenTelemetry and Aspire dashboard
- [Load Balancing](infrastructure/load-balancing.md) - Envoy proxy and AWS Network Load Balancer

### 🛠️ [Development Features](development/)
Tools and processes for local development and testing.

- [Local Setup](development/local-setup.md) - Development environment configuration
- [Testing Framework](development/testing-framework.md) - Unit, integration, and end-to-end testing
- [Debugging Tools](development/debugging-tools.md) - Development debugging and profiling
- [Code Generation](development/code-generation.md) - gRPC client and error code generation

### 🔌 [API Features](api-gateway/)
API design, gRPC services, and client integration.

- [gRPC Services](api-gateway/grpc-services.md) - Service architecture and SignUpService implementation
- [Protocol Buffers](api-gateway/protocol-buffers.md) - Message definitions and schema management
- [Client Code Generation](api-gateway/client-code-generation.md) - gRPC-Web integration and code generation

## Feature Documentation Template

Each feature document follows a consistent structure:

1. **Overview** - Purpose and functionality description
2. **Implementation** - Technical implementation details
3. **Configuration** - Setup and customization options
4. **Usage** - Developer/operator usage instructions
5. **Testing** - Validation and testing procedures
6. **Troubleshooting** - Common issues and solutions
7. **Related Features** - Cross-references to related functionality

## Contributing to Documentation

When adding new features or updating existing ones:

1. Follow the established template structure
2. Use consistent formatting and terminology
3. Include practical examples and code snippets
4. Update cross-references to related features
5. Validate all links and references work correctly

---

*For setup guides and architectural overviews, see the [Guides](../guides/) section.*