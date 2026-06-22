---
title: "fix: sidebar collapse no longer remounts/refetches the workspace selector"
type: fix
date: 2026-06-22
branch: feat-one-shot-sidebar-collapse-selector-remount
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_adrs: [ADR-047, ADR-044]
related_prs: [5075, 4915, 4810]
---

# fix: Collapsing the sidebar must not remount/refetch the workspace selector 🐛

## Enhancement Summary

**Deepened on:** 2026-06-22
**Sections enhanced:** Implementation Phases, Test Strategy, Research Reconciliation, Sharp Edges
**Research agents used:** React-reconciliation researcher, codebase-structure investigator,
verify-the-negative + implementation-realism pass, precedent-diff pass.

### Key Improvements
1. **Root cause precisely localized** to the `collapsed` early-return at
   `workspace-context-band.tsx:83` — a regression against active ADR-047's
   "never gated on `collapsed`" decision, relocated one level deeper than the
   original `!collapsed` bug.
2. **Fix design grounded in the house-style precedent split:** presentational chrome
   (ThemeToggle, kb-sidebar-shell) MAY early-return two trees, but the **data-bearing**
   `OrgSwitcherContainer` is exactly the ADR-047 keep-mounted case. The fix keeps the
   container mounted and renders its icon-only presentation internally.
3. **All seven negative/structural claims verified** (single-mount import guard stays
   green; `useActiveWorkspace` has a single runtime consumer; no e2e assertion breaks).

### New Considerations Discovered
- The hypothesized `test/use-active-workspace.test.ts(x)` does **not** exist — the
  "delete the test" step is a correct no-op (two similarly-named test files are
  unrelated server-resolver tests that never import the hook).
- **No** existing test asserts a mount-counter / fetch-count invariant across a collapse
  toggle — the load-bearing regression test (Test Strategy #1) is net-new; mirror the
  `vi.fn()` fetch-spy + `rerender({collapsed})` + `toHaveBeenCalledTimes(1)` shape.
- The switch-confirm dialog (`role="dialog"`, `org-switcher-container.tsx:234`) has no
  focus trap / `autoFocus`, so gating its render when collapsed (`pending && !collapsed`)
  strands no focus — safe.

## Overview

Each time the user collapses or expands the main dashboard sidebar, the workspace
selector ("Soleur Workspace" pill with avatar, org name `jikig-ai/soleur`, and `▾`
chevron) flashes and reloads its data. The cause is a **conditional-render subtree
swap** inside `WorkspaceContextBand`: the rail variant *early-returns a completely
different subtree when `collapsed` is true*, and that collapsed subtree does **not**
contain `OrgSwitcherContainer`. React therefore unmounts `OrgSwitcherContainer` on
every collapse and mounts a fresh instance on every expand — re-running its mount
`useEffect` (`fetch("/api/workspace/list-memberships")`), resetting `memberships` to
`null`, and returning `null` until the round-trip resolves (the visible "glitch +
reload"). It also discards any in-flight switch-confirm dialog state.

This is a **regression against an active ADR**. ADR-047 ("Workspace context band
outside the single-rail swap region") explicitly decided the band renders
**"never gated on `collapsed`"** precisely because the *original* live bug was a
`!collapsed` gate that unmounted `OrgSwitcherContainer`. The current code moved the
band out of the App-Router swap region (honoring ADR-047 §Decision 1's location
clause) but then **re-introduced a `collapsed` gate one level deeper, inside the band
itself** — silently re-creating the exact unmount/remount the ADR set out to kill.

The fix keeps a single `OrgSwitcherContainer` instance mounted across the
collapse/expand toggle and switches only its *presentation* (full pill ↔ icon-only
tile), so React preserves its state and fires no refetch. The redundant
`useActiveWorkspace` hook — which exists *only* because the collapsed band lacked the
container's data — and its prop-threading are then removed.

### Root-cause evidence (file:line)

- `apps/web-platform/components/dashboard/workspace-context-band.tsx:83` —
  `if (variant === "rail" && collapsed) { return <icon-only tree> }` — the
  structurally-divergent early return. Its own comment (`:79–82`) admits "The
  identity is never FULLY unmounted (ADR-047): the data-bearing OrgSwitcherContainer
  … stay[s] mounted in the CSS-exclusive **mobile** band" — i.e. it *knowingly*
  relies on a second, CSS-hidden mobile instance to keep data alive, while the
  *visible* desktop instance churns.
- `apps/web-platform/components/dashboard/org-switcher-container.tsx:87–94` — mount
  `useEffect` calls `loadMemberships()` → `fetch("/api/workspace/list-memberships")`;
  `:214` returns `null` while `memberships === null`. Local `useState` for
  `memberships`, `pending`, `status`, `postRpcRetries` (`:51–56`) is lost on unmount.
- `apps/web-platform/app/(dashboard)/layout.tsx:136` —
  `useActiveWorkspace(collapsed)` — a *second* fetch of the SAME endpoint, added
  (`#4915` P0-3) solely to feed the collapsed tile that lacks the container's data.
- `knowledge-base/engineering/architecture/decisions/ADR-047-nav-context-band-outside-swap.md`
  §Decision 1 + §Context bullet 1: the band must be "never gated on `collapsed`"; the
  original bug was the `!collapsed` unmount gate.

## Premise Validation

- **Component exists (not a never-built feature):** `OrgSwitcherContainer`,
  `OrgSwitcher`, `WorkspaceContextBand`, `WorkspaceIdentityTile`, and
  `useActiveWorkspace` all exist on the branch and are rendered from
  `app/(dashboard)/layout.tsx` (two band mount sites, `:282` mobile + `:387` rail).
  This is a **behavioral fix**, not a build.
- **Cited mechanism vs ADR corpus:** the "keep mounted, never gate on collapse"
  mechanism is the *explicit decision* of ADR-047 (not a rejected alternative) — the
  fix re-aligns the code with the ADR rather than diverging from it.
- **Screenshot symptoms confirmed against code:** collapsed = grid-icon Dashboard
  nav + icon-only identity tile (`workspace-context-band.tsx:99–124`); expanded =
  full pill with avatar + name + `▾` (`org-switcher.tsx:110–`). Both match.
- **No stale external premises (no `#N` cited as blocker).** Nothing to falsify via
  `gh`.

## Research Reconciliation — Spec vs. Codebase

| Claim (from bug report) | Codebase reality | Plan response |
| --- | --- | --- |
| "Selector fully unmounts and reloads data each collapse/expand" | True for the **visible desktop rail** instance: the band's `collapsed` early-return omits `OrgSwitcherContainer` (`workspace-context-band.tsx:83`). A *second* mobile instance stays mounted (CSS-hidden) but is never visible on desktop. | Keep the rail instance mounted across collapse; presentation-only toggle. |
| "Preserve state instead of remounting" | `OrgSwitcherContainer` holds `memberships` + switch-confirm (`pending`/`status`/`postRpcRetries`) in local `useState`; only keeping the instance mounted preserves them. A module cache would save *data* but not the confirm dialog. | Pattern 2a (keep instance mounted) — not a cache-only fix. |
| Collapsed tile data comes from a separate hook | `useActiveWorkspace` (`hooks/use-active-workspace.ts:33`) fetches the **same** `/api/workspace/list-memberships`, picks `isCurrent ?? [0]` — identical to `OrgSwitcher`'s `current` (`org-switcher.tsx:73`). | Render the collapsed tile from the container's own `current` membership; delete `useActiveWorkspace` + its prop threading. |
| Fix risks a second mount (single-mount invariant) | `nav-single-mount.test.ts` guards **imports** (one importer module = `workspace-context-band.tsx`), not runtime instances. | Fix keeps the import in that one file → guard stays green. |

## User-Brand Impact

**If this lands broken, the user experiences:** a workspace selector that either (a)
keeps flashing/reloading on every sidebar collapse (status quo, the bug), or (b) — if
the fix is wrong — shows the **wrong** active workspace (a stale or absent identity)
while the user performs a tenant-sensitive action (invite a member, share an API key,
edit scope grants). ADR-047 classifies an ambiguous active-workspace indicator during
a tenant action as the load-bearing brand invariant.

**If this leaks, the user's workflow/data is exposed via:** acting against the wrong
tenant's repo because the visible workspace identity disagreed with the durable
`current_workspace_id`. The selector IS the orientation anchor for cross-tenant
safety; a remount that briefly blanks or desyncs it is the exposure vector.

**Brand-survival threshold:** single-user incident.

> CPO sign-off required at plan time before `/work` begins. CPO is the relevant
> domain leader (workspace-identity UX correctness). `user-impact-reviewer` will be
> invoked at review-time per the review skill's conditional-agent block.

## Implementation Phases

> Phase order is load-bearing: the contract-changing leaf (`OrgSwitcher` gains a
> `collapsed` mode) lands **before** its consumer (`OrgSwitcherContainer` threads
> `collapsed`), which lands before the band stops swapping subtrees — so no phase
> ships dead code or a vacuously-green test.

### Research Insights — precedent-diff (house-style split)

The repo has **two** established collapse idioms, and the choice between them is the
crux of this fix:

- **Presentational chrome → early-return two trees is acceptable.** `ThemeToggle`
  (`components/theme/theme-toggle.tsx:67-98` vs `:124-162`), `kb-sidebar-shell.tsx:40-95`,
  and the *current* band all early-return an icon-only subtree when `collapsed`. This is
  fine for stateless chrome because there is nothing to lose on remount.
- **Data-bearing / stateful child → keep ONE instance mounted, toggle presentation.**
  This is the ADR-047 rule and the established idiom for the nav `<Link>` items
  (`layout.tsx:411-433`: the same element stays mounted, only `className`/`title` flip
  on `collapsed` — `${collapsed ? "md:hidden" : ""}` on the label span). `OrgSwitcherContainer`
  is data-bearing (membership fetch + switch-confirm `useState`), so it MUST follow the
  keep-mounted idiom — NOT the chrome early-return.

The current bug is precisely a **category error**: the band applied the *chrome*
early-return idiom to a *data-bearing* child. The fix moves `OrgSwitcherContainer` to the
keep-mounted idiom (Phases 1–3), with its icon-only collapsed presentation rendered
*inside* the still-mounted container. Precedent endorsement:
`knowledge-base/project/learnings/best-practices/2026-06-09-conditional-render-swap-does-not-animate-needs-mount-flag.md`
("a transition/state only survives on an element that **persists across the state
change**"; conditional swap = unmount = state/transition lost; unit tests can't see it).

### Phase 0 — Preconditions (grep/read, no edits)

0.1. Confirm the single-mount guard scope: `nav-single-mount.test.ts` asserts the
import set `["components/dashboard/workspace-context-band.tsx"]` and scans
`app|components|hooks` (`test/nav-single-mount.test.ts:14,38–48`). Do **not** add a
new importer of `org-switcher-container`/`live-repo-badge`.
0.2. Confirm `OrgSwitcher` has no `collapsed` prop today and renders three full-width
forms only (`org-switcher.tsx:22–35`, `:71`, `:80`, `:110`). The collapsed icon-only
form is currently a *different component* (`WorkspaceIdentityTile`) rendered in the
band, not a mode of `OrgSwitcher`.
0.3. Confirm `OrgMembershipSummary` carries `organizationName`, `workspaceId`,
`hasLogo`, `isCurrent` (`server/org-memberships-resolver.ts:8–18`) so the collapsed
tile renders from the container's own `current` membership.
0.4. Enumerate `useActiveWorkspace` consumers: sole runtime caller is
`app/(dashboard)/layout.tsx:136`; a comment-only reference in
`lib/workspace-logo-events.ts`. (Confirms safe deletion.)
0.5. `vitest.config.ts` include globs: component tests = `test/**/*.test.tsx`
(happy-dom); unit = `test/**/*.test.ts` (node) (`vitest.config.ts:40–81`). Edited
band test stays `test/workspace-context-band.test.tsx`.

### Phase 1 — `OrgSwitcher` gains an icon-only collapsed mode (RED→GREEN)

`apps/web-platform/components/dashboard/org-switcher.tsx`

- Add an optional `collapsed?: boolean` prop (default `false`).
- When `collapsed` is true AND `memberships.length >= 1`, render an **icon-only**
  form: a single `WorkspaceIdentityTile` (`size="sm"`, `variant="identity"`,
  `workspaceId`/`hasLogo`/`name` from `current`), wrapped in the element carrying
  `data-testid="workspace-identity-icon"` + `aria-label`/`title = current.organizationName`
  (preserving the testid + tooltip the e2e at `nav-states-shell.e2e.ts:500–513,567`
  and the band unit suite rely on). Keep `memberships.length === 0 → null`.
- When `collapsed` is false, behavior is byte-for-byte unchanged (solo static chip /
  multi pill + dropdown). Add RED tests first (see Test Strategy) asserting:
  collapsed multi renders `workspace-identity-icon` with the name as `title` and NO
  `▾`/`Switch workspace` button; collapsed solo renders the same icon tile; expanded
  forms unchanged.

> Why fold the collapsed form into `OrgSwitcher` rather than keep
> `WorkspaceIdentityTile` in the band: the *same* `OrgSwitcherContainer` instance
> must own both presentations so the toggle is a prop change on a persistent element,
> not an element swap (the only thing that preserves the fetch + confirm-dialog
> state). See `2026-06-09-conditional-render-swap-does-not-animate-needs-mount-flag.md`.

### Phase 2 — `OrgSwitcherContainer` threads `collapsed` and renders one tree

`apps/web-platform/components/dashboard/org-switcher-container.tsx`

- Add `collapsed?: boolean` prop; pass it to `<OrgSwitcher collapsed={collapsed} />`
  (`:228`).
- Keep `if (memberships === null) return null` (`:214`) — preserves the existing
  no-flash-on-first-load contract; once mounted, subsequent collapses no longer
  remount, so `memberships` is never reset back to `null`.
- When `collapsed`, suppress the switch-confirm dialog block (`pending && …`,
  `:234–334`) from rendering in the cramped 56px rail — but **do not unmount the
  container**; the `pending`/`status` state persists and the dialog reappears on
  expand. (Container stays the single data + dialog-state owner.)
- The outer wrapper's `py-3`/padding may differ per state via a `collapsed` class
  branch; this is a className change on a persistent element, not an element swap.

### Phase 3 — `WorkspaceContextBand` stops swapping subtrees

`apps/web-platform/components/dashboard/workspace-context-band.tsx`

- **Delete the `collapsed` early return (`:83–127`).** Render ONE subtree for the
  rail variant in both states. `<OrgSwitcherContainer collapsed={variant === "rail" && collapsed} />`
  is always present at the same tree position.
- The collapsed icon-only presentation now comes from `OrgSwitcherContainer`/`OrgSwitcher`
  (Phase 1–2), so the band no longer needs `activeWorkspaceName`/`activeWorkspaceId`/
  `activeWorkspaceHasLogo` props or the inline `WorkspaceIdentityTile`. Remove those
  props from the band's signature (`:54–64`) and the inline tile render (`:111–124`).
- Preserve the collapsed-state container/styling so the rail still reserves top
  clearance for the floated collapse toggle and renders the back chevron when
  drilled. The back-chevron + section-title rows (`:193–217`) stay; gate their
  *layout* (icon column vs full rows) on `collapsed` via className, not via an
  element swap that removes the container.
- Keep `data-testid="workspace-context-band"`, `data-variant`, and
  `data-collapsed="true"` (when collapsed) — e2e selectors depend on them
  (`nav-states-shell.e2e.ts:349–353,500`).

### Phase 4 — Remove the now-redundant `useActiveWorkspace` and its threading

`apps/web-platform/app/(dashboard)/layout.tsx`

- Remove `const activeWorkspace = useActiveWorkspace(collapsed)` (`:136–137`) and the
  `activeWorkspaceName/Id/HasLogo` props passed to the rail band (`:390–392`).
- Remove the `useActiveWorkspace` import (`:13`).
- Delete `apps/web-platform/hooks/use-active-workspace.ts` (sole runtime consumer was
  the layout). Update the comment-only reference in
  `apps/web-platform/lib/workspace-logo-events.ts` if it names the hook.
- Delete the dedicated test `apps/web-platform/test/use-active-workspace.test.ts(x)`
  if present (grep in Phase 0; if it exists, remove with the hook).

> Scope guard: only remove `useActiveWorkspace` after Phase 3 makes the collapsed
> band data-self-sufficient. If a non-layout consumer surfaces in the Phase 0.4 grep,
> downgrade Phase 4 to "leave the hook, just stop the layout from calling it" and note
> the deferral.

### Phase 5 — Typecheck + full suite

- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/workspace-context-band.test.tsx test/org-switcher.test.tsx test/org-switcher-container.test.tsx test/dashboard-sidebar-collapse.test.tsx test/nav-single-mount.test.ts`
- Full suite per `package.json scripts.test` before ship.

## Files to Edit

- `apps/web-platform/components/dashboard/org-switcher.tsx` — add `collapsed` icon-only mode (Phase 1).
- `apps/web-platform/components/dashboard/org-switcher-container.tsx` — thread `collapsed`, suppress dialog when collapsed (Phase 2).
- `apps/web-platform/components/dashboard/workspace-context-band.tsx` — delete the `collapsed` early return; single subtree; drop the threaded-name props (Phase 3).
- `apps/web-platform/app/(dashboard)/layout.tsx` — remove `useActiveWorkspace` call + import + prop threading (Phase 4).
- `apps/web-platform/lib/workspace-logo-events.ts` — update comment-only reference if it names the hook (Phase 4).
- `apps/web-platform/test/org-switcher.test.tsx` — add collapsed-mode cases (Phase 1).
- `apps/web-platform/test/workspace-context-band.test.tsx` — rewrite the collapsed suite (`:222–264`) to supply membership data via the container (stub `fetch`) instead of the `activeWorkspaceName` prop; assert `workspace-identity-icon` still renders with the name as `title` and no `▾` (Phase 3).
- `apps/web-platform/test/org-switcher-container.test.tsx` — add a collapsed-prop case (dialog suppressed, identity icon shown); existing switch-write-path tests unchanged (default expanded).

## Files to Create / Delete

- DELETE `apps/web-platform/hooks/use-active-workspace.ts` (Phase 4, conditional on Phase 0.4 grep).
- DELETE `apps/web-platform/test/use-active-workspace.test.ts(x)` — **verified absent at deepen-plan time**, so this resolves to a no-op (the two `*active-workspace*` test files in `test/` are unrelated server-resolver tests that do not import the hook).
- ADD (optional) `apps/web-platform/test/workspace-selector-collapse-persists.test.tsx` — a focused **mount-counter** regression test (see Test Strategy) proving collapse→expand does not remount the container / refire the fetch.

## Open Code-Review Overlap

None found at plan time. (Run `gh issue list --label code-review --state open --json number,title,body --limit 200` then `jq --arg path …` against each file in `## Files to Edit` at /work Phase 0; record matches there.)

## Test Strategy

The visible symptom (refetch + flash) is **invisible to a plain jsdom/happy-dom render
assertion** — happy-dom doesn't run the compositor and presence/role assertions never
observe a remount. (Directly per
`knowledge-base/project/learnings/best-practices/2026-06-09-conditional-render-swap-does-not-animate-needs-mount-flag.md`.)
So the regression test must observe the *mount/fetch lifecycle*, not just the DOM:

1. **Mount-counter / fetch-count regression (the load-bearing test):** render the
   rail band (or the layout) expanded with a `fetch` spy on
   `/api/workspace/list-memberships`; assert the spy fired once. Toggle
   `collapsed → expanded` (re-render with the new prop, OR fire the collapse toggle
   in the layout test). Assert the fetch spy count is **unchanged** (no new fetch)
   and that the container's confirm-dialog state would survive (no remount). This is
   the invariant the fix exists to hold — assert the invariant (no refetch on
   toggle), not a proxy (DOM presence).
2. **`OrgSwitcher` collapsed mode (Phase 1):** collapsed multi → `workspace-identity-icon`
   present, `title` = org name, NO `Switch workspace` button / `▾`. Collapsed solo →
   same icon tile. Expanded forms byte-unchanged.
3. **Band collapsed suite rewrite (Phase 3):** supply membership data (stub `fetch`),
   assert `workspace-identity-icon` + `title` + monogram/logo render when collapsed,
   and `nav-section-title` still absent on top-level collapsed. Preserve testids for
   the e2e.
4. **e2e (`e2e/nav-states-shell.e2e.ts`):** existing collapsed assertions
   (`:483–514` top-level, `:556–569` drilled) already check
   `workspace-identity-icon` visible + `title="Soleur Workspace"` + monogram `"S"`
   when collapsed — keep them green. Optionally extend with a network-request count
   assertion across a collapse→expand toggle (Playwright `page.on("request")`) to
   guard the no-refetch invariant end-to-end.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Collapsing then expanding the sidebar fires **zero** additional
      `/api/workspace/list-memberships` requests (mount-counter test, Test Strategy #1).
- [ ] `OrgSwitcherContainer` is imported by **exactly**
      `components/dashboard/workspace-context-band.tsx` (`nav-single-mount.test.ts`
      green — single importer preserved).
- [ ] `WorkspaceContextBand` rail variant renders ONE subtree (no `collapsed`
      early-return). Grep: the file contains no `if (variant === "rail" && collapsed)
      … return` early-return for the band body.
- [ ] Collapsed rail still renders `data-testid="workspace-identity-icon"` with
      `title` = active workspace name and no `▾`/`Switch workspace` button
      (band + e2e green).
- [ ] Expanded rail renders the full pill with avatar + name + `▾` (multi) / static
      chip (solo) — unchanged (`org-switcher.test.tsx` green).
- [ ] `useActiveWorkspace` hook is deleted (or, if a non-layout consumer was found in
      Phase 0.4, the layout no longer calls it and the deferral is noted) — and the
      layout no longer threads `activeWorkspaceName/Id/HasLogo` into the band.
- [ ] `tsc --noEmit` clean; full vitest suite green; e2e `nav-states-shell.e2e.ts`
      collapsed/expanded assertions green.

### Post-merge (operator)

- _None._ Pure client-component change against an already-provisioned surface; the
  `web-platform-release.yml` container restart on merge to `apps/web-platform/**` is
  the deploy. (Automation: container restart is automatic on merge — no operator step.)

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-047** (`knowledge-base/engineering/architecture/decisions/ADR-047-nav-context-band-outside-swap.md`)
via `/soleur:architecture`. The current ADR already decides "the band renders outside
the swap region, never gated on `collapsed`." Add a clarifying note to §Decision 1 (or
a `## Amendment 2026-06-22` block) that the **"never gated on `collapsed`" invariant
extends to the band's INTERNAL render path** — a `collapsed` early-return that omits
`OrgSwitcherContainer` is the same unmount bug relocated one level deeper, and is
prohibited. Record that the icon-only collapsed presentation is a *mode of the mounted
container*, not a separate component swap, and that the `useActiveWorkspace`
data-duplication hook (added as a workaround for the gated-out container) is retired.
This amendment ships **in this PR**, not a follow-up issue.

### C4 views
**No C4 impact.** Read of all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`)
required at /work Phase 0 to confirm: this change introduces no new external human
actor (no new correspondent/recipient), no new external system/vendor (no new
webhook/API/store — it *removes* a duplicate call to the existing
`/api/workspace/list-memberships` edge), no new container/data-store, and no change to
an actor↔surface access relationship (the same authenticated user reads the same
membership endpoint; workspace-grain switching semantics from ADR-044 are untouched).
The `### C4 views` "None" is cited against this enumeration, not an unsupported grep.
/work MUST perform the three-file read to confirm before finalizing.

### Sequencing
The ADR amendment describes the *current* target state (already true once this PR
lands) — no soak gate, status stays `active`.

## Observability

```yaml
liveness_signal:
  what: client render of the workspace selector (no server signal added/removed)
  cadence: per page load / per sidebar toggle (client-only)
  alert_target: none (UI-only change; no new server route or background process)
  configured_in: n/a — pure client component change
error_reporting:
  destination: existing Sentry via reportSilentFallback (org-switcher-container.tsx:149) — UNCHANGED by this fix
  fail_loud: the post-RPC refreshSession failure path already mirrors to Sentry; this fix does not alter it. The membership-fetch catch stays console-only (transient/expected) per existing design.
failure_modes:
  - mode: collapsed rail shows no/stale workspace identity after the fix
    detection: e2e nav-states-shell.e2e.ts collapsed assertions (workspace-identity-icon + title) fail in CI
    alert_route: CI red on PR (pre-merge gate); no runtime alert needed (UI-only)
  - mode: collapse→expand still refetches (regression not actually fixed)
    detection: mount-counter / fetch-count unit test (Test Strategy #1) fails
    alert_route: CI red on PR
logs:
  where: browser console only (no server log lines added/removed)
  retention: n/a (client console)
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/workspace-context-band.test.tsx test/nav-single-mount.test.ts
  expected_output: all tests pass; mount-counter test confirms a single list-memberships fetch across a collapse→expand toggle
```

## Domain Review

**Domains relevant:** Product (UX correctness of the workspace selector).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline/subagent context — plan-file-path argument)
**Skipped specialists:** none — no NEW user-facing surface (this restores correct
behavior of an EXISTING control; no new page/component file under
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` is created — the
edited `layout.tsx` is modified, not created).
**Pencil available:** N/A (no new UI surface; visual states `collapsed`/`expanded`
already exist and are unchanged — only their remount behavior is fixed).

#### Findings

This is a behavioral fix to an existing control, not a new flow. The mechanical
UI-surface override (Files-to-Edit touch `components/**` + `app/**/layout.tsx`) forces
Product-relevant = true, but no NEW surface is created → ADVISORY, auto-accepted in
pipeline. The brand-survival framing (`single-user incident`, tenant-identity
ambiguity) is the load-bearing Product concern; it is covered by the
`## User-Brand Impact` section + the `user-impact-reviewer` at review-time +
CPO sign-off at plan-time.

**`wg-ui-feature-requires-pen-wireframe` / deepen-plan Phase 4.9 disposition:** the
plan touches UI-surface files but references no `.pen`, and this is correct — the gate
targets UI *features* that create a NEW surface (new page/component/layout file). This
fix creates **zero** new component/page/layout files (only edits to existing components
+ a regression test + a hook deletion). The visual states (collapsed icon tile,
expanded pill) already exist and are visually **unchanged** — only their remount
behavior is fixed. This matches the disposition of the sibling sidebar behavioral PRs
(#5630, #5539, #5075), none of which produced a new `.pen`. No wireframe is a
meaningful artifact for a remount-lifecycle fix.

## Hypotheses

- **H1 (chosen):** the band's `collapsed` early-return swaps subtrees, so React
  unmounts/remounts `OrgSwitcherContainer`, re-running its fetch. **Confirmed** by
  React reconciliation rules (different element type at same position → teardown) and
  the band code at `:83`. Fix: keep one instance mounted, toggle presentation.
- **H2 (rejected):** the fetch itself is slow / the endpoint is the problem. Rejected
  — the endpoint is fine; the issue is *re-firing* it on every toggle.
- **H3 (rejected, weaker):** add a module-scoped/SWR cache so remounts read cache.
  Rejected as the primary fix — it would soften the data flash but still unmount the
  container, losing the in-flight switch-confirm dialog (`pending`/`status`) and still
  firing mount/cleanup effects + focus loss. Pattern 2a (keep mounted) is strictly
  stronger. (A cache could be a separate future cleanup but is out of scope.)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (This plan's section is filled; threshold = single-user incident.)
- **Both toggle states must be verified** (`2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`):
  the fix changes how `OrgSwitcherContainer` renders in BOTH collapsed and expanded —
  assert the selector in BOTH states (not just the collapsed state the bug names).
  Expanded must keep the full pill + `▾`; collapsed must keep the icon tile + tooltip.
- **Unit tests can't see the remount** — happy-dom runs no compositor and presence
  assertions don't observe lifecycle. The load-bearing regression test MUST be a
  mount-counter / fetch-count assertion across a toggle, not a DOM-presence check
  (`2026-06-09-conditional-render-swap-does-not-animate-needs-mount-flag.md`).
- **The mobile band still mounts its own `OrgSwitcherContainer`** (CSS-hidden on
  desktop, `layout.tsx:282`). After this fix there are still two instances on desktop
  (visible rail + hidden mobile), each with an independent fetch. This fix does NOT
  collapse that duplication (out of scope) — but it is the same `single-mount`-by-import
  invariant, so `nav-single-mount.test.ts` stays green. If a future plan wants a true
  single fetch, lift `memberships` into a shared provider; note as a candidate
  cleanup, do not fold in here.
- **`key` cannot rescue an absent element** — the collapsed branch simply omits the
  container, so no `key` preserves it. The only fix is structural (keep it rendered).

## Deferred / Tracking

- (Candidate, not deferred-with-issue yet) De-duplicate the rail vs mobile
  `OrgSwitcherContainer` fetches by lifting `memberships` into a shared provider. Out
  of scope for this fix. If `/work` or review wants it tracked, file an issue with
  re-evaluation criteria ("revisit when the two-instance fetch shows in profiling /
  rate-limit telemetry"). Recorded here so the deferral is not invisible.
