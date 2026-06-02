---
date: 2026-06-02
category: best-practices
tags: [e2e, playwright, visual-regression, false-green, plan-review, mock]
relates:
  - knowledge-base/project/learnings/2026-06-02-ui-structural-diffs-need-prepush-browser-gate.md
  - knowledge-base/engineering/architecture/decisions/ADR-049-headless-visual-regression-gate.md
issue: 4834
pr: 4833
---

# A visual-regression gate must assert rendered CONTENT, not a wrapper box — components that return `null` until an app-API-route resolves will false-GREEN

## Context

Planning the nav visual-regression gate (#4834), 3-agent plan-review (spec-flow + Kieran +
simplicity) caught three **false-GREEN** holes in a plan that read as correct. The gate would have
"passed" while validating nothing — the exact failure class the gate exists to prevent.

## The trap

The gate asserts a collapsed nav band is "icon-only / no overflow" and "identity visible." The
plan used `scrollWidth <= clientWidth` and `band.toBeVisible()`. But:

1. **The band's children return `null` until their app API routes resolve.** `LiveRepoBadge` is
   `null` until `GET /api/workspace/active-repo` resolves; `OrgSwitcherContainer` is `null` until
   `GET /api/workspace/list-memberships`. These are **Next.js app routes, not Supabase REST**, so
   the e2e harness's Supabase mock does NOT cover them. Unmocked → both render `null` → the band is
   **empty**.
2. An empty band satisfies **every proxy assertion**: `scrollWidth <= clientWidth` (no content to
   overflow), `toBeVisible()` (a 1px wrapper passes), `boundingBox` checks. The gate goes GREEN on a
   band that renders no identity at all — and the whole bug class was "identity ambiguous on
   collapse."
3. Separately, the Bug-1 fix had to be a **render-conditional** (`{drill === null && …}`), not a
   `md:hidden` CSS class — the companion jsdom assertion (`queryByText` absent) can only pass if the
   element leaves the DOM, since jsdom renders no CSS.

## The rule

For any real-browser gate over component-rendered content:

1. **Mock the app API routes the rendered content depends on**, not just the auth/DB layer. Trace
   each asserted component to its data source (`grep` for the early `return null`); a component that
   short-circuits to `null` on a pending/failed fetch makes every box-geometry assertion vacuous.
2. **Assert the invariant, never a proxy.** `scrollWidth`/`boundingBox`/`toBeVisible()` are
   necessary but never sufficient — also assert the *content* testids are present (expanded) or the
   *labels are hidden AND an icon is visible* (collapsed). A proxy that an empty/zero-box element
   satisfies is not a gate.
3. **DOM-removal vs CSS-hide:** if a jsdom test is the cheap half of the gate, the fix must remove
   the element from the DOM (render-conditional), because jsdom ignores `display:none`/`md:hidden`.
4. **A gate that gates nothing is worse than no gate** — it reports safety it doesn't provide.
   Prove it RED on the live bug first; a green-from-birth assertion is unvalidated.

## How it was caught

Multi-agent plan-review at `single-user incident` threshold: Kieran traced the `return null` data
dependency to the app routes; spec-flow flagged the proxy-vs-invariant gap and that the `/work`
wiring named a predicate with no qa step to gate. None were visible to the plan author (the
assumption WAS the bug). Reinforces: at brand-survival threshold, run the review panel and verify
gate assertions read the invariant, not a co-varying proxy.
