import fs from "node:fs";
import path from "node:path";
import { Readable } from "node:stream";
import { isPathInWorkspace } from "@/server/sandbox";
import { KB_BINARY_RESPONSE_CSP } from "@/lib/kb-csp";

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
 * Successful result of readBinaryFile. Holds validated metadata; does NOT
 * hold the file bytes in memory. Response bodies open a fresh stream via
 * openBinaryStream(filePath, …) so peak RSS per request stays ~64 KB
 * (default createReadStream chunk size) instead of ~size bytes.
 */
export interface BinaryFileMetadata {
  ok: true;
  filePath: string;
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
 * Validate a KB-relative path + collect metadata. Opens with O_NOFOLLOW,
 * fstats against the fd to close the symlink-swap window, then closes the
 * fd and returns metadata only. Callers stream bytes separately via
 * openBinaryStream(result.filePath, …), which opens another O_NOFOLLOW fd.
 *
 * This decouples validation from byte transfer. The trade-off: there is a
 * small TOCTOU window between this function returning and openBinaryStream
 * opening — the file could be swapped. isPathInWorkspace and O_NOFOLLOW
 * still apply to the second open, so symlink replacement is rejected, and
 * the verdict cache in share-hash-verdict-cache.ts keys on (token,
 * mtimeMs, size) so a mutation between validate and stream will not be
 * served from a stale verdict.
 */
export async function readBinaryFile(
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
    const ext = path.extname(relativePath).toLowerCase();
    const contentType = CONTENT_TYPE_MAP[ext] || "application/octet-stream";
    const disposition = ATTACHMENT_EXTENSIONS.has(ext) ? "attachment" : "inline";
    const rawName = path.basename(relativePath);
    return {
      ok: true,
      filePath: fullPath,
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
 * Open a fresh O_NOFOLLOW read stream for an already-validated filePath.
 * The returned Node Readable is backed by the opened FileHandle with
 * autoClose: true, so fd lifetime is tied to the stream. Pass start/end
 * for Range requests; omit for full-file reads.
 *
 * Returns a Node Readable (not a web ReadableStream) so callers can either:
 *   - wrap via Readable.toWeb(stream) for Response bodies, or
 *   - pipe directly into hashStream() from kb-content-hash.ts.
 */
export async function openBinaryStream(
  filePath: string,
  opts?: { start?: number; end?: number },
): Promise<Readable> {
  const handle = await fs.promises.open(
    filePath,
    fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW,
  );
  return handle.createReadStream({
    autoClose: true,
    ...(opts?.start !== undefined ? { start: opts.start } : {}),
    ...(opts?.end !== undefined ? { end: opts.end } : {}),
  });
}

export async function buildBinaryResponse(
  meta: BinaryFileMetadata,
  request?: Request,
): Promise<Response> {
  const size = meta.size;
  const commonHeaders: Record<string, string> = {
    "Content-Type": meta.contentType,
    "Content-Disposition": formatContentDisposition(meta.disposition, meta.rawName),
    "X-Content-Type-Options": "nosniff",
    "Cache-Control": "private, max-age=60",
    "Content-Security-Policy": KB_BINARY_RESPONSE_CSP,
    "Accept-Ranges": "bytes",
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
      const nodeStream = await openBinaryStream(meta.filePath, { start, end });
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

  const nodeStream = await openBinaryStream(meta.filePath);
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
