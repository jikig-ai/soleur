import { NextResponse } from "next/server";
import path from "node:path";
import { createServiceClient } from "@/lib/supabase/server";
import {
  readContent,
  KbNotFoundError,
  KbAccessDeniedError,
} from "@/server/kb-reader";
import {
  readBinaryFile,
  buildBinaryResponse,
} from "@/server/kb-binary-response";
import {
  shareEndpointThrottle,
  extractClientIpFromHeaders,
  logRateLimitRejection,
} from "@/server/rate-limiter";
import logger from "@/server/logger";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ token: string }> },
) {
  // Rate limiting.
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
    .select("document_path, user_id, revoked")
    .eq("token", token)
    .single();

  if (fetchError || !shareLink) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  if (shareLink.revoked) {
    return NextResponse.json(
      { error: "This link has been disabled" },
      { status: 410 },
    );
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

  // Fork on extension. Markdown (or extensionless) uses readContent and
  // returns JSON as before; everything else streams the binary via the
  // shared helper. Point-of-use path containment + symlink + size guards
  // are re-validated inside readBinaryFile, per the service-role-idor
  // learning — don't trust that the owner's stored document_path is safe.
  if (ext === ".md" || ext === "") {
    try {
      const result = await readContent(kbRoot, shareLink.document_path);
      logger.info(
        { event: "shared_page_viewed", token, documentPath: shareLink.document_path },
        "shared: document viewed",
      );
      return NextResponse.json({
        content: result.content,
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
