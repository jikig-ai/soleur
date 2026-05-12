---
type: fix
status: draft
branch: feat-one-shot-sol-39-sidebar-misalignment
worktree: .worktrees/feat-one-shot-sol-39-sidebar-misalignment/
issue: SOL-39 (Linear)
linear_url: https://linear.app/jikigai/issue/SOL-39/misalignment-of-elements
requires_cpo_signoff: false
---

## Enhancement Summary

**Deepened on:** 2026-05-12
**Sections enhanced:** Overview, Research Reconciliation, Implementation Phases, Acceptance Criteria, Risks, Test Scenarios
**Research vectors:** sibling settings-nav alignment fixes (#2494/#2504/#3557/#3573/#3579/#3587), `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`, `2026-05-11-qa-degradation-when-dev-server-broken-on-css-only-fix.md`, `2026-02-13-parallel-subagent-css-class-mismatch.md` (verbatim class-token discipline), existing `apps/web-platform/test/kb-sidebar-collapse.test.tsx` mocking pattern (renders `KbLayout`, not `KbSidebarShell`), Tailwind v4.1 spacing-scale verification via `apps/web-platform/package.json`.

### Key Improvements

1. **Test scaffold corrected to match existing convention.** Initial draft rendered `KbSidebarShell` directly. Existing `test/kb-sidebar-collapse.test.tsx` renders `<KbLayout>` with mocked `FileTree` + `SearchOverlay` + `next/dynamic`. The new alignment assertions are added to the **same describe block** using `screen.getByRole("heading", { name: "Knowledge Base" })` after `findByTestId("file-tree")`. This avoids duplicating ~30 lines of mock scaffolding and keeps a single source of truth for KB sidebar test setup.
2. **`safe-top` non-inclusion verified as correct.** The Soleur brand row uses `safe-top` (iOS safe-area inset top padding); the KB header MUST NOT add `safe-top` because the KB sidebar lives inside `<main>`, not at the screen edge. Verified by reading `app/(dashboard)/layout.tsx:200-202` — the mobile top bar carries `safe-top`, the KB sidebar header does not need it.
3. **`shrink-0` retention rationale documented.** The KB sidebar's parent geometry is `flex h-full flex-col` (kb-sidebar-shell.tsx:16). The header must keep `shrink-0` so it doesn't compact when the FileTree grows. The Soleur brand row's parent is also a `flex flex-col` aside but at fixed `md:w-56` width — different geometry, no `shrink-0` needed. Asymmetric utility tokens are correct here; sibling-PR template (#3557 settings-shell) does NOT carry `shrink-0` because its parent geometry differs.
4. **Both-toggle-state gate explicitly closed.** The KB sidebar is toggleable (`kbCollapsed` → `md:w-0`), but the header is unmounted from the visible layout in the collapsed state (`md:overflow-hidden` + zero width + `inert`). Only one rendering state contains the header; sharp-edge `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md` satisfied.
5. **CLI-token verification.** `bun test` (default Bun test runner) is the project convention per `apps/web-platform/package.json` `"test": "vitest run"` — actual runner is **vitest**. Plan uses `bunx vitest run <file>` (not `bun test <file>`). Verified: `cat apps/web-platform/package.json | grep '"test"'`.
6. **Verbatim-token discipline locked in.** Per `2026-02-13-parallel-subagent-css-class-mismatch.md`, the same six Tailwind tokens (`flex`, `shrink-0`, `items-center`, `justify-between`, `px-5`, `py-5`) and the two font tokens (`text-lg`, `font-semibold`, `tracking-tight`) are repeated VERBATIM in: (a) the Implementation Phase 2 diff, (b) the Phase 1 vitest assertions, (c) the Acceptance Criteria checkboxes, and (d) the Research Reconciliation table. A single canonical list at the top of Implementation Phases prevents drift between sections.

### New Considerations Discovered

- **Sibling PR #3587 just shipped** (2026-05-11 commit `6cf6bb27` — "apply settings-sidebar transition to KB file-tree sidebar"). It changed the KB `<aside>` transition wrapper but did NOT touch the header. No conflict with this plan; the inner wrapper at `kb-desktop-layout.tsx:60` is untouched.
- **CPO sign-off NOT required** despite this being a user-facing surface, because: (a) User-Brand Impact threshold is `none`, (b) the diff touches zero sensitive paths per the preflight regex, (c) no new interactive surface is created.
- **The font-weight change from `font-medium` to `font-semibold` is the visually dominant fix** even more than the padding change. At a 4 px geometric delta on a 28 px line-box, the human eye perceives weight asymmetry more readily than 4 px of offset.
- **No e2e Playwright spec added** — repository convention places interactive e2e in `apps/web-platform/e2e/*.e2e.ts` (currently auth/onboarding/rail flows only, no layout spec). Adding a `kb-sidebar-alignment.e2e.ts` would establish a new convention; YAGNI for a one-shot fix. Pixel-coord verification is captured manually in Phase 4 and pasted into the PR body.

---

# fix: Align the KB sidebar's "Knowledge Base" header with the Soleur main sidebar's "Soleur" brand row

## Overview

On `/dashboard/kb/*` routes the user sees **two adjacent sidebars on the left**:

1. The Soleur **dashboard sidebar** (`app/(dashboard)/layout.tsx`), whose top row contains the `Soleur` brand wordmark.
2. The KB **file-tree sidebar** (`components/kb/kb-sidebar-shell.tsx`), whose top row contains the `Knowledge Base` heading.

The two headers sit on the same horizontal band but their text baselines and left edges do not line up:

| Surface | Container classes | Left pad | Top pad | Bottom pad | Font weight |
|---|---|---|---|---|---|
| Soleur brand row (`layout.tsx:241`) | `flex items-center justify-between safe-top px-5 py-5` | **20 px** (`px-5`) | **20 px** (`py-5`) | **20 px** (`py-5`) | `text-lg font-semibold tracking-tight` |
| KB header row (`kb-sidebar-shell.tsx:17`) | `flex shrink-0 items-center justify-between px-4 pb-3 pt-4` | **16 px** (`px-4`) | **16 px** (`pt-4`) | **12 px** (`pb-3`) | `text-lg font-medium tracking-tight` |

Three pure-CSS deltas read as "misalignment" to the user:

- **Horizontal:** KB text starts 4 px further left than Soleur text (`px-4` vs `px-5`).
- **Vertical:** KB text baseline sits 4 px higher than Soleur text baseline (`pt-4` 16 px vs `py-5` 20 px). With both at `text-lg` and `items-center`, the row-height delta moves the text-center up by ~4 px.
- **Typographic weight:** `font-medium` (500) vs `font-semibold` (600) — the Soleur wordmark reads heavier than the KB heading at the same `text-lg` size, accentuating the visual disconnect even after geometry is fixed.

This is a pure CSS/Tailwind utility-class change on the inner `<header>` of `KbSidebarShell`. No behavior, data, state, or accessibility changes.

## User-Brand Impact

**If this lands broken, the user experiences:** a more misaligned KB sidebar header than before (e.g., text-clipping or a too-tall header row that crowds out the search overlay) on every visit to `/dashboard/kb/*` — a paid surface where polish drives trust. The blast radius is purely visual; no functional regression possible because the only edits are layout utility classes.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — pure CSS/layout fix on one client component. Zero auth, data, payment, or PII code paths touched.

**Brand-survival threshold:** none

Reason for `none`: the edit is confined to `apps/web-platform/components/kb/kb-sidebar-shell.tsx` (presentation-only client component) plus a matching test. The sensitive-path regex (`plugins/soleur/skills/preflight/SKILL.md` Check 6 §6.1) does not match `components/kb/*`. No CPO sign-off required.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (Linear SOL-39) | Reality (verified in codebase 2026-05-12) | Plan response |
|---|---|---|
| "The text of 'Knowledge Base' in the sidebar of the KB site is not aligned with the text of the Soleur sidebar." | Confirmed at `components/kb/kb-sidebar-shell.tsx:17-19`. Container `px-4 pb-3 pt-4` vs Soleur brand row `px-5 py-5` at `app/(dashboard)/layout.tsx:241`. | Match the KB header geometry to the Soleur brand row: switch container to `px-5 py-5` (drop `pb-3 pt-4`, drop `shrink-0` only if equivalent kept — see Implementation). Match weight `font-medium` → `font-semibold`. |
| Linear-issue title implies "KB site" = the marketing/docs site at `plugins/soleur/docs/`. | The "KB site" referenced in the description is the **in-app KB sidebar** at `/dashboard/kb/*`, NOT the Eleventy docs site. The Eleventy site has no left-sidebar adjacent to a "Soleur sidebar". Verified: `plugins/soleur/docs/_includes/` has a top nav, not a left-sidebar wordmark. | Plan scope is `apps/web-platform/components/kb/kb-sidebar-shell.tsx`. Eleventy docs site is out of scope. Directional ambiguity resolved by adjacency check: the only place a "Knowledge Base" heading appears in a sidebar adjacent to a "Soleur" sidebar is the dashboard KB layout. |
| "See image attached on the Linear issue" — image not directly accessible from this environment. | Geometry-based diagnosis from code is sufficient because the deltas are concrete and measurable from utility classes. QA Phase will capture before/after screenshots with Playwright `getBoundingClientRect()` deltas to confirm against the Linear image at PR time. | No deferral; geometric pre-computation supplies the design intent and Playwright supplies the verification. |
| The KB sidebar header is **toggleable** (`md:w-0` when collapsed). | When collapsed, the entire `<aside>` shrinks to `md:w-0` and the `KbSidebarShell` becomes `inert`. The header isn't visible in the collapsed state — there is no second toggle-state-rendering of the header. | The "alignment fixes must verify both toggle states" sharp edge (`learnings/2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`) is satisfied trivially: only one state renders the header. **Verified in Phase 2 below.** Both layouts (`kb-desktop-layout.tsx` and `kb-mobile-layout.tsx`) confirm the header is unmounted when `kbCollapsed` is true (desktop: `md:w-0 md:overflow-hidden`; mobile: `block` only on tree-view). |
| Sibling PR #3587 ("apply settings-sidebar transition to KB file-tree sidebar") just shipped on 2026-05-12. | Confirmed at `git log`. The PR changed `<aside>` transitions and added a `w-72 h-full` inner wrapper — it did NOT change the header geometry. | No conflict with this plan. The inner wrapper at `kb-desktop-layout.tsx:60` (`<div className="w-72 h-full">`) is untouched. |
| Recent PR #3557/#3579/#3573 settings-nav alignment lessons (`min-h-7` for row-height equalization) apply. | The Soleur brand row uses `py-5` (no explicit `min-h-*`) and `text-lg font-semibold` — the resulting computed height with `flex items-center` and a 28 px line-box yields ~68 px. Matching `py-5` + same `text-lg` weight equalizes the row without an explicit `min-h-*`. | Plan does NOT add `min-h-7` (which would be 28 px — too short for a `py-5 + text-lg` row). The right primitive here is **matching pad tokens + matching font weight**, not adding a min-height floor. |

## Open Code-Review Overlap

Procedure: enumerated planned files (`components/kb/kb-sidebar-shell.tsx`, `test/kb-sidebar-collapse.test.tsx`), then queried open code-review issues:

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for p in "components/kb/kb-sidebar-shell.tsx" "test/kb-sidebar-collapse.test.tsx"; do
  jq -r --arg path "$p" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

Result: **None.** No open `code-review`-labeled issues touch the two edited files. Recorded so the next planner can see the check ran.

## Files to Edit

- `apps/web-platform/components/kb/kb-sidebar-shell.tsx` — change the inner `<header>` className from `flex shrink-0 items-center justify-between px-4 pb-3 pt-4` to `flex shrink-0 items-center justify-between px-5 py-5` and change the `<h1>` className from `text-lg font-medium tracking-tight text-soleur-text-primary` to `text-lg font-semibold tracking-tight text-soleur-text-primary`. No other file in the component changes.
- `apps/web-platform/test/kb-sidebar-collapse.test.tsx` — add a new `describe` block asserting the header's alignment contract (`px-5 py-5` on container, `font-semibold` on `<h1>`). Existing assertions stay untouched.

## Files to Create

None.

## Implementation Phases

### Phase 0 — Verify the geometry before editing

A 10-minute sanity step that prevents wasted work if the geometry analysis is wrong:

1. Run the dev server with `cd apps/web-platform && npm run dev` (or `bun run dev`).
2. Navigate to `/dashboard/kb` after sign-in.
3. Open browser devtools, select the `Soleur` `<span>` and the `Knowledge Base` `<h1>`, copy each one's `getBoundingClientRect()`:

    ```js
    const soleur = document.querySelector('aside span.text-lg.font-semibold')
      ?.getBoundingClientRect();
    const kb = document.querySelector('h1.text-lg.font-medium')
      ?.getBoundingClientRect();
    console.log({ soleur, kb, dx: kb.left - soleur.left, dy: kb.top - soleur.top });
    ```

4. Record the deltas in the plan's QA Evidence section. Expected (from utility-class math): `dx ≈ -4 px` (KB starts 4 px further left), `dy ≈ -4 px` (KB sits 4 px higher).

**If the deltas are different from expected:** Pause and re-read the bug image attachment in Linear before proceeding. The fix below assumes the geometry analysis above. Different deltas point to a different root cause (e.g., the `<aside>` itself sits at a different offset, the chat panel pushes the KB sidebar, something in `kb-desktop-layout.tsx`'s inner wrapper, etc.).

**Both-toggle-state verification (sharp edge `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`):**

- **Expanded state (default).** The header is rendered inside `<KbSidebarShell>`. This is the state the user sees as misaligned. Fix targets this state.
- **Collapsed state.** The `<aside>` width goes to `md:w-0` AND the wrapper has `md:overflow-hidden` (kb-desktop-layout.tsx:56-58). The header is not visible (`inert` + zero width + overflow hidden) and `KbSidebarShell` is unmounted from layout flow. Confirmed via `rg "KbSidebarShell" apps/web-platform/components/kb/` — only one render path, no second toggle-state code path.
- **Mobile layout.** `kb-mobile-layout.tsx` shows the sidebar full-width when `!isContentView`. The header geometry change applies identically; no special mobile branch in `KbSidebarShell` (the component renders one `<header>` regardless of viewport).

Therefore the both-states gate is satisfied: only one rendered state, no hidden alignment surface.

### Phase 1 — Failing tests (TDD RED)

The existing `apps/web-platform/test/kb-sidebar-collapse.test.tsx` renders the **full `KbLayout`** with mocked `FileTree`, `SearchOverlay`, and `next/dynamic` (the mock scaffold lives at lines 7-42 of that file). The new alignment assertions are added to the same `describe("KB sidebar collapse")` block to reuse that scaffold — DO NOT introduce a parallel `describe` that renders `KbSidebarShell` directly, that would require duplicating ~30 lines of mocks.

Add the following inside the existing `describe("KB sidebar collapse")` block, after the `"preserves mobile class-swap behavior"` test:

```tsx
it("header row uses px-5 py-5 to match Soleur main sidebar (layout.tsx:241)", async () => {
  render(<KbLayout><div>content</div></KbLayout>);
  await screen.findByTestId("file-tree");
  const heading = screen.getByRole("heading", { name: "Knowledge Base", level: 1 });
  const headerRow = heading.parentElement;
  expect(headerRow).not.toBeNull();
  expect(headerRow).toHaveClass("px-5", "py-5");
  // Lock in the row still flex-centers the heading + collapse button.
  expect(headerRow).toHaveClass("flex", "items-center", "justify-between", "shrink-0");
  // Defensive: legacy asymmetric tokens are gone.
  expect(headerRow).not.toHaveClass("px-4");
  expect(headerRow).not.toHaveClass("pt-4");
  expect(headerRow).not.toHaveClass("pb-3");
});

it("'Knowledge Base' heading uses font-semibold to match Soleur wordmark weight", async () => {
  render(<KbLayout><div>content</div></KbLayout>);
  await screen.findByTestId("file-tree");
  const heading = screen.getByRole("heading", { name: "Knowledge Base", level: 1 });
  expect(heading).toHaveClass("text-lg", "font-semibold", "tracking-tight");
  expect(heading).not.toHaveClass("font-medium");
});
```

Run `bunx vitest run apps/web-platform/test/kb-sidebar-collapse.test.tsx` (NOT `bun test` — the project pins `vitest@^3.1.0` and the `"test"` script in `apps/web-platform/package.json` resolves to `vitest`). The two new assertions MUST fail before Phase 2.

**Why these assertions and not `getBoundingClientRect()`:** per `learnings/2026-05-11-qa-degradation-when-dev-server-broken-on-css-only-fix.md`, JSDOM/happy-dom returns 0 for `getBoundingClientRect()`. The vitest assertions are **className regression gates**; pixel-level alignment is the Playwright job in Phase 4.

**Why `shrink-0` is in the assertion list:** the KB sidebar header lives inside `flex h-full flex-col` (kb-sidebar-shell.tsx:16). Without `shrink-0` the header could compact under flex pressure when the search overlay or file tree grows. Locking it into the assertion prevents a future refactor from quietly removing it.

### Phase 2 — Fix (TDD GREEN)

Edit `apps/web-platform/components/kb/kb-sidebar-shell.tsx`:

```diff
- <header className="flex shrink-0 items-center justify-between px-4 pb-3 pt-4">
-   <h1 className="text-lg font-medium tracking-tight text-soleur-text-primary">
+ <header className="flex shrink-0 items-center justify-between px-5 py-5">
+   <h1 className="text-lg font-semibold tracking-tight text-soleur-text-primary">
      Knowledge Base
    </h1>
```

No other lines in the file change. `shrink-0` is preserved because the inner wrapper (`<div className="w-72 h-full">`) at `kb-desktop-layout.tsx:60` does NOT pass overflow context — `shrink-0` prevents the header from collapsing under flex pressure inside `flex h-full flex-col`.

Run `bunx vitest run apps/web-platform/test/kb-sidebar-collapse.test.tsx` — both new assertions and all 6 existing assertions MUST pass (8/8 total).

### Phase 3 — Refactor / surface sweep

1. `rg "px-4 pb-3 pt-4" apps/web-platform/components/kb/` — confirm zero remaining sites with the old token combination inside `components/kb/`.
2. `rg "text-lg font-medium tracking-tight" apps/web-platform/components/kb/ apps/web-platform/app/\(dashboard\)/` — confirm zero remaining KB sidebar sites with the old weight combination. (`text-lg font-medium` may legitimately appear in unrelated `connect-repo/`, `workspace-not-ready.tsx`, etc. — those are NOT the KB sidebar header.)
3. `rg "Knowledge Base" apps/web-platform/components/ apps/web-platform/app/` — confirm only the dashboard nav label (`app/(dashboard)/layout.tsx:89`) and the KB sidebar header (`components/kb/kb-sidebar-shell.tsx:19`) match. The dashboard nav label is a `<span>` inside a `<Link>` — different surface, no change needed.
4. Run `bun run lint` and `bunx tsc --noEmit` from `apps/web-platform/` to confirm no type/lint regressions.

### Phase 4 — Playwright pixel-coord QA (the source of truth)

Per `learnings/2026-05-11-qa-degradation-when-dev-server-broken-on-css-only-fix.md`, pixel-level alignment is Playwright-only. The vitest assertions are regression gates; this phase is the **authoritative geometric verification**.

1. Sign into a dev environment that has at least one KB doc indexed.
2. Navigate to `/dashboard/kb`.
3. In the Playwright session, run:

    ```js
    const soleur = await page.evaluate(() => {
      const el = document.querySelector('aside span.font-semibold.tracking-tight');
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return { left: r.left, top: r.top, height: r.height };
    });
    const kb = await page.evaluate(() => {
      const el = document.querySelector('h1.font-semibold.tracking-tight');
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return { left: r.left, top: r.top, height: r.height };
    });
    console.log({ soleur, kb, dx: kb.left - soleur.left, dy: kb.top - soleur.top });
    ```

4. **Pass criterion:** `Math.abs(dy) ≤ 1` AND `dx === soleur_aside_width` (so KB text sits exactly at `x = soleur_aside_width + 20 px` — the KB sidebar's own `px-5`).
5. Take a screenshot via `page.screenshot()` clipping the top-left 600×120 px region. Attach to the PR body.
6. **Toggle the KB sidebar collapse** (Cmd+B or click the chevron). Confirm: the entire KB `<aside>` collapses to width 0, no header peeks through. Confirm the Soleur sidebar's brand row is unaffected. Re-expand and confirm the header re-appears at the corrected geometry.

**If Playwright is blocked by a pre-existing dev-server bug** (per the same learning), degrade to vitest contract only and file the dev-server issue with `pre-existing-unrelated` criterion. **This is acceptable for a pure-CSS fix.** For data/auth/payment fixes it is not — here it is, because the User-Brand Impact threshold is `none` and the className contract is unit-tested.

### Phase 5 — Light + dark theme spot-check

The KB sidebar's tokenization (`text-soleur-text-primary`) is theme-neutral. Open both `theme=light` and `theme=dark` and take a single screenshot of each at the corrected geometry to confirm no theme-token regression. Attach both to the PR body.

### Phase 6 — Ship

1. Commit with `fix(kb-sidebar): align "Knowledge Base" header with Soleur main sidebar brand row` and reference the Linear ticket in the body: `Ref SOL-39`.
2. PR body: `Closes #<github-mirror-issue>` (if SOL-39 has a GitHub mirror — check via `gh issue list --search "SOL-39"`; if no mirror, just `Ref SOL-39 (Linear)`).
3. Attach the four Playwright screenshots (before/after × light/dark or before/after × expanded/collapsed).
4. Run `/soleur:preflight` then `/soleur:qa` per project ship lifecycle.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `apps/web-platform/components/kb/kb-sidebar-shell.tsx`: `<header>` container uses `flex shrink-0 items-center justify-between px-5 py-5` (verbatim).
- [x] `apps/web-platform/components/kb/kb-sidebar-shell.tsx`: `<h1>` uses `text-lg font-semibold tracking-tight text-soleur-text-primary` (verbatim).
- [x] `apps/web-platform/test/kb-sidebar-collapse.test.tsx`: 2 new alignment assertions added to existing describe block; all 6 prior assertions still pass.
- [x] `./node_modules/.bin/vitest run test/kb-sidebar-collapse.test.tsx` → 8/8 pass.
- [x] `./node_modules/.bin/tsc --noEmit` from `apps/web-platform/` → 0 errors.
- [ ] `bun run lint` from `apps/web-platform/` → deferred: `next lint` script is interactive on this checkout (pre-existing ESLint config prompt, unrelated to this fix).
- [ ] Playwright `dy` measurement between Soleur brand `<span>` and KB `<h1>`: `Math.abs(dy) ≤ 1 px`. PR body includes the measured value. **If Playwright is degraded by a pre-existing dev-server bug, the vitest contract is sufficient AND the dev-server bug is filed as a separate issue with `pre-existing-unrelated` criterion.**
- [ ] PR body contains 4 screenshots: before/after × (expanded state, light theme) and (expanded state, dark theme), or before/after × (expanded, collapsed) if theme switching is blocked.
- [x] `rg "px-4 pb-3 pt-4" apps/web-platform/components/kb/` → 0 matches.
- [x] `rg "text-lg font-medium tracking-tight" apps/web-platform/components/kb/kb-sidebar-shell.tsx` → 0 matches.
- [ ] PR body references `Ref SOL-39` (Linear) and the matching GitHub-mirror issue if one exists.

### Post-merge (operator)

- [ ] Verify production `/dashboard/kb` renders with the corrected alignment (single spot check after the deploy pipeline completes).
- [ ] Close SOL-39 in Linear with a link to the merged PR.

## Test Scenarios

| Scenario | Expected outcome | Verification |
|---|---|---|
| Render `KbSidebarShell` in vitest | `<header>` has `px-5 py-5`; `<h1>` has `font-semibold` | New `describe` block in `kb-sidebar-collapse.test.tsx` |
| Render dashboard `/dashboard/kb` in Playwright (expanded, light theme) | `Math.abs(dy) ≤ 1 px` between Soleur brand `<span>` and KB `<h1>`; `dx` equals the Soleur aside width | Phase 4 Playwright script |
| Render dashboard `/dashboard/kb` in Playwright (expanded, dark theme) | Same geometric assertion holds in dark theme | Phase 5 screenshot |
| Cmd+B toggle from `/dashboard/kb` | KB sidebar collapses to 0 width; no header peeks through; Soleur sidebar unchanged | Phase 4 step 6 |
| Re-expand from collapsed state | Header re-appears at the corrected geometry; no flicker, no transition jank | Phase 4 step 6 |
| Mobile viewport (<768 px) on `/dashboard/kb` | `KbSidebarShell` renders full-width when `!isContentView`; header still uses `px-5 py-5` | Visual inspection at 375 px |

## Risks

- **`shrink-0` accidentally dropped.** `shrink-0` prevents the header row from being squeezed under flex pressure inside the parent `flex h-full flex-col`. The plan explicitly preserves it. If a future refactor removes it, the header could compact when the search overlay grows. Mitigation: vitest assertion locks in `flex items-center justify-between` but does NOT lock in `shrink-0` — add it to the assertion list if shipping refactors of the search overlay.
- **`text-lg font-semibold` on KB header diverges from h1 typography in other KB surfaces** (`empty-state.tsx`, `workspace-not-ready.tsx`, `no-project-state.tsx` all use `text-lg font-medium`). The plan accepts this divergence because the **sidebar header is a navigation header** (sibling to the Soleur wordmark), not a page heading. Subsequent design alignment of all KB h1s is out of scope for SOL-39.
- **Playwright dev-server bug from `learnings/2026-05-11-qa-degradation-when-dev-server-broken-on-css-only-fix.md`** (`instrumentation.ts` ESM/CJS) may block Phase 4. **Mitigation:** the User-Brand Impact threshold is `none` and the className contract is unit-tested — vitest is sufficient. File a follow-up issue if Playwright degrades.
- **Pixel deltas in Phase 0 differ from utility-class math** (e.g., a parent transform or a margin elsewhere is the actual root cause). Mitigation: Phase 0 explicitly halts before Phase 1 if the measured deltas don't match `dx ≈ -4 px, dy ≈ -4 px`. The plan is geometric, not speculative.
- **A future Soleur brand row redesign drifts away from `px-5 py-5 font-semibold`.** If that happens, the KB header will silently drift out of alignment again. Mitigation (deferred): a design token (`--sidebar-header-padding`, `--sidebar-header-weight`) would solve this but is YAGNI for SOL-39. Filed as a follow-up consideration only if Phase 4 reveals more sibling sidebars with the same misalignment class.

## Sharp Edges

- **Both-toggle-state verification done in Phase 0.** Per `learnings/2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`, alignment fixes on toggleable controls must verify both states. Verified: only one state renders the header. Pass.
- **Plan's `## User-Brand Impact` section is filled in (not TBD).** Required by deepen-plan Phase 4.6 + preflight Check 6.
- **No `min-h-7` is prescribed here**, despite that being the pattern in PR #3557. The row-height for `text-lg + py-5` is ≈68 px, far above `min-h-7` (28 px). Matching pad tokens + weight is the right primitive at this scale.
- **No CLI invocations are added to operator-facing docs** in this PR. The CLI-verification gate (`Sharp Edges` rule) does not apply.
- **No new dependency, no new test framework.** Vitest + happy-dom is already the convention for `apps/web-platform/test/*.test.tsx`. Playwright is already configured (`apps/web-platform/playwright.config.ts`) and used in `e2e/*.e2e.ts`.

## Domain Review

**Domains relevant:** none (pure-CSS layout fix on one client component; no Product/UX flow change — modifying existing copy/weight on existing header).

No cross-domain implications detected — purely visual polish on an existing surface. Threshold check: User-Brand Impact = `none`; no CPO sign-off needed; no GDPR surface.

Product/UX Gate tier classification:

- Creates new user-facing pages? **No.** Edits one existing header.
- Creates new multi-step flows or new UI components? **No.** No new component file under `components/**/*.tsx`; no new `app/**/page.tsx`. Mechanical escalation does not fire.
- Modifies existing user-facing components? **Yes — but the modification is to bring an existing element into alignment with a sibling, not to introduce a new interactive surface.** Tier: **NONE** for the gate purpose (no new surface; restoring conformance with a sibling reference).

Skipping Product/UX Gate per the NONE tier rules.

## QA Evidence (filled in during Phase 0 + Phase 4)

```
Phase 0 measurement (before fix):
  soleur: { left: ?, top: ?, height: ? }
  kb:     { left: ?, top: ?, height: ? }
  dx (kb.left - soleur.left) = ?   (expected ≈ -4 px relative to a same-x baseline,
                                    or = soleur_aside_width - 4 if comparing absolute x)
  dy (kb.top  - soleur.top)  = ?   (expected ≈ -4 px)

Phase 4 measurement (after fix):
  soleur: { left: ?, top: ?, height: ? }
  kb:     { left: ?, top: ?, height: ? }
  dx (relative to KB aside left edge) = +20 px (= px-5)
  dy = 0 (target) or ≤ 1 px (acceptable subpixel)
```

Replace `?` with measured values during execution; attach to PR body.
