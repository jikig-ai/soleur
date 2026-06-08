import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { tryCreateVision } from "@/server/vision-helpers";
import { resolveActiveWorkspacePath } from "@/server/workspace-resolver";

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

  // #5005 — resolve the caller's ACTIVE workspace path via the membership-scoped
  // resolver, NOT the caller's own `users.workspace_path` column. That column is
  // stale/empty for any account provisioned after the ADR-044 `users →
  // workspaces` relocation, which 503'd first-run vision creation for recent
  // signups. The resolver always returns a path (fails closed to solo), and
  // `tryCreateVision` mkdirs the target recursively, so the legacy
  // "not provisioned" 503 guard is dropped — this endpoint is fire-and-forget
  // (the client ignores errors), and a genuine FS failure still surfaces as 500.
  const serviceClient = createServiceClient();
  const workspacePath = await resolveActiveWorkspacePath(user.id, serviceClient);

  try {
    await tryCreateVision(workspacePath, body.content);
    return NextResponse.json({ ok: true });
  } catch {
    return NextResponse.json(
      { error: "Failed to create vision" },
      { status: 500 },
    );
  }
}
