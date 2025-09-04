import { type NextRequest, NextResponse } from "next/server";
import { createAuthorizationServiceClient } from "./lib/services/grpc-clients"; // Assuming this path is correct
import { Empty } from "google-protobuf/google/protobuf/empty_pb";

const protectedRoutes = ["/"];
const authRoutes = ["/sign-in", "/sign-up"];
const authorizationServiceClient = createAuthorizationServiceClient();

/**
 * Checks if the user is authenticated by making a gRPC call.
 */
async function isUserAuthenticated() {
    try {
        await authorizationServiceClient.check(new Empty());
        return true;
    } catch (err: unknown) {
        return false;
    }
}

export default async function middleware(request: NextRequest) {
    const { pathname } = request.nextUrl;
    const isProtectedRoute = protectedRoutes.some((route) => pathname === route || pathname.startsWith(`${route}/`));
    const isAuthRoute = authRoutes.some((route) => pathname === route);

    const isAuthenticated = await isUserAuthenticated();

    if (isProtectedRoute && !isAuthenticated) {
        const redirectUrl = new URL("/sign-in", request.url);
        redirectUrl.searchParams.set("callbackUrl", pathname);
        return NextResponse.redirect(redirectUrl);
    }

    if (isAuthRoute && isAuthenticated) {
        return NextResponse.redirect(new URL("/", request.url));
    }

    return NextResponse.next();
}
