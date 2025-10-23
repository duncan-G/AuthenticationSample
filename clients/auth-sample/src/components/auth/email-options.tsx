import { Lock, Mail, AlertCircle } from "lucide-react"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { AuthCard } from "./auth-card"
import { AuthButton } from "./auth-button"
import { AuthHeader } from "./auth-header"
import { useState, useEffect, useRef, useCallback } from "react"
import { validateEmail } from "@/lib/validation"

interface EmailOptionsProps {
  email: string
  onEmailChange: (email: string) => void
  onPasswordFlow: () => void
  onPasswordlessFlow: () => void
  onBack: () => void
  isLoading: boolean
  serverError?: string
}

export function EmailOptions({
  email,
  onEmailChange,
  onPasswordFlow,
  onPasswordlessFlow,
  onBack,
  isLoading,
  serverError
}: EmailOptionsProps) {
  const [emailError, setEmailError] = useState<string>("")
  const [showError, setShowError] = useState<boolean>(false)
  const isUserTypingRef = useRef<boolean>(false)
  const lastEmailChangeRef = useRef<string>("")

  const validateAndProceed = useCallback((action: () => void) => {
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
    action()
  }, [email])

  const handleEmailChange = (value: string) => {
    // Mark that user is actively typing
    isUserTypingRef.current = true
    
    // Clear the typing flag after a delay
    setTimeout(() => {
      isUserTypingRef.current = false
    }, 500)
    
    onEmailChange(value)
    // Clear error when user starts typing
    if (showError) {
      setShowError(false)
      setEmailError("")
    }
  }

  // Show server error if provided
  useEffect(() => {
    if (serverError) {
      setEmailError(serverError)
      setShowError(true)
    }
  }, [serverError])

  // Check for autofilled email on component mount
  useEffect(() => {
    const timer = setTimeout(() => {
      if (email && validateEmail(email) && !isUserTypingRef.current) {
        if (!showError && !emailError) { // Only if no validation errors
          validateAndProceed(onPasswordFlow)
        }
      }
    }, 300) // Longer delay for initial check
    
    return () => clearTimeout(timer)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []) // Only run once on mount

  // Auto-proceed when email is autofilled (for dynamic autofill)
  useEffect(() => {
    if (email && validateEmail(email) && email !== lastEmailChangeRef.current) {
      // Check if this was likely an autofill (not user typing)
      if (!isUserTypingRef.current) {
        // Small delay to ensure autofill is complete and avoid false positives
        const timer = setTimeout(() => {
          if (email && validateEmail(email) && !isUserTypingRef.current) {
            validateAndProceed(onPasswordFlow)
          }
        }, 150)
        
        return () => clearTimeout(timer)
      }
    }
    lastEmailChangeRef.current = email
  }, [email, onPasswordFlow, validateAndProceed])

  // Method to set server validation errors (reserved for future use)
  // const setServerError = (error: string) => {
  //   setEmailError(error)
  //   setShowError(true)
  // }

  return (
    <div className="w-full max-w-md mx-auto">
      <AuthHeader
        title="Sign in with email"
        showBackButton
        onBack={onBack}
      />

      <AuthCard>
        <form onSubmit={(e) => { 
          e.preventDefault()
          validateAndProceed(onPasswordFlow)
        }} noValidate>
          <div className="space-y-3">
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
                  validateAndProceed(onPasswordFlow)
                }
              }}
              onFocus={() => { isUserTypingRef.current = true }}
              autoFocus
              required
              className="h-12 bg-stone-900/70 border-2 border-stone-700/50 text-stone-50 placeholder:text-stone-400/60 focus:border-stone-500/90 focus:ring-stone-500/30 rounded-lg text-base transition-all duration-200"
            />
            
            {/* Reserved space for error message - prevents layout shift (allow up to 2 lines) */}
            <div className="min-h-[40px] flex items-center">
              {showError && emailError && (
                <div className="flex items-center space-x-2 text-red-400 text-sm">
                  <AlertCircle className="w-4 h-4 flex-shrink-0" />
                  <span>{emailError}</span>
                </div>
              )}
            </div>
          </div>

          <div className="space-y-4 pt-4">
            <AuthButton
              type="submit"
              disabled={isLoading}
            >
              <Lock className="w-5 h-5 mr-3" />
              Continue with Password
            </AuthButton>

            <AuthButton
              variant="secondary"
              type="button"
              onClick={() => validateAndProceed(onPasswordlessFlow)}
              disabled={isLoading}
            >
              <Mail className="w-5 h-5 mr-3" />
              Send Verification Code
            </AuthButton>
          </div>
        </form>
      </AuthCard>
    </div>
  )
} 