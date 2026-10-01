import { test, expect } from "@playwright/test";
import type { Locator } from "@playwright/test";

/**
 * Layout gate for the Button primitive (Guard 2 mutation #5).
 *
 * happy-dom cannot measure layout, so the class-contract vitest suites cannot
 * see the composer regression where `px-6 py-3` inside a 36px border-box left
 * a 0px content box and the attach/send SVG collapsed. This measures the real
 * rendered box.
 */

/** Viewports every glyph-box assertion runs at (desktop + mobile composer). */
export const GLYPH_VIEWPORTS = [
  { name: "1440px", width: 1440, height: 900 },
  { name: "390px", width: 390, height: 844 },
] as const;

/** Minimum rendered SVG box edge (px). The composer icons are 18px. */
export const MIN_GLYPH_PX = 16;

/**
 * Poll (never a one-shot read: the box is 0 until layout + fonts settle) until
 * the locator's bounding box is at least `min` px in both dimensions.
 */
export async function expectBoxAtLeast(
  target: Locator,
  min: number,
  what: string,
): Promise<void> {
  await expect
    .poll(
      async () => {
        const box = await target.boundingBox();
        return box ? Math.min(box.width, box.height) : 0;
      },
      {
        message: `${what}: rendered box must be at least ${min}x${min}px`,
        timeout: 10_000,
      },
    )
    .toBeGreaterThanOrEqual(min);
}

/**
 * Skip only outside CI. A dev-server CSS compile failure (5xx / invalid-URL
 * page) must never swallow the layout gate in CI: an un-compiled stylesheet is
 * exactly the failure this gate exists to catch.
 */
export function skipLocallyFailInCi(reason: string): void {
  if (process.env.CI) {
    throw new Error(`${reason} — in CI this gate must fail, not skip.`);
  }
  test.skip(true, `${reason} — skipped locally only; fails in CI`);
}
