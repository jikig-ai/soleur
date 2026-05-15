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
 * Coordinates are in pixels measured from the top-left corner. Rectangles
 * that fall partially outside the image bounds are clipped silently — sharp
 * handles the clipping in `extract`/`composite`. Zero-size rects are ignored.
 */
export async function redactScreenshot(
  inputPath: string,
  outputPath: string,
  rects: readonly RedactionRect[],
): Promise<void> {
  const valid = rects.filter((r) => r.width > 0 && r.height > 0);
  if (valid.length === 0) {
    // No-op redaction — copy input through unchanged so the caller's
    // contract ("redacted PNG at outputPath") still holds.
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
