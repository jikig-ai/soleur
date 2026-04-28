import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { createServiceClient } from "@/lib/supabase/server";
import { resolveOrigin } from "@/lib/auth/resolve-origin";
import { classifyCallbackError } from "@/lib/auth/error-classifier";
import { provisionWorkspace } from "@/server/workspace";
import { TC_VERSION } from "@/lib/legal/tc-version";
import { NextResponse, type NextRequest } from "next/server";
import logger from "@/server/logger";
import { reportSilentFallback } from "@/server/observability";

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const code = searchParams.get("code");
  const origin = resolveOrigin(
    request.headers.get("x-forwarded-host"),
    request.headers.get("x-forwarded-proto"),
    request.headers.get("host"),
  );

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
      return NextResponse.redirect(`${origin}/login?error=${errorCode}`);
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
  // No `code` query-param means the OAuth provider redirected without one
  // (e.g. uri_allow_list rejected the redirect, or the provider errored).
  // Mirror to Sentry per cq-silent-fallback-must-mirror-to-sentry so the
  // class of failure is observable.
  reportSilentFallback(null, {
    feature: "auth",
    op: "callback_no_code",
    message: "Auth failed — no code or exchange error",
    extra: { codePresent: !!code, origin },
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
