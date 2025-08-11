import { useRef, useEffect, useState } from "react"
import { AuthCard } from "./auth-card"
import { AuthButton } from "./auth-button"
import { AuthHeader } from "./auth-header"
// import { AuthDivider } from "./auth-divider"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { validatePassword, validatePasswordConfirmation, getPasswordErrors } from "@/lib/validation"

interface SignUpPasswordProps {
  email: string
  password: string
  passwordConfirmation: string
  onPasswordChange: (password: string) => void
  onPasswordConfirmationChange: (passwordConfirmation: string) => void
  onPasswordSignUp: () => Promise<void>
  onBack: () => void
  isLoading: boolean
}

export function SignUpPassword({
  email,
  password,
  passwordConfirmation,
  onPasswordChange,
  onPasswordConfirmationChange,
  onPasswordSignUp,
  onBack,
  isLoading
}: SignUpPasswordProps) {
  const passwordInputRef = useRef<HTMLInputElement>(null)
  const [passwordErrors, setPasswordErrors] = useState<string[]>([])
  const [confirmationError, setConfirmationError] = useState<string>("")
  const [showValidation, setShowValidation] = useState<boolean>(false)

  // Auto-focus on password input when component mounts
  useEffect(() => {
    if (passwordInputRef.current) {
      passwordInputRef.current.focus()
    }
  }, [])

  // Validate password confirmation on change
  useEffect(() => {
    if (showValidation && passwordConfirmation) {
      if (!validatePasswordConfirmation(password, passwordConfirmation)) {
        setConfirmationError("Passwords do not match")
      } else {
        setConfirmationError("")
      }
    }
  }, [password, passwordConfirmation, showValidation])

  // Handle form submission (Enter key)
  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    setShowValidation(true)
    
    const currentPasswordErrors = getPasswordErrors(password)
    const isPasswordValid = validatePassword(password)
    const isConfirmationValid = validatePasswordConfirmation(password, passwordConfirmation)
    
    setPasswordErrors(currentPasswordErrors)
    
    if (!isConfirmationValid) {
      setConfirmationError("Passwords do not match")
    } else {
      setConfirmationError("")
    }
    
    if (isPasswordValid && isConfirmationValid && !isLoading) {
      onPasswordSignUp()
    }
  }

  // const isFormValid = validatePassword(password) && validatePasswordConfirmation(password, passwordConfirmation)

  return (
    <div className="w-full max-w-md mx-auto">
      <AuthHeader
        title="Create password"
        showBackButton
        onBack={onBack}
      />

      <AuthCard>
        <p className="text-stone-200/90 text-center">Creating account for {email}</p>

        <form onSubmit={handleSubmit} noValidate>
          <div className="space-y-6 mb-6">
            <div className="space-y-3">
              <Label htmlFor="password" className="text-stone-100 font-medium text-base">
                Password
              </Label>
              <Input
                id="password"
                type="password"
                placeholder="Create a strong password"
                value={password}
                onChange={(e) => onPasswordChange(e.target.value)}
                required
                ref={passwordInputRef}
                className="h-12 bg-stone-900/70 border-stone-700/50 text-stone-50 placeholder:text-stone-400/60 focus:border-stone-500/90 focus:ring-stone-500/30 rounded-lg text-base"
              />
              <div className="text-xs text-stone-400/80 space-y-1">
                <p>Password should be at least 8 characters long and include:</p>
                <ul className="list-disc list-inside space-y-0.5 ml-2">
                  <li>At least one letter</li>
                  <li>At least one number</li>
                </ul>
              </div>
              <div className="text-xs text-red-400 min-h-[40px]">
                {showValidation && passwordErrors.length > 0 && (
                  <div className="space-y-1">
                    {passwordErrors.map((error, index) => (
                      <p key={index}>• {error}</p>
                    ))}
                  </div>
                )}
              </div>
            </div>

            <div className="space-y-3">
              <Label htmlFor="passwordConfirmation" className="text-stone-100 font-medium text-base">
                Confirm Password
              </Label>
              <Input
                id="passwordConfirmation"
                type="password"
                placeholder="Confirm your password"
                value={passwordConfirmation}
                onChange={(e) => onPasswordConfirmationChange(e.target.value)}
                required
                className="h-12 bg-stone-900/70 border-stone-700/50 text-stone-50 placeholder:text-stone-400/60 focus:border-stone-500/90 focus:ring-stone-500/30 rounded-lg text-base"
              />
              <div className="text-xs text-red-400 min-h-[16px]">
                {showValidation && confirmationError && (
                  <p>• {confirmationError}</p>
                )}
              </div>
            </div>
          </div>

          <AuthButton
            type="submit"
            disabled={!password || !passwordConfirmation || isLoading}
          >
            {isLoading ? "Creating account..." : "Create Account"}
          </AuthButton>
        </form>
      </AuthCard>
    </div>
  )
} 