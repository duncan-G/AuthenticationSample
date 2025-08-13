import { Fingerprint } from "lucide-react"
import { AuthCard } from "./auth-card"
import { AuthButton } from "./auth-button"
import { AuthHeader } from "./auth-header"

interface PasskeySignInProps {
  email: string
  onPasskeySignIn: () => Promise<void>
  onPasswordFlow: () => void
  onBack: () => void
  isLoading: boolean
}

export function PasskeySignIn({
  email,
  onPasskeySignIn,
  onPasswordFlow,
  onBack,
  isLoading
}: PasskeySignInProps) {
  return (
    <div className="w-full max-w-md mx-auto">
      <AuthHeader
        title="Use your passkey"
        showBackButton
        onBack={onBack}
      />

      <AuthCard>
        <p className="text-stone-200/90 text-center">Signing in to {email}</p>

        <div className="text-center py-8">
          <div className="w-24 h-24 mx-auto mb-6 bg-gradient-to-br from-stone-700/40 to-stone-600/40 rounded-full flex items-center justify-center border-2 border-stone-500/50">
            <Fingerprint className="w-12 h-12 text-stone-300/80" />
          </div>
          <p className="text-stone-300/80 text-lg mb-2">Secure Authentication</p>
          <p className="text-stone-300/80 text-sm leading-relaxed">
            Use your fingerprint, face, or security key to sign in securely.
          </p>
        </div>

        <AuthButton
          onClick={onPasskeySignIn}
          disabled={isLoading}
        >
          {isLoading ? "Authenticating..." : "Use Passkey"}
        </AuthButton>

        <AuthButton
          variant="secondary"
          onClick={onPasswordFlow}
        >
          Use Password Instead
        </AuthButton>
      </AuthCard>
    </div>
  )
} 