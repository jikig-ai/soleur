---
title: Workspace context band + switcher render outside the single-rail swap region; secondary navs lift in via a portal slot
status: active
date: 2026-06-02
related_adrs: [ADR-044]
related: [4813, 4810, 4826, 5632]
related_plans:
  - knowledge-base/project/plans/2026-06-02-feat-single-nav-rail-drill-in-plan.md
related_specs:
  - knowledge-base/project/specs/feat-single-nav-rail/spec.md
brand_survival_threshold: single-user incident
principles: [AP-011]
---

# ADR-047: Workspace context band outside the single-rail swap region

## Context

The dashboard previously rendered two side-by-side rails: a primary nav rail and a
section-specific secondary rail (KB file tree / Settings sub-nav / Chat conversations
rail), each owned by its route-segment layout. The single-nav-rail feature (#4813)
collapses these into ONE rail where the secondary nav *replaces* the primary nav,
driven by the URL segment, with a back chevron returning to the top level.

Two forces make this a **single-user-incident** brand-survival change, not a cosmetic one:

1. **Workspace identity must never be ambiguous during a tenant-sensitive action.** The
   pre-existing `(dashboard)/layout.tsx` *unmounted* `OrgSwitcherContainer` +
   `LiveRepoBadge` when the rail collapsed (`!collapsed` gate) — a live bug: a user could
   invite a member / share an API key / edit scope grants with no visible active-workspace
   indicator. Collapsing to one rail, where the rail body now *swaps* on every navigation,
   makes any identity element mounted *inside* the swap region disappear on drill.

2. **The swap region trap (App Router `children`).** Next.js swaps `children` on every
   navigation. Anything that must persist across drills (the workspace identity) cannot
   live in the swapped body — the same class as the 2026-04-10 "KB tree disappears on
   file select" bug.

A secondary structural force: the three secondary navs are not symmetric. The KB file
tree depends on `KbContext` (one `/api/kb/tree` fetch shared with the doc viewer + chat
panel, established in `kb/layout.tsx`); the Settings sub-nav depends on server-resolved
`membersTab`/`activityTab` props (resolved in `settings/layout.tsx`); the Conversations
rail is self-contained. A naive "render the secondary nav directly in the dashboard
layout, keyed by segment" would force lifting KB/Settings data layers up to the always-
mounted parent — fetching the KB tree on every dashboard route, or duplicating the fetch.

## Decision

**1. The persistent context band renders OUTSIDE the swap region, never gated on
`collapsed`.** A single `WorkspaceContextBand` is mounted directly in
`(dashboard)/layout.tsx` (desktop rail) / the mobile top bar — above the swap region. It
is the SOLE render site for `OrgSwitcherContainer` + `LiveRepoBadge` (single-mount,
enforced by a negative-space import guard). Workspace identity is therefore present in
EVERY drill state on EVERY breakpoint (the load-bearing brand invariant). The band also
carries the net-new chrome: the back chevron (synchronous, slot reserved when not drilled
— no layout shift) and the section-title label.

**2. Drilled sections lift their secondary nav into the rail via a React portal.** The
rail renders one secondary-nav *slot* below the band; each segment layout portals its nav
into that slot (`RailSlotPortal` → `createPortal`). React context follows the *React*
tree, not the DOM tree, so the KB tree portaled from inside `KbContext` keeps its provider
(one fetch) while its DOM lands in the unified rail; the Settings sub-nav keeps its
server-resolved props. This avoids both lifting data layers and double-fetching.

**3. `segmentToDrillLevel(pathname)` is the sole drill-state authority** (allowlist
`kb|settings|chat`; `/dashboard/admin/analytics` stays top-level). Every drill-detection
`pathname.startsWith(...)` literal routes through it (grep-enforced).

**4. The wrong-workspace detector ships with the prevention.** `emitWorkspaceActionContext`
logs the active workspace (hashed actor) at commit time on invite / api-key-share /
scope-grant, so a wrong-workspace action is detectable post-hoc without a dashboard eyeball.

## Considered Options

- **Render secondary navs directly in the dashboard layout, keyed by segment.** Rejected:
  forces the KB/Settings data layers up to the always-mounted parent → tree fetched on
  every dashboard route, or two `useKbLayoutState` instances (two fetches, split state).
- **Portal slot (chosen).** Keeps each nav inside its own provider subtree; one fetch;
  the dashboard layout owns only the slot node + the swap decision.
- **CSS-hide the primary nav instead of a true conditional swap.** Rejected: jsdom can't
  distinguish `display:none`, and a hidden-but-mounted secondary nav re-creates the
  double-mount / duplicate-Realtime-channel hazard. The swap is a true conditional render.

## Consequences

- **Single-mount is now a hard invariant** (`nav-single-mount.test.ts`): a second mount of
  the identity components would put a stale duplicate workspace on screen — the exact
  failure this ADR prevents.
- **Portals are client-only.** The secondary nav appears after hydration, not in the SSR
  HTML. Acceptable for the client-rendered dashboard; tests use a `RailSlotHarness` to
  supply a slot node in isolation.
- **One collapse key.** The per-section collapse keys (`settings`, `chat-rail`) are orphaned
  and swept once; the unified rail owns collapse via a single ⌘B handler. KB collapse stays
  ephemeral (in-memory).
- **Position-resume is cut to a follow-up (#4826):** section re-entry lands at the section
  root; the open KB file is still preserved by the URL.
- **Visual contracts move to Playwright.** jsdom layout assertions on the deleted section
  asides were removed; rail-collapse visuals are verified by the AC10 walkthrough.

## Amendment 2026-06-22 (#5632): "never gated on `collapsed`" extends to the band's INTERNAL render path

Decision 1 located the band *outside* the App-Router swap region and decided it is "never
gated on `collapsed`." A later sidebar pass (#4810/#4915) honored the *location* clause but
re-introduced a `collapsed` gate one level deeper, *inside* the band: `WorkspaceContextBand`
early-returned a structurally-divergent icon-only subtree when `collapsed` that **omitted
`OrgSwitcherContainer` entirely**, feeding the collapsed tile from a separate
`useActiveWorkspace` hook instead. React reconciles by position, so swapping to a subtree
without the container **unmounted it on every collapse and mounted a fresh instance on every
expand** — re-running its `/api/workspace/list-memberships` fetch, resetting its state, and
discarding any in-flight switch-confirm dialog (the visible "selector glitches and reloads"
bug). This is the *same* unmount defect as the original `!collapsed` gate, relocated one
level deeper.

**Amendment:** the "never gated on `collapsed`" invariant is **structural, not locational** —
it extends to the band's internal render path. A `collapsed` early-return (or any element
swap) that removes `OrgSwitcherContainer` from the tree is prohibited. The collapse/expand
toggle MUST be a *presentation* change (className branches, an icon-only **mode** of the
mounted `OrgSwitcher` via its `collapsed` prop) on a **persistent** element — never an
element swap. Consequently the `useActiveWorkspace` data-duplication hook (added only to feed
the gated-out collapsed tile, fetching the same endpoint a second time) is **retired**: the
single mounted container is again the sole source of workspace identity in both states. The
`nav-single-mount.test.ts` import guard stays the structural backstop; the new
`workspace-selector-collapse-persists.test.tsx` adds the lifecycle backstop (zero refetch
across a collapse→expand toggle), since happy-dom presence assertions cannot observe a
remount. Status stays `active` — this amendment describes the current (now-correct) target
state.
