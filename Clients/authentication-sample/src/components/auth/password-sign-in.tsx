import { Fingerprint } from "lucide-react"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { AuthCard } from "./auth-card"
import { AuthButton } from "./auth-button"
import { AuthHeader } from "./auth-header"
import { AuthDivider } from "./auth-divider"
import { useEffect, useRef } from "react"

interface PasswordSignInProps {
  email: string
  password: string
  onPasswordChange: (password: string) => void
  onPasswordSignIn: () => Promise<void>
  onPasskeyFlow: () => void
  onBack: () => void
  isLoading: boolean
}

export function PasswordSignIn({
  email,
  password,
  onPasswordChange,
  onPasswordSignIn,
  onPasskeyFlow,
  onBack,
  isLoading
}: PasswordSignInProps) {
  const passwordInputRef = useRef<HTMLInputElement>(null)

  // Auto-focus on password input when component mounts
  useEffect(() => {
    if (passwordInputRef.current) {
      passwordInputRef.current.focus()
    }
  }, [])

  // Handle form submission (Enter key)
  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (password && !isLoading) {
      onPasswordSignIn()
    }
  }
  return (
    <div className="w-full max-w-md mx-auto">
      <AuthHeader
        title="Enter password"
        showBackButton
        onBack={onBack}
      />

      <AuthCard>
        <p className="text-stone-200/90 text-center">Signing in to {email}</p>

        <form onSubmit={handleSubmit} noValidate>
          <div className="space-y-3 mb-6">
            <Label htmlFor="password" className="text-stone-100 font-medium text-base">
              Password
            </Label>
            <Input
              id="password"
              type="password"
              placeholder="Enter your password"
              value={password}
              onChange={(e) => onPasswordChange(e.target.value)}
              required
              ref={passwordInputRef}
              className="h-12 bg-stone-900/70 border-stone-700/50 text-stone-50 placeholder:text-stone-400/60 focus:border-stone-500/90 focus:ring-stone-500/30 rounded-lg text-base"
            />
          </div>

          <AuthButton
            type="submit"
            disabled={!password || isLoading}
          >
            {isLoading ? "Signing in..." : "Sign In"}
          </AuthButton>
        </form>

        <AuthDivider text="or use" />

        <AuthButton
          variant="secondary"
          onClick={onPasskeyFlow}
          disabled={isLoading}
        >
          <Fingerprint className="w-5 h-5 mr-3" />
          Sign in with Passkey
        </AuthButton>

        <p className="text-center pt-4">
          <button 
            type="button"
            tabIndex={0}
            className="text-stone-400/80 hover:text-stone-300 underline text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 rounded px-2 py-1"
          >
            Forgot your password?
          </button>
        </p>
      </AuthCard>
    </div>
  )
} 