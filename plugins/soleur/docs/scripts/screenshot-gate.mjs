#!/usr/bin/env node
// Screenshot gate for the Eleventy docs site.
//
// Detects critical-CSS FOUC: pages that render with default browser styles in the
// window between DOMContentLoaded and the async stylesheet swap (the
// `<link rel="preload" ... onload="this.rel='stylesheet'">` pattern in base.njk).
//
// Strategy:
//   1. Block ALL external stylesheets at the network layer (`page.route("**/*.css", abort)`).
//      This pins the page in its inline-CSS-only state for the entire test, so
//      assertions are deterministic regardless of `waitUntil` timing or which
//      additional stylesheets a future template might add.
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
const BASE_URL = process.env.SCREENSHOT_GATE_BASE_URL || "http://127.0.0.1:8888";
const FAILURE_DIR = resolve(process.cwd(), "screenshot-gate-failures");

// Named thresholds. `--header-h` is `3.5rem` and the docs site keeps the
// browser default 16px root font-size, so the fixed header is 56px tall.
// `H1_MIN_FONT_PX` is sized to catch the user-agent-default H1 (~36px) while
// staying under both `.page-hero h1` (`var(--text-4xl)` = 48px) and
// `.landing-hero h1` (`var(--text-5xl)` = 72px).
const HEADER_PX = 56;
const NAV_TIMEOUT_MS = 15_000;
const HONEYPOT_MAX_HEIGHT_PX = 1;
const HONEYPOT_MIN_OFFSCREEN_LEFT_PX = -100;
const H1_MIN_FONT_PX = 40;

// Worker pool size: each route opens a `BrowserContext` (~30MB resident).
// 4 in parallel keeps memory under ~150MB on GitHub runners (7GB) while
// dropping wall-time from ~25s sequential to ~7s for 20 routes.
const POOL_SIZE = 4;

// Output mode. `--json` makes the gate machine-parseable for downstream agents
// (skill wrappers, GitHub Actions checks, IDE integrations). The human-readable
// stderr report is still emitted on failure either way.
const JSON_OUTPUT = process.argv.includes("--json");

if (!existsSync(ROUTES_FILE)) {
  console.error(`screenshot-gate: routes file missing: ${ROUTES_FILE}`);
  process.exit(2);
}

const config = JSON.parse(readFileSync(ROUTES_FILE, "utf8"));
const routes = config.routes;
const viewport = config.viewport;

mkdirSync(FAILURE_DIR, { recursive: true });

let browser;
try {
  browser = await chromium.launch();
} catch (err) {
  console.error("screenshot-gate: failed to launch chromium:", err.message);
  process.exit(2);
}

// Pre-flight: confirm the static server is up. A 404 (no index for whatever path
// we're hitting) is fine — we only need to know the TCP listener exists. Without
// this check, every route fails with the same "navigation failed: ECONNREFUSED"
// and the gate exits 1 instead of the documented "bootstrap error" exit 2.
try {
  const probe = await fetch(`${BASE_URL}/`, { method: "HEAD" });
  // Any HTTP response means the server is up; status code is irrelevant.
  void probe;
} catch (err) {
  console.error(`screenshot-gate: server unreachable at ${BASE_URL}: ${err.message}`);
  await browser.close();
  process.exit(2);
}

async function auditRoute(route) {
  const ctx = await browser.newContext({ viewport });
  const page = await ctx.newPage();
  const errs = [];
  let screenshotPath;

  try {
    // Block ALL external stylesheets — pins the page in its inline-CSS-only state
    // regardless of which `<link>` URLs a future template introduces. The block
    // intentionally ignores method; abort fires for HEAD too which is fine.
    await page.route("**/*.css", (request) => request.abort());

    const url = `${BASE_URL}${route.path}`;
    try {
      await page.goto(url, { waitUntil: "domcontentloaded", timeout: NAV_TIMEOUT_MS });
    } catch (err) {
      errs.push(`navigation failed: ${err.message}`);
      return { route: route.path, errs };
    }

    const result = await page.evaluate(() => {
      // Honeypot: check the WRAPPER, not the <input>. The CSS rule hides the
      // wrapper via `height:0; left:-9999px; overflow:hidden`. The input keeps
      // its natural getBoundingClientRect() because clipping by an ancestor's
      // overflow doesn't shrink the descendant's box.
      const honeypotWrapper = document.querySelector(".honeypot-trap");
      const honeypotRect = honeypotWrapper ? honeypotWrapper.getBoundingClientRect() : null;
      const h1 = document.querySelector("main h1");
      const h1Rect = h1 ? h1.getBoundingClientRect() : null;
      const h1Style = h1 ? getComputedStyle(h1) : null;
      // Body font tells us whether the @layer base body { font-family: ... }
      // rule applied. Without inline tokens the body falls back to the browser
      // default serif stack, which is a strong FOUC signal applicable on every
      // page (no per-template selector dependency).
      const bodyFont = getComputedStyle(document.body).fontFamily.toLowerCase();
      // .landing-cta h2: only present on /pricing/. The default browser h2
      // inherits the body font (Inter); the inline rule switches to the
      // display font (Cormorant Garamond). Detecting "cormorant" or "garamond"
      // is robust to the resolved-fontFamily-stack quirk.
      const landingCta = document.querySelector(".landing-cta");
      const landingCtaH2 = document.querySelector(".landing-cta h2");
      const landingCtaH2Font = landingCtaH2
        ? getComputedStyle(landingCtaH2).fontFamily.toLowerCase()
        : null;
      return {
        hasHoneypot: !!honeypotWrapper,
        honeypotHeight: honeypotRect ? honeypotRect.height : null,
        honeypotLeft: honeypotRect ? honeypotRect.left : null,
        hasH1: !!h1,
        h1Top: h1Rect ? h1Rect.top : null,
        h1FontPx: h1Style ? parseFloat(h1Style.fontSize) : null,
        bodyFont,
        hasLandingCta: !!landingCta,
        landingCtaH2Font,
      };
    });

    if (result.hasHoneypot) {
      if (result.honeypotHeight > HONEYPOT_MAX_HEIGHT_PX) {
        errs.push(
          `honeypot wrapper has non-zero height (${result.honeypotHeight.toFixed(1)}px) — .honeypot-trap height:0 missing from inline CSS`,
        );
      }
      if (result.honeypotLeft > HONEYPOT_MIN_OFFSCREEN_LEFT_PX) {
        errs.push(
          `honeypot wrapper not positioned off-screen (left=${result.honeypotLeft.toFixed(1)}px) — .honeypot-trap left:-9999px missing from inline CSS`,
        );
      }
    }

    if (result.hasH1 && result.h1Top !== null && result.h1Top < HEADER_PX) {
      errs.push(
        `h1 above/under header (top=${result.h1Top.toFixed(1)}px, header=${HEADER_PX}px) — .page-hero/.landing-hero margin-top missing from inline CSS`,
      );
    }
    if (result.hasH1 && result.h1FontPx !== null && result.h1FontPx < H1_MIN_FONT_PX) {
      errs.push(
        `h1 too small (${result.h1FontPx}px < ${H1_MIN_FONT_PX}px) — page-hero/landing-hero h1 size missing from inline CSS`,
      );
    }

    // Body font is a global FOUC tripwire — if @layer base body { font-family: var(--font-body) }
    // is dropped from the inline block, every page falls back to browser default serif.
    if (!result.bodyFont.includes("inter")) {
      errs.push(
        `body font is "${result.bodyFont}" (expected to include "inter") — @layer base body { font-family } missing from inline CSS`,
      );
    }

    // .landing-cta h2 must use the display font on routes that have a CTA section.
    // Catches a regression where .landing-cta h2 { font-family: var(--font-display) }
    // is dropped from the inline block while .page-hero h1 still passes (the page-hero
    // h1 inherits Inter from body; without .landing-cta h2's display-font override
    // the CTA heading would fall back to Inter and visually break the design.)
    if (
      result.hasLandingCta &&
      result.landingCtaH2Font &&
      !result.landingCtaH2Font.includes("cormorant") &&
      !result.landingCtaH2Font.includes("garamond")
    ) {
      errs.push(
        `.landing-cta h2 uses "${result.landingCtaH2Font}" (expected display font: cormorant/garamond) — .landing-cta h2 font-family missing from inline CSS`,
      );
    }

    if (errs.length) {
      const slug =
        route.path === "/" ? "home" : route.path.replace(/^\/|\/$/g, "").replace(/\//g, "_");
      screenshotPath = resolve(FAILURE_DIR, `${slug}.png`);
      try {
        await page.screenshot({ path: screenshotPath, fullPage: true });
      } catch (err) {
        console.error(
          `screenshot-gate: screenshot capture failed for ${route.path}: ${err.message}`,
        );
        screenshotPath = undefined;
      }
    }
  } finally {
    await ctx.close();
  }

  return { route: route.path, errs, screenshot: screenshotPath };
}

// Bounded-pool runner: process up to POOL_SIZE routes concurrently. Each
// concurrent slot opens its own BrowserContext from the shared `browser`
// instance — Playwright's contexts are isolated cookie/cache jars, safe to
// run in parallel.
const allResults = [];
for (let i = 0; i < routes.length; i += POOL_SIZE) {
  const chunk = routes.slice(i, i + POOL_SIZE);
  const chunkResults = await Promise.all(chunk.map((r) => auditRoute(r)));
  allResults.push(...chunkResults);
}
const failures = allResults.filter((r) => r.errs.length > 0);

await browser.close();

if (JSON_OUTPUT) {
  // Machine-parseable summary. Stable schema:
  //   { status: "pass" | "fail", totalRoutes, failures: [{ route, errs: [string], screenshot?: string }] }
  const summary = {
    status: failures.length ? "fail" : "pass",
    totalRoutes: routes.length,
    failures: failures.map((f) => ({
      route: f.route,
      errs: f.errs,
      screenshot: f.screenshot,
    })),
  };
  process.stdout.write(JSON.stringify(summary) + "\n");
}

if (failures.length) {
  if (!JSON_OUTPUT) {
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
  }
  process.exit(1);
}

if (!JSON_OUTPUT) {
  console.log(`screenshot-gate: PASS (${routes.length} routes)`);
}
