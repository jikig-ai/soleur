---
title: Single Nav Rail — Drill-In Replacement with Persistent Workspace Context
type: feat
feature: feat-single-nav-rail
date: 2026-06-02
status: ready
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 4813
pr: 4810
brainstorm: knowledge-base/project/brainstorms/2026-06-02-single-nav-rail-brainstorm.md
spec: knowledge-base/project/specs/feat-single-nav-rail/spec.md
wireframes: knowledge-base/product/design/navigation/single-nav-rail.pen
---

# Plan: Single Nav Rail — Drill-In Replacement

## Overview

Collapse the web app's two side-by-side rails into **one rail**. A section's secondary nav
(KB file tree / Settings sub-nav / Chat conversations rail) **replaces** the primary nav in
the same rail, driven by the URL segment, with a back chevron returning to main nav. A slim
**persistent context band** — `[‹ back · workspace avatar/name · "Working on: repo" · section]`
— stays pinned in every drill state and is mounted **outside** the swap region in the
always-mounted `(dashboard)/layout.tsx`. Scope: KB, Settings, Chat. Approach A from the
brainstorm; CPO/CTO/CLO assessed; wireframes at `knowledge-base/product/design/navigation/`.

This supersedes the collapse-in-place model (#2342, shipped) and fixes an existing latent
bug: `OrgSwitcherContainer` + `LiveRepoBadge` currently *unmount* when the rail is collapsed
(`layout.tsx:281,286-290`, gated on `!collapsed`), so a wrong-workspace action is already
possible today.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality (verified) | Plan response |
|---|---|---|
| `use-kb-layout-state` under `components/kb/` | It's under `apps/web-platform/hooks/use-kb-layout-state.tsx` | Use the `hooks/` path throughout. |
| "3 ⌘B handlers" | **4** owners: `layout.tsx:157-179`, `settings-shell.tsx:41-53`, `use-kb-layout-state.tsx:165-177`, AND `components/chat/conversations-rail.tsx:95` | Consolidate all four. |
| KB collapse uses `useSidebarCollapse` | KB collapse is **in-memory `useState`** (`use-kb-layout-state.tsx:56`), NOT localStorage; only main + settings use the hook | Reconcile persistence in Phase 4. |
| Drill state is novel | `isContentView = pathname !== "/dashboard/kb"` (`use-kb-layout-state.tsx:179`) already URL-derives a drill on mobile; `kb-mobile-layout.tsx:40-61` is the proven single-column analog | Generalize the existing pattern, don't invent. |
| Context band fixes a regression | Confirmed: switcher/badge unmount on collapse (`layout.tsx:281,286-290`) — band fixes a *live* bug, not just a future one | Frame as a fix. |

## User-Brand Impact

**If this lands broken, the user experiences:** a nav rail where the active workspace is
ambiguous or hidden, so they invite a member / share an API key / edit Scope Grants against
the **wrong workspace**; or they get stranded in a drilled state with no visible way back.

**If this leaks, the user's data/workflow is exposed via:** cross-tenant action — a
mutation (membership, API-key share, scope grant) applied to the wrong workspace because the
context band failed to keep workspace identity unambiguous.

**Brand-survival threshold:** single-user incident. `requires_cpo_signoff: true` (carried
from brainstorm). `user-impact-reviewer` runs at PR review. The two load-bearing invariants:
(1) workspace identity is visible in EVERY drill state on EVERY breakpoint; (2) a workspace
switch never silently lands the user on a tenant-sensitive pane for the new tenant.

## Resolved Open Questions (from spec-flow P0/P1 gaps + brainstorm OQs)

- **RQ1 — Mobile workspace identity (P0-1).** The context band renders in the **mobile top
  bar** (replacing the bare "Soleur" label, `layout.tsx:207`), so workspace identity shows in
  every mobile state, outside the hamburger drawer. Hard requirement — closes the FR3 breach
  on mobile.
- **RQ2 — Workspace switch landing (P0-3, brand-critical) [revised post-review].** Replace
  `window.location.reload()` (`org-switcher-container.tsx:94`) with a **hard navigation**
  `window.location.assign("/dashboard")` — NOT a soft `router.push`. Rationale: the existing
  `reload()` is load-bearing for *correctness*, not just landing — its in-file comment (lines
  13-16) states it forces server components to re-render against the new workspace's freshly-
  minted JWT (`refreshSession()` at :77). A soft `router.push("/dashboard")` serves cached RSC
  → the user lands on the neutral route but sees **stale prior-tenant server-rendered data**
  (spec-flow + Kieran + architecture-strategist all flagged this). A hard `assign` gives BOTH
  the neutral landing AND the full RSC re-render. `executeSwitch` is shared by confirm AND the
  failure→Retry path (`:133`) — both are covered by the one change; the test must assert both.
  Single most consequential change — CPO sign-off required.
- **RQ3 — Switcher reachable while drilled (P0-2).** The band's workspace chip is the switcher
  trigger in every drill state (tapping workspace name opens the existing switcher). This is
  distinct from a section-switcher — NG3 (no sibling-section switcher) stands.
- **RQ4 — Position resume (P1-1, P1-2) [CUT to follow-up per plan-review].** NOT in this PR.
  DHH + code-simplicity both flagged it as the highest-complexity / lowest-invariant-value item
  on a brand-critical PR, and it lightly fights the "key-by-segment to avoid stale context" rule
  (Phase 2). Accepted behavior: section re-entry lands at the section root; the KB **file** is
  already preserved by the URL (`use-kb-layout-state.tsx:137-158` auto-expands ancestors from the
  pathname). Sticky last-item/scroll resume → follow-up issue **#4826**.
- **RQ5 — Empty states (P0-4, P1-5).** Always drill (never a blank rail). Conversations rail
  empty → in-rail "No conversations yet — Start one →" CTA. KB empty → in-rail
  "Connect a repo / add docs" CTA. Back chevron always labeled "Back to menu".
- **RQ6 — Back-chevron target (P1-3, P2-1) [route corrected post-review].** Desktop: back from
  any drilled section → `/dashboard` (tree/file depth within KB is content, not a rail drill).
  Back chevron **hidden** on NON-drilled routes, slot width reserved (no layout shift). NOTE:
  Analytics lives at **`/dashboard/admin/analytics`** (Kieran P0-1 — there is NO `/analytics`
  route; `layout.tsx:98` is admin-gated `/dashboard/admin/analytics`). Therefore the
  drill set is an explicit **allowlist** (`kb` | `settings` | `chat`), NOT a denylist of top-
  level routes — otherwise `/dashboard/admin/analytics` (deeper than the drill sections) would
  wrongly render a back chevron, and future `/dashboard/admin/*` routes would inherit it. Mobile:
  existing `isContentView` handles file→tree; band back → main nav.
- **RQ7 — Solo-user band (TR6 / brainstorm OQ1).** Band always shows workspace name + repo
  (orientation value; wireframe frame 5). For solo users (`memberships.length <= 1`) the chip
  is display-only (no switcher dropdown — nothing to switch to). The band's identity display
  is a **distinct concern** from the interactive `OrgSwitcherContainer` self-hide.
- **RQ8 — Drill-level helper [reframed post-review].** A single plain exported **pure function**
  `segmentToDrillLevel(pathname): DrillLevel` (a typed union over the allowlist `kb|settings|chat`
  + top-level) — NOT a `use-`-prefixed hook (no state/effects), NOT a "#2343 manifest seed"
  (YAGNI; drop the speculative shaping). It MUST become the **sole authority** for "is this route
  drilled": route every existing `pathname.startsWith("/dashboard/(kb|settings|chat)")` literal
  (`layout.tsx:141,169-172,297`; `use-kb-layout-state.tsx:179`; `settings-shell.tsx`) through it,
  so it consolidates today's scattered checks rather than adding a parallel one. When #2343 lands
  it can promote this function; no pre-built manifest now.
- **RQ9 — LiveRepoBadge relocation (brainstorm OQ2).** Verified poll-based (`fetch` on mount +
  `window` focus, `live-repo-badge.tsx:30-48`), no Realtime channel → survives relocation into
  the band with no subscription-lifecycle risk.

## Implementation Phases (TDD — failing tests first per cq-write-failing-tests-before)

Collapsed 8 → 4 per plan-review (DHH P1-1): phases are NOT independent merge boundaries (atomic
single-PR), so they group by coherent unit. Tests written *with* each change; order is
dependency-directed (contract before consumer).

**Phase 0 (pre-flight note):** Node ≥ 22.9.0 ✓ (v22.22.1), Pencil ✓ (wireframes done). Re-grep the
4 ⌘B owners + `!collapsed` gate + the 3 localStorage keys before editing. Runner = **vitest**
(`./node_modules/.bin/vitest run <path>`; `bunfig.toml` ignores bun test).

### Phase A — Brand-safety payload: context band + single ⌘B owner + safe switch
The whole brand-survival payload; coupled (band hosts the switcher chip, the switch behavior, the
single-rail ⌘B owner).
- **Context band ⚠️ render OUTSIDE `children`.** New `components/dashboard/workspace-context-band.tsx`
  mounted directly in `(dashboard)/layout.tsx` above the swap region, never gated on `collapsed`
  (learning `ui-bugs/2026-04-10-kb-nav-tree-disappears-on-file-select` — `children` swaps on every
  nav). The band **relocates** existing components: imports `OrgSwitcherContainer` (interactive chip,
  RQ3; RQ7 one-render-path) + `LiveRepoBadge` (poll-safe, RQ9). ONLY net-new render code = back
  chevron + section-title label + layout shell. Do NOT reimplement identity/solo/poll logic.
- **Single-mount enforcement (THE structural rule, architecture-strategist P0-A).** After this change
  `OrgSwitcherContainer` + `LiveRepoBadge` render in **exactly one module** (the band). RED: identity
  is in the DOM on a **drilled** route (`/dashboard/settings/members`, rail in secondary-nav state) +
  a grep/import test that no other module renders them (learning
  `best-practices/2026-04-29-duplicate-component-mount-across-layouts`).
- **Safe switch (RQ2, contract-before-consumer).** `org-switcher-container.tsx:94`
  `window.location.reload()` → `window.location.assign("/dashboard")` (hard nav: neutral landing +
  RSC re-render under new JWT — NOT soft `router.push`). Update `org-switcher-container.test.tsx`
  confirm AND retry paths (`reloadMock` at :93/:118).
- **Single ⌘B owner.** Remove the 4 per-route guards (`layout.tsx:157-179`, `settings-shell.tsx:41-53`,
  `use-kb-layout-state.tsx:165-177`, `conversations-rail.tsx:91-95`); one handler. RED: jsdom assertion
  that exactly one keydown handler calls a toggle (architecture P2-A) + a Playwright assertion across
  KB/Settings/Chat.

### Phase B — URL-derived drill + lift the three secondary navs
- **Drill helper (RQ8).** Pure `segmentToDrillLevel(pathname)` (typed allowlist `kb|settings|chat`);
  route ALL existing `startsWith` literals through it (`layout.tsx:141,169-172,297`,
  `use-kb-layout-state.tsx:179`, `settings-shell.tsx`). RED: main nav on `/dashboard` AND
  `/dashboard/admin/analytics`; secondary slot on the 3 drill segments; back hidden on non-drill
  routes; stable module-level nav-hook mocks (learning
  `test-failures/2026-04-07-userouter-mock-instability-causes-useeffect-refire`). Reuse the
  `translate-x` slide (`layout.tsx:238-239`) + `ChevronLeftIcon`.
- **Lift secondary navs into the swap slot**, keyed by segment so each re-inits on section change
  (learning `2026-04-17-kb-chat-stale-context-on-doc-switch`). **Explicitly DELETE the
  `chat/layout.tsx:67-72` `<aside data-testid="conversations-rail">`** in the same change (only the
  aside moves; the async delegation-banner resolution STAYS) — else double-mount (architecture P0-C).
  Regression: exactly one `conversations-rail` node on `/dashboard/chat` at md+. Strip redundant
  `mx-auto max-w-*`/`px/py` from lifted child pages (learning
  `best-practices/nextjs-lift-shared-shell-to-route-group-layout-20260415` double-wrap); ref-guard any
  relocated reset effect (learning `ui-bugs/2026-04-16-react-effect-ordering-on-component-extraction`).
- **Collapse-key unification (Kieran P1-2).** 3 localStorage keys exist (main, settings, chat:
  `soleur:sidebar.chat-rail.collapsed`) + KB ephemeral. The unified rail uses **one** key + a one-time
  cleanup removing the 3 orphans. KB stays ephemeral by default — documented, NOT migrated (DHH P0-2).

### Phase C — Empty states, mobile band, wrong-workspace instrumentation
- Generic labeled empty-state CTA for empty Conversations + empty KB rails (RQ5) — never a blank rail.
- Mobile top-bar context band (RQ1) replacing the static "Soleur" `<span>` (`layout.tsx:216-218`); ONE
  band component via a `variant` prop (no third identity copy, architecture P2-B).
- **AC11 instrumentation (pulled into PR per operator decision):** emit workspace-context-at-action-
  time on invite / API-key-share / scope-grant so a wrong-workspace action is detectable. Detector
  ships with the prevention.

### Phase D — ADR + test rework
- ADR-**047** "Workspace context band + switcher render outside the rail swap region"; cite **AP-011**
  (architecture P1-C).
- Test rework across the verified file list (below). Write tests plainly; extract a shared nav-hook
  mock helper ONLY if the shape repeats ≥5× (DHH P2-1 — do not pre-build the factory). **Never assert
  jsdom layout values** — width/alignment → Playwright or `data-*` (learning
  `best-practices/2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps`); assert collapse
  alignment + presence in **both** rail states (learning
  `2026-04-17-alignment-fixes-must-verify-both-toggle-states`); `WEBPLAT_TEST_USE_FORKS=1` to triage
  kb-chat-sidebar flakes (learning `test-failures/2026-05-15-kb-chat-sidebar-chat-page-flake-recurrence`).

## Files to Edit

- `apps/web-platform/app/(dashboard)/layout.tsx` — rail container, drill swap, band mount, ⌘B, mobile top bar.
- `apps/web-platform/components/dashboard/org-switcher-container.tsx` — switch lands on `/dashboard` (RQ2); expose switcher to band chip.
- `apps/web-platform/components/dashboard/live-repo-badge.tsx` — relocate into band (poll-based, safe).
- `apps/web-platform/components/settings/settings-shell.tsx` — sub-nav into swap slot; remove own ⌘B; strip redundant layout classes.
- `apps/web-platform/components/kb/kb-sidebar-shell.tsx`, `kb-desktop-layout.tsx`, `kb-mobile-layout.tsx` — tree into swap slot.
- `apps/web-platform/hooks/use-kb-layout-state.tsx` — remove own ⌘B; reconcile collapse persistence.
- `apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` — **DELETE the `conversations-rail` `<aside>` (`:67-72`)** (only the aside; KEEP the async delegation-banner resolution); rail moves to swap slot.
- `apps/web-platform/components/chat/conversations-rail.tsx` — remove own ⌘B (`:91-95`); rail into swap slot; empty state.
- `apps/web-platform/hooks/use-sidebar-collapse.ts` — unified-rail key + one-time orphan-key cleanup (3 keys).
- **~17 test files (verified list, re-grep before RED per Kieran P1-1):** `dashboard-layout-{drawer-rail,sidebar-settings,signout,banner}.test.tsx`, `dashboard-sidebar-collapse.test.tsx`, `use-sidebar-collapse.test.tsx`, `settings-sidebar-collapse.test.tsx`, `kb-sidebar-{collapse,transition}.test.tsx`, `kb-layout-panels.test.tsx`, `kb-layout-chat-close-on-switch.test.tsx`, `kb-chat-sidebar-a11y.test.tsx` (added), `conversations-rail.test.tsx`, `org-switcher-container.test.tsx`, `org-switcher.test.tsx` (added), `live-repo-badge.test.tsx`.

## Files to Create

- `apps/web-platform/components/dashboard/workspace-context-band.tsx`
- `apps/web-platform/hooks/segment-to-drill-level.ts` (pure function, NOT a hook — RQ8)
- `apps/web-platform/test/workspace-context-band.test.tsx`
- `apps/web-platform/test/nav-rail-drill.test.tsx`
- `knowledge-base/engineering/architecture/decisions/ADR-047-nav-context-band-outside-swap.md`

## Acceptance Criteria

### Pre-merge (PR)
- AC1. Workspace identity (name + repo) is present in the DOM on `/dashboard`, `/dashboard/kb`,
  `/dashboard/settings/members`, `/dashboard/chat`, AND in the mobile top bar — asserted via
  `data-testid`, not layout measurement. (Brand invariant 1.)
- AC2. `org-switcher-container.test.tsx` (confirm AND retry paths): switch calls
  `window.location.assign("/dashboard")` — a **hard navigation** (asserts the neutral landing AND
  the RSC-re-render mechanism, NOT a soft `router.push`). No path lands on a tenant-sensitive pane
  for the new workspace. (Brand invariant 2.)
- AC3. Back chevron renders synchronously (present in first render, not async-gated) and is hidden
  on non-drill routes (`/dashboard`, `/dashboard/admin/analytics`); navigates to `/dashboard` on
  click from a drilled section. `segmentToDrillLevel` is a typed **allowlist** (`kb|settings|chat`).
- AC4. The context band is rendered directly in `layout.tsx`, never through `children`; a
  regression test asserts it does not double-mount on segment routes.
- **AC4b (single-mount — THE structural rule).** `OrgSwitcherContainer` + `LiveRepoBadge` are
  imported/rendered in exactly one module (`workspace-context-band.tsx`); a grep/import test asserts
  zero other render sites; and workspace identity is present in the DOM on a **drilled** route
  (`/dashboard/settings/members` with the rail in secondary-nav state), not only at `/dashboard`.
- **AC4c (drill-authority).** No `pathname.startsWith("/dashboard/(kb|settings|chat)")` literal
  survives outside `segmentToDrillLevel` (grep test) — the helper is the sole route-truth source.
- **AC4d (no chat double-mount).** `data-testid="conversations-rail"` resolves to exactly one node
  on `/dashboard/chat` at md+ (the `chat/layout.tsx` aside is deleted, not duplicated).
- AC5. Exactly one ⌘B handler toggles exactly one rail across KB/Settings/Chat (Playwright + a
  jsdom assertion that only one keydown handler calls a toggle).
- AC6. Empty Conversations rail and empty KB rail render a labeled CTA, not a blank rail.
- AC7. `./node_modules/.bin/vitest run` green across the ~15 reworked files; no test asserts a jsdom
  layout value; nav-hook mocks use stable refs; collapse alignment asserted in both states.
- AC8. `tsc --noEmit` clean (enumerate any exhaustiveness rails via the compiler, not a count).
- AC9. Wireframes referenced in spec FRs (`knowledge-base/product/design/navigation/*`).

- **AC11 (pulled into PR per operator decision).** Wrong-workspace action-time instrumentation
  emits workspace-context on invite / API-key-share / scope-grant (spec AC1) — the detector ships
  WITH the prevention, not after. Pre-merge.

### Post-merge (operator)
- AC10. Playwright/agent-browser walkthrough of the 4 rail states + a workspace switch from a
  Settings pane confirming the `/dashboard` hard-nav landing renders the NEW tenant's data (not
  stale). *Automation: feasible via `mcp__playwright__*` — run in `/soleur:qa` before merge if dev
  env is seeded; otherwise post-merge smoke.*

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO) — carried forward from brainstorm.

### Engineering (CTO)
**Status:** reviewed (brainstorm carry-forward). **Assessment:** URL-derived drill (shape B); switcher
mounts in always-mounted route-group layout above the swap region (load-bearing); reuse `translate-x`
slide; ~15 test files; most-likely failure = switcher rides inside the swapped body and vanishes →
prevented by the Phase-1 "render outside swap region" rule + AC4.

### Legal (CLO)
**Status:** reviewed (brainstorm carry-forward). **Assessment:** low legal surface; GDPR
deletion/export stay reachable behind Settings drill-in (Art. 12(2)/17/20 require accessible, not
N-click); only ask = active-workspace identity unambiguous on Members/Scope-Grants/Integrations —
satisfied by the band + RQ2.

### Product/UX Gate
**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo (carry-forward), ux-design-lead
**Skipped specialists:** none
**Pencil available:** yes

#### Findings
spec-flow-analyzer surfaced 4 P0 + 5 P1 journey gaps; P0s resolved in RQ1/RQ2/RQ3/RQ5 (mobile band,
hard-nav switch-landing, switcher reachability, empty Chat-nav); RQ4 position-resume CUT to a
follow-up. ux-design-lead produced `knowledge-base/product/design/navigation/single-nav-rail.pen` +
5 screenshots; frame 3 makes the wrong-workspace circuit breaker concrete (Members + "Inviting into
→ workspace" callout). **CPO plan-time sign-off: CLEARED (2026-06-02) with 3 conditions** — all
already in the plan: (1) AC10 must include a "switch mid-task, then resume" task so the
always-discard-section-context trade is *measured*; (2) solo-user band chip renders a visibly
non-interactive state (`memberships<=1`); (3) empty-state CTAs (AC6) stay pre-merge. CPO explicitly
REJECTED the v1 mitigations of returning-to-section-root (re-introduces stale-tenant risk) and a
switch toast (redundant with the persistent band). Cleared for /work.

**5-agent plan-review applied (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow):**
cut RQ4 + the KB→localStorage migration; reframed `segmentToDrillLevel` as a pure sole-authority
function; corrected the `/analytics` → `/dashboard/admin/analytics` route bug (Kieran P0-1); changed
the switch fix to a **hard nav** to preserve RSC re-render (spec-flow/Kieran/architecture P0); added
single-mount AC4b + chat-aside-delete AC4d; pulled AC11 instrumentation pre-merge. **Note:**
architecture-strategist's P0-B ("7 cited learnings absent") was a verified **false negative** — all
7 files exist (confirmed by path); citations retained.

## Observability

```yaml
liveness_signal:    { what: "n/a — client-only nav refactor, no new runtime/cron", cadence: n/a, alert_target: n/a, configured_in: n/a }
error_reporting:    { destination: "existing Sentry (client)", fail_loud: "workspace-switch failure already surfaces Retry/Cancel (org-switcher-container.tsx:123)" }
failure_modes:
  - { mode: "switch lands on wrong-tenant pane", detection: "AC2 unit test + AC11 action-time instrumentation", alert_route: "Sentry breadcrumb on switch" }
  - { mode: "context band fails to render workspace identity", detection: "AC1 DOM test across routes + breakpoints", alert_route: "n/a (caught pre-merge)" }
logs:               { where: "browser console / Sentry client events", retention: "per existing Sentry config" }
discoverability_test: { command: "./node_modules/.bin/vitest run apps/web-platform/test/workspace-context-band.test.tsx apps/web-platform/test/org-switcher-container.test.tsx", expected_output: "all green; switch asserts /dashboard landing" }
```

## Risks & Sharp Edges
- **App Router `children` trap:** persistent band MUST render directly in `layout.tsx`, never via
  `children` (the swap on every navigation is the 2026-04-10 KB-tree-disappears bug).
- **Double-mount:** any rail hook in both the always-mounted layout and a segment layout mounts
  twice; gate non-owner on UI state AND `pathname.startsWith(...)`; AC4 regression test.
- **Double-wrap:** stripping shell `max-w/px/py` from child pages is part of the same atomic lift.
- **jsdom layout assertions** silently no-op — width/alignment checks go to Playwright.
- **Switch fix must be a HARD nav** (`window.location.assign("/dashboard")`), NOT `router.push` —
  the `reload()` it replaces is load-bearing for the RSC re-render under the new JWT
  (`org-switcher-container.tsx:13-16`). A soft nav lands on the neutral route showing **stale
  prior-tenant data** — the very wrong-workspace failure this PR exists to kill. Highest-impact
  change; CPO sign-off.
- **Accepted orientation cost (spec-flow):** a workspace switch always discards section context
  (lands on `/dashboard`), even from a non-sensitive section like KB reading. This is deliberate
  (safety over convenience); CPO's AC3 moderated test MUST include a "switch mid-task, then resume"
  task so the trade is measured, not assumed.
- **Solo-user band chip (RQ7):** must render a clearly non-interactive state (no tap target / no
  hover affordance) so a solo user doesn't tap the workspace name expecting a dropdown that never
  comes — one render path, affordance gated on `memberships.length > 1` (not two components).
- **Chat active-nav quirk (Kieran P1-3):** `/dashboard/chat` highlights the *Dashboard* nav item
  (`layout.tsx:297`) while drilled into Chat; back targets `/dashboard` (already "active"). Confirm
  this round-trip reads correctly against wireframe frame 4 at /work time.
- A plan whose `## User-Brand Impact` is empty/`TBD` fails deepen-plan Phase 4.6 — this one is filled.

## Open Code-Review Overlap
Checked 73 open `code-review` issues against the Files-to-Edit list. 5 reference touched files:
- **#2194 — refactor(dashboard): decompose DashboardLayout into hooks and subcomponents.**
  **Disposition: Acknowledge (partial fold).** This PR extracts `WorkspaceContextBand` + the
  drill-state helper out of `layout.tsx` (a concrete step toward the decomposition #2194 wants)
  but does NOT complete the full hook/subcomponent breakout — that stays open. Note progress on
  #2194; do not `Closes`.
- **#4525 — code-review: PR #4518 resolveCurrentOrganizationId migration (conversations-rail).**
  **Disposition: Acknowledge.** Different concern (org-id resolution). The implementer moving
  `conversations-rail` into the swap slot must rebase-aware so the two edits don't collide; no
  scope fold.
- **#3564 (Core Web Vitals infra), #2197 (SubscriptionStatus type / Sentry UUID), #2193 (banner
  unify + useDismissiblePersistent).** **Disposition: Acknowledge.** All touch `layout.tsx` for
  unrelated concerns (perf infra / billing banners); not folded.
