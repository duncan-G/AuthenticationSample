import { ReactNode } from "react"

interface AuthFlowTransitionProps {
  children: ReactNode
  flowKey: string
  direction?: "forward" | "backward"
  isLoading?: boolean
  className?: string
}

export function AuthFlowTransition({ 
  children, 
  flowKey, 
  direction = "forward",
  isLoading = false,
  className = "" 
}: AuthFlowTransitionProps) {
  return (
    <div 
      key={flowKey}
      className={`
        ${isLoading ? 'pointer-events-none opacity-75' : ''}
        ${className}
      `}
    >
      {children}
    </div>
  )
}
