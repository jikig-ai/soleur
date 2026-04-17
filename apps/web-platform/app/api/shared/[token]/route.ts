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
  buildBinaryResponse,
  openBinaryStream,
  deriveBinaryKind,
  SHARED_CONTENT_KIND_HEADER,
  BinaryOpenError,
  type BinaryFileMetadata,
} from "@/server/kb-binary-response";
import { hashBytes, hashStream } from "@/server/kb-content-hash";
import { shareHashVerdictCache } from "@/server/share-hash-verdict-cache";
import {
  shareEndpointThrottle,
  extractClientIpFromHeaders,
  logRateLimitRejection,
} from "@/server/rate-limiter";
import logger from "@/server/logger";
import { reportSilentFallback } from "@/server/observability";

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
      // PostgREST embedded many-to-one returns a single object; some
      // client/server-type combinations surface it as an array. Normalize
      // below so the route is robust to both shapes.
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
    // Legacy row from before content-hash binding. Treat as invalid — the
    // migration should have revoked these, but belt-and-suspenders.
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
    return NextResponse.json(
      { error: "Document no longer available" },
      { status: 404 },
    );
  }

  const kbRoot = path.join(owner.workspace_path, "knowledge-base");
  const ext = path.extname(shareLink.document_path).toLowerCase();
  const contentSha256 = shareLink.content_sha256;
  const documentPath = shareLink.document_path;

  // Markdown / extensionless branch.
  if (ext === ".md" || ext === "") {
    try {
      const { buffer, raw } = await readContentRaw(kbRoot, documentPath);
      const currentHash = hashBytes(buffer);
      if (currentHash !== contentSha256) {
        logger.info(
          {
            event: "shared_content_mismatch",
            token,
            documentPath,
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
          documentPath,
          kind: "markdown",
        },
        "shared: document viewed",
      );
      return NextResponse.json(
        { content, path: documentPath },
        { headers: { [SHARED_CONTENT_KIND_HEADER]: "markdown" } },
      );
    } catch (err) {
      return mapSharedError(err, token, documentPath);
    }
  }

  // Binary branch — validate metadata without reading bytes, then either
  // trust the verdict cache (fast path) or hash via a fresh stream before
  // serving (slow path: first view OR file mutated since last verify).
  try {
    const binary = await validateBinaryFile(kbRoot, documentPath);

    const cachedVerdict = shareHashVerdictCache.get(
      token,
      binary.ino,
      binary.mtimeMs,
      binary.size,
    );

    if (cachedVerdict !== true) {
      const hashResult = await hashAndVerify(binary, contentSha256);
      if (hashResult !== "match") {
        logger.info(
          {
            event: "shared_content_mismatch",
            token,
            documentPath,
            kind: "binary",
            reason: hashResult,
          },
          "shared: content hash mismatch",
        );
        return contentChangedResponse();
      }
      shareHashVerdictCache.set(token, binary.ino, binary.mtimeMs, binary.size);
    }

    logger.info(
      {
        event: "shared_page_viewed",
        token,
        documentPath,
        kind: deriveBinaryKind(binary),
        contentType: binary.contentType,
        cached: cachedVerdict === true,
      },
      "shared: document viewed",
    );
    return await buildBinaryResponse(binary, request, {
      // Strong ETag from the stored content hash: a repeat view with a
      // matching If-None-Match returns 304 without re-opening the fd.
      strongETag: contentSha256,
    });
  } catch (err) {
    return mapSharedError(err, token, documentPath);
  }
}

/**
 * Hash the currently-on-disk bytes and compare to the stored hash. Returns
 * "match" on success, a reason string on mismatch (surfaces in the
 * shared_content_mismatch log), and re-throws `BinaryOpenError` /
 * KB errors so the route-level catch can map them to HTTP responses.
 */
async function hashAndVerify(
  meta: BinaryFileMetadata,
  expectedHash: string,
): Promise<"match" | "inode-drift" | "hash-mismatch"> {
  let currentHash: string;
  try {
    const hashStreamObj = await openBinaryStream(meta.filePath, {
      expected: { ino: meta.ino, size: meta.size },
    });
    currentHash = await hashStream(hashStreamObj);
  } catch (err) {
    if (err instanceof BinaryOpenError && err.code === "content-changed") {
      return "inode-drift";
    }
    throw err;
  }
  return currentHash === expectedHash ? "match" : "hash-mismatch";
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
    return NextResponse.json(
      { error: "Document no longer available" },
      { status: 404 },
    );
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
  // Unknown error — mirror to Sentry so the silent-fallback rule is honored.
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
