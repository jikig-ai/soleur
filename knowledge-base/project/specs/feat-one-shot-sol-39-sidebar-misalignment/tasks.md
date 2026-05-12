---
plan: knowledge-base/project/plans/2026-05-12-fix-kb-sidebar-header-alignment-plan.md
issue: SOL-39 (Linear)
branch: feat-one-shot-sol-39-sidebar-misalignment
---

# Tasks — fix(kb): align "Knowledge Base" sidebar header with Soleur brand row

## Phase 0 — Geometry verification (before any code edit)

- [ ] 0.1 Start dev server: `cd apps/web-platform && bun run dev` (or fall back to `npm run dev`).
- [ ] 0.2 Sign in to a dev account that has a KB workspace; navigate to `/dashboard/kb`.
- [ ] 0.3 In browser devtools console, run the geometry script from plan Phase 0 step 3 and capture: `soleur.getBoundingClientRect()`, `kb.getBoundingClientRect()`, `dx`, `dy`.
- [ ] 0.4 Confirm `dy ≈ -4 px` (KB sits ~4 px higher than Soleur) and `dx ≈ -4 px` relative to a same-x baseline. If deltas differ, HALT and re-diagnose before proceeding.
- [ ] 0.5 Confirm both-toggle-state invariant: collapse the KB sidebar (Cmd+B); confirm `<aside>` width transitions to 0 and the header is fully hidden (no peek).

## Phase 1 — Failing tests (TDD RED)

- [ ] 1.1 Open `apps/web-platform/test/kb-sidebar-collapse.test.tsx`.
- [ ] 1.2 Add two new `it()` blocks inside the existing `describe("KB sidebar collapse")` block (after `"preserves mobile class-swap behavior"`) per plan Phase 1.
- [ ] 1.3 Run `bunx vitest run apps/web-platform/test/kb-sidebar-collapse.test.tsx` — confirm the two new tests FAIL and the existing 6 still PASS (6/8 pass, 2/8 fail).

## Phase 2 — Implementation (TDD GREEN)

- [ ] 2.1 Edit `apps/web-platform/components/kb/kb-sidebar-shell.tsx`:
  - `<header>` className: `flex shrink-0 items-center justify-between px-4 pb-3 pt-4` → `flex shrink-0 items-center justify-between px-5 py-5`.
  - `<h1>` className: `text-lg font-medium tracking-tight text-soleur-text-primary` → `text-lg font-semibold tracking-tight text-soleur-text-primary`.
- [ ] 2.2 Run `bunx vitest run apps/web-platform/test/kb-sidebar-collapse.test.tsx` — confirm 8/8 PASS.

## Phase 3 — Refactor / surface sweep

- [ ] 3.1 `rg "px-4 pb-3 pt-4" apps/web-platform/components/kb/` → expect 0 matches.
- [ ] 3.2 `rg "text-lg font-medium tracking-tight" apps/web-platform/components/kb/kb-sidebar-shell.tsx` → expect 0 matches.
- [ ] 3.3 `rg "Knowledge Base" apps/web-platform/components/ apps/web-platform/app/` → confirm only the dashboard nav link label and the KB sidebar h1 match; nothing else changed.
- [ ] 3.4 `cd apps/web-platform && bun run lint` → expect 0 errors.
- [ ] 3.5 `cd apps/web-platform && bunx tsc --noEmit` → expect 0 errors.

## Phase 4 — Playwright pixel-coord QA (source of truth)

- [ ] 4.1 With dev server running and signed in, navigate Playwright to `/dashboard/kb`.
- [ ] 4.2 Run the Playwright `getBoundingClientRect()` measurement from plan Phase 4 step 3.
- [ ] 4.3 Assert `Math.abs(dy) ≤ 1 px` between Soleur `<span>` and KB `<h1>` text-tops; record numeric value for PR body.
- [ ] 4.4 Capture before/after screenshots (top-left 600×120 px region).
- [ ] 4.5 Toggle Cmd+B; confirm KB sidebar collapses cleanly (no header peek); re-expand; confirm header re-renders at corrected geometry with no flicker.
- [ ] 4.6 **Degraded-QA branch:** if dev server fails to start (e.g., `instrumentation.ts` ESM/CJS issue per learning 2026-05-11), file a `pre-existing-unrelated` follow-up issue, document the `Math.abs(dy)` measurement as `not-measured (dev-server blocked by #<followup-issue>)`, and proceed to ship with vitest contract only. This is acceptable because User-Brand Impact = `none` and className contract is unit-tested.

## Phase 5 — Theme spot-check

- [ ] 5.1 Switch to `theme=light`, capture screenshot of corrected geometry.
- [ ] 5.2 Switch to `theme=dark`, capture screenshot of corrected geometry.
- [ ] 5.3 Attach both screenshots to PR body alongside the Phase 4 before/after pair.

## Phase 6 — Ship

- [ ] 6.1 Commit with `fix(kb-sidebar): align "Knowledge Base" header with Soleur main sidebar brand row`.
- [ ] 6.2 PR body MUST include: (a) Phase 4 measured `dy` value, (b) all four screenshots, (c) `Ref SOL-39 (Linear)`, (d) `Closes #<github-mirror-issue>` if one exists.
- [ ] 6.3 Run `/soleur:preflight` → confirm Check 6 passes (User-Brand Impact section present, threshold `none`, no sensitive-path matches).
- [ ] 6.4 Run `/soleur:qa` → confirm visual regression check (or accept degraded-QA path per Phase 4.6).
- [ ] 6.5 Push branch; create PR; mark ready when checks green.
- [ ] 6.6 After merge: verify production `/dashboard/kb` renders correctly post-deploy.
- [ ] 6.7 Close SOL-39 in Linear with a link to the merged PR.

## Phase 7 — Learning capture (optional)

- [ ] 7.1 If anything non-trivial surfaced during Phase 0-6 (e.g., a sibling misalignment, an unexpected mobile-layout interaction, a CSS-token drift), invoke `/soleur:compound` to capture as a learning under `knowledge-base/project/learnings/`.
