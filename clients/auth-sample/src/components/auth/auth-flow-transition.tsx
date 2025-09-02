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
        ${isLoading 
          ? 'pointer-events-none transform-gpu will-change-transform scale-[0.98] opacity-95 transition-transform transition-opacity duration-200 ease-out' 
          : 'transform-gpu will-change-transform scale-100 opacity-100 transition-transform transition-opacity duration-200 ease-out'}
        ${className}
      `.trim()}
    >
      {children}
    </div>
  )
}
