import { Button } from "@/components/ui/button"
import { ArrowLeft } from "lucide-react"

interface AuthHeaderProps {
  title: string
  subtitle?: string
  showBackButton?: boolean
  onBack?: () => void
}

export function AuthHeader({ title, subtitle, showBackButton, onBack }: AuthHeaderProps) {
  if (showBackButton && onBack) {
    return (
      <div className="flex items-center mb-6">
        <Button
          variant="ghost"
          size="sm"
          onClick={onBack}
          className="p-2 text-stone-300 hover:text-stone-200 hover:bg-stone-700/30 rounded-full"
          aria-label="Back"
          title="Back"
        >
          <ArrowLeft className="w-5 h-5" />
          <span className="sr-only">Back</span>
        </Button>
        <h1 className="text-2xl font-bold text-amber-50 ml-4">{title}</h1>
      </div>
    )
  }

  return (
    <div className="text-center mb-8">
      <h1 className="text-4xl font-bold text-amber-50 mb-2 tracking-wide">{title}</h1>
      {subtitle && (
        <p className="text-lg text-amber-100/90 font-light">{subtitle}</p>
      )}
    </div>
  )
} 