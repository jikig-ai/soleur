import type { Logger } from "pino";
import { NextResponse } from "next/server";
import { isMarkdownKbPath } from "@/lib/kb-extensions";
import {
  validateBinaryFile,
  buildBinaryResponse,
  openBinaryStream,
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
    { status: 410 },
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
  const result = await validateBinaryFile(kbRoot, relativePath);
  if (!result.ok) {
    opts.onError?.(result.status, result.error);
    return NextResponse.json(
      { error: result.error },
      { status: result.status },
    );
  }
  try {
    return await buildBinaryResponse(result, opts.request);
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
    let currentHash: string;
    try {
      const stream = await openBinaryStream(meta.filePath, {
        expected: { ino: meta.ino, size: meta.size },
      });
      currentHash = await hashStream(stream);
    } catch (err) {
      if (err instanceof BinaryOpenError) {
        if (err.code === "content-changed") {
          logger.info(
            {
              event: "shared_content_mismatch",
              token,
              documentPath,
              kind: "binary",
              reason: "inode-drift",
            },
            "shared: inode drift between validate and hash",
          );
          return contentChangedResponse();
        }
        logger.warn(
          {
            err: err.message,
            code: err.code,
            token,
            path: documentPath,
          },
          "shared: open failed on hash pass",
        );
        reportSilentFallback(err, {
          feature: "shared-token",
          op: "hash-gate",
          extra: { token, documentPath },
        });
        return NextResponse.json(
          { error: err.message },
          { status: err.status },
        );
      }
      logger.error(
        { err, token, path: documentPath },
        "shared: hash stream drain failed",
      );
      reportSilentFallback(err, {
        feature: "shared-token",
        op: "hash-gate",
        extra: { token, documentPath },
      });
      return NextResponse.json(
        { error: "An unexpected error occurred" },
        { status: 500 },
      );
    }
    if (currentHash !== expectedHash) {
      logger.info(
        {
          event: "shared_content_mismatch",
          token,
          documentPath,
          kind: "binary",
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
      contentType: meta.contentType,
      cached: cachedVerdict === true,
    },
    "shared: document viewed",
  );
  try {
    return await buildBinaryResponse(meta, request, {
      strongETag: expectedHash,
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
        "shared: open failed on serve",
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
