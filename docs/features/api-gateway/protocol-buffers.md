# Protocol Buffer Definitions

## Overview

Protocol Buffers (protobuf) define the contract between gRPC services and clients. They provide language-neutral, platform-neutral, extensible mechanism for serializing structured data. The system uses proto3 syntax with well-defined message structures and service definitions.

## Protocol Buffer Structure

### File Organization

Protocol buffer definitions are organized by service:

```text
microservices/Auth/src/Auth.Grpc/Protos/
├── sign-up.proto          # User registration service
├── authz.proto           # Authorization service
└── (additional services)

microservices/Greeter/Greeter/Protos/
└── greet.proto           # Example greeting service
```

### Common Patterns

All proto files follow consistent patterns:

```protobuf
syntax = "proto3";

import "google/protobuf/empty.proto";

option csharp_namespace = "AuthSample.ServiceName.Grpc.Protos";

package servicename;

service ServiceName {
  rpc MethodName (RequestMessage) returns (ResponseMessage);
}
```

## SignUp Service Definition

### Service Contract

The sign-up service defines three main operations:

```protobuf
service SignUpService {
  rpc InitiateSignUpAsync (InitiateSignUpRequest) returns (InitiateSignUpResponse);
  rpc VerifyAndSignInAsync (VerifyAndSignInRequest) returns (VerifyAndSignInResponse);
  rpc ResendVerificationCodeAsync (ResendVerificationCodeRequest) returns (google.protobuf.Empty);
}
```

### Message Definitions

#### SignUp Flow States

```protobuf
enum SignUpStep {
  UNSPECIFIED = 0;           // Default/unknown state
  PASSWORD_REQUIRED = 1;     // User needs to provide password
  VERIFICATION_REQUIRED = 2; // Email verification needed
  SIGN_IN_REQUIRED = 3;      // User needs to sign in
  REDIRECT_REQUIRED = 4;     // Redirect to application
}
```

#### Request Messages

**InitiateSignUpRequest**
```protobuf
message InitiateSignUpRequest {
  string email_address = 1;    // User's email address
  bool require_password = 2;   // Whether password is required
  optional string password = 3; // Password (if required)
}
```

**VerifyAndSignInRequest**
```protobuf
message VerifyAndSignInRequest {
  string email_address = 1;      // User's email address
  string verification_code = 2;  // Email verification code
  string name = 3;              // User's display name
}
```

**ResendVerificationCodeRequest**
```protobuf
message ResendVerificationCodeRequest {
  string email_address = 1;     // Email to resend code to
}
```

#### Response Messages

**InitiateSignUpResponse**
```protobuf
message InitiateSignUpResponse {
  SignUpStep next_step = 1;     // Next step in sign-up flow
}
```

**VerifyAndSignInResponse**
```protobuf
message VerifyAndSignInResponse {
  SignUpStep next_step = 1;     // Next step after verification
}
```

### Field Numbering Strategy

- **1-15**: Most frequently used fields (single-byte encoding)
- **16+**: Less frequently used fields
- **Reserved ranges**: Avoid conflicts with future extensions

## Authorization Service Definition

### Service Contract

Simple authorization check service:

```protobuf
service AuthorizationService {
  rpc Check (google.protobuf.Empty) returns (google.protobuf.Empty);
}
```

### Usage Pattern

- **Input**: Empty message (authorization context from gRPC metadata)
- **Output**: Empty message (success) or gRPC error status
- **Purpose**: External authorization for Envoy proxy

## Greeter Service Definition (Example)

### Service Contract

Demonstrates basic gRPC patterns:

```protobuf
service Greeter {
  rpc SayHello (HelloRequest) returns (HelloReply);
}

message HelloRequest {
  string name = 1;
}

message HelloReply {
  string message = 1;
}
```

## Code Generation

### .NET Code Generation

Protocol buffers are compiled to C# classes during build:

```xml
<ItemGroup>
  <Protobuf Include="Protos\sign-up.proto" GrpcServices="Server" />
  <Protobuf Include="Protos\authz.proto" GrpcServices="Server" />
</ItemGroup>
```

Generated classes include:
- **Message classes**: Strongly-typed request/response objects
- **Service base classes**: Abstract base for service implementation
- **Client classes**: For service-to-service communication

### TypeScript Code Generation

Frontend clients are generated using protoc-gen-grpc-web:

```bash
protoc -I="/home/protos" sign-up.proto \
  --plugin=protoc-gen-js=/usr/local/bin/protoc-gen-js \
  --js_out=import_style=commonjs:"/home/api/sign-up" \
  --grpc-web_out=import_style=typescript,mode=grpcwebtext:"/home/api/sign-up"
```

Generated files:
- **Message definitions**: `sign-up_pb.js` and `sign-up_pb.d.ts`
- **Service client**: `Sign-upServiceClientPb.ts`

## Message Design Patterns

### Optional Fields

Use `optional` keyword for fields that may not be present:

```protobuf
message InitiateSignUpRequest {
  string email_address = 1;
  bool require_password = 2;
  optional string password = 3;  // Only present when require_password = true
}
```

### Enumerations

Define clear state machines with enums:

```protobuf
enum SignUpStep {
  UNSPECIFIED = 0;        // Always include default value
  PASSWORD_REQUIRED = 1;
  VERIFICATION_REQUIRED = 2;
  SIGN_IN_REQUIRED = 3;
  REDIRECT_REQUIRED = 4;
}
```

### Well-Known Types

Leverage Google's well-known types:

```protobuf
import "google/protobuf/empty.proto";
import "google/protobuf/timestamp.proto";

rpc ResendVerificationCodeAsync (ResendVerificationCodeRequest) 
    returns (google.protobuf.Empty);
```

## Validation Patterns

### Field Validation

Protocol buffers support validation through options:

```protobuf
message InitiateSignUpRequest {
  string email_address = 1 [(validate.rules).string.email = true];
  bool require_password = 2;
  optional string password = 3 [(validate.rules).string.min_len = 8];
}
```

### Business Rule Validation

Complex validation is handled in service implementation:

```csharp
public override async Task<InitiateSignUpResponse> InitiateSignUpAsync(
    InitiateSignUpRequest request, ServerCallContext context)
{
    // Validate email format
    if (!IsValidEmail(request.EmailAddress))
        throw new RpcException(new Status(StatusCode.InvalidArgument, "Invalid email"));
    
    // Validate password requirements
    if (request.RequirePassword && string.IsNullOrEmpty(request.Password))
        throw new RpcException(new Status(StatusCode.InvalidArgument, "Password required"));
}
```

## Schema Evolution

### Backward Compatibility

Protocol buffers support schema evolution:

- **Adding fields**: Always backward compatible
- **Removing fields**: Mark as reserved to prevent reuse
- **Changing field types**: Limited compatibility (e.g., int32 ↔ int64)

```protobuf
message InitiateSignUpRequest {
  string email_address = 1;
  bool require_password = 2;
  optional string password = 3;
  
  // Reserved for future use or removed fields
  reserved 4, 5;
  reserved "old_field_name";
}
```

### Forward Compatibility

Clients can handle unknown fields gracefully:

```csharp
// Unknown fields are preserved during serialization/deserialization
var request = InitiateSignUpRequest.Parser.ParseFrom(bytes);
var serialized = request.ToByteArray(); // Preserves unknown fields
```

## Performance Considerations

### Message Size Optimization

- **Field ordering**: Place frequently used fields first (1-15)
- **Optional fields**: Use sparingly to reduce message size
- **Repeated fields**: Consider pagination for large collections

### Serialization Performance

- **Binary format**: More efficient than JSON
- **Schema validation**: Compile-time type checking
- **Compression**: Built-in gRPC compression support

## Testing Protocol Buffers

### Message Testing

Test message serialization/deserialization:

```csharp
[Test]
public void InitiateSignUpRequest_Serialization_PreservesData()
{
    // Arrange
    var original = new InitiateSignUpRequest
    {
        EmailAddress = "test@example.com",
        RequirePassword = true,
        Password = "password123"
    };

    // Act
    var bytes = original.ToByteArray();
    var deserialized = InitiateSignUpRequest.Parser.ParseFrom(bytes);

    // Assert
    Assert.That(deserialized.EmailAddress, Is.EqualTo(original.EmailAddress));
    Assert.That(deserialized.RequirePassword, Is.EqualTo(original.RequirePassword));
    Assert.That(deserialized.Password, Is.EqualTo(original.Password));
}
```

### Schema Validation Testing

Validate that schema changes maintain compatibility:

```csharp
[Test]
public void SignUpStep_Enum_HasExpectedValues()
{
    // Ensure enum values don't change unexpectedly
    Assert.That((int)SignUpStep.Unspecified, Is.EqualTo(0));
    Assert.That((int)SignUpStep.PasswordRequired, Is.EqualTo(1));
    Assert.That((int)SignUpStep.VerificationRequired, Is.EqualTo(2));
}
```

## Documentation Standards

### Service Documentation

Document service purpose and usage:

```protobuf
// The SignUpService handles user registration workflows including
// email verification and password-based or passwordless sign-up flows.
service SignUpService {
  // Initiates the sign-up process for a new user.
  // Returns the next step required to complete registration.
  rpc InitiateSignUpAsync (InitiateSignUpRequest) returns (InitiateSignUpResponse);
}
```

### Message Documentation

Document field purposes and constraints:

```protobuf
message InitiateSignUpRequest {
  // The user's email address. Must be a valid email format.
  string email_address = 1;
  
  // Whether the user must provide a password during sign-up.
  // If false, a passwordless flow will be used.
  bool require_password = 2;
  
  // The user's password. Required only when require_password is true.
  // Must meet minimum security requirements (8+ characters).
  optional string password = 3;
}
```

## Troubleshooting

### Common Issues

#### Compilation Errors
- **Missing imports**: Ensure all imported proto files are available
- **Namespace conflicts**: Use unique package names
- **Field number conflicts**: Ensure unique field numbers within messages

#### Runtime Errors
- **Serialization failures**: Check for required fields
- **Version mismatches**: Ensure client/server use compatible schemas
- **Unknown field handling**: Verify forward compatibility

### Debugging Tools

#### Protocol Buffer Inspector
Use protoc to inspect compiled schemas:

```bash
protoc --decode_raw < message.bin
protoc --decode=auth.InitiateSignUpRequest sign-up.proto < message.bin
```

#### Schema Validation
Validate proto files before deployment:

```bash
protoc --proto_path=. --csharp_out=temp sign-up.proto
```

## Related Features

- [gRPC Services](grpc-services.md) - Service implementation details
- [gRPC-Web Client Integration](grpc-web-client.md) - Frontend client usage
- [Code Generation](client-code-generation.md) - Automated client generation
- [API Gateway Configuration](api-gateway.md) - Envoy proxy routing