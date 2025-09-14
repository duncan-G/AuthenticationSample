# Code Generation

## Overview

The code generation system automates the creation of gRPC clients, protocol buffer types, error code constants, and API documentation. This ensures type safety, consistency, and reduces manual maintenance overhead across the frontend and backend codebases.

## Implementation

### gRPC Client Generation

The system uses a Docker-based approach to generate TypeScript gRPC clients from protocol buffer definitions:

```bash
# Docker container for protoc compilation
FROM node:18-alpine
RUN npm install -g protoc-gen-js protoc-gen-grpc-web
RUN apk add --no-cache protobuf
WORKDIR /app
ENTRYPOINT ["protoc"]
```

### Error Code Generation

Automated generation of TypeScript error codes from .NET enum definitions:

```javascript
// generate_error_codes.js
const fs = require('fs');
const path = require('path');

async function findErrorCodeFiles(rootDir) {
  // Recursively find *ErrorCodes.cs files
  const files = [];
  const entries = await fs.promises.readdir(rootDir, { withFileTypes: true });
  
  for (const entry of entries) {
    const fullPath = path.join(rootDir, entry.name);
    if (entry.isDirectory()) {
      const nested = await findErrorCodeFiles(fullPath);
      files.push(...nested);
    } else if (entry.isFile() && /.*ErrorCodes\.cs$/i.test(entry.name)) {
      files.push(fullPath);
    }
  }
  return files;
}
```

### Protocol Buffer Compilation

Automated compilation of .proto files to TypeScript:

```bash
# gen-grpc-web.sh
docker run \
    -v $proto_directory_path:/home/protos \
    -v $output_directory_path:/home/api \
    --name protoc-gen-grpc-web \
    protoc-gen-grpc-web -I="/home/protos" $file_name \
    --plugin=protoc-gen-js=/usr/local/bin/protoc-gen-js \
    --js_out=import_style=commonjs:"/home/api/$output_sub_directory" \
    --grpc-web_out=import_style=typescript,mode=grpcwebtext:"/home/api/$output_sub_directory"
```

### Type Generation Pipeline

The generation pipeline ensures consistency across the codebase:

1. **Protocol Buffer Analysis**: Parse .proto files for service definitions
2. **Client Generation**: Generate TypeScript gRPC clients
3. **Type Generation**: Create TypeScript interfaces from proto messages
4. **Error Code Extraction**: Parse .NET error code enums
5. **Validation**: Ensure generated code compiles and passes tests

## Configuration

### gRPC Client Generation Setup

Configure the gRPC client generation environment:

```bash
# Build the protoc container
docker build -t protoc-gen-grpc-web:latest ./infrastructure/protoc-gen

# Set up generation directories
mkdir -p clients/auth-sample/src/lib/services/generated
```

### Error Code Generation Configuration

Configure error code generation paths:

```javascript
// Configuration in generate_error_codes.js
const config = {
  sourceRoot: path.join(repoRoot, 'libraries', 'Exceptions'),
  outputFile: path.join(
    repoRoot,
    'clients',
    'auth-sample',
    'src',
    'lib',
    'services',
    'error-codes.ts'
  ),
  filePattern: /.*ErrorCodes\.cs$/i
};
```

### Build Integration

Integrate code generation into the build process:

```json
// package.json scripts
{
  "scripts": {
    "generate:grpc": "./scripts/development/gen-grpc-web.sh -i microservices/Auth/src/Auth.Grpc/Protos/sign-up.proto -o clients/auth-sample/src/lib/services",
    "generate:errors": "node scripts/development/generate_error_codes.js",
    "generate:all": "npm run generate:grpc && npm run generate:errors",
    "prebuild": "npm run generate:all"
  }
}
```

## Usage

### Generating gRPC Clients

Generate TypeScript clients from protocol buffer definitions:

```bash
# Generate client for a specific proto file
./scripts/development/gen-grpc-web.sh \
  -i microservices/Auth/src/Auth.Grpc/Protos/sign-up.proto \
  -o clients/auth-sample/src/lib/services \
  -f sign-up.proto

# Generated files structure
clients/auth-sample/src/lib/services/sign-up/
├── sign-up_pb.js          # Protocol buffer messages
├── sign-up_pb.d.ts        # TypeScript definitions
├── sign-up_grpc_web_pb.js # gRPC client implementation
└── sign-up_grpc_web_pb.d.ts # gRPC client types
```

### Using Generated gRPC Clients

Integrate generated clients into the application:

```typescript
// Import generated client
import { SignUpServiceClient } from '@/lib/services/sign-up/sign-up_grpc_web_pb'
import { InitiateSignUpRequest, SignUpStep } from '@/lib/services/sign-up/sign-up_pb'

// Create client instance
const createSignUpServiceClient = () => {
  return new SignUpServiceClient(process.env.NEXT_PUBLIC_AUTH_SERVICE_URL!)
}

// Use generated types
const initiateSignUp = async (email: string, requirePassword: boolean) => {
  const client = createSignUpServiceClient()
  const request = new InitiateSignUpRequest()
  request.setEmail(email)
  request.setRequirePassword(requirePassword)
  
  const response = await client.initiateSignUpAsync(request)
  return response.getNextStep() === SignUpStep.PASSWORD_REQUIRED
}
```

### Generating Error Codes

Generate TypeScript error codes from .NET enums:

```bash
# Generate error codes
node scripts/development/generate_error_codes.js

# Generated output: clients/auth-sample/src/lib/services/error-codes.ts
export const ErrorCodes = {
    INVALID_EMAIL: "1001",
    WEAK_PASSWORD: "1002",
    USER_ALREADY_EXISTS: "1003",
    RATE_LIMIT_EXCEEDED: "2001",
    INVALID_VERIFICATION_CODE: "3001",
} as const

export type KnownErrorCode = (typeof ErrorCodes)[keyof typeof ErrorCodes]
```

### Using Generated Error Codes

Integrate error codes into error handling:

```typescript
// Import generated error codes
import { ErrorCodes, KnownErrorCode } from '@/lib/services/error-codes'

// Type-safe error handling
const handleApiError = (error: { code: string }) => {
  switch (error.code as KnownErrorCode) {
    case ErrorCodes.INVALID_EMAIL:
      return 'Please enter a valid email address'
    case ErrorCodes.RATE_LIMIT_EXCEEDED:
      return 'Too many requests. Please try again later.'
    case ErrorCodes.USER_ALREADY_EXISTS:
      return 'An account with this email already exists'
    default:
      return 'An unexpected error occurred'
  }
}
```

### Automated Generation Workflow

Set up automated generation in development:

```bash
# Watch for proto file changes and regenerate
fswatch -o microservices/*/src/*/Protos/*.proto | \
  xargs -n1 -I{} npm run generate:grpc

# Watch for error code changes and regenerate
fswatch -o libraries/Exceptions/*ErrorCodes.cs | \
  xargs -n1 -I{} npm run generate:errors
```

## Testing

### Validating Generated Code

Ensure generated code is correct and functional:

```typescript
// Test generated gRPC client
describe('Generated gRPC Client', () => {
  it('should create valid client instance', () => {
    const client = createSignUpServiceClient()
    expect(client).toBeInstanceOf(SignUpServiceClient)
  })
  
  it('should create valid request objects', () => {
    const request = new InitiateSignUpRequest()
    request.setEmail('test@example.com')
    request.setRequirePassword(true)
    
    expect(request.getEmail()).toBe('test@example.com')
    expect(request.getRequirePassword()).toBe(true)
  })
})
```

### Testing Error Code Generation

```typescript
// Test generated error codes
describe('Generated Error Codes', () => {
  it('should contain all expected error codes', () => {
    expect(ErrorCodes.INVALID_EMAIL).toBeDefined()
    expect(ErrorCodes.RATE_LIMIT_EXCEEDED).toBeDefined()
    expect(ErrorCodes.USER_ALREADY_EXISTS).toBeDefined()
  })
  
  it('should have correct error code values', () => {
    expect(ErrorCodes.INVALID_EMAIL).toMatch(/^\d+$/)
    expect(ErrorCodes.RATE_LIMIT_EXCEEDED).toMatch(/^\d+$/)
  })
})
```

### Integration Testing

Test generated code with real services:

```typescript
// Integration test with generated client
describe('gRPC Client Integration', () => {
  it('should communicate with real service', async () => {
    const client = createSignUpServiceClient()
    const request = new InitiateSignUpRequest()
    request.setEmail('integration-test@example.com')
    
    const response = await client.initiateSignUpAsync(request)
    expect(response.getNextStep()).toBeDefined()
  })
})
```

## Troubleshooting

### gRPC Generation Issues

#### Protocol Buffer Compilation Errors

```bash
# Check proto file syntax
protoc --proto_path=microservices/Auth/src/Auth.Grpc/Protos \
       --decode_raw sign-up.proto

# Validate proto file dependencies
protoc --proto_path=microservices/Auth/src/Auth.Grpc/Protos \
       --dependency_out=/tmp/deps.txt \
       sign-up.proto
```

#### Docker Container Issues

```bash
# Rebuild protoc container
docker build --no-cache -t protoc-gen-grpc-web:latest ./infrastructure/protoc-gen

# Check container functionality
docker run --rm protoc-gen-grpc-web --version

# Debug volume mounting
docker run --rm -v $(pwd):/test protoc-gen-grpc-web ls -la /test
```

#### Generated Client Issues

```typescript
// Debug generated client imports
try {
  const { SignUpServiceClient } = require('@/lib/services/sign-up/sign-up_grpc_web_pb')
  console.log('Client loaded successfully:', SignUpServiceClient)
} catch (error) {
  console.error('Failed to load generated client:', error)
}
```

### Error Code Generation Issues

#### Source File Detection

```bash
# Debug file discovery
node -e "
const fs = require('fs');
const path = require('path');
const files = fs.readdirSync('libraries/Exceptions', { recursive: true });
console.log('Found files:', files.filter(f => f.includes('ErrorCodes')));
"
```

#### Parsing Issues

```javascript
// Debug C# constant parsing
const content = fs.readFileSync('libraries/Exceptions/AuthErrorCodes.cs', 'utf8');
const constRegex = /public\s+const\s+string\s+(\w+)\s*=\s*"(\d+)"\s*;/g;
let match;
while ((match = constRegex.exec(content)) !== null) {
  console.log(`Found: ${match[1]} = ${match[2]}`);
}
```

### Build Integration Issues

#### Pre-build Hook Failures

```bash
# Debug npm script execution
npm run generate:all --verbose

# Check individual generation steps
npm run generate:grpc
npm run generate:errors
```

#### TypeScript Compilation Errors

```bash
# Check generated TypeScript files
npx tsc --noEmit --project clients/auth-sample/tsconfig.json

# Validate specific generated files
npx tsc --noEmit clients/auth-sample/src/lib/services/error-codes.ts
```

### Performance Optimization

#### Generation Speed

```bash
# Profile generation time
time npm run generate:all

# Optimize Docker container startup
docker build --cache-from protoc-gen-grpc-web:latest -t protoc-gen-grpc-web:latest ./infrastructure/protoc-gen
```

#### Incremental Generation

```bash
# Only regenerate changed files
find microservices/*/src/*/Protos -name "*.proto" -newer clients/auth-sample/src/lib/services/generated/.timestamp -exec npm run generate:grpc {} \;
```

## Related Features

- [gRPC Services](../api/grpc-services.md) - Backend gRPC service implementation
- [Protocol Buffers](../api/protocol-buffers.md) - Protocol buffer definitions
- [Local Setup](local-setup.md) - Development environment setup
- [Testing Framework](testing-framework.md) - Testing generated code
- [Error Handling](../security/error-handling.md) - Using generated error codes