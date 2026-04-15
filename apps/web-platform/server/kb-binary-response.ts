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
      safeName: string;
    }
  | {
      ok: false;
      status: 403 | 404 | 413;
      error: string;
    };

export async function readBinaryFile(
  kbRoot: string,
  relativePath: string,
): Promise<BinaryReadResult> {
  const fullPath = path.join(kbRoot, relativePath);
  if (!isPathInWorkspace(fullPath, kbRoot)) {
    return { ok: false, status: 403, error: "Access denied" };
  }
  let lstat: fs.Stats;
  try {
    lstat = await fs.promises.lstat(fullPath);
  } catch {
    return { ok: false, status: 404, error: "File not found" };
  }
  if (lstat.isSymbolicLink() || !lstat.isFile()) {
    return { ok: false, status: 403, error: "Access denied" };
  }
  if (lstat.size > MAX_BINARY_SIZE) {
    return { ok: false, status: 413, error: "File exceeds maximum size limit" };
  }
  const ext = path.extname(relativePath).toLowerCase();
  const contentType = CONTENT_TYPE_MAP[ext] || "application/octet-stream";
  const disposition = ATTACHMENT_EXTENSIONS.has(ext) ? "attachment" : "inline";
  const rawName = path.basename(relativePath);
  const safeName = rawName.replace(/["\r\n\\]/g, "_");
  let buffer: Buffer;
  try {
    buffer = await fs.promises.readFile(fullPath);
  } catch {
    return { ok: false, status: 404, error: "File not found" };
  }
  return { ok: true, buffer, contentType, disposition, safeName };
}

export function buildBinaryResponse(r: {
  buffer: Buffer;
  contentType: string;
  disposition: "inline" | "attachment";
  safeName: string;
}): Response {
  return new Response(new Uint8Array(r.buffer), {
    headers: {
      "Content-Type": r.contentType,
      "Content-Disposition": `${r.disposition}; filename="${r.safeName}"`,
      "Content-Length": r.buffer.length.toString(),
      "X-Content-Type-Options": "nosniff",
      "Cache-Control": "private, max-age=60",
      "Content-Security-Policy": KB_BINARY_RESPONSE_CSP,
    },
  });
}
