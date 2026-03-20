import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { TC_VERSION } from "@/lib/legal/tc-version";

// No auth required — middleware returns early
const PUBLIC_PATHS = ["/login", "/signup", "/callback", "/api/webhooks", "/ws"];

// Auth required, but T&C check skipped (user must reach these to accept terms)
const TC_EXEMPT_PATHS = ["/accept-terms", "/api/accept-terms"];

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Allow public paths (exact match or sub-path only, not prefix collisions)
  if (PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"))) {
    return NextResponse.next();
  }

  // Allow health check
  if (pathname === "/health") {
    return NextResponse.next();
  }

  let response = NextResponse.next({
    request: { headers: request.headers },
  });

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
            request: { headers: request.headers },
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
    return redirectResponse;
  }

  if (!user) {
    return redirectWithCookies("/login");
  }

  // Skip T&C check for exempt paths (accept-terms page and API)
  if (!TC_EXEMPT_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"))) {
    const { data: userRow, error: tcError } = await supabase
      .from("users")
      .select("tc_accepted_version")
      .eq("id", user.id)
      .single();

    if (tcError) {
      // Fail open: allow request if we cannot verify T&C status.
      // Auth is already verified by getUser() above.
      console.error(`[middleware] tc_accepted_version query failed: ${tcError.message}`);
      return response;
    }

    if (userRow?.tc_accepted_version !== TC_VERSION) {
      return redirectWithCookies("/accept-terms");
    }
  }

  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
