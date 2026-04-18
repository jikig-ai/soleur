import type { Logger } from "pino";
import { NextResponse } from "next/server";
import { isMarkdownKbPath } from "@/lib/kb-extensions";
import {
  KbAccessDeniedError,
  KbFileTooLargeError,
  KbNotFoundError,
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
import { hashStream } from "@/server/kb-content-hash";
import { shareHashVerdictCache } from "@/server/share-hash-verdict-cache";
import { reportSilentFallback } from "@/server/observability";

// 410 response shared between the markdown and binary branches of the share
// route. Extracted here so serveSharedBinaryWithHashGate can use it without
// the route re-exporting a helper (Next.js route-file export validator allows
// only HTTP method handlers from app/**/route.ts).
export function contentChangedResponse(): Response {
  return NextResponse.json(
    {
      error: "The shared file has been modified since it was shared.",
      code: "content-changed",
    },
    { status: 410, headers: { "Cache-Control": "no-store" } },
  );
}

/**
 * Serve a binary KB file with default owner-route semantics: validate
 * metadata, stream bytes with weak ETag / Range / 304 support. onError is
 * invoked on every non-ok branch so callers can emit their own structured
 * log lines; it is NOT a short-circuit (the caller's log is a side effect,
 * the helper still returns the standard JSON error Response).
 */
export async function serveBinary(
  kbRoot: string,
  relativePath: string,
  opts: {
    request: Request;
    onError?: (status: number, reason: string, code?: string) => void;
  },
): Promise<Response> {
  let meta: BinaryFileMetadata;
  try {
    meta = await validateBinaryFile(kbRoot, relativePath);
  } catch (err) {
    if (err instanceof KbAccessDeniedError) {
      opts.onError?.(403, "Access denied");
      return NextResponse.json({ error: "Access denied" }, { status: 403 });
    }
    if (err instanceof KbNotFoundError) {
      opts.onError?.(404, "File not found");
      return NextResponse.json({ error: "File not found" }, { status: 404 });
    }
    if (err instanceof KbFileTooLargeError) {
      opts.onError?.(413, err.message);
      return NextResponse.json({ error: err.message }, { status: 413 });
    }
    throw err;
  }
  try {
    return await buildBinaryResponse(meta, opts.request);
  } catch (err) {
    if (err instanceof BinaryOpenError) {
      opts.onError?.(err.status, err.message, err.code);
      return NextResponse.json(
        { error: err.message },
        { status: err.status },
      );
    }
    throw err;
  }
}

/**
 * Dispatch a KB request to markdown or binary handler by extension. Both
 * handlers are required — callers decide their own error-logging and
 * response-shaping, so the dispatcher has nothing sensible to default to.
 */
export async function serveKbFile(
  kbRoot: string,
  relativePath: string,
  opts: {
    request: Request;
    onMarkdown: (kbRoot: string, relativePath: string) => Promise<Response>;
    onBinary: (kbRoot: string, relativePath: string) => Promise<Response>;
  },
): Promise<Response> {
  if (isMarkdownKbPath(relativePath)) {
    return opts.onMarkdown(kbRoot, relativePath);
  }
  return opts.onBinary(kbRoot, relativePath);
}

export interface HashGateLogContext {
  token: string;
  documentPath: string;
}

// Verdict-cache + hash-stream + serve orchestration for SHARED binary files
// (i.e., accessed via /api/shared/[token], not the owner route). Returns ONLY
// a Response — no side-channel fields. Log emission happens inside the helper
// using the caller's logger so field names, events, and codes stay exact
// (observability dashboards and SIEM filters key off these strings).
//
// Caller has already run validateBinaryFile to obtain meta. Throws from the
// validate step are the caller's responsibility so KB error mapping stays
// consistent across markdown and binary branches.
export async function serveSharedBinaryWithHashGate(args: {
  expectedHash: string;
  meta: BinaryFileMetadata;
  request: Request;
  logger: Logger;
  logContext: HashGateLogContext;
}): Promise<Response> {
  const { expectedHash, meta, request, logger, logContext } = args;
  const { token, documentPath } = logContext;
  const cachedVerdict = shareHashVerdictCache.get(
    token,
    meta.ino,
    meta.mtimeMs,
    meta.size,
  );

  if (cachedVerdict !== true) {
    const hashResult = await hashAndVerify(meta, expectedHash);
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
    shareHashVerdictCache.set(token, meta.ino, meta.mtimeMs, meta.size);
  }

  logger.info(
    {
      event: "shared_page_viewed",
      token,
      documentPath,
      kind: deriveBinaryKind(meta),
      contentType: meta.contentType,
      cached: cachedVerdict === true,
    },
    "shared: document viewed",
  );
  try {
    return await buildBinaryResponse(meta, request, {
      strongETag: expectedHash,
      scope: "public",
    });
  } catch (err) {
    if (err instanceof BinaryOpenError && err.code === "content-changed") {
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
    if (err instanceof BinaryOpenError) {
      logger.warn(
        { err: err.message, code: err.code, token, path: documentPath },
        "shared: binary open failed",
      );
      reportSilentFallback(err, {
        feature: "shared-token",
        op: "serve",
        extra: { token, documentPath },
      });
      return NextResponse.json(
        { error: err.message },
        { status: err.status },
      );
    }
    throw err;
  }
}

// Hash the currently-on-disk bytes and compare to the stored hash. Returns
// "match" on success, a reason string on mismatch (surfaces in the
// shared_content_mismatch log). Re-throws unexpected errors so the route-
// level mapSharedError catch can map them to HTTP responses.
async function hashAndVerify(
  meta: BinaryFileMetadata,
  expectedHash: string,
): Promise<"match" | "inode-drift" | "hash-mismatch"> {
  let currentHash: string;
  try {
    const stream = await openBinaryStream(meta.filePath, {
      expected: { ino: meta.ino, size: meta.size },
    });
    currentHash = await hashStream(stream);
  } catch (err) {
    if (err instanceof BinaryOpenError && err.code === "content-changed") {
      return "inode-drift";
    }
    throw err;
  }
  return currentHash === expectedHash ? "match" : "hash-mismatch";
}

// Re-export for caller convenience (share route uses the header on markdown
// responses too, so keeping kb-serve.ts as the single import site for all
// KB-serving primitives shrinks the route's import block).
export { SHARED_CONTENT_KIND_HEADER };
