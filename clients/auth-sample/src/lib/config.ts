export const config = {
  authServiceUrl: process.env.NEXT_PUBLIC_AUTHENTICATION_SERVICE_URL || 'http://localhost:10000',
  otlpHttpEndpoint: process.env.NEXT_PUBLIC_OTLP_HTTP_ENDPOINT || 'http://localhost:4318/v1',
  authority: process.env.NEXT_PUBLIC_COGNITO_AUTHORITY || '',
  clientId: process.env.NEXT_PUBLIC_COGNITO_CLIENT_ID || '',
  redirectUri: process.env.NEXT_PUBLIC_COGNITO_REDIRECT_URI || '',
  scope: process.env.NEXT_PUBLIC_COGNITO_SCOPE || 'email openid profile',
  responseType: process.env.NEXT_PUBLIC_COGNITO_RESPONSE_TYPE || 'code',
  cognitoDomain: process.env.NEXT_PUBLIC_COGNITO_DOMAIN || '',
  logoutRedirectUri: process.env.NEXT_PUBLIC_COGNITO_LOGOUT_REDIRECT_URI || ''
};