// PR-C (#2939) Stage 6 — operator-facing screenshot redaction helper.
//
// Used during FR5 visual-QA capture to overlay solid-black rectangles on
// avatar + email regions of a Playwright screenshot BEFORE the operator
// pastes the PNG into the GitHub PR body (FR5.6 / CLO ask). Not invoked
// from CI; pure module, no Playwright dependency at module-eval time.
//
// Sharp is in `devDependencies` (PR-C added explicitly — was already
// installed transitively via Next.js / Playwright dependency graph; PR-C
// formalizes it so the helper has a stable contract).

import sharp from "sharp";

export interface RedactionRect {
  x: number;
  y: number;
  width: number;
  height: number;
  /** For debug logging only — not rendered. */
  label?: string;
}

/**
 * Overlay opaque-black rectangles on `inputPath` and write the redacted PNG
 * to `outputPath`. Existing pixels outside the rects are preserved.
 *
 * Coordinates are in pixels from the top-left corner. Fractional values
 * (common when copying from devtools `getBoundingClientRect()`) are coerced
 * — `x`/`y` floored, `width`/`height` ceiled — so the rounded rect strictly
 * covers the floating-point region. Rects that extend beyond the right or
 * bottom edge are clipped silently by sharp's `composite`. Rects fully
 * outside the bounds, with non-positive size after coercion, or `NaN`
 * components are dropped. Zero-rects produce a copy-through (caller's
 * "redacted PNG at outputPath" contract still holds).
 *
 * @throws when `inputPath` is missing, unreadable, or not a decodable
 * image; when `outputPath` parent is unwritable; or when sharp itself
 * rejects a coerced rect (e.g., rect strictly larger than the source).
 */
export async function redactScreenshot(
  inputPath: string,
  outputPath: string,
  rects: readonly RedactionRect[],
): Promise<void> {
  const { width: imgWidth, height: imgHeight } = await sharp(inputPath).metadata();
  if (!imgWidth || !imgHeight) {
    throw new Error(`redactScreenshot: cannot read dimensions of ${inputPath}`);
  }

  const valid: RedactionRect[] = [];
  for (const rect of rects) {
    if (!Number.isFinite(rect.x) || !Number.isFinite(rect.y)) continue;
    if (!Number.isFinite(rect.width) || !Number.isFinite(rect.height)) continue;
    const x = Math.max(0, Math.floor(rect.x));
    const y = Math.max(0, Math.floor(rect.y));
    if (x >= imgWidth || y >= imgHeight) continue;
    const width = Math.min(imgWidth - x, Math.ceil(rect.x + rect.width) - x);
    const height = Math.min(imgHeight - y, Math.ceil(rect.y + rect.height) - y);
    if (width <= 0 || height <= 0) continue;
    valid.push({ x, y, width, height, label: rect.label });
  }

  if (valid.length === 0) {
    await sharp(inputPath).png().toFile(outputPath);
    return;
  }

  const overlays = await Promise.all(
    valid.map(async (rect) => {
      const swatch = await sharp({
        create: {
          width: rect.width,
          height: rect.height,
          channels: 4,
          background: { r: 0, g: 0, b: 0, alpha: 1 },
        },
      })
        .png()
        .toBuffer();
      return { input: swatch, left: rect.x, top: rect.y };
    }),
  );

  await sharp(inputPath).composite(overlays).png().toFile(outputPath);
}
