import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { createServiceClient } from "@/lib/supabase/server";
import { resolveOrigin } from "@/lib/auth/resolve-origin";
import { classifyCallbackError } from "@/lib/auth/error-classifier";
import {
  classifyProviderError,
  isKnownProviderErrorCode,
} from "@/lib/auth/provider-error-classifier";
import { provisionWorkspace } from "@/server/workspace";
import { resolveCurrentWorkspaceId } from "@/server/workspace-resolver";
import { safeReturnTo } from "@/lib/safe-return-to";
import { TC_VERSION } from "@/lib/legal/tc-version";
import { NextResponse, type NextRequest } from "next/server";
import * as Sentry from "@sentry/nextjs";
import logger from "@/server/logger";
import {
  reportSilentFallback,
  warnSilentFallback,
} from "@/server/observability";
import { hashUserIdValue } from "@/server/userid-pseudonymize";
import { userHasEffectiveByokKey } from "@/server/byok-resolver";
import {
  shouldRouteToSetupKey,
  isInviteReturnTarget,
} from "@/lib/onboarding/setup-key-gate";

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
  // Validated same-origin relative path to land on once the user is fully
  // onboarded (e.g. /invite/<token> threaded through the OAuth round-trip by
  // oauth-buttons). null when absent or rejected. This NEVER skips the
  // /accept-terms, /setup-key, or /connect-repo gates below — it only
  // overrides the terminal /dashboard hop.
  const nextParam = safeReturnTo(searchParams.get("next"));
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
    if (providerErrorBucket === "oauth_cancelled") {
      // User clicked Cancel — expected per RFC 6749 §4.1.2.1; structured log
      // only. Sentry alert rules count ALL captureMessage events regardless of
      // level, so even warning-level emission triggers auth-per-user-loop.
      logger.info(
        {
          feature: "auth",
          op: "callback_provider_error",
          providerErrorCode,
          bucket: providerErrorBucket,
          urlPath: pathname,
          refererHost,
          origin,
        },
        `OAuth provider returned error=${providerErrorCode}`,
      );
    } else {
      warnSilentFallback(null, {
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
    }
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
        // Delegation+skip-aware (#4642). `hasEffectiveKey` = own valid key OR
        // accepted delegation; `onErrorReturn: true` fails OPEN so a transient
        // resolver error never traps a possibly-delegated user at /setup-key
        // (chat-time enforcement is authoritative). `setup_key_skipped_at` is
        // read alongside the existing repo_status service-client read.
        const hasEffectiveKey = await userHasEffectiveByokKey(user.id, {
          onErrorReturn: true,
        });
        const serviceClient = createServiceClient();
        // ADR-044 PR-2 (#5462): `repo_status` is AUTHORITATIVE on the active
        // `workspaces` row (it goes stale on `users` for post-cutover
        // connects/disconnects). `setup_key_skipped_at` is NOT relocated — it
        // stays on `users`. Read each from its source. Resolve the active
        // workspace (claim → solo fallback, never a sibling).
        const activeWorkspaceId = await resolveCurrentWorkspaceId(
          user.id,
          serviceClient,
        );
        const [skipRes, repoStatusRes] = await Promise.all([
          serviceClient
            .from("users")
            .select("setup_key_skipped_at")
            .eq("id", user.id)
            .single(),
          serviceClient
            .from("workspaces")
            .select("repo_status")
            .eq("id", activeWorkspaceId)
            .maybeSingle(),
        ]);
        const setupKeySkippedAt =
          (skipRes.data?.setup_key_skipped_at as string | null | undefined) ??
          null;
        const repoStatus =
          (repoStatusRes.data?.repo_status as string | null | undefined) ??
          null;

        if (shouldRouteToSetupKey({ hasEffectiveKey, setupKeySkippedAt })) {
          // Invite outranks onboarding (#4715): a keyless invitee can't
          // complete the /setup-key key-purchase funnel, so a validated
          // `/invite/<token>` next-param wins here (T&C already recorded — the
          // tcAcceptedVersion gate above routes unaccepted users to
          // /accept-terms first). The previous code dropped nextParam entirely,
          // the live deadlock this fix closes. Non-invite keyless signups still
          // land on /setup-key.
          redirectPath = isInviteReturnTarget(nextParam)
            ? nextParam
            : "/setup-key";
        } else if (!hasEffectiveKey) {
          // Keyless but skipped: terminal hop — honor the invite next-param
          // (#4641) else the dashboard (where the NoApiKeyBanner explains the
          // blocked state). Do NOT route into /connect-repo — repo setup
          // auto-fires a headless sync agent that needs a key, which would
          // orphan a stalled "active" conversation and show a misleading
          // "ready" screen (#4642 review).
          redirectPath = nextParam ?? "/dashboard";
        } else {
          redirectPath =
            repoStatus == null || repoStatus === "not_connected"
              ? "/connect-repo"
              : (nextParam ?? "/dashboard");
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
    //
    // Workspace identifier === userId per migration 053 §1.1.7 N2 invariant
    // (the workspace_members backfill makes workspaces.id = owner_user_id;
    // the handle_new_user trigger preserves this for new signups).
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
      Sentry.withIsolationScope(() => {
        Sentry.getCurrentScope().setUser({ id: hashUserIdValue(userId) });
        reportSilentFallback(insertError, {
          feature: "auth-callback",
          op: "user-upsert",
          message: "Fallback user upsert failed",
          extra: { userId },
        });
      });
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
      Sentry.withIsolationScope(() => {
        Sentry.getCurrentScope().setUser({ id: hashUserIdValue(userId) });
        reportSilentFallback(err, {
          feature: "auth-callback",
          op: "workspace-provisioning",
          message: "Workspace provisioning failed",
          extra: { userId },
        });
      });
    }
  }

  return existing.tc_accepted_version ?? null;
}
