import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { TC_VERSION } from "@/lib/legal/tc-version";
import { buildCspHeader } from "@/lib/csp";
import { resolveOrigin } from "@/lib/auth/resolve-origin";
import { PUBLIC_PATHS, TC_EXEMPT_PATHS } from "@/lib/routes";

function withCspHeaders(response: NextResponse, cspValue: string): NextResponse {
  response.headers.set("Content-Security-Policy", cspValue);
  return response;
}

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Health check: no HTML rendered, CSP unnecessary
  if (pathname === "/health") {
    return NextResponse.next();
  }

  // Generate per-request nonce for CSP
  const nonce = Buffer.from(crypto.randomUUID()).toString("base64");
  // Resolve client-facing host via the same validated fallback chain used by
  // the auth callback (resolveOrigin). This prevents CSP injection via spoofed
  // x-forwarded-host headers and eliminates duplication with resolve-origin.ts.
  const origin = resolveOrigin(
    request.headers.get("x-forwarded-host"),
    request.headers.get("x-forwarded-proto"),
    request.headers.get("host"),
  );
  const appHost = new URL(origin).host;
  const cspValue = buildCspHeader({
    nonce,
    isDev: process.env.NODE_ENV === "development",
    supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
    appHost,
    sentryReportUri: process.env.SENTRY_CSP_REPORT_URI,
  });

  // Set nonce and CSP on request headers for Next.js SSR nonce extraction.
  // SECURITY: x-nonce is a request-only header for server-side rendering.
  // Never render it into HTML output or expose it in API responses.
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-nonce", nonce);
  requestHeaders.set("Content-Security-Policy", cspValue);

  // Allow public paths (exact match or sub-path only, not prefix collisions)
  if (PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"))) {
    return withCspHeaders(
      NextResponse.next({ request: { headers: requestHeaders } }),
      cspValue,
    );
  }

  let response = NextResponse.next({
    request: { headers: requestHeaders },
  });

  // Skip Supabase auth when env vars are missing in dev mode — allow
  // unauthenticated access so the dev server can boot without Doppler.
  // Only triggers for NODE_ENV=development (not test, where mocks provide the client).
  if (
    process.env.NODE_ENV === "development" &&
    (!process.env.NEXT_PUBLIC_SUPABASE_URL || !process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY)
  ) {
    console.warn(
      "[supabase] Middleware env vars missing — skipping auth. " +
        "Run with: doppler run -c dev -- npm run dev",
    );
    return withCspHeaders(response, cspValue);
  }

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookieOptions: {
        sameSite: "lax" as const, // SECURITY: blocks cross-site cookie transmission
        secure: process.env.NODE_ENV === "production", // SECURITY: HTTPS-only in production
        path: "/",
      },
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(
          cookiesToSet: {
            name: string;
            value: string;
            options: CookieOptions;
          }[],
        ) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value),
          );
          response = NextResponse.next({
            request: { headers: requestHeaders },
          });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  function redirectWithCookies(pathname: string) {
    const url = request.nextUrl.clone();
    url.pathname = pathname;
    const redirectResponse = NextResponse.redirect(url);
    response.cookies.getAll().forEach((cookie) =>
      redirectResponse.cookies.set(cookie.name, cookie.value),
    );
    return withCspHeaders(redirectResponse, cspValue);
  }

  if (!user) {
    return redirectWithCookies("/login");
  }

  // Skip T&C check for exempt paths (accept-terms page and API)
  if (!TC_EXEMPT_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"))) {
    const { data: userRow, error: tcError } = await supabase
      .from("users")
      .select("tc_accepted_version, subscription_status")
      .eq("id", user.id)
      .single();

    if (tcError) {
      // Fail open: allow request if we cannot verify T&C or billing status.
      // Auth is already verified by getUser() above.
      console.error(`[middleware] user query failed: ${tcError.message}`);
      return withCspHeaders(response, cspValue);
    }

    if (userRow?.tc_accepted_version !== TC_VERSION) {
      return redirectWithCookies("/accept-terms");
    }

    // Billing enforcement: unpaid users are read-only (GET only).
    // Allow billing/checkout paths so users can resolve payment.
    if (
      userRow?.subscription_status === "unpaid" &&
      request.method !== "GET" &&
      !pathname.startsWith("/api/billing") &&
      !pathname.startsWith("/api/checkout")
    ) {
      return withCspHeaders(
        NextResponse.json(
          { error: "subscription_suspended" },
          { status: 403 },
        ),
        cspValue,
      );
    }
  }

  return withCspHeaders(response, cspValue);
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|sw\\.js|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
