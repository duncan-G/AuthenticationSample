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
  direction: _direction = "forward",
  isLoading = false,
  className = "" 
}: AuthFlowTransitionProps) {
  void _direction // Intentionally unused, reserved for future animation direction logic
  
  return (
    <div 
      key={flowKey}
      className={`
        ${isLoading ? 'pointer-events-none scale-[0.98] blur-[0.5px] transition-all duration-200 ease-out' : 'scale-100 blur-0 transition-all duration-200 ease-out'}
        ${className}
      `.trim()}
    >
      {children}
    </div>
  )
}
