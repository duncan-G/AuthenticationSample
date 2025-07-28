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
  direction: _direction = "forward", // Reserved for future animation direction logic
  isLoading = false,
  className = "" 
}: AuthFlowTransitionProps) {
  void _direction // Reserved for future animation direction logic
  
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
