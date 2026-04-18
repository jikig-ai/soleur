// Metadata-only first-page preview helpers for kb_share_preview (#2322).
//
// pdfjs and sharp are lazy-imported so the cost is paid only on the preview
// branch — not on every KB request. pdfjs uses the legacy entry
// (pdfjs-dist/legacy/build/pdf.mjs) to avoid the browser Worker assumption;
// all operations here are parser-only (numPages + page 1 viewport), so no
// `canvas` / `node-canvas` dependency is required. sharp(buffer).metadata()
// is synchronously-by-promise; no worker needed.
//
// Errors are silent-fallbacks: a corrupted PDF or unknown image format
// returns null, logged + mirrored to Sentry, while the outer tool call
// still returns the core metadata ({ contentType, size, filename }).

import type { Readable } from "node:stream";
import { warnSilentFallback } from "@/server/observability";

/**
 * Preview input cap. Smaller than MAX_BINARY_SIZE (50 MB) because pdfjs and
 * sharp parse the full buffer into an object graph before surfacing
 * metadata — a 50 MB PDF can peak at 200-300 MB RSS. For metadata-only
 * reads (numPages, dimensions), 15 MB is ample for any PDF a user actually
 * shares. Files above the cap return firstPagePreview: undefined so the
 * outer tool call still ships { contentType, size, filename }.
 */
export const PREVIEW_MAX_BYTES = 15 * 1024 * 1024;

export interface PdfPreview {
  kind: "pdf";
  width: number;
  height: number;
  numPages: number;
}

export interface ImagePreview {
  kind: "image";
  width: number;
  height: number;
  format: string;
}

/**
 * Drain up to PREVIEW_MAX_BYTES from the stream into a single Buffer.
 * Returns null if the stream exceeds the cap (DoS guard). Destroys the
 * stream on overflow so the underlying fd closes promptly.
 */
async function streamToBoundedBuffer(stream: Readable): Promise<Buffer | null> {
  const chunks: Buffer[] = [];
  let total = 0;
  for await (const chunk of stream) {
    const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    total += buf.length;
    if (total > PREVIEW_MAX_BYTES) {
      stream.destroy();
      return null;
    }
    chunks.push(buf);
  }
  return Buffer.concat(chunks, total);
}

export async function readPdfMetadata(
  stream: Readable,
): Promise<PdfPreview | null> {
  let buffer: Buffer | null;
  try {
    buffer = await streamToBoundedBuffer(stream);
  } catch (err) {
    warnSilentFallback(err, {
      feature: "kb-share",
      op: "preview-pdf-drain",
    });
    return null;
  }
  if (buffer === null) {
    // Over cap — skip preview rather than risk 200-300 MB RSS on a single
    // agent call. Outer tool still returns core metadata; agent sees a
    // missing firstPagePreview field and can ask the user for page count
    // if needed.
    return null;
  }

  try {
    const pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
    // Legacy entry provides a fake worker for Node so GlobalWorkerOptions
    // does not need to be set. isEvalSupported: false avoids Function()
    // usage inside the parser — irrelevant for metadata-only reads but
    // keeps behavior identical to the browser SSR-safe config. Buffer is
    // a Uint8Array subclass; pdfjs accepts it directly, no wrapping copy.
    const doc = await pdfjs.getDocument({
      data: buffer,
      isEvalSupported: false,
    }).promise;
    try {
      const page = await doc.getPage(1);
      const viewport = page.getViewport({ scale: 1 });
      return {
        kind: "pdf",
        width: viewport.width,
        height: viewport.height,
        numPages: doc.numPages,
      };
    } finally {
      await doc.destroy().catch(() => {});
    }
  } catch (err) {
    warnSilentFallback(err, {
      feature: "kb-share",
      op: "preview-pdf-parse",
    });
    return null;
  }
}

export async function readImageMetadata(
  stream: Readable,
): Promise<ImagePreview | null> {
  let buffer: Buffer | null;
  try {
    buffer = await streamToBoundedBuffer(stream);
  } catch (err) {
    warnSilentFallback(err, {
      feature: "kb-share",
      op: "preview-image-drain",
    });
    return null;
  }
  if (buffer === null) {
    return null;
  }

  try {
    const sharp = (await import("sharp")).default;
    const meta = await sharp(buffer).metadata();
    if (!meta.width || !meta.height || !meta.format) return null;
    return {
      kind: "image",
      width: meta.width,
      height: meta.height,
      format: meta.format,
    };
  } catch (err) {
    warnSilentFallback(err, {
      feature: "kb-share",
      op: "preview-image-parse",
    });
    return null;
  }
}
