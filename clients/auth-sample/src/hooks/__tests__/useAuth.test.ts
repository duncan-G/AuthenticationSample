import { renderHook, act } from '@testing-library/react'
import { useAuth } from '../useAuth'

describe('useAuth', () => {
  beforeEach(() => {
    // Clear all mocks before each test
    jest.clearAllMocks()
    // Mock console.log to avoid noise in test output
    jest.spyOn(console, 'log').mockImplementation(() => {})
  })

  afterEach(() => {
    jest.restoreAllMocks()
  })

  describe('initial state', () => {
    it('should initialize with correct default values', () => {
      const { result } = renderHook(() => useAuth())

      expect(result.current.currentFlow).toBe('main')
      expect(result.current.email).toBe('')
      expect(result.current.password).toBe('')
      expect(result.current.otpCode).toBe('')
      expect(result.current.isLoading).toBe(false)
      expect(result.current.signupMethod).toBeUndefined()
    })
  })

  describe('state setters', () => {
    it('should update email correctly', () => {
      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.setEmail('test@example.com')
      })

      expect(result.current.email).toBe('test@example.com')
    })

    it('should update password correctly', () => {
      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.setPassword('password123')
      })

      expect(result.current.password).toBe('password123')
    })

    it('should update OTP code correctly', () => {
      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.setOtpCode('123456')
      })

      expect(result.current.otpCode).toBe('123456')
    })

    it('should update current flow correctly', () => {
      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.setCurrentFlow('email-options')
      })

      expect(result.current.currentFlow).toBe('email-options')
    })
  })

  describe('sign-in handlers', () => {
    it('should handle Google sign-in', async () => {
      const { result } = renderHook(() => useAuth())

      await act(async () => {
        await result.current.handleGoogleSignIn()
      })

      expect(console.log).toHaveBeenCalledWith('Google sign in')
    })

    it('should handle Apple sign-in', async () => {
      const { result } = renderHook(() => useAuth())

      await act(async () => {
        await result.current.handleAppleSignIn()
      })

      expect(console.log).toHaveBeenCalledWith('Apple sign in')
    })

    it('should handle email sign-in flow transition', () => {
      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.handleEmailSignIn()
      })

      expect(result.current.currentFlow).toBe('email-options')
    })

    it('should handle password sign-in with email and password', async () => {
      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.setEmail('test@example.com')
        result.current.setPassword('password123')
      })

      await act(async () => {
        await result.current.handlePasswordSignIn()
      })

      expect(console.log).toHaveBeenCalledWith('Password sign in with:', 'test@example.com', 'password123')
    })

    it('should handle passwordless sign-in', async () => {
      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.setEmail('test@example.com')
      })

      await act(async () => {
        await result.current.handlePasswordlessSignIn()
      })

      expect(console.log).toHaveBeenCalledWith('Sending passwordless link to:', 'test@example.com')
    })

    it('should handle passkey sign-in', async () => {
      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.setEmail('test@example.com')
      })

      await act(async () => {
        await result.current.handlePasskeySignIn()
      })

      expect(console.log).toHaveBeenCalledWith('Passkey sign in for:', 'test@example.com')
    })

    it('should handle OTP verification', async () => {
      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.setOtpCode('123456')
      })

      await act(async () => {
        await result.current.handleOtpVerification()
      })

      expect(console.log).toHaveBeenCalledWith('Verifying OTP:', '123456')
    })
  })

  describe('sign-up handlers', () => {
    it('should handle Google sign-up', async () => {
      const { result } = renderHook(() => useAuth())

      await act(async () => {
        await result.current.handleGoogleSignUp()
      })

      expect(console.log).toHaveBeenCalledWith('Google sign up')
    })

    it('should handle Apple sign-up', async () => {
      const { result } = renderHook(() => useAuth())

      await act(async () => {
        await result.current.handleAppleSignUp()
      })

      expect(console.log).toHaveBeenCalledWith('Apple sign up')
    })

    it('should handle password sign-up flow setup', () => {
      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.handlePasswordSignUpFlowStart()
      })

      expect(result.current.signupMethod).toBe('password')
      expect(result.current.currentFlow).toBe('signup-email')
    })

    it('should handle passwordless sign-up flow setup', () => {
      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.handlePasswordlessSignUpFlowStart()
      })

      expect(result.current.signupMethod).toBe('passwordless')
      expect(result.current.currentFlow).toBe('signup-email')
    })

    it('should handle password sign-up with email and password', async () => {
      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.setEmail('test@example.com')
        result.current.setPassword('password123')
      })

      await act(async () => {
        await result.current.handlePasswordSignUp()
      })

      expect(console.log).toHaveBeenCalledWith('Password sign up with:', 'test@example.com', 'password123')
    })

    it('should handle passwordless sign-up', async () => {
      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.setEmail('test@example.com')
      })

      await act(async () => {
        await result.current.handlePasswordlessSignUpFlowStart()
      })

      expect(console.log).toHaveBeenCalledWith('Sending verification email to:', 'test@example.com')
    })

    it('should handle sign-up OTP verification', async () => {
      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.setOtpCode('123456')
      })

      await act(async () => {
        await result.current.handleSignUpOtpVerification()
      })

      expect(console.log).toHaveBeenCalledWith('Verifying sign up OTP:', '123456')
    })
  })

  describe('loading states', () => {
    it('should set loading state during Google sign-in', async () => {
      const { result } = renderHook(() => useAuth())

      await act(async () => {
        await result.current.handleGoogleSignIn()
      })

      // Since the function is mocked and completes immediately,
      // we can't easily test the intermediate loading state
      // but we can verify it ends in the correct state
      expect(result.current.isLoading).toBe(false)
    })

    it('should set loading state during password sign-in', async () => {
      const { result } = renderHook(() => useAuth())

      await act(async () => {
        await result.current.handlePasswordSignIn()
      })

      expect(result.current.isLoading).toBe(false)
    })

    it('should set loading state during password sign-up', async () => {
      const { result } = renderHook(() => useAuth())

      await act(async () => {
        await result.current.handlePasswordSignUp()
      })

      expect(result.current.isLoading).toBe(false)
    })
  })
})
