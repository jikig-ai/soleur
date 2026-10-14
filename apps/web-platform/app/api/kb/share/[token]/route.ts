import { NextResponse } from "next/server";
import { createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { verifiedUserId } from "@/server/request-auth";
import { revokeShare } from "@/server/kb-share";

/** DELETE — revoke a share link (permanent). */
export async function DELETE(
  request: Request,
  { params }: { params: Promise<{ token: string }> },
) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/kb/share/[token]", origin);

  const userId = await verifiedUserId(request);
  if (!userId) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { token } = await params;

  // Note: workspace_status check is intentionally skipped for revocation.
  // Revoking a share link is a metadata operation on kb_share_links, not a
  // workspace content access. Users should be able to revoke even if their
  // workspace is disconnected or not ready.
  const serviceClient = createServiceClient();
  const result = await revokeShare(serviceClient, userId, token);
  if (!result.ok) {
    // Surface `code` so the SharePopover UI can branch on partial-success
    // states. 502 + "purge-failed" means the DB row IS revoked but the CF
    // cache may serve the old 200 for up to s-maxage seconds — the UI can
    // show a degraded-success toast instead of a hard error.
    return NextResponse.json(
      { error: result.error, code: result.code },
      { status: result.status },
    );
  }
  return NextResponse.json({ revoked: true });
}
