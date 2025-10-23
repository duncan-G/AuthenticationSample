import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { SignUpVerification } from '../signup-verification'

// Mock props for testing
const defaultProps = {
  email: 'test@example.com',
  otpCode: '',
  onOtpChange: jest.fn(),
  onResendEmail: jest.fn(),
  onVerifyOtp: jest.fn(),
  onBack: jest.fn(),
  isLoading: false,
  isResendLoading: false,
  serverError: undefined,
  isRateLimited: false,
  rateLimitRetryAfter: undefined
}

describe('SignUpVerification - Rate Limiting', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('should show resend button when not rate limited and no cooldown', () => {
    render(<SignUpVerification {...defaultProps} />)
    
    expect(screen.getByText('Resend code')).toBeInTheDocument()
    expect(screen.getByText('Resend code')).not.toBeDisabled()
  })

  it('should show client-side cooldown when active', async () => {
    const mockOnResendEmail = jest.fn().mockResolvedValue(undefined)
    
    render(
      <SignUpVerification 
        {...defaultProps} 
        onResendEmail={mockOnResendEmail}
      />
    )
    
    // Click resend to trigger cooldown
    fireEvent.click(screen.getByText('Resend code'))
    
    // Should show cooldown timer
    await waitFor(() => {
      expect(screen.getByText(/Resend in \d+s/)).toBeInTheDocument()
    })
    
    expect(mockOnResendEmail).toHaveBeenCalledTimes(1)
  })

  it('should show rate limit message when rate limited without retry time', () => {
    render(
      <SignUpVerification 
        {...defaultProps} 
        isRateLimited={true}
      />
    )
    
    expect(screen.getByText('Rate limit exceeded. Please wait before trying again.')).toBeInTheDocument()
    expect(screen.queryByText('Resend code')).not.toBeInTheDocument()
  })

  it('should show rate limit message with retry time when provided', () => {
    render(
      <SignUpVerification 
        {...defaultProps} 
        isRateLimited={true}
        rateLimitRetryAfter={45}
      />
    )
    
    expect(screen.getByText('Rate limit exceeded. Try again in 45 minutes.')).toBeInTheDocument()
    expect(screen.queryByText('Resend code')).not.toBeInTheDocument()
  })

  it('should disable resend button when rate limited', () => {
    render(
      <SignUpVerification 
        {...defaultProps} 
        isRateLimited={true}
      />
    )
    
    // Button should not be present when rate limited
    expect(screen.queryByText('Resend code')).not.toBeInTheDocument()
  })

  it('should show loading state during resend', () => {
    render(
      <SignUpVerification 
        {...defaultProps} 
        isResendLoading={true}
      />
    )
    
    expect(screen.getByText('Sending...')).toBeInTheDocument()
    expect(screen.getByText('Sending...')).toBeDisabled()
  })

  it('should not trigger client-side cooldown when rate limited', async () => {
    const mockOnResendEmail = jest.fn().mockResolvedValue(undefined)
    
    render(
      <SignUpVerification 
        {...defaultProps} 
        onResendEmail={mockOnResendEmail}
        isRateLimited={true}
      />
    )
    
    // Rate limited message should be shown, no resend button
    expect(screen.getByText('Rate limit exceeded. Please wait before trying again.')).toBeInTheDocument()
    expect(screen.queryByText('Resend code')).not.toBeInTheDocument()
  })

  it('should handle server error display alongside rate limiting', () => {
    render(
      <SignUpVerification 
        {...defaultProps} 
        isRateLimited={true}
        rateLimitRetryAfter={30}
        serverError="Something went wrong"
      />
    )
    
    // Both server error and rate limit message should be visible
    expect(screen.getByText('Something went wrong')).toBeInTheDocument()
    expect(screen.getByText('Rate limit exceeded. Try again in 30 minutes.')).toBeInTheDocument()
  })

  it('should prioritize rate limit display over cooldown', async () => {
    const mockOnResendEmail = jest.fn().mockResolvedValue(undefined)
    
    const { rerender } = render(
      <SignUpVerification 
        {...defaultProps} 
        onResendEmail={mockOnResendEmail}
      />
    )
    
    // Click resend to trigger cooldown
    fireEvent.click(screen.getByText('Resend code'))
    
    // Should show cooldown timer
    await waitFor(() => {
      expect(screen.getByText(/Resend in \d+s/)).toBeInTheDocument()
    })
    
    // Now simulate rate limiting
    rerender(
      <SignUpVerification 
        {...defaultProps} 
        onResendEmail={mockOnResendEmail}
        isRateLimited={true}
        rateLimitRetryAfter={60}
      />
    )
    
    // Rate limit message should take precedence
    expect(screen.getByText('Rate limit exceeded. Try again in 60 minutes.')).toBeInTheDocument()
    expect(screen.queryByText(/Resend in \d+s/)).not.toBeInTheDocument()
  })
})