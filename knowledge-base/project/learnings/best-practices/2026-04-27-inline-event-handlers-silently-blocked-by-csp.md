---
module: docs-site
date: 2026-04-27
problem_type: integration_issue
component: csp_inline_event_handler
symptoms:
  - "Production docs site rendered the entire below-the-fold area in default browser styles for ~9 hours"
  - "<link rel=preload onload=this.rel=stylesheet> async-swap pattern silently failed in browsers with JS enabled"
  - "validate-csp.sh PASSED on every commit while the bug was live; eleventy build PASSED; SEO validator PASSED"
  - "Compound failure: PR #2904 introduced the bug, PR #2960 fixed only the above-the-fold symptom (inline-CSS coverage), PR #2966 fixed the actual root cause (CSP-blocked swap), PR #2967 closed the workflow gap"
root_cause: csp_script_src_blocks_inline_event_handlers_without_unsafe_inline_or_unsafe_hashes
severity: critical
tags:
  - csp
  - inline-event-handler
  - silent-failure
  - workflow-gate
  - validate-csp
  - eleventy
synced_to: []
---

# Inline event-handler attributes are silently blocked by CSP — and no static gate caught it

## Problem

PR #2904 introduced an async-stylesheet-swap pattern in `_includes/base.njk`:

```html
<link rel="preload" href="css/style.css" as="style" onload="this.onload=null;this.rel='stylesheet'">
<noscript><link rel="stylesheet" href="css/style.css"></noscript>
```

The docs site CSP allows only:

```
script-src 'self' https://plausible.io 'sha256-<plausible>' 'sha256-<signup-handler>'
```

No `'unsafe-inline'`, no `'unsafe-hashes'`. The HTML5 spec treats `onload=` (and every `on*=` attribute) as an inline event handler that requires either `'unsafe-inline'` or `'unsafe-hashes'` + a matching SHA-256 hash. Neither was present, so every browser with JavaScript enabled silently refused to execute the handler. The `<link rel="preload">` fetched `css/style.css` correctly, but the `rel='stylesheet'` swap never fired. Below-the-fold elements stayed in default browser styles indefinitely.

The bug shipped to production at PR #2904 merge and stayed live for ~9 hours through PR #2960 (which "fixed" FOUC by inlining more above-the-fold CSS but left the swap broken) until PR #2966 replaced the inline `onload=` with a hashed `<script>` block.

## Why the existing gates didn't catch it

| Gate | Why it missed |
|---|---|
| `eleventy build` | Pure templating — no semantic awareness of CSP behavior. |
| `validate-csp.sh` (pre-PR #2967) | Only checked `<script>` block hashes. Did not scan for inline event-handler attributes. CSP enforcement against attributes is a different surface. |
| `validate-seo.sh` | Markup correctness, not runtime behavior. |
| `screenshot-gate.mjs` (added PR #2960) | Intentionally blocks `**/*.css` to test inline-only state. By design cannot detect "swap doesn't fire." |
| `check-critical-css-coverage.mjs` (added PR #2960) | Static selector enumeration. Does not exercise the swap mechanism. |
| Multi-agent code review (PR #2960) | None of 8 reviewers traced the real-browser-with-CSP load path. security-sentinel reviewed CSP for the workflow YAML, not for inline handlers in the rendered HTML. |
| Local Playwright check (PR #2960 author) | Used `waitUntil: 'networkidle'` which masks the bug — `networkidle` does not care whether the swap script ran, only whether the browser finished loading the preload. |
| Production curl probe (PR #2960 author) | Verified the inline `<style>` block contained the new selectors. Did not verify post-load DOM state. |

The compound failure mode: every layer was looking at one specific facet (markup, hashes, FOUC, networking) and none was checking the *post-load DOM state in the actual CSP-enforced runtime*.

## Root cause

CSP `script-src` controls four execution surfaces:

1. `<script>` blocks (with `src=` or inline body)
2. Inline event handlers (`on*=` attributes)
3. `javascript:` URIs (in `href=`, `src=`, `action=`)
4. `eval`-class APIs (`eval`, `Function`, `setTimeout("string", ...)`)

`'unsafe-inline'` allows (1) and (2). `'unsafe-hashes'` plus a matching SHA-256 hash allows (2) for the specific handler content. Neither was present, so (2) was blocked.

Browsers do not produce a console error visible to static gates. They emit a CSP violation event (visible to a Playwright `console` listener observing `error`-level messages, or a CSP `report-uri` endpoint), but neither surface was being read. The user-visible symptom was "below-the-fold renders unstyled forever," reported by a human ~9 hours later.

## Solution

### Layer 1 — fix the immediate bug (PR #2966)

Replace the inline `onload=` attribute with a separate inline `<script>` block whose SHA-256 is allowlisted in CSP `script-src`:

```html
<link id="soleur-css-preload" rel="preload" href="css/style.css" as="style">
<noscript><link rel="stylesheet" href="css/style.css"></noscript>
<script>(function(){var l=document.getElementById('soleur-css-preload');if(!l)return;function sw(){l.rel='stylesheet';}if(l.sheet){sw();}else{l.addEventListener('load',sw);}})();</script>
```

CSP gains `'sha256-9o2LMPU0pCC0i/83pWDPlO90JiCMiJbUjQWPhLF+W0Y='`.

### Layer 2 — runtime regression gate (PR #2966)

`plugins/soleur/docs/scripts/check-stylesheet-swap.mjs` — navigates without blocking CSS, waits for `'load'`, asserts (a) preload link's `rel` swapped to `stylesheet`, (b) a below-the-fold style applied (`.site-footer` padding-top from `var(--space-8)`), (c) zero CSP violations in the console log. Wired into both `deploy-docs.yml` (post-merge) and `ci.yml` (pre-merge).

### Layer 3 — static gate that would have caught PR #2904 (PR #2967, this learning)

Extended `plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh` to detect inline event-handler attributes when CSP `script-src` lacks `'unsafe-inline'` and `'unsafe-hashes'`. The detection uses Python's `html.parser` (avoids regex false-positives in `<script>` content and HTML comments). Each `<tag on*="...">` becomes a `FAIL: page: inline event-handler attribute 'line:tag:attr=value' is silently blocked by script-src...` line.

Verified by reintroducing the PR #2904 pattern in a test build — produces 41 FAIL lines (one per built page) with file:line and the offending attribute. Restoring the fix returns to PASS.

`validate-csp.sh` also added to the pre-merge `ci.yml critical-css-gate` job (it was previously deploy-time only).

### Layer 4 — pre-merge defense in depth

`ci.yml critical-css-gate` now runs all six docs validators before merge:

1. `npx @11ty/eleventy` (build)
2. `validate-csp.sh` (hashes + NEW inline-handler check)
3. `validate-seo.sh` (markup)
4. `check-critical-css-coverage.mjs` (selectors inlined)
5. `screenshot-gate.mjs` (FOUC behavior)
6. `check-stylesheet-swap.mjs` (swap fires + no CSP violations)

A PR that introduces an inline handler now fails `validate-csp.sh` mechanically before the more expensive Playwright gates run.

## Key insight

**CSP-enforcement bugs are a class of silent failure that no markup-level static check can detect without modeling the runtime behavior of the policy.** Three durable principles:

1. **Static gates must scan all four script-execution surfaces, not just `<script>` blocks.** Event handlers, `javascript:` URIs, and `eval`-class APIs are equally constrained by `script-src`. Hash validation alone is incomplete.
2. **Runtime gates must include "no CSP violations in console" as a first-class assertion.** Any test that boots a real browser is a candidate. A page that loads with violations is a page that's silently degraded.
3. **`waitUntil` semantics in Playwright are subtle.** `networkidle` does NOT mean "scripts ran successfully" — it means "no network requests for 500ms." If a script is CSP-blocked, the network looks idle and the test passes. Use post-load DOM-state assertions, not network-state assertions.

## Prevention strategies

- **Any inline event handler attribute (`on*=`) in `plugins/soleur/docs/**` HTML/Nunjucks templates is rejected by `validate-csp.sh` if CSP `script-src` lacks `'unsafe-inline'` or `'unsafe-hashes'`.** This is a deterministic mechanical safeguard that runs in <1s on every PR. No agent vigilance required.
- **When introducing or modifying a CSP-enforced page, run a real-browser load probe that captures `console.error` messages for CSP violations.** `check-stylesheet-swap.mjs` is the existing example.
- **Treat `<link rel="preload">` swap mechanisms as security-policy-coupled.** The browser-default `onload=` attribute is the simplest pattern, but it requires CSP buy-in. A hashed `<script>` block is the CSP-compliant alternative for sites that don't allow `'unsafe-inline'`.
- **When `validate-csp.sh` is the gate, remember it scans the BUILT HTML (`_site/`), not the source templates.** This is correct — Nunjucks expansion can introduce attributes the source template doesn't show. Always run after `npx @11ty/eleventy`.

## Session Errors

- **PR #2960 author (me) verified the fix locally with `waitUntil: 'networkidle'` Playwright loads, which silently masked the CSP-blocked swap.** Recovery: in PR #2966, the new `check-stylesheet-swap.mjs` uses `waitUntil: 'load'` AND asserts on post-load DOM state (`link.rel === 'stylesheet'`). **Prevention:** when verifying script-side-effects in Playwright, never use `networkidle` alone — it doesn't care whether scripts executed. Assert on the script's observable side effect.
- **Multi-agent review on PR #2960 didn't trace the CSP-vs-inline-handler interaction across the 8 spawned reviewers.** security-sentinel reviewed CSP for the new workflow YAML, not for inline handlers in the rendered HTML. **Prevention:** when prompting a security agent for a CSP review, explicitly enumerate ALL four script-execution surfaces (script blocks, on* attributes, javascript: URIs, eval) and ask whether the policy covers each. The reviewer prompt template should include this checklist.
- **Production curl-probe in PR #2960's session checked inline `<style>` content but not post-load DOM state.** Recovery: PR #2966 added the runtime gate. **Prevention:** any "is the fix live?" check must include a real-browser-load assertion, not just markup-content grep.

## Cross-references

- **PR #2904** — introduced the bug. Async stylesheet swap with inline `onload=`.
- **PR #2960** — partial fix: inlined more critical CSS for above-the-fold. Swap still broken.
- **PR #2966** — root-cause fix: hashed inline `<script>` block. Added `check-stylesheet-swap.mjs` runtime gate.
- **PR #2967** — workflow gap fix: `validate-csp.sh` now scans for inline event-handler attributes. Added `validate-csp.sh` + `validate-seo.sh` to pre-merge `ci.yml`.
- `knowledge-base/project/learnings/best-practices/2026-04-27-critical-css-fouc-prevention-via-static-and-playwright-gates.md` — sibling learning covering the FOUC class. This learning extends the same compound failure with the CSP-blocked-swap class.
- `knowledge-base/project/learnings/best-practices/2026-04-27-hand-extracted-critical-css-misses-globally-rendered-selectors.md` — original PR #2904 learning. Names the FOUC class but did not address the swap-mechanism class.
