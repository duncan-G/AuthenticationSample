# Development Features

This section documents the tools, processes, and frameworks that support local development, testing, and debugging of the authentication system.

## Features Overview

### [Local Setup](local-setup.md)
Complete development environment configuration with automated setup scripts, service orchestration, and environment management.

**Key capabilities:**
- Automated setup with `./setup.sh` for dependencies and Docker images
- Service orchestration with Docker Swarm for local development
- Environment variable management with AWS Secrets Manager integration
- Individual service startup options (database, microservices, client, proxy)
- SSL certificate generation for local HTTPS development
- Hot reload support for frontend and backend services

### [Testing Framework](testing-framework.md)
Comprehensive testing infrastructure supporting unit, integration, and end-to-end testing across the entire stack.

**Key capabilities:**
- Frontend testing with Jest, React Testing Library, and jsdom environment
- Backend testing with xUnit, Moq, and ASP.NET Core Test Host
- gRPC service testing with test clients and mock implementations
- Integration testing with TestContainers and real service communication
- Rate limiting and authentication flow testing
- Test coverage reporting and quality metrics

### [Debugging Tools](debugging-tools.md)
Advanced debugging, profiling, and diagnostic tools for development troubleshooting and performance analysis.

**Key capabilities:**
- Aspire dashboard for distributed tracing and service observability
- gRPC service debugging with reflection and command-line tools
- Frontend debugging with React DevTools and network inspection
- Database debugging with PgAdmin interface and query analysis
- Performance profiling with dotnet-trace and browser dev tools
- Centralized logging with structured log analysis

### [Code Generation](code-generation.md)
Automated code generation system for maintaining type safety and consistency across frontend and backend codebases.

**Key capabilities:**
- gRPC client generation from protocol buffer definitions to TypeScript
- Protocol buffer compilation with Docker-based protoc toolchain
- Error code generation from .NET enums to TypeScript constants
- Type-safe client library generation with full IntelliSense support
- Build integration with npm scripts and automated regeneration
- Validation testing for generated code correctness

## Development Workflow

The development process follows established patterns for efficient development:

1. **Initial Setup**: Run `./setup.sh` for automated environment configuration
2. **Service Startup**: Use `./start.sh -a` for full environment or individual components
3. **Development**: Hot-reload enabled for both frontend (Next.js) and backend (.NET)
4. **Code Generation**: Automatic gRPC client and error code generation
5. **Testing**: Continuous testing with watch modes and real-time feedback
6. **Debugging**: Integrated debugging with Aspire dashboard and IDE tools
7. **Validation**: Pre-commit hooks, linting, and automated CI validation

## Development Environment

### Local Services
- **Frontend**: Next.js development server with Turbopack and hot reload
- **Backend**: .NET gRPC services with hot reload and debugging support
- **Database**: PostgreSQL with PgAdmin web interface for inspection
- **Cache**: Redis with monitoring and debugging tools
- **Proxy**: Envoy API gateway with admin interface and reflection
- **Observability**: Aspire dashboard with OpenTelemetry integration

### Development Tools
- **Aspire Dashboard**: Distributed tracing, metrics, and service monitoring
- **Docker Desktop**: Container orchestration with Docker Swarm
- **IDE Integration**: VS Code and JetBrains with debugging configurations
- **Code Generation**: Automated gRPC client and type generation
- **Testing Tools**: Jest, xUnit, and specialized gRPC testing utilities

## Testing Strategy

### Test Types
- **Unit Tests**: Component, service, and utility function testing
- **Integration Tests**: gRPC service communication and database integration
- **End-to-End Tests**: Complete authentication workflows and user journeys
- **Performance Tests**: Load testing and response time validation
- **Security Tests**: Authentication, authorization, and rate limiting validation

### Test Infrastructure
- **Frontend**: Jest with React Testing Library and jsdom environment
- **Backend**: xUnit with Moq for mocking and ASP.NET Core Test Host
- **gRPC Testing**: Test clients with mock implementations and real service testing
- **Test Containers**: Isolated environments with Docker-based test services
- **CI/CD Integration**: Automated testing with coverage reporting

## Code Quality

### Standards and Conventions
- **Code Formatting**: EditorConfig for consistency, Prettier for TypeScript
- **Linting**: ESLint for TypeScript, Roslyn analyzers for .NET
- **Type Safety**: Strict TypeScript configuration and .NET nullable reference types
- **Documentation**: Comprehensive inline documentation and feature guides

### Automation
- **Code Generation**: Automated gRPC client and error code generation
- **Pre-commit Hooks**: Code formatting, linting, and basic validation
- **CI Validation**: Comprehensive testing, coverage, and quality checks
- **Type Safety**: Generated types ensure compile-time safety across the stack

## Integration Points

Development features integrate with:

- **Application Code**: Hot reload and debugging support
- **Infrastructure**: Local development environment consistency
- **CI/CD**: Automated testing and validation pipelines
- **Monitoring**: Development observability and debugging

## Getting Started

For new developers joining the project:

1. **Prerequisites**: Install Docker Desktop, .NET SDK 9.0, Node.js 22+, and bash
2. **Initial Setup**: Run `./setup.sh` for automated environment configuration
3. **Start Services**: Use `./start.sh -a` to start the complete development environment
4. **Verify Setup**: Access Aspire dashboard (http://localhost:18888) and frontend (https://localhost:3000)
5. **Development**: Begin coding with hot reload enabled for both frontend and backend
6. **Testing**: Run `npm test` (frontend) and `dotnet test` (backend) to verify functionality

---

*For detailed setup instructions, see the [Developer Setup Guide](../../guides/developer-setup.md).*