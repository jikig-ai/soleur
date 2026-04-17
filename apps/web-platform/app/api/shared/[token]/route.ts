import { NextResponse } from "next/server";
import path from "node:path";
import { createServiceClient } from "@/lib/supabase/server";
import {
  readContentRaw,
  parseFrontmatter,
  KbNotFoundError,
  KbAccessDeniedError,
} from "@/server/kb-reader";
import { validateBinaryFile } from "@/server/kb-binary-response";
import { hashBytes } from "@/server/kb-content-hash";
import {
  contentChangedResponse,
  serveKbFile,
  serveBinaryWithHashGate,
} from "@/server/kb-serve";
import {
  shareEndpointThrottle,
  extractClientIpFromHeaders,
  logRateLimitRejection,
} from "@/server/rate-limiter";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";

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

  return serveKbFile(kbRoot, shareLink.document_path, {
    request,
    onMarkdown: async (root, rel) => {
      try {
        const { buffer, raw } = await readContentRaw(root, rel);
        const currentHash = hashBytes(buffer);
        if (currentHash !== shareLink.content_sha256) {
          logger.info(
            {
              event: "shared_content_mismatch",
              token,
              documentPath: rel,
              kind: "markdown",
            },
            "shared: content hash mismatch",
          );
          return contentChangedResponse();
        }
        const { content } = parseFrontmatter(raw);
        logger.info(
          { event: "shared_page_viewed", token, documentPath: rel },
          "shared: document viewed",
        );
        return NextResponse.json({
          content,
          path: rel,
        });
      } catch (err) {
        if (err instanceof KbAccessDeniedError) {
          logger.warn(
            { token, path: rel },
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
        Sentry.captureException(err, {
          tags: { feature: "shared-token" },
          extra: { token },
        });
        return NextResponse.json(
          { error: "An unexpected error occurred" },
          { status: 500 },
        );
      }
    },
    onBinary: async (root, rel) => {
      const binary = await validateBinaryFile(root, rel);
      if (!binary.ok) {
        if (binary.status === 403) {
          logger.warn(
            { token, path: rel },
            "shared: binary access denied (symlink / outside root)",
          );
        }
        return NextResponse.json(
          { error: binary.error },
          { status: binary.status },
        );
      }
      return serveBinaryWithHashGate({
        token,
        expectedHash: shareLink.content_sha256,
        meta: binary,
        request,
        logger,
        logContext: { token, documentPath: rel },
      });
    },
  });
}
