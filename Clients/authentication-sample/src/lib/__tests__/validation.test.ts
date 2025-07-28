import { validateEmail, validatePassword, validatePasswordConfirmation, getPasswordErrors } from '../validation'

describe('validation utilities', () => {
  describe('validateEmail', () => {
    it('should return true for valid email addresses', () => {
      const validEmails = [
        'test@example.com',
        'user@domain.org',
        'hello@test.co.uk',
        'user.name@example.com',
        'user+tag@example.com',
        'user123@example123.com',
        'a@b.co',
        'test.email.with+symbol@example.com',
      ]

      validEmails.forEach(email => {
        expect(validateEmail(email)).toBe(true)
      })
    })

    it('should return false for invalid email addresses', () => {
      const invalidEmails = [
        '',
        'invalid',
        'invalid@',
        '@invalid.com',
        'invalid@.com',
        'invalid@com.',
        'invalid.com',
        'invalid@com',
        'invalid @example.com',
        'invalid@ex ample.com',
        'invalid@@example.com',
        'invalid@example',
        '.invalid@example.com',
        'invalid.@example.com',
        'invalid@example..com',
      ]

      invalidEmails.forEach(email => {
        expect(validateEmail(email)).toBe(false)
      })
    })

    it('should handle edge cases', () => {
      expect(validateEmail(null as any)).toBe(false)
      expect(validateEmail(undefined as any)).toBe(false)
      expect(validateEmail(123 as any)).toBe(false)
      expect(validateEmail({} as any)).toBe(false)
      expect(validateEmail([] as any)).toBe(false)
    })
  })

  describe('validatePassword', () => {
    it('should return true for valid passwords', () => {
      const validPasswords = [
        'password1',
        'PASSWORD1',
        'Password1',
        'mypass123',
        'MYPASS123',
        'longpassword123',
        'a1234567',
        'A1234567',
      ]

      validPasswords.forEach(password => {
        expect(validatePassword(password)).toBe(true)
      })
    })

    it('should return false for passwords shorter than 8 characters', () => {
      const shortPasswords = [
        'short1',
        'abc123',
        'a1',
        'Pass1',
      ]

      shortPasswords.forEach(password => {
        expect(validatePassword(password)).toBe(false)
      })
    })

    it('should return false for passwords without letters', () => {
      const passwordsWithoutLetters = [
        '12345678',
        '1234567890',
        '!@#$%^&*',
      ]

      passwordsWithoutLetters.forEach(password => {
        expect(validatePassword(password)).toBe(false)
      })
    })

    it('should return false for passwords without numbers', () => {
      const passwordsWithoutNumbers = [
        'password',
        'PASSWORD',
        'MyPassword',
        'longpassword',
      ]

      passwordsWithoutNumbers.forEach(password => {
        expect(validatePassword(password)).toBe(false)
      })
    })

    it('should handle edge cases', () => {
      expect(validatePassword('')).toBe(false)
      expect(validatePassword(null as any)).toBe(false)
      expect(validatePassword(undefined as any)).toBe(false)
      expect(validatePassword(123 as any)).toBe(false)
    })
  })

  describe('validatePasswordConfirmation', () => {
    it('should return true when passwords match and are not empty', () => {
      expect(validatePasswordConfirmation('password123', 'password123')).toBe(true)
      expect(validatePasswordConfirmation('MyPass1', 'MyPass1')).toBe(true)
      expect(validatePasswordConfirmation('a', 'a')).toBe(true)
    })

    it('should return false when passwords do not match', () => {
      expect(validatePasswordConfirmation('password123', 'password124')).toBe(false)
      expect(validatePasswordConfirmation('MyPass1', 'mypass1')).toBe(false)
      expect(validatePasswordConfirmation('test', 'different')).toBe(false)
    })

    it('should return false when either password is empty', () => {
      expect(validatePasswordConfirmation('', '')).toBe(false)
      expect(validatePasswordConfirmation('password123', '')).toBe(false)
      expect(validatePasswordConfirmation('', 'password123')).toBe(false)
    })
  })

  describe('getPasswordErrors', () => {
    it('should return no errors for valid passwords', () => {
      expect(getPasswordErrors('password1')).toEqual([])
      expect(getPasswordErrors('PASSWORD1')).toEqual([])
      expect(getPasswordErrors('MyPass123')).toEqual([])
    })

    it('should return required error for empty password', () => {
      expect(getPasswordErrors('')).toEqual(['Password is required'])
    })

    it('should return length error for short passwords', () => {
      expect(getPasswordErrors('short1')).toContain('Password must be at least 8 characters long')
    })

    it('should return letter error for passwords without letters', () => {
      expect(getPasswordErrors('12345678')).toContain('Password must contain at least one letter')
    })

    it('should return number error for passwords without numbers', () => {
      expect(getPasswordErrors('password')).toContain('Password must contain at least one number')
    })

    it('should return multiple errors for passwords with multiple issues', () => {
      const errors = getPasswordErrors('short')
      expect(errors).toContain('Password must be at least 8 characters long')
      expect(errors).toContain('Password must contain at least one number')
      expect(errors).toHaveLength(2)
    })

    it('should return all applicable errors for completely invalid password', () => {
      const errors = getPasswordErrors('abc')
      expect(errors).toContain('Password must be at least 8 characters long')
      expect(errors).toContain('Password must contain at least one number')
      expect(errors).toHaveLength(2)
    })
  })
}) 