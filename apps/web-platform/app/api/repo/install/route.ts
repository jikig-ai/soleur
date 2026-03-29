import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import logger from "@/server/logger";

/**
 * POST /api/repo/install
 *
 * Stores the GitHub App installation ID on the user record after
 * the user completes the GitHub App installation flow.
 *
 * Body: { installationId: number }
 */
export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/repo/install", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body?.installationId || typeof body.installationId !== "number") {
    return NextResponse.json(
      { error: "Missing or invalid installationId" },
      { status: 400 },
    );
  }

  const serviceClient = createServiceClient();
  const { error: updateError } = await serviceClient
    .from("users")
    .update({ github_installation_id: body.installationId })
    .eq("id", user.id);

  if (updateError) {
    logger.error(
      { err: updateError, userId: user.id },
      "Failed to store installation ID",
    );
    return NextResponse.json(
      { error: "Failed to store installation ID" },
      { status: 500 },
    );
  }

  return NextResponse.json({ ok: true });
}
