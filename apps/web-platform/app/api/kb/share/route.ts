// Thin HTTP wrappers around the share lifecycle in server/kb-share.ts.
// All validation + DB lifecycle lives in the shared module so the in-process
// MCP tools (server/kb-share-tools.ts) inherit the same hardening by
// construction. Closes #2298.

import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { resolveUserKbRoot } from "@/server/kb-route-helpers";
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

  const serviceClient = createServiceClient();
  const workspace = await resolveUserKbRoot(serviceClient, user.id);
  if (!workspace.ok) return workspace.response;

  const result = await createShare(
    serviceClient,
    user.id,
    workspace.kbRoot,
    body.documentPath,
  );
  if (!result.ok) {
    return NextResponse.json({ error: result.error }, { status: result.status });
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
