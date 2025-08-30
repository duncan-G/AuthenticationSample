import { Mail, Lock } from "lucide-react"
import { AuthCard } from "./auth-card"
import { AuthButton } from "./auth-button"
import { AuthHeader } from "./auth-header"
import { AuthDivider } from "./auth-divider"
import { GoogleSignInButton } from "./google-sign-in-button"
import { AppleSignInButton } from "./apple-sign-in-button"

interface MainSignUpProps {
  onGoogleSignUp: () => Promise<void>
  onAppleSignUp: () => Promise<void>
  onPasswordSignUp: () => void
  onPasswordlessSignUp: () => void
  isLoading: boolean
}

export function MainSignUp({ 
  onGoogleSignUp, 
  onAppleSignUp, 
  onPasswordSignUp, 
  onPasswordlessSignUp, 
  isLoading 
}: MainSignUpProps) {
  return (
    <div className="w-full max-w-md mx-auto">
      <AuthHeader 
        title="Join Us" 
        subtitle="Create your account to get started" 
      />

      <AuthCard>
        <div className="space-y-4">
          <GoogleSignInButton
            onClick={onGoogleSignUp}
            theme="dark"
            text="signup"
            disabled={isLoading}
          />

          <AppleSignInButton
            onClick={onAppleSignUp}
            variant="black"
            text="signup"
            disabled={isLoading}
          />
        </div>

        <AuthDivider />

        <div className="space-y-3">
          <AuthButton
            type="button"
            onClick={onPasswordSignUp}
            disabled={isLoading}
            loading={isLoading}
          >
            <Lock className="w-5 h-5 mr-3" />
            Sign up with Password
          </AuthButton>

          <AuthButton
            type="button"
            variant="secondary"
            onClick={onPasswordlessSignUp}
            disabled={isLoading}
            loading={isLoading}
          >
            <Mail className="w-5 h-5 mr-3" />
            Sign up Passwordless
          </AuthButton>
        </div>

        <p className="text-xs text-center text-amber-200/60 mt-6 leading-relaxed">
          By creating an account, you agree to our{" "}
          <button 
            type="button"
            tabIndex={0}
            className="text-amber-100/90 underline hover:text-amber-50 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 rounded px-1"
          >
            Terms of Service
          </button>{" "}
          and{" "}
          <button 
            type="button"
            tabIndex={0}
            className="text-amber-100/90 underline hover:text-amber-50 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 rounded px-1"
          >
            Privacy Policy
          </button>
        </p>
      </AuthCard>
      
      {/* Sign-in link */}
      <div className="text-center mt-6">
        <p className="text-stone-300/80 text-sm">
          Already have an account?{" "}
          <a 
            href="/sign-in"
            className="text-amber-200/90 hover:text-amber-100 underline font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 rounded px-1"
          >
            Sign in
          </a>
        </p>
      </div>
    </div>
  )
} 