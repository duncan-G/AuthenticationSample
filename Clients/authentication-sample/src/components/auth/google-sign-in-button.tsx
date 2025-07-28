import { Button } from "@/components/ui/button"
import { GoogleIcon } from "./icons"

interface GoogleSignInButtonProps {
  onClick?: () => void
  disabled?: boolean
  theme?: "light" | "dark" | "neutral"
  text?: "signin" | "signup" | "continue"
  shape?: "rectangular" | "pill"
  className?: string
}

export function GoogleSignInButton({ 
  onClick, 
  disabled = false,
  theme = "light",
  text = "signin",
  shape = "rectangular",
  className = ""
}: GoogleSignInButtonProps) {
  // Google-approved button text based on branding guidelines
  const buttonTextMap = {
    signin: "Sign in with Google",
    signup: "Sign up with Google", 
    continue: "Continue with Google"
  }

  // Google-compliant styling based on theme - following exact color specifications
  const themeStyles = {
    light: {
      backgroundColor: '#FFFFFF',
      color: '#1F1F1F',
      border: '2px solid #d6d3d1',
      hoverBackgroundColor: '#F8F9FA'
    },
    dark: {
      backgroundColor: '#000000',
      color: '#FFFFFF', 
      border: '2px solid #78716c',
      hoverBackgroundColor: '#1c1c1e'
    },
    neutral: {
      backgroundColor: '#F2F2F2',
      color: '#1F1F1F',
      border: '2px solid #a8a29e',
      hoverBackgroundColor: '#E8E8E8'
    }
  }

  const currentTheme = themeStyles[theme]
  const borderRadius = shape === "pill" ? "50px" : "8px"

  return (
    <Button
      type="button"
      tabIndex={0}
      className={`
        w-full h-14 flex items-center justify-center
        shadow-sm hover:shadow-md transition-all duration-200
        font-semibold text-base relative overflow-hidden
        ${className}
      `}
      onClick={onClick}
      disabled={disabled}
      style={{
        // Font styling to match Apple's format
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif',
        fontWeight: '600', // Semibold to match Apple
        fontSize: '16px', // text-base to match Apple
        lineHeight: '20px',
        letterSpacing: '-0.022em', // Match Apple's letter spacing
        backgroundColor: currentTheme.backgroundColor,
        color: currentTheme.color,
        border: currentTheme.border,
        borderRadius: borderRadius,
        // Google's specific padding requirements for web
        paddingLeft: '12px',
        paddingRight: '12px',
        minHeight: '48px' // Google's minimum touch target
      }}
      onMouseEnter={(e) => {
        if (!disabled) {
          e.currentTarget.style.backgroundColor = currentTheme.hoverBackgroundColor
        }
      }}
      onMouseLeave={(e) => {
        if (!disabled) {
          e.currentTarget.style.backgroundColor = currentTheme.backgroundColor
        }
      }}
    >
      {/* Google logo with transparent background for dark themes */}
      <div 
        className="flex items-center justify-center mr-3 flex-shrink-0"
        style={{
          width: '18px',
          height: '18px',
          padding: '1px'
        }}
      >
        <GoogleIcon className="w-4 h-4" />
      </div>
      
      {/* Button text with proper spacing */}
      <span className="text-center">
        {buttonTextMap[text]}
      </span>
    </Button>
  )
} 