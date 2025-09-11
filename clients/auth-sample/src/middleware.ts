import {type NextRequest, NextResponse} from "next/server";
import {trace, ROOT_CONTEXT, type TextMapGetter} from "@opentelemetry/api";
import {W3CTraceContextPropagator} from "@opentelemetry/core";
import {config as appConfig} from "@/lib/config";
import {checkAuthentication, type AuthCheckResult } from "@/lib/server/authz-client";
import {isProtectedRoute, isAuthRoute, createSignInRedirectUrl, createHomeRedirectUrl} from "@/lib/server/route-utils";
import {hasIncomingTrace, injectSpanContextHeaders} from "@/lib/server/trace-utils";

export const config = {
    // Exclude static assets, Next internals, and Chrome DevTools requests
    matcher:
        '/((?!_next/static|_next/image|favicon.ico|error|.*\\.(?:svg|png|jpg|jpeg|gif|webp|woff|woff2|ttf|eot|css|js)$|.well-known/).*)',
};


export default async function middleware(request: NextRequest) {
    const {pathname} = request.nextUrl;

    // Extract incoming W3C context (if any) to continue the trace
    const tracer = trace.getTracer("middleware");
    const incomingCarrier: Record<string, string> = {};
    request.headers.forEach((value, key) => {
        // Store headers lower-cased for case-insensitive access
        incomingCarrier[key.toLowerCase()] = value;
    });

    const w3c = new W3CTraceContextPropagator();
    const getter: TextMapGetter<Record<string, string>> = {
        get: (carrier, key) => carrier[key.toLowerCase()],
        keys: (carrier) => Object.keys(carrier),
    };
    const extractedCtx = w3c.extract(ROOT_CONTEXT, incomingCarrier, getter);

    const middlewareSpan = tracer.startSpan(
        `${request.method} ${pathname}`,
        {
            attributes: {
                "http.target": pathname,
                "http.method": request.method,
            },
        },
        extractedCtx,
    );

    try {
        const isProtected = isProtectedRoute(pathname);
        const isAuth = isAuthRoute(pathname);

        const cookieHeader = request.headers.get("cookie") ?? "";
        const authResult: AuthCheckResult = await checkAuthentication(
            appConfig.authServiceUrl,
            middlewareSpan,
            {cookie: cookieHeader}
        );

        if (isProtected && !authResult.isAuthenticated) {
            const res = NextResponse.redirect(createSignInRedirectUrl(request.url, pathname));
            for (const c of authResult.setCookies) res.headers.append("set-cookie", c);
            return res;
        }

        if (isAuth && authResult.isAuthenticated) {
            const res = NextResponse.redirect(createHomeRedirectUrl(request.url));
            for (const c of authResult.setCookies) res.headers.append("set-cookie", c);
            return res;
        }

        // Inject W3C trace context so downstream work continues this trace
        const headers = new Headers(request.headers);
        if (!hasIncomingTrace(incomingCarrier)) {
            injectSpanContextHeaders(headers, middlewareSpan);
        }

        const res = NextResponse.next({request: {headers}});
        for (const c of authResult.setCookies) res.headers.append("set-cookie", c);
        return res;
    } catch (error) {
        // Log the error for debugging
        console.error("Authentication check failed:", error);

        // Redirect to error page with error information
        const errorUrl = new URL("/error", request.url);
        errorUrl.searchParams.set("message", error instanceof Error ? error.message : String(error));
        errorUrl.searchParams.set("from", pathname);
        return NextResponse.redirect(errorUrl);
    } finally {
        middlewareSpan.end();
    }
}
