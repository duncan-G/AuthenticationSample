import { useState, useRef, useEffect } from "react"
import { Mail, CheckCircle2, AlertCircle } from "lucide-react"
import { AuthCard } from "./auth-card"
import { AuthButton } from "./auth-button"
import { AuthHeader } from "./auth-header"
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
  serverError?: string
}

export function SignUpPasswordless({
  email,
  otpCode,
  onOtpChange,
  onResendEmail,
  onVerifyOtp,
  onBack,
  isLoading,
  serverError
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
            We&apos;ve sent a verification code to{" "}
            <span className="text-stone-200 font-medium">{email}</span>
          </p>
        </div>

        <form onSubmit={handleSubmit} noValidate>
          <div className="space-y-3 mb-4">
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

          {/* Server error below input */}
          <div className="min-h-6 mb-4 flex items-center">
            {serverError && (
              <div className="flex items-center space-x-2 text-red-400 text-sm">
                <AlertCircle className="w-4 h-4 flex-shrink-0" />
                <span>{serverError}</span>
              </div>
            )}
          </div>

          <AuthButton
            type="submit"
            disabled={otpCode.length !== 6 || isLoading}
            loading={isLoading}
          >
            {isLoading ? "Verifying..." : "Verify Code"}
          </AuthButton>
        </form>

        {/* Resend code link with timeout */}
        <div className="text-center mt-6">
          <p className="text-stone-300/80 text-sm">
            Didn&apos;t receive the code?{" "}
            {resendCooldown > 0 ? (
              <span className="text-stone-400/60">
                Resend in {resendCooldown}s
              </span>
            ) : (
              <button
                type="button"
                onClick={handleResend}
                disabled={isLoading}
                className="text-stone-200 hover:text-stone-100 underline underline-offset-2 transition-colors duration-200 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {isLoading ? "Sending..." : "Resend code"}
              </button>
            )}
          </p>
        </div>
      </AuthCard>
    </div>
  )
} 