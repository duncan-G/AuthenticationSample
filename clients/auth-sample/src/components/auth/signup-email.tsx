import { useState, useRef, useCallback } from "react"
import { AlertCircle } from "lucide-react"
import { AuthCard } from "./auth-card"
import { AuthButton } from "./auth-button"
import { AuthHeader } from "./auth-header"
import { AuthDivider } from "./auth-divider"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { validateEmail } from "@/lib/validation"
import { friendlyMessageFor } from "@/lib/services/handle-api-error"
import { ErrorCodes } from "@/lib/services/error-codes"

interface SignUpEmailProps {
  email: string
  onEmailChange: (email: string) => void
  onPasswordFlowContinue: () => Promise<void>
  onPasswordlessFlow: () => void
  onBack: () => void
  isLoading: boolean
  serverError?: string
  signupMethod?: "password" | "passwordless"
}

export function SignUpEmail({
  email,
  onEmailChange,
  onPasswordFlowContinue,
  onPasswordlessFlow,
  onBack,
  isLoading,
  serverError,
  signupMethod
}: SignUpEmailProps) {
  
  
  const [emailError, setEmailError] = useState<string>("")
  const [showError, setShowError] = useState<boolean>(false)
  const isUserTypingRef = useRef<boolean>(false)

  const handleEmailChange = (newEmail: string) => {
    onEmailChange(newEmail)
    isUserTypingRef.current = true
    
    // Clear errors when user starts typing
    if (showError) {
      setShowError(false)
      setEmailError("")
    }
  }

  const validateAndProceed = useCallback((action: () => void | Promise<void>) => {
    if (!email.trim()) {
      setEmailError("Email address is required")
      setShowError(true)
      return
    }
    
    if (!validateEmail(email)) {
      setEmailError("Please enter a valid email address")
      setShowError(true)
      return
    }
    
    // Clear any errors and proceed
    setEmailError("")
    setShowError(false)
    void action()
  }, [email])

  const getTitle = () => {
    switch (signupMethod) {
      case "password":
        return "Create account with password"
      case "passwordless":
        return "Create passwordless account"
      default:
        return "Create your account"
    }
  }

  const getButtonText = () => {
    switch (signupMethod) {
      case "password":
        return isLoading ? "Validating..." : "Continue"
      case "passwordless":
        return isLoading ? "Sending verification..." : "Send verification email"
      default:
        return isLoading ? "Creating account..." : "Create Account"
    }
  }

  const handleFormSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (signupMethod === "passwordless") {
      validateAndProceed(onPasswordlessFlow)
    } else {
      validateAndProceed(onPasswordFlowContinue)
    }
  }

  return (
    <div className="w-full max-w-md mx-auto">
      <AuthHeader
        title={getTitle()}
        showBackButton
        onBack={onBack}
      />

      <AuthCard>
        <form onSubmit={handleFormSubmit} noValidate>
          <div className="space-y-3 mb-6">
            <Label htmlFor="email" className="text-stone-100 font-medium text-base">
              Email address
            </Label>
            
            <Input
              id="email"
              type="email"
              placeholder="Enter your email address"
              value={email}
              onChange={(e) => handleEmailChange(e.target.value)}
              onKeyDown={(e) => { 
                isUserTypingRef.current = true
                // Allow form submission on Enter
                if (e.key === 'Enter') {
                  e.preventDefault()
                  handleFormSubmit(e)
                }
              }}
              onFocus={() => { isUserTypingRef.current = true }}
              autoFocus
              required
              className="h-12 bg-stone-900/70 border-2 border-stone-700/50 text-stone-50 placeholder:text-stone-400/60 focus:border-stone-500/90 focus:ring-stone-500/30 rounded-lg text-base transition-all duration-200"
            />
            
            {/* Reserved space for error message - prevents layout shift (allow up to 2 lines) */}
            <div className="min-h-[40px] flex items-center">
              {(showError && emailError) && (
                <div className="flex items-center space-x-2 text-red-400 text-sm">
                  <AlertCircle className="w-4 h-4 flex-shrink-0" />
                  <span>{emailError}</span>
                </div>
              )}
              {!emailError && serverError && (
                <div className="flex items-center space-x-2 text-red-400 text-sm">
                  <AlertCircle className="w-4 h-4 flex-shrink-0" />
                  <span>{serverError}</span>
                </div>
              )}
            </div>
          </div>

          <AuthButton
            type="submit"
            disabled={isLoading}
            loading={isLoading}
          >
            {getButtonText()}
          </AuthButton>
        </form>

        {/* Only show alternative option if no specific method was chosen */}
        {!signupMethod && (
          <>
            <AuthDivider text="or" />

            <AuthButton
              variant="secondary"
              onClick={() => validateAndProceed(onPasswordlessFlow)}
              disabled={isLoading}
            loading={isLoading}
            >
              Send verification email
            </AuthButton>
          </>
        )}
      </AuthCard>
      {/* Reserved space below card to avoid layout shift when CTA appears */}
      <div className="min-h-[40px] mt-6 flex items-center justify-center">
        {!emailError && serverError === friendlyMessageFor[ErrorCodes.DuplicateEmail] && (
          <p className="text-stone-300/80 text-sm text-center">
            If this email belongs to you, then please {" "}
            <a
              href="/sign-in"
              className="text-amber-200/90 hover:text-amber-100 underline font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 rounded px-1"
            >
              Sign in
            </a>
          </p>
        )}
      </div>
    </div>
  )
} 