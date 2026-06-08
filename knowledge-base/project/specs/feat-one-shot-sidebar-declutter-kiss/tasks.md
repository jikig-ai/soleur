# Tasks — Declutter Collapsed Sidebar + Bias ux-design-lead Toward KISS

Plan: `knowledge-base/project/plans/2026-06-08-refactor-collapsed-sidebar-declutter-and-ux-kiss-plan.md`
Lane: cross-domain

## 1. Setup / RED

- [ ] 1.1 Update `apps/web-platform/test/workspace-context-band.test.tsx` collapsed-state cases to assert *absence* of `live-repo-dot` and *absence* of the collapsed single-letter `nav-section-title`; keep expanded/mobile full-text `nav-section-title` assertions intact. (RED — fails against current component.)
- [ ] 1.2 Confirm `apps/web-platform/test/nav-rail-drill.test.tsx` rail-band `nav-section-title` assertions target the expanded band (no collapse set) and stay green; adjust only if a collapsed dependency exists.
- [ ] 1.3 Update `apps/web-platform/e2e/nav-states-shell.e2e.ts` (`:525`, `:606`) to replace `live-repo-dot` visibility with the `workspace-identity-icon` collapsed invariant. (RED.)

## 2. Core Implementation / GREEN

- [ ] 2.1 In `apps/web-platform/components/dashboard/workspace-context-band.tsx`, delete the collapsed-branch `live-repo-dot` `<span>` (the gold `●`, `:117-124`).
- [ ] 2.2 Delete the collapsed-branch single-letter `nav-section-title` `<span>` (`:125-133`); leave the non-collapsed full-text title (`:199-206`) untouched.
- [ ] 2.3 Audit the collapsed container's `flex flex-col items-center gap-3` after removal — no orphaned empty slot (AC4).
- [ ] 2.4 Verify the collapsed `workspace-identity-icon` / `WorkspaceIdentityTile` is retained verbatim (AC3).

## 3. Other-screens sweep (verify "everywhere")

- [ ] 3.1 Run `grep -rn '●' apps/web-platform/components --include=*.tsx | grep -v node_modules`; confirm only legitimate separators/bullets/masks remain (enumerated in plan Research Reconciliation). Record output in PR body (AC8).

## 4. ux-design-lead KISS principle

- [ ] 4.1 Add a design-time KISS/simplicity principle to `## Step 2: Design` in `plugins/soleur/agents/product/design/ux-design-lead.md`. Do NOT touch the `description:` line (AC9).
- [ ] 4.2 Reconcile `.openhands/skills/ux-design-lead/SKILL.md` — mirror the principle if it duplicates the design workflow; note divergence otherwise (AC10).

## 5. Verify

- [ ] 5.1 `tsc --noEmit` clean for `apps/web-platform`.
- [ ] 5.2 `./node_modules/.bin/vitest run test/workspace-context-band.test.tsx test/nav-rail-drill.test.tsx` — all green.
- [ ] 5.3 Confirm ACs 1-11 in the plan are satisfied; capture sweep grep output for the PR body.
