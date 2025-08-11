import { Button } from "@/components/ui/button"
import { AppleIcon } from "./icons"

interface AppleSignInButtonProps {
  onClick?: () => void
  disabled?: boolean
  variant?: "black" | "white" | "outline"
  text?: "signin" | "continue" | "signup"
  className?: string
}

export function AppleSignInButton({ 
  onClick, 
  disabled = false,
  variant = "black",
  text = "signin",
  className = ""
}: AppleSignInButtonProps) {
  // Apple-approved button text based on Human Interface Guidelines
  const buttonTextMap = {
    signin: "Sign in with Apple",
    continue: "Continue with Apple", 
    signup: "Sign up with Apple"
  }

  // Apple-compliant styling based on variant
  const variantStyles = {
    black: "bg-black hover:bg-[#1c1c1e] text-white border-2 border-stone-600",
    white: "bg-white hover:bg-[#f2f2f7] text-black border-2 border-stone-300",
    outline: "bg-transparent hover:bg-[#f2f2f7] text-black border-2 border-stone-600"
  }

  return (
    <Button
      type="button"
      tabIndex={0}
      className={`
        w-full h-14 rounded-lg shadow-sm hover:shadow-md 
        transition-all duration-200 font-semibold text-base 
        min-h-[44px] min-w-[140px] flex items-center justify-center
        ${variantStyles[variant]}
        ${className}
      `}
      onClick={onClick}
      disabled={disabled}
      style={{
        // Apple's required font specifications
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif',
        letterSpacing: '-0.022em',
        borderRadius: '8px',
        // Ensure proper minimum sizing per Apple guidelines
        minWidth: '140px',
        minHeight: '44px'
      }}
    >
      <AppleIcon className="w-5 h-5 mr-3 flex-shrink-0" />
      <span className="text-center">{buttonTextMap[text]}</span>
    </Button>
  )
} 