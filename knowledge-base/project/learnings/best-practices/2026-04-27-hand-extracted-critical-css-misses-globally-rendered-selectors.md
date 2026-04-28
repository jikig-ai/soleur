---
name: hand-extracted-critical-css-misses-globally-rendered-selectors
description: A hand-extracted critical-CSS inline block silently omits selectors for globally-rendered template fragments (e.g., a nav CTA driven by _data/site.json). Static markup checks pass; users see FOUC. The only fix that survives is enumerating every globally-rendered above-fold selector during extraction, not relying on a free-text regenerate comment.
type: best-practice
tags: [code-review, critical-css, eleventy, FOUC, drift, multi-agent-review]
category: best-practices
module: plugins/soleur/docs
---

# Hand-Extracted Critical CSS Misses Globally-Rendered Selectors

## Problem

PR #2904 (`fix-2831-lcp-clean`) inlined an above-the-fold critical CSS block
into `plugins/soleur/docs/_includes/base.njk` and switched the linked
stylesheet to a `preload`+`onload`-swap async pattern. The PR author hand-
extracted the critical subset from `css/style.css` (1759 lines) into a 60-
line `<style>` block and protected it with a free-text comment:

> "Regenerate this block if style.css tokens, header, or hero sections change."

The pre-merge mechanical gates all passed:

- `npx @11ty/eleventy` → 78 files written, 0 errors
- `grep onload _site/index.html` → swap markup present
- Inline `<style>` block contains every selector the author thought was needed

Yet the inline block omitted `.nav-cta-slot`, `.nav-cta`, and `.btn--sm`.
Why this matters: `_data/site.json` sets `primaryCta` globally, so every
page renders this fragment in its nav:

```html
<li class="nav-cta-slot">
  <a class="btn btn-primary btn--sm nav-cta">Sign up</a>
</li>
```

Without those rules in the inline block, the nav CTA flashes unstyled
(oversized button, wrong color) until the async stylesheet swaps in. The
exact bug the inline block was supposed to prevent — a Flash Of Unstyled
Content — was preserved on the most prominent above-fold element on every
page in the site.

## Why Mechanical Checks Missed It

- `tsc`, lint, build → no concept of "is this CSS sufficient for the page".
- `grep "<style>" _site/*.html` → present, passes.
- Author's manual visual check on `/` and `/blog/...` → the FOUC happens in
  the first ~400ms before stylesheet swap; easy to miss on a fast local
  network and a primed font cache.
- Test plan checkbox "no FOUC" → unchecked at PR time, deferred to "manual
  visual check post-merge".

The bug is structural: it's about which selectors the page renders at first
paint, which is information distributed across `_data/site.json`,
`base.njk`, and `css/style.css`. No single file shows the gap.

## Solution

Multi-agent review caught it. The pattern-recognition specialist agent was
given the diff and asked "what's missing for above-fold first paint?" and
listed every selector consumed by the rendered nav. Cross-referencing
against the inline block surfaced the gap immediately.

Inline fix (commit `f96276db` on `fix-2831-lcp-clean`):

```css
.nav-links .nav-cta-slot { margin-left: auto; }
.nav-links .nav-cta-slot .nav-cta { color: var(--color-text-inverse); }
.nav-links .nav-cta-slot .nav-cta:hover { color: var(--color-text-inverse); border-bottom-color: transparent; }
.nav-links .nav-cta-slot .nav-cta:focus-visible { outline: 2px solid var(--color-text-inverse); outline-offset: 3px; }
.btn.btn--sm { padding: var(--space-2) var(--space-4); font-size: 0.875rem; }
@media(max-width:768px){
  .nav-links .nav-cta-slot { margin-left: 0; margin-top: var(--space-2); }
  .nav-links .nav-cta-slot .nav-cta { display: inline-block; text-align: center; }
}
```

Plus a tightened regenerate-comment with a grep-stable selector list (per
rule `cq-code-comments-symbol-anchors-not-line-numbers`) so a future editor
of `.nav-cta-slot` in `style.css` will hit the inline block via grep.

## Key Insight

Any time you hand-extract a "critical subset" from a larger source (CSS,
schema, GraphQL fragment, type definition, config), the extraction is
silently incomplete if you do not enumerate the consumer's input set.

The consumer here was `base.njk`'s `<nav>` block, which renders fragments
driven by `_data/site.json` — a data file separate from both the source
CSS and the inline block. The author saw `style.css` and the page they
were optimizing, but not the data file that wires them together.

**Generalizable rule:** Before hand-extracting a critical subset, list
every consumer the page renders at first paint by reading the template
top-to-bottom, then the data files driving each `{% if %}` and
`{{ ... }}` interpolation. Extract the subset to satisfy the union, not
the visible-on-first-load subset of the union.

The free-text comment ("regenerate when X changes") is the weakest
possible enforcement — it depends on a future editor noticing the comment
and reasoning correctly. Stronger options, in order:

1. **Build-time extractor** (Eleventy `addTransform` reading source CSS
   and emitting the inline block). Eliminates drift entirely. Cost:
   ~50 LOC + dev-loop integration.
2. **CI parity test** (a test that re-extracts on every build and diffs
   against the committed inline block). Catches drift at PR time. Cost:
   one test file.
3. **Grep-stable comment with explicit selector enumeration** (this PR's
   approach — a comment listing every selector mirrored). Catches an
   editor mid-edit if they grep for the selector they're changing.
4. **Free-text comment** (the original approach). Decorative.

The rule of thumb: when the cost of (1) is small and the consequence of
drift is user-visible (FOUC, broken layout, wrong colors), pay for (1).
This PR shipped (3) because the docs site is small and weekly-cadence;
(1) is a candidate follow-up if the inline block grows or drifts.

## Related Learnings

- `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — parent
  pattern: tests/tsc pass, structural review catches.
- `2026-04-24-multi-agent-review-catches-feature-wiring-bugs.md` — same
  shape (the bug lives in a downstream consumer the author didn't model).
- `2026-04-22-binary-lcp-gate-vs-measurement-variance.md` — the issue
  acceptance criterion this PR addresses; reminds reviewers that "build
  passes" ≠ "performance budget met".

## Session Errors

- **Wrong CWD for Eleventy build verification.** Ran `npx @11ty/eleventy`
  from `plugins/soleur/docs/` and got `filter not found: dateToShort`.
  Recovery: ran from repo root (the `package.json` script in
  `plugins/soleur/docs/` does `cd ../../../ && npx @11ty/eleventy`).
  **Prevention:** existing project convention via the `docs:build` npm
  script; no rule needed — discoverable via clear error.

## References

- PR: #2904 (`fix-2831-lcp-clean`)
- Issue: #2831 (Eleventy LCP optimization)
- Replaces abandoned attempts: #2857, #2859 (both bundled the fix with
  destructive scope and were closed).
- Touched file: `plugins/soleur/docs/_includes/base.njk:126-186`
- Source CSS: `plugins/soleur/docs/css/style.css:771-781` (the missed
  rules)
- Globally-rendered consumer: `plugins/soleur/docs/_data/site.json:26`
  (`primaryCta`) → `base.njk:206-208`
