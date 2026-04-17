import { NextResponse } from "next/server";
import path from "node:path";
import { createServiceClient } from "@/lib/supabase/server";
import {
  readContentRaw,
  parseFrontmatter,
  KbNotFoundError,
  KbAccessDeniedError,
  KbFileTooLargeError,
} from "@/server/kb-reader";
import {
  validateBinaryFile,
  BinaryOpenError,
} from "@/server/kb-binary-response";
import { hashBytes } from "@/server/kb-content-hash";
import {
  contentChangedResponse,
  serveKbFile,
  serveSharedBinaryWithHashGate,
  SHARED_CONTENT_KIND_HEADER,
} from "@/server/kb-serve";
import {
  shareEndpointThrottle,
  extractClientIpFromHeaders,
  logRateLimitRejection,
} from "@/server/rate-limiter";
import logger from "@/server/logger";
import { reportSilentFallback } from "@/server/observability";

// Opaque public-facing 404 copy. Used by every 404 path on this endpoint —
// missing workspace and missing file (markdown or binary, surfaced through
// KbNotFoundError by kb-reader/validateBinaryFile). Centralizes the string
// so a future drift in one branch cannot silently break the privacy posture.
const SHARED_NOT_FOUND_MESSAGE = "Document no longer available";

function notFoundResponse() {
  return NextResponse.json(
    { error: SHARED_NOT_FOUND_MESSAGE },
    { status: 404 },
  );
}

// Kept route-private (not in kb-serve.ts) because "legacy-null-hash" is a
// share-specific migration artifact: only pre-#2326 share rows can carry a
// null content_sha256. contentChangedResponse, by contrast, lives in
// kb-serve.ts because any hash-gated flow can emit it.
function legacyNullHashResponse() {
  return NextResponse.json(
    {
      error: "This link is from an older share system and is no longer valid.",
      code: "legacy-null-hash",
    },
    { status: 410 },
  );
}

function logSharedFailed(
  token: string,
  documentPath: string,
  reason: string,
  extra?: Record<string, unknown>,
): void {
  logger.info(
    { event: "shared_page_failed", token, documentPath, reason, ...extra },
    "shared: request failed",
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

  // Single round-trip: PostgREST embedded resource pulls the owner row via
  // the FK `kb_share_links.user_id -> users.id` (see migration 017). Saves
  // one Supabase network hop per view vs. the previous sequential pair.
  const { data: shareLink, error: fetchError } = await serviceClient
    .from("kb_share_links")
    .select(
      "document_path, revoked, content_sha256, users!inner(workspace_path, workspace_status)",
    )
    .eq("token", token)
    .single<{
      document_path: string;
      revoked: boolean;
      content_sha256: string | null;
      users:
        | { workspace_path: string | null; workspace_status: string | null }
        | { workspace_path: string | null; workspace_status: string | null }[]
        | null;
    }>();

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

  const owner = Array.isArray(shareLink.users)
    ? shareLink.users[0]
    : shareLink.users;
  if (!owner?.workspace_path || owner.workspace_status !== "ready") {
    logSharedFailed(token, shareLink.document_path, "workspace-unavailable");
    return notFoundResponse();
  }

  const kbRoot = path.join(owner.workspace_path, "knowledge-base");
  const contentSha256 = shareLink.content_sha256;
  const documentPath = shareLink.document_path;

  return serveKbFile(kbRoot, documentPath, {
    request,
    onMarkdown: async (root, rel) => {
      try {
        const { buffer, raw } = await readContentRaw(root, rel);
        const currentHash = hashBytes(buffer);
        if (currentHash !== contentSha256) {
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
          {
            event: "shared_page_viewed",
            token,
            documentPath: rel,
            kind: "markdown",
          },
          "shared: document viewed",
        );
        return NextResponse.json(
          { content, path: rel },
          { headers: { [SHARED_CONTENT_KIND_HEADER]: "markdown" } },
        );
      } catch (err) {
        return mapSharedError(err, token, rel);
      }
    },
    onBinary: async (root, rel) => {
      try {
        const binary = await validateBinaryFile(root, rel);
        return await serveSharedBinaryWithHashGate({
          expectedHash: contentSha256,
          meta: binary,
          request,
          logger,
          logContext: { token, documentPath: rel },
        });
      } catch (err) {
        return mapSharedError(err, token, rel);
      }
    },
  });
}

function mapSharedError(
  err: unknown,
  token: string,
  documentPath: string,
): Response {
  if (err instanceof KbAccessDeniedError) {
    logger.warn(
      { token, path: documentPath },
      "shared: access denied (null byte / symlink / traversal)",
    );
    logSharedFailed(token, documentPath, "access-denied");
    return NextResponse.json({ error: "Access denied" }, { status: 403 });
  }
  if (err instanceof KbNotFoundError) {
    logSharedFailed(token, documentPath, "not-found");
    return notFoundResponse();
  }
  if (err instanceof KbFileTooLargeError) {
    logSharedFailed(token, documentPath, "file-too-large");
    return NextResponse.json({ error: err.message }, { status: 413 });
  }
  if (err instanceof BinaryOpenError) {
    if (err.code === "content-changed") {
      logger.info(
        {
          event: "shared_content_mismatch",
          token,
          documentPath,
          kind: "binary",
          reason: "inode-drift-serve",
        },
        "shared: inode drift between hash and serve",
      );
      return contentChangedResponse();
    }
    logger.warn(
      { err: err.message, code: err.code, token, path: documentPath },
      "shared: binary open failed",
    );
    logSharedFailed(token, documentPath, `binary-open:${err.code ?? "unknown"}`);
    return NextResponse.json({ error: err.message }, { status: err.status });
  }
  reportSilentFallback(err, {
    feature: "shared-token",
    op: "serve",
    extra: { token, documentPath },
  });
  return NextResponse.json(
    { error: "An unexpected error occurred" },
    { status: 500 },
  );
}
