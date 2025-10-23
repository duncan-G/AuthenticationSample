export type AuthFlow = "main" | "email-options" | "password" | "passwordless" | "passkey" | "signup-main" | "signup-email" | "signup-password" | "signup-verification" | "signup-success"

export interface AuthState {
  currentFlow: AuthFlow
  email: string
  password: string
  passwordConfirmation: string
  otpCode: string
  isLoading: boolean
  isResendLoading: boolean
  signupMethod?: "password" | "passwordless"
  errorMessage?: string
  isRateLimited: boolean
  rateLimitRetryAfter?: number
}

export interface AuthHandlers {
  handleGoogleSignIn: () => Promise<void>
  handleAppleSignIn: () => Promise<void>
  handleEmailSignIn: () => void
  handlePasswordSignIn: () => Promise<void>
  handlePasswordlessSignIn: () => Promise<void>
  handlePasskeySignIn: () => Promise<void>
  handleOtpVerification: () => Promise<void>
  // Sign-up handlers
  handleGoogleSignUp: () => Promise<void>
  handleAppleSignUp: () => Promise<void>
  handlePasswordSignUpFlowStart: () => void
  handlePasswordlessSignUpFlowStart: () => void
  handlePasswordEmailContinue: () => Promise<void>
  handlePasswordlessEmailContinue: () => Promise<void>
  handlePasswordSignUp: () => Promise<void>
  handleSignUpOtpVerification: () => Promise<void>
  handleResendVerificationCode: () => Promise<void>
  setCurrentFlow: (flow: AuthFlow) => void
  setEmail: (email: string) => void
  setPassword: (password: string) => void
  setPasswordConfirmation: (passwordConfirmation: string) => void
  setOtpCode: (code: string) => void
}
