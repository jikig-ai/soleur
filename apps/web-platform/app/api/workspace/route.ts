import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { provisionWorkspace } from "@/server/workspace";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import logger from "@/server/logger";

export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/workspace", origin);

  // Authenticate the request
  const supabase = await createClient();
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();

  if (authError || !user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Check if workspace is already provisioned
  const serviceClient = createServiceClient();
  const { data: existingUser, error: fetchError } = await serviceClient
    .from("users")
    .select("workspace_status")
    .eq("id", user.id)
    .single();

  if (fetchError) {
    return NextResponse.json(
      { error: "Failed to fetch user record" },
      { status: 500 },
    );
  }

  if (existingUser?.workspace_status === "ready") {
    return NextResponse.json({ status: "already_provisioned" });
  }

  // Mark as provisioning
  await serviceClient
    .from("users")
    .update({ workspace_status: "provisioning" })
    .eq("id", user.id);

  try {
    const workspacePath = await provisionWorkspace(user.id);

    // Update user record with workspace path and ready status
    const { error: updateError } = await serviceClient
      .from("users")
      .update({ workspace_path: workspacePath, workspace_status: "ready" })
      .eq("id", user.id);

    if (updateError) {
      return NextResponse.json(
        { error: "Workspace created but failed to update user record" },
        { status: 500 },
      );
    }

    return NextResponse.json({
      status: "ready",
      workspace_path: workspacePath,
    });
  } catch (err) {
    logger.error({ err, userId: user.id }, "Workspace provisioning failed");
    return NextResponse.json(
      { error: "Workspace provisioning failed" },
      { status: 500 },
    );
  }
}
