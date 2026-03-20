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
        // Ensure workspace is provisioned (first-time users)
        await ensureWorkspaceProvisioned(user.id, user.email ?? "");

        // Check if user has an API key set up
        const { data: keys } = await supabase
          .from("api_keys")
          .select("id")
          .eq("user_id", user.id)
          .eq("provider", "anthropic")
          .eq("is_valid", true)
          .limit(1);

        // Redirect to key setup if no valid key, otherwise dashboard
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
): Promise<void> {
  const serviceClient = createServiceClient();

  // Upsert user row (first login creates it, subsequent logins are no-ops)
  const { data: existing } = await serviceClient
    .from("users")
    .select("workspace_status")
    .eq("id", userId)
    .single();

  if (!existing) {
    // First-time user — create row and provision
    // Note: this is a safety net path. The handle_new_user() trigger on
    // auth.users INSERT is the primary mechanism for creating the users row
    // (including tc_accepted_at). This fallback fires only if the trigger
    // failed silently or was not present.
    const workspacePath = await provisionWorkspace(userId);
    await serviceClient.from("users").insert({
      id: userId,
      email,
      workspace_path: workspacePath,
      workspace_status: "ready",
      tc_accepted_at: new Date().toISOString(),
    });
    return;
  }

  if (existing.workspace_status === "ready") return;

  // Workspace exists in DB but not provisioned on disk
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
