#!/usr/bin/env node
// Static selector-coverage check for the inline critical-CSS block in
// _includes/base.njk.
//
// The Playwright screenshot gate (`screenshot-gate.mjs`) catches FOUC for the
// specific assertions it knows about (`.page-hero`, `.honeypot-trap`,
// `.landing-cta h2`, body font, h1 size). It cannot catch a regression for a
// NEW above-fold component class added to a future template (e.g.,
// `.feature-grid`, `.testimonial-row`, `.product-spec-card`).
//
// This static check enumerates every class used in `pages/**` and `_includes/**`
// that matches an above-fold prefix pattern, then asserts each class has at
// least one CSS rule in the inline `<style>` block of any built page (the inline
// block is identical across pages).
//
// Run AFTER `npx @11ty/eleventy` (needs _site/) and before the screenshot gate.
//
// Exit codes:
//   0  every above-fold class has a corresponding rule in the inline block
//   1  one or more classes have no inline rule — FOUC class regression risk
//   2  bootstrap error (no _site/ build, missing base.njk)

import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "../../../..");
const TEMPLATE_ROOTS = [
  resolve(REPO_ROOT, "plugins/soleur/docs/pages"),
  resolve(REPO_ROOT, "plugins/soleur/docs/_includes"),
];
const SITE_ROOT = resolve(REPO_ROOT, "_site");
// Any built page contains the same inline <style> block from base.njk.
// /pricing/index.html is a deterministic choice (always built, always uses the layout).
const SAMPLE_BUILT_PAGE = resolve(SITE_ROOT, "pricing/index.html");

// Class-name prefixes that indicate an above-the-fold component class.
// Add to this list when introducing a new component prefix that may appear at
// first paint (e.g., a future ".banner-*" announcement bar).
const ABOVE_FOLD_PREFIXES = [
  "page-hero",
  "landing-hero",
  "landing-cta",
  "landing-section",
  "section-label",
  "section-title",
  "section-desc",
  "honeypot-trap",
  "site-header",
  "header-mark",
  "header-name",
  "nav-links",
  "nav-cta",
  "nav-cta-slot",
  "nav-toggle",
  "skip-link",
  "newsletter-form",
  "hero-waitlist-form",
  "blog-post-meta",
];

// Allowlist: classes used only inside a <noscript> or print-media context, or
// known to be below-the-fold despite matching a prefix. Empty for now; extend
// when a false-positive surfaces.
const ALLOWLIST = new Set([]);

// TCP slow-start window for HTML responses is ~14KB pre-gzip. The HTML response
// also includes JSON-LD, CSP meta, og: tags, etc. — the inline <style> block can
// safely consume most of it but not all. Warn at 9KB gzipped, fail at 11KB:
// at >11KB the inline block alone risks pushing the HTML response across the
// initial-congestion-window boundary, regressing the LCP gain that originally
// motivated PR #2904.
const INLINE_CSS_WARN_GZIPPED_BYTES = 9 * 1024;
const INLINE_CSS_FAIL_GZIPPED_BYTES = 11 * 1024;

function listFiles(root, ext) {
  const out = [];
  if (!existsSync(root)) return out;
  for (const entry of readdirSync(root)) {
    const full = join(root, entry);
    const st = statSync(full);
    if (st.isDirectory()) out.push(...listFiles(full, ext));
    else if (full.endsWith(ext)) out.push(full);
  }
  return out;
}

function extractClassesFromTemplates() {
  const used = new Map(); // class -> Set<file>
  const classAttrRe = /class\s*=\s*"([^"]+)"/g;
  for (const root of TEMPLATE_ROOTS) {
    for (const file of listFiles(root, ".njk")) {
      const src = readFileSync(file, "utf8");
      let m;
      while ((m = classAttrRe.exec(src)) !== null) {
        for (const cls of m[1].split(/\s+/).filter(Boolean)) {
          // Skip Nunjucks expressions like {{ foo }} that may appear inside class=""
          if (cls.includes("{") || cls.includes("}")) continue;
          // Skip anything that doesn't look like a single CSS class token
          if (!/^[A-Za-z][\w-]*$/.test(cls)) continue;
          if (!used.has(cls)) used.set(cls, new Set());
          used.get(cls).add(file);
        }
      }
    }
  }
  return used;
}

function isAboveFold(cls) {
  if (ALLOWLIST.has(cls)) return false;
  return ABOVE_FOLD_PREFIXES.some((prefix) => cls === prefix || cls.startsWith(prefix + "-"));
}

function extractInlineStyleBlock(htmlPath) {
  if (!existsSync(htmlPath)) {
    console.error(`check-critical-css-coverage: built page not found: ${htmlPath}`);
    console.error("  Run `npx @11ty/eleventy` first.");
    process.exit(2);
  }
  const html = readFileSync(htmlPath, "utf8");
  const m = html.match(/<style>([\s\S]*?)<\/style>/);
  if (!m) {
    console.error(`check-critical-css-coverage: no <style> block found in ${htmlPath}`);
    process.exit(2);
  }
  // Strip CSS /* ... */ comments. Comments may name selectors as documentation,
  // and we don't want a documented selector to count as an inlined rule.
  return m[1].replace(/\/\*[\s\S]*?\*\//g, "");
}

const usedClasses = extractClassesFromTemplates();
const aboveFoldClasses = [...usedClasses.keys()].filter(isAboveFold).sort();

if (aboveFoldClasses.length === 0) {
  console.error(
    "check-critical-css-coverage: no above-fold classes discovered — check ABOVE_FOLD_PREFIXES",
  );
  process.exit(2);
}

const inlineCss = extractInlineStyleBlock(SAMPLE_BUILT_PAGE);

const missing = [];
for (const cls of aboveFoldClasses) {
  const escaped = cls.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  // Match `.<class>` followed by a non-class boundary (space, comma, `:`, `{`, end).
  const ruleRe = new RegExp(`\\.${escaped}(?![\\w-])`);
  if (!ruleRe.test(inlineCss)) {
    const usedIn = [...usedClasses.get(cls)].map((f) => f.replace(REPO_ROOT + "/", "")).slice(0, 3);
    missing.push({ cls, usedIn });
  }
}

// Size guard: gzipped inline-CSS budget. We're a CI gate — measure on the actual
// rendered output, not the source file (Nunjucks templating may expand vars).
const inlineGzipped = gzipSync(Buffer.from(inlineCss, "utf8")).length;

if (missing.length) {
  console.error("check-critical-css-coverage: FAIL");
  console.error(
    `  ${missing.length} above-fold class(es) used in templates but missing from inline <style> in ${SAMPLE_BUILT_PAGE.replace(REPO_ROOT + "/", "")}:`,
  );
  for (const { cls, usedIn } of missing) {
    console.error(`    .${cls}  (used in: ${usedIn.join(", ")})`);
  }
  console.error(
    "  Add a rule for each missing class to the inline <style> block in plugins/soleur/docs/_includes/base.njk,",
  );
  console.error(
    "  OR extend ABOVE_FOLD_PREFIXES / ALLOWLIST in this script if the class is genuinely below the fold.",
  );
  process.exit(1);
}

if (inlineGzipped > INLINE_CSS_FAIL_GZIPPED_BYTES) {
  console.error(
    `check-critical-css-coverage: FAIL — inline <style> block is ${inlineGzipped} bytes gzipped (cap ${INLINE_CSS_FAIL_GZIPPED_BYTES})`,
  );
  console.error(
    "  At this size the HTML response risks crossing the TCP slow-start window (~14KB), undoing PR #2904's LCP gain.",
  );
  console.error(
    "  Switch the docs site to a build-time critical-CSS extractor (e.g., `beasties`, `critical`, `penthouse`) or split per-template inline blocks.",
  );
  process.exit(1);
}

const sizeNote =
  inlineGzipped > INLINE_CSS_WARN_GZIPPED_BYTES
    ? ` — WARN: inline CSS ${inlineGzipped}B gzipped, near ${INLINE_CSS_FAIL_GZIPPED_BYTES}B cap`
    : ` (inline CSS ${inlineGzipped}B gzipped, under ${INLINE_CSS_WARN_GZIPPED_BYTES}B warn)`;

console.log(
  `check-critical-css-coverage: PASS (${aboveFoldClasses.length} above-fold classes, all present in inline CSS)${sizeNote}`,
);
