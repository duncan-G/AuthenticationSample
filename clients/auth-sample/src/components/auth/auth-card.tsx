import { Card, CardContent } from "@/components/ui/card"
import { ReactNode } from "react"

interface AuthCardProps {
  children: ReactNode
  className?: string
}

export function AuthCard({ children, className = "" }: AuthCardProps) {
  return (
    <Card className={`backdrop-blur-xl bg-gradient-to-b from-stone-950/60 to-stone-800/80 border-stone-600/30 shadow-2xl shadow-black/50 ${className}`}>
      <CardContent className="p-8 space-y-6">
        {children}
      </CardContent>
    </Card>
  )
} 