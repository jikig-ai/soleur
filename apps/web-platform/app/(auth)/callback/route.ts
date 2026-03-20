import { createClient, createServiceClient } from "@/lib/supabase/server";
import { provisionWorkspace } from "@/server/workspace";
import { NextResponse } from "next/server";

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const code = searchParams.get("code");
  const forwardedHost = request.headers.get("x-forwarded-host");
  const forwardedProto = request.headers.get("x-forwarded-proto") ?? "https";
  const host = forwardedHost ?? request.headers.get("host") ?? "app.soleur.ai";
  const origin = `${forwardedProto}://${host}`;

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);

    if (error) {
      console.error("[callback] exchangeCodeForSession failed:", error.message, error.status);
    }

    if (!error) {
      const {
        data: { user },
      } = await supabase.auth.getUser();

      if (user) {
        const tcAcceptedAt = await ensureWorkspaceProvisioned(user.id, user.email ?? "");

        if (!tcAcceptedAt) {
          return NextResponse.redirect(`${origin}/accept-terms`);
        }

        // Check if user has an API key set up
        const { data: keys } = await supabase
          .from("api_keys")
          .select("id")
          .eq("user_id", user.id)
          .eq("provider", "anthropic")
          .eq("is_valid", true)
          .limit(1);

        if (!keys || keys.length === 0) {
          return NextResponse.redirect(`${origin}/setup-key`);
        }
        return NextResponse.redirect(`${origin}/dashboard`);
      }
    }
  }

  // Auth failed — redirect to login with error
  console.error("[callback] Auth failed — no code or exchange error. code:", code ? "present" : "missing", "origin:", origin);
  return NextResponse.redirect(`${origin}/login?error=auth_failed`);
}

async function ensureWorkspaceProvisioned(
  userId: string,
  email: string,
): Promise<string | null> {
  const serviceClient = createServiceClient();

  const { data: existing } = await serviceClient
    .from("users")
    .select("workspace_status, tc_accepted_at")
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
      console.error(`[callback] Fallback user upsert failed for ${userId}:`, insertError);
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
      console.error(`[callback] Workspace provisioning failed for ${userId}:`, err);
    }
  }

  return existing.tc_accepted_at;
}
