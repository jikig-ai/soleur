import fs from "node:fs";
import path from "node:path";
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

export type BinaryReadResult =
  | {
      ok: true;
      buffer: Buffer;
      contentType: string;
      disposition: "inline" | "attachment";
      rawName: string;
    }
  | {
      ok: false;
      status: 403 | 404 | 413;
      error: string;
    };

/**
 * Build an RFC 6266 Content-Disposition header value with both an ASCII
 * fallback (`filename="..."`) and a UTF-8 RFC 5987 encoded form
 * (`filename*=UTF-8''...`). Strips control characters from the fallback to
 * keep the header parseable across browsers and proxies.
 */
export function formatContentDisposition(
  disposition: "inline" | "attachment",
  rawName: string,
): string {
  const asciiFallback = rawName.replace(/[^\x20-\x7e]/g, "_").replace(/["\r\n\\]/g, "_");
  const utf8Encoded = encodeURIComponent(rawName)
    // RFC 5987 reserves * ' ( ) ; , / ? : @ & = + $ -- encodeURIComponent
    // already escapes most; leave * untouched per RFC 5987 examples.
    .replace(/['()]/g, escape);
  return `${disposition}; filename="${asciiFallback}"; filename*=UTF-8''${utf8Encoded}`;
}

export async function readBinaryFile(
  kbRoot: string,
  relativePath: string,
): Promise<BinaryReadResult> {
  // Reject null bytes — `path.join`/`open` would throw `ERR_INVALID_ARG_VALUE`
  // and bubble up as an unhandled 500. Mirrors `readContent`'s guard.
  if (relativePath.includes("\0")) {
    return { ok: false, status: 403, error: "Access denied" };
  }
  const fullPath = path.join(kbRoot, relativePath);
  if (!isPathInWorkspace(fullPath, kbRoot)) {
    return { ok: false, status: 403, error: "Access denied" };
  }
  // Open with O_NOFOLLOW to refuse symlinks at open time, then fstat the fd
  // and read from the fd. This closes the lstat→readFile TOCTOU window: a
  // file replaced between lstat and readFile would still be served from the
  // fd we already hold. A symlink swapped in is rejected by O_NOFOLLOW.
  let handle: fs.promises.FileHandle;
  try {
    handle = await fs.promises.open(fullPath, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code === "ELOOP" || code === "EMLINK") {
      return { ok: false, status: 403, error: "Access denied" };
    }
    if (code === "ENOENT") {
      return { ok: false, status: 404, error: "File not found" };
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
    const buffer = await handle.readFile();
    return { ok: true, buffer, contentType, disposition, rawName };
  } catch {
    return { ok: false, status: 404, error: "File not found" };
  } finally {
    await handle.close().catch(() => {});
  }
}

export function buildBinaryResponse(r: {
  buffer: Buffer;
  contentType: string;
  disposition: "inline" | "attachment";
  rawName: string;
}): Response {
  return new Response(new Uint8Array(r.buffer), {
    headers: {
      "Content-Type": r.contentType,
      "Content-Disposition": formatContentDisposition(r.disposition, r.rawName),
      "Content-Length": r.buffer.length.toString(),
      "X-Content-Type-Options": "nosniff",
      "Cache-Control": "private, max-age=60",
      "Content-Security-Policy": KB_BINARY_RESPONSE_CSP,
    },
  });
}
