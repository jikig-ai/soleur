import fs from "node:fs";
import path from "node:path";
import { Readable } from "node:stream";
import { isPathInWorkspace } from "@/server/sandbox";
import { KB_BINARY_RESPONSE_CSP } from "@/lib/kb-csp";
import {
  KbAccessDeniedError,
  KbFileTooLargeError,
  KbNotFoundError,
} from "@/server/kb-reader";
import {
  SHARED_CONTENT_KIND_HEADER,
  type SharedContentKind,
} from "@/lib/shared-kind";
import { MAX_BINARY_SIZE, CONTENT_TYPE_MAP } from "@/server/kb-limits";
import { classifyByContentType } from "@/lib/kb-file-kind";
import { getKbExtension } from "@/lib/kb-extensions";

export { SHARED_CONTENT_KIND_HEADER };
export type { SharedContentKind };

/**
 * Derive the shared-content kind from validated binary metadata.
 * Thin re-export over `classifyByContentType` so the `X-Soleur-Kind`
 * header and the client-side viewer share a single classifier. The
 * classifier's return type excludes `"markdown"` — markdown is served
 * via a separate JSON path and never flows through this module.
 */
export function deriveBinaryKind(
  meta: Pick<BinaryFileMetadata, "contentType" | "disposition">,
): Exclude<SharedContentKind, "markdown"> {
  return classifyByContentType(meta.contentType, meta.disposition);
}

/**
 * Validated metadata from validateBinaryFile. Carries (ino, mtimeMs, size)
 * so callers of openBinaryStream can pass `expected` and reject a second
 * open if the underlying inode drifted between validation and serve. This
 * closes the TOCTOU window that would otherwise open between two separate
 * fds on the same path.
 */
export interface BinaryFileMetadata {
  filePath: string;
  ino: number;
  size: number;
  mtimeMs: number;
  contentType: string;
  disposition: "inline" | "attachment";
  rawName: string;
}

export class BinaryOpenError extends Error {
  constructor(
    public readonly status: 403 | 404 | 500 | 503,
    message: string,
    public readonly code?: string,
  ) {
    super(message);
    this.name = "BinaryOpenError";
  }
}

export function formatContentDisposition(
  disposition: "inline" | "attachment",
  rawName: string,
): string {
  const asciiFallback = rawName.replace(/[^\x20-\x7e]/g, "_").replace(/["\r\n\\]/g, "_");
  const utf8Encoded = encodeURIComponent(rawName)
    .replace(/['()]/g, escape);
  return `${disposition}; filename="${asciiFallback}"; filename*=UTF-8''${utf8Encoded}`;
}

/**
 * Validate a KB-relative path and collect metadata. Opens with O_NOFOLLOW
 * to refuse symlinks, fstats against the held fd to capture ino/size/mtimeMs,
 * then closes the fd and returns metadata only — no bytes in memory.
 *
 * Response bodies are opened separately via `openBinaryStream(filePath,
 * { expected: { ino, size } })`. The `expected` tuple guards against a
 * rename-swap TOCTOU between validate and serve: if the second fd points
 * at a different inode or size, openBinaryStream throws BinaryOpenError.
 *
 * Throws:
 * - `KbAccessDeniedError` for null bytes, paths outside the workspace,
 *   symlinks (ELOOP/EMLINK), non-regular files, and EACCES/EPERM.
 * - `KbFileTooLargeError` when the file exceeds `MAX_BINARY_SIZE`.
 * - `KbNotFoundError` for ENOENT (and any other open failure that does
 *   not map to one of the classes above).
 *
 * Error-shape mirrors `readContent` / `readContentRaw` in `kb-reader.ts`
 * so both routes dispatch via a single `instanceof` chain.
 */
export async function validateBinaryFile(
  kbRoot: string,
  relativePath: string,
): Promise<BinaryFileMetadata> {
  if (relativePath.includes("\0")) {
    throw new KbAccessDeniedError();
  }
  const fullPath = path.join(kbRoot, relativePath);
  if (!isPathInWorkspace(fullPath, kbRoot)) {
    throw new KbAccessDeniedError();
  }
  let handle: fs.promises.FileHandle;
  try {
    handle = await fs.promises.open(
      fullPath,
      fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW,
    );
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code === "ELOOP" || code === "EMLINK") {
      throw new KbAccessDeniedError();
    }
    if (code === "EACCES" || code === "EPERM") {
      throw new KbAccessDeniedError();
    }
    throw new KbNotFoundError();
  }
  try {
    const stat = await handle.stat();
    if (!stat.isFile()) {
      throw new KbAccessDeniedError();
    }
    if (stat.size > MAX_BINARY_SIZE) {
      throw new KbFileTooLargeError();
    }
    const ext = getKbExtension(relativePath);
    const contentType = CONTENT_TYPE_MAP[ext] || "application/octet-stream";
    // Inline the single attachment-only check. Extend via kb-file-kind.ts
    // (classifyByExtension) when adding more attachment-only types.
    const disposition = ext === ".docx" ? "attachment" : "inline";
    const rawName = path.basename(relativePath);
    return {
      filePath: fullPath,
      ino: stat.ino,
      size: stat.size,
      mtimeMs: stat.mtimeMs,
      contentType,
      disposition,
      rawName,
    };
  } finally {
    await handle.close().catch(() => {});
  }
}

/**
 * Open a fresh O_NOFOLLOW read stream for a filePath previously validated
 * by validateBinaryFile. The returned Node Readable is backed by the
 * opened FileHandle with autoClose: true — fd lifetime is tied to the
 * stream.
 *
 * Pass `expected: { ino, size }` to close the TOCTOU window: if the
 * freshly opened fd points at a different inode or the size changed, the
 * stream is closed and a BinaryOpenError("content-changed") is thrown.
 * Callers that know the expected inode (from a prior validateBinaryFile)
 * SHOULD pass it; callers that do not (e.g., a path the caller just
 * validated inline) MAY omit it.
 *
 * Caller remains responsible for running path containment checks
 * (isPathInWorkspace) BEFORE invoking this helper — openBinaryStream
 * trusts filePath and only enforces O_NOFOLLOW + optional inode identity.
 */
export async function openBinaryStream(
  filePath: string,
  opts?: { start?: number; end?: number; expected?: { ino: number; size: number } },
): Promise<Readable> {
  let handle: fs.promises.FileHandle;
  try {
    handle = await fs.promises.open(
      filePath,
      fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW,
    );
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code === "ENOENT") {
      throw new BinaryOpenError(404, "File not found", code);
    }
    if (code === "ELOOP" || code === "EMLINK") {
      throw new BinaryOpenError(403, "Access denied", code);
    }
    if (code === "EACCES" || code === "EPERM") {
      throw new BinaryOpenError(403, "Access denied", code);
    }
    if (code === "EMFILE" || code === "ENFILE") {
      throw new BinaryOpenError(503, "Server is out of file descriptors", code);
    }
    throw new BinaryOpenError(500, "Failed to open file", code);
  }
  if (opts?.expected) {
    const stat = await handle.stat().catch(() => null);
    if (!stat || stat.ino !== opts.expected.ino || stat.size !== opts.expected.size) {
      await handle.close().catch(() => {});
      throw new BinaryOpenError(
        404,
        "File changed between validation and read",
        "content-changed",
      );
    }
  }
  return handle.createReadStream({
    autoClose: true,
    start: opts?.start,
    end: opts?.end,
  });
}

/**
 * Build an ETag for a binary response. Strong ETag (caller-supplied
 * content hash, e.g. `kb_share_links.content_sha256`) is used verbatim
 * inside double quotes. Otherwise a weak ETag is derived from the fstat
 * tuple `W/"<ino>-<size>-<mtimeMs>"` — cheap, stable for unchanged
 * content, and invalidates on any mutation tracked by fstat.
 */
function buildETag(meta: BinaryFileMetadata, strongETag?: string): string {
  if (strongETag) return `"${strongETag}"`;
  return `W/"${meta.ino}-${meta.size}-${Math.floor(meta.mtimeMs)}"`;
}

/**
 * RFC 7232 If-None-Match: weak-equality comparison (sufficient for GET).
 * Handles `*` wildcard and strips `W/` prefix before comparing so weak
 * and strong ETags with the same opaque value match. Multiple
 * comma-separated candidates are accepted.
 */
function matchesIfNoneMatch(ifNoneMatch: string, etag: string): boolean {
  if (ifNoneMatch.trim() === "*") return true;
  const normalize = (s: string) => s.trim().replace(/^W\//, "");
  const candidates = new Set(ifNoneMatch.split(",").map((s) => normalize(s)));
  return candidates.has(normalize(etag));
}

export type CacheScope = "public" | "private";

// Cache-Control header values, keyed by scope.
//
// - `public` — shared-route binaries. Browser `max-age=60` preserves the
//   60s revocation-latency SLA inherited from the previous
//   `private, max-age=60` default. `s-maxage=60` lets Cloudflare (and any
//   RFC-7234-compliant shared cache) keep an edge copy for 1 minute so
//   repeat viewers of a shared PDF do not re-hit origin. The 60s ceiling
//   is a defense-in-depth backstop on the active CF Cache Purge call in
//   server/kb-share.ts::revokeShare (#2568) — even if the purge API call
//   fails or is delayed, the worst-case revoked-share leak window stays
//   bounded to 60 seconds. `stale-while-revalidate=3600` lets the edge
//   serve a slightly-stale body while refreshing in the background for
//   up to an hour. `must-revalidate` forces the browser to re-check the
//   ETag once max-age expires — pairs with the existing strong-ETag 304
//   path to make revalidation free (0 body bytes).
//
// - `private` — owner-route binaries. 60s browser cache, no shared-cache
//   storage.
const CACHE_CONTROL_BY_SCOPE: Record<CacheScope, string> = {
  public:
    "public, max-age=60, s-maxage=60, stale-while-revalidate=3600, must-revalidate",
  private: "private, max-age=60",
};

/**
 * Builds a 304 Not Modified response with the ETag and Cache-Control
 * headers that a conditional GET or HEAD would return. Shared by
 * buildBinaryResponse, buildBinaryHeadResponse, and upstream share-route
 * helpers that short-circuit before any filesystem work when the client's
 * If-None-Match matches the stored content hash.
 *
 * @param opts.scope Cache policy — `"public"` for the shared route (edge-
 *   cacheable), `"private"` (default) for the owner route.
 */
export function build304Response(
  etag: string,
  opts?: { scope?: CacheScope },
): Response {
  return new Response(null, {
    status: 304,
    headers: {
      ETag: etag,
      "Cache-Control": CACHE_CONTROL_BY_SCOPE[opts?.scope ?? "private"],
    },
  });
}

/** Format a strong ETag (double-quoted sha) from a raw content hash. */
export function formatStrongETag(contentSha256: string): string {
  return `"${contentSha256}"`;
}

/**
 * RFC 7232 If-None-Match weak-equality comparison. Re-exported so upstream
 * callers (share-route helpers) can emit conditional-response short-circuits
 * using the same comparison the main builders use.
 */
export function ifNoneMatchMatches(
  ifNoneMatch: string,
  etag: string,
): boolean {
  return matchesIfNoneMatch(ifNoneMatch, etag);
}

/**
 * Pure header derivation shared by GET and HEAD response builders. Emits
 * the body-agnostic header set a 200 binary response needs. Does NOT
 * include Content-Length or Content-Range — those vary by response shape
 * (full body vs. Range vs. HEAD) and are set by the caller.
 */
export function buildBinaryHeaders(
  payload: BinaryFileMetadata,
  opts?: { strongETag?: string; scope?: CacheScope },
): Record<string, string> {
  const scope: CacheScope = opts?.scope ?? "private";
  const headers: Record<string, string> = {
    "Content-Type": payload.contentType,
    "Content-Disposition": formatContentDisposition(payload.disposition, payload.rawName),
    "X-Content-Type-Options": "nosniff",
    "Cache-Control": CACHE_CONTROL_BY_SCOPE[scope],
    "Content-Security-Policy": KB_BINARY_RESPONSE_CSP,
    "Accept-Ranges": "bytes",
    [SHARED_CONTENT_KIND_HEADER]: deriveBinaryKind(payload),
    ETag: buildETag(payload, opts?.strongETag),
  };
  // Defensive on public responses: any future middleware that branches on a
  // request header must either add to Vary here or flip scope back to
  // "private". Accept-Encoding is implicit in Next.js but making it explicit
  // pins the contract at the source.
  if (scope === "public") headers.Vary = "Accept-Encoding";
  return headers;
}

/**
 * HEAD-equivalent of buildBinaryResponse: returns 200 with an empty body
 * plus Content-Length matching what GET would return (RFC 7231 §4.3.2),
 * or 304 when If-None-Match matches. Never opens a file descriptor — the
 * size is taken from the validated metadata and the ETag comparison runs
 * against the in-memory tuple. This is what lets a HEAD on a cached
 * share short-circuit before the hash drain.
 */
export function buildBinaryHeadResponse(
  payload: BinaryFileMetadata,
  request?: Request,
  opts?: { strongETag?: string; scope?: CacheScope },
): Response {
  const etag = buildETag(payload, opts?.strongETag);
  const ifNoneMatch = request?.headers.get("if-none-match");
  if (ifNoneMatch && matchesIfNoneMatch(ifNoneMatch, etag)) {
    return build304Response(etag, { scope: opts?.scope });
  }
  return new Response(null, {
    status: 200,
    headers: {
      ...buildBinaryHeaders(payload, opts),
      "Content-Length": payload.size.toString(),
    },
  });
}

export async function buildBinaryResponse(
  meta: BinaryFileMetadata,
  request?: Request,
  opts?: { strongETag?: string; scope?: CacheScope },
): Promise<Response> {
  const size = meta.size;
  const expected = { ino: meta.ino, size: meta.size };
  const etag = buildETag(meta, opts?.strongETag);

  // Conditional GET short-circuit: If-None-Match matches → 304 with no
  // body and no fd open. Saves bytes AND the validate+stream round-trip
  // for clients that hold a valid cache entry. Works for full and Range
  // requests (RFC 7232 permits honoring If-None-Match on the overall
  // resource ETag even when a Range header is present).
  const ifNoneMatch = request?.headers.get("if-none-match");
  if (ifNoneMatch && matchesIfNoneMatch(ifNoneMatch, etag)) {
    return build304Response(etag, { scope: opts?.scope });
  }

  const commonHeaders = buildBinaryHeaders(meta, opts);

  const rangeHeader = request?.headers.get("range");
  if (rangeHeader) {
    const match = rangeHeader.trim().match(/^bytes=(\d+)-(\d*)$/);
    if (match) {
      const start = Number.parseInt(match[1], 10);
      const end = match[2] ? Number.parseInt(match[2], 10) : size - 1;
      if (
        !Number.isFinite(start) ||
        !Number.isFinite(end) ||
        start < 0 ||
        start >= size ||
        end < start ||
        end >= size
      ) {
        return new Response(null, {
          status: 416,
          headers: {
            "Content-Range": `bytes */${size}`,
            // Match the other error branches: a malformed-Range 416 must not
            // be shared-cached past its natural lifetime.
            "Cache-Control": "no-store",
          },
        });
      }
      const chunkLength = end - start + 1;
      const nodeStream = await openBinaryStream(meta.filePath, { start, end, expected });
      return new Response(
        Readable.toWeb(nodeStream) as ReadableStream<Uint8Array>,
        {
          status: 206,
          headers: {
            ...commonHeaders,
            "Content-Range": `bytes ${start}-${end}/${size}`,
            "Content-Length": chunkLength.toString(),
          },
        },
      );
    }
    // Malformed Range header: fall through to full response.
  }

  const nodeStream = await openBinaryStream(meta.filePath, { expected });
  return new Response(
    Readable.toWeb(nodeStream) as ReadableStream<Uint8Array>,
    {
      headers: {
        ...commonHeaders,
        "Content-Length": size.toString(),
      },
    },
  );
}
