/**
 * Routes that require authentication
 */
export const PROTECTED_ROUTES = ["/"] as const;

/**
 * Routes that are authentication-related (sign-in, sign-up)
 */
export const AUTH_ROUTES = ["/sign-in", "/sign-up"] as const;

/**
 * Checks if a pathname matches any protected route
 */
export function isProtectedRoute(pathname: string): boolean {
    return PROTECTED_ROUTES.some(
        (route) => pathname === route || pathname.startsWith(`${route}/`),
    );
}

/**
 * Checks if a pathname is an authentication route
 */
export function isAuthRoute(pathname: string): boolean {
    return AUTH_ROUTES.some((route) => pathname === route);
}

/**
 * Creates a redirect URL for sign-in with callback
 */
export function createSignInRedirectUrl(requestUrl: string, callbackPath: string): URL {
    const redirectUrl = new URL("/sign-in", requestUrl);
    redirectUrl.searchParams.set("callbackUrl", callbackPath);
    return redirectUrl;
}

/**
 * Creates a redirect URL to home page
 */
export function createHomeRedirectUrl(requestUrl: string): URL {
    return new URL("/", requestUrl);
}
