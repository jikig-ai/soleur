import fs from "node:fs";
import path from "node:path";
import { randomBytes } from "crypto";
import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isPathInWorkspace } from "@/server/sandbox";
import { MAX_BINARY_SIZE } from "@/server/kb-binary-response";
import { hashStream } from "@/server/kb-content-hash";
import { resolveUserKbRoot } from "@/server/kb-route-helpers";
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
  const workspace = await resolveUserKbRoot(serviceClient, user.id);
  if (!workspace.ok) return workspace.response;

  // Validate the document exists in the user's workspace and is a regular
  // file. Symlink + size + type checks are done via O_NOFOLLOW + fstat on
  // the fd we hash from — no pre-lstat, since the pre-lstat only opens a
  // TOCTOU window the fd path already closes (CodeQL js/file-system-race).
  const { kbRoot } = workspace;
  const fullPath = path.join(kbRoot, body.documentPath);
  if (!isPathInWorkspace(fullPath, kbRoot)) {
    return NextResponse.json({ error: "Invalid document path" }, { status: 400 });
  }

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
    // 23505 = unique_violation. The partial unique index
    // kb_share_links_one_active_per_doc guarantees one active share per
    // (user_id, document_path), so a concurrent POST won that race. Read
    // the winner's row and return its token if hashes match; otherwise
    // surface the conflict as 409 (user can retry).
    if ((insertError as { code?: string }).code === "23505") {
      const { data: winner } = await serviceClient
        .from("kb_share_links")
        .select("token, content_sha256")
        .eq("user_id", user.id)
        .eq("document_path", body.documentPath)
        .eq("revoked", false)
        .maybeSingle();
      if (winner && winner.content_sha256 === contentHash) {
        return NextResponse.json({
          token: winner.token,
          url: `/shared/${winner.token}`,
        });
      }
      return NextResponse.json(
        { error: "Concurrent share creation — retry" },
        { status: 409 },
      );
    }
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
