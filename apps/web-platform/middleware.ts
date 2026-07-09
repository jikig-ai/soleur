// live-verify gate exercise: deliberate no-op to trigger the report-only
// post-deploy harness (this file matches scripts/live-verify/trigger-paths.txt
// `^apps/web-platform/middleware\.ts`, re-homed by PR #5488). No behavior change;
// report-only cannot block deploy. Re-armed to validate the start_session-ack
// fix (PR #5573) — confirm the harness now reaches PASS rather than session-rejected.
import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { TC_VERSION } from "@/lib/legal/tc-version";
import { buildCspHeader } from "@/lib/csp";
import { resolveOrigin } from "@/lib/auth/resolve-origin";
import { PUBLIC_PATHS, TC_EXEMPT_PATHS } from "@/lib/routes";
// Edge middleware cannot import `@/server/observability` (pulls `node:crypto`
// + `pino`, breaks edge bundle). Use the lib/ edge-safe variant instead;
// see `lib/auth/validate-origin.ts:3-7` for the documented constraint.
import { reportEdgeSilentFallback } from "@/lib/observability-edge";

// Inline JWT-payload decoder (edge-safe). The canonical decoder lives at
// `lib/supabase/tenant.ts:decodeJwtPayloadUnsafe` but tenant.ts transitively
// imports `@/server/observability` (pino), which is incompatible with the
// edge runtime. Per #4307 plan §2.1 (C2 + K-P0-1): inline the decoder
// rather than refactor tenant.ts to extract a shared edge-safe module.
// Throws a plain `Error` so the call site (revocation gate below) can
// route it through `reportEdgeSilentFallback` + 401 — no shared
// RuntimeAuthError class on the edge.
function decodeJwtPayloadEdgeSafe(jwt: string): Record<string, unknown> {
  const parts = jwt.split(".");
  if (parts.length !== 3) {
    throw new Error("malformed_jwt: expected 3 segments");
  }
  const padded =
    parts[1].replace(/-/g, "+").replace(/_/g, "/") +
    "=".repeat((4 - (parts[1].length % 4)) % 4);
  try {
    // atob is available in Edge runtime; Buffer is not.
    const json = atob(padded);
    return JSON.parse(json);
  } catch {
    throw new Error("malformed_jwt: payload not JSON");
  }
}

// `clearSessionAndRedirect`: helper for the #4307 revocation gate. Clears
// every `sb-*` cookie on BOTH Domain shapes (Domain-less AND
// `Domain=NEXT_PUBLIC_COOKIE_DOMAIN` — F8 in plan-review) so a Domain-
// scoped Supabase cookie can't survive the Domain-less clear as a phantom.
// Sets `Cache-Control: no-store` so a downstream cache (Vercel edge cache
// or operator-side proxy) cannot serve the redirect target with cookies
// still attached.
function clearSessionAndRedirect(
  request: NextRequest,
  cspValue: string,
  pathname: string,
  searchParams: URLSearchParams,
): NextResponse {
  const url = request.nextUrl.clone();
  url.pathname = pathname;
  url.search = searchParams.toString();
  const response = NextResponse.redirect(url, { status: 302 });
  response.headers.set("Content-Security-Policy", cspValue);
  response.headers.set("Cache-Control", "no-store, no-cache, must-revalidate");
  response.headers.set("Pragma", "no-cache");
  const cookieDomain = process.env.NEXT_PUBLIC_COOKIE_DOMAIN;
  // Append Set-Cookie headers directly. `response.cookies.set(name, ...)`
  // dedupes by name and would clobber the Domain-less clear with the
  // Domain= clear; we need BOTH on the wire so a Supabase-set cookie with
  // either Domain shape gets killed (F8).
  for (const cookie of request.cookies.getAll()) {
    if (cookie.name.startsWith("sb-")) {
      response.headers.append(
        "Set-Cookie",
        `${cookie.name}=; Max-Age=0; Path=/`,
      );
      if (cookieDomain) {
        response.headers.append(
          "Set-Cookie",
          `${cookie.name}=; Max-Age=0; Path=/; Domain=${cookieDomain}`,
        );
      }
    }
  }
  return response;
}

function withCspHeaders(response: NextResponse, cspValue: string): NextResponse {
  response.headers.set("Content-Security-Policy", cspValue);
  return response;
}

// GAP G (ADR-067 staleTimes amendment): `Sec-Fetch-Dest` values that carry
// cacheable NON-document payloads (RSC/API fetches send `empty`; sub-resources
// send `script`/`style`/`image`/…). Everything else — a real `document` nav OR
// an ABSENT header (legacy Safari < 16.4) — is treated as a document and gets
// `no-store` (fail-closed). Module-scoped so it is allocated once, not per request.
const NON_DOCUMENT_DESTS = new Set([
  "empty",
  "script",
  "style",
  "image",
  "font",
  "audio",
  "video",
  "object",
  "embed",
  "manifest",
  "worker",
  "sharedworker",
]);

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
  // `/internal/github-app-init` POSTs the committed manifest JSON to
  // GitHub's App-create form (https://github.com/settings/apps/new) per
  // the manifest-flow design in #4115. Default `form-action 'self'`
  // CSP-blocks the POST. Narrow per-route extension keeps the
  // default-deny posture for every other route.
  const formActionExtra =
    pathname === "/internal/github-app-init"
      ? ["https://github.com"]
      : undefined;
  const cspValue = buildCspHeader({
    nonce,
    isDev: process.env.NODE_ENV === "development",
    supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
    appHost,
    sentryReportUri: process.env.SENTRY_CSP_REPORT_URI,
    formActionExtra,
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

  // #4307 revocation gate. Runs immediately after getUser() so a removed-
  // or role-changed member with a still-valid JWT (natural ~1h expiry) is
  // bounced to /login before any downstream RLS-bound query trusts the
  // workspace_id claim.
  //
  // Topology:
  //   - Per-request RPC call (no cache; Vercel edge isolates are non-
  //     coherent so a per-isolate cache would still leak across regions).
  //   - GENUINE revocation is fail-CLOSED: a row with revoked=true clears
  //     cookies and redirects to /login. That boundary is non-negotiable
  //     (a silent fall-open would re-leak a removed member's stale JWT).
  //   - TRANSIENT failures are NOT revocations and must NOT log the user
  //     out (2026-06-15 session-disconnect fix). A transient RPC error or a
  //     JWT-decode hiccup grace-falls-through (request allowed, re-checked
  //     next request) instead of 503-for-all / forced /login. getUser()
  //     above already authenticated the session against the auth server, so
  //     "RPC errored" and "can't decode iat" tell us nothing about removal.
  //   - User-global predicate (plan F5): the RPC is keyed on auth.uid()
  //     alone, NOT current_organization_id — multi-workspace user removed
  //     from one workspace is bounced on ANY context.
  if (user) {
    // getUser() (above) is the authentication — it validates the JWT with
    // the Supabase auth server. getSession() is retained ONLY to read the
    // raw access-token bytes for the local `iat` decode below; getUser()
    // does not expose the token string. This is NOT the redundant
    // getSession()-after-getUser() re-validation the @supabase/ssr docs warn
    // against (framework-docs §2.4) — it is a token-bytes read, not a second
    // auth round trip. (AC4: documented single getSession() call.)
    const { data: sessionData } = await supabase.auth.getSession();
    const accessToken = sessionData?.session?.access_token;
    if (accessToken) {
      let iatSeconds: number | null = null;
      let decodeThrew = false;
      try {
        const payload = decodeJwtPayloadEdgeSafe(accessToken);
        if (typeof payload.iat === "number") {
          iatSeconds = payload.iat;
        }
      } catch (err) {
        decodeThrew = true;
        // Malformed JWT. getUser() already validated the session, so this is
        // a decoder/transport hiccup, NOT a removal — grant GRACE (allow the
        // request through; re-check next request) rather than forcing a
        // logout. Still mirror to Sentry so a real decoder regression is
        // visible without SSH.
        await reportEdgeSilentFallback(err, {
          feature: "middleware",
          op: "revocation_gate.malformed_jwt",
          extra: { userId: user.id },
        });
      }

      if (!decodeThrew && iatSeconds === null) {
        // Decode succeeded but carried no numeric `iat`. Same grace rationale
        // as malformed_jwt: getUser() validated the session, a missing iat is
        // a token-shape hiccup, not a revocation. Distinct op slug preserved.
        await reportEdgeSilentFallback(new Error("JWT missing iat claim"), {
          feature: "middleware",
          op: "revocation_gate.no_iat",
          extra: { userId: user.id },
        });
      }

      // Only run the revocation predicate when we have a usable iat. A decode
      // hiccup or missing iat grace-falls-through to the normal flow below.
      if (iatSeconds !== null) {
        const iat = new Date(iatSeconds * 1000);
        const { data: revokeData, error: revokeError } = await supabase.rpc(
          "check_my_revocation",
          { p_jwt_iat: iat.toISOString() },
        );
        if (revokeError) {
          // Transient revocation-RPC failure (connectivity blip, pool
          // exhaustion, read-replica lag). Previously fail-CLOSED to 503 for
          // EVERY authenticated request — a single DB blip became a site-wide
          // outage / mass forced-logout. Now: GRACE — allow the
          // otherwise-valid session through and re-check on the next request.
          // The genuine revoked=true branch below stays fail-CLOSED. Distinct
          // op slug so operators see transient DB degradation without SSH.
          //
          // DELIBERATE divergence from the T&C gate below (~L322), which
          // fail-OPENs a transient `tcError` by REDIRECTING to /accept-terms.
          // The two transient-Supabase-error handlers intentionally differ:
          // revocation is a getUser()-authenticated user whose REMOVAL status
          // is merely unknown (and RLS `is_workspace_member` still denies a
          // removed member at the data layer), so we serve the request; T&C is
          // a consent-demonstrability legal gate where serving /dashboard would
          // be an Art. 7(1) breach, so we bounce. Not drift — by threat model.
          await reportEdgeSilentFallback(revokeError, {
            feature: "middleware",
            op: "revocation_gate.transient_grace",
            extra: { userId: user.id },
          });
        } else {
          const row = Array.isArray(revokeData) ? revokeData[0] : revokeData;
          if (row && row.revoked === true) {
            const reason =
              row.reason === "ownership-transferred"
                ? "ownership-transferred"
                : row.reason === "role-changed" ? "role-changed" : "removed";
            const params = new URLSearchParams({ revoked: reason });
            return clearSessionAndRedirect(request, cspValue, "/login", params);
          }
        }
      }
    }
  }

  function redirectWithCookies(pathname: string, searchParams?: URLSearchParams) {
    const url = request.nextUrl.clone();
    url.pathname = pathname;
    if (searchParams) {
      // Replace the query string entirely with the caller-supplied params.
      url.search = searchParams.toString();
    }
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
      // Fail CLOSED. The exempt-path short-circuit at line 126 already
      // covers /accept-terms + /api/accept-terms + the github-resolve
      // recovery callback; this branch fires only on non-exempt paths.
      // Without this redirect, a Supabase outage silently lets every
      // authenticated user reach /dashboard without consent verification
      // — Art. 7(1) demonstrability breach (plan §"User-Brand Impact").
      // The Sentry mirror gives operations a paging signal.
      // Best-effort fire-and-forget: edge runtime can outlive the response
      // via waitUntil semantics, but Next.js middleware does not give us a
      // waitUntil handle on the response object. We accept that some events
      // may be lost on cold-edge isolate teardown; the redirect itself is
      // the load-bearing signal and runs synchronously below.
      void reportEdgeSilentFallback(tcError, {
        feature: "middleware",
        op: "tc_query_failed",
        message: "users.tc_accepted_version SELECT failed",
        extra: { userId: user.id },
      });
      const params = new URLSearchParams();
      params.set("error", "db_unavailable");
      return redirectWithCookies("/accept-terms", params);
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

  // GAP G (ADR-067 staleTimes amendment): defeat bfcache for authenticated
  // documents. A hard navigation wipes the App Router *Router Cache*, but NOT
  // the browser's back/forward cache (bfcache) — a whole-document snapshot that
  // could restore a rendered authenticated page after sign-out + browser Back.
  // `force-dynamic` tabs already emit no-store (Next maps revalidate=0 →
  // no-store); this covers the non-`force-dynamic` authenticated routes (the
  // `"use client"` dashboard/kb pages, settings/billing). We EXCLUDE only the
  // fetch dests that carry cacheable non-document payloads (RSC/API/asset
  // fetches send `Sec-Fetch-Dest: empty`, and `script`/`style`/`image`/etc.),
  // so those keep their caching and the client Router Cache — which is NOT
  // governed by Cache-Control — keeps the perf win. Everything else (a real
  // `document` navigation, OR a request that OMITS the header — legacy Safari
  // < 16.4 still supports bfcache but sends no `Sec-Fetch-*`) is treated as a
  // document and gets `no-store`: FAIL-CLOSED, because a missed no-store on an
  // authenticated document is the exact leak (a shared-device Back restoring
  // the prior user's shell). Public paths already returned above (:134), so
  // they never reach this line and keep their bfcache eligibility.
  const fetchDest = request.headers.get("sec-fetch-dest");
  if (fetchDest === null || !NON_DOCUMENT_DESTS.has(fetchDest)) {
    response.headers.set("Cache-Control", "no-store, no-cache, must-revalidate");
    response.headers.set("Pragma", "no-cache");
  }

  return withCspHeaders(response, cspValue);
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|sw\\.js|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
