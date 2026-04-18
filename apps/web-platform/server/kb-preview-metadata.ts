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

async function streamToBuffer(stream: Readable): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of stream) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

export async function readPdfMetadata(
  stream: Readable,
): Promise<PdfPreview | null> {
  let buffer: Buffer;
  try {
    buffer = await streamToBuffer(stream);
  } catch (err) {
    warnSilentFallback(err, {
      feature: "kb-share",
      op: "preview-pdf-drain",
    });
    return null;
  }

  try {
    const pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
    // Legacy entry provides a fake worker for Node so GlobalWorkerOptions
    // does not need to be set. isEvalSupported: false avoids Function()
    // usage inside the parser — irrelevant for metadata-only reads but
    // keeps behavior identical to the browser SSR-safe config.
    const doc = await pdfjs.getDocument({
      data: new Uint8Array(buffer),
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
  let buffer: Buffer;
  try {
    buffer = await streamToBuffer(stream);
  } catch (err) {
    warnSilentFallback(err, {
      feature: "kb-share",
      op: "preview-image-drain",
    });
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
