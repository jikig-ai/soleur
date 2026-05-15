// PR-C (#2939) Stage 6 — unit test for the operator-facing screenshot
// redaction helper. Covers the FR5.6 contract: rectangles overlay as
// opaque black, surrounding pixels survive unchanged.

import { describe, test, expect, beforeAll, afterAll } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import sharp from "sharp";

import { redactScreenshot } from "@/e2e/helpers/screenshot-redact";

const WIDTH = 4;
const HEIGHT = 4;

// 4×4 RGBA buffer, all pixels filled with a distinctive non-black color so a
// redaction overlay is detectable. RGB(200, 100, 50, 255).
function makeFixturePng(): Promise<Buffer> {
  const channels = 4;
  const raw = Buffer.alloc(WIDTH * HEIGHT * channels);
  for (let i = 0; i < WIDTH * HEIGHT; i++) {
    raw[i * channels + 0] = 200;
    raw[i * channels + 1] = 100;
    raw[i * channels + 2] = 50;
    raw[i * channels + 3] = 255;
  }
  return sharp(raw, { raw: { width: WIDTH, height: HEIGHT, channels: 4 } })
    .png()
    .toBuffer();
}

interface Pixel { r: number; g: number; b: number; a: number }

async function readPixels(path: string): Promise<Pixel[][]> {
  const { data, info } = await sharp(path)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const pixels: Pixel[][] = [];
  for (let y = 0; y < info.height; y++) {
    const row: Pixel[] = [];
    for (let x = 0; x < info.width; x++) {
      const idx = (y * info.width + x) * info.channels;
      row.push({
        r: data[idx],
        g: data[idx + 1],
        b: data[idx + 2],
        a: data[idx + 3],
      });
    }
    pixels.push(row);
  }
  return pixels;
}

describe("redactScreenshot", () => {
  let workdir: string;
  let inputPath: string;
  let outputPath: string;

  beforeAll(async () => {
    workdir = await mkdtemp(join(tmpdir(), "stage6-redact-"));
    inputPath = join(workdir, "input.png");
    outputPath = join(workdir, "output.png");
    await sharp(await makeFixturePng()).toFile(inputPath);
  });

  afterAll(async () => {
    await rm(workdir, { recursive: true, force: true });
  });

  test("overlays opaque black on the redaction rect; other pixels survive", async () => {
    await redactScreenshot(inputPath, outputPath, [
      { x: 1, y: 1, width: 2, height: 2, label: "test-region" },
    ]);

    const pixels = await readPixels(outputPath);

    // Inside the 2×2 redaction at (1,1).
    for (let y = 1; y <= 2; y++) {
      for (let x = 1; x <= 2; x++) {
        expect(pixels[y][x], `pixel (${x},${y}) should be opaque black`).toEqual({
          r: 0,
          g: 0,
          b: 0,
          a: 255,
        });
      }
    }

    // Outside the rect — original color must survive.
    const surviving = [
      [0, 0], [3, 0], [0, 3], [3, 3], // corners
      [0, 1], [0, 2], [3, 1], [3, 2], // edges
      [1, 0], [2, 0], [1, 3], [2, 3],
    ];
    for (const [x, y] of surviving) {
      expect(pixels[y][x], `pixel (${x},${y}) should preserve original`).toEqual({
        r: 200,
        g: 100,
        b: 50,
        a: 255,
      });
    }
  });

  test("zero-rect input is a copy-through (no-op redaction)", async () => {
    const noopOut = join(workdir, "noop.png");
    await redactScreenshot(inputPath, noopOut, []);
    const pixels = await readPixels(noopOut);
    for (const row of pixels) {
      for (const px of row) {
        expect(px).toEqual({ r: 200, g: 100, b: 50, a: 255 });
      }
    }
  });

  test("rect partially outside image bounds is clipped to source dimensions", async () => {
    const clipOut = join(workdir, "clip.png");
    // Rect at (2,2) with size 99×99 extends well past the 4×4 source — must
    // clip to (2,2)..(3,3) (the source's bottom-right 2×2 quadrant).
    await redactScreenshot(inputPath, clipOut, [
      { x: 2, y: 2, width: 99, height: 99, label: "oversized" },
    ]);
    const pixels = await readPixels(clipOut);
    for (let y = 2; y <= 3; y++) {
      for (let x = 2; x <= 3; x++) {
        expect(pixels[y][x], `pixel (${x},${y}) should be opaque black`).toEqual({
          r: 0,
          g: 0,
          b: 0,
          a: 255,
        });
      }
    }
    // Outside the clipped region — original survives.
    expect(pixels[0][0]).toEqual({ r: 200, g: 100, b: 50, a: 255 });
    expect(pixels[1][1]).toEqual({ r: 200, g: 100, b: 50, a: 255 });
  });

  test("fractional coords from getBoundingClientRect are floored/ceiled, not rejected", async () => {
    const fracOut = join(workdir, "frac.png");
    // Devtools-shaped fractional inputs; floor + ceil produce a 2×2 at (1,1).
    await redactScreenshot(inputPath, fracOut, [
      { x: 1.4, y: 1.6, width: 1.2, height: 1.2 },
    ]);
    const pixels = await readPixels(fracOut);
    expect(pixels[1][1]).toEqual({ r: 0, g: 0, b: 0, a: 255 });
    expect(pixels[2][2]).toEqual({ r: 0, g: 0, b: 0, a: 255 });
    // Corner remains the original color.
    expect(pixels[0][0]).toEqual({ r: 200, g: 100, b: 50, a: 255 });
  });

  test("multiple non-overlapping rects redact independently", async () => {
    const multiOut = join(workdir, "multi.png");
    await redactScreenshot(inputPath, multiOut, [
      { x: 0, y: 0, width: 1, height: 1, label: "top-left" },
      { x: 3, y: 3, width: 1, height: 1, label: "bottom-right" },
    ]);
    const pixels = await readPixels(multiOut);
    expect(pixels[0][0]).toEqual({ r: 0, g: 0, b: 0, a: 255 });
    expect(pixels[3][3]).toEqual({ r: 0, g: 0, b: 0, a: 255 });
    // Middle survives.
    expect(pixels[1][1]).toEqual({ r: 200, g: 100, b: 50, a: 255 });
    expect(pixels[2][2]).toEqual({ r: 200, g: 100, b: 50, a: 255 });
  });
});
