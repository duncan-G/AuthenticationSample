import { renderHook, act } from '@testing-library/react'
import { useAuth } from '../useAuth'
import { ErrorCodes } from '@/lib/services/error-codes'

// Mock the gRPC client
const mockResendVerificationCodeAsync = jest.fn()
jest.mock('@/lib/services/grpc-clients', () => ({
  createSignUpServiceClient: () => ({
    resendVerificationCodeAsync: mockResendVerificationCodeAsync
  })
}))

// Mock the workflow system
jest.mock('@/lib/workflows', () => ({
  startWorkflow: () => ({
    startStep: () => ({
      run: (fn: () => Promise<unknown>) => fn(),
      fail: jest.fn(),
      succeed: jest.fn()
    }),
    succeed: jest.fn()
  })
}))

// Mock OIDC
jest.mock('react-oidc-context', () => ({
  useAuth: () => ({
    signinRedirect: jest.fn()
  })
}))

// Mock console.error to avoid noise in tests
const mockConsoleError = jest.spyOn(console, 'error').mockImplementation(() => { })

describe('useAuth - Rate Limiting', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    mockConsoleError.mockClear()
    mockResendVerificationCodeAsync.mockClear()
  })

  afterAll(() => {
    mockConsoleError.mockRestore()
  })

  it('should handle successful resend verification code', async () => {
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

    expect(result.current.isRateLimited).toBe(false)
    expect(result.current.rateLimitRetryAfter).toBeUndefined()
    expect(result.current.errorMessage).toBeUndefined()
  })

  it('should handle rate limit exceeded error', async () => {
    const rateLimitError = {
      code: ErrorCodes.ResourceExhausted,
      message: 'Rate limit exceeded',
      metadata: { 'error-code': ErrorCodes.ResourceExhausted }
    }

    mockResendVerificationCodeAsync.mockRejectedValue(rateLimitError)

    const { result } = renderHook(() => useAuth())

    // Set email for the test
    act(() => {
      result.current.setEmail('test@example.com')
    })

    // Call resend verification code
    await act(async () => {
      await result.current.handleResendVerificationCode()
    })

    expect(result.current.isRateLimited).toBe(true)
    expect(result.current.rateLimitRetryAfter).toBeUndefined()
    expect(result.current.errorMessage).toBe(
      "You've reached the maximum number of resend attempts (5 per hour). Please wait before trying again."
    )
  })

  it('should extract retry-after minutes from server message', async () => {
    const rateLimitError = {
      code: ErrorCodes.ResourceExhausted,
      message: 'Rate limit exceeded. Try again in 30 minutes.',
      metadata: { 'error-code': ErrorCodes.ResourceExhausted }
    }

    mockResendVerificationCodeAsync.mockRejectedValue(rateLimitError)

    const { result } = renderHook(() => useAuth())

    // Set email for the test
    act(() => {
      result.current.setEmail('test@example.com')
    })

    // Call resend verification code
    await act(async () => {
      await result.current.handleResendVerificationCode()
    })

    expect(result.current.isRateLimited).toBe(true)
    expect(result.current.rateLimitRetryAfter).toBe(30)
    expect(result.current.errorMessage).toBe(
      "You've reached the maximum number of resend attempts (5 per hour). Please wait 30 minutes before trying again."
    )
  })

  it('should clear rate limit state before new resend attempt', async () => {
    const { result } = renderHook(() => useAuth())

    // Set email for the test
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

    expect(result.current.isRateLimited).toBe(false)
    expect(result.current.rateLimitRetryAfter).toBeUndefined()
    expect(result.current.errorMessage).toBeUndefined()
  })

  it('should handle delivery failed error without rate limiting', async () => {
    const deliveryError = {
      code: ErrorCodes.VerificationCodeDeliveryFailed,
      message: 'Email delivery failed',
      metadata: { 'error-code': ErrorCodes.VerificationCodeDeliveryFailed }
    }

    mockResendVerificationCodeAsync.mockRejectedValue(deliveryError)

    const { result } = renderHook(() => useAuth())

    // Set email for the test
    act(() => {
      result.current.setEmail('test@example.com')
    })

    // Call resend verification code
    await act(async () => {
      await result.current.handleResendVerificationCode()
    })

    expect(result.current.isRateLimited).toBe(false)
    expect(result.current.rateLimitRetryAfter).toBeUndefined()
    expect(result.current.errorMessage).toBe(
      "We couldn't send a verification code. Please try again later."
    )
  })

  it('should handle unexpected errors without rate limiting', async () => {
    const unexpectedError = {
      code: ErrorCodes.Unexpected,
      message: 'Something went wrong',
      metadata: { 'error-code': ErrorCodes.Unexpected }
    }

    mockResendVerificationCodeAsync.mockRejectedValue(unexpectedError)

    const { result } = renderHook(() => useAuth())

    // Set email for the test
    act(() => {
      result.current.setEmail('test@example.com')
    })

    // Call resend verification code
    await act(async () => {
      await result.current.handleResendVerificationCode()
    })

    expect(result.current.isRateLimited).toBe(false)
    expect(result.current.rateLimitRetryAfter).toBeUndefined()
    expect(result.current.errorMessage).toBe(
      "Something went wrong. Please try again in a moment."
    )
  })
})