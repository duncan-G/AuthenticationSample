"use client"

import { useAuth } from "@/hooks/useAuth"
import { useState, useEffect } from "react"
import { 
  MainSignUp, 
  SignUpEmailOptions, 
  SignUpPassword, 
  SignUpPasswordless,
  AuthFlowTransition 
} from "@/components/auth"

export default function SignUpPage() {
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
      case "signup-main":
        return (
          <AuthFlowTransition 
            flowKey="signup-main" 
            direction={getFlowDirection()}
            isLoading={auth.isLoading}
          >
            <MainSignUp
              onGoogleSignUp={auth.handleGoogleSignUp}
              onAppleSignUp={auth.handleAppleSignUp}
              onPasswordSignUp={auth.handlePasswordSignUpFlow}
              onPasswordlessSignUp={auth.handlePasswordlessSignUpFlow}
              isLoading={auth.isLoading}
            />
          </AuthFlowTransition>
        )
      case "signup-email-options":
        return (
          <AuthFlowTransition 
            flowKey="signup-email-options" 
            direction={getFlowDirection()}
            isLoading={auth.isLoading}
          >
            <SignUpEmailOptions
              email={auth.email}
              onEmailChange={auth.setEmail}
              onPasswordFlow={() => auth.setCurrentFlow("signup-password")}
              onPasswordlessFlow={() => auth.setCurrentFlow("signup-passwordless")}
              onBack={() => auth.setCurrentFlow("signup-main")}
              isLoading={auth.isLoading}
              signupMethod={auth.signupMethod}
            />
          </AuthFlowTransition>
        )
      case "signup-password":
        return (
          <AuthFlowTransition 
            flowKey="signup-password" 
            direction={getFlowDirection()}
            isLoading={auth.isLoading}
          >
            <SignUpPassword
              email={auth.email}
              password={auth.password}
              passwordConfirmation={auth.passwordConfirmation}
              onPasswordChange={auth.setPassword}
              onPasswordConfirmationChange={auth.setPasswordConfirmation}
              onPasswordSignUp={auth.handlePasswordSignUp}
              onBack={() => auth.setCurrentFlow("signup-email-options")}
              isLoading={auth.isLoading}
            />
          </AuthFlowTransition>
        )
      case "signup-passwordless":
        return (
          <AuthFlowTransition 
            flowKey="signup-passwordless" 
            direction={getFlowDirection()}
            isLoading={auth.isLoading}
          >
            <SignUpPasswordless
              email={auth.email}
              otpCode={auth.otpCode}
              onOtpChange={auth.setOtpCode}
              onResendEmail={auth.handlePasswordlessSignUp}
              onVerifyOtp={auth.handleSignUpOtpVerification}
              onBack={() => auth.setCurrentFlow("signup-email-options")}
              isLoading={auth.isLoading}
            />
          </AuthFlowTransition>
        )
      default:
        // Default to signup-main if no flow is set or invalid flow
        auth.setCurrentFlow("signup-main")
        return null
    }
  }

  // Set default flow to signup-main on page load
  useEffect(() => {
    if (auth.currentFlow === "main" || !auth.currentFlow.startsWith("signup")) {
      auth.setCurrentFlow("signup-main")
    }
  }, [auth])

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
      
      <div className="w-full max-w-md relative z-20">
        <div className="transition-all duration-300 ease-out">
          {renderCurrentFlow()}
        </div>
      </div>
    </div>
  )
} 