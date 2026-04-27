# fix: Website visual regressions on /pricing, /blog, and add pre-deploy screenshot gate

**Status:** Deepened (2026-04-27)
**Date:** 2026-04-27
**Branch:** `feat-one-shot-website-visual-regressions`
**Type:** Bug fix (P0 production fire) + prevention infrastructure
**Detail level:** A LOT (production outage + new CI gate)

## Enhancement Summary

**Deepened on:** 2026-04-27
**Sections enhanced:** Hypotheses, Files to Edit, Implementation Phases (especially 2-5), Risks, Test Scenarios.
**Research applied:** Playwright `waitUntil` semantics (Microsoft Playwright docs), critical-CSS sizing under TCP slow-start (web.dev), grep-based template enumeration of every selector consumed above-the-fold across `plugins/soleur/docs/pages/` (n=20 templates), verbatim CSS rule extraction from `css/style.css` with line citations.

### Key Improvements vs. initial draft

1. **Playwright `waitUntil: 'commit'`** — initial draft used `'load'`, which waits for stylesheets including the swapped one. `'commit'` fires when the network response arrives but BEFORE DOM parse, then we assert against the DOM as parsed by Playwright at `'domcontentloaded'`. Confirmed via [Playwright API docs](https://playwright.dev/docs/api/class-page#page-goto): `'load'` waits for stylesheet load, which would silently mask the FOUC window.
2. **Honeypot bug is site-wide, not just `/pricing/`.** `_includes/newsletter-form.njk` includes the honeypot trap and is rendered in `base.njk` line 226 on EVERY page (including `/`, blog posts, every legal sub-page). Home page only "looks structurally okay" because the honeypot is below the fold. The fix MUST cover the global newsletter-form honeypot, not just the pricing waitlist form.
3. **Verbatim CSS values corrected.** Initial draft fabricated `.landing-cta` declarations as `border-top/bottom + padding var(--space-10)`. Actual rule (`css/style.css:731-746`) is `background: linear-gradient(180deg, var(--color-bg) 0%, var(--color-bg-tertiary) 100%); padding: var(--space-12) var(--space-5)`. Plan now cites verbatim values.
4. **`.landing-section` + `.section-title` + `.section-desc` added** to inline scope. They are above the fold on `/pricing/`, `/agents/`, `/skills/`, `/about/`, `/getting-started/` (the next section after the page hero).
5. **TCP slow-start budget verified.** Current inline `<style>` block ≈5.5KB. New additions (page-hero, landing-cta, landing-section, section-title/desc/label, honeypot-trap) add ~700 bytes minified. Total ~6.2KB. Well under the 14KB first-roundtrip ceiling per [web.dev/extract-critical-css](https://web.dev/articles/extract-critical-css).
6. **20-page enumeration.** `rg -l "page-hero|landing-cta|landing-section" plugins/soleur/docs/pages plugins/soleur/docs/_includes` returns 20 templates; route list in `screenshot-gate-routes.yaml` MUST cover the canonical 9 routes (pricing, blog, agents, skills, about, getting-started, community, changelog, vision) plus 9 legal sub-pages (deferrable to a second-pass after fix lands — legal pages are pure markdown content, less conversion-critical).
7. **Honeypot assertion strategy** changed from `getBoundingClientRect().width === 0` to `offsetHeight === 0 && offsetWidth === 0` (jsdom-safe; per AGENTS.md `cq-jsdom-no-layout-gated-assertions`, layout values can be 0 in jsdom — but Playwright runs real Chromium, so `getBoundingClientRect()` is reliable. We're not in jsdom; the rule does not apply. Keeping `getBoundingClientRect()` since it's more semantically correct in real browsers).

## Overview

Production (`https://www.soleur.ai`) is visually broken on every Eleventy page that is **not** `/` or `/blog/<slug>/`. The `/pricing/` and `/blog/` (index) pages render with default browser styles for the duration of the async stylesheet swap window, producing the symptoms reported by the user (white honeypot rectangle, overlapping headings, missing hero H1).

**Root cause: PR #2904 (commit `5e74b560`, "perf(docs): inline critical CSS + async stylesheet swap")** replaced the synchronous `<link rel="stylesheet">` with a `preload` + `onload`-swap pattern. The hand-extracted critical CSS subset only covers selectors used on `/` (`.landing-hero`, `.hero-waitlist-form`, `.landing-stats`) and `/blog/<post>/` (`.hero`, `.blog-post-meta`). It **does not** cover above-the-fold selectors used on other pages — most importantly `.page-hero`, `.landing-cta`, `.honeypot-trap`, `.section-label`, `.newsletter-form`, and `.waitlist-form` — so those pages render in FOUC until the async swap fires.

This is the **second time the same class of bug has shipped from PR #2904.** The first iteration (missing `.nav-cta-slot` / `.nav-cta` / `.btn--sm`) was caught and fixed in the same PR, and a learning was filed at `knowledge-base/project/learnings/best-practices/2026-04-27-hand-extracted-critical-css-misses-globally-rendered-selectors.md`. The learning correctly identified the structural problem ("selectors at first paint are distributed across `_data/site.json`, `base.njk`, and `css/style.css`; no single file shows the gap") but no durable mechanical gate was added, so the second iteration shipped within hours.

**Scope of this plan:**

1. **Immediate fix (P0):** Restore correct first-paint rendering on `/pricing/`, `/blog/` (index), and every other non-`/` non-`/blog/<post>/` page that uses `.page-hero` / `.landing-cta` / `.honeypot-trap` / `.section-label`.
2. **Durable prevention:** Add a Playwright-based visual smoke check to the `deploy-docs.yml` workflow that fails the build BEFORE GitHub Pages deployment if key routes (`/`, `/pricing/`, `/blog/`, `/agents/`, `/skills/`, `/about/`, `/getting-started/`) render with broken layout signals (visible honeypot, missing `.page-hero` height, stylesheet not yet applied at first contentful paint).
3. **Workflow gate:** Add an AGENTS.md `cq-` rule that the next change to `_includes/base.njk`'s critical-CSS block must include the new gate's output as a screenshot artifact in the PR.

## Symptoms (from user-supplied screenshots, 2026-04-27 17:28-17:29)

1. **`/pricing/` Image 1 + Image 4:** A blank white rectangle renders to the LEFT of the gold "Join the Waitlist" button, between the email input and the button. **Cause:** `<div class="honeypot-trap">` (containing `<input type="text" name="url">`) inside the form (`pages/pricing.njk` lines 35-37). The `.honeypot-trap` rule (`position:absolute; left:-9999px; height:0; overflow:hidden;`) lives at `css/style.css:1593-1598` but is NOT in the inline critical CSS, so until the async swap fires the honeypot div+input render in normal document flow.
2. **`/pricing/` Image 1 — heading overlap "Every department." / "One price.":** The `<h1>Every department.<br>One price.</h1>` (line 15 of `pages/pricing.njk`) is wrapped by `<section class="page-hero">`. The `.page-hero h1 { font-size: var(--text-4xl); margin-bottom: var(--space-4); letter-spacing: -0.02em; }` rule lives at `css/style.css:121` but is NOT inline. Without it, the H1 inherits `@layer base` defaults (font-size `var(--text-3xl)`, line-height 1.2, no letter-spacing) and the `<br>`-separated lines collide at the default line-height because the page does not yet have the page-hero's display-font scaling.
3. **`/blog/` Image 2 — missing H1/hero:** `pages/blog.njk` uses `<section class="page-hero"><h1>Blog</h1><p>Insights on agentic engineering...</p></section>`. Without `.page-hero` styles inline, the section has no `margin-top: var(--header-h)` (line 115 in `style.css`), so the H1 renders **behind** the fixed `.site-header` (which has `position:fixed; height:var(--header-h)` and IS inlined). The H1 + subtitle disappear under the header until the async swap fires.
4. **`/` Image 3:** Home page uses `.landing-hero`, which IS in the inline block, so the home page renders correctly. Symptom: "looks structurally okay" — confirms the regression is page-class scoped.

## Root Cause Analysis

### Why the screenshots show this state and not the post-swap state

The async swap pattern is:

```html
<link rel="preload" href="css/style.css" as="style" onload="this.onload=null;this.rel='stylesheet'">
<noscript><link rel="stylesheet" href="css/style.css"></noscript>
```

This depends on:

1. The browser supporting `<link rel="preload">` `onload` (modern browsers do).
2. The `onload` handler firing — which it does, on the order of 100-400ms after first paint depending on network.

User's screenshots (taken at 17:28-17:29 — Cloudflare Pages, `cache-control: max-age=14400`) likely caught the page during this swap window. The honeypot rectangle, missing hero, and overlapping H1 are all FOUC symptoms that resolve once the stylesheet swaps. The bug is **real** even if the post-swap state is correct: every first-time visitor to `/pricing/`, `/blog/`, `/agents/`, `/skills/`, `/about/`, `/getting-started/`, `/community/`, `/changelog/`, `/articles/`, `/company-as-a-service/`, `/legal/<sub>/` will see this for the first ~150-400ms of every cold load, and the broken pricing form is on the page that converts.

### Why mechanical gates didn't catch this

- `npx @11ty/eleventy` build → succeeds (no template errors).
- `validate-seo.sh _site` → passes (markup is correct).
- `validate-csp.sh _site` → passes (no new inline scripts).
- `Verify build output` (line 50 of `deploy-docs.yml`) → only `test -f` checks for file presence.
- No Playwright screenshot gate.
- The existing `scheduled-ux-audit.yml` workflow runs **monthly** on a cron and is **dry-run permanent** (per the workflow header comment) — it cannot serve as a deploy gate.

### Why the learning didn't prevent this

`knowledge-base/project/learnings/best-practices/2026-04-27-hand-extracted-critical-css-misses-globally-rendered-selectors.md` (filed earlier today as part of PR #2904) correctly identified the class but documented it as a *learning* — not as a workflow gate, AGENTS.md rule, or CI check. Per AGENTS.md `wg-when-a-workflow-gap-causes-a-mistake-fix`: "When a workflow gap causes a mistake, fix the skill or agent first — a learning is not a fix." The fix iteration before-merge addressed only the symptom the multi-agent review found (nav CTA), not the underlying gap (every page-class with above-fold styles outside `/` and `/blog/<post>/`).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| User said "Eleventy docs site lives in `apps/web-platform`" | Eleventy lives at repo root, building from `plugins/soleur/docs/`. `apps/web-platform/` is the Next.js Command Center app (different surface). | Plan targets `plugins/soleur/docs/` for fixes, `eleventy.config.js` at root, and `.github/workflows/deploy-docs.yml` for the gate. |
| User said "(possibly a duplicate input, a hidden honeypot field that's now visible, or a broken component)" | Confirmed: it's the honeypot field at `pages/pricing.njk:35-37`. The `.honeypot-trap` CSS rule exists and is correct in `css/style.css:1593`; the bug is exclusively that the rule is not in the inline critical block. | No template changes to the honeypot. CSS-only fix in `_includes/base.njk`. |
| User said "Home page... looks structurally okay" | Confirmed: home page uses `.landing-hero` which IS inlined. | Home is unaffected. Plan covers it in the screenshot gate to prevent regression. |

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned zero matches for `_includes/base.njk`, `css/style.css`, or `deploy-docs.yml` body content.

## Scope Expansion (deepen-pass finding)

The user's report named `/pricing/` and `/blog/` as the failing pages. The deepen pass uncovered that **the honeypot regression is site-wide**, not page-scoped:

- `_includes/newsletter-form.njk` contains `<div class="honeypot-trap"><input type="text" name="url"></div>` (verified at lines 14-16 of the include).
- `base.njk:226` includes `newsletter-form.njk` on every page (`{% include "newsletter-form.njk" %}`).
- Therefore EVERY page rendered through `base.njk` (which is every Eleventy page on the site) has the same broken-honeypot state during the FOUC window.

The user reported the home page as "looks structurally okay" — this is correct because the home page's honeypot is rendered in the footer newsletter form, far below the fold. A user scrolling to the bottom of the home page during the FOUC window WOULD see the broken honeypot rectangle there.

**Implication for fix:** `.honeypot-trap` MUST be inlined regardless of which pages we narrowly scope. It is NOT a `/pricing/`-only fix.

**Implication for the gate:** the screenshot gate must check ALL routes, including `/`, for the no-visible-honeypot assertion. If we scroll the page first (or check via `getBoundingClientRect()` even for off-screen elements), we catch the bug.

Concretely, the assertion `await page.locator('.honeypot-trap input[name="url"]').evaluate(el => el.getBoundingClientRect().width === 0 && el.getBoundingClientRect().height === 0)` works for off-screen elements because `getBoundingClientRect()` returns the element's box regardless of viewport position. The honeypot, if styled (`position:absolute; left:-9999px; height:0`), will report `width: 0, height: 0`. If un-styled, it reports the natural input box (~150x32px). Therefore the gate catches it without needing to scroll.

## Hypotheses

| # | Hypothesis | Evidence for | Evidence against | Verdict |
|---|---|---|---|---|
| H1 | PR #2904's critical CSS only covers `/` and `/blog/<post>/`; every other page renders in FOUC during the async swap window. | Inline block selector list (`base.njk:126-191`) lists `.landing-hero`, `.hero` (blog post), `.hero-waitlist-form`, `.blog-post-meta`. `.page-hero`, `.landing-cta`, `.honeypot-trap`, `.section-label` are absent. Production HTML for `/pricing/` and `/blog/` is structurally correct and references `<link rel="preload">`. | None. | **Confirmed.** |
| H2 | Cloudflare/GitHub Pages caching is serving a stale page version. | `last-modified` on `style.css` is 11:53; user screenshots at 17:28. | Same page reproduces with `curl -L`. The HTML uses the new pattern; the bug is the pattern itself. | Rejected. |
| H3 | A separate change (e.g., `c46b371f` SEO audit) modified `base.njk` in a breaking way. | `c46b371f` did touch `base.njk`. | The diff is one byte (a paragraph URL change in OG tag); does not touch CSS or layout. | Rejected. |
| H4 | The CSP `style-src` blocks the inline `<style>` block. | None. | CSP includes `'unsafe-inline'` for style-src; inline block parses and applies. | Rejected. |

**Conclusion:** H1 is the sole root cause. The fix is to either (a) widen the inline critical CSS to cover above-the-fold selectors for **every** page class, or (b) revert to a synchronous stylesheet for non-LCP-gated pages, or (c) generate the critical-CSS block at build time per-route. See "Alternative Approaches Considered" below.

## Files to Edit

- `plugins/soleur/docs/_includes/base.njk` — extend the inline critical CSS block to cover `.page-hero` (h1, p, container), `.landing-cta`, `.honeypot-trap`, `.section-label`, `.newsletter-form` (extend coverage), and the `.page-hero, .landing-hero { margin-top: 0 }` override at the bottom of `style.css:1610`. Update the regenerate comment with the additional grep-stable selector list.
- `.github/workflows/deploy-docs.yml` — insert a "Screenshot gate" step between `Verify build output` and `Setup Pages`. Step runs Playwright against a locally-served `_site/` (via `npx http-server _site -p 8888`), captures `/`, `/pricing/`, `/blog/`, `/agents/`, `/skills/`, `/about/`, `/getting-started/` at viewport 1440×900, and asserts:
  - The honeypot input (`input[name="url"]` inside `.honeypot-trap`) has `getBoundingClientRect().width === 0` (i.e., off-screen).
  - The first `<h1>` on each page has `getBoundingClientRect().top >= 56` (i.e., not behind the 3.5rem header).
  - The page's first `<h1>` `font-family` resolves to a `Cormorant Garamond` token (i.e., display font applied) on hero-using pages.
  Failure uploads the screenshot as a workflow artifact and fails the deploy.
- `AGENTS.md` — add a new `cq-` rule under "Code Quality" that PRs touching `plugins/soleur/docs/_includes/base.njk`'s critical-CSS block must include the screenshot-gate output as a PR artifact, AND grep-enumerate every `.page-hero` / `.landing-*` / `.section-*` selector against the inline block before merging. `**Why:** PR #2904 + this plan — second occurrence of same FOUC class within 8 hours.`

## Files to Create

- `plugins/soleur/docs/scripts/screenshot-gate.mjs` — Playwright script that boots `npx http-server`, navigates to each route in a route list, runs the assertions above, takes a full-page PNG, and exits non-zero on the first failure with a structured stderr message.
- `plugins/soleur/docs/scripts/screenshot-gate-routes.yaml` — declarative route list (`{path, viewport, expectedHero, expectedHoneypot}`) consumed by `screenshot-gate.mjs`. Source of truth for the gate.
- `tests/docs/screenshot-gate.test.sh` — bats-style smoke test (or a simple `node` driver) that runs `screenshot-gate.mjs` against the local `_site/` and asserts exit-code semantics. Wired into the existing `tests/` convention.

## Implementation Phases

### Phase 1 — Reproduce locally (15-30 min)

1. Build the site locally: `cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-website-visual-regressions && npx @11ty/eleventy`.
2. Serve `_site/`: `npx http-server _site -p 8888 -c-1` (cache disabled).
3. Use Playwright MCP to navigate `http://localhost:8888/pricing/` and `http://localhost:8888/blog/`. Slow the network throttle so the async swap window is visible. Take screenshots and confirm they reproduce the user's reports.
4. Verify the home page renders correctly (`landing-hero` inline path). This is the control case.
5. **Acceptance gate:** screenshots match user-reported symptoms 1, 2, 3.

### Phase 2 — Write the failing screenshot gate FIRST (TDD, per `cq-write-failing-tests-before`) (30-60 min)

Write the gate before fixing the CSS so the gate proves it actually catches the bug.

1. Create `plugins/soleur/docs/scripts/screenshot-gate-routes.yaml` with the canonical anonymous-marketing routes:
   - `/` (control — must always pass; uses `landing-hero` already inlined)
   - `/pricing/` (primary symptom: honeypot, heading overlap, hero margin)
   - `/blog/` (primary symptom: H1 hidden behind header)
   - `/agents/`, `/skills/`, `/about/`, `/getting-started/`, `/community/`, `/changelog/`, `/vision/`, `/company-as-a-service/`, `/articles/` (page-hero consumers — same FOUC class)
   - DEFER 9 `/legal/<sub>/` pages to a follow-up issue (markdown-rendered, lower conversion impact, longer tail).

   Each entry: `{path, viewport: {w: 1440, h: 900}, assertions: [no_visible_honeypot, h1_below_header, h1_uses_display_font]}`. The home `/` uses `landing-hero` not `page-hero`, so its `h1_uses_display_font` assertion still passes.

2. Create `plugins/soleur/docs/scripts/screenshot-gate.mjs`. Critical implementation notes from deepen-pass research:

   ### Research Insights — Playwright `waitUntil` selection

   **Playwright `page.goto({waitUntil})` semantics** (per [Playwright API docs](https://playwright.dev/docs/api/class-page#page-goto), verified 2026-04-27):

   - `'commit'` — fires when network response received, document started loading. Pre-DOM-parse.
   - `'domcontentloaded'` — DOM parsed, `<style>` blocks applied, async stylesheets NOT yet loaded. **This is the FOUC window.** ← USE THIS
   - `'load'` — all resources (including the swapped stylesheet) loaded. Post-FOUC. Would mask the bug.
   - `'networkidle'` — 500ms of zero network. Definitely post-swap.

   **Decision:** `waitUntil: 'domcontentloaded'` is the correct gate. The async stylesheet load via `<link rel="preload">` + `onload`-swap fires *after* `domcontentloaded` (the preload doesn't block DOM parsing — that's the whole point), so assertions at `domcontentloaded` see the inline-only state. This is exactly the user-visible FOUC window we need to gate.

   ```javascript
   import { chromium } from 'playwright';
   import { readFileSync } from 'node:fs';
   import { mkdirSync } from 'node:fs';
   import yaml from 'js-yaml'; // or hand-parse the YAML if we want zero deps

   const BASE = process.env.SCREENSHOT_GATE_BASE_URL || 'http://localhost:8888';
   const ROUTES = yaml.load(readFileSync('plugins/soleur/docs/scripts/screenshot-gate-routes.yaml', 'utf8')).routes;

   mkdirSync('screenshot-gate-failures', { recursive: true });

   const browser = await chromium.launch();
   const failures = [];

   for (const route of ROUTES) {
     const ctx = await browser.newContext({ viewport: route.viewport });
     const page = await ctx.newPage();
     await page.goto(`${BASE}${route.path}`, { waitUntil: 'domcontentloaded' });

     // Assertions run AGAINST the inline-CSS-only state (pre-swap)
     const result = await page.evaluate(() => {
       const honeypot = document.querySelector('.honeypot-trap input[name="url"]');
       const h1 = document.querySelector('main h1');
       const headerH = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--header-h')) || 3.5;
       const headerPx = headerH * 16; // rem to px
       return {
         honeypotVisible: honeypot ? (honeypot.getBoundingClientRect().width > 1 || honeypot.getBoundingClientRect().height > 1) : false,
         h1Top: h1 ? h1.getBoundingClientRect().top : null,
         headerPx,
         h1Font: h1 ? getComputedStyle(h1).fontFamily.toLowerCase() : '',
       };
     });

     const errs = [];
     if (result.honeypotVisible) errs.push('honeypot visible');
     if (result.h1Top !== null && result.h1Top < result.headerPx) errs.push(`h1 above header (top=${result.h1Top}, header=${result.headerPx})`);
     // h1_uses_display_font: ALL hero h1s should resolve to Cormorant. Home uses --font-display via .landing-hero h1. Page-hero h1s also need it. Skip if h1 is null.
     if (result.h1Font && !result.h1Font.includes('cormorant') && !result.h1Font.includes('garamond') && route.assertions.includes('h1_uses_display_font')) {
       errs.push(`h1 not display font: ${result.h1Font}`);
     }

     if (errs.length) {
       const slug = route.path.replace(/\//g, '_') || 'home';
       await page.screenshot({ path: `screenshot-gate-failures/${slug}.png`, fullPage: true });
       failures.push({ route: route.path, errs });
     }
     await ctx.close();
   }
   await browser.close();

   if (failures.length) {
     console.error('SCREENSHOT GATE FAILED:');
     failures.forEach(f => console.error(`  ${f.route}: ${f.errs.join('; ')}`));
     process.exit(1);
   }
   console.log(`Screenshot gate passed: ${ROUTES.length} routes`);
   ```

   **Why two display-font names** (`cormorant` OR `garamond`): per `style.css:52`, the font stack is `'Cormorant Garamond', Georgia, 'Times New Roman', serif` — the resolved `getComputedStyle(...).fontFamily` may return any of these. We accept both the brand font and its fallback name for robustness. **Better fix:** assert against `font-size: var(--text-4xl) === 3rem === 48px` instead, since that's the load-bearing visual property (`getComputedStyle().fontSize === '48px'`). The display font is decorative; the size is what causes the heading-overlap symptom.

   **Refinement:** replace `h1_uses_display_font` assertion with `h1_size_at_least_text_4xl` → `parseFloat(getComputedStyle(h1).fontSize) >= 40` (1px buffer on `var(--text-4xl) === 3rem`). This catches the actual user-visible bug (default `text-3xl: 2.25rem === 36px` instead of `text-4xl: 3rem === 48px`). Update YAML accordingly.

3. Run the gate against the current (buggy) `_site/`. **It must fail on `/pricing/`, `/blog/`, `/agents/`, `/skills/`, `/about/`, `/getting-started/`, etc. with the honeypot+h1 assertions.** This is the RED step. Do NOT proceed to Phase 3 until the gate fails on the bug it's supposed to catch.

4. Wire `tests/docs/screenshot-gate.test.sh` to invoke the gate against a known-bad fixture (HTML with no inline CSS at all) and assert exit-code 1, plus a known-good fixture (full inlined CSS) and assert exit-code 0. This is the gate-of-the-gate.

5. **Acceptance gate:** gate fails on current `_site/`; gate passes on a hand-built fixture that has the right CSS inlined. Captures saved to `screenshot-gate-failures/` for visual confirmation.

### Phase 3 — Widen the inline critical CSS (30-45 min)

Do this in `_includes/base.njk` between lines 133-191 (the existing `<style>` block).

Add the following selectors, copied **verbatim** from `css/style.css` with line citations per `cq-code-comments-symbol-anchors-not-line-numbers`. Sources verified during deepen pass with `grep -nE` against the live `css/style.css` (lines indicated):

```css
/* Page hero — style.css:111-122; used on /pricing/, /blog/, /agents/, /skills/, /about/, /getting-started/, /community/, /changelog/, /vision/, /company-as-a-service/, /articles/, /legal.njk, and 9 /legal/<sub>/ markdown pages */
.page-hero{background:var(--color-bg);color:var(--color-text);padding:var(--space-10) 0 var(--space-8);margin-top:var(--header-h);position:relative;text-align:center;border-bottom:1px solid var(--color-border)}
.page-hero .container{position:relative;z-index:1}
.page-hero h1{font-size:var(--text-4xl);margin-bottom:var(--space-4);letter-spacing:-0.02em}
.page-hero p{font-size:var(--text-lg);color:var(--color-text-secondary);max-width:600px;margin-inline:auto}

/* Landing CTA — style.css:731-746; used on /pricing/ #waitlist section */
.landing-cta{background:linear-gradient(180deg,var(--color-bg) 0%,var(--color-bg-tertiary) 100%);padding:var(--space-12) var(--space-5);text-align:center}
.landing-cta h2{font-family:var(--font-display);font-size:var(--text-4xl);font-weight:500;margin-bottom:var(--space-4)}
.landing-cta p{font-size:1.0625rem;color:var(--color-text-secondary);margin-bottom:var(--space-8)}

/* Landing section / section-label / section-title / section-desc — style.css:506-540; first content section after every page-hero */
.landing-section{padding:var(--space-10) var(--space-5)}
.landing-section-inner{max-width:1200px;margin-inline:auto}
.section-label{font-size:var(--text-xs);font-weight:600;letter-spacing:3px;color:var(--color-accent);text-transform:uppercase;text-align:center;margin-bottom:var(--space-4)}
.section-title{font-family:var(--font-display);font-size:2.625rem;font-weight:500;text-align:center;max-width:800px;margin-inline:auto;margin-bottom:var(--space-4);line-height:1.15}
.section-desc{font-size:1.0625rem;color:var(--color-text-secondary)}

/* Honeypot — style.css:1593-1598; used on EVERY page via _includes/newsletter-form.njk (footer) AND on /pricing/ via the waitlist form */
.honeypot-trap{position:absolute;left:-9999px;height:0;overflow:hidden}
```

**CRITICAL: VERBATIM transcription.** During deepen pass, the initial draft fabricated `.landing-cta` declarations (`border-top/bottom`, `padding var(--space-10)`). Actual values from `style.css:731-746` are `background: linear-gradient(...); padding: var(--space-12) var(--space-5)`. Implementer MUST `Read` `css/style.css` at the cited line ranges and copy declarations literally. Do NOT freestyle.

Update the regenerate-comment block (`base.njk` lines 126-132) to add grep-stable selector anchors:

```
.page-hero*, .landing-cta*, .landing-section*, .section-label, .section-title, .section-desc, .honeypot-trap
```

**Sanity grep before commit:**

```bash
# Every selector in the inline block must exist in style.css
for sel in '\.page-hero' '\.landing-cta' '\.landing-section' '\.section-label' '\.section-title' '\.section-desc' '\.honeypot-trap'; do
  grep -qE "^\s*${sel}\s*\{" plugins/soleur/docs/css/style.css || echo "MISSING: $sel"
done
```

### Phase 4 — Re-run the gate; it must now PASS (10 min)

1. Rebuild: `npx @11ty/eleventy`.
2. Re-run `node plugins/soleur/docs/scripts/screenshot-gate.mjs` against the new `_site/`.
3. **Acceptance gate:** all assertions pass on `/pricing/`, `/blog/`, `/agents/`, `/skills/`, `/about/`, `/getting-started/`. Screenshot `_site/pricing/` and `_site/blog/` for the PR description.

### Phase 5 — Wire the gate into `deploy-docs.yml` (30 min)

Insert between `Verify build output` and `Setup Pages`:

```yaml
- name: Install Playwright (Chromium only)
  run: |
    npm install --no-save playwright@1
    npx playwright install --with-deps chromium

- name: Screenshot gate
  run: |
    npx http-server _site -p 8888 -c-1 &
    SERVER_PID=$!
    sleep 2
    node plugins/soleur/docs/scripts/screenshot-gate.mjs
    GATE_EXIT=$?
    kill $SERVER_PID || true
    exit $GATE_EXIT

- name: Upload screenshot-gate artifacts on failure
  if: failure()
  uses: actions/upload-artifact@v4
  with:
    name: screenshot-gate-failures
    path: screenshot-gate-failures/
    retention-days: 14
```

**Pin `actions/upload-artifact` to a SHA, not `@v4`**, per existing workflow conventions in this repo.

Verify with `actionlint` if available, then push and watch the workflow run on a deliberately-broken fixture branch (e.g., temporarily revert one of the inlined selectors) before merging the real fix.

### Phase 6 — AGENTS.md rule + retroactive gate application (15 min)

Add to AGENTS.md "Code Quality" section. **Byte-budget aware** per `cq-agents-md-why-single-line` — the rule below is ~580 bytes, under the ~600 cap; the **Why** is single-sentence with a learning-file pointer:

```
- When modifying the critical-CSS block in `plugins/soleur/docs/_includes/base.njk`, the deploy-docs screenshot-gate (`scripts/screenshot-gate.mjs`) MUST pass against `_site/` for every route in `screenshot-gate-routes.yaml`, AND every `.page-hero*`, `.landing-*`, `.section-*`, `.honeypot-trap`, `.newsletter-form*` selector used in `plugins/soleur/docs/pages/**` or `_includes/**` MUST be in the inline `<style>` block [id: cq-eleventy-critical-css-screenshot-gate]. **Why:** PR #2904 shipped twice within 8 hours — hand-extraction missed `.nav-cta-slot` first iteration, then `.page-hero` + `.honeypot-trap` second iteration; see `knowledge-base/project/learnings/best-practices/2026-04-27-hand-extracted-critical-css-misses-globally-rendered-selectors.md`.
```

**Byte verification before commit:**

```bash
awk '/cq-eleventy-critical-css-screenshot-gate/ {print length}' AGENTS.md
# Must report under 600. Ideally under 580 to leave headroom.

# Total AGENTS.md must stay under 40000 (critical threshold).
wc -c AGENTS.md
# Pre-rule: 38360. Post-rule estimated: ~38960. Under threshold but warn-band.
# If post-rule > 40000, retire one rule via scripts/retired-rule-ids.txt before merging.
```

**Headroom warning:** AGENTS.md is at 38360 bytes pre-rule (above 37000 warn, below 40000 critical per `cq-agents-md-why-single-line`). Adding ~600 bytes lands at ~38960 — still under critical, but tight. If the implementer needs to expand the rule for clarity, audit `scripts/retired-rule-ids.txt` for an existing retirement opportunity first.

Per `wg-when-fixing-a-workflow-gates-detection` (Retroactive Gate Application), the new gate MUST also run against `main` (post-merge) to confirm no other production page is currently broken. If the gate finds additional FOUC-affected pages, fix them in the same PR.

**Retroactive coverage check:** before merging, run the gate against the FULL list of 20 templates that use `.page-hero` (enumerated via `rg -l "page-hero" plugins/soleur/docs/pages plugins/soleur/docs/_includes`). Add any additional failing pages to `screenshot-gate-routes.yaml` and verify the inline CSS covers their above-the-fold selectors. If new selectors are needed (e.g., a `.legal-toc` if any legal page renders one above the fold), add them in the same PR.

### Phase 7 — Local verification with Playwright (15 min)

Use Playwright MCP to:

1. Navigate to local `http://localhost:8888/pricing/` (post-fix). Verify visually that the form has no white rectangle, headings stack with proper rhythm, and the waitlist button is correctly aligned.
2. Navigate to `http://localhost:8888/blog/`. Verify the H1 is visible below the header.
3. Navigate to `http://localhost:8888/`. Verify no regression on the home page.
4. Take "after" screenshots and attach them to the PR description alongside the user's "before" screenshots.

**Acceptance gate:** side-by-side comparison shows all three symptoms resolved. No new symptoms introduced.

### Phase 8 — Throttle test (10 min)

Use Playwright MCP `browser_evaluate` with CDP `Network.emulateNetworkConditions` (Slow 3G profile) on `/pricing/` and `/blog/`. Capture screenshots at 200ms, 400ms, 800ms, and 2000ms after navigation start. Assert NO FOUC at ANY of those timestamps for the page-hero, honeypot, or landing-cta. This validates the fix is correct under realistic adverse network conditions, not just on the local fast connection.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `screenshot-gate.mjs` exits 0 against the post-fix `_site/`.
- [x] `screenshot-gate.mjs` exits 1 against a hand-built fixture missing one of the new inlined selectors (RED test passes — verified by `sed`-stripping `.honeypot-trap` from `base.njk` and running the gate; failure observed; rule restored).
- [x] `npx @11ty/eleventy` builds cleanly; `_site/pricing/index.html`, `_site/blog/index.html` contain the expanded inline critical CSS block.
- [x] `validate-seo.sh _site` and `validate-csp.sh _site` still pass.
- [ ] PR description includes side-by-side before (user's screenshots) and after (Playwright captures of `/pricing/`, `/blog/`, `/`). _Pending QA phase._
- [ ] Throttle test: Slow 3G capture at t=200ms shows no honeypot, hero visible below header, headings styled. _Deferred — gate is already deterministic across all routes via stylesheet-block strategy; throttle is redundant._
- [x] AGENTS.md rule `cq-eleventy-critical-css-screenshot-gate` added (558 bytes; total AGENTS.md 38918, under 40000 critical).
- [x] Plan and learning saved.
- [ ] PR body uses `Closes` for any related issues we file. _Pending /ship — will reference user's outage report and PR #2904._

### Post-merge (operator)

- [ ] `deploy-docs.yml` workflow run on `main` succeeds, including the new "Screenshot gate" step.
- [ ] Production https://www.soleur.ai/pricing/ and https://www.soleur.ai/blog/ verified visually correct from a fresh browser session (clear cache, throttle to Slow 3G if possible).
- [ ] If retroactive gate run on `main` revealed additional FOUC-affected pages, all of them are now passing.

## Test Scenarios

| Scenario | Page | Expected outcome |
|---|---|---|
| Cold load, fast network | `/pricing/` | Honeypot invisible, headings stacked correctly with display font, gold "Join the Waitlist" button left-aligned to email input. No white rectangle. |
| Cold load, Slow 3G | `/pricing/` | Same as above, even at t=200ms after `goto`. The gate passes because the inline `<style>` is in the same HTML response. |
| Cold load, fast network | `/blog/` | H1 "Blog" visible below the fixed header. Subtitle paragraph rendered below. No clipping. |
| Cold load, Slow 3G | `/blog/` | Same as above. |
| Cold load | `/` | Home page renders identically to pre-PR state (control). |
| Cold load | `/agents/`, `/skills/`, `/about/`, `/getting-started/` | All pass the screenshot gate. Caught any other FOUC-affected pages we missed. |
| JS disabled (`<noscript>`) | All pages | Synchronous `<link rel="stylesheet">` loads, page renders correctly. |
| First-load FCP | `/pricing/` | LCP target preserved (the original perf goal of PR #2831). Adding ~600 bytes of CSS to inline does not push HTML over the TCP slow-start window for typical CF responses (~14KB). |

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| **(A) Widen inline critical CSS to cover all page-classes** | Preserves PR #2904's perf gain (LCP improvement). Single-file change. Already proven pattern. | Hand-extraction is fragile — that's exactly how this bug shipped. Mitigated by the new screenshot gate. | **Chosen.** Combined with the gate, the gate makes this approach durable. |
| (B) Revert PR #2904 (synchronous `<link rel="stylesheet">`) | Simplest. Eliminates the FOUC class entirely. | Loses the LCP improvement that fixed #2831. Discards the multi-week investment. | Rejected. The gate makes (A) safe. |
| (C) Build-time critical-CSS extractor (`critical`, `penthouse`, etc.) | Mechanical, no hand-extraction drift. | New runtime dependency, longer build time, complex CI integration. Overkill for an Eleventy site with ~10 page templates. | Rejected for now. Filed as deferred capability `feat-build-time-critical-css-extractor` in roadmap "Post-MVP / Later" if (A) regresses again. |
| (D) Synchronous `<link>` for non-LCP-gated pages, async for `/` only | Targeted. Preserves home-page LCP. | Eleventy's `base.njk` is shared across all pages; conditional `{% if page.url == "/" %}` works but bifurcates the head. Maintenance burden. | Rejected. Cleaner to widen the inline block. |

## Non-Goals

- **NOT** changing the LCP/perf optimization strategy. PR #2904's intent is preserved.
- **NOT** adding a Percy/Chromatic-style pixel-diff regression service. The gate is layout-assertion-based (DOM bounding rects, computed font), not pixel comparison. Pixel diff is a separate capability with separate cost/value tradeoffs.
- **NOT** wiring the gate into `pull_request` events (only `push: main` via `deploy-docs.yml`). PR-level gating would require a different workflow that builds the site on PR — out of scope for this fire. Filed as a follow-up.
- **NOT** addressing the `apps/web-platform/` Next.js Command Center surface. The user's screenshots are all from the Eleventy marketing site.

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Inlining ~700 more bytes pushes the HTML response above the 14KB TCP slow-start window, regressing LCP. | Low. **Verified in deepen pass:** current inline block ~5.5KB; new additions (`.page-hero` + `.landing-cta` + `.landing-section` + `.section-label` + `.section-title` + `.section-desc` + `.honeypot-trap`) ~700 bytes minified. Total ~6.2KB. Well below the 14KB first-roundtrip ceiling per [web.dev/articles/extract-critical-css](https://web.dev/articles/extract-critical-css). Pricing page is currently 46KB uncompressed, ~12-15KB gzipped — adding 700 bytes minified ≈ 350 bytes gzipped. Single-digit percent overhead. | Measure post-fix HTML response size (`curl -sS https://www.soleur.ai/pricing/ \| wc -c`) and compare to pre-fix. Document in PR. Filed as deferred follow-up: when total inline block exceeds 9KB, switch to a build-time critical-CSS extractor (`critical`, `penthouse`, `beasties`) per the "Alternative Approaches Considered" option C. |
| The Playwright `goto` "load" event fires AFTER the async swap, so the gate doesn't actually catch the FOUC window. | **Resolved in deepen pass.** `waitUntil: 'load'` waits for ALL stylesheets (including the swapped one), masking the bug. | Phase 2 prescribes `waitUntil: 'domcontentloaded'` per [Playwright docs](https://playwright.dev/docs/api/class-page#page-goto): DOM parsed, inline `<style>` applied, async stylesheet NOT yet loaded. This IS the FOUC window. Phase 8 throttle test validates by capturing at multiple wall-clock checkpoints under Slow 3G. |
| `deploy-docs.yml` runs on `push: main`, not on PRs — so the gate fires AFTER merge, not before. | High by design (this is how `deploy-docs.yml` is structured today). | Phase 5 wires the gate into the deploy workflow. Filing a follow-up issue to also wire it as a `pull_request` check on the existing `ci.yml` workflow with separate caching. Out of scope to keep this P0 fix small. |
| Inline `<style>` block grows to the point of being unmaintainable. | Medium long-term. | The screenshot gate makes regressions immediate-feedback; the regenerate comment is grep-stable; if the block exceeds ~200 lines, reopen the build-time extractor decision (option C above). |
| Playwright in CI is heavy (chromium download ~300MB). | Low. Existing `ux-audit` workflow already provisions Playwright. Same caching applies. | Use `npx playwright install --with-deps chromium` (only chromium, not all browsers) and rely on GitHub Actions' `setup-node` npm cache. Expected step duration ~90s. |

## Open Questions

- **Q1:** Should the screenshot gate also run on PR events (via `ci.yml` or a dedicated PR-scoped workflow), in addition to `deploy-docs.yml`?
  - **Answer:** Yes, eventually — but defer to a follow-up issue. Today's P0 is to stop the bleeding.
- **Q2:** Should we backport the gate to also catch the original missing `.nav-cta-slot` regression from PR #2904?
  - **Answer:** Yes — assertion `nav_cta_styled` (computed `font-size <= 0.875rem` on the nav CTA) is a one-liner addition. Add it in Phase 2.
- **Q3:** Are there other `.page-hero`-using templates we're missing?
  - **Answer:** `rg "page-hero" plugins/soleur/docs/pages/ plugins/soleur/docs/blog/` returns the canonical list. Run the grep at start of work and confirm the route list in `screenshot-gate-routes.yaml` covers all of them.

## Domain Review

**Domains relevant:** Engineering (CTO), Marketing (CMO).

### Engineering (CTO)

**Status:** Routed via passive domain routing per AGENTS.md `pdr-when-a-user-message-contains-a-clear`. The signal is unambiguous (production visual outage on a docs-site CSS regression).

**Assessment:** This is a P0 production fire on the Eleventy marketing surface. The fix is mechanically simple (inline a few more CSS rules) but the prevention work matters more — the same class shipped twice in 8 hours, and the existing learning didn't prevent recurrence per `wg-when-a-workflow-gap-causes-a-mistake-fix`. The Phase 5 + Phase 6 prevention work is the load-bearing deliverable.

### Marketing (CMO) — website framing

**Status:** Routed because `/pricing/` is the conversion-critical page. Per `hr-before-shipping-ship-phase-5-5-runs`, CMO website-framing review is required for changes affecting `plugins/soleur/docs/pages/pricing.njk` or related conversion surfaces. **This plan does NOT change pricing copy or layout** — only fixes the broken first-paint render. CMO advisory: confirm post-fix screenshots match the approved pricing-page design (no copy changes, no layout shifts beyond restoring the intended state). Light-touch review.

### Product/UX Gate

**Tier:** ADVISORY (modifies first-paint render of existing user-facing pages; no new components or flows).
**Decision:** auto-accepted (pipeline). The fix restores the **intended** styling — it does not introduce new UX. UX artifacts already exist and are correctly reflected in `css/style.css`; the bug is purely that the inlined subset is incomplete.
**Agents invoked:** none (auto-accepted).
**Skipped specialists:** ux-design-lead (auto-accepted; restoring existing approved state, no new design), copywriter (no copy changes).
**Pencil available:** N/A (no new design).

## Telemetry

Emit on plan finalize:

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
  emit_incident wg-when-a-workflow-gap-causes-a-mistake-fix applied \
  "Critical-CSS FOUC class shipped twice from PR #2904 within 8 hours; previous learning did not prevent recurrence. Plan adds CI screenshot gate + AGENTS.md rule."
```

## Resume Prompt (for `/clear`)

```
/soleur:work knowledge-base/project/plans/2026-04-27-fix-website-visual-regressions-and-add-pre-deploy-screenshot-gate-plan.md

Context: branch feat-one-shot-website-visual-regressions, worktree .worktrees/feat-one-shot-website-visual-regressions/, P0 production visual outage on Eleventy /pricing/ and /blog/ from PR #2904's hand-extracted critical-CSS block. Fix: widen inline CSS in _includes/base.njk for .page-hero/.landing-cta/.honeypot-trap/.section-label, then add a Playwright screenshot gate to deploy-docs.yml + AGENTS.md cq- rule to prevent recurrence. Plan reviewed and ready; implementation next.
```
