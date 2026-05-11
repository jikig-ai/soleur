---
type: fix
status: draft
branch: feat-one-shot-fix-settings-sidebar-gap-and-header-alignment
worktree: .worktrees/feat-one-shot-fix-settings-sidebar-gap-and-header-alignment/
requires_cpo_signoff: false
---

# fix: Settings sidebar gap on close and header misalignment

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
  const headingEl = screen.getByText("Settings", { selector: "h2" });
  // The <div> wrapping the <h2> + collapse button is the header row.
  const headerRow = headingEl.parentElement;
  expect(headerRow).not.toBeNull();
  expect(headerRow).toHaveClass("min-h-7");
});
```

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
- (Alignment) The `<` chevron in the settings header and the `<` chevron in the main app sidebar header sit on the same y-baseline (within ±1px).
- (Gap) When settings is CLOSED, the content area's leftmost element (expand chevron) sits ~8px from the previous nav edge — no >32px dead zone.

Attach screenshots to the PR.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/components/settings/settings-shell.tsx` header row has `min-h-7 flex items-center justify-between`.
- [ ] Content-area `<div>` uses conditional `md:pl-8 md:pr-10` when `settingsCollapsed` and `md:px-10` otherwise; `py-10` / `md:pb-10` unchanged.
- [ ] All existing assertions in `apps/web-platform/test/settings-sidebar-collapse.test.tsx` continue to pass.
- [ ] Three new assertions added (min-h-7 on header row, collapsed-state nav guard, collapsed-state content-padding guard) all pass.
- [ ] `bun test apps/web-platform/test/settings-sidebar-collapse.test.tsx` → green.
- [ ] `bunx tsc --noEmit` from `apps/web-platform/` → no new errors.
- [ ] Visual QA screenshots attached to the PR for the four toggle-state combinations enumerated in Phase 6.
- [ ] Screenshot inspection confirms: (a) settings `<` chevron and main app `<` chevron land on the same y-baseline (±1px), (b) when settings sidebar is closed, the content area collapses cleanly with no visible gap >32px between the main app sidebar and content.

### Post-merge (operator)

None — pure client-side UI fix, no migration, no infra, no Doppler write.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned an empty list (zero open code-review issues touch `settings-shell.tsx` or the settings-sidebar test).

## Hypotheses

1. **Bug 1 root cause (highest confidence):** content area's symmetric `md:px-10` is fully exposed when the nav is `md:w-0`, reading as a "gap/margin" to the user. Conditional collapse-state padding fixes this.
2. **Bug 1 secondary (low confidence, mitigated by test):** in some browsers or due to Tailwind class-ordering edge cases, the base `border-r` could outlast `md:border-r-0`. The Phase-1 RED test asserts both utility classes are present, providing regression coverage.
3. **Bug 2 root cause (high confidence):** font-size differential drives row-height delta; `flex items-center` then centers in different-height boxes, producing the 2-6px vertical drift visible in the screenshot. `min-h-7` normalizes the row height to match `text-lg`'s natural line-height (28px).

## Risks

- **Wrong root cause for Bug 1.** The "gap" could actually be a 1px `border-r` rendering artifact (border-box behavior at `width:0`). The Phase-1 test asserts `md:border-r-0` is present; if QA still shows a 1px line, fold in a `border-0` (not just `border-r-0`) override in the collapsed branch. Recovery: trivial — single-token addition.
- **`min-h-7` too aggressive.** If `min-h-7` (28px) interacts oddly with the existing `mb-4` to push the nav items down 6px, the menu may shift. Mitigation: visual QA in Phase 6 covers this. If observed, swap to `h-7` directly or recalibrate to `min-h-[28px]`.
- **Conditional content-padding may shift content during transition.** The width transition is on `[width]` (200ms) but the padding swap is instant. Visual flicker possible. If observed in QA, add `transition-[padding]` on the content area to match. Acceptance criterion already requires Phase 6 QA.
- **Test fragility on text matcher.** `screen.getByText("Settings", { selector: "h2" })` depends on the rendered text "Settings" (mixed case in the JSX, uppercased via `uppercase` utility). The matcher uses the DOM text content (mixed case) — verified by reading the JSX. If a future commit changes the label, both the component and the test must update together.

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
