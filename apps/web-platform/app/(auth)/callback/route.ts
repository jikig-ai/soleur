import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { createServiceClient } from "@/lib/supabase/server";
import { resolveOrigin } from "@/lib/auth/resolve-origin";
import { classifyCallbackError } from "@/lib/auth/error-classifier";
import {
  classifyProviderError,
  isKnownProviderErrorCode,
} from "@/lib/auth/provider-error-classifier";
import { provisionWorkspace } from "@/server/workspace";
import { TC_VERSION } from "@/lib/legal/tc-version";
import { NextResponse, type NextRequest } from "next/server";
import logger from "@/server/logger";
import { reportSilentFallback } from "@/server/observability";

// Matches both the canonical verifier cookie and the hypothetical chunked
// variant (`@supabase/ssr` chunks `sb-<ref>-auth-token` once it exceeds ~4KB;
// the verifier cookie is short today but the regex tolerates a `.N` suffix
// in case the chunk threshold ever drops). Anchored on both ends so the
// session cookie family (`sb-<ref>-auth-token`, `sb-<ref>-auth-token.0`)
// never matches.
const VERIFIER_COOKIE_PATTERN = /^sb-.*-auth-token-code-verifier(\.\d+)?$/;

const SEARCH_PARAM_KEY_RE = /^[a-zA-Z0-9_.-]{1,32}$/;
const SEARCH_PARAM_KEYS_CAP = 20;

/** Extract `hostname` from an arbitrary referer — never path, query, or port. */
function safeRefererHost(referer: string | null): string | null {
  if (!referer) return null;
  try {
    return new URL(referer).hostname || null;
  } catch {
    return null;
  }
}

/**
 * Wrap `NextResponse.redirect` with `Cache-Control: no-store` so a Cloudflare
 * cache layer (or the synthetic OAuth probe) can never serve a stale
 * pre-fix response back to a real user. All four redirect sites in this
 * route funnel through this helper.
 */
function noStoreRedirect(url: string): NextResponse {
  const response = NextResponse.redirect(url);
  response.headers.set("Cache-Control", "no-store");
  return response;
}

export async function GET(request: NextRequest) {
  const { searchParams, pathname } = new URL(request.url);
  const code = searchParams.get("code");
  const origin = resolveOrigin(
    request.headers.get("x-forwarded-host"),
    request.headers.get("x-forwarded-proto"),
    request.headers.get("host"),
  );
  const refererHost = safeRefererHost(request.headers.get("referer"));
  // Keys-only — never values (would forward `error_description` PII). Capped
  // and shape-filtered so an attacker can't pump arbitrary tag values into
  // Sentry via `?<random>=1&<random>=1&...`.
  const searchParamKeys = [...new Set(searchParams.keys())]
    .filter((k) => SEARCH_PARAM_KEY_RE.test(k))
    .sort()
    .slice(0, SEARCH_PARAM_KEYS_CAP);

  // Provider-side OAuth error (`?error=access_denied&error_description=...`).
  // Branch BEFORE the `if (code)` block so user-cancel is never conflated
  // with system failure. Supabase forwards the upstream provider's `error`
  // verbatim per its documented user-deny redirect path.
  const providerErrorBucket = classifyProviderError(searchParams);
  if (providerErrorBucket) {
    const rawErrorCode = searchParams.get("error") ?? "";
    // Forward the raw error code only when it's in our closed table.
    // Unknown values become `unknown` so an attacker can't inflate the
    // Sentry `providerErrorCode` tag's cardinality with `?error=<random>`
    // and can't smuggle account-specific text via the `error_description`
    // sibling param.
    const providerErrorCode = isKnownProviderErrorCode(rawErrorCode)
      ? rawErrorCode
      : "unknown";
    reportSilentFallback(null, {
      feature: "auth",
      op: "callback_provider_error",
      message: `OAuth provider returned error=${providerErrorCode}`,
      extra: {
        providerErrorCode,
        bucket: providerErrorBucket,
        urlPath: pathname,
        refererHost,
        origin,
      },
    });
    // Verifier cookies are intentionally NOT cleared on this branch — no
    // `exchangeCodeForSession` was attempted, so the verifier in the cookie
    // jar is still valid for a retry.
    return noStoreRedirect(`${origin}/login?error=${providerErrorBucket}`);
  }

  if (code) {
    // Guard: in dev mode without Supabase env vars, redirect to login with error.
    // Only triggers for NODE_ENV=development (not test, where mocks provide the client).
    if (
      process.env.NODE_ENV === "development" &&
      (!process.env.NEXT_PUBLIC_SUPABASE_URL || !process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY)
    ) {
      logger.warn("Auth callback called without Supabase env vars — redirecting to login");
      return noStoreRedirect(`${origin}/login?error=auth_failed`);
    }

    // Accumulate cookie operations so they can be applied to whatever
    // redirect response we return. cookies() from next/headers does NOT
    // carry over to NextResponse.redirect() — cookies must be set on the
    // response object directly.
    const pendingCookies: { name: string; value: string; options: CookieOptions }[] = [];

    const supabase = createServerClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        cookieOptions: {
          sameSite: "lax" as const,
          secure: process.env.NODE_ENV === "production",
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
            cookiesToSet.forEach((cookie) => pendingCookies.push(cookie));
          },
        },
      },
    );

    const { error } = await supabase.auth.exchangeCodeForSession(code);

    if (error) {
      // Mirror to Sentry per cq-silent-fallback-must-mirror-to-sentry.
      // Forward only typed enum fields — error.message can embed user-supplied
      // input (email in OTP errors, OAuth `code` query param) and Sentry is a
      // shared project, so PII forwarding is a cross-tenant exposure vector.
      reportSilentFallback(error, {
        feature: "auth",
        op: "exchangeCodeForSession",
        extra: {
          errorCode: (error as { code?: string }).code,
          errorName: error.name,
          errorStatus: error.status,
        },
      });

      // Discriminate on the typed error.code enum, not error.message
      // substring (drift-prone across Supabase versions).
      const errorCode = classifyCallbackError(error);
      const response = noStoreRedirect(`${origin}/login?error=${errorCode}`);

      // Folds in #3001: on verifier-class failure, clear stale
      // sb-*-auth-token-code-verifier cookies so the next sign-in attempt
      // mints a fresh PKCE verifier instead of reusing the one Supabase
      // already rejected. The deletion is host-only: it matches the
      // host-only Set-Cookie above (no `domain` in cookieOptions). If a
      // future engineer adds `domain: ".soleur.ai"` to `cookieOptions`,
      // mirror it here or this sweep silently no-ops.
      if (errorCode === "code_verifier_missing") {
        for (const cookie of request.cookies.getAll()) {
          if (VERIFIER_COOKIE_PATTERN.test(cookie.name)) {
            response.cookies.set(cookie.name, "", {
              path: "/",
              maxAge: 0,
              sameSite: "lax",
              secure: process.env.NODE_ENV === "production",
            });
          }
        }
      }

      return response;
    }

    if (!error) {
      const {
        data: { user },
      } = await supabase.auth.getUser();

      if (!user) {
        // Exchange succeeded but getUser returned null — distinct failure
        // class from "no code" (bottom-of-function fallback). Mirror with a
        // dedicated op so telemetry doesn't conflate the two.
        reportSilentFallback(null, {
          feature: "auth",
          op: "getUser_null_after_exchange",
          message: "exchangeCodeForSession ok but getUser returned null",
          extra: { origin },
        });
        return noStoreRedirect(`${origin}/login?error=auth_failed`);
      }

      const tcAcceptedVersion = await ensureWorkspaceProvisioned(user.id, user.email ?? "");

      let redirectPath: string;
      if (tcAcceptedVersion !== TC_VERSION) {
        redirectPath = "/accept-terms";
      } else {
        const { data: keys } = await supabase
          .from("api_keys")
          .select("id")
          .eq("user_id", user.id)
          .eq("provider", "anthropic")
          .eq("is_valid", true)
          .limit(1);

        if (!keys || keys.length === 0) {
          redirectPath = "/setup-key";
        } else {
          // Check if a repository is connected
          const serviceClient = createServiceClient();
          const { data: repoUser } = await serviceClient
            .from("users")
            .select("repo_status")
            .eq("id", user.id)
            .single();

          redirectPath =
            !repoUser || repoUser.repo_status === "not_connected"
              ? "/connect-repo"
              : "/dashboard";
        }
      }

      return redirectWithCookies(`${origin}${redirectPath}`, pendingCookies);
    }
  }

  // No `code` AND no recognized provider `error=` — the user opened
  // /callback directly (bookmark, stale link) or hit an unmodeled fallback
  // (e.g. uri_allow_list rejection that strips both). The extras let
  // ops query root-cause-class in Sentry without redeploying.
  reportSilentFallback(null, {
    feature: "auth",
    op: "callback_no_code",
    message: "Auth failed — no code or exchange error",
    extra: {
      codePresent: !!code,
      origin,
      urlPath: pathname,
      refererHost,
      searchParamKeys,
    },
  });
  return noStoreRedirect(`${origin}/login?error=auth_failed`);
}

/** Create a no-store redirect response with accumulated session cookies applied. */
function redirectWithCookies(
  url: string,
  cookies: { name: string; value: string; options: CookieOptions }[],
): NextResponse {
  const response = noStoreRedirect(url);
  cookies.forEach(({ name, value, options }) => {
    response.cookies.set(name, value, {
      ...options,
      sameSite: "lax",
      secure: process.env.NODE_ENV === "production",
      path: "/",
    });
  });
  return response;
}

async function ensureWorkspaceProvisioned(
  userId: string,
  email: string,
): Promise<string | null> {
  // Uses service role client (bypasses RLS) intentionally: during callback,
  // the user row may still be mid-creation by the trigger, and the session
  // client's RLS query could return empty. Middleware uses the session client
  // (anon key + RLS) which is appropriate for established sessions.
  const serviceClient = createServiceClient();

  const { data: existing } = await serviceClient
    .from("users")
    .select("workspace_status, tc_accepted_version")
    .eq("id", userId)
    .single();

  if (!existing) {
    // Safety net: the handle_new_user() trigger is the primary mechanism for
    // creating the users row. This fallback fires only if the trigger failed.
    // tc_accepted_at is always NULL — acceptance is recorded server-side via
    // POST /api/accept-terms.
    const workspacePath = await provisionWorkspace(userId);
    const { error: insertError } = await serviceClient
      .from("users")
      .upsert(
        {
          id: userId,
          email,
          workspace_path: workspacePath,
          workspace_status: "ready",
        },
        { onConflict: "id", ignoreDuplicates: true },
      );
    if (insertError) {
      logger.error({ err: insertError, userId }, "Fallback user upsert failed");
    }
    return null;
  }

  if (existing.workspace_status !== "ready") {
    try {
      const workspacePath = await provisionWorkspace(userId);
      await serviceClient
        .from("users")
        .update({ workspace_path: workspacePath, workspace_status: "ready" })
        .eq("id", userId);
    } catch (err) {
      logger.error({ err, userId }, "Workspace provisioning failed");
    }
  }

  return existing.tc_accepted_version ?? null;
}
