import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { createServiceClient } from "@/lib/supabase/server";
import { resolveOrigin } from "@/lib/auth/resolve-origin";
import { provisionWorkspace } from "@/server/workspace";
import { TC_VERSION } from "@/lib/legal/tc-version";
import { NextResponse, type NextRequest } from "next/server";
import logger from "@/server/logger";

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
      logger.error(
        { err: error, status: error.status, errorName: error.name },
        "exchangeCodeForSession failed",
      );

      // Return specific error so the login page can show a helpful message
      const errorCode = error.message?.includes("code verifier")
        ? "code_verifier_missing"
        : "auth_failed";
      return NextResponse.redirect(`${origin}/login?error=${errorCode}`);
    }

    if (!error) {
      const {
        data: { user },
      } = await supabase.auth.getUser();

      if (user) {
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
  }

  // Auth failed — redirect to login with error
  logger.error({ codePresent: !!code, origin }, "Auth failed — no code or exchange error");
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
