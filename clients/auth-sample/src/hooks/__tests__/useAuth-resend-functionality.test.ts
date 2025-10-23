import { renderHook, act } from '@testing-library/react'
import { useAuth } from '../useAuth'
import { ErrorCodes } from '@/lib/services/error-codes'

// Mock the gRPC client
const mockResendVerificationCodeAsync = jest.fn()

// Mock console.error to avoid noise in tests
const mockConsoleError = jest.spyOn(console, 'error').mockImplementation(() => { })

// Override the existing mock from jest.setup.js for this specific test
jest.mock('@/lib/services/grpc-clients', () => ({
  createSignUpServiceClient: () => ({
    resendVerificationCodeAsync: mockResendVerificationCodeAsync,
    initiateSignUpAsync: jest.fn(() => Promise.resolve({
      getNextStep: () => 1 // SignUpStep.VERIFICATION_REQUIRED
    })),
    verifyAndSignInAsync: jest.fn(() => Promise.resolve({
      getNextStep: () => 2 // SignUpStep.SIGN_IN_REQUIRED
    }))
  })
}))

describe('useAuth - Resend Functionality', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    mockConsoleError.mockClear()
    mockResendVerificationCodeAsync.mockClear()
  })

  afterAll(() => {
    mockConsoleError.mockRestore()
  })

  describe('handleResendVerificationCode', () => {
    it('should successfully resend verification code', async () => {
      mockResendVerificationCodeAsync.mockResolvedValue({})

      const { result } = renderHook(() => useAuth())

      // Set email for the test
      act(() => {
        result.current.setEmail('test@example.com')
      })

      // Call resend verification code
      await act(async () => {
        await result.current.handleResendVerificationCode()
      })

      // Verify gRPC call was made with correct parameters
      expect(mockResendVerificationCodeAsync).toHaveBeenCalledTimes(1)
      const request = mockResendVerificationCodeAsync.mock.calls[0][0]
      expect(request.getEmailAddress()).toBe('test@example.com')

      // Verify state is correct after successful resend
      expect(result.current.isRateLimited).toBe(false)
      expect(result.current.rateLimitRetryAfter).toBeUndefined()
      expect(result.current.errorMessage).toBeUndefined()
      expect(result.current.isResendLoading).toBe(false)
    })

    it('should clear previous rate limit state before new resend attempt', async () => {
      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.setEmail('test@example.com')
      })

      // First, simulate a rate limit error
      const rateLimitError = {
        code: ErrorCodes.ResourceExhausted,
        message: 'Rate limit exceeded',
        metadata: { 'error-code': ErrorCodes.ResourceExhausted }
      }

      mockResendVerificationCodeAsync.mockRejectedValueOnce(rateLimitError)

      await act(async () => {
        await result.current.handleResendVerificationCode()
      })

      expect(result.current.isRateLimited).toBe(true)

      // Now simulate a successful resend
      mockResendVerificationCodeAsync.mockResolvedValueOnce({})

      await act(async () => {
        await result.current.handleResendVerificationCode()
      })

      // Verify rate limit state was cleared
      expect(result.current.isRateLimited).toBe(false)
      expect(result.current.rateLimitRetryAfter).toBeUndefined()
      expect(result.current.errorMessage).toBeUndefined()
    })

    it('should handle rate limit exceeded error with retry time extraction', async () => {
      const rateLimitError = {
        code: ErrorCodes.ResourceExhausted,
        message: 'Rate limit exceeded. Try again in 45 minutes.',
        metadata: { 'error-code': ErrorCodes.ResourceExhausted }
      }

      mockResendVerificationCodeAsync.mockRejectedValue(rateLimitError)

      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.setEmail('test@example.com')
      })

      await act(async () => {
        await result.current.handleResendVerificationCode()
      })

      // Verify rate limiting state
      expect(result.current.isRateLimited).toBe(true)
      expect(result.current.rateLimitRetryAfter).toBe(45)
      expect(result.current.errorMessage).toBe(
        "You've reached the maximum number of resend attempts (5 per hour). Please wait before trying again."
      )
    })

    it('should handle rate limit exceeded error without retry time', async () => {
      const rateLimitError = {
        code: ErrorCodes.ResourceExhausted,
        message: 'Rate limit exceeded',
        metadata: { 'error-code': ErrorCodes.ResourceExhausted }
      }

      mockResendVerificationCodeAsync.mockRejectedValue(rateLimitError)

      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.setEmail('test@example.com')
      })

      await act(async () => {
        await result.current.handleResendVerificationCode()
      })

      // Verify rate limiting state
      expect(result.current.isRateLimited).toBe(true)
      expect(result.current.rateLimitRetryAfter).toBeUndefined()
      expect(result.current.errorMessage).toBe(
        "You've reached the maximum number of resend attempts (5 per hour). Please wait before trying again."
      )
    })

    it('should handle delivery failed error', async () => {
      const deliveryError = {
        code: ErrorCodes.VerificationCodeDeliveryFailed,
        message: 'Email delivery failed',
        metadata: { 'error-code': ErrorCodes.VerificationCodeDeliveryFailed }
      }

      mockResendVerificationCodeAsync.mockRejectedValue(deliveryError)

      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.setEmail('test@example.com')
      })

      await act(async () => {
        await result.current.handleResendVerificationCode()
      })

      // Verify error handling
      expect(result.current.isRateLimited).toBe(false)
      expect(result.current.rateLimitRetryAfter).toBeUndefined()
      expect(result.current.errorMessage).toBe(
        "We couldn't send a verification code. Please try again later."
      )
    })

    it('should handle unexpected errors', async () => {
      const unexpectedError = {
        code: ErrorCodes.Unexpected,
        message: 'Something went wrong',
        metadata: { 'error-code': ErrorCodes.Unexpected }
      }

      mockResendVerificationCodeAsync.mockRejectedValue(unexpectedError)

      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.setEmail('test@example.com')
      })

      await act(async () => {
        await result.current.handleResendVerificationCode()
      })

      // Verify error handling
      expect(result.current.isRateLimited).toBe(false)
      expect(result.current.rateLimitRetryAfter).toBeUndefined()
      expect(result.current.errorMessage).toBe(
        "Something went wrong. Please try again in a moment."
      )
    })

    it('should handle network errors gracefully', async () => {
      const networkError = new Error('Network error')
      mockResendVerificationCodeAsync.mockRejectedValue(networkError)

      const { result } = renderHook(() => useAuth())

      act(() => {
        result.current.setEmail('test@example.com')
      })

      await act(async () => {
        await result.current.handleResendVerificationCode()
      })

      // Verify error handling for non-gRPC errors
      expect(result.current.isRateLimited).toBe(false)
      expect(result.current.rateLimitRetryAfter).toBeUndefined()
      expect(result.current.errorMessage).toBe(
        "Something went wrong. Please try again in a moment."
      )
    })
  })

  describe('resend state management', () => {
    it('should initialize with correct resend-related state', () => {
      const { result } = renderHook(() => useAuth())

      expect(result.current.isResendLoading).toBe(false)
      expect(result.current.isRateLimited).toBe(false)
      expect(result.current.rateLimitRetryAfter).toBeUndefined()
    })

    it('should maintain signup state consistency during resend operations', async () => {
      mockResendVerificationCodeAsync.mockResolvedValue({})

      const { result } = renderHook(() => useAuth())

      // Set up signup state
      act(() => {
        result.current.setEmail('test@example.com')
        result.current.setPassword('password123')
        result.current.setCurrentFlow('signup-verification')
      })

      const initialEmail = result.current.email
      const initialPassword = result.current.password
      const initialFlow = result.current.currentFlow

      await act(async () => {
        await result.current.handleResendVerificationCode()
      })

      // Verify signup state is preserved
      expect(result.current.email).toBe(initialEmail)
      expect(result.current.password).toBe(initialPassword)
      expect(result.current.currentFlow).toBe(initialFlow)
    })
  })
})