# Testing Framework

## Overview

The testing framework provides comprehensive test coverage across the entire authentication system, supporting unit tests, integration tests, and end-to-end tests. The framework uses Jest for frontend testing and xUnit for .NET backend testing, with specialized tools for gRPC service testing and authentication flow validation.

## Implementation

### Frontend Testing Architecture

The frontend uses Jest with React Testing Library for comprehensive testing:

```typescript
// Jest Configuration (jest.config.js)
const nextJest = require('next/jest')

const createJestConfig = nextJest({
  dir: './',
})

const customJestConfig = {
  setupFilesAfterEnv: ['<rootDir>/jest.setup.js'],
  testEnvironment: 'jsdom',
  moduleNameMapping: {
    '^@/(.*)$': '<rootDir>/src/$1',
  },
  collectCoverageFrom: [
    'src/**/*.{js,jsx,ts,tsx}',
    '!src/**/*.d.ts',
    '!src/app/layout.tsx',
  ],
}
```

### Backend Testing Architecture

The .NET backend uses xUnit with Moq for mocking and ASP.NET Core testing utilities:

```xml
<!-- Unit Test Project Configuration -->
<PackageReference Include="xunit" Version="2.9.2"/>
<PackageReference Include="xunit.runner.visualstudio" Version="2.8.2"/>
<PackageReference Include="Moq" Version="4.20.72"/>
<PackageReference Include="Microsoft.Extensions.Logging.Abstractions" Version="9.0.9"/>

<!-- Integration Test Project Configuration -->
<PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="9.0.9" />
<PackageReference Include="Grpc.Net.Client" Version="2.71.0" />
<PackageReference Include="Grpc.Core.Testing" Version="2.46.6" />
```

### Test Categories

#### Unit Tests
- **Frontend**: Component testing, hook testing, utility function testing
- **Backend**: Service layer testing, domain logic testing, validator testing
- **Shared**: Library function testing, utility testing

#### Integration Tests
- **gRPC Services**: End-to-end service testing with real gRPC clients
- **Database Integration**: Repository pattern testing with test databases
- **Authentication Flow**: Complete authentication workflow testing
- **Rate Limiting**: Rate limiting behavior testing with Redis

#### End-to-End Tests
- **User Workflows**: Complete user signup and signin flows
- **Error Handling**: Error scenario testing across the entire stack
- **Security Testing**: Authentication and authorization testing
- **Performance Testing**: Load testing and response time validation

## Configuration

### Frontend Test Setup

The Jest setup file configures the testing environment:

```javascript
// jest.setup.js
import '@testing-library/jest-dom'

// Environment variables for testing
process.env.NEXT_PUBLIC_AUTH_SERVICE_URL = 'http://localhost:8080'
process.env.NEXT_PUBLIC_GREETER_SERVICE_URL = 'http://localhost:8081'

// Mock gRPC clients with realistic behavior
jest.mock('@/lib/services/grpc-clients', () => {
  const { SignUpStep } = require('@/lib/services/auth/sign-up/sign-up_pb')
  
  const createSignUpServiceClient = () => ({
    initiateSignUpAsync: jest.fn((request) => {
      const requirePassword = request.getRequirePassword()
      const next = requirePassword ? SignUpStep.PASSWORD_REQUIRED : SignUpStep.VERIFICATION_REQUIRED
      return Promise.resolve({ getNextStep: () => next })
    }),
    verifyAndSignInAsync: jest.fn(() => {
      return Promise.resolve({ getNextStep: () => SignUpStep.SIGN_IN_REQUIRED })
    }),
    resendVerificationCodeAsync: jest.fn(() => Promise.resolve({})),
  })
  
  return { createSignUpServiceClient, createGreeterServiceClient }
})
```

### Backend Test Configuration

Integration tests use the ASP.NET Core Test Host:

```csharp
// TestAuthWebApplicationFactory.cs
public class TestAuthWebApplicationFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Replace production services with test doubles
            services.RemoveAll<ICognitoIdentityGateway>();
            services.AddSingleton<ICognitoIdentityGateway, MockCognitoIdentityGateway>();
        });
    }
}
```

### Test Data Management

Test data is managed through:

- **Frontend**: Mock data generators and fixtures
- **Backend**: Test data builders and object mothers
- **Integration**: Test containers with seeded data
- **E2E**: Automated test user creation and cleanup

## Usage

### Running Frontend Tests

```bash
cd clients/auth-sample

# Run all tests
npm test

# Run tests in watch mode
npm run test:watch

# Run tests with coverage
npm run test:coverage

# Run specific test file
npm test -- signup-verification.test.tsx

# Run tests matching pattern
npm test -- --testNamePattern="resend"
```

### Running Backend Tests

```bash
cd microservices/Auth

# Run all tests
dotnet test

# Run specific test project
dotnet test tests/Auth.UnitTests

# Run tests with coverage
dotnet test --collect:"XPlat Code Coverage"

# Run specific test class
dotnet test --filter "ClassName=IdentityServiceTests"

# Run tests matching pattern
dotnet test --filter "Name~Resend"
```

### Test Categories and Patterns

#### Frontend Component Testing

```typescript
// Component test example
describe('SignupVerification', () => {
  it('should display resend button after initial verification fails', async () => {
    const mockResend = jest.fn()
    render(<SignupVerification onResendCode={mockResend} />)
    
    // Simulate verification failure
    const verifyButton = screen.getByRole('button', { name: /verify/i })
    await user.click(verifyButton)
    
    // Check resend button appears
    expect(screen.getByRole('button', { name: /resend/i })).toBeInTheDocument()
  })
})
```

#### Backend Service Testing

```csharp
// Service test example
[Fact]
public async Task ResendVerificationCode_ShouldCallCognito_WhenValidRequest()
{
    // Arrange
    var request = new ResendSignUpVerificationRequest { Email = "test@example.com" };
    var mockGateway = new Mock<ICognitoIdentityGateway>();
    var service = new IdentityService(mockGateway.Object);
    
    // Act
    await service.ResendSignUpVerificationCodeAsync(request);
    
    // Assert
    mockGateway.Verify(x => x.ResendConfirmationCodeAsync(request.Email), Times.Once);
}
```

#### Integration Testing

```csharp
// Integration test example
[Fact]
public async Task ResendVerificationCode_Integration_ShouldReturnSuccess()
{
    // Arrange
    using var factory = new TestAuthWebApplicationFactory();
    var client = factory.CreateGrpcClient<SignUpService.SignUpServiceClient>();
    
    // Act
    var response = await client.ResendVerificationCodeAsync(new ResendVerificationCodeRequest
    {
        Email = "integration-test@example.com"
    });
    
    // Assert
    Assert.NotNull(response);
}
```

### Test Execution Strategies

#### Continuous Testing
- **Watch Mode**: Automatic test execution on file changes
- **Incremental Testing**: Only run tests affected by changes
- **Parallel Execution**: Run tests in parallel for faster feedback

#### CI/CD Integration
- **Pre-commit Hooks**: Run fast tests before commits
- **Pull Request Validation**: Full test suite on PR creation
- **Deployment Gates**: All tests must pass before deployment

## Testing

### Test Coverage Metrics

#### Frontend Coverage Targets
- **Statements**: >90%
- **Branches**: >85%
- **Functions**: >90%
- **Lines**: >90%

#### Backend Coverage Targets
- **Line Coverage**: >85%
- **Branch Coverage**: >80%
- **Method Coverage**: >90%

### Test Quality Metrics

#### Test Reliability
- **Flaky Test Detection**: Automated detection of unreliable tests
- **Test Isolation**: Each test runs independently
- **Deterministic Results**: Tests produce consistent results

#### Test Performance
- **Execution Time**: Unit tests <100ms, Integration tests <5s
- **Parallel Execution**: Tests can run concurrently
- **Resource Usage**: Minimal memory and CPU usage

### Specialized Testing

#### gRPC Service Testing

```csharp
// gRPC service test with test client
[Fact]
public async Task SignUpService_ShouldHandleValidRequest()
{
    // Arrange
    var testServer = new TestServer(new WebHostBuilder()
        .UseStartup<TestStartup>());
    var client = new SignUpService.SignUpServiceClient(
        testServer.CreateGrpcChannel());
    
    // Act
    var response = await client.InitiateSignUpAsync(new InitiateSignUpRequest
    {
        Email = "test@example.com",
        RequirePassword = true
    });
    
    // Assert
    Assert.Equal(SignUpStep.PasswordRequired, response.NextStep);
}
```

#### Rate Limiting Testing

```typescript
// Rate limiting test
describe('Rate Limiting', () => {
  it('should enforce rate limits on resend requests', async () => {
    const { result } = renderHook(() => useAuth())
    
    // Make multiple rapid requests
    for (let i = 0; i < 6; i++) {
      await act(async () => {
        await result.current.resendVerificationCode('test@example.com')
      })
    }
    
    // Verify rate limit error
    expect(mockHandleApiError).toHaveBeenCalledWith(
      expect.objectContaining({ code: 'RATE_LIMIT_EXCEEDED' })
    )
  })
})
```

#### Authentication Flow Testing

```typescript
// End-to-end authentication flow test
describe('Authentication Flow', () => {
  it('should complete full signup and signin flow', async () => {
    render(<AuthFlow />)
    
    // Step 1: Initiate signup
    await user.type(screen.getByLabelText(/email/i), 'test@example.com')
    await user.click(screen.getByRole('button', { name: /sign up/i }))
    
    // Step 2: Enter verification code
    await user.type(screen.getByLabelText(/verification code/i), '123456')
    await user.click(screen.getByRole('button', { name: /verify/i }))
    
    // Step 3: Verify successful completion
    expect(screen.getByText(/welcome/i)).toBeInTheDocument()
  })
})
```

## Troubleshooting

### Common Test Issues

#### Frontend Test Failures

```bash
# Clear Jest cache
npm test -- --clearCache

# Update snapshots
npm test -- --updateSnapshot

# Debug specific test
npm test -- --verbose signup-verification.test.tsx
```

#### Backend Test Failures

```bash
# Clean and rebuild
dotnet clean
dotnet build

# Run tests with detailed output
dotnet test --logger "console;verbosity=detailed"

# Debug specific test
dotnet test --filter "FullyQualifiedName~ResendVerificationCode" --logger "console;verbosity=detailed"
```

#### Integration Test Issues

```bash
# Check test database connectivity
docker exec -it $(docker ps -q -f name=postgres-test) pg_isready

# Verify test services are running
docker service ls | grep test

# Check test container logs
docker service logs auth-sample-test_auth
```

### Test Environment Issues

#### Mock Configuration Problems
- Verify mock implementations match real service interfaces
- Check that mocks return realistic data structures
- Ensure async mocks properly handle Promise resolution

#### Test Data Issues
- Verify test data generators create valid data
- Check that test cleanup properly removes test data
- Ensure test isolation prevents data leakage between tests

#### Performance Issues
- Use `--maxWorkers` to limit Jest worker processes
- Implement test timeouts for long-running tests
- Use `--runInBand` for debugging test execution order

## Related Features

- [Local Setup](local-setup.md) - Setting up the testing environment
- [Debugging Tools](debugging-tools.md) - Debugging failed tests
- [Code Generation](code-generation.md) - Generating test clients
- [Error Handling](../security/error-handling.md) - Testing error scenarios
- [Rate Limiting](../security/rate-limiting.md) - Testing rate limiting behavior