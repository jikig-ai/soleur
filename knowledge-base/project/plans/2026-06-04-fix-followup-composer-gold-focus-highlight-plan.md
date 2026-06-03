---
title: "fix: remove double gold focus highlight on follow-up chat composer"
type: fix
date: 2026-06-04
branch: feat-one-shot-fix-followup-input-gold-focus-highlight
lane: cross-domain
status: planned
---

# 🐛 fix: Remove the double gold focus highlight on the follow-up chat composer

## Overview

When the user clicks/focuses the follow-up question textarea in the chat/concierge
surface (placeholder `"Follow up or ask another question... Type @ to switch leader"`),
the composer renders **two** overlapping gold/amber focus treatments:

1. An **inner gold ring** hugging the textarea, and
2. An **outer gold border** around the whole composer container.

This double-gold look is visually noisy and inconsistent with the rest of the dark
theme. The fix replaces both with a single, subtle dark-theme-appropriate focus
treatment on the composer container only, while preserving the app-wide accessible
focus indicator everywhere else.

### Root cause (both sources located and verified)

| # | Symptom | Source | Mechanism |
|---|---------|--------|-----------|
| 1 | Inner gold ring around the textarea | `apps/web-platform/app/globals.css:164-169` | A global `@layer base` rule applies a 2-layer `box-shadow` (`0 0 0 2px var(--soleur-bg-base), 0 0 0 4px var(--soleur-accent-gold-fill)`) to **every** `:focus-visible` interactive element, including the composer's `<textarea>`. The textarea's Tailwind `focus:outline-none` only suppresses the `outline` — it does **not** cancel this global `box-shadow`. |
| 2 | Outer gold border around the container | `apps/web-platform/components/chat/chat-input.tsx:606` | The composer container className uses `focus-within:border-soleur-border-emphasized`. `--soleur-border-emphasized` = `#c9a962` (gold) in all themes (`globals.css:48,72,102`). On focus-within the whole 1px container border turns gold. |

Both sources independently render gold; together they produce the reported "double gold border."

### Why this is NOT a global-token change

The global `:focus-visible` gold box-shadow (`globals.css:164`) is the **load-bearing,
app-wide accessible focus indicator** (WCAG 2.4.7). It is the intended focus affordance
for buttons, links, and inputs across dozens of components. `--soleur-border-emphasized`
and `--soleur-accent-gold-fill` are likewise referenced broadly (auth pages, banners,
dashboard, attachment display, sub-agent groups — verified via `git grep`). **The fix
must be scoped to the composer only.** Removing the global rule or recoloring a shared
token would regress accessibility and theming app-wide. This is the single most important
design constraint of this plan.

## Research Reconciliation — Spec vs. Codebase

No spec file exists for this branch (direct plan entry, no brainstorm). The feature
description's premise was validated against the codebase before planning:

| Description claim | Codebase reality | Plan response |
|---|---|---|
| "gold focus ring around the inner input" | Confirmed — global `:focus-visible` box-shadow at `globals.css:164-169` uses `--soleur-accent-gold-fill` (`#c9a962`) | Scope an override that suppresses the gold box-shadow on the composer textarea |
| "outer gold border around the whole composer container" | Confirmed — `chat-input.tsx:606` `focus-within:border-soleur-border-emphasized` (`#c9a962`) | Replace the gold focus-within border with a subtle neutral treatment |
| "web-platform chat/concierge follow-up composer" | Confirmed — `ChatInput` rendered by `ChatSurface` at `chat-surface.tsx:805`; placeholder string at `chat-surface.tsx:820` | Edit `ChatInput` (`chat-input.tsx`) — the single shared composer component |
| "UI exists but is broken" | Confirmed broken-behavior, not never-built | Behavioral CSS fix, not a build |

**Premise Validation:** No external GitHub issues/PRs are cited by reference. All cited
artifacts (component, placeholder, theme tokens, test files) exist on the working tree.
The premise holds end-to-end; no stale references.

## User-Brand Impact

**If this lands broken, the user experiences:** a chat composer whose focus state is
either invisible (no focus affordance — accessibility regression) or still shows the
unattractive double-gold highlight; in the worst case a global accessibility regression
if the shared `:focus-visible` rule is touched.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — this is a
purely presentational CSS/className change with no data, auth, or network surface.

**Brand-survival threshold:** none

> The composer textarea must still expose a *visible, non-gold* focus indicator (keyboard
> a11y) — the fix subtracts the gold treatment but must not subtract focus visibility.

## The Fix (minimal, composer-scoped)

Two coordinated edits, both confined to the composer:

### Edit A — composer container border (`chat-input.tsx:606`)

Replace the gold `focus-within:border-soleur-border-emphasized` with a subtle dark-theme
focus treatment. Recommended: keep the container's default border and apply a low-contrast
neutral elevation on focus-within (the container already has `transition-shadow`), e.g. a
1px brightened-but-neutral border plus an optional faint inset/0-spread shadow — NOT gold.

Concrete candidate (to be finalized at /work after visual check):

```tsx
// apps/web-platform/components/chat/chat-input.tsx:604-608  (BEFORE)
<div
  className={
    "flex items-end gap-1.5 rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1 px-2 py-1.5 transition-shadow focus-within:border-soleur-border-emphasized" +
    (flashQuote ? " ring-2 ring-amber-400" : "")
  }
>

// AFTER (candidate — subtle neutral focus, no gold)
<div
  className={
    "flex items-end gap-1.5 rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1 px-2 py-1.5 transition-shadow focus-within:border-soleur-text-muted" +
    (flashQuote ? " ring-2 ring-amber-400" : "")
  }
>
```

> **Code-simplicity (review):** start with the **border-color shift alone**
> (`focus-within:border-soleur-text-muted`) — the simplest possible subtle affordance. Only
> add an extra `focus-within:shadow-[...]` layer if the AC8 screenshot shows the border-only
> shift is too weak to read as a focus state. Do not pre-add the shadow.

> NOTE: the **transient amber quote-flash** (`flashQuote ? " ring-2 ring-amber-400"`) is a
> SEPARATE, intentional feature (KB selection → quote insert). It is **not** the focus
> highlight and MUST be preserved verbatim. Tests in `chat-input-quote.test.tsx` assert it.

### Edit B — suppress the global gold box-shadow on the composer textarea

The textarea (`chat-input.tsx:636-647`) inherits the global `:focus-visible` gold
box-shadow. Suppress it **only for this textarea** so the inner gold ring disappears.
Two viable approaches — finalize one at /work:

**DHH (review): default to B1 — do not edit `globals.css` unless the cascade check fails.**
B1 keeps the entire fix in one component file with zero global-CSS risk surface.

- **B1 (preferred, Tailwind-only, no global CSS edit):** add a focus utility to the
  textarea className that overrides the inherited box-shadow, e.g.
  `focus-visible:shadow-none` (Tailwind emits `box-shadow: ...` which wins by specificity/
  cascade order over the `@layer base` rule). Verify cascade win at /work — `@layer base`
  rules are lower-priority than unlayered utilities in Tailwind v4, so a utility should win;
  if not, fall back to B2.
- **B2 (scoped global rule):** add a single scoped selector to `globals.css` `@layer base`
  immediately after the global rule (lines 164-169) that resets `box-shadow: none` for the
  composer textarea (target via a stable data attribute, e.g. `data-chat-composer-input`
  added to the textarea, NOT a brittle structural selector). This keeps the global a11y
  rule intact for every other element.

The textarea already has `focus:outline-none`; after Edit B it shows no gold ring. The
**container** (Edit A) carries the single subtle focus affordance for the whole composer,
which is the correct ChatGPT-style pattern already intended by the code comment at
`chat-input.tsx:598-603`.

## Files to Edit

- `apps/web-platform/components/chat/chat-input.tsx` — container focus-within className
  (line 606) + textarea focus className/data-attr (lines 636-647). Preserve existing
  textarea tokens `min-h-[36px]` / `max-h-[140px]` (asserted by `chat-input.test.tsx:136-137`)
  and the `flashQuote` amber quote-flash branch (asserted by `chat-input-quote.test.tsx`).
- `apps/web-platform/app/globals.css` — **only if** Edit B2 is chosen (scoped box-shadow
  reset). Do NOT modify the global `:focus-visible` rule itself (lines 164-169) or any
  `--soleur-*` token value. Skip this file entirely if B1 (Tailwind-only) works.
- `apps/web-platform/test/chat-input.test.tsx` — add a focus-styling assertion (see Test
  Strategy). New test code lives here because vitest jsdom only collects
  `test/**/*.test.tsx` (`vitest.config.ts:60`); a co-located component test would be
  silently skipped.

## Files to Create

- None. (If a separate focus test file is preferred over extending `chat-input.test.tsx`,
  it must live at `apps/web-platform/test/chat-input-focus.test.tsx` to match the vitest
  `test/**/*.test.tsx` jsdom include glob — never co-located under `components/`.)

## Open Code-Review Overlap

None — checked once `## Files to Edit` was finalized. (No open `code-review`-labeled issues
were cited; a `gh issue list --label code-review` sweep should be run at /work for the two
edited files as a backstop, per plan Phase 1.7.5.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — no gold on focus:** After the fix, focusing the composer textarea renders
  neither (a) the inner gold box-shadow ring nor (b) the gold outer container border. The
  composer className no longer contains `focus-within:border-soleur-border-emphasized`
  (grep: `grep -c 'focus-within:border-soleur-border-emphasized' apps/web-platform/components/chat/chat-input.tsx` returns `0`).
- [ ] **AC2 — subtle focus affordance preserved:** The composer container still has a
  *visible, non-gold* focus-within treatment (a `focus-within:` border/shadow utility is
  present on the container div; value resolves to a neutral token, not `border-emphasized`
  / `accent-gold-fill`).
- [ ] **AC3 — global a11y rule untouched:** `globals.css:164-169` (the `:where(... ):focus-visible`
  gold box-shadow) is byte-identical to pre-change (`git diff globals.css` shows no change
  to that block). No `--soleur-*` token value changed.
- [ ] **AC4 — quote-flash preserved:** The `flashQuote ? " ring-2 ring-amber-400"` branch is
  unchanged; `chat-input-quote.test.tsx` passes.
- [ ] **AC5 — textarea tokens preserved:** `chat-input.test.tsx` `min-h-[36px]` /
  `max-h-[140px]` assertions still pass.
- [ ] **AC6 — focus-styling test:** A new test in `apps/web-platform/test/chat-input*.test.tsx`
  asserts the composer container className does NOT contain `border-soleur-border-emphasized`
  and DOES contain a `focus-within:` neutral focus utility. (jsdom cannot compute the global
  `box-shadow` from the `@layer base` rule, so AC1(a) is verified visually + by absence of
  gold tokens in className, not by a computed-style assertion — see Sharp Edges.)
- [ ] **AC7 — typecheck + lint + suite green:** `vitest` (the package runner) passes for
  the edited test files; `tsc --noEmit` clean; no new lint errors.
- [ ] **AC8 — visual verification:** Screenshot the focused composer (Playwright MCP or
  `/soleur:qa`) in dark theme confirming a single subtle non-gold focus state. Per the
  toggle-state Sharp Edge, also confirm the focus state when the textarea is empty vs. has
  content (both render the same container) and that the Send button's intentional amber fill
  (`bg-amber-600`, `chat-input.tsx:682`) is unaffected.

### Post-merge (operator)

- None — pure code change against an already-provisioned surface; `web-platform-release.yml`
  redeploys on merge automatically.

## Test Strategy

- **Runner:** `vitest` (per `apps/web-platform/package.json:15` — NOT bun). jsdom project
  collects `test/**/*.test.tsx` (`vitest.config.ts:60`).
- **Unit/DOM (jsdom):** extend `apps/web-platform/test/chat-input.test.tsx` with a test
  rendering `<ChatInput>` and asserting on the composer container's className tokens
  (absence of `border-soleur-border-emphasized`; presence of the new neutral `focus-within:`
  utility). jsdom does NOT apply real CSS cascade for the `@layer base` box-shadow, so the
  inner-ring removal (AC1a) is verified by className/token absence + the AC8 screenshot, not
  by `getComputedStyle`.
- **Visual (AC8):** Playwright MCP screenshot of the focused composer in dark theme.

## Domain Review

**Domains relevant:** Product (UI surface)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none — N/A (no new UI surface; modifies an existing component's
focus styling only)
**Pencil available:** N/A (no UI surface — this is a focus-state CSS refinement of an
existing component, not a new page/flow/component requiring wireframes)

#### Findings

The mechanical UI-surface override fires (the plan edits `components/chat/chat-input.tsx`,
a UI-surface path). However, the change creates **no new user-facing page, flow, or
component** — it refines the focus styling of an existing composer. Per the plan skill's
three-tier rule, modifying an existing component's appearance without adding a new
interactive surface is **ADVISORY**, not BLOCKING. On the pipeline path, ADVISORY
auto-accepts. No wireframe is required because there is no new flow or layout to design;
the only visual delta is "gold focus → subtle neutral focus," validated by the AC8
screenshot. The design intent (single container-level focus affordance, ChatGPT-style) is
already documented in the component at `chat-input.tsx:598-603`.

## Observability

This is a presentational CSS/className change with no runtime logic, no new code path, no
network/data surface, and no failure modes to detect. Per the plan skill's Phase 2.9 skip
rule (pure-presentational edit, no new server/infra surface), an observability schema is
not applicable. The only "signal" is visual, covered by AC8.

## Risks & Mitigations

- **Risk: removing the gold ring removes ALL focus visibility (a11y regression).**
  Mitigation: Edit A keeps a visible neutral `focus-within:` border/shadow on the
  container; AC2 + AC8 enforce a visible non-gold affordance.
- **Risk: Edit B accidentally suppresses the global gold ring app-wide.** Mitigation: B1
  scopes via the textarea's own Tailwind class; B2 scopes via a stable data attribute on
  the composer textarea. AC3 asserts the global rule and tokens are byte-unchanged.
- **Risk: Tailwind utility does not win the cascade over the `@layer base` rule (B1).**
  Mitigation: verify cascade win at /work; fall back to B2 (scoped global reset) if the
  utility loses. In Tailwind v4, unlayered utilities outrank `@layer base`, so B1 should
  win — but this is a "verify the cascade" step, not an assumption.
- **Risk: touching the container className breaks the transient quote-flash.** Mitigation:
  the `flashQuote` branch is left verbatim; AC4 + `chat-input-quote.test.tsx` guard it.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is
  filled; threshold = none, with a non-empty reason for the sensitive-path carve-out N/A.)
- **jsdom cannot verify the inner-ring removal via computed style.** The global gold ring
  comes from an `@layer base` `box-shadow` that jsdom does not evaluate. Do NOT write a
  `getComputedStyle(textarea).boxShadow === ""` assertion — it will be vacuously true in
  jsdom regardless of the fix. Verify via className-token absence (AC6) + screenshot (AC8).
- **Verify focus in both content states** (empty vs. with text) — both render the same
  container, but confirm per the toggle-state alignment learning; the Send button's amber
  fill is a deliberate brand element and must remain.
- **New test file path must match the vitest jsdom include glob** (`test/**/*.test.tsx`).
  A co-located `components/**/*.test.tsx` is silently skipped (`vitest.config.ts:60`).
- **Do not recolor `--soleur-border-emphasized` or `--soleur-accent-gold-fill`** to fix
  this — both are shared across the app (auth, banners, dashboard, attachment display).
  The fix is composer-local only.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Edit the global `:focus-visible` rule to use a neutral color | Regresses the app-wide accessible focus indicator for every button/link/input; out of scope and harmful. |
| Recolor `--soleur-border-emphasized` token to neutral | Token is used broadly for emphasized borders elsewhere; would change unrelated UI. |
| Remove `focus-within` entirely with no replacement | Removes keyboard focus visibility on the composer — a11y regression (fails AC2). |
| Only fix the outer border (Edit A) and leave the inner ring | The inner gold ring (global box-shadow) is the more prominent half of the reported "double" — both must be addressed. |
