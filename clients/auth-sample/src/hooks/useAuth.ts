import { useRef, useState } from "react"
import { useAuth as useOidcAuth } from "react-oidc-context"
import type { AuthFlow, AuthState, AuthHandlers } from "@/types/auth"
import { createSignUpServiceClient } from "@/lib/services/grpc-clients"
import {
  InitiateSignUpRequest,
  VerifyAndSignInRequest,
  SignUpStep,
} from "@/lib/services/auth/sign-up/sign-up_pb"
import { startWorkflow } from "@/lib/workflows"
import type { WorkflowHandle } from "@/lib/workflows"
import {friendlyMessageFor, handleApiError} from "@/lib/services/handle-api-error";
import { ErrorCodes } from "@/lib/services/error-codes"

/** Wrap an async handler with loading toggles. */
const withLoading =
  (setIsLoading: (v: boolean) => void, fn: () => Promise<void>) =>
  async () => {
    setIsLoading(true)
    try {
      await fn()
    } finally {
      setIsLoading(false)
    }
  }

/** Optionally run a client call inside a workflow step. */
const runInStep = async <T>(
  step: ReturnType<WorkflowHandle["startStep"]> | undefined,
  runner: () => Promise<T>
): Promise<T> => {
  return step ? step.run(runner) : runner()
}

/** -------- Hook -------- */
export function useAuth(): AuthState & AuthHandlers {
  const [currentFlow, setCurrentFlow] = useState<AuthFlow>("main")
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const [passwordConfirmation, setPasswordConfirmation] = useState("")
  const [otpCode, setOtpCode] = useState("")
  const [isLoading, setIsLoading] = useState(false)
  const [signupMethod, setSignupMethod] = useState<
    "password" | "passwordless" | undefined
  >()
  const [errorMessage, setErrorMessage] = useState<string | undefined>()

  const oidc = useOidcAuth()
  const client = createSignUpServiceClient()
  const signupWorkflowRef = useRef<WorkflowHandle | null>(null)

  /** Ensure a workflow exists (optionally forcing a fresh one). */
  const ensureSignupWorkflow = (
    attrs?: Record<string, unknown>,
    force?: boolean
  ) => {
    if (!signupWorkflowRef.current || force) {
      signupWorkflowRef.current = startWorkflow("signup", "v1", attrs)
    }
  }

  /** Centralized OIDC redirect sign-in handler factory (DRY). */
  const makeOidcRedirectHandler = () =>
    withLoading(setIsLoading, async () => {
      await oidc.signinRedirect()
    })

  // ---------- Sign-in handlers (all OIDC redirect) ----------
  const handleGoogleSignIn = makeOidcRedirectHandler()
  const handleAppleSignIn = makeOidcRedirectHandler()
  const handleEmailSignIn = makeOidcRedirectHandler()
  const handlePasswordSignIn = makeOidcRedirectHandler()
  const handlePasswordlessSignIn = makeOidcRedirectHandler()
  const handlePasskeySignIn = makeOidcRedirectHandler()
  const handleOtpVerification = makeOidcRedirectHandler()

  // ---------- Sign-up handlers ----------
  const handleGoogleSignUp = withLoading(setIsLoading, async () => {
    ensureSignupWorkflow({ method: "google" }, true)
    // Implement Google OAuth sign up flow
    // (left as-is intentionally)
    console.log("Google sign up")
  })

  const handleAppleSignUp = withLoading(setIsLoading, async () => {
    ensureSignupWorkflow({ method: "apple" }, true)
    // Implement Apple OAuth sign up flow
    // (left as-is intentionally)
    console.log("Apple sign up")
  })

  const handlePasswordSignUpFlowStart = () => {
    setErrorMessage(undefined)
    setSignupMethod("password")
    ensureSignupWorkflow({ method: "password" }, true)
    setCurrentFlow("signup-email")
  }

  const handlePasswordlessSignUpFlowStart = () => {
    setErrorMessage(undefined)
    setSignupMethod("passwordless")
    ensureSignupWorkflow({ method: "passwordless" }, true)
    setCurrentFlow("signup-email")
  }

  /** After email entered (password flow): check availability. */
  const handlePasswordEmailContinue = withLoading(setIsLoading, async () => {
    ensureSignupWorkflow()
    const step = signupWorkflowRef.current?.startStep("checkEmailAvailability")

    try {
      const request = new InitiateSignUpRequest()
      request.setEmailAddress(email)
      request.setRequirePassword(true)

      const response = await runInStep(step, () =>
        client.initiateSignUpAsync(request, {})
      )
      const nextStep = response.getNextStep()

      if (nextStep === SignUpStep.PASSWORD_REQUIRED) {
        setCurrentFlow("signup-password")
      } else if (nextStep === SignUpStep.VERIFICATION_REQUIRED) {
        setCurrentFlow("signup-verification")
      } else {
        step?.fail(ErrorCodes.Unexpected, "Unknown error")
        setErrorMessage(friendlyMessageFor[ErrorCodes.Unexpected])
        return
      }

      step?.succeed({ email })
      setErrorMessage(undefined)  

    } catch (err: unknown) {
        handleApiError(err, setErrorMessage, step)
    }
  })

  /** After email entered (passwordless flow): send verification. */
  const handlePasswordlessEmailContinue = withLoading(
    setIsLoading,
    async () => {
      ensureSignupWorkflow()
      const step = signupWorkflowRef.current?.startStep("initiatePasswordless")

      try {
          const request = new InitiateSignUpRequest()
          request.setEmailAddress(email)

          await runInStep(step, () => client.initiateSignUpAsync(request, {}))

          step?.succeed({email})
          setErrorMessage(undefined)
          setCurrentFlow("signup-verification")
      } catch (err) {
          handleApiError(err, setErrorMessage, step)
      }
    }
  )

  /** Initiate password signup (send verification for password flow). */
  const handlePasswordSignUp = withLoading(setIsLoading, async () => {
    ensureSignupWorkflow()
    const step = signupWorkflowRef.current?.startStep("initiatePassword")

    try {
        const request = new InitiateSignUpRequest()
        request.setEmailAddress(email)
        request.setPassword(password)
        request.setRequirePassword(true)

        await runInStep(step, () => client.initiateSignUpAsync(request, {}))

        step?.succeed({email})
        setErrorMessage(undefined)
        // Keeping original flow transition as in provided code.
        setCurrentFlow("signup-verification")
    } catch (err) {
        handleApiError(err, setErrorMessage, step)
    }
  })

  /** Verify OTP and create account. */
  const handleSignUpOtpVerification = withLoading(
    setIsLoading,
    async () => {
      ensureSignupWorkflow()
      const step = signupWorkflowRef.current?.startStep("verifyAndCreateAccount")
      try {
          const request = new VerifyAndSignInRequest()
          request.setEmailAddress(email)
          request.setVerificationCode(otpCode)

          // Fallback name from email local-part if not collected via UI
          const derivedName = email.includes("@") ? email.split("@")[0] : email
          request.setName(derivedName || "User")

          await runInStep(step, () => client.verifyAndSignInAsync(request, {}))

          step?.succeed({email})
          signupWorkflowRef.current?.succeed()
          signupWorkflowRef.current = null

          // Reset state after success
          setPassword("")
          setPasswordConfirmation("")
          setOtpCode("")
          setSignupMethod(undefined)
          setCurrentFlow("signup-main")
          setErrorMessage(undefined)

          // Redirect to home after successful sign up
          if (typeof window !== "undefined") {
            window.location.replace("/")
          }
      } catch (err) {
          handleApiError(err, setErrorMessage, step)
      }
    }
  )

  // ---------- Setters that clear server errors ----------
  const handleSetEmail = (value: string) => {
    setEmail(value)
    if (errorMessage) setErrorMessage(undefined)
  }

  const handleSetOtpCode = (value: string) => {
    setOtpCode(value)
    if (errorMessage) setErrorMessage(undefined)
  }

  const handleSetCurrentFlow = (flow: AuthFlow) => {
    if (errorMessage) setErrorMessage(undefined)
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

    // sign-in
    handleGoogleSignIn,
    handleAppleSignIn,
    handleEmailSignIn,
    handlePasswordSignIn,
    handlePasswordlessSignIn,
    handlePasskeySignIn,
    handleOtpVerification,

    // sign-up
    handleGoogleSignUp,
    handleAppleSignUp,
    handlePasswordSignUpFlowStart,
    handlePasswordlessSignUpFlowStart,
    handlePasswordEmailContinue,
    handlePasswordlessEmailContinue,
    handlePasswordSignUp,
    handleSignUpOtpVerification,

    // setters
    setCurrentFlow: handleSetCurrentFlow,
    setEmail: handleSetEmail,
    setPassword,
    setPasswordConfirmation,
    setOtpCode: handleSetOtpCode,
  }
}
