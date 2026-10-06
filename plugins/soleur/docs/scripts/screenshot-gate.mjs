#!/usr/bin/env node
// Screenshot gate for the Eleventy docs site.
//
// Detects critical-CSS FOUC: pages that render with default browser styles in the
// window between DOMContentLoaded and the async stylesheet swap (the
// `<link rel="preload" ... onload="this.rel='stylesheet'">` pattern in base.njk).
//
// Strategy:
//   1. Block ALL external stylesheets at the network layer (`page.route("**/*.css", abort)`).
//      This pins the page in its inline-CSS-only state for every route's audit, so
//      assertions are deterministic regardless of `waitUntil` timing or which
//      additional stylesheets a future template might add. The one exception is the
//      homepage's separate full-stylesheet passes (`fullStyleErrors`, at phone and
//      route width), which open their own contexts WITH the stylesheet.
//   2. Navigate to each route and assert layout invariants that only hold when the
//      relevant selectors (`.page-hero`, `.honeypot-trap`, `.landing-cta`, ...) are
//      present in the inline `<style>` block.
//
// Exit codes:
//   0  all routes pass
//   1  one or more assertion failures (screenshots written to screenshot-gate-failures/)
//   2  bootstrap error (missing routes file, the routes file not listing the homepage,
//      browser launch failed, server unreachable)

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
// Homepage-only (#9579): the waitlist privacy line is load-bearing and sits
// above the fold, so the inline-CSS-only state must keep it BELOW the submit
// button (its flex-basis:100% lives in the inline block) and the page must not
// overflow horizontally on a phone. The routes file has one global viewport, so
// the inline-only phone check resizes the same page, and the full-stylesheet
// checks (phone and route viewport) each open their own browser context.
const HOME_PATH = "/";
const PHONE_VIEWPORT = { width: 390, height: 844 };

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

// The homepage block below is the gate for the hero privacy line. Without "/" in
// the routes file it would be skipped and the gate would exit 0 having checked nothing.
if (!routes.some((r) => r.path === HOME_PATH)) {
  console.error(`screenshot-gate: ${ROUTES_FILE} does not list the homepage route "${HOME_PATH}"`);
  process.exit(2);
}

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

// In-page reader for the hero privacy line (serialised by page.evaluate, so it
// must stay self-contained). Reports every way the line can be on the page yet
// not readable: hidden by itself or an ancestor, faded by the product of the
// ancestors' opacity, mostly clipped by an ancestor, off the viewport, positioned
// out of flow, clipped by clip/clip-path, indented away, transparent (colour or
// text-fill) or too close to its background (WCAG contrast under 4.5), covered by
// another element at its centre, or too small to read. Also checks the submit
// button is there. Colours go through a canvas so oklch(), color-mix() and the like
// are read as the browser resolves them.
function readPrivacyVisibility() {
  const el = document.getElementById("homepage-waitlist-privacy");
  const submit = document.querySelector("#homepage-waitlist-form button[type='submit']");
  const why = [];
  const cv = document.createElement("canvas");
  cv.width = cv.height = 1;
  const cx = cv.getContext("2d", { willReadFrequently: true });
  const rgba = (str) => {
    cx.clearRect(0, 0, 1, 1);
    cx.fillStyle = "#000";
    cx.fillStyle = str;
    cx.fillRect(0, 0, 1, 1);
    const d = cx.getImageData(0, 0, 1, 1).data;
    return { r: d[0], g: d[1], b: d[2], a: d[3] / 255 };
  };
  const blend = (fg, bg) => ({
    r: fg.r * fg.a + bg.r * (1 - fg.a),
    g: fg.g * fg.a + bg.g * (1 - fg.a),
    b: fg.b * fg.a + bg.b * (1 - fg.a),
    a: 1,
  });
  const lum = (c) => {
    const f = (v) => {
      const x = v / 255;
      return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
  };
  const ratio = (a, b) => {
    const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x);
    return (hi + 0.05) / (lo + 0.05);
  };
  if (!el) return { found: false, why: ["privacy line not found"] };
  // Geometry is read BEFORE any scrolling: scrollIntoView would also scroll a clipping
  // ancestor (an overflow:hidden box is still programmatically scrollable) and pull the
  // line back into view, which would hide exactly the clip this reader exists to see.
  const cs = getComputedStyle(el);
  const r = el.getBoundingClientRect();
  // Read with the same scroll position as `r`, so the two compare.
  const submitBottom = submit ? submit.getBoundingClientRect().bottom : null;
  let opacity = 1;
  let bg = null;
  for (let n = el; n && n.nodeType === 1; n = n.parentElement) {
    const c = getComputedStyle(n);
    const tag = n === el ? "line" : n.tagName.toLowerCase();
    opacity *= parseFloat(c.opacity);
    if (c.display === "none") why.push(`${tag} display:none`);
    if (c.clipPath && c.clipPath !== "none") why.push(`${tag} clip-path:${c.clipPath}`);
    if (n !== el && (c.overflowX !== "visible" || c.overflowY !== "visible")) {
      const ar = n.getBoundingClientRect();
      const w = Math.max(0, Math.min(r.right, ar.right) - Math.max(r.left, ar.left));
      const h = Math.max(0, Math.min(r.bottom, ar.bottom) - Math.max(r.top, ar.top));
      const area = r.width * r.height;
      if (area > 0 && (w * h) / area < 0.9) why.push(`${tag} clips the line (${Math.round(((w * h) / area) * 100)}% visible)`);
    }
    if (!bg) {
      // The first ancestor with any background colour decides the contrast. Its alpha is
      // not blended outward (a translucent card over a different page colour reads as
      // opaque): the limit is accepted because the hero card is opaque.
      const b = rgba(c.backgroundColor);
      if (b.a > 0) bg = b;
    }
  }
  if (cs.visibility !== "visible") why.push(`visibility:${cs.visibility}`);
  if (opacity < 1) why.push(`effective opacity ${opacity}`);
  if (cs.position === "absolute" || cs.position === "fixed") why.push(`position:${cs.position}`);
  if (cs.clip && cs.clip !== "auto") why.push(`clip:${cs.clip}`);
  if (parseFloat(cs.textIndent) <= -100) why.push(`text-indent:${cs.textIndent}`);
  const fontPx = parseFloat(cs.fontSize);
  if (fontPx < 10) why.push(`font ${fontPx}px`);
  if (r.height < 8 || r.width < 100) why.push(`box ${r.width}x${r.height}`);
  // Outside the page, not outside the first screen: below the fold is where a hero line
  // normally sits on a phone, so only the horizontal extent and the document's top count.
  if (r.right <= 0 || r.left >= window.innerWidth || r.bottom + window.scrollY <= 0) why.push("outside the page");
  const page = bg ?? { r: 255, g: 255, b: 255, a: 1 };
  const fg = rgba(cs.webkitTextFillColor || cs.color);
  if (fg.a === 0) {
    why.push("transparent text");
  } else {
    const c = ratio(blend(fg, page), page);
    if (c < 4.5) why.push(`contrast ${c.toFixed(2)}:1 against its background (needs 4.5)`);
  }
  // The hit test needs the point on screen: scroll the WINDOW only (instant, because the
  // site sets smooth scrolling), then read the line's centre again.
  window.scrollTo({ top: Math.max(0, window.scrollY + r.top - window.innerHeight / 2), left: 0, behavior: "instant" });
  const r2 = el.getBoundingClientRect();
  const hit = document.elementFromPoint(r2.left + r2.width / 2, r2.top + r2.height / 2);
  if (!hit || (hit !== el && !el.contains(hit))) {
    why.push(`covered at its centre by ${hit ? hit.tagName.toLowerCase() + (hit.className ? "." + String(hit.className).split(/\s+/)[0] : "") : "nothing"}`);
  }
  if (!submit) why.push("submit button missing");
  else {
    const sr = submit.getBoundingClientRect();
    if (getComputedStyle(submit).display === "none" || sr.height < 8 || sr.width < 8) why.push("submit button not rendered");
  }
  return {
    found: true,
    why,
    top: r.top,
    submitBottom,
    scrollWidth: document.documentElement.scrollWidth,
    clientWidth: document.documentElement.clientWidth,
  };
}

// Full-stylesheet state of the homepage at one viewport. The inline-only pass cannot
// see a rule in style.css that hides the privacy line or widens the form, and a rule
// can be scoped to a width, so this runs at the phone AND the route viewport. Never
// throws: a failure to reach that state is reported as an error string, with the other
// routes' results kept.
async function fullStyleErrors(vp, label) {
  let ctx;
  const errs = [];
  try {
    ctx = await browser.newContext({ viewport: vp });
    const page = await ctx.newPage();
    try {
      await page.goto(`${BASE_URL}${HOME_PATH}`, { waitUntil: "load", timeout: NAV_TIMEOUT_MS });
    } catch (err) {
      return [`${label} full-stylesheet navigation failed: ${err.message.split("\n")[0]}`];
    }
    // The stylesheet swaps in after load: wait until the preload link has become a
    // stylesheet AND style.css is in document.styleSheets with rules. A link whose
    // `rel` flipped but whose sheet never applied would otherwise read the
    // inline-only state as the full-stylesheet one.
    try {
      await page.waitForFunction(
        () => {
          if (document.getElementById("soleur-css-preload")?.rel !== "stylesheet") return false;
          try {
            return [...document.styleSheets].some((sh) => /\/css\/style\.css/.test(sh.href || "") && sh.cssRules.length > 0);
          } catch {
            return false;
          }
        },
        null,
        { timeout: NAV_TIMEOUT_MS },
      );
    } catch (err) {
      return [`${label} full-stylesheet state not reached: style.css did not apply within ${NAV_TIMEOUT_MS}ms (${err.message.split("\n")[0]})`];
    }
    const m = await page.evaluate(readPrivacyVisibility);
    if (m.scrollWidth > m.clientWidth) {
      errs.push(`homepage overflows horizontally at ${vp.width}px with the full stylesheet (scrollWidth=${m.scrollWidth} > clientWidth=${m.clientWidth})`);
    }
    if (m.why.length) {
      errs.push(`hero privacy line is not readable at ${label} width with the full stylesheet: ${m.why.join("; ")}`);
    } else if (m.submitBottom !== null && m.top < m.submitBottom - 1) {
      errs.push(`hero privacy line (top=${m.top.toFixed(1)}px) is not below the submit button (bottom=${m.submitBottom.toFixed(1)}px) at ${label} width with the full stylesheet`);
    }
    if (errs.length) {
      const shot = resolve(FAILURE_DIR, `home-${label}-full-stylesheet.png`);
      try {
        await page.screenshot({ path: shot, fullPage: true });
        errs.push(`screenshot of the ${label} full-stylesheet state: ${shot}`);
      } catch (err) {
        console.error(`screenshot-gate: ${label} full-stylesheet screenshot failed: ${err.message}`);
      }
    }
  } catch (err) {
    errs.push(`${label} full-stylesheet pass failed: ${err.message.split("\n")[0]}`);
  } finally {
    if (ctx) await ctx.close().catch(() => {});
  }
  return errs;
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
      const privacy = document.getElementById("homepage-waitlist-privacy");
      const submit = document.querySelector("#homepage-waitlist-form button[type='submit']");
      const card = document.querySelector(".hero-waitlist-form-card");
      const plan = document.querySelector(".landing-hero-plan");
      return {
        cardBorderPx: card ? parseFloat(getComputedStyle(card).borderTopWidth) : null,
        planDisplay: plan ? getComputedStyle(plan).display : null,
        hasHomeForm: !!privacy && !!submit,
        privacyTop: privacy ? privacy.getBoundingClientRect().top : null,
        submitBottom: submit ? submit.getBoundingClientRect().bottom : null,
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

    if (route.path === HOME_PATH) {
      if (!result.hasHomeForm) {
        errs.push("homepage hero waitlist form missing its privacy line or submit button");
      } else {
        if (result.privacyTop < result.submitBottom - 1) {
          errs.push(
            `hero privacy line (top=${result.privacyTop.toFixed(1)}px) is not below the submit button (bottom=${result.submitBottom.toFixed(1)}px) — the hero form layout rules are missing from the inline CSS`,
          );
        }
        const visible = await page.evaluate(readPrivacyVisibility);
        if (visible.why.length) {
          errs.push(`hero privacy line is not readable in the inline-CSS-only state: ${visible.why.join("; ")}`);
        }
      }
      // The hosted card and the two-sentence plan line are styled only by inline
      // rules before the stylesheet swaps; a dropped rule collapses them into
      // unstyled blocks (a visible layout jump at swap).
      if (result.cardBorderPx === null || result.cardBorderPx < 1) {
        errs.push(".hero-waitlist-form-card has no border — its inline rule is missing from the critical CSS");
      }
      if (result.planDisplay !== "grid") {
        errs.push(`.landing-hero-plan display is "${result.planDisplay}" (expected grid) — its inline rule is missing from the critical CSS`);
      }
      // Phone width, inline-CSS-only: resize the same page after the desktop reads.
      await page.setViewportSize(PHONE_VIEWPORT);
      const phone = await page.evaluate(() => ({
        scrollWidth: document.documentElement.scrollWidth,
        clientWidth: document.documentElement.clientWidth,
      }));
      if (phone.scrollWidth > phone.clientWidth) {
        errs.push(
          `homepage overflows horizontally at ${PHONE_VIEWPORT.width}px (scrollWidth=${phone.scrollWidth} > clientWidth=${phone.clientWidth}) in the inline-CSS-only state`,
        );
      }
      errs.push(...(await fullStyleErrors(PHONE_VIEWPORT, "phone")));
      errs.push(...(await fullStyleErrors(viewport, "desktop")));
    }

    if (errs.length) {
      if (route.path === HOME_PATH) await page.setViewportSize(viewport).catch(() => {});
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
