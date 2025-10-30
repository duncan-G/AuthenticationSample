export const config = {
  authServiceUrl: process.env.NEXT_PUBLIC_AUTH_SERVICE_URL,
  greeterServiceUrl: process.env.NEXT_PUBLIC_GREETER_SERVICE_URL,
  otlpHttpEndpoint: process.env.NEXT_PUBLIC_OTLP_HTTP_ENDPOINT,
  authority: process.env.NEXT_PUBLIC_OIDC_AUTHORITY,
  clientId: process.env.NEXT_PUBLIC_OIDC_CLIENT_ID,
  redirectUri: process.env.NEXT_PUBLIC_OIDC_REDIRECT_URI,
  responseType: "code",
  scope: "openid email profile",
};
