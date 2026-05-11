---
type: fix
status: draft
branch: feat-one-shot-fix-settings-sidebar-gap-and-header-alignment
worktree: .worktrees/feat-one-shot-fix-settings-sidebar-gap-and-header-alignment/
requires_cpo_signoff: false
---

# fix: Settings sidebar gap on close and header misalignment

## Enhancement Summary

**Deepened on:** 2026-05-11
**Sections enhanced:** Overview, Hypotheses, Implementation Phases, Acceptance Criteria, Risks, Test Scenarios
**Research vectors:** prior settings-nav alignment plans (#2494, #2504), `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md` learning, Tailwind v4.1 docs, existing test contract in `test/settings-sidebar-collapse.test.tsx`, `app/(dashboard)/layout.tsx` main-sidebar geometry, `app/globals.css` token surface.

### Key Improvements

1. **Geometric pre-computation grounded.** The prior fix (#2504) left a residual 2 px y-delta documented in `knowledge-base/project/plans/2026-04-17-fix-settings-nav-expanded-chevron-alignment-plan.md` ("main nav chevron y ≈ 34 px, settings nav chevron y ≈ 32 px post-fix, delta ≤ 2 px"). This plan's `min-h-7` proposal raises the settings header row to 28 px → both chevron centers at 34 px → delta target = 0 px.
2. **Tailwind v4 verification.** The codebase uses `tailwindcss@^4.1.0` (`apps/web-platform/package.json`). Tailwind v4's unified spacing scale generates `min-h-7` as `min-height: calc(var(--spacing) * 7) = 1.75rem = 28px` — no `tailwind.config.*` extension required. Safe to use.
3. **Test selector hardened.** Initial draft used `screen.getByText("Settings", { selector: "h2" })`. Replaced with `screen.getByLabelText("Collapse settings nav").parentElement` because the existing test file already imports and uses that label-based query, avoiding a CSS-text-transform pitfall (`uppercase` class affects visual rendering, not `textContent`, but consistent test style is safer).
4. **Pixel-coord verification mandated in QA.** Per the prior plan's lesson, screenshots alone read as "looks aligned"; `getBoundingClientRect()` deltas in `browser_evaluate` provide quantitative evidence. Acceptance criterion now requires `yDelta ≤ 1` numeric measurement in the PR body.
5. **Content-padding-transition smoothness deferred to QA.** The conditional `md:pl-8` swap is instantaneous while width transitions over 200 ms. If QA reveals visual jank, a `transition-[padding]` fallback is enumerated in Risks rather than pre-emptively shipped (YAGNI — pixel jank may be imperceptible).

### New Considerations Discovered

- The bug screenshot was captured AFTER #2504 landed (which already brought delta to ≤ 2 px). The user is reporting the residual 2 px, not regression. Plan accordingly targets 0 px, not "restore #2504 behavior".
- The collapsed-state nav guard test is defensive but does NOT trigger any code change because `md:border-r-0` is already present. It's a regression tripwire for future edits.
- Light-theme tokenization (#3308) was the only intervening change since #2504 — it changed colors only, not layout. No structural drift to undo.

## Overview

Two visual regressions on `/dashboard/settings/*` routes:

1. **Gap on close.** When the settings sidebar is collapsed (`md:w-0`), a visible gap/margin persists between the main app sidebar and the content area instead of the layout collapsing cleanly to zero. The most likely source is the content area's `md:px-10` (40px) left padding combined with the absolute expand-chevron at `left-2 top-5` — when the nav is at width 0, the content's left padding is fully exposed as visible empty space, reading as a "margin/gap". Secondary suspect: the base `border-r` may not be fully suppressed by `md:border-r-0` in every browser due to Tailwind class ordering.

2. **Header misalignment.** The `SETTINGS` header (`<h2>` at `text-xs`, line-height 16px) and the main app sidebar's `Soleur` brand (`<span>` at `text-lg`, line-height 28px) both sit inside `py-5` containers with `flex items-center`, but the row heights differ by 12px because the content height differs (16 vs 28). With `items-center`, the SETTINGS text-center lands ~6px above the Soleur text-center. The two `<` chevrons are both `h-6 w-6`, so they each center on their parent row; the row-height delta drags the settings chevron up by ~2-6px relative to the main nav chevron.

Both bugs are pure CSS/layout — no behavior, data, or state changes. Scope is exclusively `apps/web-platform/components/settings/settings-shell.tsx` plus matching test updates.

## User-Brand Impact

**If this lands broken, the user experiences:** a visibly misaligned settings sidebar header and a residual margin on close, which signals "unfinished UI" on a paid surface (settings/billing) where polish disproportionately drives trust.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — pure-CSS layout fix, no credential/data/payment surface touched.

**Brand-survival threshold:** none

Reason for `none`: the fix touches one client component file (`settings-shell.tsx`) with zero auth/data/payment/PII code paths. The sensitive-path regex (`plugins/soleur/skills/preflight/SKILL.md` Check 6 §6.1) does not match `components/settings/settings-shell.tsx`.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (from feature description) | Reality (verified in codebase) | Plan response |
|---|---|---|
| "Gap on close" caused by transition CSS | Current collapsed class set `md:w-0 md:overflow-hidden md:border-r-0` already targets width and border; transition is on `[width]` only. Most likely visible gap source is content `md:px-10` exposure, NOT the nav itself. | Plan addresses content-side padding compaction in collapsed state AND verifies nav-side border/width are fully zero via integration test. |
| "Header misalignment" caused by spacing tokens | Both containers use `py-5`. Misalignment driven by row-height delta from font-size differential (`text-xs` 12px vs `text-lg` 18px). | Plan adds `min-h-7` (28px) to the settings header `<div>` to match the main sidebar's brand row height. |
| "Investigate slide/transition CSS" | Transition is `md:transition-[width] md:duration-200 md:ease-out` — correct and matches main sidebar. | No change to transition tokens. |
| Existing test at `test/settings-sidebar-collapse.test.tsx` enforces `py-5` on nav and `left-2 top-5 z-10 h-6 w-6` on expand button. | Confirmed. Test must continue to pass. | Plan preserves `py-5` and the expand-button locked classes. |

## Files to Edit

- `apps/web-platform/components/settings/settings-shell.tsx` — fix both bugs (see Implementation).
- `apps/web-platform/test/settings-sidebar-collapse.test.tsx` — extend with two new assertions: (a) header row has `min-h-7`, (b) when collapsed, content area's left padding is reduced to a token that matches the expand-chevron's `left-2` anchor.

## Files to Create

None.

## Implementation Phases

### Phase 1 — Failing tests (TDD RED)

Add to `apps/web-platform/test/settings-sidebar-collapse.test.tsx` inside the existing `describe("collapse button alignment with main nav chevron (expanded state)")` block:

```tsx
it("settings header row matches main sidebar brand row height (min-h-7)", () => {
  render(<SettingsShell><div>content</div></SettingsShell>);
  // Use the existing label-based query the test file already relies on,
  // then walk to the wrapping <div> (the header row).
  const collapseBtn = screen.getByLabelText("Collapse settings nav");
  const headerRow = collapseBtn.parentElement;
  expect(headerRow).not.toBeNull();
  expect(headerRow).toHaveClass("min-h-7");
  // Also lock in the row still flex-centers the chevron + heading.
  expect(headerRow).toHaveClass("flex", "items-center", "justify-between");
});
```

**Why `min-h-7` and not `h-7`:** `min-h-7` (28 px) sets a floor without preventing growth if a future translation widens the heading line. Tailwind v4.1 generates this as `min-height: calc(var(--spacing) * 7) = 1.75rem = 28 px` directly from the unified spacing scale — no `tailwind.config.*` extension required. Verified: `apps/web-platform/package.json` pins `tailwindcss@^4.1.0` and `@tailwindcss/postcss@^4.2.1`.

Add a new `describe` block for the close-state layout-collapse contract:

```tsx
describe("content area collapses cleanly when sidebar is closed", () => {
  it("collapsed nav has zero rendered width contribution (no border, no width, overflow hidden)", async () => {
    render(<SettingsShell><div>content</div></SettingsShell>);
    await userEvent.click(screen.getByLabelText("Collapse settings nav"));
    const navEl = document.querySelector("nav");
    expect(navEl).not.toBeNull();
    // Collapsed-state utility tokens.
    expect(navEl?.className).toMatch(/\bmd:w-0\b/);
    expect(navEl?.className).toMatch(/\bmd:overflow-hidden\b/);
    expect(navEl?.className).toMatch(/\bmd:border-r-0\b/);
    // Open-state padding tokens (px-4 py-5) MUST NOT be present when collapsed.
    expect(navEl?.className).not.toMatch(/\bpx-4\b/);
  });

  it("content area uses a reduced left padding when sidebar is collapsed", async () => {
    render(<SettingsShell><div>content</div></SettingsShell>);
    await userEvent.click(screen.getByLabelText("Collapse settings nav"));
    // The content area is the .relative.flex-1 sibling of <nav>.
    const expandBtn = screen.getByLabelText("Expand settings nav");
    const contentArea = expandBtn.parentElement;
    expect(contentArea).not.toBeNull();
    // When collapsed, the content area should drop md:px-10 in favor of a
    // token that visually closes the gap left by the zero-width nav.
    // We assert the presence of the collapsed-state token rather than the
    // absence of md:px-10, because the open state still uses md:px-10.
    expect(contentArea?.className).toMatch(/\bmd:pl-(?:6|8)\b/);
  });
});
```

Run `bun test apps/web-platform/test/settings-sidebar-collapse.test.tsx`. New assertions MUST fail; existing assertions MUST still pass.

### Phase 2 — Fix header alignment (Bug 2)

In `apps/web-platform/components/settings/settings-shell.tsx`, change the header `<div>` (currently line 41):

```diff
- <div className="mb-4 flex items-center justify-between">
+ <div className="mb-4 flex min-h-7 items-center justify-between">
```

`min-h-7` (28px) matches the implicit row height of the main app sidebar's brand `<span class="text-lg">Soleur</span>` (text-lg line-height = 1.75rem = 28px). With `items-center`, both rows now center their content at the same y-offset from `py-5`.

### Phase 3 — Fix gap on close (Bug 1)

In `apps/web-platform/components/settings/settings-shell.tsx`, change the content area's padding (currently line 104):

```diff
- <div className="relative flex-1 px-4 py-10 pb-20 md:px-10 md:pb-10">
+ <div className={`relative flex-1 px-4 py-10 pb-20 md:py-10 md:pb-10 ${settingsCollapsed ? "md:pl-8 md:pr-10" : "md:px-10"}`}>
```

`md:pl-8` (32px) is the smallest token that still clears the absolutely-positioned expand chevron (`left-2 top-5 h-6 w-6` = chevron right edge at 8 + 24 = 32px). When the sidebar is OPEN, the content keeps its current `md:px-10` (40px symmetric padding); when CLOSED, the left padding tightens to 32px so the layout reads as "collapsed cleanly" while still giving the chevron breathing room.

### Phase 4 — Verify nav-side close-state already collapses (Bug 1 secondary)

The current collapsed class set `${settingsCollapsed ? "md:w-0 md:overflow-hidden md:border-r-0" : "w-48 px-4 py-5"}` already drops `border-r` to 0 and width to 0. The Phase-1 RED test asserts these utilities are present. No code change required — but the test guard is added to prevent regression if anyone removes `md:border-r-0` later.

### Phase 5 — Run all updated tests (TDD GREEN)

`bun test apps/web-platform/test/settings-sidebar-collapse.test.tsx` → all green.

### Phase 6 — Visual QA via Playwright MCP

Per `cq-when-a-plan-addresses-alignment-of-a` (alignment fixes must verify BOTH toggle states), capture two screenshots at `/dashboard/settings` under each combination:

1. Main sidebar OPEN + settings sidebar OPEN.
2. Main sidebar OPEN + settings sidebar CLOSED.
3. Main sidebar COLLAPSED + settings sidebar OPEN.
4. Main sidebar COLLAPSED + settings sidebar CLOSED.

For each, verify:
- (Alignment) The `<` chevron in the settings header and the `<` chevron in the main app sidebar header sit on the same y-baseline (within ±1 px).
- (Gap) When settings is CLOSED, the content area's leftmost element (expand chevron) sits ~8 px from the previous nav edge — no >32 px dead zone.

**Quantitative evidence required** (per `knowledge-base/project/plans/2026-04-17-fix-settings-nav-expanded-chevron-alignment-plan.md` precedent — "looks aligned" screenshots are insufficient). Use `mcp__playwright__browser_evaluate` to capture pixel deltas:

```javascript
() => {
  const mainBtn = document.querySelector('aside button[aria-label*="sidebar" i]');
  const settingsBtn = document.querySelector('nav button[aria-label="Collapse settings nav"]');
  if (!mainBtn || !settingsBtn) return { error: "button(s) not found", mainBtn: !!mainBtn, settingsBtn: !!settingsBtn };
  const m = mainBtn.getBoundingClientRect();
  const s = settingsBtn.getBoundingClientRect();
  return {
    mainY: m.top + m.height / 2,
    settingsY: s.top + s.height / 2,
    yDelta: Math.abs((m.top + m.height / 2) - (s.top + s.height / 2)),
  };
}
```

**AC:** `yDelta ≤ 1`. Record `{ mainY, settingsY, yDelta }` in the PR body for each toggle-state combination where both chevrons are visible (combinations 1 + 3).

If `yDelta > 1`, escalate — the `min-h-7` fix did not normalize to the live font/line-height combo. Recovery: switch to absolute-positioning the settings collapse chevron (mirror the expand-chevron approach at `left-N top-5`) rather than fighting flex-row geometry.

Attach screenshots to the PR alongside the numeric deltas.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/components/settings/settings-shell.tsx` header row has `min-h-7 flex items-center justify-between`.
- [ ] Content-area `<div>` uses conditional `md:pl-8 md:pr-10` when `settingsCollapsed` and `md:px-10` otherwise; `py-10` / `md:pb-10` unchanged.
- [ ] All existing assertions in `apps/web-platform/test/settings-sidebar-collapse.test.tsx` continue to pass.
- [ ] Three new assertions added (min-h-7 on header row, collapsed-state nav guard, collapsed-state content-padding guard) all pass.
- [ ] `bun test apps/web-platform/test/settings-sidebar-collapse.test.tsx` → green.
- [ ] `bunx tsc --noEmit` from `apps/web-platform/` → no new errors.
- [ ] Visual QA screenshots attached to the PR for the four toggle-state combinations enumerated in Phase 6.
- [ ] Quantitative `yDelta` measurements via `mcp__playwright__browser_evaluate` recorded in the PR body for combinations 1 + 3 (both states where both chevrons are visible). `yDelta ≤ 1 px`.
- [ ] Screenshot inspection confirms: (a) settings `<` chevron and main app `<` chevron land on the same y-baseline (±1 px, corroborated by the numeric `yDelta`), (b) when settings sidebar is closed, the content area collapses cleanly with no visible gap >32 px between the main app sidebar's right edge and the expand chevron's left edge.

### Post-merge (operator)

None — pure client-side UI fix, no migration, no infra, no Doppler write.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned an empty list (zero open code-review issues touch `settings-shell.tsx` or the settings-sidebar test).

## Hypotheses

1. **Bug 1 root cause (highest confidence):** content area's symmetric `md:px-10` is fully exposed when the nav is `md:w-0`, reading as a "gap/margin" to the user. Conditional collapse-state padding fixes this.
2. **Bug 1 secondary (low confidence, mitigated by test):** in some browsers or due to Tailwind class-ordering edge cases, the base `border-r` could outlast `md:border-r-0`. The Phase-1 RED test asserts both utility classes are present, providing regression coverage.
3. **Bug 2 root cause (high confidence):** font-size differential drives row-height delta; `flex items-center` then centers in different-height boxes, producing the 2 px vertical drift residual from PR #2504 visible in the screenshot. `min-h-7` normalizes the row height to match `text-lg`'s natural line-height (28 px).

### Research Insights

**Geometric computation (Bug 2):**

Per `app/(dashboard)/layout.tsx:250` the main sidebar brand row uses `px-5 py-5` (expanded) or `px-2 py-5` (collapsed); inside, `<span class="text-lg">Soleur</span>` (line-height = 1.75 rem = 28 px) and a `h-6 w-6` collapse button. With `flex items-center`, the row height = `max(28, 24) = 28 px`. Chevron y-center = `20 (py-5) + 14 (28/2) = 34 px`.

Settings header at `apps/web-platform/components/settings/settings-shell.tsx:41`: `<h2 class="text-xs ...">Settings</h2>` (text-xs line-height = 1 rem = 16 px) + `h-6 w-6` button. Row height = `max(16, 24) = 24 px`. Chevron y-center = `20 (py-5) + 12 (24/2) = 32 px`. **Residual delta = 2 px** — matches what PR #2504's plan recorded as the post-fix tolerance.

With `min-h-7` (28 px) on the settings header row, the row floor rises to 28 px → chevron y-center = `20 + 14 = 34 px` → **target delta = 0 px**.

**Prior precedent (PR #2494 + PR #2504):**

PR #2494 fixed the **collapsed-state** expand chevron (`>`) by absolute-positioning it at `left-2 top-5 z-10 h-6 w-6` inside the content wrapper. This bypassed flex-row geometry entirely. PR #2504 then fixed the **expanded-state** collapse chevron (`<`) by shrinking the settings `<nav>` padding from `py-10` to `py-5`. Both fixes landed; the current 2 px residual is the limit of what `py-5` alone could achieve.

Reference: `knowledge-base/project/learnings/2026-04-17-alignment-fixes-must-verify-both-toggle-states.md` — "A fix for the collapsed state does not carry over to the expanded state because the two branches of the conditional `className` render different DOM structures with different parent geometry." Applied here: both states are exercised in Phase 6 QA.

**Tailwind v4 spacing semantics (Bug 2 implementation):**

`apps/web-platform/package.json` pins `tailwindcss@^4.1.0` + `@tailwindcss/postcss@^4.2.1`. Tailwind v4 unifies the spacing scale: `min-h-N` generates `min-height: calc(var(--spacing) * N)`. `--spacing` defaults to `0.25rem` (4 px), so `min-h-7` = `28 px`. The token is generated on-demand by `@tailwindcss/postcss` — no `tailwind.config.*` extension required. Verified the codebase already uses numeric `min-h-N` elsewhere (`apps/web-platform/components/chat/conversations-rail.tsx`, `kb/pdf-preview.tsx`, etc., all using `min-h-0`).

**Content-area conditional padding (Bug 1 implementation):**

The `md:pl-8` choice (32 px) is calibrated to the expand chevron's effective right edge: `left-2` (8 px) + `h-6 w-6` (24 px) = `32 px`. Any reduction below 32 px would clip the chevron's hover-target. The right padding stays at `md:pr-10` for content-side symmetry.

## Risks

- **Wrong root cause for Bug 1.** The "gap" could actually be a 1 px `border-r` rendering artifact (border-box behavior at `width:0`). The Phase-1 test asserts `md:border-r-0` is present; if QA still shows a 1 px line, fold in a `border-0` (not just `border-r-0`) override in the collapsed branch. Recovery: trivial — single-token addition.
- **`min-h-7` interaction with `mb-4`.** `min-h-7` raises the header row from 24 px to 28 px (Δ = 4 px). The settings nav items (the `<ul class="space-y-1">`) sit below the header `<div class="mb-4 ...">`, so they shift down by 4 px. The first nav item was previously at `y = 20 + 24 + 16 = 60 px`; after fix at `y = 20 + 28 + 16 = 64 px`. This is an intentional vertical alignment with the main sidebar's content (which starts at `y = 20 + 28 = 48 px + nav padding`). Mitigation: visual QA in Phase 6 confirms the shift is imperceptible. If QA flags it, swap `min-h-7` for `min-h-[1.75rem]` (identical computed value, more explicit intent) or remove `mb-4` and use `mt-4` on the nav `<ul>` instead.
- **Conditional content-padding may flicker during the 200 ms width transition.** The width transition is on `[width]` (200 ms) but the padding swap is instant. Visual flicker possible. If observed in QA, add `md:transition-[padding,width] md:duration-200 md:ease-out` on the content `<div>` to match. Not pre-emptively shipped — YAGNI; only add if QA observes jank.
- **Test selector fragility (resolved).** Initial draft used `screen.getByText("Settings", { selector: "h2" })`. Replaced with `screen.getByLabelText("Collapse settings nav").parentElement` because (a) the existing test file already uses the label-based query, (b) the heading text is wrapped in a `uppercase` utility but `textContent` remains mixed-case, (c) future i18n could replace "Settings" but `aria-label="Collapse settings nav"` is the contract surface.
- **`getBoundingClientRect()` in JSDOM returns zeros.** The numeric `yDelta` assertion is Playwright-only (real browser). The unit test asserts only the presence of `min-h-7`, NOT the computed pixel-level alignment — JSDOM cannot measure it. This is by design: classname tests are regression gates; Playwright is the alignment source of truth. Recorded in the prior plan (`2026-04-17-fix-settings-nav-expanded-chevron-alignment-plan.md`) as the established convention.
- **`flex justify-between` with one visible child.** When the main app sidebar is collapsed, the `<span>Soleur</span>` is `md:hidden`, leaving only the chevron button in the brand row. With `justify-between` and one flex child, the child aligns to the start of the row. The settings sidebar's `<` chevron sits in a `justify-between` row where both children are visible (h2 + button), so the button aligns to the end. The two chevrons therefore land at DIFFERENT x-positions when the main sidebar is collapsed. This is out-of-scope (the bug report is vertical alignment) but flagged so the QA evaluator does not mis-read horizontal offset as a regression.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is complete (`threshold: none` with stated reason).
- Alignment fixes must verify BOTH toggle states (open + closed) per the existing learning at `knowledge-base/project/learnings/2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`. Phase 6 QA explicitly covers four state combinations, not just the closed state from the bug report.
- This file edits a component whose alignment contract was hardened twice before (PR #2494, PR #2504). Re-read the existing test contract before editing — every locked-down assertion in `test/settings-sidebar-collapse.test.tsx` is a regression tripwire from a prior fix. Do NOT relax those assertions to make new ones pass.
- The new `min-h-7` token is `1.75rem = 28px`, which matches `text-lg` line-height exactly. Do NOT substitute `h-7` (fixed height) — `min-h-7` preserves the row's ability to grow if a future translation/copy change widens the line.

## Domain Review

**Domains relevant:** Engineering (current task topic — no separate leader spawn per `pdr-do-not-route-on-trivial-messages-yes` parallel).

No cross-domain leaders spawned: this is a 2-line CSS fix with zero architectural, product-strategy, legal, marketing, or financial implications. Product domain assessed as ADVISORY (modifies existing component, no new pages/components, no new flows) — mechanical escalation does NOT fire because no new file is created under `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

Per `plan` skill Step 2.5 Step 2 "On ADVISORY → If in pipeline/subagent context: auto-accept, write Product/UX Gate subsection with Tier: advisory, Decision: auto-accepted (pipeline), proceed silently."

#### Findings

No content review needed — fix touches no copy, no labels, no flows. Visual QA in Phase 6 substitutes for a wireframe pass (the design exists; the bug is a pixel-level deviation from it).

## Test Scenarios

| Scenario | State | Expected |
|---|---|---|
| Header alignment open | settings open + main app open | `<` chevron in settings header and `<` chevron in main app sidebar share the same y-baseline (±1px). |
| Header alignment open + main collapsed | settings open + main app collapsed | Same as above — main app collapse does not affect settings header position. |
| Gap on close | settings closed | Content area's leftmost rendered element (expand `>` chevron) sits ≤32px from the main app sidebar's right edge. No visible >32px dead zone. |
| Test guard: collapsed-state utilities | DOM after collapse click | `<nav>` element has `md:w-0`, `md:overflow-hidden`, `md:border-r-0` and lacks `px-4`. |
| Test guard: min-h-7 on header row | DOM at initial render | Header `<div>` has `min-h-7` class. |
| Test guard: collapsed-state content padding | DOM after collapse click | Content `<div>` has `md:pl-8` (or equivalent reduced left padding). |
| Existing alignment contract | DOM after collapse click | All assertions in the existing `expand button alignment` describe block continue to pass. |
| Existing nav py-5 contract | DOM at initial render | `<nav>` element retains `py-5` (not `py-10`). |

## Definition of Done

- Both bugs visibly resolved in Playwright screenshots across all four toggle-state combinations.
- All `bun test apps/web-platform/test/settings-sidebar-collapse.test.tsx` assertions green.
- `bunx tsc --noEmit` from `apps/web-platform/` passes.
- PR description includes before/after screenshots for at least two toggle-state combinations (settings-open and settings-closed).
- PR uses `Closes #N` only if a tracking issue exists; otherwise `Ref` to the originating screenshot/conversation.
