interface AuthDividerProps {
  text?: string
}

export function AuthDivider({ text = "OR" }: AuthDividerProps) {
  return (
    <div className="relative py-4">
      <div className="absolute inset-0 flex items-center">
        <div className="w-full border-t border-stone-600/40"></div>
      </div>
      <div className="relative flex justify-center">
        <span className="relative z-10 bg-stone-900 px-6 py-2 text-sm font-medium text-stone-300/80 rounded-full border border-stone-600/30">
          {text}
        </span>
      </div>
    </div>
  )
} 