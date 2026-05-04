import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { createServiceClient } from "@/lib/supabase/server";
import { resolveOrigin } from "@/lib/auth/resolve-origin";
import { classifyCallbackError } from "@/lib/auth/error-classifier";
import { classifyProviderError } from "@/lib/auth/provider-error-classifier";
import { provisionWorkspace } from "@/server/workspace";
import { TC_VERSION } from "@/lib/legal/tc-version";
import { NextResponse, type NextRequest } from "next/server";
import logger from "@/server/logger";
import { reportSilentFallback } from "@/server/observability";

const VERIFIER_COOKIE_PATTERN = /^sb-.*-auth-token-code-verifier$/;

/** Extract `host` from an arbitrary referer header — never the path or query. */
function safeRefererHost(referer: string | null): string | null {
  if (!referer) return null;
  try {
    return new URL(referer).host || null;
  } catch {
    return null;
  }
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
  // Sorted, key-only — never values (would forward error_description PII).
  const searchParamKeys = Array.from(new Set(Array.from(searchParams.keys()))).sort();

  // 1. Provider-side OAuth error (`?error=access_denied&error_description=...`).
  //    Supabase forwards the upstream provider's `error` query param verbatim
  //    on `redirect_to` per the documented user-deny path. Branch BEFORE the
  //    `if (code)` block so user-cancel is never conflated with system failure.
  const providerErrorBucket = classifyProviderError(searchParams);
  if (providerErrorBucket) {
    const providerErrorCode = searchParams.get("error");
    reportSilentFallback(null, {
      feature: "auth",
      op: "callback_provider_error",
      message: `OAuth provider returned error=${providerErrorCode}`,
      // Typed enum + hostname only. Never the raw `error_description`
      // (free text, may include account-specific details), never the full
      // request URL (carries the same free text), never the full referer.
      extra: {
        providerErrorCode,
        bucket: providerErrorBucket,
        urlPath: pathname,
        refererHost,
        origin,
      },
    });
    return NextResponse.redirect(`${origin}/login?error=${providerErrorBucket}`);
  }

  if (code) {
    // Guard: in dev mode without Supabase env vars, redirect to login with error.
    // Only triggers for NODE_ENV=development (not test, where mocks provide the client).
    if (
      process.env.NODE_ENV === "development" &&
      (!process.env.NEXT_PUBLIC_SUPABASE_URL || !process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY)
    ) {
      logger.warn("Auth callback called without Supabase env vars — redirecting to login");
      return NextResponse.redirect(`${origin}/login?error=auth_failed`);
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
      const response = NextResponse.redirect(`${origin}/login?error=${errorCode}`);

      // Folds in #3001: on verifier-class failure, clear stale
      // sb-*-auth-token-code-verifier cookies so the next sign-in attempt
      // mints a fresh PKCE verifier instead of reusing the one Supabase
      // already rejected.
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
        return NextResponse.redirect(`${origin}/login?error=auth_failed`);
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

  // Auth failed — redirect to login with error.
  // No `code` query-param AND no recognized provider `error=` means either
  // the user opened /callback directly (bookmark, stale link) or an
  // unmodeled fallback (e.g. uri_allow_list rejection that strips both).
  // Mirror to Sentry per cq-silent-fallback-must-mirror-to-sentry so the
  // class of failure is observable; the new extras (urlPath, refererHost,
  // searchParamKeys) make root-cause-class queryable without redeploying.
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
  return NextResponse.redirect(`${origin}/login?error=auth_failed`);
}

/** Create a redirect response with accumulated session cookies applied. */
function redirectWithCookies(
  url: string,
  cookies: { name: string; value: string; options: CookieOptions }[],
): NextResponse {
  const response = NextResponse.redirect(url);
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
