"use client"

import { useEffect } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import ThemeInitializer from "@/components/theme/theme-initializer"

export default function ErrorPage() {
  const router = useRouter()
  const searchParams = useSearchParams()
  
  const message = searchParams.get("message") || "Something went wrong"
  const from = searchParams.get("from") || "/"

  useEffect(() => {
    // Auto-redirect to sign-in after 5 seconds
    const timer = setTimeout(() => {
      router.push("/sign-in")
    }, 5000)

    return () => clearTimeout(timer)
  }, [router])

  return (
    <>
      <ThemeInitializer />
      <div className="min-h-screen flex items-center justify-center bg-background">
        <div className="max-w-md w-full bg-card shadow-lg rounded-lg p-6 text-center border">
          <div className="mb-4">
            <div className="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-destructive/10">
              <svg
                className="h-6 w-6 text-destructive"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.732-.833-2.5 0L4.268 19.5c-.77.833.192 2.5 1.732 2.5z"
                />
              </svg>
            </div>
          </div>
          <h1 className="text-xl font-semibold text-foreground mb-2">
            Something went wrong
          </h1>
          <p className="text-muted-foreground mb-6">
            We encountered an unexpected error. This could be due to a temporary service issue.
          </p>
          <div className="space-y-3">
            <button
              onClick={() => router.push(from)}
              className="w-full bg-secondary text-secondary-foreground py-2 px-4 rounded-md hover:bg-secondary/80 transition-colors"
            >
              Try Again
            </button>
          </div>
          {process.env.NODE_ENV === "development" && (
            <details className="mt-4 text-left">
              <summary className="cursor-pointer text-sm text-muted-foreground hover:text-foreground">
                Error Details (Development)
              </summary>
              <pre className="mt-2 text-xs text-destructive bg-destructive/10 p-2 rounded overflow-auto">
                {message}
              </pre>
            </details>
          )}
        </div>
      </div>
    </>
  )
}
