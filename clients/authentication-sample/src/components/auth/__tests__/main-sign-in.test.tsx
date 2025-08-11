import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MainSignIn } from '../main-sign-in'

describe('MainSignIn', () => {
  const mockProps = {
    onGoogleSignIn: jest.fn(),
    onAppleSignIn: jest.fn(),
    onEmailSignIn: jest.fn(),
    isLoading: false,
  }

  beforeEach(() => {
    jest.clearAllMocks()
  })

  describe('rendering', () => {
    it('should render all essential elements', () => {
      render(<MainSignIn {...mockProps} />)

      expect(screen.getByText('Welcome')).toBeInTheDocument()
      expect(screen.getByText('Choose your path to continue')).toBeInTheDocument()
      expect(screen.getByText('Continue with Google')).toBeInTheDocument()
      expect(screen.getByText('Continue with Apple')).toBeInTheDocument()
      expect(screen.getByText('Sign in with email')).toBeInTheDocument()
      expect(screen.getByText("Don't have an account?")).toBeInTheDocument()
      expect(screen.getByText('Sign up')).toBeInTheDocument()
    })

    it('should render terms and privacy policy links', () => {
      render(<MainSignIn {...mockProps} />)

      expect(screen.getByText(/By continuing, you agree to our/)).toBeInTheDocument()
      expect(screen.getByRole('button', { name: 'Terms of Service' })).toBeInTheDocument()
      expect(screen.getByRole('button', { name: 'Privacy Policy' })).toBeInTheDocument()
    })

    it('should render sign-up link with correct href', () => {
      render(<MainSignIn {...mockProps} />)

      const signUpLink = screen.getByRole('link', { name: 'Sign up' })
      expect(signUpLink).toHaveAttribute('href', '/sign-up')
    })
  })

  describe('interactions', () => {
    it('should call onGoogleSignIn when Google button is clicked', async () => {
      const user = userEvent.setup()
      render(<MainSignIn {...mockProps} />)

      const googleButton = screen.getByText('Continue with Google')
      await user.click(googleButton)

      expect(mockProps.onGoogleSignIn).toHaveBeenCalledTimes(1)
    })

    it('should call onAppleSignIn when Apple button is clicked', async () => {
      const user = userEvent.setup()
      render(<MainSignIn {...mockProps} />)

      const appleButton = screen.getByText('Continue with Apple')
      await user.click(appleButton)

      expect(mockProps.onAppleSignIn).toHaveBeenCalledTimes(1)
    })

    it('should call onEmailSignIn when Email button is clicked', async () => {
      const user = userEvent.setup()
      render(<MainSignIn {...mockProps} />)

      const emailButton = screen.getByText('Sign in with email')
      await user.click(emailButton)

      expect(mockProps.onEmailSignIn).toHaveBeenCalledTimes(1)
    })

    it('should handle Terms of Service button click', async () => {
      const user = userEvent.setup()
      render(<MainSignIn {...mockProps} />)

      const termsButton = screen.getByRole('button', { name: 'Terms of Service' })
      await user.click(termsButton)

      // Button should be focusable and clickable (no error thrown)
      expect(termsButton).toBeInTheDocument()
    })

    it('should handle Privacy Policy button click', async () => {
      const user = userEvent.setup()
      render(<MainSignIn {...mockProps} />)

      const privacyButton = screen.getByRole('button', { name: 'Privacy Policy' })
      await user.click(privacyButton)

      // Button should be focusable and clickable (no error thrown)
      expect(privacyButton).toBeInTheDocument()
    })
  })

  describe('loading states', () => {
    it('should disable all buttons when loading', () => {
      render(<MainSignIn {...mockProps} isLoading={true} />)

      const googleButton = screen.getByText('Continue with Google').closest('button')
      const appleButton = screen.getByText('Continue with Apple').closest('button')
      const emailButton = screen.getByText('Sign in with email').closest('button')

      expect(googleButton).toBeDisabled()
      expect(appleButton).toBeDisabled()
      expect(emailButton).toBeDisabled()
    })

    it('should enable all buttons when not loading', () => {
      render(<MainSignIn {...mockProps} isLoading={false} />)

      const googleButton = screen.getByText('Continue with Google').closest('button')
      const appleButton = screen.getByText('Continue with Apple').closest('button')
      const emailButton = screen.getByText('Sign in with email').closest('button')

      expect(googleButton).not.toBeDisabled()
      expect(appleButton).not.toBeDisabled()
      expect(emailButton).not.toBeDisabled()
    })

    it('should not call handlers when buttons are disabled due to loading', async () => {
      const user = userEvent.setup()
      render(<MainSignIn {...mockProps} isLoading={true} />)

      const googleButton = screen.getByText('Continue with Google')
      const emailButton = screen.getByText('Sign in with email')

      await user.click(googleButton)
      await user.click(emailButton)

      expect(mockProps.onGoogleSignIn).not.toHaveBeenCalled()
      expect(mockProps.onEmailSignIn).not.toHaveBeenCalled()
    })
  })

  describe('accessibility', () => {
    it('should have proper ARIA labels and roles', () => {
      render(<MainSignIn {...mockProps} />)

      // Check that buttons have proper roles
      expect(screen.getByRole('button', { name: /Continue with Google/i })).toBeInTheDocument()
      expect(screen.getByRole('button', { name: /Continue with Apple/i })).toBeInTheDocument()
      expect(screen.getByRole('button', { name: /Sign in with email/i })).toBeInTheDocument()

      // Check link has proper role
      expect(screen.getByRole('link', { name: 'Sign up' })).toBeInTheDocument()
    })

    it('should be keyboard navigable', async () => {
      const user = userEvent.setup()
      render(<MainSignIn {...mockProps} />)

      // Tab through interactive elements
      await user.tab()
      expect(screen.getByText('Continue with Google').closest('button')).toHaveFocus()

      await user.tab()
      expect(screen.getByText('Continue with Apple').closest('button')).toHaveFocus()

      await user.tab()
      expect(screen.getByText('Sign in with email').closest('button')).toHaveFocus()
    })

    it('should trigger handlers on Enter key press', async () => {
      const user = userEvent.setup()
      render(<MainSignIn {...mockProps} />)

      const emailButton = screen.getByText('Sign in with email').closest('button')
      if (emailButton) {
        emailButton.focus()
        await user.keyboard('{Enter}')
      }

      expect(mockProps.onEmailSignIn).toHaveBeenCalledTimes(1)
    })
  })
}) 