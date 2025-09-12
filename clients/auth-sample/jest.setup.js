import '@testing-library/jest-dom'

// Polyfill for TextEncoder/TextDecoder in test environment
if (typeof global.TextEncoder === 'undefined') {
  const { TextEncoder, TextDecoder } = require('util')
  global.TextEncoder = TextEncoder
  global.TextDecoder = TextDecoder
}

// Mock environment variables
process.env.NEXT_PUBLIC_AUTH_SERVICE_URL = 'http://localhost:8080'
process.env.NEXT_PUBLIC_GREETER_SERVICE_URL = 'http://localhost:8081'

// Mock react-oidc-context
jest.mock('react-oidc-context', () => ({
  useAuth: () => ({
    signinRedirect: jest.fn(),
    isLoading: false,
    user: null,
    error: null,
  }),
}))

// Mock gRPC clients with useful defaults for flows
jest.mock('@/lib/services/grpc-clients', () => {
  const { SignUpStep } = require('@/lib/services/auth/sign-up/sign-up_pb')

  const createSignUpServiceClient = () => ({
    initiateSignUpAsync: jest.fn((request) => {
      // Determine next step based on whether password is required
      const requirePassword = typeof request.getRequirePassword === 'function' ? request.getRequirePassword() : false
      const next = requirePassword ? SignUpStep.PASSWORD_REQUIRED : SignUpStep.VERIFICATION_REQUIRED
      return Promise.resolve({
        getNextStep: () => next,
      })
    }),
    verifyAndSignInAsync: jest.fn(() => {
      // Default to sign-in required to complete flow in tests
      return Promise.resolve({
        getNextStep: () => SignUpStep.SIGN_IN_REQUIRED,
      })
    }),
    resendVerificationCodeAsync: jest.fn(() => Promise.resolve({})),
  })

  const createGreeterServiceClient = () => ({
    sayHelloAsync: jest.fn(),
  })

  return { createSignUpServiceClient, createGreeterServiceClient }
})

// Mock workflows
jest.mock('@/lib/workflows', () => ({
  startWorkflow: () => ({
    id: 'test-workflow',
    name: 'test',
    version: 'v1',
    startStep: () => ({
      name: 'test-step',
      attempt: 1,
      run: (fn) => fn(),
      succeed: jest.fn(),
      fail: jest.fn(),
      event: jest.fn(),
    }),
    succeed: jest.fn(),
    fail: jest.fn(),
    event: jest.fn(),
  }),
}))

// Mock Next.js router
jest.mock('next/navigation', () => ({
  useRouter() {
    return {
      push: jest.fn(),
      replace: jest.fn(),
      prefetch: jest.fn(),
      back: jest.fn(),
      forward: jest.fn(),
      refresh: jest.fn(),
    }
  },
  useSearchParams() {
    return new URLSearchParams()
  },
  usePathname() {
    return '/'
  },
}))

// Mock window.matchMedia
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: jest.fn().mockImplementation(query => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: jest.fn(), // deprecated
    removeListener: jest.fn(), // deprecated
    addEventListener: jest.fn(),
    removeEventListener: jest.fn(),
    dispatchEvent: jest.fn(),
  })),
}) 