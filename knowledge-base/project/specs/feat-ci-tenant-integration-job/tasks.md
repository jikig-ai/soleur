---
title: "Tasks: feat(ci): tenant-integration workflow"
plan: knowledge-base/project/plans/2026-05-16-feat-ci-tenant-integration-workflow-plan.md
date: 2026-05-16
lane: single-domain
---

# Tasks: feat(ci): tenant-integration workflow

## Phase 0 — Preconditions

- [x] 0.1 Confirm `DOPPLER_TOKEN_DEV_SCHEDULED` GH secret exists
  (`gh secret list | grep DOPPLER_TOKEN_DEV_SCHEDULED`). Done at plan time.
- [x] 0.2 Confirm Doppler `dev_scheduled` config resolves to
  `environment=dev` (`doppler configs -p soleur --json | jq '.[] |
  select(.name=="dev_scheduled") | .environment'`). Done at plan time.
- [x] 0.3 Verify the dev_scheduled token can read 4 Supabase secrets
  (`SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`,
  `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWT_SECRET`) via `doppler secrets
  get … --plain | wc -c` per `hr-never-paste-secrets-via-bang-prefix`.
  (559 bytes total, non-empty.)
- [x] 0.4 Confirm all 12 tenant-isolation test files use the literal
  `process.env.TENANT_INTEGRATION_TEST === "1"` gate. (12/12 matches.)
- [x] 0.5 Confirm vitest `unit` project picks up
  `test/server/*.tenant-isolation.test.ts` (run with
  `TENANT_INTEGRATION_TEST=0` and expect 12 skipped). (Confirmed: 12 files
  skipped, 55 tests skipped under `TENANT_INTEGRATION_TEST=0`.)

## Phase 1 — Author workflow YAML

- [x] 1.1 Create `.github/workflows/tenant-integration.yml` per the
  Reference Implementation in the plan. (118 lines.)
- [x] 1.2 Verify SHA pins match AC9 (5 actions, all already in use across
  other workflows).
- [x] 1.3 Verify path-filter globs against `git ls-files` (12 / 104 / 55).

## Phase 2 — Static validation (local)

- [x] 2.1 `actionlint .github/workflows/tenant-integration.yml`
  (LOCAL ONLY — no CI workflow lints workflows; see SE7 + Enhancement
  Summary §3-4). (Only SC2020 info-level shellcheck noise on the
  `tr -d '\r\n\f\v\x7f\x85'` strip; identical to
  `scheduled-realtime-probe.yml` precedent which ships with the same.)
- [x] 2.2 `yamllint -d relaxed .github/workflows/tenant-integration.yml`.
  (Local yamllint pipx venv broken — bad python interpreter; actionlint
  YAML parse covers structural validation. Noted as env issue, not file
  issue.)
- [x] 2.3 `bash -c '<extracted vitest snippet>'` shell parse check (NOT
  `bash -n` per SE6). (Parsed clean.)

## Phase 3 — Push, verify CI fires

- [x] 3.1 Push commit to `feat-ci-tenant-integration-job`. (Handled by
  pipeline-mode ship phase.)
- [ ] 3.2 Confirm `tenant-integration` check appears on PR #3893 via
  `gh pr checks 3893`. (Handled by ship phase.)
- [ ] 3.3 Confirm workflow runs green; vitest summary matches AC6 band
  (`Test Files 12 passed (12)` + `Tests 5[5-6] passed( | [01] todo)?`).
  (Handled by ship phase / post-merge verification.)
- [x] 3.4 AC11 silent-skip sanity check locally (`TENANT_INTEGRATION_TEST=0
  npm run test:ci -- test/server/ --project unit --reporter=verbose` in
  `apps/web-platform/` → expect 12 skipped). (Confirmed: `Test Files 11
  passed | 12 skipped (23); Tests 108 passed | 55 skipped | 1 todo (164)`.
  Gate logic verified — silent-skip trap is correctly identified.)

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
