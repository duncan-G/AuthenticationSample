import { render, screen, fireEvent } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { PasswordSignIn } from '../password-sign-in'

describe('PasswordSignIn', () => {
  const mockProps = {
    email: 'test@example.com',
    password: '',
    onPasswordChange: jest.fn(),
    onPasswordSignIn: jest.fn(),
    onPasskeyFlow: jest.fn(),
    onBack: jest.fn(),
    isLoading: false,
  }

  beforeEach(() => {
    jest.clearAllMocks()
  })

  describe('rendering', () => {
    it('should render all essential elements', () => {
      render(<PasswordSignIn {...mockProps} />)

      expect(screen.getByText('Enter password')).toBeInTheDocument()
      expect(screen.getByText('Signing in to test@example.com')).toBeInTheDocument()
      expect(screen.getByLabelText('Password')).toBeInTheDocument()
      expect(screen.getByRole('button', { name: 'Sign In' })).toBeInTheDocument()
      expect(screen.getByRole('button', { name: 'Sign in with Passkey' })).toBeInTheDocument()
      expect(screen.getByRole('button', { name: 'Forgot your password?' })).toBeInTheDocument()
    })

    it('should render back button', () => {
      render(<PasswordSignIn {...mockProps} />)

      // The back button is the first button element (has arrow-left icon)
      const backButton = screen.getAllByRole('button')[0]
      expect(backButton).toBeInTheDocument()
      expect(backButton.querySelector('svg')).toBeInTheDocument()
    })

    it('should render password input with correct attributes', () => {
      render(<PasswordSignIn {...mockProps} />)

      const passwordInput = screen.getByLabelText('Password')
      expect(passwordInput).toHaveAttribute('type', 'password')
      expect(passwordInput).toHaveAttribute('placeholder', 'Enter your password')
      expect(passwordInput).toHaveAttribute('required')
      expect(passwordInput).toHaveFocus()
    })
  })

  describe('password input handling', () => {
    it('should call onPasswordChange when password input changes', async () => {
      const user = userEvent.setup()
      render(<PasswordSignIn {...mockProps} />)

      const passwordInput = screen.getByLabelText('Password')
      await user.type(passwordInput, 'test')

      // Check that onPasswordChange was called - each character triggers onChange
      expect(mockProps.onPasswordChange).toHaveBeenCalled()
      expect(mockProps.onPasswordChange).toHaveBeenCalledTimes(4)
      // Each keystroke calls onChange with the individual character
      expect(mockProps.onPasswordChange).toHaveBeenNthCalledWith(1, 't')
      expect(mockProps.onPasswordChange).toHaveBeenNthCalledWith(2, 'e')
      expect(mockProps.onPasswordChange).toHaveBeenNthCalledWith(3, 's')
      expect(mockProps.onPasswordChange).toHaveBeenNthCalledWith(4, 't')
    })

    it('should display current password value', () => {
      render(<PasswordSignIn {...mockProps} password="mypassword" />)

      const passwordInput = screen.getByLabelText('Password') as HTMLInputElement
      expect(passwordInput.value).toBe('mypassword')
    })

    it('should auto-focus on password input when component mounts', () => {
      render(<PasswordSignIn {...mockProps} />)

      const passwordInput = screen.getByLabelText('Password')
      expect(passwordInput).toHaveFocus()
    })
  })

  describe('form submission', () => {
    it('should call onPasswordSignIn when form is submitted with password', async () => {
      render(<PasswordSignIn {...mockProps} password="password123" />)

      const form = document.querySelector('form')
      expect(form).toBeInTheDocument()
      fireEvent.submit(form!)
      expect(mockProps.onPasswordSignIn).toHaveBeenCalledTimes(1)
    })

    it('should call onPasswordSignIn when Sign In button is clicked', async () => {
      const user = userEvent.setup()
      render(<PasswordSignIn {...mockProps} password="password123" />)

      const signInButton = screen.getByRole('button', { name: 'Sign In' })
      await user.click(signInButton)

      expect(mockProps.onPasswordSignIn).toHaveBeenCalledTimes(1)
    })

    it('should submit form on Enter key press in password field', async () => {
      const user = userEvent.setup()
      render(<PasswordSignIn {...mockProps} password="password123" />)

      const passwordInput = screen.getByLabelText('Password')
      await user.type(passwordInput, '{enter}')

      expect(mockProps.onPasswordSignIn).toHaveBeenCalledTimes(1)
    })

    it('should not submit when password is empty', async () => {
      const user = userEvent.setup()
      render(<PasswordSignIn {...mockProps} password="" />)

      const signInButton = screen.getByRole('button', { name: 'Sign In' })
      await user.click(signInButton)

      expect(mockProps.onPasswordSignIn).not.toHaveBeenCalled()
    })

    it('should not submit when loading', async () => {
      render(<PasswordSignIn {...mockProps} password="password123" isLoading={true} />)

      const form = document.querySelector('form')
      expect(form).toBeInTheDocument()
      fireEvent.submit(form!)
      expect(mockProps.onPasswordSignIn).not.toHaveBeenCalled()
    })
  })

  describe('navigation', () => {
    it('should call onBack when back button is clicked', async () => {
      const user = userEvent.setup()
      render(<PasswordSignIn {...mockProps} />)

      // The back button is the first button element in the component
      const backButton = screen.getAllByRole('button')[0]
      await user.click(backButton)

      expect(mockProps.onBack).toHaveBeenCalledTimes(1)
    })

    it('should call onPasskeyFlow when passkey button is clicked', async () => {
      const user = userEvent.setup()
      render(<PasswordSignIn {...mockProps} />)

      const passkeyButton = screen.getByRole('button', { name: 'Sign in with Passkey' })
      await user.click(passkeyButton)

      expect(mockProps.onPasskeyFlow).toHaveBeenCalledTimes(1)
    })

    it('should handle forgot password button click', async () => {
      const user = userEvent.setup()
      render(<PasswordSignIn {...mockProps} />)

      const forgotButton = screen.getByRole('button', { name: 'Forgot your password?' })
      await user.click(forgotButton)

      // Button should be clickable (no error thrown)
      expect(forgotButton).toBeInTheDocument()
    })
  })

  describe('loading states', () => {
    it('should disable submit button when no password', () => {
      render(<PasswordSignIn {...mockProps} password="" />)

      const submitButton = screen.getByRole('button', { name: 'Sign In' })
      expect(submitButton).toBeDisabled()
    })

    it('should disable submit button when loading', () => {
      render(<PasswordSignIn {...mockProps} password="password123" isLoading={true} />)

      const submitButton = screen.getByRole('button', { name: 'Signing in...' })
      expect(submitButton).toBeDisabled()
    })

    it('should disable passkey button when loading', () => {
      render(<PasswordSignIn {...mockProps} isLoading={true} />)

      const passkeyButton = screen.getByRole('button', { name: 'Sign in with Passkey' })
      expect(passkeyButton).toBeDisabled()
    })

    it('should enable submit button when password exists and not loading', () => {
      render(<PasswordSignIn {...mockProps} password="password123" isLoading={false} />)

      const submitButton = screen.getByRole('button', { name: 'Sign In' })
      expect(submitButton).not.toBeDisabled()
    })
  })

  describe('accessibility', () => {
    it('should have proper form structure', () => {
      render(<PasswordSignIn {...mockProps} />)

      const form = document.querySelector('form')
      expect(form).toBeInTheDocument()
      expect(form).toHaveAttribute('noValidate')
    })

    it('should have proper label association', () => {
      render(<PasswordSignIn {...mockProps} />)

      const passwordInput = screen.getByLabelText('Password')
      expect(passwordInput).toHaveAttribute('id', 'password')
    })

    it('should be keyboard navigable', async () => {
      const user = userEvent.setup()
      render(<PasswordSignIn {...mockProps} password="password123" />)

      // Password input should be focused first
      expect(screen.getByLabelText('Password')).toHaveFocus()

      // Tab to submit button
      await user.tab()
      expect(screen.getByRole('button', { name: 'Sign In' })).toHaveFocus()

      // Tab to passkey button
      await user.tab()
      expect(screen.getByRole('button', { name: 'Sign in with Passkey' })).toHaveFocus()
    })
  })
}) 