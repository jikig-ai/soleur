// Content-integrity hashing for KB share links. Two entry points by caller
// shape: hashBytes for post-read verification where the buffer is already
// in hand (view path), hashStream for share creation where streaming avoids
// a second 50 MB buffer allocation on top of the fd read.

import { createHash } from "node:crypto";
import type { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";

/**
 * SHA-256 of a byte buffer, lowercase hex. Use when the caller already
 * holds the full buffer (e.g. markdown files read via readContentRaw).
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
 * That is the caller's responsibility (it owns the fd lifecycle). On
 * pipeline error the source is explicitly destroyed so a subsequent close
 * on the caller's fd does not race with a still-draining stream.
 */
export async function hashStream(source: Readable): Promise<string> {
  const hasher = createHash("sha256");
  try {
    await pipeline(source, hasher);
  } catch (err) {
    source.destroy();
    throw err;
  }
  return hasher.digest("hex");
}
