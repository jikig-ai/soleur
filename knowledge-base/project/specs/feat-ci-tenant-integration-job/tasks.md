---
title: "Tasks: feat(ci): tenant-integration workflow"
plan: knowledge-base/project/plans/2026-05-16-feat-ci-tenant-integration-workflow-plan.md
date: 2026-05-16
lane: single-domain
---

# Tasks: feat(ci): tenant-integration workflow

## Phase 0 — Preconditions

- [ ] 0.1 Confirm `DOPPLER_TOKEN_DEV_SCHEDULED` GH secret exists
  (`gh secret list | grep DOPPLER_TOKEN_DEV_SCHEDULED`). Done at plan time.
- [ ] 0.2 Confirm Doppler `dev_scheduled` config resolves to
  `environment=dev` (`doppler configs -p soleur --json | jq '.[] |
  select(.name=="dev_scheduled") | .environment'`). Done at plan time.
- [ ] 0.3 Verify the dev_scheduled token can read 4 Supabase secrets
  (`SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`,
  `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWT_SECRET`) via `doppler secrets
  get … --plain | wc -c` per `hr-never-paste-secrets-via-bang-prefix`.
- [ ] 0.4 Confirm all 12 tenant-isolation test files use the literal
  `process.env.TENANT_INTEGRATION_TEST === "1"` gate.
- [ ] 0.5 Confirm vitest `unit` project picks up
  `test/server/*.tenant-isolation.test.ts` (run with
  `TENANT_INTEGRATION_TEST=0` and expect 12 skipped).

## Phase 1 — Author workflow YAML

- [ ] 1.1 Create `.github/workflows/tenant-integration.yml` per the
  Reference Implementation in the plan.
- [ ] 1.2 Verify SHA pins match AC9 (5 actions, all already in use across
  other workflows).
- [ ] 1.3 Verify path-filter globs against `git ls-files` (12 / 104 / 55).

## Phase 2 — Static validation (local)

- [ ] 2.1 `actionlint .github/workflows/tenant-integration.yml`
  (LOCAL ONLY — no CI workflow lints workflows; see SE7 + Enhancement
  Summary §3-4).
- [ ] 2.2 `yamllint -d relaxed .github/workflows/tenant-integration.yml`.
- [ ] 2.3 `bash -c '<extracted vitest snippet>'` shell parse check (NOT
  `bash -n` per SE6).

## Phase 3 — Push, verify CI fires

- [ ] 3.1 Push commit to `feat-ci-tenant-integration-job`.
- [ ] 3.2 Confirm `tenant-integration` check appears on PR #3893 via
  `gh pr checks 3893`.
- [ ] 3.3 Confirm workflow runs green; vitest summary matches AC6 band
  (`Test Files 12 passed (12)` + `Tests 5[5-6] passed( | [01] todo)?`).
- [ ] 3.4 AC11 silent-skip sanity check locally (`TENANT_INTEGRATION_TEST=0
  npm run test:ci -- test/server/ --project unit --reporter=verbose` in
  `apps/web-platform/` → expect 12 skipped).

## Phase 4 — PR body wiring

- [ ] 4.1 Update PR #3893 body:
  - `Closes #3869`
  - `Ref #3244` and `Ref #3883`
  - "Verification log" with workflow run URL + vitest summary + AC11 output
  - Note: small infra-only PR; prerequisite for PR-D #3883

## Phase 5 — Compound learning capture

- [ ] 5.1 If any unexpected behavior surfaces (vitest project resolution,
  Doppler token scope mismatch, npm-vs-bun parity surprise, dispatch
  rejection), capture as a learning under `knowledge-base/project/learnings/`
  per `wg-every-session-error-must-produce-either`.
