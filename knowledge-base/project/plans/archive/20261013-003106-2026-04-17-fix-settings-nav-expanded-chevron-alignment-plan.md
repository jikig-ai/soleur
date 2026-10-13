# Fix: Align Settings sub-nav expanded-state collapse chevron with main nav chevron

**Date:** 2026-04-17
**Type:** fix (UI alignment)
**Branch:** `feat-one-shot-settings-nav-chevron-align`
**Worktree:** `.worktrees/feat-one-shot-settings-nav-chevron-align/`
**Related:** PR #2494 (commit `0badb928`) fixed the **collapsed-state** expand chevron. This plan addresses the **expanded-state** collapse chevron that is still misaligned.

## Enhancement Summary

**Deepened on:** 2026-04-17
**Sections enhanced:** Overview, Approach, Implementation Phases (test strategy), Sharp Edges, Acceptance Criteria
**Research applied:** direct geometric analysis, testing-library best-practice review, AGENTS.md cross-reference (directional ambiguity gate)

### Key Improvements

1. **Geometric pre-verification added** — computed y-center math (main nav chevron y ≈ 34 px, settings nav chevron y ≈ 32 px post-fix) shows the fix puts both chevrons within the ≤ 2 px AC tolerance; risk flagged if the "Soleur" brand line-height grows.
2. **Directional ambiguity acknowledged** — the user's phrasing "different x-positions" is technically X-axis but Approach A fixes Y-axis (consistent with PR #2494 precedent). Flagged as a verification checkpoint with Playwright before shipping.
3. **Test strategy hardened** — added `getBoundingClientRect()` JSDOM limitation note + Playwright-driven pixel assertion as the source of truth for actual alignment; classname tests become lightweight regression gates, not the alignment contract itself.
4. **New "Geometric Model" subsection** documents the pixel math so future planners don't have to re-derive it.

### New Considerations Discovered

- JSDOM returns `DOMRect { x:0, y:0, width:0, height:0 }` for every element — classname-only tests CANNOT prove actual alignment. Playwright screenshot + `boundingBox()` is the only reliable alignment contract.
- The main nav header has `safe-top` on its wrapper; the settings `<nav>` does not. On desktop both resolve to 0 so the fix holds; on an iPad in portrait (md breakpoint), the main nav gains `env(safe-area-inset-top)` while settings does not — a latent 20-50 px divergence that this plan does NOT address (out of scope, but documented).
- If Tailwind's `content-[]` tracking changes or the "Soleur" text font scales up, the geometric match degrades. A Playwright bounding-box test (see Phase 3) is the durable guardrail.

## Overview

When the user is on a Team Settings page and **both** the main nav sidebar AND the Settings sub-nav sidebar are expanded, two `<` (collapse) chevrons are visible:

- **Main nav** chevron: right edge of the 224 px wide main sidebar (`md:w-56`), inside a header wrapper with `px-5 py-5`.
- **Settings sub-nav** chevron: right edge of the 192 px wide settings sidebar (`w-48`), inside a `<nav>` with `px-4 py-10` and an inner flex row with `mb-4` and no internal vertical padding.

Because the main nav header uses `py-5` (20 px top padding) while the settings `<nav>` uses `py-10` (40 px top padding), the two chevron buttons sit on **different horizontal rows** — the settings chevron is roughly 20 px lower than the main nav chevron. Users reading across the top of the screen see the two `<` icons staggered instead of aligned on a single y-row.

The geometry of the buttons themselves already matches (both are `h-6 w-6` with `h-4 w-4` svg, same `rounded` / hover styles) — only the vertical anchor is wrong. The fix is a 1-token change to the settings `<nav>` vertical padding to reuse the main nav's `py-5` row origin, with an accompanying adjustment so existing content (the "Settings" label row + tab list) keeps its intended spacing.

### Directional ambiguity — "horizontally" vs. "different x-positions"

The user's phrasing is ambiguous between two failure modes and AGENTS.md `idea-refinement.directional-ambiguity-gate` requires confirmation. In pipeline (auto) mode we pick the interpretation consistent with precedent and flag it for Playwright verification before shipping:

- **Interpretation A (chosen):** "aligned horizontally" = on the same horizontal line (same y-coordinate). The symptom "different x-positions" is interpreted as a loose visual description of y-shifted chevrons (a y-delta in adjacent columns visually reads as an x-stagger when scanning top-to-bottom). PR #2494 fixed the collapsed-state chevron along the Y-axis; treating this follow-up the same way is the lowest-risk parity move.
- **Interpretation B (rejected in pipeline):** "same x-position" literally. This would require the settings sub-nav to be the same width as the main sidebar (224 px vs current 192 px), or the chevrons to overlay the column boundary. Both are larger design changes requiring a UX-gated spec. If Playwright screenshots in Phase 3 show that y-alignment does not resolve the user's complaint, escalate to Interpretation B via a brainstorm pass, not an in-pipeline fix.

**Verification checkpoint:** If Phase 3 screenshots still look "staggered" to the user after the fix, STOP and re-open the direction with the user. Do not keep pushing geometric tweaks.

### Geometric model (y-center math)

Both sidebars are siblings under `<div className="flex h-dvh flex-col md:flex-row">` and start at viewport y = 0 on md+. The chevron y-center is derived from parent padding + `items-center` row height.

| Sidebar            | Parent padding | Tallest row child                   | Row height (approx) | Chevron center y |
| ------------------ | -------------- | ----------------------------------- | ------------------- | ---------------- |
| Main nav (expanded)| `py-5` (20 px) | "Soleur" span at `text-lg` (~28 px) | 28 px               | 20 + 14 = 34 px  |
| Settings nav (today)| `py-10` (40 px)| `h-6 w-6` button (24 px)            | 24 px               | 40 + 12 = 52 px  |
| Settings nav (after)| `py-5` (20 px) | `h-6 w-6` button (24 px)            | 24 px               | 20 + 12 = 32 px  |

**Delta today:** |34 − 52| = 18 px (visibly misaligned).
**Delta after fix:** |34 − 32| = 2 px (within AC tolerance).

**Risk:** if the "Soleur" text-lg line-height resolves above ~28 px on a particular browser/font stack, row height grows and the delta can hit 4-6 px. The Playwright bounding-box assertion in Phase 3 catches this before merge.

### Why this wasn't caught in PR #2494

PR #2494 targeted the collapsed-state (expand) chevron. The fix there adopted the KB layout precedent: absolute-position the expand button inside the content area at `top-5` to match main nav's header y-origin. That change did not touch the expanded-state `<nav>` sidebar, which still carries the original `py-10` y-origin — so the expanded-state chevron remains misaligned with both (a) the main nav chevron and (b) the collapsed-state chevron the previous PR just aligned.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (from user report)                                                                       | Codebase reality                                                                                                                                                                               | Plan response                                                                                                                                                  |
| --------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "Collapse chevron in the Team Settings sidebar is not aligned horizontally with the main nav chevron." | Verified at `apps/web-platform/components/settings/settings-shell.tsx:36-55`. `<nav>` wrapper uses `py-10`; main nav at `apps/web-platform/app/(dashboard)/layout.tsx:231` uses `py-5`.         | Align the settings `<nav>` header's chevron y-origin to `py-5` (see Approach A below). KB layout uses `pt-4` for its header — deliberately NOT the reference here because the user asked for parity with main nav, not KB. |
| "PR #2494 fixed it."                                                                                | Verified via `git show 0badb928`: PR #2494 changed **only** the collapsed-state expand button (inside the content area). The expanded-state `<nav>` sidebar was untouched.                      | Treat this as a distinct, follow-up fix. Do not alter the PR #2494 code path.                                                                                  |
| "Button icon sizes look the same, only position is off."                                            | Confirmed: both buttons are `h-6 w-6` with `h-4 w-4` svg (lines 49 and 247). The delta is purely the vertical anchor (`py-10` vs `py-5`).                                                       | No icon-size change required. Adjust only the parent vertical padding and inner wrapper.                                                                     |

## Files to Edit

- `apps/web-platform/components/settings/settings-shell.tsx` — adjust the expanded-state `<nav>` vertical padding so its header row lands on the same y-row as the main nav header row.
- `apps/web-platform/test/settings-sidebar-collapse.test.tsx` — add an alignment-contract test for the expanded state (mirrors the existing collapsed-state tests added in PR #2494).

## Files to Create

None.

## Open Code-Review Overlap

Ran `gh issue list --label deferred-scope-out --state open` and grepped for `settings-shell`, `settings-sidebar`, `settings/` paths. **None** of the 16 open scope-outs touch this file. No fold-in or defer decisions needed.

## Approach

### Approach A (chosen): shrink the expanded `<nav>` top padding to match main nav

Change the expanded-state `<nav>` class from `w-48 px-4 py-10` to `w-48 px-4 py-5`. This aligns the top of the "Settings" header row (and its chevron) to y ≈ 20 px, matching the main nav header row's y ≈ 20 px.

**Pros:**

- 1-token diff (`py-10` → `py-5`).
- Uses the main nav's exact y-origin as the reference — parity is direct, not inferred.
- No new absolute-positioning gymnastics; the chevron stays in natural document flow inside the existing flex row.
- Existing hover/click targets and a11y labels are untouched.

**Cons / trade-offs:**

- Reduces the top spacing above the "Settings" section heading by 20 px. The section still reads as distinct because the heading sits in its own `<div className="mb-4 flex items-center justify-between">` row with `mb-4` bottom margin.
- If a designer wanted extra breathing room above the heading, that decision is lost. Counter: the user's report explicitly asks for alignment with main nav — the reference design is main nav's `py-5`.

### Approach B (rejected): absolute-position the expanded collapse chevron inside the content area

Mirror PR #2494's technique: remove the chevron from the `<nav>` header row and render it absolute-positioned at `top-5 right-<X>` anchored to a `relative` parent.

**Rejected because:**

- In the expanded state the chevron sits **inside the `<nav>` column**, not in the content area. The `<nav>` is the parent of the "Settings" heading. Ripping the chevron out of the header row for purely cosmetic y-alignment adds complexity (z-index, focus order, screen-reader reading order change — the chevron would come **after** the Settings tab list in DOM order).
- PR #2494 used absolute positioning only because the collapsed state hides `<nav>` entirely (`md:w-0`), so the expand button must live in the content area. That constraint doesn't apply here.

### Approach C (rejected): shift just the chevron row with `mt-[-20px]` or a row-specific offset

Keep `py-10` on `<nav>` but negative-margin the chevron row upward.

**Rejected because:**

- Negative margins are brittle and leak layout assumptions across children.
- Does not explain itself to the next reader — a hand-off hack.

**Decision:** Approach A.

## Implementation Phases

### Phase 1 — Write failing test (RED)

Add a new test case to `apps/web-platform/test/settings-sidebar-collapse.test.tsx` under the existing `describe("expand button alignment with main nav chevron", () => { ... })` block (or a sibling `describe("collapse button alignment with main nav chevron", () => { ... })` block — the sibling is clearer).

Assert the **expanded-state** collapse button's parent `<nav>` uses `py-5`, NOT `py-10`, matching the main nav header wrapper at `apps/web-platform/app/(dashboard)/layout.tsx:231`.

Suggested test:

```tsx
describe("collapse button alignment with main nav chevron (expanded state)", () => {
  it("nav wrapper uses py-5 to align chevron y-origin with main nav header", () => {
    render(
      <SettingsShell>
        <div>content</div>
      </SettingsShell>,
    );
    const collapseBtn = screen.getByLabelText("Collapse settings nav");
    const navEl = collapseBtn.closest("nav");
    expect(navEl).not.toBeNull();
    expect(navEl).toHaveClass("py-5");
    expect(navEl?.className).not.toMatch(/\bpy-10\b/);
  });

  it("collapse button keeps h-6 w-6 geometry matching main nav toggle", () => {
    render(
      <SettingsShell>
        <div>content</div>
      </SettingsShell>,
    );
    const btn = screen.getByLabelText("Collapse settings nav");
    expect(btn).toHaveClass("h-6", "w-6", "rounded");
    expect(btn.className).not.toMatch(/\bborder(-|\s|$)/);
    const svg = btn.querySelector("svg");
    expect(svg).toHaveClass("h-4", "w-4");
  });
});
```

Run under `apps/web-platform`:

```bash
cd apps/web-platform && ./node_modules/.bin/vitest run test/settings-sidebar-collapse.test.tsx
```

Expect the first assertion (`toHaveClass("py-5")`) to FAIL with the current `py-10`.

**Stack note:** Use `./node_modules/.bin/vitest` per AGENTS.md `cq-in-worktrees-run-vitest-via-node-node` — `npx vitest` resolves via the shared cache and can pick up a stale worktree's vitest installation.

### Phase 2 — Apply the fix (GREEN)

Edit `apps/web-platform/components/settings/settings-shell.tsx`:

**Before (line 38-40):**

```tsx
className={`hidden shrink-0 border-r border-neutral-800 md:block
md:transition-[width] md:duration-200 md:ease-out
${settingsCollapsed ? "md:w-0 md:overflow-hidden md:border-r-0" : "w-48 px-4 py-10"}`}>
```

**After:**

```tsx
className={`hidden shrink-0 border-r border-neutral-800 md:block
md:transition-[width] md:duration-200 md:ease-out
${settingsCollapsed ? "md:w-0 md:overflow-hidden md:border-r-0" : "w-48 px-4 py-5"}`}>
```

Net diff: a single `py-10` → `py-5` token in the expanded-state branch of the conditional className.

Re-run the test file. All assertions in both the PR #2494 tests and the new ones MUST pass.

### Phase 3 — Visual QA with Playwright MCP (the durable alignment contract)

Per AGENTS.md hr-mcp-tools-playwright-etc-resolve-paths, pass absolute paths. Per the PR #2494 precedent (session-state), capture screenshots at 1280×800 for:

1. Main nav expanded + Settings sub-nav expanded (the bug scenario) — both `<` chevrons must be on the same y-row.
2. Main nav expanded + Settings sub-nav collapsed — the PR #2494 expand `>` chevron must still align with main nav `<`.
3. Main nav collapsed + Settings sub-nav expanded — main nav `>` vs settings `<` must align.
4. Main nav collapsed + Settings sub-nav collapsed — both `>` chevrons must align.

Save screenshots under `/tmp/settings-chevron-alignment-<timestamp>/` and reference them in the PR body.

**Route to hit:** `/dashboard/settings/team` (Team Settings page, per the user's screenshot).

**Local dev server:** per AGENTS.md `cq-for-local-verification-of-apps-doppler`, run `cd apps/web-platform && ./scripts/dev.sh 3000` in a backgrounded Bash call, then point Playwright at `http://localhost:3000/dashboard/settings/team`.

#### Pixel-level alignment assertion (primary contract)

Classname tests (Phase 1) prove the correct *intent*. Actual pixel alignment must be verified with Playwright because JSDOM reports `DOMRect { x:0, y:0, width:0, height:0 }` for every element — `getBoundingClientRect()` is a no-op in the vitest/jsdom environment.

For scenario 1 (the bug), add this Playwright step alongside the screenshot:

```javascript
// Inside mcp__playwright__browser_evaluate after navigating to /dashboard/settings/team
// at viewport 1280x800 with both navs expanded:
const mainBtn = document.querySelector('aside button[aria-label="Collapse sidebar"]');
const settingsBtn = document.querySelector('nav button[aria-label="Collapse settings nav"]');
const mainRect = mainBtn.getBoundingClientRect();
const settingsRect = settingsBtn.getBoundingClientRect();
const yDelta = Math.abs(
  (mainRect.top + mainRect.height / 2) -
  (settingsRect.top + settingsRect.height / 2)
);
return { mainY: mainRect.top, settingsY: settingsRect.top, yDelta };
```

**AC:** `yDelta ≤ 2`. If `yDelta > 2`, escalate — the classname fix was not sufficient for the live font/line-height combo and we need to re-examine the "Soleur" brand row height or switch to an absolute-positioned approach (Approach B-lite).

Record the returned `{mainY, settingsY, yDelta}` in the PR body alongside the screenshots — quantitative evidence that the fix landed, not just a "looks aligned" screenshot.

#### Route & auth setup

`/dashboard/settings/team` requires an authenticated user. For local Playwright QA:

- If a dev session cookie is already present, reuse it.
- Otherwise, hit `/login`, sign in with the Doppler-stored dev credentials (`doppler secrets get DEV_TEST_EMAIL DEV_TEST_PASSWORD -p soleur -c dev --plain`). If those keys are absent from Doppler, fall back to prompting the user per AGENTS.md `hr-when-playwright-mcp-hits-an-auth-wall` — keep the browser tab open on the login page, do not close and hand off a URL.
- Navigate to `/dashboard/settings/team` only after authentication.

### Phase 4 — Update session-state.md

Append a new "Plan Phase" subsection to `knowledge-base/project/specs/feat-one-shot-settings-nav-chevron-align/session-state.md` referencing this plan file. Do NOT overwrite the PR #2494 entry — both plans coexist on this branch because the second fix extends the first.

### Phase 5 — Compound + ship

Per AGENTS.md `wg-before-every-commit-run-compound-skill`, run `skill: soleur:compound` before the commit that applies this fix, capturing the learning that "alignment fixes must check both expanded and collapsed states for every pair of nav chevrons" — this is the gap that made PR #2494 incomplete and should be a compound capture so future planners surface the other state automatically.

Then `skill: soleur:ship` to open the PR. PR body MUST include:

- `Closes #<issue-number>` once the user files the tracking issue (or a direct reference to the user's screenshots in the session).
- `Ref #2494` to cross-link the prior PR that addressed the collapsed-state counterpart.
- The four QA screenshots from Phase 3.

## Acceptance Criteria

- [ ] On `/dashboard/settings/*` with main nav expanded AND settings sub-nav expanded, the two `<` chevron buttons sit on the same horizontal y-row (center-to-center y-delta ≤ 2 px at 1280×800).
- [ ] The x-positions of the chevrons remain at the right edge of their respective sidebars — no x-axis change requested.
- [x] PR #2494's existing alignment contract tests (collapsed-state expand button classnames, relative parent, hidden md:flex) all still pass.
- [x] New tests assert (a) the `<nav>` parent uses `py-5` not `py-10` when expanded, (b) the collapse button preserves `h-6 w-6 rounded` and an `h-4 w-4` svg with no border class.
- [ ] Four Playwright screenshots at 1280×800 covering all four (main × settings) × (collapsed × expanded) combinations, with both chevrons visually aligned in every combination where both are present.
- [ ] Playwright `boundingBox()` assertion for scenario 1 (expanded/expanded) reports `yDelta ≤ 2` px; `{mainY, settingsY, yDelta}` recorded in the PR body as quantitative evidence.
- [x] No changes to click handler, aria-label, keyboard shortcut (`⌘B`), or localStorage key.
- [x] No changes to mobile tab bar (unchanged precedent from PR #2494's test).
- [x] Markdown lint passes on this plan file (`npx markdownlint-cli2 --fix knowledge-base/project/plans/2026-04-17-fix-settings-nav-expanded-chevron-alignment-plan.md`).
- [ ] If Phase 3 Playwright screenshots show chevrons still visually staggered after the fix lands, STOP shipping and re-open direction with user (Interpretation B escalation — the issue may be X-axis, not Y-axis).

## Test Scenarios

1. **Expanded/Expanded alignment (new bug)** — render `SettingsShell` on `/dashboard/settings`, assert `<nav>` has `py-5` and not `py-10`.
2. **Collapse button geometry preserved** — assert `h-6 w-6 rounded` on the button, `h-4 w-4` on the svg, no `border` class.
3. **Collapsed-state expand button (regression)** — re-run the 6 tests added in PR #2494 to ensure this change does not break them.
4. **Toggle round-trip** — click collapse, click expand, confirm `<nav>` renders again with `py-5` (not regressed to `py-10`).
5. **Cmd/Ctrl+B shortcut untouched** — existing PR #2494 shortcut tests pass unchanged.
6. **Playwright visual contract** — four screenshots (see Phase 3) demonstrate the alignment across all four state combinations.

## Non-Goals / Out of Scope

- Changing the `<nav>` width (`w-48`) to match main nav width (`md:w-56`). The user asked for chevron alignment, not sidebar-width uniformity. The two sidebars can remain different widths; only the chevron y-row needs to match.
- Changing the KB layout (`dashboard/kb/layout.tsx`) to use `py-5`. KB uses `pt-4 pb-3` deliberately (tighter header to maximize file-tree vertical real estate). Out of scope unless a user report flags KB misalignment specifically.
- Adding `safe-top` to the settings `<nav>`. `safe-top` resolves to 0 on desktop (the affected breakpoint) and the settings shell is only visible at `md:` and above, so there is no notch/safe-area concern.
- Restructuring the settings sidebar layout. The fix is a one-token padding change; any larger restructure belongs in a product/UX-gated design pass.
- Revisiting PR #2494's absolute-positioning approach for the collapsed-state button. That code path is correct for its state and explicitly anchored to a `relative` content-area parent.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a pure UI alignment bug fix touching a single component file with a 1-token className change plus tests. No product strategy, security, data, or architecture implications. No new user-facing surface; the existing surface is unchanged functionally.

## Observability / Rollback

- **Observability:** none. Pure CSS class change with no runtime branches.
- **Rollback:** revert the single-file diff; the test addition remains a useful regression gate even if reverted (it will fail loudly if a future edit re-introduces `py-10`).

## Sharp Edges

- Do NOT change the collapsed-state branch of the className conditional (`md:w-0 md:overflow-hidden md:border-r-0`). That branch intentionally strips padding so the content area can flow to the left edge while the absolute-positioned expand button renders.
- The inner flex row `<div className="mb-4 flex items-center justify-between">` keeps its `mb-4` — do not remove it. `mb-4` (16 px) separates the header from the tab `<ul>`; removing it would visually crowd the "General / Team / Integrations / Billing" list against the heading.
- Vitest class assertions use `toHaveClass("py-5")` + `not.toMatch(/\bpy-10\b/)`. The second guard is necessary because Tailwind's utility composition means `py-5` and `py-10` can coexist in the same className string without React warning (the later one wins in CSS cascade) — a naive `toHaveClass("py-5")` alone would pass even if someone left `py-10` behind. Mirror the regex form used in the existing PR #2494 tests for consistency.
- When running the dev server via `./scripts/dev.sh`, wait for "ready in <N>ms" before Playwright navigates. Use the Monitor tool for polling, not a fixed sleep.
- JSDOM does NOT implement layout. `getBoundingClientRect()` returns all-zero, `offsetTop/offsetHeight` return 0, and computed styles reflect the stylesheet string but not resolved pixel values. Classname assertions in vitest cannot prove alignment — they only prove the class is present. The Playwright bounding-box check in Phase 3 is the source of truth for y-delta ≤ 2 px.
- The main nav header wrapper carries `safe-top` (iOS notch padding). The settings `<nav>` does not. On a macOS/Chrome desktop at 1280×800 both resolve to 0 and the fix holds, but on iPad portrait (at or near the md breakpoint) the main nav could gain `env(safe-area-inset-top)` while settings does not — a latent divergence. Out of scope for this PR but flagged for a future iPad QA pass.
- Do NOT attempt to also match x-position by widening the settings `<nav>` from `w-48` to `md:w-56`. That is a larger UX decision (affects readable width of settings content column) and belongs in a UX-gated design pass. Interpretation B in the Overview's directional-ambiguity section explicitly rules this out of pipeline scope.
- When the test file imports `SettingsShell` from `@/components/settings/settings-shell`, the `usePathname` mock at the top of the test file must be present — the component reads `pathname` inside a `useEffect` for the ⌘B shortcut. The existing test file already sets this up; do not remove or reorder the mock block.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-04-17-fix-settings-nav-expanded-chevron-alignment-plan.md. Branch: feat-one-shot-settings-nav-chevron-align. Worktree: .worktrees/feat-one-shot-settings-nav-chevron-align/. Issue: none filed yet (follow-up to PR #2494). Plan written, tests not yet added, implementation pending — 1-token CSS fix + alignment test.
```
