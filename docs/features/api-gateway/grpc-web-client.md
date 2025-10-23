# gRPC-Web Client Integration

## Overview

gRPC-Web enables browser-based applications to communicate with gRPC services through a proxy that translates between gRPC-Web and native gRPC protocols. The frontend uses TypeScript clients generated from protocol buffer definitions, providing type-safe communication with backend services.

## Architecture

### Communication Flow

```text
Browser (gRPC-Web) → Envoy Proxy → Backend gRPC Service
                   ←              ←
```

1. **Frontend**: Makes gRPC-Web requests using generated TypeScript clients
2. **Envoy Proxy**: Translates gRPC-Web to native gRPC
3. **Backend Service**: Processes gRPC requests and returns responses
4. **Response Flow**: Reverse path with protocol translation

### Client Generation Process

```text
Protocol Buffers (.proto) → protoc-gen-grpc-web → TypeScript Clients
```

## Client Implementation

### Generated Client Structure

Each service generates multiple files:

```text
src/lib/services/auth/sign-up/
├── sign-up_pb.js           # Message definitions (JavaScript)
├── sign-up_pb.d.ts         # Message type definitions (TypeScript)
└── Sign-upServiceClientPb.ts # Service client implementation
```

### Service Client Factory

Centralized client creation with configuration:

```typescript
// src/lib/services/grpc-clients.ts
import { SignUpServiceClient } from '@/lib/services/auth/sign-up/Sign-upServiceClientPb';
import { GreeterClient } from '@/lib/services/auth/greet/GreetServiceClientPb';
import { createTraceUnaryInterceptor } from '@/lib/services/trace-interceptor';
import { config } from '../config';

export function createSignUpServiceClient() {
  assertConfig(config);
  
  return new SignUpServiceClient(
    config.authServiceUrl!,
    null,
    { 
      unaryInterceptors: [createTraceUnaryInterceptor()], 
      withCredentials: true 
    }
  );
}

export function createGreeterClient() {
  assertConfig(config);
  
  return new GreeterClient(
    config.greeterServiceUrl!,
    null,
    { 
      unaryInterceptors: [createTraceUnaryInterceptor()], 
      withCredentials: true 
    }
  );
}
```

### Client Configuration

#### Service URLs
Environment-based service endpoint configuration:

```typescript
// src/lib/config.ts
export const config = {
  authServiceUrl: process.env.NEXT_PUBLIC_AUTH_SERVICE_URL,
  greeterServiceUrl: process.env.NEXT_PUBLIC_GREETER_SERVICE_URL,
} as const;
```

#### Client Options
- **withCredentials: true**: Enables cookie-based authentication
- **unaryInterceptors**: Adds tracing and error handling
- **format: 'text'**: Uses text-based gRPC-Web format

## Usage Patterns

### Basic Service Call

```typescript
import { createSignUpServiceClient } from '@/lib/services/grpc-clients';
import { InitiateSignUpRequest } from '@/lib/services/auth/sign-up/sign-up_pb';

const client = createSignUpServiceClient();

const request = new InitiateSignUpRequest();
request.setEmailAddress('user@example.com');
request.setRequirePassword(true);
request.setPassword('securePassword123');

try {
  const response = await client.initiateSignUpAsync(request);
  const nextStep = response.getNextStep();
  
  // Handle response based on next step
  switch (nextStep) {
    case SignUpStep.PASSWORD_REQUIRED:
      // Show password form
      break;
    case SignUpStep.VERIFICATION_REQUIRED:
      // Show verification code form
      break;
    // ... handle other steps
  }
} catch (error) {
  // Handle gRPC errors
  console.error('Sign-up failed:', error);
}
```

### React Hook Integration

Custom hook for sign-up functionality:

```typescript
// src/hooks/useAuth.ts
import { useState } from 'react';
import { createSignUpServiceClient } from '@/lib/services/grpc-clients';
import { InitiateSignUpRequest, SignUpStep } from '@/lib/services/auth/sign-up/sign-up_pb';

export function useSignUp() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  
  const initiateSignUp = async (email: string, password?: string) => {
    setLoading(true);
    setError(null);
    
    try {
      const client = createSignUpServiceClient();
      const request = new InitiateSignUpRequest();
      
      request.setEmailAddress(email);
      request.setRequirePassword(!!password);
      if (password) {
        request.setPassword(password);
      }
      
      const response = await client.initiateSignUpAsync(request);
      return response.getNextStep();
      
    } catch (err) {
      const errorMessage = extractErrorMessage(err);
      setError(errorMessage);
      throw err;
    } finally {
      setLoading(false);
    }
  };
  
  return { initiateSignUp, loading, error };
}
```

### Error Handling

Comprehensive error handling for gRPC-Web calls:

```typescript
// src/lib/services/handle-api-error.ts
import { RpcError } from 'grpc-web';

export function handleApiError(error: unknown): string {
  if (error instanceof RpcError) {
    // Extract error details from gRPC error
    const metadata = error.metadata;
    const errorCodes = metadata['error-codes'];
    const retryAfter = metadata['retry-after-seconds'];
    
    // Handle specific error codes
    switch (error.code) {
      case 14: // UNAVAILABLE
        return 'Service temporarily unavailable. Please try again.';
      case 16: // UNAUTHENTICATED
        return 'Authentication required. Please sign in.';
      case 7: // PERMISSION_DENIED
        return 'Permission denied. Please check your credentials.';
      case 8: // RESOURCE_EXHAUSTED (rate limiting)
        const retryMessage = retryAfter 
          ? `Please try again in ${retryAfter} seconds.`
          : 'Please try again later.';
        return `Too many requests. ${retryMessage}`;
      default:
        return error.message || 'An unexpected error occurred.';
    }
  }
  
  return 'Network error. Please check your connection.';
}
```

## Interceptors

### Tracing Interceptor

Adds distributed tracing to gRPC-Web calls:

```typescript
// src/lib/services/trace-interceptor.ts
import { UnaryInterceptor } from 'grpc-web';

export function createTraceUnaryInterceptor(): UnaryInterceptor<any, any> {
  return (request, invoker) => {
    // Add tracing headers
    const metadata = request.getMetadata();
    metadata['traceparent'] = generateTraceParent();
    metadata['tracestate'] = generateTraceState();
    
    // Log request
    console.debug('gRPC request:', {
      method: request.getMethodDescriptor().getName(),
      service: request.getMethodDescriptor().getService().getName()
    });
    
    return invoker(request).then(
      response => {
        console.debug('gRPC response received');
        return response;
      },
      error => {
        console.error('gRPC error:', error);
        throw error;
      }
    );
  };
}
```

### Authentication Interceptor

Handles authentication token management:

```typescript
export function createAuthInterceptor(): UnaryInterceptor<any, any> {
  return (request, invoker) => {
    // Authentication is handled via cookies (withCredentials: true)
    // Additional auth headers can be added here if needed
    
    return invoker(request).catch(error => {
      if (error.code === 16) { // UNAUTHENTICATED
        // Redirect to login or refresh token
        window.location.href = '/sign-in';
      }
      throw error;
    });
  };
}
```

## Message Handling

### Request Construction

Type-safe request building:

```typescript
import { 
  InitiateSignUpRequest, 
  VerifyAndSignInRequest,
  ResendVerificationCodeRequest 
} from '@/lib/services/auth/sign-up/sign-up_pb';

// Initiate sign-up
const initiateRequest = new InitiateSignUpRequest();
initiateRequest.setEmailAddress(email);
initiateRequest.setRequirePassword(requirePassword);
if (password) {
  initiateRequest.setPassword(password);
}

// Verify and sign in
const verifyRequest = new VerifyAndSignInRequest();
verifyRequest.setEmailAddress(email);
verifyRequest.setVerificationCode(code);
verifyRequest.setName(displayName);

// Resend verification code
const resendRequest = new ResendVerificationCodeRequest();
resendRequest.setEmailAddress(email);
```

### Response Processing

Handle different response types:

```typescript
// Process sign-up response
const response = await client.initiateSignUpAsync(request);
const nextStep = response.getNextStep();

switch (nextStep) {
  case SignUpStep.PASSWORD_REQUIRED:
    setCurrentStep('password');
    break;
  case SignUpStep.VERIFICATION_REQUIRED:
    setCurrentStep('verification');
    break;
  case SignUpStep.SIGN_IN_REQUIRED:
    router.push('/sign-in');
    break;
  case SignUpStep.REDIRECT_REQUIRED:
    router.push('/dashboard');
    break;
  default:
    console.warn('Unknown sign-up step:', nextStep);
}
```

## Testing

### Unit Testing gRPC-Web Clients

Mock gRPC-Web clients for testing:

```typescript
// src/lib/services/__tests__/grpc-clients.test.ts
import { createSignUpServiceClient } from '../grpc-clients';
import { InitiateSignUpRequest, SignUpStep } from '../auth/sign-up/sign-up_pb';

// Mock the generated client
jest.mock('../auth/sign-up/Sign-upServiceClientPb');

describe('SignUpServiceClient', () => {
  it('should create client with correct configuration', () => {
    const client = createSignUpServiceClient();
    
    expect(client).toBeDefined();
    expect(client.hostname_).toBe(process.env.NEXT_PUBLIC_AUTH_SERVICE_URL);
  });
  
  it('should handle successful sign-up initiation', async () => {
    const mockClient = createSignUpServiceClient();
    const mockResponse = { getNextStep: () => SignUpStep.VERIFICATION_REQUIRED };
    
    (mockClient.initiateSignUpAsync as jest.Mock).mockResolvedValue(mockResponse);
    
    const request = new InitiateSignUpRequest();
    request.setEmailAddress('test@example.com');
    
    const response = await mockClient.initiateSignUpAsync(request);
    
    expect(response.getNextStep()).toBe(SignUpStep.VERIFICATION_REQUIRED);
  });
});
```

### Integration Testing

Test actual gRPC-Web communication:

```typescript
// src/__tests__/integration/auth-flow.test.tsx
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { SignUpForm } from '@/components/auth/signup-form';

describe('Auth Flow Integration', () => {
  it('should complete sign-up flow', async () => {
    render(<SignUpForm />);
    
    // Fill in email
    fireEvent.change(screen.getByLabelText(/email/i), {
      target: { value: 'test@example.com' }
    });
    
    // Submit form
    fireEvent.click(screen.getByRole('button', { name: /sign up/i }));
    
    // Wait for verification step
    await waitFor(() => {
      expect(screen.getByText(/verification code/i)).toBeInTheDocument();
    });
    
    // Verify gRPC call was made
    expect(mockSignUpClient.initiateSignUpAsync).toHaveBeenCalledWith(
      expect.objectContaining({
        getEmailAddress: () => 'test@example.com'
      })
    );
  });
});
```

## Performance Optimization

### Connection Management

gRPC-Web clients reuse connections efficiently:

```typescript
// Create clients once and reuse
const signUpClient = createSignUpServiceClient();
const greeterClient = createGreeterClient();

// Reuse clients across multiple requests
export const clientInstances = {
  signUp: signUpClient,
  greeter: greeterClient
};
```

### Request Batching

For multiple related requests:

```typescript
// Batch related operations
const [signUpResponse, userProfile] = await Promise.all([
  signUpClient.initiateSignUpAsync(signUpRequest),
  userClient.getUserProfileAsync(profileRequest)
]);
```

### Caching Strategies

Implement response caching for appropriate operations:

```typescript
const responseCache = new Map<string, any>();

export async function cachedGreeting(name: string) {
  const cacheKey = `greeting:${name}`;
  
  if (responseCache.has(cacheKey)) {
    return responseCache.get(cacheKey);
  }
  
  const client = createGreeterClient();
  const request = new HelloRequest();
  request.setName(name);
  
  const response = await client.sayHello(request);
  responseCache.set(cacheKey, response);
  
  return response;
}
```

## Troubleshooting

### Common Issues

#### Connection Errors
- **CORS issues**: Verify Envoy CORS configuration
- **Certificate problems**: Check TLS certificate setup
- **Network connectivity**: Test direct proxy connectivity

#### Authentication Issues
- **Cookie problems**: Verify `withCredentials: true` setting
- **Token expiry**: Implement token refresh logic
- **CSRF protection**: Ensure proper CSRF handling

#### Message Serialization
- **Type mismatches**: Verify proto definitions match
- **Missing fields**: Check required vs optional fields
- **Encoding issues**: Ensure proper UTF-8 handling

### Debugging Tools

#### Browser Developer Tools
- **Network tab**: Inspect gRPC-Web requests/responses
- **Console logs**: View client-side errors and traces
- **Application tab**: Check cookies and local storage

#### gRPC-Web Inspector
Browser extension for gRPC-Web debugging:
- Request/response inspection
- Message payload viewing
- Performance metrics

### Logging and Monitoring

Comprehensive client-side logging:

```typescript
// Enhanced logging for debugging
export function createDebugSignUpClient() {
  const client = createSignUpServiceClient();
  
  // Wrap methods with logging
  const originalInitiate = client.initiateSignUpAsync.bind(client);
  client.initiateSignUpAsync = async (request) => {
    console.log('Initiating sign-up:', {
      email: request.getEmailAddress(),
      requirePassword: request.getRequirePassword()
    });
    
    try {
      const response = await originalInitiate(request);
      console.log('Sign-up response:', {
        nextStep: response.getNextStep()
      });
      return response;
    } catch (error) {
      console.error('Sign-up error:', error);
      throw error;
    }
  };
  
  return client;
}
```

## Related Features

- [gRPC Services](grpc-services.md) - Backend service implementation
- [Protocol Buffer Definitions](protocol-buffers.md) - Message contracts
- [API Gateway Configuration](api-gateway.md) - Envoy proxy setup
- [Client Code Generation](client-code-generation.md) - Automated client generation
- [Error Handling](../security/error-handling.md) - Error management strategies