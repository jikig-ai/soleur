import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { tryCreateVision } from "@/server/vision-helpers";

/**
 * POST /api/vision
 *
 * Creates vision.md from the dashboard first-run form.
 * Called fire-and-forget from the client — errors are non-blocking.
 *
 * Body: { content: string }
 */
export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/vision", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body?.content || typeof body.content !== "string") {
    return NextResponse.json(
      { error: "Missing or invalid content" },
      { status: 400 },
    );
  }

  const serviceClient = createServiceClient();
  const { data: userData } = await serviceClient
    .from("users")
    .select("workspace_path")
    .eq("id", user.id)
    .single();

  if (!userData?.workspace_path) {
    return NextResponse.json(
      { error: "Workspace not provisioned" },
      { status: 503 },
    );
  }

  try {
    await tryCreateVision(userData.workspace_path, body.content);
    return NextResponse.json({ ok: true });
  } catch {
    return NextResponse.json(
      { error: "Failed to create vision" },
      { status: 500 },
    );
  }
}
