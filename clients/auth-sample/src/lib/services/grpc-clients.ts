import { createTraceUnaryInterceptor } from '@/lib/services/trace-interceptor';
import { GreeterClient } from '@/lib/services/auth/greet/GreetServiceClientPb';
import { SignUpServiceClient } from '@/lib/services/auth/sign-up/Sign-upServiceClientPb';
import { config } from '../config';

export function createGreeterClient() {
  assertConfig(config)

  return new GreeterClient(
    config.greeterServiceUrl!,
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

type Config = typeof config;

function assertConfig(config: Config) {
  if (!config.authServiceUrl) {
    throw new Error('NEXT_PUBLIC_AUTH_SERVICE_URL is not set')
  }
  if (!config.greeterServiceUrl) {
    throw new Error('NEXT_PUBLIC_GREETER_SERVICE_URL is not set')
  }
}


