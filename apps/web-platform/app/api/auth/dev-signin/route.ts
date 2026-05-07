// POST /api/auth/dev-signin — dev-only multi-account QA sign-in (R3).
//
// Triple-defense gate (each layer fails closed independently):
//   A) Strict NODE_ENV === "development" runtime literal at request entry.
//   B) FLAG_DEV_SIGNIN runtime feature-flag check via isDevSignInEnabled().
//   C) Doppler `prd`-absence preflight (verify-required-secrets.sh).
// Plus (D) post-build CI grep gate for forbidden source-level identifiers.
//
// Cookie-writer wiring (R3 in the plan): `NextResponse.redirect()` is
// constructed BEFORE the supabase client, and the supabase `cookies.setAll`
// callback writes onto `response.cookies` — never onto `cookies()` from
// `next/headers` (which writes to the request bag and is dropped on
// redirect, leaving the user authenticated server-side but logged-out
// client-side; middleware would then bounce them back to /login).

import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import { isDevSignInEnabled } from "@/lib/auth/dev-mode";
import { rejectCsrf, validateOrigin } from "@/lib/auth/validate-origin";

import {
  getEmailForSlot,
  getPasswordForSlot,
  slotSchema,
  type DevSlot,
} from "./_helpers";

// 404 with no body — same shape any unmatched App Router request would
// produce, so probing in prd reveals nothing about whether the route exists.
function notFound(): Response {
  return new Response(null, { status: 404 });
}

// 500 with a fixed, scrubbed message. The env-var key DEV_USER_<n>_PASSWORD
// MUST NOT appear in any branch of the error text — operators reading 500
// logs would otherwise learn exactly which Doppler key is missing or
// drifting. Dev-only env-var key names are also on the post-build CI
// grep gate's forbidden-token list.
function configurationError(): Response {
  return new Response("dev sign-in misconfigured", { status: 500 });
}

export async function POST(request: NextRequest | Request): Promise<Response> {
  // Layer A — NODE_ENV literal. Strict `=== "development"`; never
  // `!== "production"` (fires under NODE_ENV=test / SDK-mocked suites).
  if (process.env.NODE_ENV !== "development") return notFound();

  // Layer B — feature flag (must explicitly be "1" in Doppler dev).
  if (!isDevSignInEnabled()) return notFound();

  // CSRF — the route is gated to dev so the realistic threat is a
  // malicious site loaded in the same browser session as a developer's
  // dev server with FLAG_DEV_SIGNIN=1. validateOrigin resolves to the
  // local dev allowlist (localhost:3000 + NEXT_PUBLIC_APP_URL); 403 on
  // mismatch. Required by lib/auth/csrf-coverage.test.ts (negative-space
  // gate over every state-mutating route).
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("/api/auth/dev-signin", origin);

  // Parse form-encoded body (the panel posts a vanilla <form>).
  let slot: DevSlot;
  try {
    const formData = await request.formData();
    const slotRaw = formData.get("slot");
    const parsed = slotSchema.safeParse({
      slot: typeof slotRaw === "string" ? Number(slotRaw) : slotRaw,
    });
    if (!parsed.success) {
      return new Response("invalid slot", { status: 400 });
    }
    slot = parsed.data.slot;
  } catch {
    return new Response("invalid request body", { status: 400 });
  }

  const password = getPasswordForSlot(slot);
  if (!password) return configurationError();

  const email = getEmailForSlot(slot);

  // Construct the redirect response FIRST so the supabase setAll callback
  // can write the auth-token cookie onto `response.cookies` (load-bearing
  // for R3). 303 forces a GET on the redirect target.
  const response = NextResponse.redirect(new URL("/", request.url), 303);

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!supabaseUrl || !supabaseAnonKey) return configurationError();

  const supabase = createServerClient(supabaseUrl, supabaseAnonKey, {
    cookieOptions: {
      sameSite: "lax",
      secure: false, // dev-only — local http://localhost
      path: "/",
    },
    cookies: {
      getAll() {
        // App Router `Request` does not expose a cookies bag; `NextRequest`
        // does. Either way, supabase only needs `getAll` to populate its
        // refresh-token check, and a fresh sign-in flow starts clean.
        const reqCookies = (request as NextRequest).cookies;
        return reqCookies?.getAll?.() ?? [];
      },
      setAll(cookiesToSet: { name: string; value: string; options: CookieOptions }[]) {
        cookiesToSet.forEach(({ name, value, options }) => {
          response.cookies.set(name, value, options);
        });
      },
    },
  });

  const { error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    // Surface a generic failure — never echo `password` (would leak the
    // dev secret) or the env-var key name. Distinct status code from the
    // missing-config 500 so operators can disambiguate via metrics, but
    // the response body is fixed.
    return new Response("dev sign-in failed", { status: 500 });
  }

  return response;
}
