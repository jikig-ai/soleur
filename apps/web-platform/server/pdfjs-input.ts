// Shared no-copy view helper for pdfjs-dist@5+ inputs.
//
// pdfjs-dist@5.4.296 explicitly REJECTS Node Buffer
// ("Please provide binary data as Uint8Array, rather than Buffer.")
// even though Buffer extends Uint8Array — its check is
// `instanceof Buffer === false`. Wrap to a plain Uint8Array view (no
// copy) so the legacy parser entry accepts it.
//
// Single source of truth for `pdf-text-extract.ts` and
// `kb-preview-metadata.ts` so the two helpers never drift.

export function toPdfjsData(buffer: Buffer | Uint8Array): Uint8Array {
  if (typeof Buffer !== "undefined" && Buffer.isBuffer(buffer)) {
    return new Uint8Array(buffer.buffer, buffer.byteOffset, buffer.byteLength);
  }
  return buffer;
}
