import fs from "node:fs";
import path from "node:path";
import { randomBytes } from "crypto";
import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isPathInWorkspace } from "@/server/sandbox";
import { MAX_BINARY_SIZE } from "@/server/kb-binary-response";
import { hashStream } from "@/server/kb-content-hash";
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
  if (body.documentPath.includes("\0")) {
    return NextResponse.json(
      { error: "Invalid document path" },
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

  // Hash the file through an O_NOFOLLOW fd. Stream-hashing avoids a second
  // 50 MB buffer allocation and the fd-level fstat re-validates the type/size
  // post-lstat, closing any symlink-swap window between lstat and open.
  let contentHash: string;
  let handle: fs.promises.FileHandle;
  try {
    handle = await fs.promises.open(
      fullPath,
      fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW,
    );
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code === "ELOOP" || code === "EMLINK") {
      return NextResponse.json({ error: "Invalid document path" }, { status: 400 });
    }
    return NextResponse.json({ error: "File not found" }, { status: 404 });
  }
  try {
    const fdStat = await handle.stat();
    if (!fdStat.isFile()) {
      return NextResponse.json({ error: "Invalid document path" }, { status: 400 });
    }
    if (fdStat.size > MAX_BINARY_SIZE) {
      return NextResponse.json(
        { error: "File exceeds maximum size limit" },
        { status: 413 },
      );
    }
    contentHash = await hashStream(handle.createReadStream({ autoClose: false }));
  } finally {
    await handle.close().catch(() => {});
  }

  // Check if an active (non-revoked) share already exists for this document.
  // If the stored hash still matches the current file, return the existing
  // token (idempotent happy path). If the hash differs, the user is re-sharing
  // a modified file — revoke the stale row and fall through to issue a fresh
  // token. This keeps creation user-friendly after legitimate edits without
  // coupling it to the view-time 410 branch.
  const { data: existing } = await serviceClient
    .from("kb_share_links")
    .select("id, token, content_sha256")
    .eq("user_id", user.id)
    .eq("document_path", body.documentPath)
    .eq("revoked", false)
    .maybeSingle();

  if (existing) {
    if (existing.content_sha256 === contentHash) {
      return NextResponse.json({
        token: existing.token,
        url: `/shared/${existing.token}`,
      });
    }
    await serviceClient
      .from("kb_share_links")
      .update({ revoked: true })
      .eq("id", existing.id);
    logger.info(
      {
        event: "share_reissued_on_content_drift",
        userId: user.id,
        documentPath: body.documentPath,
      },
      "kb/share: revoked stale share and issuing new token (content changed)",
    );
  }

  // Generate a new cryptographically random token.
  const token = randomBytes(32).toString("base64url");
  const { error: insertError } = await serviceClient
    .from("kb_share_links")
    .insert({
      user_id: user.id,
      token,
      document_path: body.documentPath,
      content_sha256: contentHash,
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
