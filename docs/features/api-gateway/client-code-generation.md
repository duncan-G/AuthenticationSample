# Client Code Generation

## Overview

The system uses automated code generation to create type-safe client libraries from Protocol Buffer definitions. This ensures consistency between frontend and backend, eliminates manual client maintenance, and provides compile-time type safety for all gRPC communications.

## Code Generation Pipeline

### Generation Flow

```text
Protocol Buffers (.proto) → protoc-gen-grpc-web → TypeScript Clients
                          ↓
                    JavaScript Message Classes + TypeScript Definitions
```

### Build Integration

Code generation is integrated into the development workflow:

1. **Proto file changes** trigger regeneration
2. **Build process** includes client generation
3. **Type checking** validates generated code
4. **Testing** ensures client functionality

## Generation Script

### Script Overview

The `gen-grpc-web.sh` script handles client generation:

```bash
#!/bin/bash
# scripts/development/gen-grpc-web.sh

# Usage: ./gen-grpc-web.sh -i <proto_file> -o <output_dir> [-f <filename>]

proto_file_path=""
output_directory_path=""
file_name=""
```

### Docker-based Generation

Uses containerized protoc for consistent generation:

```bash
docker run \
    -v $proto_directory_path:/home/protos \
    -v $output_directory_path:/home/api \
    --name protoc-gen-grpc-web \
    protoc-gen-grpc-web -I="/home/protos" $file_name \
    --plugin=protoc-gen-js=/usr/local/bin/protoc-gen-js \
    --js_out=import_style=commonjs:"/home/api/$output_sub_directory" \
    --grpc-web_out=import_style=typescript,mode=grpcwebtext:"/home/api/$output_sub_directory"
```

### Generation Parameters

#### JavaScript Output
```bash
--js_out=import_style=commonjs:"/home/api/$output_sub_directory"
```
- **import_style=commonjs**: CommonJS module format
- **Output**: Message classes in JavaScript

#### gRPC-Web Output
```bash
--grpc-web_out=import_style=typescript,mode=grpcwebtext:"/home/api/$output_sub_directory"
```
- **import_style=typescript**: TypeScript client generation
- **mode=grpcwebtext**: Text-based gRPC-Web protocol
- **Output**: Service clients and TypeScript definitions

## Generated File Structure

### Output Organization

Each proto file generates a subdirectory:

```text
src/lib/services/auth/
├── sign-up/                          # From sign-up.proto
│   ├── sign-up_pb.js                # Message classes (JS)
│   ├── sign-up_pb.d.ts              # Message type definitions (TS)
│   └── Sign-upServiceClientPb.ts    # Service client (TS)
├── authz/                           # From authz.proto
│   ├── authz_pb.js                  # Message classes (JS)
│   └── authz_grpc_pb.js             # Service client (JS)
└── greet/                           # From greet.proto
    ├── greet_pb.js                  # Message classes (JS)
    ├── greet_pb.d.ts                # Message type definitions (TS)
    └── GreetServiceClientPb.ts      # Service client (TS)
```

### File Naming Convention

- **Message files**: `{proto-name}_pb.js` and `{proto-name}_pb.d.ts`
- **Service files**: `{ServiceName}ServiceClientPb.ts`
- **Directory names**: Match proto file name (without extension)

## Generated Message Classes

### JavaScript Message Classes

Generated from proto definitions:

```javascript
// sign-up_pb.js
goog.provide('auth.InitiateSignUpRequest');
goog.provide('auth.InitiateSignUpResponse');
goog.provide('auth.SignUpStep');

/**
 * @param {Array=} opt_data Optional initial data array
 * @constructor
 * @extends {jspb.Message}
 */
auth.InitiateSignUpRequest = function(opt_data) {
  jspb.Message.initialize(this, opt_data, 0, -1, null, null);
};
goog.inherits(auth.InitiateSignUpRequest, jspb.Message);
```

### TypeScript Type Definitions

Type-safe interfaces for messages:

```typescript
// sign-up_pb.d.ts
export class InitiateSignUpRequest extends jspb.Message {
  getEmailAddress(): string;
  setEmailAddress(value: string): InitiateSignUpRequest;

  getRequirePassword(): boolean;
  setRequirePassword(value: boolean): InitiateSignUpRequest;

  getPassword(): string;
  setPassword(value: string): InitiateSignUpRequest;
  hasPassword(): boolean;
  clearPassword(): InitiateSignUpRequest;

  serializeBinary(): Uint8Array;
  toObject(includeInstance?: boolean): InitiateSignUpRequest.AsObject;
  static toObject(includeInstance: boolean, msg: InitiateSignUpRequest): InitiateSignUpRequest.AsObject;
  static serializeBinaryToWriter(message: InitiateSignUpRequest, writer: jspb.BinaryWriter): void;
  static deserializeBinary(bytes: Uint8Array): InitiateSignUpRequest;
  static deserializeBinaryFromReader(message: InitiateSignUpRequest, reader: jspb.BinaryReader): InitiateSignUpRequest;
}

export namespace InitiateSignUpRequest {
  export type AsObject = {
    emailAddress: string,
    requirePassword: boolean,
    password: string,
  }
}
```

## Generated Service Clients

### Client Class Structure

TypeScript service clients provide type-safe API access:

```typescript
// Sign-upServiceClientPb.ts
export class SignUpServiceClient {
  client_: grpcWeb.AbstractClientBase;
  hostname_: string;
  credentials_: null | { [index: string]: string; };
  options_: null | { [index: string]: any; };

  constructor (hostname: string,
               credentials?: null | { [index: string]: string; },
               options?: null | { [index: string]: any; }) {
    if (!options) options = {};
    if (!credentials) credentials = {};
    options['format'] = 'text';

    this.client_ = new grpcWeb.GrpcWebClientBase(options);
    this.hostname_ = hostname.replace(/\/+$/, '');
    this.credentials_ = credentials;
    this.options_ = options;
  }
```

### Method Descriptors

Each RPC method gets a descriptor:

```typescript
  methodDescriptorInitiateSignUpAsync = new grpcWeb.MethodDescriptor(
    '/auth.SignUpService/InitiateSignUpAsync',
    grpcWeb.MethodType.UNARY,
    sign$up_pb.InitiateSignUpRequest,
    sign$up_pb.InitiateSignUpResponse,
    (request: sign$up_pb.InitiateSignUpRequest) => {
      return request.serializeBinary();
    },
    sign$up_pb.InitiateSignUpResponse.deserializeBinary
  );
```

### Method Implementations

Type-safe method implementations with overloads:

```typescript
  initiateSignUpAsync(
    request: sign$up_pb.InitiateSignUpRequest,
    metadata?: grpcWeb.Metadata | null): Promise<sign$up_pb.InitiateSignUpResponse>;

  initiateSignUpAsync(
    request: sign$up_pb.InitiateSignUpRequest,
    metadata: grpcWeb.Metadata | null,
    callback: (err: grpcWeb.RpcError,
               response: sign$up_pb.InitiateSignUpResponse) => void): grpcWeb.ClientReadableStream<sign$up_pb.InitiateSignUpResponse>;

  initiateSignUpAsync(
    request: sign$up_pb.InitiateSignUpRequest,
    metadata?: grpcWeb.Metadata | null,
    callback?: (err: grpcWeb.RpcError,
               response: sign$up_pb.InitiateSignUpResponse) => void) {
    if (callback !== undefined) {
      return this.client_.rpcCall(
        this.hostname_ + '/auth.SignUpService/InitiateSignUpAsync',
        request,
        metadata || {},
        this.methodDescriptorInitiateSignUpAsync,
        callback);
    }
    return this.client_.unaryCall(
    this.hostname_ + '/auth.SignUpService/InitiateSignUpAsync',
    request,
    metadata || {},
    this.methodDescriptorInitiateSignUpAsync);
  }
```

## Build Integration

### Development Workflow

Client generation is integrated into the development process:

```bash
# scripts/development/start_client.sh
GEN_SCRIPT="$working_dir/scripts/development/gen-grpc-web.sh"

# Generate clients for all proto files
for proto_file in "${PROTO_FILES[@]}"; do
    echo "Generating gRPC-Web client for $proto_file"
    $GEN_SCRIPT -i "$proto_file" -o "$CLIENT_DIR/src/lib/services/auth"
done
```

### Docker Container Setup

Protoc generation container:

```dockerfile
# infrastructure/protoc-gen/Dockerfile
FROM namely/protoc-all:1.51_1

# Install protoc-gen-grpc-web
RUN apt-get update && apt-get install -y wget unzip
RUN wget https://github.com/grpc/grpc-web/releases/download/1.5.0/protoc-gen-grpc-web-1.5.0-linux-x86_64
RUN mv protoc-gen-grpc-web-1.5.0-linux-x86_64 /usr/local/bin/protoc-gen-grpc-web
RUN chmod +x /usr/local/bin/protoc-gen-grpc-web
```

### Build Script Integration

Setup script builds the generation container:

```bash
# scripts/development/setup.sh
echo "Building protoc-gen image..."
docker build -t protoc-gen-grpc-web:latest ./infrastructure/protoc-gen
```

## Configuration Management

### Proto File Discovery

Automatic discovery of proto files:

```bash
# Find all proto files in microservices
PROTO_FILES=(
    "microservices/Auth/src/Auth.Grpc/Protos/sign-up.proto"
    "microservices/Auth/src/Auth.Grpc/Protos/authz.proto"
    "microservices/Greeter/Greeter/Protos/greet.proto"
)
```

### Output Directory Management

Organized output structure:

```bash
# Create subdirectory for each proto file
output_sub_directory=${file_name%.proto}
mkdir -p $output_directory_path/$output_sub_directory
```

### File Validation

Input validation before generation:

```bash
# Check if proto file exists
if [ ! -f "$proto_file_path" ]; then
    echo "Error: $proto_file_path does not exist."
    exit 1
fi

# Check if it's a proto file
if [[ ! "$proto_file_path" == *.proto ]]; then
    echo "Error: Input file does not seem to be a protobuff file."
    exit 1
fi
```

## Testing Generated Code

### Unit Testing

Test generated message classes:

```typescript
// src/lib/services/__tests__/message-serialization.test.ts
import { InitiateSignUpRequest, SignUpStep } from '../auth/sign-up/sign-up_pb';

describe('Generated Message Classes', () => {
  it('should serialize and deserialize correctly', () => {
    const original = new InitiateSignUpRequest();
    original.setEmailAddress('test@example.com');
    original.setRequirePassword(true);
    original.setPassword('password123');

    const bytes = original.serializeBinary();
    const deserialized = InitiateSignUpRequest.deserializeBinary(bytes);

    expect(deserialized.getEmailAddress()).toBe('test@example.com');
    expect(deserialized.getRequirePassword()).toBe(true);
    expect(deserialized.getPassword()).toBe('password123');
  });

  it('should handle optional fields correctly', () => {
    const request = new InitiateSignUpRequest();
    request.setEmailAddress('test@example.com');
    request.setRequirePassword(false);
    // Don't set password

    expect(request.hasPassword()).toBe(false);
    expect(request.getPassword()).toBe('');
  });
});
```

### Integration Testing

Test generated service clients:

```typescript
// src/lib/services/__tests__/client-generation.test.ts
import { SignUpServiceClient } from '../auth/sign-up/Sign-upServiceClientPb';

describe('Generated Service Clients', () => {
  it('should create client with correct configuration', () => {
    const client = new SignUpServiceClient('https://api.example.com');
    
    expect(client.hostname_).toBe('https://api.example.com');
    expect(client.options_['format']).toBe('text');
  });

  it('should have all expected methods', () => {
    const client = new SignUpServiceClient('https://api.example.com');
    
    expect(typeof client.initiateSignUpAsync).toBe('function');
    expect(typeof client.verifyAndSignInAsync).toBe('function');
    expect(typeof client.resendVerificationCodeAsync).toBe('function');
  });
});
```

## Troubleshooting

### Common Generation Issues

#### Docker Container Problems
```bash
# Container already exists
docker rm protoc-gen-grpc-web

# Permission issues
docker run --user $(id -u):$(id -g) ...
```

#### Proto File Issues
```bash
# Missing imports
import "google/protobuf/empty.proto";

# Incorrect paths
protoc -I="/home/protos" -I="/usr/include" ...
```

#### Output Directory Issues
```bash
# Directory doesn't exist
mkdir -p "$output_directory_path"

# Permission problems
chmod 755 "$output_directory_path"
```

### Debugging Generation

#### Verbose Output
```bash
# Add verbose flag to protoc
protoc --grpc-web_out=import_style=typescript,mode=grpcwebtext:"/home/api" \
       --verbose \
       sign-up.proto
```

#### Manual Generation
```bash
# Test generation manually
docker run -it --rm \
    -v $(pwd)/microservices/Auth/src/Auth.Grpc/Protos:/protos \
    -v $(pwd)/temp:/output \
    protoc-gen-grpc-web \
    protoc -I=/protos \
    --js_out=import_style=commonjs:/output \
    --grpc-web_out=import_style=typescript,mode=grpcwebtext:/output \
    sign-up.proto
```

### Validation

#### Generated File Validation
```bash
# Check TypeScript compilation
npx tsc --noEmit src/lib/services/auth/sign-up/Sign-upServiceClientPb.ts

# Validate JavaScript syntax
node -c src/lib/services/auth/sign-up/sign-up_pb.js
```

#### Runtime Validation
```typescript
// Test client instantiation
try {
  const client = new SignUpServiceClient('https://test.com');
  console.log('Client created successfully');
} catch (error) {
  console.error('Client creation failed:', error);
}
```

## Maintenance

### Version Management

Track protoc and plugin versions:

```bash
# Check versions
protoc --version
protoc-gen-grpc-web --version

# Update container
docker build --no-cache -t protoc-gen-grpc-web:latest ./infrastructure/protoc-gen
```

### Regeneration Strategy

When to regenerate clients:

1. **Proto file changes**: Always regenerate
2. **Plugin updates**: Regenerate all clients
3. **Build failures**: Clean and regenerate
4. **Type errors**: Verify proto definitions

### Cleanup

Remove generated files when needed:

```bash
# Clean generated files
rm -rf src/lib/services/auth/*/
rm -rf src/lib/services/greet/*/

# Regenerate all
./scripts/development/gen-grpc-web.sh -i microservices/Auth/src/Auth.Grpc/Protos/sign-up.proto -o src/lib/services/auth
```

## Related Features

- [Protocol Buffer Definitions](protocol-buffers.md) - Source proto files
- [gRPC Services](grpc-services.md) - Backend service implementation
- [gRPC-Web Client Integration](grpc-web-client.md) - Using generated clients
- [Development Setup](../development/local-setup.md) - Development environment
- [Testing Framework](../development/testing-framework.md) - Testing generated code