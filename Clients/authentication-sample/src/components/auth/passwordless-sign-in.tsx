import { useRef, useEffect, useState } from "react"
import { AuthCard } from "./auth-card"
import { AuthButton } from "./auth-button"
import { AuthHeader } from "./auth-header"
import { AuthDivider } from "./auth-divider"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Mail, Check } from "lucide-react"

interface PasswordlessSignInProps {
  email: string
  otpCode: string
  onOtpChange: (code: string) => void
  onResendEmail: () => Promise<void>
  onVerifyOtp: () => Promise<void>
  onBack: () => void
  isLoading: boolean
}

export function PasswordlessSignIn({
  email,
  otpCode,
  onOtpChange,
  onResendEmail,
  onVerifyOtp,
  onBack,
  isLoading
}: PasswordlessSignInProps) {
  const [resendSuccess, setResendSuccess] = useState(false)
  const [resendCooldown, setResendCooldown] = useState(0)

  // Resend cooldown timer
  useEffect(() => {
    if (resendCooldown > 0) {
      const timer = setTimeout(() => setResendCooldown(resendCooldown - 1), 1000)
      return () => clearTimeout(timer)
    }
  }, [resendCooldown])

  const handleResendClick = async () => {
    try {
      setResendCooldown(30) // 30 second cooldown
      await onResendEmail()
      onOtpChange("") // Clear the verification code input
      setResendSuccess(true)
    } catch (error) {
      // Handle error if needed
      console.error("Resend failed:", error)
      // Reset cooldown on error
      setResendCooldown(0)
    }
  }

  // Reset success state after 3 seconds
  useEffect(() => {
    if (resendSuccess) {
      const timer = setTimeout(() => {
        setResendSuccess(false)
      }, 3000)
      return () => clearTimeout(timer)
    }
  }, [resendSuccess])

  return (
    <div className="w-full max-w-md mx-auto">
      <AuthHeader
        title="Enter verification code"
        showBackButton
        onBack={onBack}
      />

      <AuthCard>
        <div className="text-center py-6">
          <div className="w-20 h-20 mx-auto mb-6 bg-gradient-to-br from-stone-700/40 to-stone-600/40 rounded-full flex items-center justify-center border-2 border-stone-500/50">
            <Mail className="w-10 h-10 text-stone-300/80" />
          </div>
          <p className="text-stone-200/90 mb-2">We sent a verification code to</p>
          <p className="text-stone-100 font-medium text-lg">{email}</p>
          <p className="text-stone-300/80 text-sm mt-4 leading-relaxed">
            Enter the 6-digit code from your email to sign in. The code will expire in 10 minutes.
          </p>
        </div>

        <form onSubmit={(e) => {
          e.preventDefault()
          if (otpCode.length === 6 && !isLoading) {
            onVerifyOtp()
          }
        }} noValidate>
          <div className="space-y-3 mb-6">
            <Label htmlFor="otp" className="text-stone-100 font-medium text-base">
              6-digit verification code
            </Label>
            <Input
              id="otp"
              type="text"
              placeholder="000000"
              value={otpCode}
              onChange={(e) => onOtpChange(e.target.value.replace(/\D/g, "").slice(0, 6))}
              maxLength={6}
              className="h-12 bg-stone-900/70 border-stone-700/50 text-stone-50 placeholder:text-stone-400/60 focus:border-stone-500/90 focus:ring-stone-500/30 rounded-lg text-base text-center tracking-widest"
            />
          </div>

          <AuthButton
            type="submit"
            disabled={otpCode.length !== 6 || isLoading}
          >
            {isLoading ? "Verifying..." : "Verify Code"}
          </AuthButton>
        </form>

        <AuthDivider text="or" />

        <AuthButton
          variant="secondary"
          onClick={handleResendClick}
          disabled={resendCooldown > 0 || isLoading}
        >
          {resendCooldown > 0 
            ? `Resend code (${resendCooldown}s)` 
            : isLoading ? "Sending..." : "Resend Code"
          }
        </AuthButton>
        
        {/* Reserved space for success message - prevents layout shift */}
        <div className="h-6 mt-4 flex items-center justify-center">
          {resendSuccess && (
            <div className="flex items-center space-x-2 text-green-400 text-sm animate-in fade-in duration-300">
              <Check className="w-4 h-4" />
              <span>Code sent successfully!</span>
            </div>
          )}
        </div>
      </AuthCard>
    </div>
  )
} 