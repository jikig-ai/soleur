---
title: "Fix workspace-selector nav overflow + back-chevron misalignment"
type: fix
date: 2026-06-03
branch: feat-one-shot-workspace-selector-nav-overflow
lane: single-domain
brand_survival_threshold: none
status: planned
---

## Enhancement Summary

**Deepened on:** 2026-06-03
**Sections enhanced:** Root-Cause Analysis, Approach (Fix A/B), Acceptance Criteria, Test Scenarios, Risks
**Halt gates passed:** 4.6 User-Brand Impact (threshold `none` + scope-out; Files-to-Edit do NOT match sensitive-path regex), 4.7 Observability (pure-CSS, no `server|src|infra` surface — section present), 4.8 PAT-shape (clean), 4.9 UI-Wireframe (no new UI surface file — only a `test/**` file in Files-to-Create → ADVISORY, no `.pen` required)

### Key Improvements (grounded in branch source)

1. **The existing #4833 VRT gate (`e2e/nav-states-shell.e2e.ts`) already asserts
   `scrollWidth - clientWidth <= 1` on the `<aside>` — but ONLY for the two
   COLLAPSED states (lines 239, 267).** The "drilled (expanded)" test (line 222)
   checks chrome presence and does NOT assert overflow. **This is the exact gap
   that lets Bug 1 ship.** The fix is to add the same overflow assertion to a new
   expanded-drilled test at `md:w-56` for `/dashboard/kb` and `/dashboard/chat/<id>`.
   Reuse the existing `aside.evaluate((el) => el.scrollWidth - el.clientWidth)` shape
   verbatim — it is the canonical overflow probe in this file.
2. **Flex-clamp precedent confirmed:** the codebase's canonical truncating-flex
   shape is `min-w-0 flex-1 truncate` (`components/chat/kb-chat-content.tsx:150`)
   and `max-w-full` for media (`components/kb/file-preview.tsx:73`). The
   `OrgSwitcher` button is the only rail-bound interactive control that omits a
   `w-full`/`min-w-0` clamp on its own flex container — adopt the precedent shape.
3. **Regression risk is low and verified:** `org-switcher.test.tsx`,
   `workspace-context-band.test.tsx`, `org-switcher-container.test.tsx` have ZERO
   `toHaveClass` assertions on padding/width (`grep -cE toHaveClass` → 0/0/0). The
   only class assertions are on the dropdown menu's `left-0`/`top-full` positioning
   (org-switcher.test.tsx:98-102), which Fix A/B do not touch.
4. **Both chevrons are byte-identical glyphs** — `ChevronLeftIcon` (layout.tsx:577)
   and `BackChevronIcon` (band:29-45) share the identical path
   `M15.75 19.5 8.25 12l7.5-7.5`. Confirms the "duplicate-looking arrows" report and
   makes the A2 (distinct-icon) disambiguation a real, verifiable change.

### New Considerations Discovered

- The VRT gate's empty-band guard (e2e comment lines 16-19) means an overflow test
  must ALSO assert the band's verbose content is visible — an unmounted band would
  trivially satisfy `scrollWidth <= clientWidth`. The new expanded-drilled overflow
  test must assert the pill text (workspace name) is visible AND no overflow.
- The collapse toggle is rendered UNCONDITIONALLY on md+ (layout:269, no `drill`
  gate); the band back chevron is rendered only when `drill !== null`. So the "two
  chevrons" only co-exist in drilled states — which is exactly the chat/KB
  screenshots. Top-level `/dashboard` shows only the collapse toggle (band uses the
  invisible placeholder, band:137-141). AC8 protects this.

# 🐛 fix: Workspace selector overflows nav rail + back-arrow chevrons misaligned

## Overview

The web-platform dashboard nav rail (single rail, ADR-047, shipped in PR #4810 and
patched by #4833) has two CSS/layout defects in its collapsed / drilled states:

1. **Horizontal overflow of the workspace-selector pill.** In the chat and
   Knowledge Base views, the "Soleur Workspace / Owner" selector pill (gold
   square avatar + workspace name + role label + `▾` caret) is too wide and
   spills past the right edge of the nav rail into the main content area.

2. **Two misaligned back-arrow `<` chevrons.** One chevron sits at the very
   top-left of the rail (the sidebar collapse toggle in `layout.tsx`); a second
   chevron sits to the LEFT of the workspace pill (the "Back to menu" chevron in
   `WorkspaceContextBand`). They render at different vertical positions and read
   as visually broken. The expanded Dashboard view is correct (single collapse
   chevron at top + a pill that fits the rail width).

This is a self-contained client-side layout fix in the web-platform Next.js app.
No data, schema, auth, or API surface is touched.

## Root-Cause Analysis (verified against branch source)

All file paths verified present on this branch (Phase 0.6 premise validation).

### Render-path map — `apps/web-platform/app/(dashboard)/layout.tsx`

The `<aside>` rail (layout.tsx:238-391) has these vertically-stacked regions, in order:

| Region | Lines | Gated by | Renders a chevron? |
|---|---|---|---|
| Brand + collapse-toggle row | 250-281 | always (md+) | **YES** — `ChevronLeftIcon`/`ChevronRightIcon` collapse toggle (269-280) |
| Theme-toggle row | 285-289 | `drill === null` only | no |
| `WorkspaceContextBand` (desktop) | 302-304 | always (`hidden md:block`), receives `collapsed` | **YES (conditionally)** — band's own back chevron |
| Rail swap: primary nav OR secondary slot | 310-390 | `drill === null` ? nav : slot | no |

### Bug 2 (chevron misalignment) — the structural defect

`WorkspaceContextBand` (`components/dashboard/workspace-context-band.tsx`) renders
a **"Back to menu" chevron** in BOTH of its return paths whenever `drill !== null`:

- collapsed path: `nav-back-chevron` Link at lines 76-85 (icon-only column).
- expanded path: `nav-back-chevron` Link at lines 128-136 (left of the pill row).

Meanwhile the layout's **collapse-toggle** chevron (layout.tsx:269-280) renders
**unconditionally on md+** in the brand row at the very top of the rail.

So in any drilled state (chat `/dashboard/chat/*`, KB `/dashboard/kb/*`, settings)
the rail shows **two `<`-shaped chevrons** at two different vertical positions:
the collapse toggle at top, the back chevron lower down beside/above the pill.
They serve different functions (collapse the rail vs. navigate up to the top-level
menu) but are visually identical glyphs, so they read as a broken duplicate.

Note the collapse-toggle uses `ChevronLeftIcon` (`M15.75 19.5 8.25 12l7.5-7.5`)
and the band uses `BackChevronIcon` (identical path `M15.75 19.5 8.25 12l7.5-7.5`).
They are byte-identical glyphs — confirming the "two `<` arrows" report.

### Bug 1 (pill overflow) — the width defect

In the **expanded drilled** state (e.g. `/dashboard/kb` at `md:w-56` = 224px), the
band's identity row (band lines 123-145) is:

```
[ back-chevron h-7 w-7 (28px) ] [ gap-2 (8px) ] [ <div min-w-0 flex-1> OrgSwitcherContainer ] 
```

`OrgSwitcherContainer` (`org-switcher-container.tsx:122-124`) wraps `OrgSwitcher`
in its OWN `border-b ... px-3 py-3` div — a **redundant nested horizontal padding
box** (the band already supplies `px-3` at band:123, and the container adds another
`px-3` = 12px each side). `OrgSwitcher`'s multi-org button (`org-switcher.tsx:94-117`)
is a `flex` with `border`, `px-3`, a 24px avatar (`shrink-0`), a `min-w-0` text
column with `truncate`, and a trailing `▾` caret.

The width math at 224px rail width, drilled:
- rail `md:w-56` = 224px, band row `px-3` = -24px → 200px
- back-chevron 28px + gap 8px → 164px for the `min-w-0 flex-1` wrapper
- container's extra `px-3` = -24px → 140px for the `OrgSwitcher` button
- button `border` + `px-3` (-24px) + avatar 24px + gap 8px + caret (`ml-1` ~16px) →
  ~68px for the truncating text column.

The text column DOES carry `truncate` (org-switcher.tsx:83, 109), so the *name*
clips. **The overflow is the button box itself, not the text**: the `OrgSwitcher`
button has NO `w-full`/`max-w-full`/`min-w-0` on its own flex container, so its
intrinsic content width (avatar + un-truncated initial layout pass + caret +
borders + the doubled `px-3`) can exceed the `flex-1` parent before truncation
settles, and the bordered box paints past the rail's right border into `<main>`.
The doubled padding + the absence of a width clamp on the button is the overflow.

In the **collapsed** state (`md:w-14` = 56px) the band takes the icon-only path
(band:68-111), which is `items-center px-2` and does NOT overflow — so the
reported overflow is the **expanded-but-narrow drilled** state (the chat/KB rail
at `md:w-56`), consistent with the screenshots showing readable text spilling out.

### Why the expanded Dashboard view looks correct

At `/dashboard` (top level, `drill === null`): the band's back chevron is replaced
by an **invisible placeholder** of the same size (band:137-141), so there is no
second visible chevron — only the top collapse toggle. And the pill has the full
rail width because no drilled secondary content competes. The bug only manifests
when `drill !== null`.

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch (one-shot direct-to-plan path). The ARGUMENTS
bug description was validated against branch source:

| Claim (from screenshots) | Reality (verified) | Plan response |
|---|---|---|
| "workspace-switcher / sidebar / nav components" hold the bug | `layout.tsx` + `workspace-context-band.tsx` + `org-switcher-container.tsx` + `org-switcher.tsx` | Edit these (see Files to Edit) |
| Pill overflows in collapsed/narrow state | Overflow is in the **expanded drilled** rail (`md:w-56`); the truly-collapsed `md:w-14` path is already icon-only & bounded | Clamp the pill width in the expanded drilled path; remove doubled padding |
| "Two `<` chevrons not aligned" | Collapse-toggle (layout) + back-chevron (band) are byte-identical glyphs at different y-positions when drilled | Consolidate: keep ONE chevron per function and disambiguate (see Approach) |
| Expanded Dashboard view correct | Confirmed — band uses invisible chevron placeholder at top level | No change to top-level path |

## User-Brand Impact

**If this lands broken, the user experiences:** a visibly broken nav rail — the
workspace pill bleeding into chat/KB content and two duplicate-looking back arrows
— on the two most-used authenticated routes (chat, KB), undermining trust in the
product's polish on first impression.
**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — this
is a pure presentational CSS/layout change; no data, identity, or tenant boundary
is touched. The `OrgSwitcherContainer` switch logic (RPC, JWT refresh, hard nav)
is NOT modified.
**Brand-survival threshold:** none — `reason: cosmetic layout fix on already-shipped
chrome; no regulated-data surface, no write path, no tenant-isolation logic touched.`

## Approach

Two coordinated fixes, both CSS/structural in existing components. No behavior,
data, or routing change.

### Fix A — Eliminate the duplicate / misaligned chevrons (Bug 2)

The collapse toggle and the back chevron are two different affordances that happen
to share a glyph. Chosen resolution (lowest-risk, preserves both functions):

1. **Keep exactly one chevron in the top brand row.** The collapse toggle stays at
   top (layout.tsx:269-280) — it is the global "collapse the rail" control and must
   remain reachable in every state.
2. **Move the band's "Back to menu" affordance out of glyph-collision.** Two options
   to decide at /work-time against the wireframe (see Domain Review → UX gate):
   - **A1 (preferred):** Render the back affordance as a labelled row ("← Back to
     menu" with text in expanded state; chevron-only in collapsed state) and place
     it as the FIRST element of the band, vertically aligned to the same left gutter
     (`px-3`) as the collapse toggle's column — so when both are visible they sit on
     one consistent left edge and the back row reads as a distinct labelled control,
     not a duplicate of the collapse glyph.
   - **A2 (fallback):** Swap the back-chevron glyph for a visually distinct
     "arrow-uturn-left" / "arrow-left-with-bar" icon so the two controls are not
     byte-identical, and align it to the collapse toggle's left gutter.
3. **Vertical alignment invariant:** whichever option, the back affordance's left
   edge MUST share the collapse toggle's left gutter. Today the collapse toggle is
   in a `justify-between` row at `px-2`(collapsed)/`px-5`(expanded) (layout:250) and
   the band uses `px-3` (band:123) — these gutters differ, which is the root of the
   "different vertical positions / not aligned" report. Unify the band's gutter and
   the brand row's gutter, OR (cleaner) move the back affordance into the brand row's
   alignment context.

**Both toggle states MUST be verified** (collapsed `md:w-14` AND expanded `md:w-56`)
per the Sharp Edge below — the collapsed band path (band:68-111) and expanded path
(band:113-160) render different DOM subtrees and both show the back chevron when
drilled.

### Fix B — Clamp the pill so it never overflows the rail (Bug 1)

1. **Remove the redundant nested horizontal padding.** `OrgSwitcherContainer`'s
   wrapper div (`org-switcher-container.tsx:123`) double-applies `px-3` on top of the
   band's `px-3`. Drop the container wrapper's horizontal padding (or the band's) so
   there is a single padding box. Keep the `border-b` separator.
2. **Add a width clamp to the `OrgSwitcher` interactive button and static chip.**
   Add `w-full min-w-0 max-w-full` to the `OrgSwitcher` button (org-switcher.tsx:102)
   and to the solo static chip (org-switcher.tsx:74-77) so the bordered box can never
   exceed its `flex-1` parent; the inner text column already has `min-w-0 truncate`.
   Confirm the trailing `▾` caret is `shrink-0`.
3. **Verify `min-w-0` propagation.** The band's identity-row wrapper (band:142,
   `min-w-0 flex-1`) is correct; ensure the chain `band flex-1 → container → button`
   carries `min-w-0` at every level (a single missing `min-w-0` defeats the whole
   chain in flexbox).

### Out of scope (Non-Goals)

- Any change to the workspace-switch behavior (RPC, JWT refresh, reload) in
  `OrgSwitcherContainer.executeSwitch`. Untouched.
- Any change to `segment-to-drill-level.ts` drill authority or `use-sidebar-collapse`.
- Mobile top-bar band (`variant="mobile"`) — already `min-w-0 flex-1` (band:119)
  and not implicated by the screenshots. Verify it does not regress; do not redesign.
- Restructuring the rail-swap architecture (ADR-047). This is a layout-clamp fix.

## Files to Edit

- `apps/web-platform/components/dashboard/workspace-context-band.tsx` — back-chevron
  alignment + gutter unification (Fix A); both collapsed and expanded paths.
- `apps/web-platform/components/dashboard/org-switcher-container.tsx` — remove the
  redundant nested `px-3` wrapper padding (Fix B step 1).
- `apps/web-platform/components/dashboard/org-switcher.tsx` — width clamp on the
  multi-org button + solo static chip; confirm caret `shrink-0` (Fix B steps 2-3).
- `apps/web-platform/app/(dashboard)/layout.tsx` — only if Fix A requires unifying
  the brand-row gutter with the band gutter (left-edge alignment). Keep the single
  collapse toggle; do NOT remove it.

## Files to Create

- `apps/web-platform/test/nav-chevron-alignment.test.tsx` — new vitest component test
  asserting (a) in a drilled state there is exactly one element with the collapse-toggle
  role/label AND exactly one `nav-back-chevron`, and that they are distinct controls;
  (b) the pill/button carries the width-clamp classes; (c) both collapsed and expanded
  band paths render the back affordance with the unified gutter. (Path under `test/`
  to satisfy the vitest `include: ["test/**/*.test.tsx"]` glob — a co-located
  `components/**/*.test.tsx` would be silently skipped.)

## Open Code-Review Overlap

1 open scope-out touches `app/(dashboard)/layout.tsx`:

- **#2193** (`refactor(billing): unify past_due and unpaid banners into shared
  component + extract useDismissiblePersistent`) — **Acknowledge.** #2193 concerns
  the `PaymentWarningBanner` / unpaid-banner blocks in `layout.tsx` (lines 33-90,
  399-415), a billing-chrome refactor. This plan touches only the `<aside>` nav-rail
  chevron/gutter region (lines 250-281) and never the banner blocks. Different
  concern, different lines; #2193 stays open. No fold-in.

(Re-confirmed via `gh issue list --label code-review` + per-path `jq` contains-match
on the final Files-to-Edit list; the other three files had zero matches.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — No overflow (expanded drilled).** At `md:w-56` on `/dashboard/kb` and
  `/dashboard/chat/<id>`, the rail must not overflow: add a NEW test to
  `e2e/nav-states-shell.e2e.ts` (the existing "drilled (expanded)" test at line 222
  checks chrome presence only — it has NO overflow assertion; that gap is why Bug 1
  ships). The new test reuses the canonical probe verbatim:
  `const overflow = await aside.evaluate((el) => el.scrollWidth - el.clientWidth); expect(overflow).toBeLessThanOrEqual(1);`
  AND (per the empty-band guard, e2e:16-19) asserts the pill's workspace-name text
  is visible so an unmounted band cannot trivially pass.
- [ ] **AC2 — No overflow (collapsed).** At `md:w-14` the icon-only band path
  (`data-collapsed="true"`) stays within 56px; no horizontal scrollbar on the rail.
- [ ] **AC3 — Single collapse chevron.** In every state there is exactly ONE
  collapse-toggle control (`aria-label="Collapse sidebar"`/`"Expand sidebar"`) at the
  top of the rail. Asserted in `nav-chevron-alignment.test.tsx`.
- [ ] **AC4 — Back affordance disambiguated + aligned.** In a drilled state, the
  band's `nav-back-chevron` is (a) present exactly once, (b) NOT a byte-identical
  duplicate of the collapse glyph (distinct label/icon per Fix A), and (c) shares the
  collapse toggle's left gutter. Asserted in the new test + a Playwright bounding-box
  check that the back affordance's `x` ~= the collapse toggle's `x` (within tolerance).
- [ ] **AC5 — Both toggle states verified.** The new test renders the band with
  `collapsed={false}` AND `collapsed={true}` for a drilled pathname and asserts the
  back affordance in each (the two paths are different DOM subtrees).
- [ ] **AC6 — No behavior regression.** `org-switcher-container.test.tsx`,
  `org-switcher.test.tsx`, `workspace-context-band.test.tsx`, `nav-rail-drill.test.tsx`,
  `nav-single-mount.test.ts` all pass unchanged (switch RPC/JWT/reload logic untouched).
- [ ] **AC7 — Suite green.** `./node_modules/.bin/vitest run` (the package runner;
  NOT `bun test` — `bunfig.toml` blocks bun discovery) passes for the web-platform app.
- [ ] **AC8 — Top-level unchanged.** `/dashboard` (`drill === null`) still shows the
  Soleur wordmark + single collapse chevron + full-width pill (no back chevron, the
  invisible placeholder path band:137-141 is preserved).

### Post-merge (operator)

None. Pure client-side layout change; `web-platform-release.yml` redeploys on merge
to `main` touching `apps/web-platform/**` (path-filtered) — the merge IS the deploy.

## Test Scenarios

1. Multi-org user on `/dashboard/kb` expanded → pill fits, one back chevron aligned
   to collapse toggle gutter, one collapse toggle at top. (Playwright + vitest)
2. Multi-org user on `/dashboard/chat/<id>` collapsed → icon-only band, no overflow.
3. Solo user (1 membership) on `/dashboard/kb` → static identity chip clamped, no
   overflow, no dropdown affordance (org-switcher.tsx:72-92 path).
4. Top-level `/dashboard` → wordmark + single chevron, no back chevron (AC8).
5. Long workspace name (e.g. 40 chars) → name truncates with ellipsis; box does not
   grow past the rail.

## Domain Review

**Domains relevant:** Product (UI surface)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline auto-accept on ADVISORY)
**Skipped specialists:** none
**Pencil available:** N/A — this plan MODIFIES existing UI chrome (no new page,
flow, or component file). Per the Product/UX Gate, modifying existing user-facing
components without adding new interactive surfaces is ADVISORY, and on the
pipeline path ADVISORY auto-accepts. The mechanical UI-surface override checks
`Files to Create` for `components/**/*.tsx` / `app/**/page.tsx` / `app/**/layout.tsx`
— the only new file is a `test/**` file (not a UI surface), so the override does
not fire and no `.pen` wireframe is required.

#### Findings

The fix should follow the existing wireframe `04-org-switcher-header.png`
(referenced in org-switcher.tsx:9) for the pill, and the ADR-047 single-rail
model. The back-affordance disambiguation (Fix A1 vs A2) is the only open design
choice; default to A1 (labelled "Back to menu" row) unless the wireframe dictates
otherwise. No new persuasive/emotional copy is introduced.

## Observability

Skipped — pure presentational CSS/layout change with no new code-class server/infra
surface, no new failure mode, no runtime signal to emit. (Plan edits live under
`apps/web-platform/components/` + `app/(dashboard)/layout.tsx` + `test/`; the
observability gate targets `server/`, `src/`, `infra/`, `scripts/`, or new infra.)
The discoverability test for this change is the Playwright VRT gate
(`nav-states-shell.e2e.ts`), not a runtime liveness probe.

## Infrastructure (IaC)

None — no server, service, cron, vendor, DNS, cert, secret, or firewall rule
introduced. Pure code change against the already-provisioned web-platform app.

## Risks & Mitigations

### Precedent diff (Phase 4.4)

Pattern-bound behavior: truncating flex within a width-bounded rail. Codebase
precedent exists — adopt it rather than inventing a clamp shape:

```
# Canonical truncating-flex (components/chat/kb-chat-content.tsx:150)
<div className="min-w-0 flex-1 truncate"> ... </div>
# Media clamp (components/kb/file-preview.tsx:73)
className="max-h-[60vh] max-w-full object-contain"
```

The `OrgSwitcher` button (org-switcher.tsx:102) currently has neither `w-full` nor
`min-w-0` on its own flex container — it is the outlier. Fix B applies the precedent
shape (`w-full min-w-0 max-w-full`) to the button + static chip; the inner text
column already follows precedent (`min-w-0 ... truncate`, org-switcher.tsx:82-83,108-109).

### Verify-the-negative (Phase 4.45)

The plan's "no behavior regression" claim (AC6) was probed: `OrgSwitcherContainer`'s
switch path (`executeSwitch`, RPC + `refreshSession` + `window.location.assign`,
org-switcher-container.tsx:64-103) is NOT in any Files-to-Edit hunk — Fix B touches
only the `border-b px-3 py-3` wrapper (L123) padding, not the logic. Confirmed:
existing behavior tests have 0 `toHaveClass` padding/width assertions, so the
class-only changes cannot break them.

- **Flexbox `min-w-0` chain.** A single missing `min-w-0` between band `flex-1` →
  container → button defeats truncation. Mitigation: Fix B step 3 audits the full
  chain; AC1/AC5 assert no overflow in both states.
- **Removing one `px-3` could under-pad the pill.** Mitigation: keep exactly one
  `px-3` box (band's), verify visually via VRT screenshot; the gutter must still
  align with nav items below (which use `px-3`, layout:313).
- **Collapsed vs expanded divergence.** The two band return paths are separate DOM
  subtrees; a fix to one can miss the other (see Sharp Edge). AC5 forces both.
- **Glyph swap (A2) could collide with another icon.** Mitigation: if A2 is chosen,
  pick an icon not already used in the rail (grep `function .*Icon` in layout.tsx).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This
  section is filled: threshold `none` with a scope-out reason.)
- **Verify alignment in BOTH toggle states.** The bug report names the drilled
  collapsed/narrow state, but the band renders different DOM for collapsed
  (band:68-111) vs expanded (band:113-160). Fix and verify BOTH in the same PR, or
  a follow-up PR will be needed (cf. PR #2494 → #2504 settings-nav chevron). AC5
  encodes this.
- **Test file path must match the vitest glob.** New component test goes under
  `apps/web-platform/test/` (glob `test/**/*.test.tsx`, happy-dom). A co-located
  `components/**/*.test.tsx` is silently never run.
- **Runner is vitest, not bun.** `bunfig.toml` `pathIgnorePatterns = ["**"]` blocks
  bun discovery; use `./node_modules/.bin/vitest run`.

## Notes

- Bug shipped via PR #4810 (single nav rail) and was partially patched by #4833
  (which added the `nav-states-shell.e2e.ts` VRT gate and fixed two other #4810
  layout bugs). This plan fixes the remaining overflow + chevron-alignment defects;
  reuse the #4833 VRT gate for AC1/AC4 verification.
- AI tools used in research: Claude Code (repo-research, render-path trace).
