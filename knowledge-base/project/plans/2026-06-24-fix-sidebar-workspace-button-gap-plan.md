---
title: "fix: tighten the sidebar workspace-button → collapse-toggle gap"
type: fix
date: 2026-06-24
branch: feat-one-shot-sidebar-workspace-button-gap
lane: single-domain
brand_survival_threshold: none
related_adrs: [ADR-047, ADR-049]
related_prs: [5075, 4915, 4810]
related_files:
  - apps/web-platform/components/dashboard/workspace-context-band.tsx
  - apps/web-platform/app/(dashboard)/layout.tsx
  - apps/web-platform/test/workspace-context-band.test.tsx
  - apps/web-platform/e2e/nav-states-shell.e2e.ts
---

# fix: Tighten the sidebar workspace-button → collapse-toggle gap 🐛

## Overview

In the **expanded** dashboard sidebar, the workspace switcher card (avatar + truncated
workspace name `S…` + repo subtitle `jlkl…` + `▾` dropdown chevron) renders with a large
empty gap between its right edge and the floated `«` collapse toggle in the top-right
corner of the rail. The workspace name truncates harder than necessary because the card
is squeezed into less horizontal width than the rail actually provides.

**Root cause (precisely localized):** `apps/web-platform/components/dashboard/workspace-context-band.tsx:105`.
The expanded pill-row wrapper carries `md:pr-20` (5rem = **80px** of right padding).
That padding exists to reserve clearance for the floated collapse toggle so the card's
`▾` chevron never sits under it. But the toggle (`layout.tsx:356`) is only
`absolute right-3 top-10 h-6 w-6` — it occupies the band from `right-3` (12px) to
`12 + 24 = 36px` from the rail's right edge. **80px of reservation for a 36px obstacle**
over-reserves ~44px, producing exactly the "big empty gap" in the report and starving
the card of width (the rail is `md:w-56` = 224px; `RAIL_MIN_PX = 224` so it never
narrows below that). Reducing `pr-20` to a value that still clears the toggle with a
small visual margin reclaims that width for the card and tightens the gap.

The bug report says "collapsed/expanded sidebar," but the `«` toggle and the workspace
**card** only co-render in the **expanded** rail. In the collapsed rail (`md:w-14` = 56px)
the band renders an icon-only monogram tile and the toggle is centered above it
(`layout.tsx:356` collapsed branch: `left-1/2 -translate-x-1/2 top-3`) — there is no
card and no gap. **So this fix is expanded-state-only**, and the "both toggle states"
sharp-edge (below) is satisfied by confirming the collapsed state has no card-vs-toggle
gap to fix.

## Research Reconciliation — Spec vs. Codebase

| Report claim | Reality (verified) | Plan response |
| --- | --- | --- |
| "workspace button is too small" | The card is `w-full min-w-0` inside a `flex-1` wrapper (`org-switcher.tsx:152`, `workspace-context-band.tsx:110`); it already fills available width. It only *looks* small because the parent row reserves `md:pr-20` (80px) on the right. | Reduce the over-reserved right padding; the card grows to fill the reclaimed width with no card-side class change. |
| "dropdown chevron on the left" | The `▾` dropdown chevron is the **right-most** element inside the card (`org-switcher.tsx:174`, `ml-1 shrink-0`). The whole card sits on the left of the row; the `«` toggle floats top-right. | Tighten the gap between the card's right edge (chevron) and the floated `«` toggle. No chevron repositioning. |
| "« collapse button … big empty gap" | The `«` toggle is `absolute right-3 top-10` (36px footprint from the right). The `md:pr-20` (80px) clearance is ~44px wider than needed. | Change `md:pr-20` → tightened value (≈ `md:pr-12` / 48px) that clears the 36px toggle with a ~12px margin. |
| affects "collapsed/expanded" | Collapsed rail has **no card** (icon-only tile); `«` is centered above it. No gap exists there. | Expanded-only fix; collapsed path untouched and explicitly verified as not-applicable. |

## User-Brand Impact

**If this lands broken, the user experiences:** the `▾` dropdown chevron of the
workspace switcher overlapping or sitting under the floated `«` collapse toggle, or the
expanded rail overflowing horizontally — a visibly broken sidebar header.

**If this leaks, the user's data is exposed via:** N/A — this is a pure
presentational CSS-padding change. It touches no data, auth, network, or persistence
surface.

**Brand-survival threshold:** none — a cosmetic layout adjustment on an existing UI
surface, fully covered by an existing e2e rect/overflow gate. No sensitive path
(`apps/web-platform/components/dashboard/` is not a regulated-data surface).

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)

1. Confirm the only `pr-20` occurrence in app code is the band wrapper:
   `git grep -n "pr-20" apps/web-platform/components apps/web-platform/app` → exactly
   one functional hit (`workspace-context-band.tsx:105`); the comment hit at `:95`
   updates with it.
2. Confirm the toggle geometry the clearance must clear:
   `grep -n "right-3 top-10" apps/web-platform/app/\(dashboard\)/layout.tsx` →
   `right-3` (12px) + `h-6 w-6` (24px) ⇒ 36px right footprint; a `pr-12` (48px) leaves
   a ~12px margin.
3. Read the band test tripwires that MUST stay green (no `pr-20` literal is asserted,
   so the change is test-safe by construction):
   `grep -n "pr-2\|pr-20\|min-h-\[64px\]\|pt-2\|pt-3" apps/web-platform/test/workspace-context-band.test.tsx`
   → asserts `pt-2`, `pt-3`, `pb-3`, `md:min-h-[64px]` only.

### Phase 1 — Tighten the clearance padding

In `apps/web-platform/components/dashboard/workspace-context-band.tsx`:

- Line 105: change the expanded pill-row wrapper className
  `flex items-center gap-2 px-3 pt-2 md:pr-20` → `flex items-center gap-2 px-3 pt-2 md:pr-12`.
  (`pr-12` = 48px clears the 36px toggle with a ~12px margin while reclaiming ~32px of
  card width. Keep `md:min-h-[64px]` on the `drill === null` branch untouched — it is a
  vertical reserve, orthogonal to this horizontal change.)
- Lines 95–100 comment block: update the `md:pr-20` reference to `md:pr-12` and restate
  the arithmetic (toggle is `right-3` + `w-6` = 36px from the right; `pr-12` = 48px
  clears it with a 12px margin) so the next reader does not re-inflate it.

**No change to `org-switcher.tsx`** — the card is already `w-full min-w-0` and fills the
reclaimed width automatically. No change to `layout.tsx` toggle position.

### Phase 2 — Tests

1. **Update the band unit test** (`apps/web-platform/test/workspace-context-band.test.tsx`):
   add/extend a tripwire on the expanded `drill === null` (and a drilled route) pill
   wrapper asserting `className` **contains `md:pr-12`** and **does NOT contain `md:pr-20`**
   — a literal-token tripwire mirroring the existing `md:min-h-[64px]` / `pt-2` /
   `pt-3` tripwire style (jsdom has no layout engine; the binding geometric proof is the
   e2e below). Note in the test comment that the e2e rect gate is the source of truth.
2. **Confirm the existing e2e gate stays green** (no edit expected; run to verify):
   `apps/web-platform/e2e/nav-states-shell.e2e.ts` already asserts (a) the expanded
   drilled rail does not overflow horizontally (`scrollWidth - clientWidth ≤ 1`,
   ~line 428) and (b) the band rises to the aside top. Tightening the padding only
   *reduces* used width, so the no-overflow gate cannot regress. If a `«`-toggle ↔ `▾`-chevron
   rect-non-intersection assertion does not already exist in this file, ADD one in the
   `expanded multi-workspace` test: locate the `«` toggle (`getByRole("button",
   { name: /collapse sidebar/i })`) and the `▾` chevron (last child of the
   `Switch workspace` button), `boundingBox()` both, and assert
   `chevronBox.x + chevronBox.width <= toggleBox.x` (no horizontal overlap). This is the
   load-bearing proof that `pr-12` still clears the toggle.

### Phase 3 — Verify

- Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- Unit: `cd apps/web-platform && ./node_modules/.bin/vitest run test/workspace-context-band.test.tsx`.
- e2e (the binding geometric gate): run the `nav-states-shell` suite per the project's
  Playwright invocation; confirm the expanded-rail no-overflow + new non-intersection
  assertions pass.
- Visual: load `/dashboard` (multi-workspace) expanded — the card fills the rail, a
  small (~12px) gap to the `«` toggle, the `▾` chevron does not touch the toggle; the
  org name truncates only when genuinely too long for the wider card.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `workspace-context-band.tsx:105` expanded pill-row wrapper uses `md:pr-12` (not
      `md:pr-20`); `git grep -n "md:pr-20" apps/web-platform` returns zero functional hits.
- [ ] The lines 95–100 comment references `md:pr-12` with the toggle-clearance arithmetic
      (36px footprint, 48px clearance) — no stale `pr-20` reference remains.
- [ ] `md:min-h-[64px]` (drill===null) and the `pt-2`/`pt-3`/`pb-3` tripwires are
      unchanged (`vitest run test/workspace-context-band.test.tsx` green).
- [ ] New unit tripwire asserts the expanded pill wrapper `className` contains `md:pr-12`
      and not `md:pr-20`.
- [ ] e2e `nav-states-shell.e2e.ts`: expanded drilled rail overflow ≤ 1px (existing gate)
      AND `«`-toggle ↔ `▾`-chevron horizontal non-intersection holds (existing or new
      assertion).
- [ ] `tsc --noEmit` clean; no change to `org-switcher.tsx` or `layout.tsx` toggle
      position.
- [ ] Collapsed rail unaffected: `data-collapsed="true"` icon-only path (band
      `pt-16` clearance) renders unchanged (covered by the existing
      "collapsed top-level: rail is icon-only" e2e test).

## Domain Review

**Domains relevant:** Product (UX) — ADVISORY tier.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline/headless context — plan-file-path argument)
**Skipped specialists:** none — this modifies an existing UI component's spacing without
adding any new interactive surface, page, or component file (no `components/**/*.tsx`
*creation*, no `app/**/page.tsx`). Mechanical UI-surface override fires (edits
`components/dashboard/workspace-context-band.tsx`) → Product relevant; mechanical
escalation to BLOCKING does NOT fire (no new component *file* created), so tier is
ADVISORY. No wireframe is required for a single padding-token adjustment to existing,
already-designed chrome.
**Pencil available:** N/A (no new UI surface; existing-component spacing change)

#### Findings

Pure presentational adjustment. No new flows, no copy, no emotional/persuasive
interstitial. The existing ADR-049 e2e rect-non-intersection methodology already governs
this surface; the fix is a width reclamation within that proven geometry envelope.

No other domains (Engineering-infra, Legal, Finance, Sales, Marketing, Operations,
Support) have implications — no infra, no data, no money, no external surface.

## Architecture Decision (ADR/C4)

No architectural decision. This is a CSS-padding token change on an existing component
governed by the already-active ADR-047 (workspace context band placement) and ADR-049
(e2e rect-intersection nav methodology). No ownership/tenancy move, no new substrate, no
resolver/trust-boundary change, no ADR reversal. A competent engineer reading the
existing ADRs + C4 would not be misled after this ships. **Skip.**

## Observability

Skipped — pure presentational change; no Files-to-Edit under `apps/*/server/`,
`apps/*/infra/`, or `plugins/*/scripts/`. The only code edits are a Tailwind class token
in a `components/` `.tsx` file and its test. No new error path, log call, infra surface,
or failure mode is introduced. (Per Phase 2.9 skip condition: code-class file under
`apps/*/src`-equivalent but no new server/infra surface and no failure mode — the e2e
overflow/non-intersection gate is the regression detector.)

## Infrastructure (IaC)

None — no server, service, cron, secret, vendor, DNS, cert, or firewall change. Pure
front-end file edit against an already-provisioned surface. **Skip.**

## Open Code-Review Overlap

Deferred until `## Files to Edit` is frozen at draft time; the file set is exactly
`workspace-context-band.tsx` (+ its unit test and the e2e). At plan time no open
`code-review`-labeled issue is known to touch `workspace-context-band.tsx`; /work should
re-run the overlap query (`gh issue list --label code-review --state open --json
number,title,body` then `jq … contains("workspace-context-band")`) before freezing.
Disposition default: None expected.

## Files to Edit

- `apps/web-platform/components/dashboard/workspace-context-band.tsx` — `md:pr-20` →
  `md:pr-12` on the expanded pill-row wrapper (line 105) + comment update (lines 95–100).
- `apps/web-platform/test/workspace-context-band.test.tsx` — add `md:pr-12` /
  not-`md:pr-20` tripwire.
- `apps/web-platform/e2e/nav-states-shell.e2e.ts` — add `«`↔`▾` non-intersection
  assertion **only if** one does not already exist (verify in Phase 2).

## Files to Create

None.

## Sharp Edges

- **Both toggle states must be verified** (learning `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`).
  The collapsed rail renders a *different DOM subtree* (icon-only monogram, no card,
  toggle centered at `top-3` in the band's `pt-16` clearance). The expanded fix
  (`pr-20`→`pr-12`) does NOT touch the collapsed path, and the collapsed state has no
  card-vs-toggle gap to fix — confirm the existing "collapsed top-level: rail is
  icon-only" e2e test still passes (no regression), satisfying the both-states gate.
- **`pr-12` must actually clear the toggle.** The toggle is `right-3 top-10 w-6` ⇒ 36px
  right footprint. `pr-12` = 48px leaves ~12px margin. Do NOT drop below `pr-10` (40px)
  — that leaves only ~4px and risks the `▾` chevron visually touching the `«` toggle.
  The e2e non-intersection assertion is the binding proof; the unit tripwire is a token
  smoke check only (jsdom has no layout engine).
- **Do not remove `md:min-h-[64px]`** (drill===null branch). It is an orthogonal
  *vertical* reserve that holds the async/empty band open under the floated toggle's
  vertical footprint (`top-10` + `h-6` = 64px). It is unrelated to the horizontal gap
  and has its own tripwire + e2e proof — leave it intact.
- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO, or omits
  the threshold will fail `deepen-plan` Phase 4.6 — this section is filled with a
  concrete artifact, exposure vector, and `threshold: none`.

## Test Scenarios

1. Multi-workspace expanded rail: card fills the rail width, `▾` chevron sits ~12px left
   of the `«` toggle, no horizontal overflow (`scrollWidth - clientWidth ≤ 1`).
2. Solo (1 workspace) expanded rail: static identity chip fills the reclaimed width; no
   `▾`, no overlap with the toggle.
3. Drilled (Settings/KB) expanded rail: back chevron + section title rows unaffected; pill
   row reclaims width; no overflow.
4. Collapsed rail (regression): icon-only monogram, toggle centered above, `data-collapsed="true"`
   — unchanged.
5. Unit tripwires: `md:pr-12` present, `md:pr-20` absent, `md:min-h-[64px]` / `pt-2` /
   `pt-3` / `pb-3` all still present.
