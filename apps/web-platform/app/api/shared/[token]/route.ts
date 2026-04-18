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
  buildBinaryHeadResponse,
  build304Response,
  formatStrongETag,
  ifNoneMatchMatches,
  openBinaryStream,
  BinaryOpenError,
} from "@/server/kb-binary-response";
import { hashBytes, hashStream } from "@/server/kb-content-hash";
import {
  contentChangedResponse,
  serveKbFile,
  serveSharedBinaryWithHashGate,
  SHARED_CONTENT_KIND_HEADER,
} from "@/server/kb-serve";
import { shareHashVerdictCache } from "@/server/share-hash-verdict-cache";
import {
  shareEndpointThrottle,
  extractClientIpFromHeaders,
  logRateLimitRejection,
} from "@/server/rate-limiter";
import { isMarkdownKbPath } from "@/lib/kb-extensions";
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
    { status: 404, headers: { "Cache-Control": "no-store" } },
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
    { status: 410, headers: { "Cache-Control": "no-store" } },
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
 * For HEAD responses derived from a JSON-bodied error response, drop the
 * body-describing headers so the empty body is not accompanied by a
 * misleading Content-Type: application/json / Content-Length: N. All
 * other headers are preserved so HEAD clients can still act on them.
 */
function stripBodyHeadersFromResponse(source: Response): Response {
  const headers = new Headers(source.headers);
  headers.delete("Content-Type");
  headers.delete("Content-Length");
  return new Response(null, { status: source.status, headers });
}

type ShareRow = {
  document_path: string;
  revoked: boolean;
  content_sha256: string | null;
  users:
    | { workspace_path: string | null; workspace_status: string | null }
    | { workspace_path: string | null; workspace_status: string | null }[]
    | null;
};

/**
 * Run the rate-limit + share-lookup + null-hash + upstream If-None-Match
 * pre-gate pipeline. Returns an early Response for error / 304 paths or a
 * resolved share context (kbRoot + documentPath + strongETag + ownership
 * confirmed) for the dispatch branches.
 *
 * Both GET and HEAD delegate here so the security and 304 semantics never
 * drift.
 */
async function prepareSharedRequest(
  request: Request,
  token: string,
): Promise<
  | { kind: "response"; response: Response }
  | {
      kind: "ready";
      kbRoot: string;
      documentPath: string;
      contentSha256: string;
      strongETag: string;
    }
> {
  const clientIp = extractClientIpFromHeaders(request.headers);
  if (!shareEndpointThrottle.isAllowed(clientIp)) {
    logRateLimitRejection("share-endpoint", clientIp);
    return {
      kind: "response",
      response: NextResponse.json(
        { error: "Too many requests" },
        { status: 429, headers: { "Cache-Control": "no-store" } },
      ),
    };
  }

  const serviceClient = createServiceClient();
  const { data: shareLink, error: fetchError } = await serviceClient
    .from("kb_share_links")
    .select(
      "document_path, revoked, content_sha256, users!inner(workspace_path, workspace_status)",
    )
    .eq("token", token)
    .single<ShareRow>();

  if (fetchError || !shareLink) {
    return {
      kind: "response",
      response: NextResponse.json(
        { error: "Not found" },
        { status: 404, headers: { "Cache-Control": "no-store" } },
      ),
    };
  }

  if (shareLink.revoked) {
    return {
      kind: "response",
      response: NextResponse.json(
        { error: "This link has been disabled", code: "revoked" },
        { status: 410, headers: { "Cache-Control": "no-store" } },
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
  // filesystem validation, and the hash drain. Bandwidth AND work saved;
  // safe because a 304 reveals no bytes.
  const strongETag = formatStrongETag(shareLink.content_sha256);
  const ifNoneMatch = request.headers.get("if-none-match");
  if (ifNoneMatch && ifNoneMatchMatches(ifNoneMatch, strongETag)) {
    return {
      kind: "response",
      response: build304Response(strongETag, { scope: "public" }),
    };
  }

  const owner = Array.isArray(shareLink.users)
    ? shareLink.users[0]
    : shareLink.users;
  if (!owner?.workspace_path || owner.workspace_status !== "ready") {
    logSharedFailed(token, shareLink.document_path, "workspace-unavailable");
    return { kind: "response", response: notFoundResponse() };
  }

  return {
    kind: "ready",
    kbRoot: path.join(owner.workspace_path, "knowledge-base"),
    documentPath: shareLink.document_path,
    contentSha256: shareLink.content_sha256,
    strongETag,
  };
}

export async function GET(
  request: Request,
  { params }: { params: Promise<{ token: string }> },
) {
  const { token } = await params;
  const prepared = await prepareSharedRequest(request, token);
  if (prepared.kind === "response") return prepared.response;

  const { kbRoot, documentPath, contentSha256 } = prepared;

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

export async function HEAD(
  request: Request,
  { params }: { params: Promise<{ token: string }> },
) {
  const { token } = await params;
  const prepared = await prepareSharedRequest(request, token);
  if (prepared.kind === "response") {
    // HEAD must not carry a body (RFC 7231 §4.3.2). Preserve status +
    // non-body headers (Retry-After on 429, ETag/Cache-Control on 304);
    // strip Content-Type / Content-Length set by NextResponse.json.
    return stripBodyHeadersFromResponse(prepared.response);
  }

  const { kbRoot, documentPath, contentSha256, strongETag } = prepared;

  if (isMarkdownKbPath(documentPath)) {
    // Markdown HEAD: the client uses this to branch on kind before
    // issuing a follow-up GET. Preserve the same hash-gate that GET
    // applies so an HTTP 200 here never lies about a file that would
    // 410 on GET.
    try {
      const { buffer } = await readContentRaw(kbRoot, documentPath);
      const currentHash = hashBytes(buffer);
      if (currentHash !== contentSha256) {
        logger.info(
          {
            event: "shared_content_mismatch",
            token,
            documentPath,
            kind: "markdown",
          },
          "shared: content hash mismatch (head)",
        );
        return stripBodyHeadersFromResponse(contentChangedResponse());
      }
      logger.info(
        {
          event: "shared_page_head",
          token,
          documentPath,
          kind: "markdown",
        },
        "shared: document head",
      );
      return new Response(null, {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          [SHARED_CONTENT_KIND_HEADER]: "markdown",
        },
      });
    } catch (err) {
      return stripBodyHeadersFromResponse(
        mapSharedError(err, token, documentPath),
      );
    }
  }

  // Binary HEAD: run the same hash gate as GET (share verdict cache +
  // on-miss SHA-256 drain) so a mutated file 410s on HEAD and GET
  // consistently. buildBinaryHeadResponse opens zero fds on the 200 and
  // 304 paths.
  try {
    const binary = await validateBinaryFile(kbRoot, documentPath);
    const cachedVerdict = shareHashVerdictCache.get(
      token,
      binary.ino,
      binary.mtimeMs,
      binary.size,
    );

    if (cachedVerdict !== true) {
      let currentHash: string;
      try {
        const stream = await openBinaryStream(binary.filePath, {
          expected: { ino: binary.ino, size: binary.size },
        });
        currentHash = await hashStream(stream);
      } catch (err) {
        if (err instanceof BinaryOpenError && err.code === "content-changed") {
          logger.info(
            {
              event: "shared_content_mismatch",
              token,
              documentPath,
              kind: "binary",
              reason: "inode-drift-head",
            },
            "shared: inode drift between validate and hash (head)",
          );
          return stripBodyHeadersFromResponse(contentChangedResponse());
        }
        throw err;
      }
      if (currentHash !== contentSha256) {
        logger.info(
          {
            event: "shared_content_mismatch",
            token,
            documentPath,
            kind: "binary",
            reason: "hash-mismatch-head",
          },
          "shared: content hash mismatch (head)",
        );
        return stripBodyHeadersFromResponse(contentChangedResponse());
      }
      shareHashVerdictCache.set(token, binary.ino, binary.mtimeMs, binary.size);
    }

    logger.info(
      {
        event: "shared_page_head",
        token,
        documentPath,
        contentType: binary.contentType,
        cached: cachedVerdict === true,
        kind: "binary",
      },
      "shared: document head",
    );
    return buildBinaryHeadResponse(binary, request, {
      strongETag,
      scope: "public",
    });
  } catch (err) {
    return stripBodyHeadersFromResponse(
      mapSharedError(err, token, documentPath),
    );
  }
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
