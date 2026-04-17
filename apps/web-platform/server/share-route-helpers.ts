// Shared resolution pipeline for GET and HEAD on /api/shared/[token].
//
// Lives in a sibling module — not inside app/api/shared/[token]/route.ts —
// to stay inside the Next.js App Router route-file export allowlist
// (cq-nextjs-route-files-http-only-exports). The route file may export
// only HTTP method handlers.
//
// Returns a tagged-union result so GET and HEAD can reuse the same
// rate-limit + share-lookup + content-hash-gate pipeline without
// duplicating the cascade of 404 / 410 / 403 / 429 / 500 responses.

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
  openBinaryStream,
  BinaryOpenError,
  build304Response,
  formatStrongETag,
  ifNoneMatchMatches,
  deriveBinaryKind,
  SHARED_CONTENT_KIND_HEADER,
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

export function contentChangedResponse(): Response {
  return NextResponse.json(
    {
      error: "The shared file has been modified since it was shared.",
      code: "content-changed",
    },
    { status: 410 },
  );
}

function legacyNullHashResponse(): Response {
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

/**
 * Hash the currently-on-disk bytes and compare to the stored hash. Returns
 * "match" on success, a reason string on mismatch (surfaces in the
 * shared_content_mismatch log), and re-throws non-inode-drift errors so
 * the route-level catch can map them to HTTP responses.
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

export function mapSharedError(
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

export type ShareServeResolution =
  | { kind: "response"; response: Response }
  | {
      kind: "markdown";
      content: string;
      documentPath: string;
    }
  | {
      kind: "binary";
      payload: BinaryFileMetadata;
      strongETag: string;
      documentPath: string;
      cached: boolean;
    };

/**
 * Run the shared rate-limit + share-lookup + hash-gate pipeline. On
 * error paths returns `{ kind: "response", response }` with the final
 * Response already built — the caller just returns it. On the happy
 * path returns either `markdown` (with parsed content) or `binary`
 * (with a validated payload) so GET and HEAD diverge only on the body-
 * emission step.
 *
 * Emits a 304 upstream when the client's If-None-Match matches the
 * share's stored content_sha256 — saving one owner lookup, one
 * validateBinaryFile fstat, and on cold-verdict a full hash drain.
 */
export async function resolveShareForServe(
  request: Request,
  token: string,
): Promise<ShareServeResolution> {
  // Rate limiting — must precede any filesystem / hash work to avoid DoS
  // via repeated 50 MB hashing requests. HEAD counts against the same
  // budget as GET since it runs the same pipeline.
  const clientIp = extractClientIpFromHeaders(request.headers);
  if (!shareEndpointThrottle.isAllowed(clientIp)) {
    logRateLimitRejection("share-endpoint", clientIp);
    return {
      kind: "response",
      response: NextResponse.json(
        { error: "Too many requests" },
        { status: 429 },
      ),
    };
  }

  const serviceClient = createServiceClient();

  // Single round-trip: PostgREST embedded resource pulls the owner row via
  // the FK `kb_share_links.user_id -> users.id`.
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
    return {
      kind: "response",
      response: NextResponse.json({ error: "Not found" }, { status: 404 }),
    };
  }

  if (shareLink.revoked) {
    return {
      kind: "response",
      response: NextResponse.json(
        { error: "This link has been disabled", code: "revoked" },
        { status: 410 },
      ),
    };
  }

  if (!shareLink.content_sha256) {
    logger.warn(
      { event: "shared_legacy_null_hash", token, documentPath: shareLink.document_path },
      "shared: legacy row without content hash",
    );
    return { kind: "response", response: legacyNullHashResponse() };
  }

  // If-None-Match fast path: the share row's content_sha256 is the
  // strong ETag we would emit on a 200. When the client already has a
  // matching validator, short-circuit to 304 — skipping owner lookup,
  // filesystem validation, and the hash drain. Bandwidth AND work
  // saved; safe because a 304 reveals no bytes.
  const strongETag = formatStrongETag(shareLink.content_sha256);
  const ifNoneMatch = request.headers.get("if-none-match");
  if (ifNoneMatch && ifNoneMatchMatches(ifNoneMatch, strongETag)) {
    return { kind: "response", response: build304Response(strongETag) };
  }

  const owner = Array.isArray(shareLink.users)
    ? shareLink.users[0]
    : shareLink.users;
  if (!owner?.workspace_path || owner.workspace_status !== "ready") {
    logSharedFailed(token, shareLink.document_path, "workspace-unavailable");
    return {
      kind: "response",
      response: NextResponse.json(
        { error: "Document no longer available" },
        { status: 404 },
      ),
    };
  }

  const kbRoot = path.join(owner.workspace_path, "knowledge-base");
  const ext = path.extname(shareLink.document_path).toLowerCase();
  const contentSha256 = shareLink.content_sha256;
  const documentPath = shareLink.document_path;

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
        return { kind: "response", response: contentChangedResponse() };
      }
      const { content } = parseFrontmatter(raw);
      return { kind: "markdown", content, documentPath };
    } catch (err) {
      return { kind: "response", response: mapSharedError(err, token, documentPath) };
    }
  }

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
        return { kind: "response", response: contentChangedResponse() };
      }
      shareHashVerdictCache.set(token, binary.ino, binary.mtimeMs, binary.size);
    }

    return {
      kind: "binary",
      payload: binary,
      strongETag: contentSha256,
      documentPath,
      cached: cachedVerdict === true,
    };
  } catch (err) {
    return { kind: "response", response: mapSharedError(err, token, documentPath) };
  }
}

/**
 * For HEAD responses derived from a JSON-bodied error response, drop the
 * body-describing headers so the empty body is not accompanied by a
 * misleading Content-Type: application/json / Content-Length: N. All
 * other headers (e.g., Retry-After, X-RateLimit-*) are preserved so HEAD
 * clients can still act on them.
 */
export function stripBodyHeaders(source: Headers): Headers {
  const headers = new Headers(source);
  headers.delete("Content-Type");
  headers.delete("Content-Length");
  return headers;
}
