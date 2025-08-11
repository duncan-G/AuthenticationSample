"use client"

import { useAuth } from "@/hooks/useAuth"
import { useState, useEffect } from "react"
import {
  MainSignIn,
  EmailOptions,
  PasswordSignIn,
  PasswordlessSignIn,
  PasskeySignIn,
  AuthFlowTransition
} from "@/components/auth"

export default function SignInPage() {
  const auth = useAuth()

  // Background carousel state
  const backgroundImages = [
    "/images/auth-background-01.png",
    "/images/auth-background-02.png",
    "/images/auth-background-03.png",
    "/images/auth-background-04.png",
    "/images/auth-background-05.png",
    "/images/auth-background-06.png",
  ]
  // Start with first image for sign-in page (deterministic for SSR)
  const [currentBackgroundIndex, setCurrentBackgroundIndex] = useState(0)

  // Randomly transition backgrounds every 8 seconds
  useEffect(() => {
    const interval = setInterval(() => {
      setCurrentBackgroundIndex((prevIndex) => {
        let newIndex
        do {
          newIndex = Math.floor(Math.random() * backgroundImages.length)
        } while (newIndex === prevIndex && backgroundImages.length > 1)
        return newIndex
      })
    }, 8000)

    return () => clearInterval(interval)
  }, [backgroundImages.length])

  // Helper to determine transition direction based on flow navigation
  const getFlowDirection = (): "forward" | "backward" => {
    // For now, we'll handle back navigation in the individual components
    // This could be enhanced with a flow history state if needed
    return "forward"
  }

  const renderCurrentFlow = () => {
    switch (auth.currentFlow) {
      case "main":
        return (
          <AuthFlowTransition
            flowKey="main"
            direction={getFlowDirection()}
            isLoading={auth.isLoading}
          >
            <MainSignIn
              onGoogleSignIn={auth.handleGoogleSignIn}
              onAppleSignIn={auth.handleAppleSignIn}
              onEmailSignIn={auth.handleEmailSignIn}
              isLoading={auth.isLoading}
            />
          </AuthFlowTransition>
        )
      case "email-options":
        return (
          <AuthFlowTransition
            flowKey="email-options"
            direction={getFlowDirection()}
            isLoading={auth.isLoading}
          >
            <EmailOptions
              email={auth.email}
              onEmailChange={auth.setEmail}
              onPasswordFlow={() => auth.setCurrentFlow("password")}
              onPasswordlessFlow={() => auth.setCurrentFlow("passwordless")}
              onBack={() => auth.setCurrentFlow("main")}
              isLoading={auth.isLoading}
            />
          </AuthFlowTransition>
        )
      case "password":
        return (
          <AuthFlowTransition
            flowKey="password"
            direction={getFlowDirection()}
            isLoading={auth.isLoading}
          >
            <PasswordSignIn
              email={auth.email}
              password={auth.password}
              onPasswordChange={auth.setPassword}
              onPasswordSignIn={auth.handlePasswordSignIn}
              onPasskeyFlow={() => auth.setCurrentFlow("passkey")}
              onBack={() => auth.setCurrentFlow("email-options")}
              isLoading={auth.isLoading}
            />
          </AuthFlowTransition>
        )
      case "passwordless":
        return (
          <AuthFlowTransition
            flowKey="passwordless"
            direction={getFlowDirection()}
            isLoading={auth.isLoading}
          >
            <PasswordlessSignIn
              email={auth.email}
              otpCode={auth.otpCode}
              onOtpChange={auth.setOtpCode}
              onResendEmail={auth.handlePasswordlessSignIn}
              onVerifyOtp={auth.handleOtpVerification}
              onBack={() => auth.setCurrentFlow("email-options")}
              isLoading={auth.isLoading}
            />
          </AuthFlowTransition>
        )
      case "passkey":
        return (
          <AuthFlowTransition
            flowKey="passkey"
            direction={getFlowDirection()}
            isLoading={auth.isLoading}
          >
            <PasskeySignIn
              email={auth.email}
              onPasskeySignIn={auth.handlePasskeySignIn}
              onPasswordFlow={() => auth.setCurrentFlow("password")}
              onBack={() => auth.setCurrentFlow("password")}
              isLoading={auth.isLoading}
            />
          </AuthFlowTransition>
        )
      default:
        return null
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center p-4 relative overflow-hidden">
      {/* Background images with smooth transitions */}
      {backgroundImages.map((bgImage, index) => (
        <div
          key={bgImage}
          className={`absolute inset-0 bg-cover bg-center bg-no-repeat transition-opacity duration-1000 ease-in-out ${
            index === currentBackgroundIndex ? 'opacity-100' : 'opacity-0'
          }`}
          style={{ backgroundImage: `url(${bgImage})` }}
        />
      ))}

      {/* Enhanced overlay with warm gradient */}
      <div className="absolute inset-0 bg-gradient-to-br from-black/70 via-stone-900/30 to-black/60 z-10"></div>

      <div className="w-full max-w-md relative z-20 animate-slide-in-from-bottom">
        <div className="transition-all duration-300 ease-out">
          {renderCurrentFlow()}
        </div>
      </div>
    </div>
  )
}
