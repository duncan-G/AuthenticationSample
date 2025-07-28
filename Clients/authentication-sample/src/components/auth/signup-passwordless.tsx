import { useState, useRef, useEffect } from "react"
import { Mail, CheckCircle2 } from "lucide-react"
import { AuthCard } from "./auth-card"
import { AuthButton } from "./auth-button"
import { AuthHeader } from "./auth-header"
import { AuthDivider } from "./auth-divider"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"

interface SignUpPasswordlessProps {
  email: string
  otpCode: string
  onOtpChange: (code: string) => void
  onResendEmail: () => Promise<void>
  onVerifyOtp: () => Promise<void>
  onBack: () => void
  isLoading: boolean
}

export function SignUpPasswordless({
  email,
  otpCode,
  onOtpChange,
  onResendEmail,
  onVerifyOtp,
  onBack,
  isLoading
}: SignUpPasswordlessProps) {
  const [emailSent, setEmailSent] = useState(false)
  const [resendCooldown, setResendCooldown] = useState(0)
  const otpInputRef = useRef<HTMLInputElement>(null)

  // Auto-focus on OTP input when component mounts
  useEffect(() => {
    // Simulate email being sent on mount
    setEmailSent(true)
    
    // Focus on OTP input after a short delay
    const timer = setTimeout(() => {
      if (otpInputRef.current) {
        otpInputRef.current.focus()
      }
    }, 500)

    return () => clearTimeout(timer)
  }, [])

  // Resend cooldown timer
  useEffect(() => {
    if (resendCooldown > 0) {
      const timer = setTimeout(() => setResendCooldown(resendCooldown - 1), 1000)
      return () => clearTimeout(timer)
    }
  }, [resendCooldown])

  const handleResend = async () => {
    setResendCooldown(30) // 30 second cooldown
    await onResendEmail()
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (otpCode && !isLoading) {
      onVerifyOtp()
    }
  }

  return (
    <div className="w-full max-w-md mx-auto">
      <AuthHeader
        title="Check your email"
        showBackButton
        onBack={onBack}
      />

      <AuthCard>
        <div className="text-center mb-6">
          {emailSent ? (
            <div className="w-16 h-16 mx-auto mb-4 bg-gradient-to-br from-green-600/40 to-green-500/40 rounded-full flex items-center justify-center border-2 border-green-500/50">
              <CheckCircle2 className="w-8 h-8 text-green-400" />
            </div>
          ) : (
            <div className="w-16 h-16 mx-auto mb-4 bg-gradient-to-br from-stone-700/40 to-stone-600/40 rounded-full flex items-center justify-center border-2 border-stone-500/50">
              <Mail className="w-8 h-8 text-stone-300/80" />
            </div>
          )}
          
          <h3 className="text-stone-200/90 text-lg font-medium mb-2">
            Verification email sent
          </h3>
          <p className="text-stone-300/80 text-sm leading-relaxed">
            We've sent a verification code to{" "}
            <span className="text-stone-200 font-medium">{email}</span>
          </p>
        </div>

        <form onSubmit={handleSubmit} noValidate>
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
              ref={otpInputRef}
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
          onClick={handleResend}
          disabled={resendCooldown > 0 || isLoading}
        >
          {resendCooldown > 0 
            ? `Resend code (${resendCooldown}s)` 
            : "Resend Code"
          }
        </AuthButton>
      </AuthCard>
    </div>
  )
} 