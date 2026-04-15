import fs from "node:fs";
import path from "node:path";
import { randomBytes } from "crypto";
import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isPathInWorkspace } from "@/server/sandbox";
import { MAX_BINARY_SIZE } from "@/server/kb-binary-response";
import logger from "@/server/logger";

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
  const { data: userData } = await serviceClient
    .from("users")
    .select("workspace_path, workspace_status")
    .eq("id", user.id)
    .single();

  if (!userData?.workspace_path || userData.workspace_status !== "ready") {
    return NextResponse.json({ error: "Workspace not ready" }, { status: 503 });
  }

  // Validate the document exists in the user's workspace and is a regular
  // file (not a directory, not a symlink) within the size limit. Symlink +
  // size checks are point-of-use per the service-role-idor learning: every
  // operation re-validates, even on owner-supplied paths.
  const kbRoot = path.join(userData.workspace_path, "knowledge-base");
  const fullPath = path.join(kbRoot, body.documentPath);
  if (!isPathInWorkspace(fullPath, kbRoot)) {
    return NextResponse.json({ error: "Invalid document path" }, { status: 400 });
  }
  let lstat: fs.Stats;
  try {
    lstat = await fs.promises.lstat(fullPath);
  } catch {
    return NextResponse.json({ error: "File not found" }, { status: 404 });
  }
  if (lstat.isSymbolicLink() || !lstat.isFile()) {
    return NextResponse.json({ error: "Invalid document path" }, { status: 400 });
  }
  if (lstat.size > MAX_BINARY_SIZE) {
    return NextResponse.json(
      { error: "File exceeds maximum size limit" },
      { status: 413 },
    );
  }

  // Check if an active (non-revoked) share already exists for this document.
  const { data: existing } = await serviceClient
    .from("kb_share_links")
    .select("token")
    .eq("user_id", user.id)
    .eq("document_path", body.documentPath)
    .eq("revoked", false)
    .maybeSingle();

  if (existing) {
    return NextResponse.json({
      token: existing.token,
      url: `/shared/${existing.token}`,
    });
  }

  // Generate a new cryptographically random token.
  const token = randomBytes(32).toString("base64url");
  const { error: insertError } = await serviceClient
    .from("kb_share_links")
    .insert({
      user_id: user.id,
      token,
      document_path: body.documentPath,
    });

  if (insertError) {
    logger.error({ err: insertError }, "kb/share: failed to create share link");
    return NextResponse.json(
      { error: "Failed to create share link" },
      { status: 500 },
    );
  }

  logger.info(
    { event: "share_created", userId: user.id, documentPath: body.documentPath },
    "kb/share: share link created",
  );
  return NextResponse.json({ token, url: `/shared/${token}` }, { status: 201 });
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
  let query = serviceClient
    .from("kb_share_links")
    .select("token, document_path, created_at, revoked")
    .eq("user_id", user.id);

  if (documentPath) {
    query = query.eq("document_path", documentPath);
  }

  const { data: shares, error } = await query
    .order("created_at", { ascending: false });

  if (error) {
    logger.error({ err: error }, "kb/share: failed to list shares");
    return NextResponse.json(
      { error: "Failed to list shares" },
      { status: 500 },
    );
  }

  return NextResponse.json({ shares: shares ?? [] });
}
