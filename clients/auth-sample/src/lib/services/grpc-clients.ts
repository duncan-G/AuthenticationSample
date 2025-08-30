import { createTraceUnaryInterceptor } from '@/lib/services/trace-interceptor';
import { GreeterClient } from '@/lib/services/auth/greet/GreetServiceClientPb';
import { SignUpManagerClient } from '@/lib/services/auth/sign-up/Sign-upServiceClientPb';
import { config } from '../config';

export function createGreeterClient() {
  assertConfig(config)

  return new GreeterClient(
    config.authServiceUrl,
    null,
    { unaryInterceptors: [createTraceUnaryInterceptor()] }
  );
}

export function createSignUpManagerClient() {
  assertConfig(config)

  return new SignUpManagerClient(
      config.authServiceUrl,
      null,
      { unaryInterceptors: [createTraceUnaryInterceptor()] }
  );
}

type Config = typeof config;

function assertConfig(config: Config) {
  if (!config.authServiceUrl) {
    throw new Error('NEXT_PUBLIC_AUTH_SERVICE_URL is not set')
  }
}


