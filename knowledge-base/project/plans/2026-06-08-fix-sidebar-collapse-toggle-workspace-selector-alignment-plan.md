---
title: "fix: Align floated sidebar collapse toggle with the workspace selector card"
date: 2026-06-08
type: fix
status: draft
branch: feat-one-shot-collapse-icon-workspace-selector-align
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
issue: null
related_prs: [4997]
---

# 🐛 fix: Align the floated sidebar collapse toggle with the workspace selector card

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

The desktop sidebar's collapse / panel-toggle icon (top-right of the rail) is
visually misaligned with the workspace selector card it sits beside. PR #4997
floated the toggle (`absolute right-3 top-3 z-10 … h-6 w-6 … md:flex`) to
reclaim ~45px of top space, mounting it OUTSIDE the flex-col flow and offsetting
it from the rail's top-left origin. The float offset (`top-3` = 12px) was chosen
to mirror the repo's generic corner-control convention
(`components/ui/error-card.tsx:27`), NOT to vertically center the toggle against
the workspace switcher pill that now leads the band — so the toggle's vertical
mid-line lands ~6px above the pill's mid-line, reading as a misalignment.

This is a **pure CSS offset fix** on the floated toggle (and/or the band's
reserved clearance), with no markup-structure, behavior, accessibility, or
data-flow change. The icon glyph itself (`PanelToggleIcon`, a symmetric 24×24
panel) is centered within its `h-6 w-6` button, so the misalignment is entirely
in the button's `top`/`right` placement relative to the band content — not
internal icon asymmetry.

**Scope guard (from PR #4997's own learning):** the floated toggle overlays
content in BOTH band render branches — the expanded multi-workspace pill row
(`workspace-context-band.tsx:162`, has a `▾` chevron `shrink-0` at the right
edge) AND the collapsed icon-only column (`:80-135`, centered monogram tile in
a 56px rail). Any alignment change MUST be evaluated and asserted in BOTH
branches and BOTH toggle states (expand vs collapse), or it ships a regression
in the un-eyeballed branch (per AGENTS.md Sharp Edge
`2026-04-17-alignment-fixes-must-verify-both-toggle-states.md` and PR #4997's
learning `2026-06-08-floating-absolute-control-needs-clearance-in-both-render-branches.md`).

## Premise Validation

- **PR #4997** (`feat(web): float the sidebar collapse toggle…`) — verified
  `MERGED`, mergeCommit `7ae439630`, mergedAt 2026-06-08T09:29:12Z. The floated
  toggle exists on `origin/main`. Premise holds; this is a *fix*, not a *build*.
- **Cited files exist on the branch:**
  `apps/web-platform/app/(dashboard)/layout.tsx` (toggle at L349-356, band mount
  at L369-377) and `apps/web-platform/components/dashboard/workspace-context-band.tsx`
  (expanded pill row L162, collapsed column L80-135) — both confirmed present.
- **"UI exists but is misaligned"** — confirmed behavioral (the toggle renders;
  it is mis-positioned), not never-built. A patch is the correct shape.
- No external premises beyond PR #4997, which holds.

## Research Reconciliation — Spec vs. Codebase

| Spec/Issue claim | Codebase reality | Plan response |
| --- | --- | --- |
| "regression likely lives in the floated-toggle positioning added by PR #4997" | Confirmed: `layout.tsx:353` `absolute right-3 top-3` is the float origin; the band's clearance is reserved via `md:pr-10` (expanded, `workspace-context-band.tsx:162`) and `pt-10` (collapsed, `:91`). | Fix targets the toggle's `top`/`right` offset and/or the band's leading padding so the toggle's center aligns with the pill/tile center. |
| "small CSS/layout fix in the sidebar component(s)" | Confirmed: the only change is Tailwind class values on the toggle button and possibly the band rows. No structural/markup change. | MINIMAL/MORE-level fix; no new component, route, or data path. |
| Toggle glyph might be internally off-center | `PanelToggleIcon` (`layout.tsx:691-707`) is a symmetric 24×24 panel path, centered in `h-6 w-6`. | No icon-internal change needed; offset is wrapper-position only. |

## Description

### Current behavior (broken)

On desktop (`md:`+), the collapse toggle is pinned to `right-3 top-3` of the
`<aside>`. The workspace pill (`org-switcher.tsx:84/118`, `px-3 py-2.5`,
≈44px tall) leads the band at `pt-2` (8px from the rail top, after the band
mount at `layout.tsx:369`). The toggle's vertical center sits at ≈12+12 = 24px
from the rail top; the pill's vertical center sits at ≈8 + 22 = 30px. The ~6px
delta makes the icon read as floating above the card rather than aligned with
it. Horizontally the toggle is `right-3` (12px) while the pill row reserves
`md:pr-10` (40px) of clearance — leaving the toggle visually detached from the
pill's right edge / `▾` chevron.

### Expected behavior (fixed)

The collapse / panel-toggle icon's center aligns with the vertical center of the
workspace selector card (expanded pill row) on desktop, and stays fully inside
and visually centered against the collapsed-rail monogram column. The icon
neither overlaps the `▾` multi-workspace chevron nor the collapsed monogram
tile, in either toggle state.

### Root cause

`top-3` (and the band's `pt-2` leading offset) were chosen independently — the
toggle offset from a generic corner convention, the band offset from a separate
spacing pass (`#4810` / sidebar-UX follow-ups). Neither was derived to make the
two share a vertical center line. The fix is to reconcile the toggle's vertical
offset with the pill row's vertical center (and confirm the horizontal offset
reads as aligned with the card's right edge / chevron clearance).

## User-Brand Impact

**If this lands broken, the user experiences:** the collapse toggle overlapping
the workspace `▾` chevron or the collapsed monogram tile (a worse regression
than the current cosmetic offset), or a still-misaligned icon — a small but
persistent polish defect on the most-seen chrome in the app (the sidebar shows
on every dashboard route).
**If this leaks, the user's data / workflow / money is exposed via:** N/A — this
is a presentation-only CSS offset on an existing control; it touches no data,
auth, persistence, or network surface.
**Brand-survival threshold:** none — purely visual chrome polish; no single-user
incident or aggregate-pattern exposure is reachable from a misplaced icon.

> `threshold: none` — purely cosmetic CSS offset on existing desktop chrome; no
> data/auth/persistence/network surface touched (sensitive-path scope-out for
> preflight Check 6).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Expanded-state vertical alignment.** With the sidebar expanded
  (`collapsed=false`, `md:`+), the floated toggle button's vertical center is
  within ≤2px of the workspace switcher card's vertical center. Asserted in the
  Playwright VRT (`nav-states-shell.e2e.ts`) via rect-center comparison
  (`toggleBox.y + toggleBox.height/2` vs `switcherBox.y + switcherBox.height/2`),
  reusing the existing helpers: `collapseToggle(page)` for the toggle, and the
  card rect from `page.getByRole("button", { name: "Switch workspace" })`
  (multi-membership) or `orgIdentity(page)` =
  `railBand(page).getByTestId("workspace-identity-static")` (single-membership
  chip). This is a NEW positive-alignment assertion; the existing test only
  asserts non-overlap (`intersects(...) === false`), which a misaligned-but-
  non-overlapping toggle passes — that gap is exactly the reported bug.
- [ ] **AC2 — Expanded-state no chevron overlap.** With a ≥2-membership mock
  (chevron renders), the toggle's bounding rect does NOT intersect the
  `▾` chevron's rect. (The PR #4997 learning's `page.route` ≥2-membership
  override registered AFTER `setupNavMocks` is required, or the assertion passes
  vacuously.)
- [ ] **AC3 — Collapsed-state inside-rail + tile clearance.** With the sidebar
  collapsed (`collapsed=true`, `md:w-14` = 56px), the toggle stays fully inside
  the rail (`toggleBox.right ≤ asideBox.right`) and does NOT intersect the
  centered monogram tile's rect.
- [ ] **AC4 — Reclaimed-space invariant preserved (no regression of #4997).**
  The band still rises to the rail top: `bandBox.y - asideBox.y ≤ 12` (the
  AC1 assertion from PR #4997 stays GREEN). The alignment fix must not
  re-introduce the ~45px top gap.
- [ ] **AC5 — Both aria-label states covered.** The VRT locator matches the
  toggle in BOTH states via `getByRole("button", { name: /^(Collapse|Expand) sidebar$/ })`
  (the toggle's `aria-label` flips with `collapsed`).
- [ ] **AC6 — Static markup assertion.** The jsdom test
  (`test/dashboard-sidebar-collapse.test.tsx`) asserts the toggle's resolved
  className set reflects the chosen offset (e.g., the new `top-*`) so a future
  edit that reverts the offset fails CI. (jsdom renders no CSS geometry, so this
  is a className-presence guard, not a geometry assertion — the geometry proof
  lives in the VRT per AC1-AC4.)
- [ ] **AC7 — `tsc --noEmit` clean** and the full web-platform vitest suite is
  green (modulo the 2 pre-existing env-only `run-migrations-unmerged-gate`
  failures documented in PR #4997).
- [ ] **AC8 — Playwright `nav-states` VRT green** on the `authenticated`
  project (`npx playwright test nav-states-shell` — offline mock-Supabase
  storageState, zero credentials).

### Post-merge (operator)

- _None._ Pure web-platform code change; the `web-platform-release.yml` pipeline
  restarts the container on merge to `main` touching `apps/web-platform/**`
  (path-filtered `on.push`) — the merge IS the deploy. No operator step.

## Implementation Phases

### Phase 1 — RED: failing alignment assertion

1. In `apps/web-platform/e2e/nav-states-shell.e2e.ts`, add (or tighten) a
   rect-center assertion for the expanded state (AC1) and confirm it goes RED on
   the current `top-3` markup. Capture the measured pre-fix delta (~6px) in the
   PR body as RED→GREEN proof. Reuse the file's established idiom:
   `getByRole("button", { name: /^(Collapse|Expand) sidebar$/ })` for the
   toggle, the `[data-testid="workspace-context-band"]` expanded pill row for
   the card, and a ≥2-membership `page.route` override (registered AFTER
   `setupNavMocks`) for the chevron-overlap branch (AC2).
2. Files to Edit: `apps/web-platform/e2e/nav-states-shell.e2e.ts`.

### Phase 2 — GREEN: the offset fix

1. In `apps/web-platform/app/(dashboard)/layout.tsx` (toggle button, L349-356),
   adjust the toggle's vertical offset (and, if needed, horizontal) so its
   center aligns with the workspace pill row's center. The candidate change is
   the `top-3` token (e.g., to a value that centers the `h-6` button against the
   `pt-2` + `py-2.5` pill — to be derived against the live VRT, not guessed).
   Keep `right-3` unless the VRT shows a horizontal misalignment against the
   `md:pr-10` clearance; if so, reconcile `right-*` with the chevron's resting
   position. Do NOT change the button's size (`h-6 w-6`), z-index, `md:flex`
   gating, `aria-label`, `title`, or `onClick` — only the offset tokens.
2. **Both-branch check:** re-run the collapsed-state assertions (AC3). The
   collapsed column reserves `pt-10` (`workspace-context-band.tsx:91`). If the
   toggle's new `top-*` reduces the bottom-edge clearance over the monogram
   tile, bump the collapsed column's `pt-*` to preserve AC3 — the collapsed rail
   has ample vertical room (PR #4997 rationale), so a larger top pad costs
   nothing the user notices.
3. **Expanded clearance check:** if the horizontal offset changes, confirm
   `md:pr-10` on the pill row (`workspace-context-band.tsx:162`) still clears the
   toggle's right footprint; widen if necessary.
4. Files to Edit: `apps/web-platform/app/(dashboard)/layout.tsx`, and (only if
   the both-branch checks above require it)
   `apps/web-platform/components/dashboard/workspace-context-band.tsx`.

### Phase 3 — Lock the static guard + full suite

1. Update `apps/web-platform/test/dashboard-sidebar-collapse.test.tsx` (AC6) so
   the toggle's new offset className is asserted (className-presence guard).
2. Run `tsc --noEmit`, the full vitest suite, and the `nav-states` VRT (AC7,
   AC8). Confirm AC4 (reclaimed-space) stays GREEN.

## Files to Edit

- `apps/web-platform/app/(dashboard)/layout.tsx` — adjust floated toggle offset tokens (`top-3`, possibly `right-3`).
- `apps/web-platform/components/dashboard/workspace-context-band.tsx` — **conditional**: bump collapsed `pt-*` / expanded `md:pr-*` clearance only if the both-branch VRT checks require it.
- `apps/web-platform/e2e/nav-states-shell.e2e.ts` — add/tighten rect-center alignment + chevron-overlap assertions (both states).
- `apps/web-platform/test/dashboard-sidebar-collapse.test.tsx` — className-presence guard for the new offset.

## Files to Create

- _None._ (PR #4997 already produced the `.pen` for this toggle —
  `knowledge-base/product/design/dashboard-nav/sidebar-float-collapse-toggle.pen`;
  no new UI surface is created by an offset nudge.)

## Open Code-Review Overlap

None. (No open `code-review`-labelled issue names
`apps/web-platform/app/(dashboard)/layout.tsx`,
`workspace-context-band.tsx`, `nav-states-shell.e2e.ts`, or
`dashboard-sidebar-collapse.test.tsx`; the check ran.)

## Test Scenarios

| Scenario | State | Assertion |
| --- | --- | --- |
| Expanded, single-membership | `collapsed=false`, 1 ws | toggle center ≈ pill-row center (≤2px); toggle inside rail |
| Expanded, multi-membership | `collapsed=false`, ≥2 ws | toggle does NOT overlap `▾` chevron rect |
| Collapsed | `collapsed=true`, `md:w-14` | toggle inside rail; no overlap of monogram tile; AC3 |
| Reclaimed-space regression guard | either | `bandBox.y - asideBox.y ≤ 12` (AC4 / PR #4997 AC1) |
| aria-label flip | both | locator `/^(Collapse|Expand) sidebar$/` resolves in both |

## Domain Review

**Domains relevant:** Product (UI surface — mechanical override)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none — `ux-design-lead` not required: no new UI surface
(an offset nudge to an existing control; PR #4997 already produced the `.pen` for
this toggle). The mechanical UI-surface override forces Product-relevant; the
tier is ADVISORY (modifies existing UI without adding new interactive surfaces),
and on the pipeline path ADVISORY auto-accepts.
**Pencil available:** N/A (no new UI surface)

#### Findings

Pure presentation offset on an existing, already-wireframed control. No new
page, flow, modal, or component. No brand-voice/content change (no copy). No
product-strategy implication. The only product-facing concern — that the fix not
trade one misalignment for a worse overlap — is captured as AC2/AC3 (both-branch
no-overlap assertions) and the both-state Sharp Edge.

## Infrastructure (IaC)

Skipped — pure code change against an already-provisioned surface
(`apps/web-platform/app` + `components`). No server, secret, vendor, DNS, cron,
or persistent runtime process introduced.

## Observability

```yaml
liveness_signal:
  what: "Playwright nav-states VRT (rect-center alignment + no-overlap assertions, both toggle states)"
  cadence: "every PR + on push to main (CI)"
  alert_target: "CI red on the web-platform e2e job"
  configured_in: "apps/web-platform/e2e/nav-states-shell.e2e.ts"
error_reporting:
  destination: "CI job status (vitest + playwright); no runtime error path — CSS-only change has no throw site"
  fail_loud: "AC1-AC4 fail the e2e job; tsc/vitest fail the unit job"
failure_modes:
  - mode: "toggle re-misaligns (offset reverted/drifted)"
    detection: "AC1 rect-center assertion in nav-states VRT + AC6 className guard"
    alert_route: "CI red"
  - mode: "toggle overlaps chevron (expanded) or monogram tile (collapsed)"
    detection: "AC2 / AC3 rect-intersection assertions (both branches)"
    alert_route: "CI red"
  - mode: "reclaimed-space regression (top gap returns)"
    detection: "AC4 bandBox.y - asideBox.y ≤ 12 assertion"
    alert_route: "CI red"
logs:
  where: "CI run logs (GitHub Actions web-platform e2e + unit jobs)"
  retention: "GitHub Actions default (90 days)"
discoverability_test:
  command: "cd apps/web-platform && npx playwright test nav-states-shell --project=authenticated"
  expected_output: "all nav-states specs pass, including the alignment + no-overlap assertions (no ssh)"
```

## Risks & Mitigations

- **Fixing only the expanded branch ships a collapsed-branch regression**
  (PR #4997's exact blast radius). Mitigation: AC2/AC3 assert BOTH branches;
  Phase 2 step 2 re-runs the collapsed checks and bumps `pt-*` if needed.
- **A vertical offset that centers against the pill could reduce the toggle's
  bottom clearance over the collapsed monogram tile.** Mitigation: AC3 +
  Phase 2 step 2 (preserve/expand collapsed `pt-*`).
- **jsdom proves nothing about geometry** — the className guard (AC6) is a
  drift tripwire, not an alignment proof; the geometry proof is the VRT (AC1-AC4).
- **Guessing the exact `top-*` value instead of deriving it from the VRT.**
  Mitigation: Phase 1 (RED) measures the live delta; the GREEN value is chosen
  against the VRT rect-center, not eyeballed.
- **Precedent note (deepen-plan Phase 4.4):** the corner-control offset
  precedent is `components/ui/error-card.tsx:27` (`absolute right-3 top-3`).
  This fix intentionally DIVERGES from that generic convention for the toggle's
  *vertical* offset because the toggle must center against an adjacent card, not
  a card corner — document the divergence rationale in the toggle's code comment
  (the existing comment cites error-card; update it to note the centering
  override).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (Filled above: threshold `none` with sensitive-path scope-out.)
- **Alignment fixes must verify BOTH toggle states** — the collapsed and
  expanded branches render structurally different DOM subtrees with different
  parent geometry; a fix for one can leave the other misaligned/overlapping
  (`knowledge-base/project/learnings/2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`
  and `…/ui-bugs/2026-06-08-floating-absolute-control-needs-clearance-in-both-render-branches.md`).
- **A toggle's `aria-label` flips with state** — the VRT locator must match both
  (`/^(Collapse|Expand) sidebar$/`), or the collapsed-state test throws
  "element not found" (PR #4997 session error).
- **The chevron-overlap branch needs a real ≥2-membership fixture** — the
  single-membership mock renders the non-interactive chip with NO `▾` chevron,
  so an overlap assertion passes vacuously. Register a ≥2-membership
  `page.route` override AFTER `setupNavMocks` (Playwright matches
  last-registered first).
- **`{/* */}` comments are invalid between JSX opening-tag attributes** — use
  `//` line comments there (PR #4997 session error).
