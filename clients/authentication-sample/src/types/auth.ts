export type AuthFlow = "main" | "email-options" | "password" | "passwordless" | "passkey" | "signup-main" | "signup-email-options" | "signup-password" | "signup-passwordless"

export interface AuthState {
  currentFlow: AuthFlow
  email: string
  password: string
  passwordConfirmation: string
  otpCode: string
  isLoading: boolean
  signupMethod?: "password" | "passwordless"
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
  handleEmailSignUp: () => void
  handlePasswordSignUpFlow: () => void
  handlePasswordlessSignUpFlow: () => void
  handlePasswordSignUp: () => Promise<void>
  handlePasswordlessSignUp: () => Promise<void>
  handleSignUpOtpVerification: () => Promise<void>
  setCurrentFlow: (flow: AuthFlow) => void
  setEmail: (email: string) => void
  setPassword: (password: string) => void
  setPasswordConfirmation: (passwordConfirmation: string) => void
  setOtpCode: (code: string) => void
} 