import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MainSignUp } from '../main-sign-up'

describe('MainSignUp', () => {
  const mockProps = {
    onGoogleSignUp: jest.fn(),
    onAppleSignUp: jest.fn(),
    onPasswordSignUp: jest.fn(),
    onPasswordlessSignUp: jest.fn(),
    isLoading: false,
  }

  beforeEach(() => {
    jest.clearAllMocks()
  })

  describe('rendering', () => {
    it('should render all essential elements', () => {
      render(<MainSignUp {...mockProps} />)

      expect(screen.getByText('Join Us')).toBeInTheDocument()
      expect(screen.getByText('Create your account to get started')).toBeInTheDocument()
      expect(screen.getByText('Sign up with Google')).toBeInTheDocument()
      expect(screen.getByText('Sign up with Apple')).toBeInTheDocument()
      expect(screen.getByText('Sign up with Password')).toBeInTheDocument()
      expect(screen.getByText('Sign up Passwordless')).toBeInTheDocument()
      expect(screen.getByText('Already have an account?')).toBeInTheDocument()
      expect(screen.getByText('Sign in')).toBeInTheDocument()
    })

    it('should render terms and privacy policy links', () => {
      render(<MainSignUp {...mockProps} />)

      expect(screen.getByText(/By creating an account, you agree to our/)).toBeInTheDocument()
      expect(screen.getByRole('button', { name: 'Terms of Service' })).toBeInTheDocument()
      expect(screen.getByRole('button', { name: 'Privacy Policy' })).toBeInTheDocument()
    })

    it('should render sign-in link with correct href', () => {
      render(<MainSignUp {...mockProps} />)

      const signInLink = screen.getByRole('link', { name: 'Sign in' })
      expect(signInLink).toHaveAttribute('href', '/sign-in')
    })
  })

  describe('interactions', () => {
    it('should call onGoogleSignUp when Google button is clicked', async () => {
      const user = userEvent.setup()
      render(<MainSignUp {...mockProps} />)

      const googleButton = screen.getByText('Sign up with Google')
      await user.click(googleButton)

      expect(mockProps.onGoogleSignUp).toHaveBeenCalledTimes(1)
    })

    it('should call onAppleSignUp when Apple button is clicked', async () => {
      const user = userEvent.setup()
      render(<MainSignUp {...mockProps} />)

      const appleButton = screen.getByText('Sign up with Apple')
      await user.click(appleButton)

      expect(mockProps.onAppleSignUp).toHaveBeenCalledTimes(1)
    })

    it('should call onPasswordSignUp when Password button is clicked', async () => {
      const user = userEvent.setup()
      render(<MainSignUp {...mockProps} />)

      const passwordButton = screen.getByText('Sign up with Password')
      await user.click(passwordButton)

      expect(mockProps.onPasswordSignUp).toHaveBeenCalledTimes(1)
    })

    it('should call onPasswordlessSignUp when Passwordless button is clicked', async () => {
      const user = userEvent.setup()
      render(<MainSignUp {...mockProps} />)

      const passwordlessButton = screen.getByText('Sign up Passwordless')
      await user.click(passwordlessButton)

      expect(mockProps.onPasswordlessSignUp).toHaveBeenCalledTimes(1)
    })

    it('should handle Terms of Service button click', async () => {
      const user = userEvent.setup()
      render(<MainSignUp {...mockProps} />)

      const termsButton = screen.getByRole('button', { name: 'Terms of Service' })
      await user.click(termsButton)

      // Button should be focusable and clickable (no error thrown)
      expect(termsButton).toBeInTheDocument()
    })

    it('should handle Privacy Policy button click', async () => {
      const user = userEvent.setup()
      render(<MainSignUp {...mockProps} />)

      const privacyButton = screen.getByRole('button', { name: 'Privacy Policy' })
      await user.click(privacyButton)

      // Button should be focusable and clickable (no error thrown)
      expect(privacyButton).toBeInTheDocument()
    })
  })

  describe('loading states', () => {
    it('should disable all buttons when loading', () => {
      render(<MainSignUp {...mockProps} isLoading={true} />)

      const googleButton = screen.getByText('Sign up with Google').closest('button')
      const appleButton = screen.getByText('Sign up with Apple').closest('button')
      const passwordButton = screen.getByText('Sign up with Password').closest('button')
      const passwordlessButton = screen.getByText('Sign up Passwordless').closest('button')

      expect(googleButton).toBeDisabled()
      expect(appleButton).toBeDisabled()
      expect(passwordButton).toBeDisabled()
      expect(passwordlessButton).toBeDisabled()
    })

    it('should enable all buttons when not loading', () => {
      render(<MainSignUp {...mockProps} isLoading={false} />)

      const googleButton = screen.getByText('Sign up with Google').closest('button')
      const appleButton = screen.getByText('Sign up with Apple').closest('button')
      const passwordButton = screen.getByText('Sign up with Password').closest('button')
      const passwordlessButton = screen.getByText('Sign up Passwordless').closest('button')

      expect(googleButton).not.toBeDisabled()
      expect(appleButton).not.toBeDisabled()
      expect(passwordButton).not.toBeDisabled()
      expect(passwordlessButton).not.toBeDisabled()
    })

    it('should not call handlers when buttons are disabled due to loading', async () => {
      const user = userEvent.setup()
      render(<MainSignUp {...mockProps} isLoading={true} />)

      const googleButton = screen.getByText('Sign up with Google')
      const passwordButton = screen.getByText('Sign up with Password')

      await user.click(googleButton)
      await user.click(passwordButton)

      expect(mockProps.onGoogleSignUp).not.toHaveBeenCalled()
      expect(mockProps.onPasswordSignUp).not.toHaveBeenCalled()
    })
  })

  describe('accessibility', () => {
    it('should have proper ARIA labels and roles', () => {
      render(<MainSignUp {...mockProps} />)

      // Check that buttons have proper roles
      expect(screen.getByRole('button', { name: /Sign up with Google/i })).toBeInTheDocument()
      expect(screen.getByRole('button', { name: /Sign up with Apple/i })).toBeInTheDocument()
      expect(screen.getByRole('button', { name: /Sign up with Password/i })).toBeInTheDocument()
      expect(screen.getByRole('button', { name: /Sign up Passwordless/i })).toBeInTheDocument()

      // Check link has proper role
      expect(screen.getByRole('link', { name: 'Sign in' })).toBeInTheDocument()
    })

    it('should be keyboard navigable', async () => {
      const user = userEvent.setup()
      render(<MainSignUp {...mockProps} />)

      // Tab through interactive elements
      await user.tab()
      expect(screen.getByText('Sign up with Google').closest('button')).toHaveFocus()

      await user.tab()
      expect(screen.getByText('Sign up with Apple').closest('button')).toHaveFocus()

      await user.tab()
      expect(screen.getByText('Sign up with Password').closest('button')).toHaveFocus()

      await user.tab()
      expect(screen.getByText('Sign up Passwordless').closest('button')).toHaveFocus()
    })

    it('should trigger handlers on Enter key press', async () => {
      const user = userEvent.setup()
      render(<MainSignUp {...mockProps} />)

      const passwordButton = screen.getByText('Sign up with Password').closest('button')
      if (passwordButton) {
        passwordButton.focus()
        await user.keyboard('{Enter}')
      }

      expect(mockProps.onPasswordSignUp).toHaveBeenCalledTimes(1)
    })
  })
}) 