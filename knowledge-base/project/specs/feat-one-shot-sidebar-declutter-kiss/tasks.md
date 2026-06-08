# Tasks — Declutter Collapsed Sidebar + Bias ux-design-lead Toward KISS

Plan: `knowledge-base/project/plans/2026-06-08-refactor-collapsed-sidebar-declutter-and-ux-kiss-plan.md`
Lane: cross-domain

## 1. Setup / RED

- [x] 1.1 ADD negative assertions to the existing collapsed-block describe in `apps/web-platform/test/workspace-context-band.test.tsx` (`"WorkspaceContextBand — collapsed monogram identity (Phase 1, #4915)"`): `queryByTestId("live-repo-dot")` and `queryByTestId("nav-section-title")` are `null` in the `collapsed` render. NOTE (deepen reconciliation): NO existing test asserts the removed glyphs, so this is an ADD, not an invert. Do NOT touch the `:205` `toHaveTextContent("S")` assertion — that is the identity MONOGRAM, not the section "K". Keep all non-collapsed `nav-section-title` assertions (`:143`/`:159`/`:167`/`:234`/`:256`/`:261`) intact. (RED — fails against current component.)
- [x] 1.2 Confirm `apps/web-platform/test/nav-rail-drill.test.tsx` `nav-section-title` assertion (`:282`) targets the expanded band (no `collapsed` set) and stays green. Expected: zero edits — drop from Files-to-Edit if untouched.
- [x] 1.3 Update `apps/web-platform/e2e/nav-states-shell.e2e.ts` (`:525`, `:606`) to replace `live-repo-dot` visibility with the `workspace-identity-icon` collapsed invariant. (RED.)

## 2. Core Implementation / GREEN

- [x] 2.1 In `apps/web-platform/components/dashboard/workspace-context-band.tsx`, delete the collapsed-branch `live-repo-dot` `<span>` (the gold `●`, `:117-124`).
- [x] 2.2 Delete the collapsed-branch single-letter `nav-section-title` `<span>` (`:125-133`); leave the non-collapsed full-text title (`:199-206`) untouched.
- [x] 2.3 Audit the collapsed container's `flex flex-col items-center gap-3` after removal — no orphaned empty slot (AC4).
- [x] 2.4 Verify the collapsed `workspace-identity-icon` / `WorkspaceIdentityTile` is retained verbatim (AC3).

## 3. Other-screens sweep (verify "everywhere")

- [x] 3.1 Run `grep -rn '●' apps/web-platform/components --include=*.tsx | grep -v node_modules`; confirm only legitimate separators/bullets/masks remain (enumerated in plan Research Reconciliation). Record output in PR body (AC8).

## 4. ux-design-lead KISS principle

- [x] 4.1 Add a design-time KISS/simplicity principle to `## Step 2: Design` in `plugins/soleur/agents/product/design/ux-design-lead.md`. Do NOT touch the `description:` line (AC9).
- [x] 4.2 Reconcile `.openhands/skills/ux-design-lead/SKILL.md` — mirror the principle if it duplicates the design workflow; note divergence otherwise (AC10).

## 5. Verify

- [x] 5.1 `tsc --noEmit` clean for `apps/web-platform`.
- [x] 5.2 `./node_modules/.bin/vitest run test/workspace-context-band.test.tsx test/nav-rail-drill.test.tsx` — all green.
- [x] 5.3 Confirm ACs 1-11 in the plan are satisfied; capture sweep grep output for the PR body.
