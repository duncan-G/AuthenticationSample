import { Button } from "@/components/ui/button"
import { ReactNode } from "react"

type ButtonVariant = "primary" | "secondary" | "ghost" | "outline"

interface AuthButtonProps {
  children: ReactNode
  variant?: ButtonVariant
  onClick?: () => void
  disabled?: boolean
  className?: string
  type?: "button" | "submit" | "reset"
  tabIndex?: number
  loading?: boolean
}

const variantStyles: Record<ButtonVariant, string> = {
  // Primary button for main actions (Continue with Email, Sign In, etc.)
  primary: "w-full h-14 bg-gradient-to-r from-stone-800/95 to-stone-900/95 hover:from-stone-700/95 hover:to-stone-800/95 text-stone-50 border-2 border-stone-600/70 hover:border-stone-500/80 shadow-lg hover:shadow-xl transition-all duration-300 font-medium text-base",
  // Secondary button for alternative actions
  secondary: "w-full h-14 bg-gradient-to-r from-stone-800/80 to-stone-700/80 hover:from-stone-700/90 hover:to-stone-600/90 text-stone-50 border-2 border-stone-600/50 hover:border-stone-500/70 shadow-lg hover:shadow-xl transition-all duration-300 font-medium text-base",
  // Ghost button for subtle actions
  ghost: "w-full h-14 bg-transparent hover:bg-stone-700/20 text-stone-300 hover:text-stone-200 border-0 shadow-none hover:shadow-sm transition-all duration-300 font-medium text-base",
  // Outline button for tertiary actions
  outline: "w-full h-14 bg-transparent hover:bg-stone-800/30 text-stone-300 hover:text-stone-200 border-2 border-stone-600/50 hover:border-stone-500/70 shadow-sm hover:shadow-md transition-all duration-300 font-medium text-base"
}

export function AuthButton({ 
  children, 
  variant = "primary", 
  onClick, 
  disabled, 
  className = "",
  type = "button",
  tabIndex = 0,
  loading = false
}: AuthButtonProps) {
  return (
    <Button
      type={type}
      tabIndex={tabIndex}
      className={`${variantStyles[variant]} ${className}`}
      onClick={onClick}
      disabled={disabled || loading}
    >
      <span className="inline-flex items-center justify-center">
        {children}
        {loading && (
          <div className="ml-3 animate-spin rounded-full h-5 w-5 border-2 border-stone-300/30 border-t-stone-200 shadow-sm" />
        )}
      </span>
    </Button>
  )
} 