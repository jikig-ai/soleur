import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";

/** DELETE — revoke a share link (permanent). */
export async function DELETE(
  request: Request,
  { params }: { params: Promise<{ token: string }> },
) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/kb/share/[token]", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { token } = await params;

  const serviceClient = createServiceClient();
  // Note: workspace_status check is intentionally skipped for revocation.
  // Revoking a share link is a metadata operation on kb_share_links,
  // not a workspace content access. Users should be able to revoke even
  // if their workspace is disconnected or not ready.
  const { data: shareLink, error: fetchError } = await serviceClient
    .from("kb_share_links")
    .select("id, user_id")
    .eq("token", token)
    .single();

  if (fetchError || !shareLink) {
    return NextResponse.json({ error: "Share link not found" }, { status: 404 });
  }

  if (shareLink.user_id !== user.id) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const { error: updateError } = await serviceClient
    .from("kb_share_links")
    .update({ revoked: true })
    .eq("id", shareLink.id);

  if (updateError) {
    logger.error({ err: updateError }, "kb/share: failed to revoke share link");
    Sentry.captureException(updateError, {
      tags: { feature: "kb-share", op: "revoke" },
      extra: { userId: user.id, token },
    });
    return NextResponse.json(
      { error: "Failed to revoke share link" },
      { status: 500 },
    );
  }

  logger.info(
    { event: "share_revoked", userId: user.id, token },
    "kb/share: share link revoked",
  );
  return NextResponse.json({ revoked: true });
}
