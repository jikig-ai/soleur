// Thin HTTP wrappers around the share lifecycle in server/kb-share.ts.
// All validation + DB lifecycle lives in the shared module so the in-process
// MCP tools (server/kb-share-tools.ts) inherit the same hardening by
// construction. Closes #2298.

import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { resolveActiveWorkspaceKbRoot } from "@/server/workspace-resolver";
import { reportSilentFallback } from "@/server/observability";
import { createShare, listShares } from "@/server/kb-share";

/** POST — generate a share link for a KB document. */
export async function POST(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/kb/share", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body?.documentPath || typeof body.documentPath !== "string") {
    return NextResponse.json(
      { error: "Missing or invalid documentPath" },
      { status: 400 },
    );
  }

  // ADR-044 resolver consolidation: read the KB root via the membership-scoped
  // service-role resolver (parity with content/tree/search/c4-project) instead
  // of the legacy tenant/RLS per-user KB-root helper. That legacy helper gated
  // on the CALLER's `users.workspace_status`, which is stale/empty for users
  // provisioned after the ADR-044 `users → workspaces` relocation — the
  // divergent failure surface that dead-ended "Generate link". createShare
  // still takes the service-role client (kb_share_links writer is allowlisted).
  const serviceClient = createServiceClient();
  const access = await resolveActiveWorkspaceKbRoot(user.id, serviceClient);
  if (!access.ok) {
    // Workstream A: mirror the resolver-error response so the failing branch is
    // observable (status now in scope — the legacy resolver returned an opaque
    // pre-built Response). reason = the HTTP status the route surfaces.
    reportSilentFallback(null, {
      feature: "kb-share",
      op: "resolve",
      message: "share resolver failed (active workspace KB root)",
      extra: {
        userId: user.id,
        documentPath: body.documentPath,
        reason: access.status,
      },
    });
    return NextResponse.json(
      { error: access.status === 404 ? "Workspace not found" : "Workspace not ready" },
      { status: access.status },
    );
  }

  // kb_share_links.workspace_id is NOT NULL (migration 059). Reuse the active
  // workspace id the resolver already resolved via
  // resolveActiveWorkspace (claim → membership-checked → solo
  // fallback = user.id) so the row satisfies the constraint AND the
  // workspace-member RLS policy. This drops the second resolveCurrentWorkspaceId
  // round-trip: the two agree for solo/legitimate-member callers, and the
  // resolver value fails CLOSED to solo on a non-member stale claim (stronger
  // than the bare claim the old call returned — the self-heal is covered by
  // test/server/workspace-resolver-repo-meta.test.ts). The route forwards this
  // resolved id into createShare's workspace_id (asserted in
  // test/kb-share-allowed-paths.test.ts "forwards the resolver's active id").
  const result = await createShare(
    serviceClient,
    user.id,
    access.activeWorkspaceId,
    access.kbRoot,
    body.documentPath,
  );
  if (!result.ok) {
    // Pass `code` through so the client can branch (e.g. re-read on the 409
    // concurrent-retry winner) instead of treating every failure identically.
    return NextResponse.json(
      { error: result.error, code: result.code },
      { status: result.status },
    );
  }
  return NextResponse.json(
    { token: result.token, url: result.url },
    { status: result.status },
  );
}

/** GET — list share links for the authenticated user, optionally filtered by documentPath. */
export async function GET(request: Request) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const documentPath = searchParams.get("documentPath");

  const serviceClient = createServiceClient();
  const result = await listShares(
    serviceClient,
    user.id,
    documentPath ? { documentPath } : undefined,
  );
  if (!result.ok) {
    return NextResponse.json({ error: result.error }, { status: result.status });
  }
  // Preserve the existing HTTP shape — list rows still use snake_case
  // column names to keep the client contract stable.
  return NextResponse.json({
    shares: result.shares.map((s) => ({
      token: s.token,
      document_path: s.documentPath,
      created_at: s.createdAt,
      revoked: s.revoked,
    })),
  });
}
