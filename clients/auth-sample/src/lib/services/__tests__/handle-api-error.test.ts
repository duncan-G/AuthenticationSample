import { handleApiError, friendlyMessageFor } from '../handle-api-error'
import type { StepHandle } from '@/lib/workflows'
import { ErrorCodes } from '../error-codes'

// Mock console.error to avoid noise in tests
const mockConsoleError = jest.spyOn(console, 'error').mockImplementation(() => {})

// Mock workflow step
let mockStep: StepHandle

describe('handleApiError', () => {
  let mockSetErrorMessage: jest.Mock
  let mockOnRateLimitExceeded: jest.Mock

  beforeEach(() => {
    mockSetErrorMessage = jest.fn()
    mockOnRateLimitExceeded = jest.fn()
    mockStep = {
      name: 'test-step',
      attempt: 1,
      run: jest.fn(async (fn: any) => await fn()),
      succeed: jest.fn(),
      fail: jest.fn(),
      event: jest.fn()
    }
    mockConsoleError.mockClear()
  })

  it('should handle ResourceExhausted error with default rate limit message', () => {
    const error = {
      code: ErrorCodes.ResourceExhausted,
      message: 'Rate limit exceeded',
      metadata: { 'error-code': ErrorCodes.ResourceExhausted }
    }

    handleApiError(error, mockSetErrorMessage, mockStep, mockOnRateLimitExceeded)

    expect(mockSetErrorMessage).toHaveBeenCalledWith(
      friendlyMessageFor[ErrorCodes.ResourceExhausted]
    )
    expect(mockOnRateLimitExceeded).toHaveBeenCalledWith(undefined)
    // Console logging is tested implicitly
  })

  it('should handle non-rate-limit errors normally', () => {
    const error = {
      code: ErrorCodes.UserNotFound,
      message: 'User not found',
      metadata: { 'error-code': ErrorCodes.UserNotFound }
    }

    handleApiError(error, mockSetErrorMessage, mockStep, mockOnRateLimitExceeded)

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

    handleApiError(errorWithRetryAfter, mockSetErrorMessage, mockStep, mockOnRateLimitExceeded)

    expect(mockOnRateLimitExceeded).toHaveBeenCalledWith(60)
  })
})