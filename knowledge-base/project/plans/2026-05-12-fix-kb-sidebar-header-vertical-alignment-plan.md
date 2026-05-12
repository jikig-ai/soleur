---
type: fix
status: draft
lane: single-domain
branch: feat-one-shot-sol-39-sidebar-misalignment
worktree: .worktrees/feat-one-shot-sol-39-sidebar-misalignment/
requires_cpo_signoff: false
linear: SOL-39
---

# fix: KB sidebar "Knowledge Base" header vertical-baseline misalignment with main "Soleur" brand row

## Enhancement Summary

**Deepened on:** 2026-05-12
**Sections enhanced:** Overview, Hypotheses (Research Insights), Implementation Phases, Acceptance Criteria, Risks, Test Scenarios
**Research vectors:** yesterday's settings-sidebar peer plan (PR #3557, plan `2026-05-11-fix-settings-sidebar-gap-and-header-alignment-plan.md`); QA-degradation learning `2026-05-11-qa-degradation-when-dev-server-broken-on-css-only-fix.md`; both-toggle-states learning `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`; Playwright-in-worktree learning `2026-02-17-playwright-screenshots-land-in-main-repo.md`; JSDOM-layout-trap learning `best-practices/2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps.md`; Tailwind v4 token-availability learning `2026-04-02-tailwind-v4-a11y-focus-ring-contrast-patterns.md`. Verified `tailwindcss@^4.1.0` + `@tailwindcss/postcss@^4.2.1` in `apps/web-platform/package.json`; verified `min-h-7` already in production at `apps/web-platform/components/settings/settings-shell.tsx:42`; verified `py-5` already in production at `apps/web-platform/app/(dashboard)/layout.tsx:241` AND `apps/web-platform/components/settings/settings-shell.tsx:41`; verified `gh issue view 3562 --json state` returns `OPEN` (dev-server bug still un-fixed — QA-degradation path is precedent).

### Key Improvements

1. **Token availability proven, not asserted.** Original plan claimed `min-h-7` and `py-5` work under Tailwind v4 from arithmetic alone. Deepen-pass grepped both tokens against the codebase and confirmed each is already in use in **production-shipped** files — `min-h-7` lives at `settings-shell.tsx:42` (landed yesterday in PR #3557), `py-5` lives at three call sites including the very `(dashboard)/layout.tsx:241` row we're aligning to. No tailwind.config.* exists (verified: `apps/web-platform/tailwind.config.*` matches zero files), so Tailwind v4's zero-config defaults are authoritative. The plan no longer depends on the arithmetic alone.
2. **QA-degradation pre-authorized.** Deepen-pass confirmed via `gh issue view 3562` that the dev-server bug (#3562) blocking Playwright is OPEN. The 2026-05-11 settings-sidebar PR (#3557) hit the same blocker and shipped on vitest className contracts alone, per `knowledge-base/project/learnings/2026-05-11-qa-degradation-when-dev-server-broken-on-css-only-fix.md`. This plan's User-Brand Impact threshold is `none`, className contracts are unit-tested, and the geometry math is in §Research Insights — three of three QA-degradation criteria. Phase 4 now has a documented escape valve that maps to the existing precedent rather than blocking on a pre-existing infra bug.
3. **Playwright screenshot path corrected.** Per `knowledge-base/project/learnings/2026-02-17-playwright-screenshots-land-in-main-repo.md`, Playwright MCP in a worktree writes screenshots to the MAIN-repo root unless an absolute filename path is passed. Phase 4 now prescribes `filename: "$(pwd)/.playwright-mcp/<name>.png"` (or equivalent absolute path) so screenshots land in the worktree's `.playwright-mcp/` and don't pollute `main`.
4. **JSDOM layout-trap risk reified.** The original Risks mentioned JSDOM zero-returns from `getBoundingClientRect`. Deepen-pass surfaced the broader pattern (`best-practices/2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps.md` — `clientWidth > 0`-gated assertions silently green-pass in JSDOM). Phase 1 test snippet was audited: it asserts ONLY className tokens, no layout values, no conditional layout gates. Confirmed safe.
5. **Plan-prescribed labels verified.** Deepen-pass ran `gh label list` (already done at plan-write time): only `domain/engineering` and `chore` resolve cleanly from the conventional candidates. The plan uses no labels (no AC-prescribed `gh issue create --label` site), so this gate passes trivially.

### New Considerations Discovered

- **Yesterday's peer plan (PR #3557) is the immediate ancestor.** This bug is the SECOND alignment regression of the same class in two days. The pattern is now established: header rows on side-by-side sidebars use different padding tokens; fix is `py-5 min-h-7`. A shared `<SidebarHeader>` component scope-out is filed in §Sharp Edges (third-occurrence trigger — keep YAGNI until then).
- **#3562 (dev-server ESM/CJS conflict) is still open.** This is the load-bearing precondition for the QA-degradation path. If #3562 lands before this plan ships, restore full Playwright QA per the original Phase 4. Until then, the degraded path stands.
- **No tailwind.config.\* file exists.** Tailwind v4 uses CSS-driven `@theme` directives instead. The `--spacing` default of `0.25rem` is therefore the source of truth for `py-5` (20 px) and `min-h-7` (28 px). If a future PR adds a `@theme` block overriding `--spacing`, both tokens would re-scale and the alignment would re-break together — but the math would still match because both sidebars use the same scale.
- **Heading-level inconsistency across sidebars is documented but out of scope.** Main brand uses `<span>`, KB uses `<h1>`, settings uses `<h2>`. An a11y/heading-hierarchy follow-up scope-out is filed in §Sharp Edges.

## Overview

On `/dashboard/kb*` routes, two sidebars sit side-by-side at the top of the app:

- The **main app sidebar** (left, owned by `apps/web-platform/app/(dashboard)/layout.tsx`) whose top-most row is the `Soleur` brand `<span class="text-lg font-semibold tracking-tight">`.
- The **KB panel sidebar** (immediately to the right of the main sidebar, owned by `apps/web-platform/components/kb/kb-sidebar-shell.tsx`) whose top-most row is the `<h1 class="text-lg font-medium tracking-tight">Knowledge Base</h1>` header.

Their top container `<div>` / `<header>` use different vertical-padding tokens, so the two header text-baselines do NOT share a y-coordinate. The visual artifact is a few-pixel vertical drift between the two text rows, reported as "the Soleur brand row sits a few pixels higher than the Knowledge Base header row" in SOL-39. (See §Research Reconciliation — the reported direction of the drift is inverted relative to the codebase measurement; the fix is direction-agnostic but the QA measurement step locks the direction down before merge.)

Scope is exclusively CSS-padding / row-height tokens on the KB sidebar header. No behavior, data, or state changes. No file is created.

## User-Brand Impact

**If this lands broken, the user experiences:** a visibly misaligned pair of sidebar header rows on the most-used surface (KB), which reads as "unfinished UI" on a paid product where polish disproportionately drives trust.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — pure-CSS layout fix, no credential/data/payment surface touched.

**Brand-survival threshold:** none

Reason for `none`: the fix touches one client component file (`kb-sidebar-shell.tsx`) with zero auth/data/payment/PII code paths. The sensitive-path regex (`plugins/soleur/skills/preflight/SKILL.md` Check 6 §6.1) does not match `components/kb/kb-sidebar-shell.tsx`.

## Research Reconciliation — Spec vs. Codebase

| Spec / report claim | Reality (verified in codebase, 2026-05-12) | Plan response |
|---|---|---|
| "The Soleur brand row sits a few pixels HIGHER than the Knowledge Base KB-panel header row" | Geometric arithmetic on the current code: main brand text y-center = `20 (py-5) + 14 (text-lg ⌊28/2⌋) = 34 px`; KB heading text y-center = `16 (pt-4) + 14 = 30 px`. KB is therefore 4 px HIGHER on screen, equivalent to Soleur being 4 px LOWER. The report's direction is inverted relative to the source-code measurement (paraphrase-without-verification class — see Sharp Edges). | Phase 0 records a `browser_evaluate` ground-truth measurement of both header text-bbox-centers BEFORE any code edit. The fix normalizes both rows to the same vertical center regardless of which side was "higher" — but the pre-edit measurement is captured in the PR body so the report's direction is reconciled with the rendered DOM, not asserted from arithmetic alone. |
| "Two sidebar headers are side-by-side at the top of the app" | Confirmed. `apps/web-platform/components/kb/kb-desktop-layout.tsx:48-63` renders the KB sidebar as a sibling `<aside>` to the dashboard layout's main `<aside>` (rendered in `apps/web-platform/app/(dashboard)/layout.tsx:229`). Both are in the same flex row established by the dashboard `<div className="flex h-dvh flex-col md:flex-row">` at layout.tsx:200. | No layout-structure change needed. The fix lives entirely inside `kb-sidebar-shell.tsx`'s top `<header>`. |
| "KB panel is the secondary panel that opens when Knowledge Base is selected in the nav" | Confirmed. `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` (the KB-segment layout) wraps the KB route in `<KbDesktopLayout>` which renders `<KbSidebarShell>` only on `/dashboard/kb*` routes. The main `<aside>` is always present; the KB `<aside>` mounts only on KB routes. | The fix targets the KB-route case (both sidebars visible side-by-side). The main sidebar is unchanged. |
| Existing test `apps/web-platform/test/kb-sidebar-collapse.test.tsx` covers the collapse toggle | Confirmed. The test asserts `getByLabelText("Collapse file tree")`, toggle behavior, Cmd/Ctrl+B keyboard shortcut, input-focus suppression, and mobile `hidden` class. No alignment-pixel assertion exists yet. | Plan extends the file with a class-presence assertion that locks `py-5 min-h-7` on the header row. No existing assertion is relaxed. |
| `tailwindcss@^4.1.0` is the installed version | Confirmed at `apps/web-platform/package.json` (per the prior peer plan 2026-05-11). Tailwind v4 spacing scale: `py-5` = 20 px V; `min-h-7` = 28 px; both generated on-demand by `@tailwindcss/postcss` — no `tailwind.config.*` extension required. | Plan uses `py-5 min-h-7` to match the main brand row's effective row height. |

## Files to Edit

- `apps/web-platform/components/kb/kb-sidebar-shell.tsx` — change the top `<header>` padding tokens and lock the row to `min-h-7`.
- `apps/web-platform/test/kb-sidebar-collapse.test.tsx` — add a class-presence assertion for `py-5 min-h-7 flex items-center justify-between` on the KB header row.

## Files to Create

None.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body --limit 200` (run 2026-05-12) returned 80 issues; standalone-`jq` searches for `kb-sidebar-shell.tsx`, `kb-desktop-layout.tsx` returned `None`. A search for `dashboard)/layout.tsx` returned one match:

- #2193: refactor(billing): unify past_due and unpaid banners into shared component + extract useDismissiblePersistent — **Disposition: Acknowledge.** The overlap is in the same file (`apps/web-platform/app/(dashboard)/layout.tsx`) but a different concern (`PaymentWarningBanner` + `subscriptionStatus`-bound banner extraction). This plan does NOT touch the main sidebar `<aside>` block; #2193's scope is the banner block inside `<main>`. The two diffs do not collide.

No other overlaps.

## Implementation Phases

### Phase 0 — Ground-truth measurement (BEFORE any code edit)

Per §Research Reconciliation row 1, the report's direction-of-drift claim is inverted relative to source-code arithmetic. Establish the rendered ground-truth FIRST so the fix is tied to the DOM, not to either prose claim.

1. Boot the dev server (`bun run dev` from `apps/web-platform/`).
2. Use `mcp__playwright__browser_navigate` to `/dashboard/kb` (any KB route with both sidebars visible at md+ width — viewport 1280×800).
3. Use `mcp__playwright__browser_evaluate` with this snippet to capture the current y-centers of both header text rows:

   ```javascript
   () => {
     const brand = Array.from(document.querySelectorAll('aside span'))
       .find(el => el.textContent?.trim() === 'Soleur');
     const kbHeading = document.querySelector('aside h1');
     if (!brand || !kbHeading) {
       return {
         error: 'header element(s) not found',
         brand: !!brand,
         kbHeading: !!kbHeading,
       };
     }
     const b = brand.getBoundingClientRect();
     const k = kbHeading.getBoundingClientRect();
     return {
       brandY: b.top + b.height / 2,
       kbY: k.top + k.height / 2,
       yDelta: Math.abs((b.top + b.height / 2) - (k.top + k.height / 2)),
       direction: (b.top + b.height / 2) > (k.top + k.height / 2)
         ? 'Soleur lower than KB'
         : 'Soleur higher than KB',
     };
   }
   ```

4. Record `{ brandY, kbY, yDelta, direction }` in the PR body under a "Ground-truth (pre-fix)" heading. The expected pre-fix shape per arithmetic is `direction: "Soleur lower than KB", yDelta ≈ 4`. If the measurement diverges from this, do NOT proceed — re-investigate (a possible third factor: font-baseline offset, theme-token override, parent-padding shift).

### Phase 1 — Failing test (TDD RED)

Add to `apps/web-platform/test/kb-sidebar-collapse.test.tsx` a new `describe` block AFTER the existing `describe("KB sidebar collapse")` block:

```tsx
describe("KB sidebar header alignment with main app brand row", () => {
  it("KB header row uses py-5 + min-h-7 to match main sidebar brand row height", async () => {
    render(<KbLayout><div>content</div></KbLayout>);
    await screen.findByTestId("file-tree");
    // Use the existing label-based query the test file relies on, then walk
    // to the wrapping <header> element (the header row).
    const collapseBtn = screen.getByLabelText("Collapse file tree");
    const headerRow = collapseBtn.closest("header");
    expect(headerRow).not.toBeNull();
    // Padding token MUST match the main sidebar's brand row (py-5).
    expect(headerRow?.className).toMatch(/\bpy-5\b/);
    // min-h-7 (28 px) matches text-lg's natural line-height, locking row
    // height to the same value as the main sidebar's brand row.
    expect(headerRow?.className).toMatch(/\bmin-h-7\b/);
    // Layout primitives must remain (regression guard).
    expect(headerRow?.className).toMatch(/\bflex\b/);
    expect(headerRow?.className).toMatch(/\bitems-center\b/);
    expect(headerRow?.className).toMatch(/\bjustify-between\b/);
    // Old `pt-4` / `pb-3` tokens must NOT be present (regression guard
    // against the misaligned baseline).
    expect(headerRow?.className).not.toMatch(/\bpt-4\b/);
    expect(headerRow?.className).not.toMatch(/\bpb-3\b/);
  });
});
```

Run `bun test apps/web-platform/test/kb-sidebar-collapse.test.tsx`. The new assertion MUST fail (current `pt-4 pb-3` tokens); all existing assertions MUST still pass.

### Phase 2 — Fix the KB sidebar header padding

In `apps/web-platform/components/kb/kb-sidebar-shell.tsx`, change the top `<header>` element (line 17):

```diff
-      <header className="flex shrink-0 items-center justify-between px-4 pb-3 pt-4">
+      <header className="flex min-h-7 shrink-0 items-center justify-between px-4 py-5">
```

**Why these tokens:**

- `py-5` (20 px top + 20 px bottom) — matches the main sidebar's brand-row vertical padding (`apps/web-platform/app/(dashboard)/layout.tsx:241`, `px-5 py-5`). Aligning vertical padding is the dominant lever; both rows now share the same outer V-padding.
- `min-h-7` (28 px) — matches `text-lg` line-height (1.75 rem = 28 px) and the height of the collapse `<button class="h-6 w-6">` (24 px) is dominated by `min-h-7`. This locks the row's minimum height to the same value as the main sidebar's effective row height (where the brand `<span class="text-lg">` already drives a 28 px line-box). With `flex items-center`, both text-centers now land at `20 + 14 = 34 px` from the top of the aside.
- `px-4` — unchanged. The KB sidebar uses a tighter horizontal padding than the main sidebar (which uses `px-5`) intentionally — this matches the file-tree's `px-2` indentation rhythm below it. Out of scope.
- `shrink-0` — preserved (regression guard against future flex-column changes shrinking the header).

The remaining `<div className="shrink-0 px-3 pb-3">` (search overlay container, line 42) is unchanged — its `pb-3` interacts with the next sibling, not with header alignment.

### Phase 3 — Run all updated tests (TDD GREEN)

```bash
bun test apps/web-platform/test/kb-sidebar-collapse.test.tsx
bunx tsc --noEmit
```

Both must pass. The new assertion goes from RED → GREEN; existing assertions remain GREEN; `tsc` shows no new errors (no type surface changed).

### Phase 4 — Quantitative visual QA via Playwright MCP (with degradation path)

Per the alignment-fixes-must-verify-both-toggle-states learning at `knowledge-base/project/learnings/2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`, capture measurements + screenshots at `/dashboard/kb` under each toggle-state combination where both sidebars are visible:

| # | Main sidebar | KB sidebar | Both visible? |
|---|---|---|---|
| 1 | open (`md:w-56`) | open (`md:w-72`) | yes — measure |
| 2 | collapsed (`md:w-14`) | open (`md:w-72`) | yes — measure |
| 3 | open (`md:w-56`) | collapsed (`md:w-0`) | KB header NOT visible — screenshot only, no measurement |
| 4 | collapsed (`md:w-14`) | collapsed (`md:w-0`) | KB header NOT visible — screenshot only, no measurement |

For combinations #1 and #2, run the same `browser_evaluate` snippet from Phase 0 and record `{ brandY, kbY, yDelta, direction }`. **AC: `yDelta ≤ 1 px`** for both #1 and #2.

For combinations #3 and #4, attach screenshots only — the assertion is "the KB sidebar collapses cleanly to `md:w-0` and the main sidebar layout is unaffected by the new `min-h-7` token."

**Screenshot paths (worktree-safety):** Per `knowledge-base/project/learnings/2026-02-17-playwright-screenshots-land-in-main-repo.md`, Playwright MCP screenshots in a worktree write to the MAIN-repo root unless the `filename:` parameter is an absolute path. For every `mcp__playwright__browser_take_screenshot` call, pass `filename: "$(pwd)/.playwright-mcp/sol-39-<combo-N>.png"` (resolving `$(pwd)` to the active worktree absolute path before the MCP call). Do NOT use relative filenames. After Phase 4 completes, run `ls .playwright-mcp/` inside the worktree to verify all four screenshots landed there, then `ls "$(git rev-parse --git-common-dir)/.."/*.png 2>/dev/null` to confirm no `.png` files leaked into the main repo root.

If `yDelta > 1` in #1 or #2, escalate — the `py-5 min-h-7` choice did not normalize to the live font/line-height combo. Recovery: read the post-edit `getBoundingClientRect()` heights of both `<header>` / brand `<div>` elements and reconcile against arithmetic (most likely cause: `font-medium` vs `font-semibold` produces a sub-pixel baseline offset that the line-box does not absorb — recovery is to add `leading-7` to both rows, but only if measurement proves it).

Attach screenshots to the PR alongside the numeric deltas.

#### Phase 4 fallback — QA-degradation path (pre-authorized)

Per `knowledge-base/project/learnings/2026-05-11-qa-degradation-when-dev-server-broken-on-css-only-fix.md`, if the dev server (`bun run dev` from `apps/web-platform/`) fails to start due to issue #3562 (verified OPEN at deepen-pass time: 2026-05-12), Playwright QA is degraded to vitest className contracts alone. Three discriminator criteria from the learning, all satisfied by this plan:

- (a) User-Brand Impact threshold = `none` — yes (see §User-Brand Impact).
- (b) className contracts are unit-tested — yes (Phase 1 RED test asserts `py-5`, `min-h-7`, `flex`, `items-center`, `justify-between` are present and `pt-4`, `pb-3` are absent).
- (c) Geometry math is in the plan — yes (see §Research Insights "Geometric computation").

If #3562 is still OPEN at QA time, the PR may merge on Phase 1+2+3 alone, with the PR body citing this fallback subsection and PR #3557 as the precedent. The Phase 0 ground-truth measurement is ALSO degraded (it requires the dev server too) — note `Phase 0 deferred to #3562 close` in the PR body if so. Re-running Phase 0 + Phase 4 quantitatively becomes a post-merge sanity check rather than a pre-merge gate, scoped to the close of #3562.

If #3562 has been resolved by QA time, run the full Phase 4 path above (no degradation).

**Do NOT use this fallback for fixes whose threshold is `single-user incident` or `aggregate pattern`, or for fixes that touch interactive flows / data writes / auth / payments.** Pure-CSS-utility-class fixes only.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `apps/web-platform/components/kb/kb-sidebar-shell.tsx` top `<header>` uses `flex min-h-7 shrink-0 items-center justify-between px-4 py-5` (verbatim class list, order-insensitive).
- [x] Old `pt-4` and `pb-3` tokens are absent from the same `<header>`.
- [x] All existing assertions in `apps/web-platform/test/kb-sidebar-collapse.test.tsx` continue to pass.
- [x] One new assertion added in a new `describe` block asserting `py-5`, `min-h-7`, `flex`, `items-center`, `justify-between` present and `pt-4`, `pb-3` absent — passes.
- [x] `bun test apps/web-platform/test/kb-sidebar-collapse.test.tsx` → green.
- [x] `bunx tsc --noEmit` from `apps/web-platform/` → no new errors.
- [ ] **Either** Phase 0 pre-fix ground-truth `{ brandY, kbY, yDelta, direction }` measurement attached to the PR body, **OR** PR body cites the §Phase 4 fallback subsection AND PR #3557 as precedent AND issue #3562 is still OPEN at PR-open time (verified via `gh issue view 3562 --json state`).
- [ ] **Either** Phase 4 post-fix `{ brandY, kbY, yDelta }` measurements attached for combinations #1 + #2 with `yDelta ≤ 1 px`, **OR** same QA-degradation fallback as above.
- [ ] **Either** Phase 4 screenshots attached for all four toggle-state combinations (filenames written via absolute path to `$(worktree)/.playwright-mcp/`), **OR** same QA-degradation fallback as above. If screenshots are taken, `ls .playwright-mcp/ && ls "$(git rev-parse --git-common-dir)/.."/*.png 2>/dev/null` confirms all PNGs landed inside the worktree and none in the main repo root.
- [ ] PR body uses `Closes SOL-39` (Linear) — or `Ref SOL-39` if the Linear close-on-merge integration is not wired for this repo.

### Post-merge (operator)

None — pure client-side CSS fix, no migration, no infra, no Doppler write.

## Hypotheses

1. **Primary root cause (high confidence):** the `<header>` uses `pt-4 pb-3` (16 + 12 = 28 px V padding, asymmetric) while the main brand row uses `py-5` (20 + 20 = 40 px V padding, symmetric). With `flex items-center` on both rows, the KB heading text y-center is `16 + 14 = 30 px`; the main brand text y-center is `20 + 14 = 34 px`. **Computed delta: 4 px (KB higher on screen, Soleur lower).** Aligning the KB header to `py-5 min-h-7` brings both text-centers to `34 px`, delta target = 0 px.

2. **Secondary factor (low confidence):** font-weight differential (`font-medium` on KB vs `font-semibold` on brand) could theoretically shift the line-box baseline by a sub-pixel. If Phase 4 measures `yDelta > 1` after the padding fix, this is the next-most-likely cause; recovery is `leading-7` on both rows. Mitigation: Phase 4 quantitative measurement, not eyeballing.

3. **Tertiary factor (mitigated):** `safe-top` on the main brand row (line 241) injects `env(safe-area-inset-top, 0px)` as additional top padding. On desktop browsers this resolves to 0; on iOS Safari with notch, it could shift the brand row down. The KB header does NOT carry `safe-top`. This is irrelevant on the desktop surface where the bug was reported, but flagged so the QA evaluator does not mis-attribute a mobile-only divergence. Out of scope (mobile shows the brand + a top bar, KB sidebar uses `md:block` only — the two are never side-by-side below md).

### Research Insights

**Geometric computation (current state, pre-fix):**

- Main sidebar brand row at `apps/web-platform/app/(dashboard)/layout.tsx:241`:
  - `<div className={"flex items-center justify-between safe-top " + (collapsed ? "px-2 py-5" : "px-5 py-5")}>`
  - Inner: `<span className="text-lg font-semibold tracking-tight">Soleur</span>` (text-lg → line-height 1.75 rem = 28 px) + `<button h-6 w-6>` (24 px).
  - Row height = `max(28, 24) = 28 px`. Brand text y-center = `20 (py-5 top) + 14 (28/2) = 34 px`.
- KB header at `apps/web-platform/components/kb/kb-sidebar-shell.tsx:17`:
  - `<header className="flex shrink-0 items-center justify-between px-4 pb-3 pt-4">`
  - Inner: `<h1 className="text-lg font-medium tracking-tight">Knowledge Base</h1>` (28 px line-height) + `<button h-6 w-6>` (24 px).
  - Row height = `max(28, 24) = 28 px`. KB text y-center = `16 (pt-4) + 14 (28/2) = 30 px`.
- **Computed Δ = 4 px.** Direction: KB header is HIGHER on screen (smaller y), main brand is LOWER (larger y).

**Geometric computation (post-fix):**

- KB header becomes `flex min-h-7 shrink-0 items-center justify-between px-4 py-5`. Row height floors to `max(min-h-7=28, text-lg=28, h-6=24) = 28 px`. KB text y-center = `20 (py-5 top) + 14 = 34 px`. **Δ = 0 px.**

**Tailwind v4 spacing semantics:**

`apps/web-platform/package.json` pins `tailwindcss@^4.1.0` + `@tailwindcss/postcss@^4.2.1` (per the 2026-05-11 peer plan, same package surface). Tailwind v4 unifies the spacing scale: `py-5` = `padding-block: calc(var(--spacing) * 5) = 1.25 rem = 20 px`; `min-h-7` = `min-height: calc(var(--spacing) * 7) = 1.75 rem = 28 px`. Both generated on-demand; no `tailwind.config.*` extension required.

**Why not change the main brand row instead?**

The main brand row is on the dashboard layout used by EVERY `/dashboard/*` route. Touching it risks shifting alignment with the chat conversation rail, settings sidebar, and dashboard-home top edge. The KB sidebar is the secondary, route-scoped panel — adapting it to the main sidebar's geometry is the minimum-blast-radius fix. (The 2026-05-11 settings-sidebar plan made the same call for the same reason: settings was the inbound, the main sidebar was the anchor.)

**Prior precedent (same workflow class):**

- `knowledge-base/project/plans/2026-05-11-fix-settings-sidebar-gap-and-header-alignment-plan.md` — same misalignment class, settings sidebar inbound. Adopted `min-h-7` and `py-5`-like normalization. This plan reuses the same pattern.
- `knowledge-base/project/learnings/2026-04-17-alignment-fixes-must-verify-both-toggle-states.md` — alignment fixes must verify BOTH toggle states. Phase 4 explicitly covers all four (main × KB sidebar) toggle-state combinations.

## Risks

- **Wrong root cause for the reported direction.** The report says "Soleur sits higher than KB" but the arithmetic shows the opposite. If Phase 0 ground-truth confirms the report's direction (Soleur higher, KB lower), then the bug is something other than `pt-4 pb-3` vs `py-5` — most likely a parent-container offset (e.g., the dashboard layout's `safe-top` resolving non-zero, or a theme-token-driven margin). Recovery: do NOT ship the Phase 2 edit until Phase 0 ground-truth matches arithmetic. If it diverges, re-investigate from the parent down.
- **`min-h-7` interaction with the search overlay below the header.** The header `<header>` and the search overlay `<div className="shrink-0 px-3 pb-3">` are siblings under the KB shell's flex column. Raising the header row by 8 px (from 28 px total height under `pt-4 pb-3` to 40 px under `py-5`) shifts the search overlay down by 8 px. This is intentional vertical alignment with the main sidebar's nav rail (which starts at `y = 20 + 28 = 48 px + 12 px (theme-toggle border padding) ≈ 60 px`), but visual QA in Phase 4 must confirm the shift is imperceptible. If QA flags it, recover by shrinking the search overlay's own padding (`pb-3` → `pb-1`), NOT by undoing the header fix.
- **Conditional collapse-state padding is NOT touched.** The KB sidebar uses an animated width transition (`md:transition-[width]`) but the header padding does NOT change between expanded and collapsed states (the KB sidebar collapses to `md:w-0`, so the header is `overflow-hidden`-ed away rather than re-padded). No collapse-state padding swap is added — out of scope.
- **`safe-top` only on main brand row.** The main brand row carries `safe-top` (`padding-top: env(safe-area-inset-top, 0px)`); the KB header does NOT. On desktop browsers `env(safe-area-inset-top)` resolves to 0, so this is irrelevant for the bug surface. On iPad/iOS Safari in standalone-PWA mode, the main brand could shift down by up to ~44 px while the KB header does not — but iPad horizontal layout is below md anyway, so the KB sidebar is `md:hidden`-equivalent. Not a blocker. Flagged so the QA evaluator does not test on iPad simulator and report a regression.
- **JSDOM `getBoundingClientRect()` returns zeros.** The numeric `yDelta` assertion is Playwright-only (real browser). The unit test asserts only class presence — JSDOM cannot measure pixels. This is by design; same convention as the 2026-05-11 settings-sidebar plan and `2026-04-17-fix-settings-nav-expanded-chevron-alignment-plan.md`.
- **JSDOM layout-trap broader pattern (audited, confirmed safe).** Per `knowledge-base/project/learnings/best-practices/2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps.md`, JSDOM also silently green-passes assertions gated on `clientWidth > 0`, `scrollWidth`, `offsetHeight`, etc. The Phase 1 test snippet was audited against this pattern: it asserts ONLY classname-token presence/absence via `.className.match()` and `closest("header")`, with NO layout-value reads, NO conditional layout gates, and NO awaited `act`-style layout measurements. Confirmed safe under JSDOM.
- **Playwright screenshots can leak into main repo.** Per `knowledge-base/project/learnings/2026-02-17-playwright-screenshots-land-in-main-repo.md`, Playwright MCP in a worktree writes screenshots to the MAIN-repo root unless `filename:` is an absolute path. Phase 4 prescribes absolute paths into `$(worktree)/.playwright-mcp/`. Mitigation also verifies via post-Phase-4 `ls` against the main repo root.
- **QA-degradation fallback is bounded to this fix class.** The fallback (vitest className contracts only, Playwright deferred) is pre-authorized ONLY because (a) threshold is `none`, (b) className contracts are unit-tested, (c) geometry math is in the plan. If a follow-up review identifies an unanticipated user-facing impact, the threshold must be re-evaluated and the fallback withdrawn — the Phase 4 quantitative path becomes load-bearing again.
- **Test selector fragility.** The new test uses `screen.getByLabelText("Collapse file tree").closest("header")`. The label string is the contract surface (used by all existing tests in `kb-sidebar-collapse.test.tsx`), and `closest("header")` resolves to the top header element by tag. If a future refactor changes the wrapping element from `<header>` to `<div>`, the selector breaks. Mitigation: the existing test file already uses this query pattern; consistency wins over a more-resilient `data-testid` for a one-line CSS test.
- **Theme-token rotation in flight.** A recent change rotated theme tokens app-wide (light-theme tokenization PR class). This plan's edit is theme-agnostic (no `text-soleur-text-*` change), so it composes cleanly with both light and dark themes. Verify Phase 4 screenshots are captured in BOTH themes (default + `next-themes`-toggled) — add as the second screenshot per combination.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is complete (`threshold: none` with stated reason).
- Alignment fixes must verify BOTH toggle states (open + closed) per the existing learning at `knowledge-base/project/learnings/2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`. Phase 4 explicitly covers four (main × KB) toggle-state combinations.
- This bug is the second alignment regression of the same class in two days (settings sidebar yesterday, KB sidebar today). The root cause class is "header rows on side-by-side sidebars use different padding tokens." A reasonable follow-up scope-out (NOT in this PR) is a shared `<SidebarHeader>` component that centralizes `flex min-h-7 items-center justify-between py-5` so the next-added sidebar inherits alignment by construction. Filed as a scope-out, not folded in — YAGNI until the third occurrence.
- The bug report's direction-of-drift wording is inverted relative to the codebase arithmetic (paraphrase-without-verification class). Phase 0 ground-truth measurement is the gate that reconciles report wording with rendered DOM — do not skip it. If the measurement matches the arithmetic, both wordings ("Soleur higher" or "KB lower") describe the same artifact and the fix proceeds. If the measurement matches the report's wording, the root cause is upstream and this plan does NOT apply.
- Do NOT substitute `h-7` for `min-h-7`. `min-h-7` preserves the row's ability to grow if a future translation/copy change widens the line; `h-7` clips. The 2026-05-11 settings-sidebar plan made the same call — keep the pattern consistent.
- The KB sidebar uses `<h1>` while the main brand uses `<span>` and the settings header uses `<h2>`. This is an existing inconsistency in heading-level semantics across sidebars but out of scope for this CSS-only fix. Filed as a scope-out (a11y / heading-hierarchy review across all sidebars), not folded in.

## Domain Review

**Domains relevant:** Engineering (current task topic).

No cross-domain leaders spawned: this is a 1-line CSS fix (plus a class-presence test) with zero architectural, product-strategy, legal, marketing, or financial implications. Product domain assessed as ADVISORY (modifies existing component, no new pages/components, no new flows) — mechanical escalation does NOT fire because no new file is created under `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

Per `plan` skill Step 2.5 Step 2: "On ADVISORY → If in pipeline/subagent context: auto-accept, write Product/UX Gate subsection with Tier: advisory, Decision: auto-accepted (pipeline), proceed silently."

#### Findings

No content review needed — fix touches no copy, no labels, no flows, no images. Visual QA in Phase 4 (Playwright MCP measurements + screenshots in both themes) substitutes for a wireframe pass: the design exists; the bug is a pixel-level deviation from it.

## Test Scenarios

| Scenario | State | Expected |
|---|---|---|
| KB header alignment, both sidebars open | main open, KB open | Brand text y-center and KB heading text y-center share the same value (±1 px). `yDelta ≤ 1` via `browser_evaluate`. |
| KB header alignment, main collapsed | main collapsed (`md:w-14`), KB open | Same as above — main collapse does not affect KB header position. |
| KB header NOT visible when KB collapsed | main open, KB collapsed | `<header>` is inside the `md:w-0 md:overflow-hidden` aside; rendered width contribution is 0. No measurement; visual confirmation only. |
| Test guard: header padding token | DOM at initial render | `<header>` has `py-5`, `min-h-7`, `flex`, `items-center`, `justify-between`; does NOT have `pt-4` or `pb-3`. |
| Existing toggle behavior | DOM after collapse click | All existing assertions in `KB sidebar collapse` describe block continue to pass — toggle still works, Cmd/Ctrl+B still works, input-focus still suppresses. |
| Dark + light theme | Both themes, combination #1 | yDelta unchanged across theme toggle (CSS-vars only affect color, not geometry). |
| QA-degradation discriminator: threshold none | Plan §User-Brand Impact | Threshold reads `none` with stated reason — fallback eligibility criterion (a) satisfied. |
| QA-degradation discriminator: className contracts unit-tested | Phase 1 RED test | Test asserts `py-5`, `min-h-7`, `flex`, `items-center`, `justify-between` present + `pt-4`/`pb-3` absent — fallback eligibility criterion (b) satisfied. |
| QA-degradation discriminator: geometry math in plan | §Research Insights "Geometric computation" | Pre-fix + post-fix arithmetic present — fallback eligibility criterion (c) satisfied. |
| Screenshot path safety | Post-Phase-4 `ls` | All `.png` files land in `$(worktree)/.playwright-mcp/`; zero PNGs in `$(git rev-parse --git-common-dir)/..`. |

## Definition of Done

- Bug visibly resolved in Playwright screenshots across all four toggle-state combinations.
- All `bun test apps/web-platform/test/kb-sidebar-collapse.test.tsx` assertions green.
- `bunx tsc --noEmit` from `apps/web-platform/` passes.
- PR description includes pre-fix (Phase 0) AND post-fix (Phase 4) `{ brandY, kbY, yDelta, direction }` measurements for combinations #1 and #2.
- PR description includes before/after screenshots for at least two toggle-state combinations.
- PR uses `Closes SOL-39` (Linear ref) only if the Linear close-on-merge integration is wired; otherwise `Ref SOL-39`.
