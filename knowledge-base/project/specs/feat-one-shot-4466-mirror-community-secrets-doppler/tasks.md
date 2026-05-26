---
title: "Tasks: mirror community-monitor secrets prd_scheduled to prd Doppler"
plan: knowledge-base/project/plans/2026-05-26-chore-mirror-community-secrets-doppler-plan.md
lane: procedural
---

# Tasks: Mirror community-monitor secrets prd_scheduled -> prd Doppler

## Phase 1: Create plan + PR (code change)

- [x] 1.1 Commit plan file to feature branch
- [x] 1.2 Open PR with `Ref #4466` in body
- [x] 1.3 Add labels: `semver:patch`, `priority/p1-high`, `domain/operations`
- [ ] 1.4 Mark PR ready for review

## Phase 2: Post-merge operator action (Doppler CLI)

- [ ] 2.1 Run mirror loop: copy 7 secrets from `prd_scheduled` to `prd` via `doppler secrets set` stdin form
- [ ] 2.2 Verify count: `doppler secrets -p soleur -c prd --only-names` grep returns 7
- [ ] 2.3 Round-trip equality probe: `diff` on `DISCORD_WEBHOOK_URL` between configs returns empty

## Phase 3: Post-fire verification

- [ ] 3.1 After next 08:00 UTC fire, verify no new FAILED issue created
- [ ] 3.2 Close #4466 via `gh issue close 4466 --reason completed`
