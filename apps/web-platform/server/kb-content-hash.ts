import { createHash } from "node:crypto";
import type { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";

/**
 * SHA-256 of a byte buffer, lowercase hex. Use when the caller already
 * holds the full buffer (e.g. readBinaryFile returns buffer).
 */
export function hashBytes(buf: Buffer): string {
  return createHash("sha256").update(buf).digest("hex");
}

/**
 * SHA-256 of a Readable stream, lowercase hex. Use at share creation to
 * avoid allocating a second 50 MB buffer for hashing — stream the file
 * through the hasher and let GC reclaim chunks.
 *
 * Callers supply the stream; this helper does NOT close the underlying fd.
 * That is the caller's responsibility (it owns the fd lifecycle).
 */
export async function hashStream(source: Readable): Promise<string> {
  const hasher = createHash("sha256");
  await pipeline(source, hasher);
  return hasher.digest("hex");
}
