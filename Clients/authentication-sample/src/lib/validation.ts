export function validateEmail(email: string): boolean {
  if (!email || typeof email !== 'string') {
    return false;
  }
  
  const trimmedEmail = email.trim();
  
  // Check for basic format requirements
  if (!trimmedEmail.includes('@')) return false;
  if (trimmedEmail.startsWith('.') || trimmedEmail.endsWith('.')) return false;
  if (trimmedEmail.includes('..')) return false;
  if (trimmedEmail.includes(' ')) return false;
  if (trimmedEmail.includes('@@')) return false;
  
  const parts = trimmedEmail.split('@');
  if (parts.length !== 2) return false;
  
  const [local, domain] = parts;
  if (!local || !domain) return false;
  if (local.startsWith('.') || local.endsWith('.')) return false;
  if (domain.startsWith('.') || domain.endsWith('.')) return false;
  if (!domain.includes('.')) return false;
  
  // Ensure domain has proper structure (at least domain.tld)
  const domainParts = domain.split('.');
  if (domainParts.length < 2) return false;
  if (domainParts.some(part => part.length === 0)) return false;
  
  // Final pattern check
  const pattern = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
  return pattern.test(trimmedEmail);
}

export function validatePassword(password: string): boolean {
  if (!password || typeof password !== 'string') {
    return false;
  }
  
  // Password should be at least 8 characters long
  if (password.length < 8) return false;
  
  // Check for at least one letter (uppercase or lowercase)
  if (!/[a-zA-Z]/.test(password)) return false;
  
  // Check for at least one number
  if (!/\d/.test(password)) return false;
  
  return true;
}

export function validatePasswordConfirmation(password: string, confirmPassword: string): boolean {
  return password === confirmPassword && password.length > 0;
}

export function getPasswordErrors(password: string): string[] {
  const errors: string[] = [];
  
  if (!password) {
    errors.push("Password is required");
    return errors;
  }
  
  if (password.length < 8) {
    errors.push("Password must be at least 8 characters long");
  }
  
  if (!/[a-zA-Z]/.test(password)) {
    errors.push("Password must contain at least one letter");
  }
  
  if (!/\d/.test(password)) {
    errors.push("Password must contain at least one number");
  }
  
  return errors;
}
