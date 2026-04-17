import fs from "node:fs";
import path from "node:path";
import { Readable } from "node:stream";
import { isPathInWorkspace } from "@/server/sandbox";
import { KB_BINARY_RESPONSE_CSP } from "@/lib/kb-csp";
import { getKbExtension } from "@/lib/kb-extensions";

export const MAX_BINARY_SIZE = 50 * 1024 * 1024; // 50 MB

export const CONTENT_TYPE_MAP: Record<string, string> = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".svg": "image/svg+xml",
  ".pdf": "application/pdf",
  ".csv": "text/csv",
  ".txt": "text/plain",
  ".docx":
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
};

export const ATTACHMENT_EXTENSIONS = new Set([".docx"]);

/**
 * Validated metadata from validateBinaryFile. Carries (ino, mtimeMs, size)
 * so callers of openBinaryStream can pass `expected` and reject a second
 * open if the underlying inode drifted between validation and serve. This
 * closes the TOCTOU window that would otherwise open between two separate
 * fds on the same path.
 */
export interface BinaryFileMetadata {
  ok: true;
  filePath: string;
  ino: number;
  size: number;
  mtimeMs: number;
  contentType: string;
  disposition: "inline" | "attachment";
  rawName: string;
}

export type BinaryReadResult =
  | BinaryFileMetadata
  | {
      ok: false;
      status: 403 | 404 | 413;
      error: string;
    };

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
 * Name note: called "validate" (not "read") because it no longer reads
 * file bytes — pre-#2316 it did; the rename avoids perpetuating the lie.
 */
export async function validateBinaryFile(
  kbRoot: string,
  relativePath: string,
): Promise<BinaryReadResult> {
  if (relativePath.includes("\0")) {
    return { ok: false, status: 403, error: "Access denied" };
  }
  const fullPath = path.join(kbRoot, relativePath);
  if (!isPathInWorkspace(fullPath, kbRoot)) {
    return { ok: false, status: 403, error: "Access denied" };
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
      return { ok: false, status: 403, error: "Access denied" };
    }
    return { ok: false, status: 404, error: "File not found" };
  }
  try {
    const stat = await handle.stat();
    if (!stat.isFile()) {
      return { ok: false, status: 403, error: "Access denied" };
    }
    if (stat.size > MAX_BINARY_SIZE) {
      return { ok: false, status: 413, error: "File exceeds maximum size limit" };
    }
    const ext = getKbExtension(relativePath);
    const contentType = CONTENT_TYPE_MAP[ext] || "application/octet-stream";
    const disposition = ATTACHMENT_EXTENSIONS.has(ext) ? "attachment" : "inline";
    const rawName = path.basename(relativePath);
    return {
      ok: true,
      filePath: fullPath,
      ino: stat.ino,
      size: stat.size,
      mtimeMs: stat.mtimeMs,
      contentType,
      disposition,
      rawName,
    };
  } catch {
    return { ok: false, status: 404, error: "File not found" };
  } finally {
    await handle.close().catch(() => {});
  }
}

/**
 * Deprecated alias preserved for backward compatibility during the rename
 * landing. Will be removed once all callers migrate to validateBinaryFile.
 *
 * @deprecated Use validateBinaryFile.
 */
export const readBinaryFile = validateBinaryFile;

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

export async function buildBinaryResponse(
  meta: BinaryFileMetadata,
  request?: Request,
  opts?: { strongETag?: string },
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
    return new Response(null, {
      status: 304,
      headers: {
        ETag: etag,
        "Cache-Control": "private, max-age=60",
      },
    });
  }

  const commonHeaders: Record<string, string> = {
    "Content-Type": meta.contentType,
    "Content-Disposition": formatContentDisposition(meta.disposition, meta.rawName),
    "X-Content-Type-Options": "nosniff",
    "Cache-Control": "private, max-age=60",
    "Content-Security-Policy": KB_BINARY_RESPONSE_CSP,
    "Accept-Ranges": "bytes",
    ETag: etag,
  };

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
          headers: { "Content-Range": `bytes */${size}` },
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
