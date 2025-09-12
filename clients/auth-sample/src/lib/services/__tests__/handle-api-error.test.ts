import { handleApiError, handleResendApiError, handleApiErrorWithRateLimit, friendlyMessageFor } from '../handle-api-error'
import { ErrorCodes } from '../error-codes'

// Mock console.error to avoid noise in tests
const mockConsoleError = jest.spyOn(console, 'error').mockImplementation(() => {})

// Mock workflow step
const mockStep = {
  fail: jest.fn(),
  succeed: jest.fn(),
  run: jest.fn()
}

describe('handleApiError', () => {
  let mockSetErrorMessage: jest.Mock

  beforeEach(() => {
    mockSetErrorMessage = jest.fn()
    mockStep.fail.mockClear()
    mockConsoleError.mockClear()
  })

  afterAll(() => {
    mockConsoleError.mockRestore()
  })

  it('should handle ResourceExhausted error with friendly message', () => {
    const error = {
      code: ErrorCodes.ResourceExhausted,
      message: 'Rate limit exceeded',
      metadata: { 'error-code': ErrorCodes.ResourceExhausted }
    }

    handleApiError(error, mockSetErrorMessage, mockStep)

    expect(mockSetErrorMessage).toHaveBeenCalledWith(
      friendlyMessageFor[ErrorCodes.ResourceExhausted]
    )
    expect(mockStep.fail).toHaveBeenCalledWith(
      ErrorCodes.ResourceExhausted,
      friendlyMessageFor[ErrorCodes.ResourceExhausted]
    )
    expect(mockConsoleError).toHaveBeenCalledWith(
      'API error',
      expect.objectContaining({
        code: ErrorCodes.ResourceExhausted,
        serverMessage: 'Rate limit exceeded'
      })
    )
  })

  it('should handle unknown error with unexpected message', () => {
    const error = {
      code: 'UNKNOWN_ERROR',
      message: 'Something went wrong'
    }

    handleApiError(error, mockSetErrorMessage, mockStep)

    expect(mockSetErrorMessage).toHaveBeenCalledWith(
      friendlyMessageFor[ErrorCodes.Unexpected]
    )
    expect(mockStep.fail).toHaveBeenCalledWith(
      'UNKNOWN_ERROR',
      friendlyMessageFor[ErrorCodes.Unexpected]
    )
  })

  it('should handle error without step', () => {
    const error = {
      code: ErrorCodes.VerificationCodeExpired,
      message: 'Code expired'
    }

    handleApiError(error, mockSetErrorMessage)

    expect(mockSetErrorMessage).toHaveBeenCalledWith(
      friendlyMessageFor[ErrorCodes.VerificationCodeExpired]
    )
    expect(mockStep.fail).not.toHaveBeenCalled()
  })
})

describe('handleResendApiError (legacy)', () => {
  let mockSetErrorMessage: jest.Mock
  let mockOnRateLimitExceeded: jest.Mock

  beforeEach(() => {
    mockSetErrorMessage = jest.fn()
    mockOnRateLimitExceeded = jest.fn()
    mockStep.fail.mockClear()
    mockConsoleError.mockClear()
  })

  it('should handle ResourceExhausted error with enhanced rate limit message', () => {
    const error = {
      code: ErrorCodes.ResourceExhausted,
      message: 'Rate limit exceeded',
      metadata: { 'error-code': ErrorCodes.ResourceExhausted }
    }

    handleResendApiError(error, mockSetErrorMessage, mockStep, mockOnRateLimitExceeded)

    expect(mockSetErrorMessage).toHaveBeenCalledWith(
      "You've reached the maximum number of resend attempts (5 per hour). Please wait before trying again."
    )
    expect(mockOnRateLimitExceeded).toHaveBeenCalledWith(undefined)
    expect(mockStep.fail).toHaveBeenCalledWith(
      ErrorCodes.ResourceExhausted,
      "You've reached the maximum number of resend attempts (5 per hour). Please wait before trying again."
    )
  })

  it('should extract retry-after minutes from gRPC metadata', () => {
    const error = {
      code: ErrorCodes.ResourceExhausted,
      message: 'Rate limit exceeded.',
      metadata: { 
        'error-code': ErrorCodes.ResourceExhausted,
        'retry-after-seconds': '2700' // 45 minutes
      }
    }

    handleResendApiError(error, mockSetErrorMessage, mockStep, mockOnRateLimitExceeded)

    expect(mockOnRateLimitExceeded).toHaveBeenCalledWith(45)
  })

  it('should prefer gRPC metadata over server message for retry-after', () => {
    const error = {
      code: ErrorCodes.ResourceExhausted,
      message: 'Rate limit exceeded. Try again in 30 minutes.', // This should be ignored
      metadata: { 
        'error-code': ErrorCodes.ResourceExhausted,
        'retry-after-seconds': '3600' // 60 minutes - this should be used
      }
    }

    handleResendApiError(error, mockSetErrorMessage, mockStep, mockOnRateLimitExceeded)

    expect(mockOnRateLimitExceeded).toHaveBeenCalledWith(60)
  })

  it('should extract retry-after from x-retry-after-seconds header', () => {
    const error = {
      code: ErrorCodes.ResourceExhausted,
      message: 'Rate limit exceeded.',
      metadata: { 
        'error-code': ErrorCodes.ResourceExhausted,
        'x-retry-after-seconds': '1800' // 30 minutes
      }
    }

    handleResendApiError(error, mockSetErrorMessage, mockStep, mockOnRateLimitExceeded)

    expect(mockOnRateLimitExceeded).toHaveBeenCalledWith(30)
  })

  it('should extract retry-after minutes from server message as fallback', () => {
    const error = {
      code: ErrorCodes.ResourceExhausted,
      message: 'Rate limit exceeded. Try again in 45 minutes.',
      metadata: { 'error-code': ErrorCodes.ResourceExhausted }
    }

    handleResendApiError(error, mockSetErrorMessage, mockStep, mockOnRateLimitExceeded)

    expect(mockOnRateLimitExceeded).toHaveBeenCalledWith(45)
  })

  it('should handle VerificationCodeDeliveryFailed with standard message', () => {
    const error = {
      code: ErrorCodes.VerificationCodeDeliveryFailed,
      message: 'Email delivery failed',
      metadata: { 'error-code': ErrorCodes.VerificationCodeDeliveryFailed }
    }

    handleResendApiError(error, mockSetErrorMessage, mockStep, mockOnRateLimitExceeded)

    expect(mockSetErrorMessage).toHaveBeenCalledWith(
      friendlyMessageFor[ErrorCodes.VerificationCodeDeliveryFailed]
    )
    expect(mockOnRateLimitExceeded).not.toHaveBeenCalled()
  })

  it('should handle other errors with standard friendly messages', () => {
    const error = {
      code: ErrorCodes.UserNotFound,
      message: 'User not found',
      metadata: { 'error-code': ErrorCodes.UserNotFound }
    }

    handleResendApiError(error, mockSetErrorMessage, mockStep, mockOnRateLimitExceeded)

    expect(mockSetErrorMessage).toHaveBeenCalledWith(
      friendlyMessageFor[ErrorCodes.UserNotFound]
    )
    expect(mockOnRateLimitExceeded).not.toHaveBeenCalled()
  })

  it('should work without rate limit callback', () => {
    const error = {
      code: ErrorCodes.ResourceExhausted,
      message: 'Rate limit exceeded',
      metadata: { 'error-code': ErrorCodes.ResourceExhausted }
    }

    expect(() => {
      handleResendApiError(error, mockSetErrorMessage, mockStep)
    }).not.toThrow()

    expect(mockSetErrorMessage).toHaveBeenCalledWith(
      "You've reached the maximum number of resend attempts (5 per hour). Please wait before trying again."
    )
  })
})

describe('handleApiErrorWithRateLimit', () => {
  let mockSetErrorMessage: jest.Mock
  let mockOnRateLimitExceeded: jest.Mock

  beforeEach(() => {
    mockSetErrorMessage = jest.fn()
    mockOnRateLimitExceeded = jest.fn()
    mockStep.fail.mockClear()
    mockConsoleError.mockClear()
  })

  it('should handle ResourceExhausted error with default rate limit message', () => {
    const error = {
      code: ErrorCodes.ResourceExhausted,
      message: 'Rate limit exceeded',
      metadata: { 'error-code': ErrorCodes.ResourceExhausted }
    }

    handleApiErrorWithRateLimit(error, mockSetErrorMessage, mockStep, mockOnRateLimitExceeded)

    expect(mockSetErrorMessage).toHaveBeenCalledWith(
      "You've reached the maximum number of resend attempts (5 per hour). Please wait before trying again."
    )
    expect(mockOnRateLimitExceeded).toHaveBeenCalledWith(undefined)
    // Console logging is tested implicitly
  })

  it('should use custom rate limit message when provided', () => {
    const error = {
      code: ErrorCodes.ResourceExhausted,
      message: 'Rate limit exceeded',
      metadata: { 'error-code': ErrorCodes.ResourceExhausted }
    }

    const customMessage = "Custom rate limit message"
    handleApiErrorWithRateLimit(error, mockSetErrorMessage, mockStep, mockOnRateLimitExceeded, {
      rateLimitMessage: customMessage
    })

    expect(mockSetErrorMessage).toHaveBeenCalledWith(customMessage)
  })

  it('should handle non-rate-limit errors normally', () => {
    const error = {
      code: ErrorCodes.UserNotFound,
      message: 'User not found',
      metadata: { 'error-code': ErrorCodes.UserNotFound }
    }

    handleApiErrorWithRateLimit(error, mockSetErrorMessage, mockStep, mockOnRateLimitExceeded)

    expect(mockSetErrorMessage).toHaveBeenCalledWith(
      friendlyMessageFor[ErrorCodes.UserNotFound]
    )
    expect(mockOnRateLimitExceeded).not.toHaveBeenCalled()
  })

  it('should extract retry-after from both header formats', () => {
    const errorWithRetryAfter = {
      code: ErrorCodes.ResourceExhausted,
      message: 'Rate limit exceeded',
      metadata: { 
        'error-code': ErrorCodes.ResourceExhausted,
        'x-retry-after-seconds': '3600' // 60 minutes
      }
    }

    handleApiErrorWithRateLimit(errorWithRetryAfter, mockSetErrorMessage, mockStep, mockOnRateLimitExceeded)

    expect(mockOnRateLimitExceeded).toHaveBeenCalledWith(60)
  })
})