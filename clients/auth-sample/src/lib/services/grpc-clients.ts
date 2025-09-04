import { createTraceUnaryInterceptor } from '@/lib/services/trace-interceptor';
import { GreeterClient } from '@/lib/services/auth/greet/GreetServiceClientPb';
import { SignUpServiceClient } from '@/lib/services/auth/sign-up/Sign-upServiceClientPb';
import { config } from '../config';
import { AuthorizationServiceClient } from './auth/authz/AuthzServiceClientPb';

export function createGreeterClient() {
  assertConfig(config)

  return new GreeterClient(
    config.authServiceUrl!,
    null,
    { unaryInterceptors: [createTraceUnaryInterceptor()], withCredentials: true }
  );
}

export function createSignUpServiceClient() {
  assertConfig(config)

  return new SignUpServiceClient(
      config.authServiceUrl!,
      null,
      { unaryInterceptors: [createTraceUnaryInterceptor()], withCredentials: true }
  );
}

export function createAuthorizationServiceClient() {
  assertConfig(config)

  return new AuthorizationServiceClient(
      config.authServiceUrl!,
      null,
      { unaryInterceptors: [createTraceUnaryInterceptor()], withCredentials: true }
  );
}

type Config = typeof config;

function assertConfig(config: Config) {
  if (!config.authServiceUrl) {
    throw new Error('NEXT_PUBLIC_AUTH_SERVICE_URL is not set')
  }
}


