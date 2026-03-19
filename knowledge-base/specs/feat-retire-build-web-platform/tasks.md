# Tasks: Retire build-web-platform.yml

**Plan:** `knowledge-base/plans/2026-03-19-chore-retire-build-web-platform-workflow-plan.md`
**Issue:** #752

## Phase 1: Delete the Workflow

- [ ] 1.1 Delete `.github/workflows/build-web-platform.yml`
- [ ] 1.2 Verify no other workflows reference `build-web-platform` (grep `.github/`)

## Phase 2: Verify No Regressions

- [ ] 2.1 Confirm `web-platform-release.yml` runs successfully on main (check recent runs)
- [ ] 2.2 Confirm `feat/web-platform-ux` branch does not exist on remote

## Phase 3: Ship

- [ ] 3.1 Run compound
- [ ] 3.2 Commit and push
- [ ] 3.3 Create PR with `Closes #752` in body
- [ ] 3.4 Merge and verify
