---
date: 2026-06-04
type: feat
title: KB Workspace Chrome / Nav Redesign (D4 borderless + workspace logo monogram)
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 4915
deferred: [4916, 4917]
branch: feat-kb-mobile-ux-redesign
worktree: .worktrees/feat-kb-mobile-ux-redesign
pr: 4911
brainstorm: knowledge-base/project/brainstorms/2026-06-04-kb-chrome-nav-redesign-brainstorm.md
spec: knowledge-base/project/specs/feat-kb-mobile-ux-redesign/spec.md
wireframes: knowledge-base/product/design/navigation/kb-mobile-nav-redesign-wireframes.pen
---

# ✨ Plan: KB Workspace Chrome / Nav Redesign

## Overview

Restyle the dashboard workspace chrome (header + workspace switcher + back navigation) wrapping the
Knowledge Base screen, mobile + desktop, to the **D4 "borderless elevation polish"** direction with a
**workspace logo (monogram fallback now, upload deferred #4916)** and the **global "Soleur" wordmark
removed**. Design is settled and committed as styled `.pen` wireframes; this plan implements them.

Purely chrome/visual + presentational work. The workspace-switch state machine (`set_current_workspace_id`
RPC + `refreshSession()` + hard `window.location.assign`) is **not touched** (ADR-044/047 load-bearing;
its latent switch-failure bug is tracked separately as #4917).

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "Redesign chromes the KB landing (2 screens: S1 content, S2 empty)" | KB landing is ~9 states; `kb/layout.tsx` `fullWidth` branch (loading / workspace-not-ready / no-project / unknown-error / reconnect) renders **chromeless** — no identity/title/back on mobile body | **Expand scope**: chrome ALL KB states; identity must persist (P0-1, brand-survival). Phase 4. |
| "One back affordance per state" | Two backs **co-render** on mobile doc view: band "Back to menu" (→/dashboard) + `kb-content-header` "Back to file tree" (→/dashboard/kb) | Define a back-state table; suppress band back in doc view. Phase 3 (P1-1). |
| "single back chevron" (FR1 redline) | Band uses a long-arrow glyph + "Back to menu" **label** (deliberate, #4810); chevron-only loses the destination cue | Keep an accessible name/label; reconcile redline. Phase 3 (P1-2). |
| Gold swatch → logo (one site) | Gold swatch at **4 sites**: `org-switcher.tsx:87/118/160` + `workspace-context-band.tsx:95` | Replace all 4 with the monogram tile. Phase 1. |
| "logo-only collapsed rail" + "monogram fallback" | With upload deferred, **100% of workspaces are monograms** → logo-only-collapsed on a monogram is a hybrid-rule contradiction; two workspaces sharing an initial are indistinguishable | Collapsed-rail exception: full-name **tooltip** (authoritative disambiguator). Name-hashed tint **dropped** (YAGNI — single-user, upload-deferred; tint over a finite palette has collisions anyway). Phase 1/4 (P0-3). |
| "chrome the KB landing" | The identity band is mounted in **`(dashboard)/layout.tsx`** (`:236` mobile, `:335` rail) — **above** the KB swap; it already persists across all fullWidth sub-states (ADR-047 render-outside-swap). What's missing is the mobile **page-body** title+back, not identity | Phase 4 adds page-body title+back to the fullWidth branch — **do NOT re-mount the identity band inside `kb/layout.tsx`** (would double-mount, inverting ADR-047). |
| collapsed band can monogram the workspace | Collapsed band (`workspace-context-band.tsx:73-116`) renders a **nameless** swatch — it does NOT mount the data-bearing container and has no workspace name in scope | Thread the active workspace `name` into the collapsed band as a prop (unstated data-flow dependency). |
| "workspace logo_url field" | **Does not exist** (no migration); identity is the swatch only | Monogram-only now; tile models `leader-avatar.tsx` img-error fallback shape for when the field lands (#4916). |
| n/a | Single-mount guard `nav-single-mount.test.ts` is a **source-text import guard** (OrgSwitcherContainer/LiveRepoBadge importable only by the band) | New monogram tile is **pure presentational** (takes `name`), imports neither. |
| n/a | **jsdom/vitest is blind to CSS layout** — PR #4810 shipped 2 layout bugs through 8166 green tests; ADR-049 headless Playwright `nav-states` gate is the only catch | Phase 5 is RED→GREEN on the ADR-049 gate; wire into `/work` Phase 4, not just one-shot qa. |

## Implementation Phases

### Phase 0 — Preconditions (verify, don't code)
- Confirm the 4 swatch sites, wordmark site, 3 back-affordance sites, and named tests exist (done in research).
- Run the ADR-049 `nav-states-shell.e2e.ts` gate on the current branch to capture a **green baseline** before edits.
- Read `leader-avatar.tsx` (size-map + img-error fallback) as the tile model.

### Phase 1 — Workspace identity monogram tile
- **Create** `components/dashboard/workspace-identity-tile.tsx`: pure presentational, props `{ name, size }` (NO speculative `variant` prop — add only when a 2nd variant exists). Renders a rounded-square monogram (first 1–2 chars of `name`, uppercased) on a **single fixed non-gold surface token** (e.g. `bg-soleur-bg-surface-2`; NOT `bg-soleur-accent-gold-fg/60`; FR6). No name-hashed tint (dropped — see reconciliation). No `img`/URL branch yet — leave a TODO + shape comment modeled on `leader-avatar.tsx`'s img-error fallback for #4916. Tokens only.
- **Replace** the 4 swatch sites (`org-switcher.tsx:87,118,160`, `workspace-context-band.tsx:95`) with the tile. **Note:** `org-switcher.tsx:160` is a **conditional fill** (gold if current row, `bg-soleur-bg-surface-2` if not) — preserve the current/non-current visual distinction in the dropdown; do not flatten both rows.
- The collapsed-rail site (`workspace-context-band.tsx:95`) needs a **`name` source** the collapsed band lacks today — thread the active workspace name into the collapsed band as a prop. Replace its static `title="Active workspace"` (`:94`) with the **full workspace name** (authoritative disambiguator for shared-initial monograms; P0-3).
- Imports neither `OrgSwitcherContainer` nor `LiveRepoBadge` (keep `nav-single-mount.test.ts` green). Runtime single-display rests on CSS exclusivity (`md:hidden` vs `hidden md:block`) + `use-active-repo` fetch coalescing — a future switch to a JS viewport gate would be the real double-mount hazard the import guard cannot catch.

### Phase 2 — Borderless de-box + wordmark removal + solo/multi affordance
- De-box: remove `border`/`border-b`/divider classes from the switcher trigger (`org-switcher.tsx:114,139,154`), the **outer container wrapper only** (`org-switcher-container.tsx:132`), and the band shell (`workspace-context-band.tsx:79,169`); convey grouping via `bg-soleur-bg-surface-1` elevation. **Do NOT touch** the confirm `role="dialog"` border (`org-switcher-container.tsx:144`) or any button handler (`:154-167,187-201`) — those belong to the switch state machine (#4917). **Retain** the confirm/retry button gold (`:157,190`) — that is the sanctioned single-primary-action gold use, not chrome to de-emphasize. **Preserve** the tested width-clamp classes (`w-full min-w-0` on trigger + chip, `shrink-0` on caret — `nav-chevron-alignment.test.tsx:106-121`) and **padding ownership** (`org-switcher-container.tsx:132` stays horizontal-padding-free; band owns `px-3` — #4810 Bug 1).
- Solo vs multi affordance under borderless (P1-3): multi-org keeps the `▾` caret + pressable surface; solo renders visibly flat (no caret, no hover-press). Keep `workspace-identity-static` testid/text structure (`org-switcher.test.tsx`).
- Remove the "Soleur" wordmark (`app/(dashboard)/layout.tsx:288-292`): delete the `<span>` only; keep the flex row + sibling close/collapse buttons. Stays render-conditional (`drill === null`) — NOT CSS-hide (jsdom asserts absence).
- Update wordmark tests: `nav-rail-drill.test.tsx:94` (was "present top-level") and `:133` (absent drilled); `nav-states-shell.e2e.ts:369/391/479` (drop/repoint the wordmark visible+absent assertions). Do **not** touch `"Soleur Workspace"` org-name assertions (different string).
- Gold reserved for active-workspace identity + single primary action only.

### Phase 3 — Suppress duplicate back in doc view (one back per state)
Today two backs co-render on the mobile KB doc view: the band "Back to menu" (→/dashboard) and `kb-content-header`'s "Back to file tree" (→/dashboard/kb). The fix is to **suppress the band back in doc view** — but the band derives state from `segmentToDrillLevel(pathname)`, which **deliberately collapses KB landing and doc view into the same `"kb"` level** and is the **sole** drill authority (ADR-047 AC4c — a parallel `pathname.startsWith`/`includes` check inside the band is a grep-enforced regression).
- **ADR-clean mechanism (pick one, do NOT add a parallel pathname check in the band):** (a) pass an explicit `suppressBack` prop from `(dashboard)/layout.tsx` (which already owns `pathname` + composes the band), OR (b) suppress at the **mobile-band placement only** — the doc-view double-back is mobile-only (`kb-content-header` back is `md:hidden`; the rail band is desktop-only). Default to (b) if it fully removes the co-render; else (a).
- The "shared slot / unify the primitive" (TR3) is a **conceptual invariant** (exactly one back reachable per state), **NOT** a literal shared React component — `kb-content-header`'s back and the band's back stay separate render sites with distinct glyphs/destinations (do not make `kb-content-header` import band concerns).
- Keep the band back glyph distinct from the layout collapse chevron `M15.75 19.5 8.25 12l7.5-7.5` (`nav-chevron-alignment.test.tsx:83/92`, `nav-states-shell.e2e.ts:426-439`).
- Add a test asserting **exactly one** back control per state (the load-bearing regression guard).

### Phase 4 — Page-body chrome for fullWidth states + title ownership
- **The identity band already persists above the KB swap** (mounted in `(dashboard)/layout.tsx:236/335`, ADR-047 render-outside-swap) — do **NOT** re-mount identity inside `kb/layout.tsx` (would double-mount, inverting ADR-047). The `fullWidth` branch (`kb/layout.tsx:49`) is a **single** wrapper swapping only the body (loading / workspace-not-ready / no-project / unknown-error / empty) — one wrapper edit, not five.
- What's missing is the mobile **page-body** "Knowledge Base" title + back affordance in the fullWidth branch (mobile body has neither today). Add page-level chrome (title + mobile back) to the single fullWidth wrapper so every sub-state shows it (P0-1).
- Title ownership per breakpoint (P2-4): exactly one "Knowledge Base" title visible on mobile (page body) — ensure the band section-title row doesn't double-render it on mobile.

### Phase 5 — Visual regression gate + test reconciliation
- Extend/author the ADR-049 `nav-states-shell.e2e.ts` gate: mock the app API routes the band depends on (`/api/workspace/active-repo`, `/api/workspace/list-memberships` — NOT Supabase REST), assert **content testids** + `scrollWidth - clientWidth <= 1` at `md:w-56` and `md:w-14`, identity present in every drill state, monogram (not gold) in collapsed. Prove RED on a pre-fix snapshot where feasible, then GREEN.
- Reconcile all impacted vitest suites green: `nav-single-mount`, `nav-chevron-alignment`, `nav-rail-drill`, `org-switcher`, `workspace-context-band`.
- Run via correct globs: `vitest run test/**/*.test.{ts,tx}`; e2e via Playwright (excluded from vitest).

## Back-affordance state table

| State | Back control | Destination | Glyph |
|---|---|---|---|
| KB landing (S1/S2) + sub-states S3–S7 | Back to menu | /dashboard | band long-arrow (labeled) |
| KB doc view (S8, mobile) | Back to file tree | /dashboard/kb | kb-content-header chevron |
| Desktop (rail persistent) | Back to menu (in band, drilled) | /dashboard | band long-arrow |

## Files to Edit
- `apps/web-platform/components/dashboard/org-switcher.tsx` — swatch→tile (3 sites), de-box, solo/multi affordance
- `apps/web-platform/components/dashboard/workspace-context-band.tsx` — swatch→tile (1 site), de-box, back-state, collapsed monogram, title ownership
- `apps/web-platform/components/dashboard/org-switcher-container.tsx` — de-box the confirm panel container row ONLY (do NOT touch RPC / refreshSession / window.location.assign)
- `apps/web-platform/app/(dashboard)/layout.tsx` — remove "Soleur" wordmark span
- `apps/web-platform/components/kb/kb-content-header.tsx` — back-affordance reconciliation (doc-view back)
- `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` — chrome the fullWidth sub-states
- Tests: `test/nav-rail-drill.test.tsx`, `test/nav-chevron-alignment.test.tsx`, `test/org-switcher.test.tsx`, `test/workspace-context-band.test.tsx`, `e2e/nav-states-shell.e2e.ts`

## Files to Create
- `apps/web-platform/components/dashboard/workspace-identity-tile.tsx` — pure presentational monogram tile
- `apps/web-platform/test/workspace-identity-tile.test.tsx` — monogram derivation, tint determinism, not-gold

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `workspace-identity-tile.tsx` exists, is pure presentational (grep: no import of `OrgSwitcherContainer`/`LiveRepoBadge`), renders a monogram on a non-gold surface (grep: tile fill is NOT `bg-soleur-accent-gold-fg`). No `variant` prop.
- [ ] All 4 prior swatch sites render the tile (grep `bg-soleur-accent-gold-fg/60` returns 0 in `org-switcher.tsx` + `workspace-context-band.tsx`); dropdown row (`org-switcher.tsx:160`) preserves current vs non-current fill distinction.
- [ ] `grep -c '>Soleur<' app/(dashboard)/layout.tsx` returns 0; `"Soleur Workspace"` org-name assertions untouched.
- [ ] `nav-single-mount.test.ts` passes (single-mount preserved); identity band NOT re-mounted inside `kb/layout.tsx`.
- [ ] Exactly one back control per state — new test asserts it; doc view shows "Back to file tree" only; band-back suppression uses no parallel pathname check (ADR-047 AC4c grep stays green).
- [ ] Page-body "Knowledge Base" title + mobile back present in every fullWidth KB sub-state (loading/not-ready/no-project/error) — single wrapper AC, verified via e2e.
- [ ] Collapsed rail: monogram non-gold + `title`/tooltip carries the **full active workspace name** (replaces static `"Active workspace"` at `workspace-context-band.tsx:94`) — unit/e2e assertion.
- [ ] ADR-049 `nav-states-shell.e2e.ts` gate GREEN: no horizontal overflow at `md:w-56`/`md:w-14`, identity content present, wordmark assertions updated.
- [ ] Full vitest suite green (`unit` + `component` projects); `tsc --noEmit` clean.
- [ ] PR body uses `Closes #4915`; references #4916 (deferred logo upload) and #4917 (deferred switch-failure).

### Post-merge (operator)
- [ ] None — pure code change against already-provisioned surface; container restart handled by `web-platform-release.yml` path-filtered push.

## Domain Review

**Domains relevant:** Product, Engineering (carry-forward from brainstorm `## Domain Assessments`).

### Engineering (CTO)
**Status:** reviewed (carry-forward)
**Assessment:** Compose around the single-mount switcher (ADR-047) — never re-mount it. Preserve the switch flow verbatim (RPC + `refreshSession` + hard `window.location.assign`; soft `router.push` = cross-tenant leak). Unify the back *primitive* (slot), not the destination. Tokens only; safe-area; ship KB-first incrementally. No new ADR.

### Product/UX Gate
**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer (this plan, Phase 1), cpo (brainstorm carry-forward), ux-design-lead (brainstorm — `.pen` committed)
**Skipped specialists:** none
**Pencil available:** yes (`.pen` committed at `knowledge-base/product/design/navigation/kb-mobile-nav-redesign-wireframes.pen`, referenced in spec FR1–FR5)

#### Findings
spec-flow surfaced P0-1 (chromeless sub-states hide identity → folded into Phase 4), P0-3 (monogram collision vs logo-only collapsed → folded into Phase 1/4), P1-1/P1-2 (back-affordance state table → Phase 3), P1-3 (solo/multi affordance → Phase 2). P0-2 (switch-failure tenant divergence) is pre-existing in the untouched switch state machine → deferred #4917.

## User-Brand Impact

**If this lands broken, the user experiences:** a KB screen where the active workspace is ambiguous or absent (esp. in loading/error sub-states or the collapsed rail), or a nav that strands them.
**If this leaks, the user's data is exposed via:** acting on the wrong tenant's knowledge base because the chrome made the active workspace unclear (cross-tenant read/edit).
**Brand-survival threshold:** single-user incident.

CPO sign-off: covered by brainstorm Phase 0.1 framing (CPO participated). `user-impact-reviewer` will be invoked at PR review. Mitigations: identity unmistakable at rest in every state (Phase 4), hybrid rule + name-hashed tint + tooltip resolve monogram ambiguity (Phase 1), switch flow untouched (no new cross-tenant vector introduced).

**Bounded async window (review finding, accepted):** the COLLAPSED desktop rail derives its monogram tooltip from `useActiveWorkspaceName`, an async fetch. On first paint (or a transient `list-memberships` failure with no cached value) the collapsed tile shows `?` with the static `"Active workspace"` tooltip for ~one RTT. This is identity-**absent**, never identity-**misidentified** (once resolved the name is server-`isCurrent`-derived, matching the switch state machine's tenant authority), it is desktop-collapsed-only, and it does not strand the user (the switcher + back affordance remain). It therefore does not breach the single-user-incident threshold. The expanded rail + mobile band are synchronous (OrgSwitcherContainer), so the window exists only in the one state that genuinely lacks the data in scope.

## Observability

```yaml
liveness_signal:
  what: ADR-049 headless nav-states Playwright gate renders all drill states
  cadence: every PR (CI) + /work Phase 4
  alert_target: CI red on overflow/identity-absence
  configured_in: e2e/nav-states-shell.e2e.ts
error_reporting:
  destination: existing Sentry (workspace-switch errors already mirrored in org-switcher-container)
  fail_loud: true (no new silent fallbacks introduced; monogram render is deterministic)
failure_modes:
  - mode: monogram tile fails to derive (empty name)
    detection: workspace-identity-tile.test.tsx unit assertion
    alert_route: CI
  - mode: identity absent in a KB sub-state
    detection: nav-states e2e identity-presence assertion
    alert_route: CI red
logs:
  where: n/a (presentational; no new server logs)
  retention: n/a
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/nav-single-mount.test.ts test/nav-chevron-alignment.test.tsx && npx playwright test e2e/nav-states-shell.e2e.ts
  expected_output: all suites pass; no horizontal overflow at md:w-56/md:w-14
```

## Infrastructure (IaC)
None — pure code change against already-provisioned surface (`apps/web-platform/components/**`, `app/**`). No new server, secret, vendor, or runtime process.

## Open Code-Review Overlap
To be confirmed at /work via `gh issue list --label code-review --state open` against the Files-to-Edit list. None known at plan time.

## GDPR / Compliance
No regulated-data surface in scope: no migration, no schema change, no new API route, no auth-flow change (switch flow untouched). The cross-tenant identity control is the brand-survival mechanism (addressed by design, not a data-processing change). The deferred logo-**upload** (#4916) DOES introduce a user-content surface (image upload) and MUST run `gdpr-gate` + validation when built.

## Test Scenarios
1. Monogram tile: 1-char and 2-char derivation, never gold, no `variant` prop.
2. Single-mount: adding the tile does not add a second OrgSwitcherContainer/LiveRepoBadge importer.
3. Wordmark: absent top-level + drilled; `"Soleur Workspace"` org-name still present.
4. Back-affordance: exactly one back per state; doc view = file-tree back only (no parallel pathname check).
5. Page-body chrome: title + mobile back present in fullWidth sub-states (loading/not-ready/no-project/error).
6. Collapsed rail: monogram non-gold + tooltip carries full workspace name.
7. ADR-049 gate: no overflow at both widths; identity content present (not box geometry).

## Sharp Edges
- A plan whose `## User-Brand Impact` is empty/placeholder fails `deepen-plan` Phase 4.6 — filled above.
- jsdom/vitest cannot see CSS layout — the ADR-049 headless gate is mandatory and must run in `/work` Phase 4, not just one-shot qa (PR #4810 shipped 2 layout bugs through 8166 green tests).
- Render-conditional (`{drill === null && …}`), never `md:hidden`, for anything a jsdom test asserts absent (`nav-rail-drill.test.tsx:133`).
- Do NOT touch the switch state machine (RPC / `refreshSession` / `window.location.assign`) — ADR-044/047 load-bearing; its failure-path bug is #4917.
- Preserve width-clamp classes (`w-full min-w-0`, `shrink-0`) and padding ownership when de-boxing (#4810 Bug 1; `nav-chevron-alignment.test.tsx`).
- **ADR-047 AC4c trap:** `segmentToDrillLevel` collapses KB landing + doc view into `"kb"` and is the sole drill authority — band-back suppression must come from an explicit prop or mobile-placement scoping, NEVER a parallel `pathname.includes('/kb/')` check in the band (grep-enforced regression).
- **ADR-047 double-mount trap:** the identity band is mounted in `(dashboard)/layout.tsx` above the KB swap and already persists across fullWidth states — do NOT wrap identity inside `kb/layout.tsx`'s fullWidth branch (Phase 4 adds page-body title+back only).
- Collapsed band has no workspace `name` in scope today — thread it as a prop before the tile/tooltip can render it.
