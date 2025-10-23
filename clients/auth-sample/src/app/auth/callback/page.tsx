"use client"

import { useEffect } from "react"
import { useAuth } from "react-oidc-context"

export default function OidcCallbackPage() {
  const auth = useAuth()

  useEffect(() => {
    // react-oidc-context will handle processing the callback automatically
    // when this page mounts due to redirect_uri matching this route
  }, [])

  if (auth.isLoading) {
    return <div className="p-6">Loading...</div>
  }

  if (auth.error) {
    return <div className="p-6">Encountering error... {auth.error.message}</div>
  }

  // After successful sign-in, navigate the user to home
  if (auth.isAuthenticated) {
    if (typeof window !== 'undefined') {
      window.location.replace("/")
    }
    return null
  }

  return <div className="p-6">Processing sign-in...</div>
}


