import React from 'react'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { useAuth } from '@/hooks/useAuth'
import { AuthFlow } from '@/types/auth'
import { MainSignIn } from '@/components/auth/main-sign-in'
import { MainSignUp } from '@/components/auth/main-sign-up'
import { SignUpEmailOptions } from '@/components/auth/signup-email-options'
import { PasswordSignIn } from '@/components/auth/password-sign-in'

// Mock the validation function
jest.mock('@/lib/validation', () => ({
  validateEmail: jest.fn(() => true),
}))

// Helper component to test the complete auth flow
function AuthFlowTestComponent({ initialFlow = 'main' }: { initialFlow?: string }) {
  const auth = useAuth()

  // Set the initial flow immediately
  React.useEffect(() => {
    auth.setCurrentFlow(initialFlow as AuthFlow)
  }, [initialFlow, auth])

  const renderCurrentFlow = () => {
    switch (auth.currentFlow) {
      case 'main':
        return (
          <MainSignIn
            onGoogleSignIn={auth.handleGoogleSignIn}
            onAppleSignIn={auth.handleAppleSignIn}
            onEmailSignIn={auth.handleEmailSignIn}
            isLoading={auth.isLoading}
          />
        )
      case 'signup-main':
        return (
          <MainSignUp
            onGoogleSignUp={auth.handleGoogleSignUp}
            onAppleSignUp={auth.handleAppleSignUp}
            onPasswordSignUp={auth.handlePasswordSignUpFlowStart}
            onPasswordlessSignUp={auth.handlePasswordlessSignUpFlowStart}
            isLoading={auth.isLoading}
          />
        )
      case 'signup-email-options':
        return (
          <SignUpEmailOptions
            email={auth.email}
            onEmailChange={auth.setEmail}
            onPasswordFlow={() => auth.setCurrentFlow('signup-password')}
            onPasswordlessFlow={auth.handlePasswordlessSignUp}
            onBack={() => auth.setCurrentFlow('signup-main')}
            isLoading={auth.isLoading}
            signupMethod={auth.signupMethod}
          />
        )
      case 'password':
        return (
          <PasswordSignIn
            email={auth.email}
            password={auth.password}
            onPasswordChange={auth.setPassword}
            onPasswordSignIn={auth.handlePasswordSignIn}
            onPasskeyFlow={auth.handlePasskeySignIn}
            onBack={() => auth.setCurrentFlow('email-options')}
            isLoading={auth.isLoading}
          />
        )
      default:
        return <div>Unknown flow: {auth.currentFlow}</div>
    }
  }

  return (
    <div>
      <div data-testid="current-flow">{auth.currentFlow}</div>
      <div data-testid="current-email">{auth.email}</div>
      <div data-testid="signup-method">{auth.signupMethod || 'none'}</div>
      {renderCurrentFlow()}
    </div>
  )
}

describe('Authentication Flow Integration Tests', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    // Mock console.log to avoid noise in test output
    jest.spyOn(console, 'log').mockImplementation(() => {})
  })

  afterEach(() => {
    jest.restoreAllMocks()
  })

  describe('Sign-in Flow', () => {
    it('should navigate from main sign-in to email options', async () => {
      const user = userEvent.setup()
      render(<AuthFlowTestComponent />)

      // Should start on main sign-in
      expect(screen.getByTestId('current-flow')).toHaveTextContent('main')
      expect(screen.getByText('Welcome')).toBeInTheDocument()

      // Click on email sign-in
      const emailButton = screen.getByText('Sign in with email')
      await user.click(emailButton)

      // Should navigate to email options
      expect(screen.getByTestId('current-flow')).toHaveTextContent('email-options')
    })

    it('should handle Google sign-in from main page', async () => {
      const user = userEvent.setup()
      render(<AuthFlowTestComponent />)

      const googleButton = screen.getByText('Continue with Google')
      await user.click(googleButton)

      expect(console.log).toHaveBeenCalledWith('Google sign in')
    })

    it('should handle Apple sign-in from main page', async () => {
      const user = userEvent.setup()
      render(<AuthFlowTestComponent />)

      const appleButton = screen.getByText('Continue with Apple')
      await user.click(appleButton)

      expect(console.log).toHaveBeenCalledWith('Apple sign in')
    })
  })

  describe('Sign-up Flow', () => {
    it('should navigate through password sign-up flow', async () => {
      const user = userEvent.setup()
      render(<AuthFlowTestComponent initialFlow="signup" />)

             // Start on main sign-up
       expect(screen.getByTestId('current-flow')).toHaveTextContent('signup-main')
      expect(screen.getByText('Join Us')).toBeInTheDocument()

      // Click on password sign-up
      const passwordButton = screen.getByText('Sign up with Password')
      await user.click(passwordButton)

      // Should navigate to email options with password method
      await waitFor(() => {
        expect(screen.getByTestId('current-flow')).toHaveTextContent('signup-email-options')
        expect(screen.getByTestId('signup-method')).toHaveTextContent('password')
      })

      // Should show password-specific content
      expect(screen.getByText('Create account with password')).toBeInTheDocument()
    })

    it('should navigate through passwordless sign-up flow', async () => {
      const user = userEvent.setup()
      render(<AuthFlowTestComponent initialFlow="signup" />)

      // Click on passwordless sign-up
      const passwordlessButton = screen.getByText('Sign up Passwordless')
      await user.click(passwordlessButton)

      // Should navigate to email options with passwordless method
      await waitFor(() => {
        expect(screen.getByTestId('current-flow')).toHaveTextContent('signup-email-options')
        expect(screen.getByTestId('signup-method')).toHaveTextContent('passwordless')
      })

      // Should show passwordless-specific content
      expect(screen.getByText('Create passwordless account')).toBeInTheDocument()
    })

    it('should handle complete email and password sign-up flow', async () => {
      const user = userEvent.setup()
      render(<AuthFlowTestComponent initialFlow="signup" />)

      // Navigate to password sign-up
      const passwordButton = screen.getByText('Sign up with Password')
      await user.click(passwordButton)

      await waitFor(() => {
        expect(screen.getByTestId('current-flow')).toHaveTextContent('signup-email-options')
      })

      // Enter email
      const emailInput = screen.getByLabelText('Email address')
      await user.type(emailInput, 'test@example.com')

      // Should update email state
      await waitFor(() => {
        expect(screen.getByTestId('current-email')).toHaveTextContent('test@example.com')
      })

      // Submit form to proceed to password creation
      const continueButton = screen.getByRole('button', { name: 'Continue' })
      await user.click(continueButton)

      // Should navigate to password creation step
      await waitFor(() => {
        expect(screen.getByTestId('current-flow')).toHaveTextContent('signup-password')
      })
    })

    it('should handle passwordless sign-up submission', async () => {
      const user = userEvent.setup()
      render(<AuthFlowTestComponent initialFlow="signup" />)

      // Navigate to passwordless sign-up
      const passwordlessButton = screen.getByText('Sign up Passwordless')
      await user.click(passwordlessButton)

      await waitFor(() => {
        expect(screen.getByTestId('current-flow')).toHaveTextContent('signup-email-options')
      })

      // Enter email
      const emailInput = screen.getByLabelText('Email address')
      await user.type(emailInput, 'test@example.com')

      // Submit for passwordless sign-up
      const submitButton = screen.getByRole('button', { name: 'Send verification email' })
      await user.click(submitButton)

      // Should call passwordless sign-up handler
      expect(console.log).toHaveBeenCalledWith('Sending verification email to:', 'test@example.com')
    })

    it('should handle back navigation in sign-up flow', async () => {
      const user = userEvent.setup()
      render(<AuthFlowTestComponent initialFlow="signup" />)

      // Navigate to email options
      const passwordButton = screen.getByText('Sign up with Password')
      await user.click(passwordButton)

      await waitFor(() => {
        expect(screen.getByTestId('current-flow')).toHaveTextContent('signup-email-options')
      })

      // Go back
      const backButton = screen.getByRole('button', { name: /back/i })
      await user.click(backButton)

             // Should return to main sign-up
       await waitFor(() => {
         expect(screen.getByTestId('current-flow')).toHaveTextContent('signup-main')
       })
    })
  })

  describe('Error Handling', () => {
    it('should handle form validation errors in sign-up flow', async () => {
      const user = userEvent.setup()
      render(<AuthFlowTestComponent initialFlow="signup" />)

      // Navigate to email options
      const passwordButton = screen.getByText('Sign up with Password')
      await user.click(passwordButton)

      await waitFor(() => {
        expect(screen.getByTestId('current-flow')).toHaveTextContent('signup-email-options')
      })

      // Try to submit without email
      const continueButton = screen.getByRole('button', { name: 'Continue' })
      await user.click(continueButton)

      // Should show validation error
      expect(screen.getByText('Email address is required')).toBeInTheDocument()

      // Should not navigate away
      expect(screen.getByTestId('current-flow')).toHaveTextContent('signup-email-options')
    })
  })

  describe('State Management', () => {
    it('should maintain email state across flow transitions', async () => {
      const user = userEvent.setup()
      render(<AuthFlowTestComponent initialFlow="signup" />)

      // Navigate to email options
      const passwordButton = screen.getByText('Sign up with Password')
      await user.click(passwordButton)

      await waitFor(() => {
        expect(screen.getByTestId('current-flow')).toHaveTextContent('signup-email-options')
      })

      // Enter email
      const emailInput = screen.getByLabelText('Email address')
      await user.type(emailInput, 'persistent@example.com')

      // Navigate back
      const backButton = screen.getByRole('button', { name: /back/i })
      await user.click(backButton)

      // Navigate forward again
      const passwordButtonAgain = screen.getByText('Sign up with Password')
      await user.click(passwordButtonAgain)

      await waitFor(() => {
        expect(screen.getByTestId('current-flow')).toHaveTextContent('signup-email-options')
      })

      // Email should be preserved
      expect(screen.getByTestId('current-email')).toHaveTextContent('persistent@example.com')
      const emailInputAgain = screen.getByLabelText('Email address') as HTMLInputElement
      expect(emailInputAgain.value).toBe('persistent@example.com')
    })
  })
})
