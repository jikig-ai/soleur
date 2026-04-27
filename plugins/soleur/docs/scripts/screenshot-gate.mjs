#!/usr/bin/env node
// Screenshot gate for the Eleventy docs site.
//
// Detects critical-CSS FOUC: pages that render with default browser styles in the
// window between DOMContentLoaded and the async stylesheet swap (the
// `<link rel="preload" ... onload="this.rel='stylesheet'">` pattern in base.njk).
//
// Strategy:
//   1. Block the full stylesheet (`css/style.css`) at the network layer. This pins
//      the page in its inline-CSS-only state for the entire test, so assertions are
//      deterministic regardless of `waitUntil` timing.
//   2. Navigate to each route and assert layout invariants that only hold when the
//      relevant selectors (`.page-hero`, `.honeypot-trap`, `.landing-cta`, ...) are
//      present in the inline `<style>` block.
//
// Exit codes:
//   0  all routes pass
//   1  one or more assertion failures (screenshots written to screenshot-gate-failures/)
//   2  bootstrap error (missing routes file, browser launch failed, server unreachable)

import { chromium } from "playwright";
import { readFileSync, mkdirSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROUTES_FILE = resolve(__dirname, "screenshot-gate-routes.json");
const BASE = process.env.SCREENSHOT_GATE_BASE_URL || "http://127.0.0.1:8888";
const FAILURE_DIR = resolve(process.cwd(), "screenshot-gate-failures");

if (!existsSync(ROUTES_FILE)) {
  console.error(`screenshot-gate: routes file missing: ${ROUTES_FILE}`);
  process.exit(2);
}

const config = JSON.parse(readFileSync(ROUTES_FILE, "utf8"));
const routes = config.routes;
const viewport = config.viewport;

mkdirSync(FAILURE_DIR, { recursive: true });

const HEADER_PX = 56; // var(--header-h) === 3.5rem; root font-size is 16px on the docs site

let browser;
try {
  browser = await chromium.launch();
} catch (err) {
  console.error("screenshot-gate: failed to launch chromium:", err.message);
  process.exit(2);
}

const failures = [];

for (const route of routes) {
  const ctx = await browser.newContext({ viewport });
  const page = await ctx.newPage();

  // Block the async-loaded full stylesheet so the page stays pinned in its
  // inline-CSS-only state. This is what the user sees during the FOUC window.
  await page.route("**/css/style.css", (request) => request.abort());

  const url = `${BASE}${route.path}`;
  let result;
  try {
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 15000 });
    result = await page.evaluate(() => {
      // Check the .honeypot-trap WRAPPER, not the <input> inside. The CSS rule
      // hides the wrapper via `height:0; left:-9999px; overflow:hidden`. The
      // input keeps its natural getBoundingClientRect() because clipping by an
      // ancestor's overflow doesn't shrink the descendant's box.
      const honeypotWrapper = document.querySelector(".honeypot-trap");
      const honeypotRect = honeypotWrapper ? honeypotWrapper.getBoundingClientRect() : null;
      const h1 = document.querySelector("main h1");
      const h1Rect = h1 ? h1.getBoundingClientRect() : null;
      const h1Style = h1 ? getComputedStyle(h1) : null;
      return {
        hasHoneypot: !!honeypotWrapper,
        honeypotHeight: honeypotRect ? honeypotRect.height : null,
        honeypotLeft: honeypotRect ? honeypotRect.left : null,
        hasH1: !!h1,
        h1Top: h1Rect ? h1Rect.top : null,
        h1FontPx: h1Style ? parseFloat(h1Style.fontSize) : null,
      };
    });
  } catch (err) {
    failures.push({ route: route.path, errs: [`navigation failed: ${err.message}`] });
    await ctx.close();
    continue;
  }

  const errs = [];

  // Honeypot wrapper must be off-screen (left far negative) AND collapsed (height 0).
  // Without the inlined `.honeypot-trap` rule, height defaults to auto (~32px) and
  // left to 0 — the wrapper renders inline and the user sees the input.
  if (result.hasHoneypot) {
    if (result.honeypotHeight > 1) {
      errs.push(
        `honeypot wrapper has non-zero height (${result.honeypotHeight.toFixed(1)}px) — .honeypot-trap height:0 missing from inline CSS`,
      );
    }
    if (result.honeypotLeft > -100) {
      errs.push(
        `honeypot wrapper not positioned off-screen (left=${result.honeypotLeft.toFixed(1)}px) — .honeypot-trap left:-9999px missing from inline CSS`,
      );
    }
  }

  // The first <h1> in <main> must render below the fixed header.
  // Without `.page-hero { margin-top: var(--header-h) }` inlined, the H1 sits at
  // the top of the document and is occluded by the fixed header.
  if (result.hasH1 && result.h1Top !== null && result.h1Top < HEADER_PX) {
    errs.push(
      `h1 above/under header (top=${result.h1Top.toFixed(1)}px, header=${HEADER_PX}px) — .page-hero missing from inline CSS`,
    );
  }

  // The hero H1 must be at display size. var(--text-4xl) === 3rem === 48px.
  // Default browser h1 (or @layer base override) is ~36px; tolerate down to 40px.
  if (result.hasH1 && result.h1FontPx !== null && result.h1FontPx < 40) {
    errs.push(
      `h1 too small (${result.h1FontPx}px < 40px) — page-hero/landing-hero h1 size missing from inline CSS`,
    );
  }

  if (errs.length) {
    const slug = route.path === "/" ? "home" : route.path.replace(/^\/|\/$/g, "").replace(/\//g, "_");
    const screenshotPath = resolve(FAILURE_DIR, `${slug}.png`);
    try {
      await page.screenshot({ path: screenshotPath, fullPage: true });
    } catch (_err) {
      // Don't fail the gate on screenshot capture failure; the assertion failure
      // is what matters.
    }
    failures.push({ route: route.path, errs, screenshot: screenshotPath });
  }

  await ctx.close();
}

await browser.close();

if (failures.length) {
  console.error("screenshot-gate: FAIL");
  for (const f of failures) {
    console.error(`  ${f.route}`);
    for (const e of f.errs) {
      console.error(`    - ${e}`);
    }
    if (f.screenshot) {
      console.error(`    screenshot: ${f.screenshot}`);
    }
  }
  process.exit(1);
}

console.log(`screenshot-gate: PASS (${routes.length} routes)`);
