import { NextResponse } from "next/server";
import path from "node:path";
import { createServiceClient } from "@/lib/supabase/server";
import {
  readContentRaw,
  parseFrontmatter,
  KbNotFoundError,
  KbAccessDeniedError,
} from "@/server/kb-reader";
import {
  readBinaryFile,
  buildBinaryResponse,
} from "@/server/kb-binary-response";
import { hashBytes } from "@/server/kb-content-hash";
import {
  shareEndpointThrottle,
  extractClientIpFromHeaders,
  logRateLimitRejection,
} from "@/server/rate-limiter";
import logger from "@/server/logger";

function contentChangedResponse() {
  return NextResponse.json(
    {
      error: "The shared file has been modified since it was shared.",
      code: "content-changed",
    },
    { status: 410 },
  );
}

function legacyNullHashResponse() {
  return NextResponse.json(
    {
      error: "This link is from an older share system and is no longer valid.",
      code: "legacy-null-hash",
    },
    { status: 410 },
  );
}

export async function GET(
  request: Request,
  { params }: { params: Promise<{ token: string }> },
) {
  // Rate limiting — must precede any filesystem / hash work to avoid DoS via
  // repeated 50 MB hashing requests.
  const clientIp = extractClientIpFromHeaders(request.headers);
  if (!shareEndpointThrottle.isAllowed(clientIp)) {
    logRateLimitRejection("share-endpoint", clientIp);
    return NextResponse.json(
      { error: "Too many requests" },
      { status: 429 },
    );
  }

  const { token } = await params;
  const serviceClient = createServiceClient();

  // Look up share link.
  const { data: shareLink, error: fetchError } = await serviceClient
    .from("kb_share_links")
    .select("document_path, user_id, revoked, content_sha256")
    .eq("token", token)
    .single();

  if (fetchError || !shareLink) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  if (shareLink.revoked) {
    return NextResponse.json(
      { error: "This link has been disabled", code: "revoked" },
      { status: 410 },
    );
  }

  if (!shareLink.content_sha256) {
    // Legacy row from before content-hash binding. Treat as invalid — the
    // migration should have revoked these, but belt-and-suspenders.
    logger.warn(
      { event: "shared_legacy_null_hash", token, documentPath: shareLink.document_path },
      "shared: legacy row without content hash",
    );
    return legacyNullHashResponse();
  }

  // Resolve owner's workspace.
  const { data: owner } = await serviceClient
    .from("users")
    .select("workspace_path, workspace_status")
    .eq("id", shareLink.user_id)
    .single();

  if (!owner?.workspace_path || owner.workspace_status !== "ready") {
    return NextResponse.json(
      { error: "Document no longer available" },
      { status: 404 },
    );
  }

  const kbRoot = path.join(owner.workspace_path, "knowledge-base");
  const ext = path.extname(shareLink.document_path).toLowerCase();

  // Markdown / extensionless branch.
  if (ext === ".md" || ext === "") {
    try {
      const { buffer, raw } = await readContentRaw(
        kbRoot,
        shareLink.document_path,
      );
      const currentHash = hashBytes(buffer);
      if (currentHash !== shareLink.content_sha256) {
        logger.info(
          {
            event: "shared_content_mismatch",
            token,
            documentPath: shareLink.document_path,
            kind: "markdown",
          },
          "shared: content hash mismatch",
        );
        return contentChangedResponse();
      }
      const { content } = parseFrontmatter(raw);
      logger.info(
        { event: "shared_page_viewed", token, documentPath: shareLink.document_path },
        "shared: document viewed",
      );
      return NextResponse.json({
        content,
        path: shareLink.document_path,
      });
    } catch (err) {
      if (err instanceof KbAccessDeniedError) {
        logger.warn(
          { token, path: shareLink.document_path },
          "shared: path traversal attempt blocked",
        );
        return NextResponse.json({ error: "Access denied" }, { status: 403 });
      }
      if (err instanceof KbNotFoundError) {
        return NextResponse.json(
          { error: "Document no longer available" },
          { status: 404 },
        );
      }
      logger.error({ err, token }, "shared: unexpected error");
      return NextResponse.json(
        { error: "An unexpected error occurred" },
        { status: 500 },
      );
    }
  }

  // Binary branch.
  const binary = await readBinaryFile(kbRoot, shareLink.document_path);
  if (!binary.ok) {
    if (binary.status === 403) {
      logger.warn(
        { token, path: shareLink.document_path },
        "shared: binary access denied (symlink / outside root)",
      );
    }
    return NextResponse.json({ error: binary.error }, { status: binary.status });
  }

  const currentHash = hashBytes(binary.buffer);
  if (currentHash !== shareLink.content_sha256) {
    logger.info(
      {
        event: "shared_content_mismatch",
        token,
        documentPath: shareLink.document_path,
        kind: "binary",
      },
      "shared: content hash mismatch",
    );
    return contentChangedResponse();
  }

  logger.info(
    {
      event: "shared_page_viewed",
      token,
      documentPath: shareLink.document_path,
      contentType: binary.contentType,
    },
    "shared: document viewed",
  );
  return buildBinaryResponse(binary, request);
}
