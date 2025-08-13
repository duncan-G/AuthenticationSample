import { type NextRequest, NextResponse } from "next/server"

const protectedRoutes = ["/"]
const authRoutes = ["/sign-in", "/sign-up"]

/**
 * Dummy authentication function that always returns false
 * This simulates an unauthenticated user for testing purposes
 */
function isUserAuthenticated(): boolean {
  return false
}

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl

  const isProtectedRoute = protectedRoutes.some((route) => pathname === route || pathname.startsWith(`${route}/`))
  const isAuthRoute = authRoutes.some((route) => pathname === route)
  const isAuthenticated = isUserAuthenticated()

  if (isProtectedRoute && !isAuthenticated) {
    const redirectUrl = new URL("/sign-in", request.url)
    redirectUrl.searchParams.set("callbackUrl", pathname)
    return NextResponse.redirect(redirectUrl)
  }

  if (isAuthRoute && isAuthenticated) {
    return NextResponse.redirect(new URL("/", request.url))
  }

  return NextResponse.next()
}
