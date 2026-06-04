# Learning: removing a brand-accent focus highlight — keep the neutral replacement above WCAG ~3:1

## Problem

The follow-up chat composer (and its dashboard landing-prompt twin) showed a
"double gold" focus treatment: an inner gold ring on the `<textarea>` from the
global `@layer base` `:where(...):focus-visible` box-shadow
(`globals.css:164-169`, `--soleur-accent-gold-fill` `#c9a962`) plus a gold outer
container border from `focus-within:border-soleur-border-emphasized` (`#c9a962`).
The operator reported it as visually noisy / "looks bad."

## Solution

Composer-scoped, no global-CSS change (the global `:focus-visible` rule is the
app-wide a11y indicator at 20+ sites):

1. Container border: `focus-within:border-soleur-border-emphasized` →
   `focus-within:border-soleur-text-secondary` on both surfaces
   (`chat-input.tsx:606`, `dashboard/page.tsx:509`).
2. Inner ring: add `focus-visible:shadow-none` to the textarea/input
   (`chat-input.tsx:646`, `dashboard/page.tsx:539`). The global rule uses
   `:where()` (zero specificity), so a class utility wins the cascade by
   specificity alone — no `globals.css` edit needed.

## Key Insight

When you *subtract* a brand-accent focus affordance, the neutral token you
replace it with still has to read as a focus state — i.e. clear the **~3:1
WCAG 2.4.11 focus-visibility threshold** against BOTH the resting border and the
surface. The first pass used `border-soleur-text-muted` (`#6a6a6a`), which is
only ~2.6:1 against the resting `#2a2a2a` border — a multi-agent a11y review
flagged it as a focus-visibility downgrade. `border-soleur-text-secondary`
(`#848484`) is ~3.8:1 vs the resting border and ~4.9:1 vs the surface — visible,
still fully neutral grey, no gold reintroduced. Don't reach for the dimmest
neutral token just because it's "subtle"; pick the dimmest neutral that still
clears 3:1.

Corollary: the a11y reviewer's first instinct ("restore a ring with
`ring-soleur-border-emphasized`") re-introduced the exact gold the operator
asked to remove. A review fix must honor the original request — solve the
contrast gap with a brighter *neutral*, not by reverting to the accent.

## Session Errors

- **Planning subagent: `Task`/`AskUserQuestion` unavailable** — Recovery: ran
  plan-review + deepen-plan gates inline. Prevention: none needed; environmental
  (one-off per execution environment).
- **Overlap-check `gh issue list | grep` over JSON returned 160KB** — Recovery:
  re-ran with a `python3` title filter. Prevention: filter `gh ... --json` to
  the minimum field set and post-process titles, don't grep the full body blob.
- **a11y-fix test `Edit` failed once ("string not found")** — Recovery: the
  assertion line still carried the pre-fix token; re-issued the Edit against the
  actual current string. Prevention: when changing a token a test asserts on,
  update the source AND the test assertion in the same pass.

## Tags
category: ui-bugs
module: web-platform/chat
