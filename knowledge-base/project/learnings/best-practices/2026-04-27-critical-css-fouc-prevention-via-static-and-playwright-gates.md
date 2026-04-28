---
module: docs-site
date: 2026-04-27
problem_type: integration_issue
component: eleventy_critical_css
symptoms:
  - "Production /pricing/ rendered a visible white honeypot rectangle next to the gold Join the Waitlist button"
  - ".page-hero h1 'Every department.' / 'One price.' collapsed without margin during the async stylesheet swap window"
  - "/blog/ index H1 hidden behind the fixed .site-header (no .page-hero margin-top: var(--header-h))"
  - "Symptom class shipped twice within 8 hours of PR #2904 — first iteration fixed only the multi-agent reviewer's surface findings (.nav-cta-slot), missed the underlying gap"
root_cause: hand_extracted_critical_css_subset_only_covered_homepage_and_blog_post_selectors
severity: critical
tags:
  - critical-css
  - fouc
  - eleventy
  - playwright
  - workflow-gate
  - prevention-infrastructure
synced_to: []
---

# Critical-CSS FOUC prevention via static + Playwright gates

## Problem

PR #2904 (commit `5e74b56`) introduced a `<link rel="preload" ... onload="this.rel='stylesheet'">` async-swap pattern for `css/style.css` to improve LCP, with a hand-extracted critical-CSS subset inlined into `_includes/base.njk`. The subset only covered selectors used on `/` (`.landing-hero*`, `.hero-waitlist-form*`, `.landing-stats*`) and individual blog posts (`.hero`, `.blog-post-meta`).

Every other Eleventy docs page — `/pricing/`, `/blog/` (index), `/agents/`, `/skills/`, `/about/`, `/getting-started/`, `/community/`, `/changelog/`, `/vision/`, `/legal/`, plus 9 `/legal/<sub>/` pages — uses `.page-hero` and/or `.landing-cta` and/or `.honeypot-trap`. None of those selectors were in the inline block. Result: every cold load on every non-`/`/non-blog-post page rendered with default browser styles for the ~150-400 ms swap window. User-reported symptoms hit the conversion-critical `/pricing/` page directly.

This was the **second iteration** of the same regression class within 8 hours. The first iteration (missing `.nav-cta-slot`/`.nav-cta`/`.btn--sm`) was caught by multi-agent review on PR #2904 and fixed in the same PR. A learning was filed naming the class but the only mechanical safeguard added was prose. The second iteration shipped through that prose with zero detection.

## Root cause

Hand-extraction of critical CSS is allowlist-shaped on a moving-target denominator. The set of selectors at first paint is the union of every `class="..."` attribute rendered above the fold across every template — a cross-cutting concern that:

- has no canonical enumeration in any single file,
- changes whenever a new component class is added to a template,
- silently fails (FOUC, not an error) when the inline block falls behind the templates,
- is invisible to existing gates (`validate-seo.sh`, `validate-csp.sh`, `npx @11ty/eleventy`, `test -f` artifact checks).

The async swap pattern preserves the LCP win (which is real and large), so reverting is undesirable. The fix has to make hand-extraction safe — i.e., add the missing detection layer.

## Solution

Three layers of mechanical detection plus a doctrinal rule, landed in PR #2960:

### Layer 1 — widen the inline `<style>` block (immediate fix)

In `plugins/soleur/docs/_includes/base.njk`, add verbatim copies (with grep-stable selector-anchor comments per `cq-code-comments-symbol-anchors-not-line-numbers`) of:

- `.page-hero`, `.page-hero .container`, `.page-hero h1`, `.page-hero p`
- `.landing-cta`, `.landing-cta h2`, `.landing-cta p`
- `.landing-section`, `.landing-section-inner`, `.section-title`, `.section-desc`
- `.honeypot-trap`

Total inline block grew from ~2.0 KB gzipped to ~2.5 KB gzipped — well under the ~14 KB TCP slow-start window.

### Layer 2 — static selector-coverage gate (closes "future hero variant" silent-pass)

New script: `plugins/soleur/docs/scripts/check-critical-css-coverage.mjs`. Enumerates every `class="..."` token in `pages/**.njk` and `_includes/*.njk` whose name matches an above-fold prefix (`page-hero`, `landing-hero`, `landing-cta`, `landing-section`, `section-title`, `section-desc`, `honeypot-trap`, `site-header`, `header-mark`, `header-name`, `nav-links`, `nav-cta`, `nav-cta-slot`, `nav-toggle`, `skip-link`, `newsletter-form`, `hero-waitlist-form`, `blog-post-meta`). For each candidate, asserts a CSS rule for `\.<class>` is present in the inline `<style>` block of `_site/pricing/index.html` (any built page works — the inline block is identical across pages). Strips `/* ... */` comments before matching to prevent false-positives where a comment names a selector the rule doesn't define.

Also enforces a gzipped size budget (warn at 9 KB, fail at 11 KB) on the inline block. At 11 KB the HTML response risks crossing the slow-start window, undoing PR #2904's LCP gain — at which point the fix is to switch to a build-time critical-CSS extractor (issue #2965 tracks this re-evaluation).

### Layer 3 — Playwright FOUC screenshot gate

New script: `plugins/soleur/docs/scripts/screenshot-gate.mjs`. Boots a Chromium instance, then for each route in `screenshot-gate-routes.json` (20 routes covering the entire anonymous-marketing surface):

1. Opens a fresh `BrowserContext` (4-context Promise.all worker pool, dropping wall-time from ~25 s sequential to ~0.7 s for 20 routes).
2. Blocks `**/*.css` at the network layer via `page.route()`. This pins the page in its inline-CSS-only state for the entire test, regardless of which `<link>` URLs a future template introduces. Deterministic: no `waitUntil` timing dependency.
3. Navigates with `waitUntil: 'domcontentloaded'`.
4. Asserts five invariants:
   - `.honeypot-trap` wrapper has `height === 0` and `left < -100` (off-screen). Check the WRAPPER not the descendant `<input>` — `getBoundingClientRect()` does NOT shrink when an ancestor has `overflow:hidden`, so checking the input gives a false-positive.
   - First `<main> <h1>` has `top >= 56` (below the 56 px fixed `.site-header`).
   - First `<main> <h1>` has `font-size >= 40 px` (catches user-agent-default ~36 px H1 vs `var(--text-4xl) === 48 px`).
   - `body` font-family includes `inter` (universal FOUC tripwire — a missing `body { font-family: var(--font-body) }` rule fails this on every page).
   - `.landing-cta h2` font-family includes `cormorant`/`garamond` on routes where `.landing-cta` is present (catches a regression where `.landing-cta h2` display-font override is dropped while `.page-hero h1` still passes — they fall back to inherited `var(--font-body)` independently).

Failures upload screenshots as workflow artifacts (`actions/upload-artifact@v4.6.2`). Supports `--json` output (`{ status, totalRoutes, failures: [{ route, errs[], screenshot? }] }`) for skill-wrapper / agent consumption.

### Layer 4 — wire both gates into BOTH workflows

Static gate + Playwright gate run in:

- `.github/workflows/deploy-docs.yml` post-build, before GitHub Pages publish (catches in production deploy).
- `.github/workflows/ci.yml` as a new `critical-css-gate` job on every PR (catches before merge — addresses the architecture review's "post-merge gate forces revert" concern).

Both workflows use the same `npm install --no-save playwright@1 http-server@14` plus `npx playwright install --with-deps chromium`, with Playwright cache hydration on cache hit. Pre-flight `curl -sf` polls server readiness with explicit `exit 2` on timeout (prevents silent run-against-dead-server).

### Layer 5 — workflow gate

New AGENTS.md rule `cq-eleventy-critical-css-screenshot-gate` (558 bytes) points at the two gate scripts as the load-bearing safeguards and notes that template/SEO/CSP gates do NOT detect the async-stylesheet-swap FOUC window. The rule is documentation pointing at gates — the gates are load-bearing, not the prose.

## Key insight

The prior PR #2904 learning correctly diagnosed the class but the only safeguard added was prose. **Per `wg-when-a-workflow-gap-causes-a-mistake-fix`, "a learning is not a fix"** — and this PR is the empirical confirmation: the same class re-shipped within 8 hours through the prose. The mechanical hierarchy that survives is:

1. Static check (cheapest, fails fastest, catches missing-rule before ever opening a browser).
2. Behavioral check (Playwright with stylesheet blocked — pins the worst-case state deterministically).
3. Documentation pointer (AGENTS.md rule — references the gates, not a substitute for them).

The static + Playwright pair forms a closed loop:

- A new above-fold class added to a template AND missing from the inline block → static check fails on PR.
- A present-but-broken inline rule (e.g., someone deletes the `height:0` from `.honeypot-trap`) → Playwright gate fails on PR.

Without one of those layers, the loop is open. The first iteration of this learning had neither.

## Prevention strategies

- **Hand-extracted critical CSS is acceptable IFF paired with a static selector-coverage check.** The check must enumerate above-fold selectors from templates (not from the inline block) so additions to templates are detected. If the toolchain supports a build-time extractor (`beasties`, `critical`, `penthouse`), that's strictly better — deferred under issue #2965 with concrete re-evaluation triggers (9 KB gzipped or 3rd FOUC).
- **Behavioral gates that simulate FOUC must block external stylesheets at the network layer**, not rely on `waitUntil` timing tricks. `waitUntil: 'load'` waits for the swapped stylesheet and silently passes the very state it's supposed to catch. `waitUntil: 'domcontentloaded'` plus `page.route(stylesheet, abort)` is deterministic.
- **Check the element bearing the CSS rule, not a descendant.** `.honeypot-trap { overflow:hidden; height:0 }` collapses the wrapper — but `getBoundingClientRect()` on a descendant `<input>` returns the input's natural box because clipping doesn't shrink children. False-positive RED on the gate. Always check the element with the rule.
- **When grep-checking CSS rules in a file, strip `/* ... */` comments first.** Documentation comments naming a selector make a missing rule look present. Same class as `cq-code-comments-symbol-anchors-not-line-numbers` but for the rule-presence direction.
- **The Playwright-first prevention rule extends to non-browser CI gates too.** Treat any "did the user see X" claim as needing a real-browser assertion — render-state in the inline-only state is a real user state during cold loads.

## Session Errors

- **Initial gate honeypot assertion targeted the descendant `<input>`, not the `.honeypot-trap` wrapper.** `getBoundingClientRect()` doesn't shrink children when an ancestor has `overflow:hidden`; the input retains its natural box. Recovery: switched to checking the wrapper. **Prevention:** when verifying a hidden-via-CSS element, the assertion target must be the element bearing the `display:none` / `height:0` / `position:absolute left:-9999px` rule, not a descendant whose box is independent. Add to screenshot-gate review checklist.
- **Static selector-coverage regex matched `.honeypot-trap` inside a CSS comment**, falsely passing after the rule was stripped. Recovery: strip `/* ... */` before matching. **Prevention:** any "is this rule defined?" check must strip comments before the regex pass; otherwise documentation comments produce false GREENs. Add to gate-construction lessons.
- **First AGENTS.md rule draft was 753 bytes (cap ~600 per `cq-agents-md-why-single-line`).** Trimmed twice. **Prevention:** before committing a new AGENTS.md rule, run `awk '/<rule-id>/ {print length}' AGENTS.md` and verify under 600. The work skill / compound could include this as a phase-end check.
- **PreToolUse Edit hook blocked the `.github/workflows/deploy-docs.yml` edit on first attempt** (security_reminder_hook flagged on workflow-file edits). Recovery: retry with the `env:` block placed before the `run:` block succeeded. **Prevention:** when editing `.github/workflows/*.yml`, structure env-var-bound steps with `env:` declared ahead of `run:` to satisfy the hook's pattern detection. Document in workflow-edit conventions.
- **PreToolUse Write hook false-positive on `RegExp.prototype` method invocation** — flagged as if it were a `child_process` shell call. Recovery: retry succeeded. **Prevention:** the hook is keyword-regex; one retry usually clears it. If not, flag to maintainer for hook tuning.
- **Background `http-server` survived between Bash calls → EADDRINUSE on next start.** Recovery: `lsof -i :8888` to find PID, `kill <PID>`. **Prevention:** kill the previous server explicitly by PID before starting a new one in CI-helper scripts; or use a `trap` cleanup. The background-task lifecycle in the Bash tool needs explicit teardown.
- **`/tmp/capture-after.mjs` failed ESM resolution because Node resolves `import "playwright"` from the script's directory** (no `node_modules` in `/tmp`). Recovery: copied the script to the worktree where `node_modules/` exists. **Prevention:** scripts that import workspace deps must live alongside a resolvable `node_modules/` chain — keep test/capture scripts inside the repo, not in `/tmp/`.
- **3 of 4 attempted scope-out filings DISSENTed by code-simplicity-reviewer.** "PR-event gating" claimed architectural-pivot but was a one-file workflow change; "worker-pool" claimed contested-design but option (d) was a no-op (not a tradeoff); "skill wrapper + JSON output" was additive packaging. Recovery: implemented all three inline (ci.yml job, 4-worker Promise.all pool, `--json` flag). **Prevention:** before drafting a scope-out, mentally simulate the simplicity-reviewer litmus — "if my fix is a one-file change OR additive packaging OR includes 'do nothing' as a viable option, the criterion doesn't apply." Add to review-skill scope-out guidance.

## Cross-references

- **PR #2904** — introduced the async-swap pattern. First iteration of this regression class.
- **PR #2960** — this fix.
- **Issue #2965** — scope-out: evaluate build-time critical-CSS extractor. Re-evaluation triggers: 9 KB gzipped inline OR 3rd FOUC OR `ABOVE_FOLD_PREFIXES` count > 30.
- `knowledge-base/project/learnings/best-practices/2026-04-27-hand-extracted-critical-css-misses-globally-rendered-selectors.md` — prior learning that named the class but lacked a mechanical gate. This learning supersedes its prevention guidance.
- `AGENTS.md` rule `cq-eleventy-critical-css-screenshot-gate` — references the gates that close the loop.
- `wg-when-a-workflow-gap-causes-a-mistake-fix` — the workflow rule that this PR finally satisfies for the critical-CSS class.
