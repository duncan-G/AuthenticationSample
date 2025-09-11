import { CheckCircle2 } from "lucide-react"
import { AuthCard } from "./auth-card"
import { AuthHeader } from "./auth-header"
import { AuthButton } from "./auth-button"

interface SignUpSuccessProps {
  onGoToSignIn: () => void
}

export function SignUpSuccess({ onGoToSignIn }: SignUpSuccessProps) {
  return (
    <div className="w-full max-w-md mx-auto">
      <AuthHeader title="Welcome aboard! 🎉" />
      <AuthCard>
        <div className="text-center px-2 py-4">
          <div className="w-20 h-20 mx-auto mb-5 bg-gradient-to-br from-green-600/40 to-green-500/40 rounded-full flex items-center justify-center border-2 border-green-500/50">
            <CheckCircle2 className="w-10 h-10 text-green-400" />
          </div>
          <h3 className="text-stone-100 text-xl font-semibold mb-2">Thank you for signing up</h3>
          <p className="text-stone-300/80 text-sm mb-6">We're excited to have you! Your account is ready — sign in to get started.</p>
          <AuthButton
            onClick={onGoToSignIn}
            className="text-lg"
          >
            Sign in to continue
          </AuthButton>
        </div>
      </AuthCard>
    </div>
  )
}


