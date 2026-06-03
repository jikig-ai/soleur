---
title: "Redesign sidebar workspace context band — reorder pill above Back-to-menu + fold repo into pill"
type: feat
date: 2026-06-03
branch: feat-one-shot-sidebar-band-redesign
lane: cross-domain
requires_cpo_signoff: false
brand_survival_threshold: none
status: planned
---

# 🎨 Redesign sidebar workspace context band — reorder + fold repo into pill

Reclaim a wasted row in the dashboard sidebar's persistent workspace context band and
fix the vertical ordering of its two top elements. Two coupled visual/layout changes
to the expanded ("rail", non-collapsed) variant of the band.

## Overview

The dashboard sidebar mounts a persistent **workspace context band** (ADR-047, always
mounted, never gated on `collapsed`). Its expanded form currently renders four stacked
blocks top-to-bottom:

1. **"Back to menu"** link (drilled routes only) — `nav-back-chevron`
2. **Workspace pill** (`OrgSwitcherContainer` → `OrgSwitcher`)
3. **"Working on: {repo}" badge** (`LiveRepoBadge`) — its own full row
4. **Section title** (drilled routes only) — `nav-section-title`

Two problems: the pill sits *below* "Back to menu" (ordering reads backwards — the
persistent identity should lead), and the repo badge burns an entire row to surface one
short string (`jikig-ai/soleur`).

**This plan:**

1. **REORDER** — render the workspace pill **above** "Back to menu", and re-tune the
   `pt-*` spacing so the top of the band still breathes after the swap.
2. **FOLD** — surface the active repo name as a small muted **subtitle line inside the
   pill**, replacing the currently-visible `Owner`/`Member` role text on the *closed pill
   face*. The role label moves *into the dropdown* (it is already there for multi-org
   users; the solo branch — which has no dropdown — simply drops the role from the face).
   The standalone repo row is removed from the expanded band.

The collapsed (icon-only `md:w-14`) and mobile variants are preserved unchanged except
where the fold mechanically requires it; collapsed has no room for a subtitle and stays
icon-only.

This is a **visual/layout-only** change. No schema, no API contract change, no new
infrastructure. Verified via a QA browser screenshot (closed pill shows workspace name +
repo subtitle, no role on the face, pill above "Back to menu").

## Research Reconciliation — Spec vs. Codebase

The one-shot argument described the surface accurately but under-specified the layering.
Verified against the branch at plan time:

| Premise (from the request) | Codebase reality | Plan response |
| --- | --- | --- |
| "OrgSwitcher is the pill, lines ~148-152" | The band renders `OrgSwitcherContainer` (`workspace-context-band.tsx:150`), which renders `OrgSwitcher`. The pill *face* lives in `org-switcher.tsx`. | Edits target `org-switcher.tsx` (pill face) + `org-switcher-container.tsx` (data plumbing) + `workspace-context-band.tsx` (ordering / row removal). |
| "Replace the visible 'Owner' role text" (singular) | The role subtitle appears in **TWO** closed-pill branches: `workspace-identity-static` (solo, `org-switcher.tsx:86-88`) AND the interactive button (multi-org, `org-switcher.tsx:112-114`). | Remove the role subtitle from **both** faces; replace with repo subtitle. |
| "Move the role label into the dropdown menu" | The multi-org dropdown **already** shows role: `{roleLabel(m.role)} · {memberCount} members` (`org-switcher.tsx:153-156`). The solo branch has **no dropdown** at all. | Multi-org: role already in dropdown — no add needed (verify it stays). Solo: no dropdown exists; role simply leaves the face (there is nowhere to "move" it, and a solo user is always Owner of their own workspace — no information loss). |
| "Pull repoName from /api/workspace/active-repo, same source as LiveRepoBadge" | That fetch (poll-on-mount + window-focus, `fellBackToSolo` self-heal) lives entirely inside `LiveRepoBadge` (`live-repo-badge.tsx:30-48`). `OrgSwitcher` has no access to it. | Extract the fetch into a shared `useActiveRepo()` hook consumed by BOTH the container (to pass `repoName` into the pill) and `LiveRepoBadge` (which keeps the J5 interstitial). See Phase 1. |
| "Keep data-testid='live-repo-badge' reachable" | `live-repo-badge` testid + `workspace-context-band.test.tsx:94` + `live-repo-badge.test.tsx` assert the repo-name string. | Relocate the `data-testid="live-repo-badge"` element to the repo subtitle inside the pill; update the assertion in `workspace-context-band.test.tsx`. `live-repo-badge.test.tsx` keeps testing the (now interstitial-only) component — see Phase 4. |
| "Remove the standalone LiveRepoBadge row" | `LiveRepoBadge` ALSO owns the **J5 revocation interstitial** (`role="alert"`, `revocation-interstitial`), a distinct concern from the repo subtitle. | Do NOT delete `LiveRepoBadge` outright — strip its repo-name line (which moves into the pill) but KEEP the component mounted in the band for the interstitial. This also preserves the `nav-single-mount.test.ts` invariant (see Sharp Edges). |

## User-Brand Impact

**If this lands broken, the user experiences:** a sidebar whose workspace identity row is
mis-ordered, missing the repo name, or showing a stale repo (e.g., a duplicate-mount
showing the wrong workspace's repo). Pure orientation/cosmetic degradation — no data loss,
no cross-tenant exposure.

**If this leaks, the user's data is exposed via:** N/A — this change reads only the
already-exposed active-workspace repo name via the existing `/api/workspace/active-repo`
endpoint (tenant-scoped, self-healing, ADR-044). It introduces no new data surface, no new
write, no new field selection.

**Brand-survival threshold:** none — visual/layout change against an already-provisioned,
already-tenant-scoped endpoint. (threshold: none, reason: read-only layout change surfacing
an existing tenant-scoped string; no new data movement, write, or persistence.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (reorder):** In the expanded rail variant on a **drilled** route, the workspace
      pill DOM node renders **before** the `nav-back-chevron` ("Back to menu") node.
      Verifiable in `workspace-context-band.test.tsx` by asserting DOM order
      (`compareDocumentPosition` / `getAllByTestId` index, or `.toBe` on
      `node.compareDocumentPosition(other) & Node.DOCUMENT_POSITION_FOLLOWING`).
- [ ] **AC2 (top spacing):** The top element of the band (now the pill) carries the
      top-padding the band used to apply to its first child — assert the pill's wrapper has
      `pt-3` on a NON-drilled route (no "Back to menu" present). On a drilled route the pill
      leads with `pt-3` and "Back to menu" follows with a tighter `pt-2`.
- [ ] **AC3 (repo subtitle, multi-org):** The closed interactive pill face shows the
      workspace name (top line) AND the active repo name as a muted subtitle
      (`jikig-ai/soleur`). Assert `findByTestId("live-repo-badge")` has text content
      `jikig-ai/soleur` and is a descendant of the pill button.
- [ ] **AC4 (repo subtitle, solo):** The closed solo `workspace-identity-static` chip shows
      the workspace name AND the repo subtitle (same `live-repo-badge` testid), NOT the role.
- [ ] **AC5 (role off the face):** Neither closed-pill branch renders `Owner` / `Member`
      text on the face. Assert the closed multi-org button and the solo chip do NOT contain
      `Owner`/`Member` (before opening the dropdown).
- [ ] **AC6 (role in dropdown):** Opening the multi-org dropdown still shows
      `{role} · {N} members` per membership row (existing behavior preserved — assert it did
      not regress).
- [ ] **AC7 (standalone repo row gone):** The expanded band no longer renders a separate
      "Working on:" row beneath the pill. Assert there is exactly ONE element with text
      `jikig-ai/soleur`, and it is inside the pill.
- [ ] **AC8 (interstitial preserved):** When `/api/workspace/active-repo` returns
      `fellBackToSolo: true`, the `revocation-interstitial` (`role="alert"`) still renders.
      `live-repo-badge.test.tsx` covers this; assert it still passes.
- [ ] **AC9 (collapsed unchanged):** The collapsed (`data-collapsed="true"`) icon-only
      column is byte-unchanged in behavior — `live-repo-dot` + `workspace-identity-icon`
      still render; no repo subtitle is introduced. Assert the existing collapsed tests pass.
- [ ] **AC10 (single-mount invariant):** `nav-single-mount.test.ts` passes —
      `LiveRepoBadge` and `OrgSwitcherContainer` are each imported by exactly
      `workspace-context-band.tsx`. (The shared `useActiveRepo` hook is a hook, not a
      component, so it is NOT covered by this guard — verify the hook is excluded.)
- [ ] **AC11 (type + suite):** `cd apps/web-platform && npx tsc --noEmit` clean, and the
      affected vitest files pass via the runner from `package.json` `scripts.test`
      (`./node_modules/.bin/vitest run test/workspace-context-band.test.tsx
      test/org-switcher.test.tsx test/org-switcher-container.test.tsx
      test/live-repo-badge.test.tsx test/nav-single-mount.test.ts`).

### Post-merge (operator)

- [ ] **AC12 (QA screenshot):** Browser screenshot via Playwright MCP / `/soleur:qa`
      confirms on a drilled route: pill sits above "Back to menu"; closed pill shows
      workspace name + `jikig-ai/soleur` subtitle; no role on the face.
      Automation: feasible via Playwright MCP — fold into the QA step, do not punt.

## Implementation Phases

### Phase 1 — Extract a shared `useActiveRepo()` hook (data plumbing)

**Goal:** make the active-repo `repoName` (and `fellBackToSolo`) reachable by BOTH the pill
(via the container) and `LiveRepoBadge`, without a second component mount.

**File to create:** `apps/web-platform/hooks/use-active-repo.ts`

- Move the fetch/poll logic from `live-repo-badge.tsx:26-48` verbatim into a hook:
  `export function useActiveRepo(): { data: ActiveRepo | null }` — `fetch("/api/workspace/active-repo")`,
  poll on mount + `window` focus, keep-last-known on transient failure. Export the
  `ActiveRepo` interface too (or import from a shared types module).
- The hook owns NO rendering and NO `dismissed` state (that stays in `LiveRepoBadge`,
  which owns the interstitial UI).

**Why a hook, not prop-drilling from the band:** the band renders `OrgSwitcherContainer`
(which fetches memberships) — the container is the natural owner of the pill's data. Having
the container call `useActiveRepo()` and pass `repoName` to `OrgSwitcher` keeps `OrgSwitcher`
a pure presentational component (its current contract). The single-mount guard
(`nav-single-mount.test.ts`) tracks *component* imports, not hooks, so two hook consumers
are fine.

### Phase 2 — Fold repo subtitle into the pill face (`org-switcher.tsx`)

**File to edit:** `apps/web-platform/components/dashboard/org-switcher.tsx`

- Widen the `OrgSwitcher` prop contract: add `repoName?: string | null`.
- In the **solo** branch (`workspace-identity-static`, currently lines 72-92): replace the
  role subtitle (`roleLabel(current.role)`, lines 86-88) with the repo subtitle —
  `data-testid="live-repo-badge"`, muted text, `{repoName}` (render the empty/no-repo case
  gracefully: if `!repoName`, render nothing or a muted "No repo connected", matching
  `LiveRepoBadge`'s empty state — pick the same copy for consistency, see Open Questions).
- In the **multi-org** branch (interactive button, currently lines 94-117): replace the role
  subtitle (lines 112-114) with the same repo subtitle element.
- **Do NOT** change the dropdown body (lines 119-175): role already shows there
  (`{roleLabel(m.role)} · {memberCount} members`) — leave it.
- `roleLabel` is still used by the dropdown, so keep the function.

**Subtitle markup** (reuse the `live-repo-badge` visual idiom — gold dot + muted text — but
WITHOUT the "Working on:" prefix, since the pill context already implies it):
```tsx
{repoName ? (
  <span data-testid="live-repo-badge"
        className="block truncate text-xs text-soleur-text-muted">
    {repoName}
  </span>
) : null}
```

### Phase 3 — Wire the container + reorder + remove the standalone row

**File to edit:** `apps/web-platform/components/dashboard/org-switcher-container.tsx`

- Call `const { data: repo } = useActiveRepo();` and pass
  `repoName={repo?.repoName ?? null}` to `<OrgSwitcher … />`.

**File to edit:** `apps/web-platform/components/dashboard/workspace-context-band.tsx`

- **Reorder (expanded variant only):** move the pill block (`OrgSwitcherContainer` wrapper,
  lines 148-152) ABOVE the "Back to menu" `Link` block (lines 137-147).
- **Spacing re-tune:** the pill block becomes the band's first child. Give the pill wrapper
  `pt-3` always; give "Back to menu" (now second) `pt-2` (tighter, since it follows the
  pill). Currently the pill uses `${drill ? "pt-2" : "pt-3"}` and Back-to-menu uses `pt-3` —
  invert the relationship so the *leading* element gets the `pt-3` breathing room.
- **Remove the standalone repo row** (lines 154-156: `<div className="px-3 pb-2 pt-1"><LiveRepoBadge /></div>`)
  is replaced by mounting `LiveRepoBadge` for its INTERSTITIAL ONLY. Two options — pick in
  Phase 4 after deciding the test shape:
  - **(a)** Keep `<LiveRepoBadge />` mounted (so the import + single-mount invariant holds
    and the interstitial still renders) but have `LiveRepoBadge` render `null` for the
    repo-name line (it now only emits the interstitial when `fellBackToSolo`). The empty
    no-op row collapses (no `px-3 pb-2 pt-1` wrapper when there's no interstitial).
  - **(b)** keep the wrapper but let `LiveRepoBadge` self-collapse.
  Recommended: (a) — `LiveRepoBadge` becomes the **interstitial-only** component; its
  repo-name branch is deleted (that string now lives in the pill).

### Phase 4 — Update `LiveRepoBadge` + tests

**File to edit:** `apps/web-platform/components/dashboard/live-repo-badge.tsx`

- Refactor to consume `useActiveRepo()` instead of its own inline fetch (delete the moved
  lines).
- Delete the repo-name render branch (lines 75-89, the `data-testid="live-repo-badge"`
  block) — that string is now the pill subtitle. Keep the `fellBackToSolo` interstitial
  (lines 55-73) and the empty/no-data guard. The component now renders the interstitial or
  `null`.
- Consequence: `data-testid="live-repo-badge"` and `live-repo-badge-empty` testids leave
  this component and (for `live-repo-badge`) reappear inside the pill. Update
  `live-repo-badge.test.tsx` accordingly (its repo-name assertions move to
  `org-switcher.test.tsx`; its interstitial assertions stay).

**Files to edit (tests):**
- `apps/web-platform/test/org-switcher.test.tsx` — add `repoName` to the fixtures; assert
  the repo subtitle (`live-repo-badge`) on both solo and multi-org closed faces; assert role
  is NOT on the face but IS in the dropdown (AC3/4/5/6).
- `apps/web-platform/test/workspace-context-band.test.tsx` — update the
  `findByTestId("live-repo-badge")` assertion (line 94) to expect it inside the pill; add the
  DOM-order assertion (AC1) and the spacing assertion (AC2); add the standalone-row-gone
  assertion (AC7).
- `apps/web-platform/test/live-repo-badge.test.tsx` — drop repo-name string assertions; keep
  interstitial (`fellBackToSolo`) assertions (AC8).
- `apps/web-platform/test/org-switcher-container.test.tsx` — stub `/api/workspace/active-repo`
  alongside `list-memberships`; assert `repoName` reaches the pill.
- `apps/web-platform/test/nav-single-mount.test.ts` — no change expected; verify it still
  passes (AC10). If the hook accidentally trips it, the test is component-scoped so it
  shouldn't — confirm.

### Phase 5 — Verify collapsed + mobile variants untouched

- Collapsed icon-only column (`workspace-context-band.tsx:73-116`): no change. Re-run
  `nav-rail-drill.test.tsx` / collapsed cases (AC9).
- Mobile variant (`variant === "mobile"`): the band's `return` shares the expanded JSX, so
  the reorder + fold apply to mobile too — which is desired (mobile also benefits from the
  reclaimed row). Confirm mobile tests pass; the mobile band has room for the subtitle.

## Files to Edit

- `apps/web-platform/components/dashboard/workspace-context-band.tsx` (reorder, spacing, row removal)
- `apps/web-platform/components/dashboard/org-switcher.tsx` (repo subtitle on both faces, role off face)
- `apps/web-platform/components/dashboard/org-switcher-container.tsx` (consume hook, pass repoName)
- `apps/web-platform/components/dashboard/live-repo-badge.tsx` (interstitial-only refactor)
- `apps/web-platform/test/org-switcher.test.tsx`
- `apps/web-platform/test/org-switcher-container.test.tsx`
- `apps/web-platform/test/workspace-context-band.test.tsx`
- `apps/web-platform/test/live-repo-badge.test.tsx`

## Files to Create

- `apps/web-platform/hooks/use-active-repo.ts` (shared active-repo fetch/poll hook)
- `knowledge-base/product/design/navigation/sidebar-band-reorder-fold.pen` (wireframe — see Domain Review)

## Open Code-Review Overlap

None — checked open `code-review`-labeled issues against the file list at plan time; no
open scope-out references these dashboard component paths.

## Open Questions

1. **No-repo subtitle copy on the pill:** when `repoName` is null, render nothing, or
   "No repo connected" (matching `live-repo-badge-empty`)? Leaning: render nothing on the
   pill face (the closed pill stays compact; the empty state is rare and low-signal). Confirm
   with the wireframe.
2. **Subtitle prefix:** drop "Working on:" inside the pill (context implies it) — confirm in
   the wireframe.

## Domain Review

**Domains relevant:** Product (UI surface).

### Product/UX Gate

**Tier:** blocking — the plan edits `components/dashboard/*.tsx` (UI-surface override fires).
This modifies existing user-facing components (no NEW page/route file), but the mechanical
UI-surface term match forces BLOCKING.
**Decision:** auto-accepted (pipeline) for the CPO/spec-flow advisory; `ux-design-lead`
wireframe is a non-skippable producer.
**Pencil available:** to be resolved by `deepen-plan` (it runs the Product/UX pipeline with
agent access). The `.pen` MUST be produced at `knowledge-base/product/design/navigation/sidebar-band-reorder-fold.pen`
and referenced in the FRs before `/work` — `wg-ui-feature-requires-pen-wireframe`. The
wireframe shows: closed pill (name + repo subtitle, no role) sitting above "Back to menu";
open dropdown (role still per-row); collapsed icon-only column unchanged.
**Skipped specialists:** none.

#### Findings

Low-risk layout polish on an existing, already-shipped band. No new flows, no copy with
persuasive/emotional weight, no error-state changes (the interstitial is preserved verbatim).
The single substantive design decision is the closed-pill subtitle (repo vs role) — the
wireframe resolves the two Open Questions.

## Observability

Not applicable — pure client-side layout change. No Files-to-Edit under `apps/*/server/`,
`apps/*/infra/`, or `plugins/*/scripts/`; the only edited `apps/*/src`-class files are React
components with no new telemetry surface. Existing `/api/workspace/active-repo` observability
(server route) is unchanged. (Phase 2.9 skip: no new code/infra liveness surface introduced.)

## Test Scenarios

| Scenario | Expectation |
| --- | --- |
| Drilled route, multi-org user | Pill (name + repo subtitle) above "Back to menu"; no role on face; dropdown shows role per row |
| Drilled route, solo user | Static chip (name + repo subtitle) above "Back to menu"; no role; no dropdown |
| Non-drilled route | Pill leads with `pt-3`; no "Back to menu", no section title |
| `fellBackToSolo: true` | Revocation interstitial still renders (alert) |
| No repo connected | Pill shows name only (no subtitle); no standalone "No repo connected" row |
| Collapsed `md:w-14` | Icon-only column unchanged (dot + avatar + section glyph) |

## Sharp Edges

- **Single-mount guard (`nav-single-mount.test.ts`):** it asserts `LiveRepoBadge` and
  `OrgSwitcherContainer` are each imported by EXACTLY `workspace-context-band.tsx`. Do NOT
  delete `LiveRepoBadge` (that would break the `expect(importers).toEqual([...band])`
  assertion which expects the band to be the importer) and do NOT import either component
  anywhere new. The shared `useActiveRepo` is a HOOK (not in the guard's CASES list) so two
  consumers are safe — but double-check no test was added that imports `LiveRepoBadge`
  outside the band.
- **Both pill branches carry the role today** — the fold must touch BOTH
  `workspace-identity-static` (solo) AND the interactive button (multi-org). Editing only one
  leaves a role label on the other face (AC5 catches this). See learning
  `knowledge-base/project/learnings/2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`
  (same defect class: a layout fix that touches one render branch and leaves its sibling).
- **`live-repo-badge` testid moves, not duplicates.** After the fold, exactly ONE element
  carries `data-testid="live-repo-badge"` (inside the pill). `LiveRepoBadge` no longer emits
  it. AC7 + the single-element assertion guard against an accidental double-mount of the repo
  string.
- **Mobile variant inherits the reorder/fold** (shared `return` JSX). That is intended
  (mobile also reclaims the row), but verify the mobile band's `findByTestId("live-repo-badge")`
  expectations if any mobile-specific test asserts the old row position.
- **Vitest test paths:** affected tests live in `apps/web-platform/test/*.test.tsx`, which
  matches the `component` project glob `test/**/*.test.tsx` (happy-dom). Do NOT co-locate a
  new test under `components/` — vitest would silently skip it. The runner is **vitest**
  (`./node_modules/.bin/vitest run …`), NOT `bun test` (blocked by
  `apps/web-platform/bunfig.toml`).
- **The `.pen` wireframe is a hard gate** for this UI feature
  (`wg-ui-feature-requires-pen-wireframe`). `deepen-plan` must produce it (or hard-block);
  it cannot be skipped.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`, or omits
  the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled, threshold
  `none` with reason.)

## Alternative Approaches Considered

| Approach | Rejected because |
| --- | --- |
| Pass `repoName` from the band into the container via props (band fetches) | The band is a presentational shell that takes only `pathname`/`variant`/`collapsed`; it deliberately does not own async data. The container already owns the pill's async (memberships). Keeping the active-repo fetch in the container (via hook) preserves that boundary. |
| Have `OrgSwitcher` fetch `/api/workspace/active-repo` itself | Breaks `OrgSwitcher`'s pure-presentational contract (it takes `memberships` as a prop and renders); pushing a fetch into it duplicates the poll/focus logic and complicates its many existing tests. |
| Delete `LiveRepoBadge` entirely and inline the interstitial in the band | Loses a cohesive, tested interstitial component and breaks the single-mount guard's expectation that the band imports `LiveRepoBadge`. The interstitial is a distinct concern worth keeping isolated. |
| Add a repo subtitle to the collapsed icon-only column | No horizontal room at `md:w-14` (56px) — the original #4810 fix exists precisely to avoid overflow there. Collapsed stays icon-only (the `live-repo-dot` already signals repo presence). |
