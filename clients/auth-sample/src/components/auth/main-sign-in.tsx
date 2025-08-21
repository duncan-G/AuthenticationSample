import { Mail } from "lucide-react"
import { AuthCard } from "./auth-card"
import { AuthButton } from "./auth-button"
import { AuthHeader } from "./auth-header"
import { AuthDivider } from "./auth-divider"
import { GoogleSignInButton } from "./google-sign-in-button"
import { AppleSignInButton } from "./apple-sign-in-button"

interface MainSignInProps {
  onGoogleSignIn: () => Promise<void>
  onAppleSignIn: () => Promise<void>
  onEmailSignIn: () => void
  isLoading: boolean
}

export function MainSignIn({ 
  onGoogleSignIn, 
  onAppleSignIn, 
  onEmailSignIn, 
  isLoading 
}: MainSignInProps) {
  return (
    <div className="w-full max-w-md mx-auto">
      <AuthHeader 
        title="Welcome" 
        subtitle="Choose your path to continue" 
      />

      <AuthCard>
        <div className="space-y-4">
          <GoogleSignInButton
            onClick={onGoogleSignIn}
            theme="dark"
            text="continue"
            disabled={isLoading}
          />

          <AppleSignInButton
            onClick={onAppleSignIn}
            variant="black"
            text="continue"
            disabled={isLoading}
          />
        </div>

        <AuthDivider />

        <AuthButton
          type="button"
          onClick={onEmailSignIn}
          disabled={isLoading}
          loading={isLoading}
        >
          <Mail className="w-5 h-5 mr-3" />
          Sign in with email
        </AuthButton>

        <p className="text-xs text-center text-amber-200/60 mt-6 leading-relaxed">
          By continuing, you agree to our{" "}
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
      
      {/* Sign-up link */}
      <div className="text-center mt-6">
        <p className="text-stone-300/80 text-sm">
          Don&apos;t have an account?{" "}
          <a 
            href="/sign-up"
            className="text-amber-200/90 hover:text-amber-100 underline font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 rounded px-1"
          >
            Sign up
          </a>
        </p>
      </div>
    </div>
  )
} 