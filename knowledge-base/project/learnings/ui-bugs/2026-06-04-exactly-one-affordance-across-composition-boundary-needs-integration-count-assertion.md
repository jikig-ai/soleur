---
date: 2026-06-04
category: ui-bugs
module: apps/web-platform/components/dashboard, app/(dashboard)
tags: [composition-boundary, test-scope, nav, one-back-per-state, multi-agent-review]
pr: 4911
issue: 4915
---

# Learning: an "exactly one X per state" invariant that spans a composition boundary is invisible to component-scoped tests

## Problem

The KB nav redesign (#4915) had an explicit AC: **exactly one back affordance per
state**. Two back controls live in DIFFERENT components on different sides of a
composition boundary:

- the persistent `WorkspaceContextBand` "Back to menu" (mounted in
  `(dashboard)/layout.tsx`, ABOVE the KB route swap), and
- a new Phase-4 page-body header "Back to menu" inside
  `app/(dashboard)/dashboard/kb/layout.tsx`'s `fullWidth` branch.

The band suppresses its back only in the KB doc view (`suppressBack` keyed on
`pathname.startsWith("/dashboard/kb/")`). The page header rendered its back
**unconditionally**. On the mobile KB **landing** (`/dashboard/kb`, where
`inKbDocView` is false) BOTH backs rendered — two identical "Back to menu" links
to `/dashboard`. A real regression against the plan's own Phase 3 AC.

It shipped green through the full vitest suite because:

- `workspace-context-band.test.tsx` is **band-scoped** — it asserted "KB landing
  → the band shows the only back," a premise that is FALSE at the composition
  level (the test subtree literally cannot contain the sibling page header).
- `kb-layout.test.tsx` rendered `KbLayout` in isolation (no band) and asserted
  "the header has a back," also true in isolation.
- The e2e asserted the header back **existed** but never asserted a **count**.

Each test was internally consistent; none rendered BOTH components together, so
none could see the duplication. `user-impact-reviewer` caught it by tracing the
state-by-state back table across the full composition.

## Solution

Key the two complementary affordances on a **single shared predicate** so they
are mutually exclusive by construction:

1. Extract the predicate once: `isKbDocView(pathname)` in
   `hooks/segment-to-drill-level.ts` (path EXTRACTION, distinct from drill
   detection — the trailing-slash form the `nav-drill-authority.test.ts` guard
   explicitly excludes).
2. Band: `suppressBack = isKbDocView(pathname)` (suppress in doc view).
3. Page header: `showHeaderBack = isKbDocView(pathname)` (show ONLY in doc view).

Now exactly one renders in every state: landing → band back; doc view → page
header back (band suppressed); doc-with-content → `kb-content-header` back. No
state has zero or two.

Test fix: a **composition-level** assertion is required.
- e2e (`nav-states-shell.e2e.ts`): `page.getByRole("link", { name: /back to menu/i })`
  `.toHaveCount(1)` on the real mobile viewport (the rail band is `md:hidden`, so
  only the one visible back counts).
- unit: `within(header).queryByRole("link", { name: /back to menu/i })`
  `.toBeNull()` on the landing, present on the doc path.

## Key Insight

A "**exactly one X per state**" invariant is a property of the COMPOSITION, not
of any single component. A component-scoped render test (`render(<Band/>)`,
`render(<KbLayout/>)`) can only ever assert "X is present/absent in MY subtree" —
it is structurally blind to a sibling that lives in a parent/cousin component.

When two components on opposite sides of a composition boundary each own one
instance of the same affordance (back button, title, primary CTA, identity
chip), you need:

1. **A shared predicate** both consumers key on, so mutual exclusivity is
   enforced by construction rather than by two independently-maintained
   conditions drifting apart.
2. **A count assertion at the composition root** — render the FULL layout (or an
   e2e at the real viewport) and assert `toHaveCount(1)`, not a per-component
   `getByX` presence check. Presence-in-my-subtree is not one-in-the-document.

Watch for the false-premise test smell: a band-scoped test titled "…it is the
only back there." "Only" is a claim about the whole document; a subtree test
cannot back it.

## Tags
category: ui-bugs
module: nav / composition-boundary
