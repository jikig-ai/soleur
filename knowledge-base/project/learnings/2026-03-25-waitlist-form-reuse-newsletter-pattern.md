# Learning: Reuse existing form patterns instead of duplicating CSS/JS

## Problem

When adding a waitlist signup form to the pricing page, the initial implementation duplicated the entire newsletter form CSS (~65 lines) and JS handler (~30 lines) with only 1 CSS property different (border-top) and different string values in the JS.

## Solution

1. **CSS:** Reuse `.newsletter-section`, `.newsletter-form`, `.newsletter-status`, `.newsletter-success`, `.newsletter-error` classes. Add a single BEM modifier `.newsletter-section--waitlist` for the accent border-top override.
2. **JS:** Extract a shared `handleSignupForm(form, opts)` function that accepts a config object with `successMessage`, `event`, and `props` callback. Both newsletter and waitlist forms call it with different configs.
3. **HTML:** The waitlist template uses dual classes (`class="newsletter-form waitlist-form"`) so the newsletter CSS applies while the JS can still select waitlist-specific forms via `.waitlist-form`.

Result: ~75 lines removed (55% of the initial waitlist code), single point of maintenance for form submission logic.

## Key Insight

When adapting an existing UI pattern (newsletter form -> waitlist form), start by reusing the original classes with a modifier, not by copying the CSS/JS. The review caught this after initial implementation — ideally the plan should flag "reuse classes" as the default approach for pattern adaptations. The only reason to duplicate is when the visual or behavioral divergence is significant enough that shared classes would require more overrides than a fresh set.

## Session Errors

1. **Wrong Eleventy config path** — Used `--config=plugins/soleur/docs/.eleventy.js` (doesn't exist). The config is `eleventy.config.js` at repo root. **Recovery:** Globbed for the config file. **Prevention:** The Eleventy config path is already in `package.json` scripts (`"docs:build": "npx @11ty/eleventy"`). Use `npm run docs:build` instead of calling eleventy directly with a guessed config path.

2. **Markdown lint failure on session-state.md** — Missing blank lines around headings and lists in the session-state file written by the orchestrator. **Recovery:** Rewrote file with proper formatting. **Prevention:** Session-state.md is written by the main orchestrator, not a skill — ensure blank lines around all markdown headings and lists when writing structured markdown.

## Tags

category: ui-bugs
module: docs-site
