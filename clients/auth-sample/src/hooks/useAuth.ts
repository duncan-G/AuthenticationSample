import { useState } from "react"
import { useAuth as useOidcAuth } from "react-oidc-context"
import type { AuthFlow, AuthState, AuthHandlers } from "@/types/auth"
import { createSignUpManagerClient } from "@/lib/services/grpc-clients"
import { runWithTracing } from "@/lib/telemetry"
import { InitiateSignUpRequest, VerifyAndSignUpRequest, IsEmailTakenRequest } from "@/lib/services/auth/sign-up/sign-up_pb"

const getErrorCode = (err: unknown): number | undefined => {
  if (typeof err === 'object' && err !== null && 'code' in err) {
    const value = (err as Record<string, unknown>).code
    if (typeof value === 'number') return value
  }
  return undefined
}

const getErrorMessage = (err: unknown): string | undefined => {
  if (err instanceof Error) return err.message
  if (typeof err === 'object' && err !== null && 'message' in err) {
    const value = (err as Record<string, unknown>).message
    if (typeof value === 'string') return value
  }
  return undefined
}

export function useAuth(): AuthState & AuthHandlers {
  const [currentFlow, setCurrentFlow] = useState<AuthFlow>("main")
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const [passwordConfirmation, setPasswordConfirmation] = useState("")
  const [otpCode, setOtpCode] = useState("")
  const [isLoading, setIsLoading] = useState(false)
  const [signupMethod, setSignupMethod] = useState<"password" | "passwordless" | undefined>()
  const [errorMessage, setErrorMessage] = useState<string | undefined>(undefined)
  const oidc = useOidcAuth()
  const client = createSignUpManagerClient()

  // Sign-in handlers
  const handleGoogleSignIn = async () => {
    setIsLoading(true)
    try {
      await oidc.signinRedirect()
    } finally {
      setIsLoading(false)
    }
  }

  const handleAppleSignIn = async () => {
    setIsLoading(true)
    try {
      await oidc.signinRedirect()
    } finally {
      setIsLoading(false)
    }
  }

  const handleEmailSignIn = async () => {
    setIsLoading(true)
    try {
      await oidc.signinRedirect()
    } finally {
      setIsLoading(false)
    }
  }

  const handlePasswordSignIn = async () => {
    setIsLoading(true)
    try {
      await oidc.signinRedirect()
    } finally {
      setIsLoading(false)
    }
  }

  const handlePasswordlessSignIn = async () => {
    setIsLoading(true)
    try {
      await oidc.signinRedirect()
    } finally {
      setIsLoading(false)
    }
  }

  const handlePasskeySignIn = async () => {
    setIsLoading(true)
    try {
      await oidc.signinRedirect()
    } finally {
      setIsLoading(false)
    }
  }

  const handleOtpVerification = async () => {
    setIsLoading(true)
    try {
      await oidc.signinRedirect()
    } finally {
      setIsLoading(false)
    }
  }

  // Sign-up handlers
  const handleGoogleSignUp = async () => {
    setIsLoading(true)
    // Implement Google OAuth sign up flow
    console.log("Google sign up")
    setIsLoading(false)
  }

  const handleAppleSignUp = async () => {
    setIsLoading(true)
    // Implement Apple OAuth sign up flow
    console.log("Apple sign up")
    setIsLoading(false)
  }

  const handleEmailSignUp = () => {
    setErrorMessage(undefined)
    setCurrentFlow("signup-email-options")
  }

  const handlePasswordSignFlowStart = () => {
    setErrorMessage(undefined)
    setSignupMethod("password")
    setCurrentFlow("signup-email-options")
  }

  const handlePasswordlessSignUpFlowStart = () => {
    setErrorMessage(undefined)
    setSignupMethod("passwordless")
    setCurrentFlow("signup-email-options")
  }

  // For password flow: after email is entered and submitted, check if email is available.
  const handlePasswordEmailContinue = async () => {
    await runWithTracing("signup.checkEmailAvailability", async () => {
      setIsLoading(true)
      try {
        const request = new IsEmailTakenRequest()
        request.setEmailAddress(email)
        const reply = await client.isEmailTakenAsync(request, {})
        const isTaken = reply.getTaken()
        if (isTaken) {
          setErrorMessage("An account with this email already exists.")
          return
        }
        setErrorMessage(undefined)
        setCurrentFlow("signup-password")
      } catch {
        setErrorMessage("Something went wrong. Please try again in a moment.")
      } finally {
        setIsLoading(false)
      }
    })
  }

  // For password flow: after email is entered and submitted, check if email is available.
  const handlePasswordlessEmailContinue = async () => {
    await runWithTracing("signup.initiatePasswordless", async () => {
      setIsLoading(true)
      try {
        const request = new InitiateSignUpRequest()
        request.setEmailAddress(email)
        await client.initiateSignUpAsync(request, {})
        setErrorMessage(undefined)
        setCurrentFlow("signup-passwordless")
      } catch (err: unknown) {
        console.error("Failed to initiate passwordless sign up", err)
        const code = getErrorCode(err)
        const message = getErrorMessage(err)
        if (code === 6) {
          setErrorMessage("An account with this email already exists.")
        } else if (code === 9) {
          setErrorMessage(message || "Verification cannot be sent right now. Please try again later.")
        } else {
          setErrorMessage("Something went wrong. Please try again.")
        }
      } finally {
        setIsLoading(false)
      }
    })
  }

  const handlePasswordSignUp = async () => {
    await runWithTracing("signup.initiatePassword", async () => {
      setIsLoading(true)
      try {
        const client = createSignUpManagerClient()
        const request = new InitiateSignUpRequest()
        request.setEmailAddress(email)
        request.setPassword(password)
        await client.initiateSignUpAsync(request, {})
        setErrorMessage(undefined)
        setCurrentFlow("signup-passwordless")
      } catch (err: unknown) {
        console.error("Failed to initiate password sign up", err)
        const code = getErrorCode(err)
        const message = getErrorMessage(err)
        if (code === 6) {
          // AlreadyExists
          setErrorMessage("An account with this email already exists.")
        } else if (code === 9) {
          // FailedPrecondition
          setErrorMessage(message || "Verification cannot be sent right now. Please try again later.")
        } else {
          setErrorMessage("Something went wrong. Please try again in a moment.")
        }
      } finally {
        setIsLoading(false)
      }
    })
  }

  const handleSignUpOtpVerification = async () => {
    await runWithTracing("signup.verifyAndCreateAccount", async () => {
      setIsLoading(true)
      try {
        const request = new VerifyAndSignUpRequest()
        request.setEmailAddress(email)
        request.setVerificationCode(otpCode)
        // Derive a fallback name from email local-part if not collected via UI
        const derivedName = email.includes("@") ? email.split("@")[0] : email
        request.setName(derivedName || "User")
        await client.verifyAndSignUpAsync(request, {})
        // Reset state after successful verification
        setPassword("")
        setPasswordConfirmation("")
        setOtpCode("")
        setSignupMethod(undefined)
        setCurrentFlow("signup-main")
        setErrorMessage(undefined)
      } catch (err: unknown) {
        console.error("Failed to verify sign up OTP", err)
        setErrorMessage("Something went wrong. Please try again in a moment.")
      } finally {
        setIsLoading(false)
      }
    })
  }

  // Clear server error on email input changes
  const handleSetEmail = (value: string) => {
    setEmail(value)
    if (errorMessage) {
      setErrorMessage(undefined)
    }
  }

  // Clear server error when OTP code changes
  const handleSetOtpCode = (value: string) => {
    setOtpCode(value)
    if (errorMessage) {
      setErrorMessage(undefined)
    }
  }

  // Clear server error on any flow navigation (including navigating back)
  const handleSetCurrentFlow = (flow: AuthFlow) => {
    if (errorMessage) {
      setErrorMessage(undefined)
    }
    setCurrentFlow(flow)
  }

  return {
    currentFlow,
    email,
    password,
    passwordConfirmation,
    otpCode,
    isLoading,
    signupMethod,
    errorMessage,
    handleGoogleSignIn,
    handleAppleSignIn,
    handleEmailSignIn,
    handlePasswordSignIn,
    handlePasswordlessSignIn,
    handlePasskeySignIn,
    handleOtpVerification,
    handleGoogleSignUp,
    handleAppleSignUp,
    handleEmailSignUp,
    handlePasswordSignFlowStart,
    handlePasswordlessSignUpFlowStart,
    handlePasswordEmailContinue,
    handlePasswordlessEmailContinue,
    handlePasswordSignUp,
    handleSignUpOtpVerification,
    setCurrentFlow: handleSetCurrentFlow,
    setEmail: handleSetEmail,
    setPassword,
    setPasswordConfirmation,
    setOtpCode: handleSetOtpCode,
  }
}
