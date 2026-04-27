#!/usr/bin/env node
// Regression gate for the post-load stylesheet swap on the Eleventy docs site.
//
// The site uses a `<link rel="preload">` + scripted `rel='stylesheet'` swap to
// improve LCP. This gate verifies the swap actually fires and applies the full
// stylesheet — catching a class of bug the screenshot gate (which blocks CSS)
// cannot detect.
//
// Detected failure classes:
//   1. CSP `script-src` blocks the swap script (no `'unsafe-inline'`,
//      `'unsafe-hashes'`, or matching SHA-256 hash). The link's `rel` stays
//      `preload` and style.css never applies. Original symptom in PR after
//      #2960: every page below the inline-CSS region rendered unstyled in
//      browsers with JavaScript enabled.
//   2. The swap script throws (referenced ID missing, addEventListener
//      unavailable, etc.) leaving rel as `preload`.
//   3. `style.css` fails to load (404, MIME type, blocked by CSP `style-src`).
//
// Strategy: navigate without blocking external CSS, wait for `'load'`, then
// assert (a) the link's `rel` is `stylesheet`, (b) a below-the-fold rule from
// `style.css` is applied (e.g., `.site-footer` padding-top from `var(--space-8)`),
// (c) no CSP violations in the console log.
//
// Exit codes:
//   0  swap fires on every probed route
//   1  one or more routes failed (rel not swapped, computed style missing, or CSP violation)
//   2  bootstrap error (browser launch failed, server unreachable)

import { chromium } from "playwright";

const BASE_URL = process.env.SCREENSHOT_GATE_BASE_URL || "http://127.0.0.1:8888";

// Probe routes. The swap mechanism is identical across all pages (defined in
// `_includes/base.njk`), so probing 3 representative pages is sufficient.
// The screenshot gate covers per-route inline-CSS regressions.
const ROUTES = ["/", "/pricing/", "/blog/"];

// var(--space-8) is `3rem`; the docs site uses the browser default 16px root
// font size, so .site-footer padding-top is 48px when style.css is applied.
// Default <footer> padding is 0.
const FOOTER_PADDING_MIN_PX = 30;

const NAV_TIMEOUT_MS = 15_000;

let browser;
try {
  browser = await chromium.launch();
} catch (err) {
  console.error("check-stylesheet-swap: failed to launch chromium:", err.message);
  process.exit(2);
}

try {
  const probe = await fetch(`${BASE_URL}/`, { method: "HEAD" });
  void probe;
} catch (err) {
  console.error(`check-stylesheet-swap: server unreachable at ${BASE_URL}: ${err.message}`);
  await browser.close();
  process.exit(2);
}

const failures = [];

for (const path of ROUTES) {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  const cspViolations = [];

  page.on("console", (msg) => {
    if (msg.type() === "error" && msg.text().includes("Content-Security-Policy")) {
      cspViolations.push(msg.text());
    }
  });

  try {
    await page.goto(`${BASE_URL}${path}`, { waitUntil: "load", timeout: NAV_TIMEOUT_MS });
    const result = await page.evaluate(() => {
      const link = document.getElementById("soleur-css-preload");
      const footer = document.querySelector(".site-footer");
      const footerCs = footer ? getComputedStyle(footer) : null;
      return {
        linkPresent: !!link,
        linkRel: link ? link.rel : null,
        footerPaddingTop: footerCs ? parseFloat(footerCs.paddingTop) : null,
      };
    });

    const errs = [];
    if (!result.linkPresent) {
      errs.push("`#soleur-css-preload` link not in DOM — base.njk swap structure changed");
    } else if (result.linkRel !== "stylesheet") {
      errs.push(
        `link rel is "${result.linkRel}" after load — swap script did not fire (CSP block? script error?)`,
      );
    }
    if (result.footerPaddingTop !== null && result.footerPaddingTop < FOOTER_PADDING_MIN_PX) {
      errs.push(
        `.site-footer padding-top=${result.footerPaddingTop}px (<${FOOTER_PADDING_MIN_PX}px) — full stylesheet did not apply`,
      );
    }
    if (cspViolations.length) {
      errs.push(`CSP violations (${cspViolations.length}): ${cspViolations[0].slice(0, 120)}`);
    }

    if (errs.length) failures.push({ path, errs });
  } catch (err) {
    failures.push({ path, errs: [`navigation failed: ${err.message}`] });
  } finally {
    await ctx.close();
  }
}

await browser.close();

if (failures.length) {
  console.error("check-stylesheet-swap: FAIL");
  for (const f of failures) {
    console.error(`  ${f.path}`);
    for (const e of f.errs) console.error(`    - ${e}`);
  }
  process.exit(1);
}

console.log(`check-stylesheet-swap: PASS (${ROUTES.length} routes; swap fires, full stylesheet applies)`);
