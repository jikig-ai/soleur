---
title: "feat(ci): tenant-integration workflow (closes #3869 item 6, unblocks PR-D)"
date: 2026-05-16
type: feat
lane: single-domain
status: ready-for-work
issue: 3869
related_pr: 3883
classification: infra-only
risk: low
requires_cpo_signoff: false
---

# feat(ci): tenant-integration workflow (closes #3869 item 6, unblocks PR-D)

## Enhancement Summary

**Deepened on:** 2026-05-16
**Sections enhanced:** Research Reconciliation, Implementation Phase 1,
Reference Implementation, Acceptance Criteria, Risks & Sharp Edges
**Verification mode:** live `gh issue view`, live `gh secret list`, live
`doppler configs`, live `git ls-files` + grep against `main@HEAD` and the
worktree's installed file state

### Key improvements

1. **Live citation audit (all green except 1 minor).** All 10 cited
   PRs/issues exist with the claimed state. **Correction:** #3878 is
   `CLOSED` (the plan implicitly treats it as open by saying "tracked in
   #3878's verification block"); since `CLOSED` is the terminal state, the
   tracking-block reference is historical and still accurate — no edit
   needed but documented here.
2. **Vitest invocation form correction.** Deepen surfaced that
   `scripts/test-all.sh` line 145-146 runs vitest via `npm run test:ci`
   (NOT `bun x vitest`) inside the bun-installed environment. AC5 +
   Reference Implementation updated to match — uses `npm run test:ci --`
   form for parity with `test-webplat`. (Original task argument's
   `./node_modules/.bin/vitest` form would not benefit from the existing
   bun cache; npm form does.)
3. **`infra-validation.yml` does NOT lint new workflows.** Deepen check
   `grep -nE 'on:|paths:' .github/workflows/infra-validation.yml`
   confirmed it triggers only on `paths: .github/workflows/infra-
   validation.yml`. SE7 corrected — actionlint is a LOCAL-ONLY check; no
   CI gate validates the new workflow YAML.
4. **No actionlint in CI.** `grep -rE 'actionlint' .github/workflows/`
   returns zero matches. AC1 split into local validation (actionlint +
   yamllint) and a follow-up out-of-scope item (#OOS-09) to wire repo-wide
   workflow lint into `pr-quality-guards.yml`.
5. **SHA pins verified.** All 5 SHA pins prescribed in AC9 are already in
   active use across other workflows (`actions/checkout` in 54 files,
   `setup-node` in 5, `setup-bun` in 5, `actions/cache` in 1,
   `DopplerHQ/cli-action@5351…` in 4). No fresh-from-internet SHAs.
6. **Gate literal uniformity.** P0.4 verified at deepen time:
   `process.env.TENANT_INTEGRATION_TEST === "1"` literal appears
   identically in all 12 files.
7. **Path-filter globs confirmed.** All 3 globs match real files
   (12 / 104 / 55).
8. **GitHub labels.** No new labels required (no `gh issue create` in this
   PR's scope). Existing `domain/engineering`, `priority/p3-low`, `chore`
   confirmed via `gh label list`.

### New considerations discovered

- **`bun install` vs `npm install` for vitest invocation.** Because
  `scripts/test-all.sh` calls `npm run test:ci`, the workflow uses bun
  for install (cache parity) but npm for invocation (correctness parity
  with `test-webplat`). Documented in SE3.
- **No CI-side workflow lint coverage.** New surface for follow-up
  (#OOS-09) to wire a repo-wide `actionlint` check; not blocking for this
  PR.

## Overview

Infra-only PR: add `.github/workflows/tenant-integration.yml` that runs the 12
`apps/web-platform/test/server/*.tenant-isolation.test.ts` files under
`TENANT_INTEGRATION_TEST=1` with Doppler-gated dev-Supabase secrets, so the
PR-C tenant-isolation suite (and the new PR-D Storage deny tests landing in
#3883) stops silent-skipping in default CI.

The trap this closes: every `*.tenant-isolation.test.ts` file uses
`describe.skipIf(!INTEGRATION_ENABLED)(...)` where `INTEGRATION_ENABLED =
process.env.TENANT_INTEGRATION_TEST === "1"`. The existing `test-webplat`
shards in `.github/workflows/ci.yml` do NOT export that flag, so vitest
silently reports the suites as `skipped` (or, in vitest 3's terse summary,
folds them into "no tests" because every `describe.skipIf` evaluates to an
empty block). The suite reports green even when a regression breaks tenant
isolation — exactly the failure mode that motivated PR-C / PR-D in the first
place.

**Scope is one file + one secret-provisioning step.** No runtime code, no
migrations, no app changes. Per `hr-write-boundary-sentinel-sweep-all-write-sites`
this is *test-infra* and is permitted to live independently of code edits.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-visible — the
  workflow is CI-only. The risk is silent: a broken workflow leaves the
  silent-skip trap in place and PR-D's Storage deny tests pass vacuously.
- **If this leaks, the user's data is exposed via:** N/A — the workflow uses
  dev Supabase only and the Doppler token is scoped to a `dev`-environment
  config (asserted at runtime per `hr-dev-prd-distinct-supabase-projects`).
  No prod credentials are touched.
- **Brand-survival threshold:** none. **Reason:** The workflow is a CI gate
  on dev-Supabase test infra; failure mode is "PR-D ships with a vacuous
  green" which is a workflow-quality issue, not a user-data exposure. The
  user-impact gate carry-forward from PR-D (`single-user incident`) applies
  to PR-D's runtime code, not to this prerequisite's workflow YAML.

## Research Reconciliation — Spec vs. Codebase

The task argument names secret `DOPPLER_TOKEN_DEV` and Doppler config
`-c dev`. Live verification against `gh secret list` and `doppler configs
-p soleur` shows neither exists in the actual form named. The plan corrects
to the canonical names; AC and PR-body wording reflect the correction.

| Spec / task claim | Codebase reality | Plan response |
|---|---|---|
| Use `DOPPLER_TOKEN_DEV` GitHub secret. | `gh secret list` returns: `DOPPLER_TOKEN`, `DOPPLER_TOKEN_DEV_SCHEDULED`, `DOPPLER_TOKEN_PRD`, `DOPPLER_TOKEN_SCHEDULED`. NO `DOPPLER_TOKEN_DEV`. | Use the existing `DOPPLER_TOKEN_DEV_SCHEDULED` (precedent: `scheduled-realtime-probe.yml:83`). It is scoped to the `dev_scheduled` Doppler config which resolves to `environment=dev`. |
| Invoke as `doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 …`. | `doppler configs -p soleur --json` returns 3 dev-environment configs: `dev`, `dev_personal`, `dev_scheduled`. The `dev` config is the local-dev workspace; `dev_scheduled` is the CI-scoped config and the only one a GH secret token currently authorizes. | Invoke as `doppler run -p soleur -c dev_scheduled -- env TENANT_INTEGRATION_TEST=1 npm run test:ci -- test/server/ --project unit --reporter=verbose` (npm form mirrors `test-webplat` per `scripts/test-all.sh:145-146` — see SE3). |
| "Reports `Test Files 12 passed (12); Tests 55 passed \| 1 todo (56)` per post-#3881 baseline." | `ls apps/web-platform/test/server/*.tenant-isolation.test.ts \| wc -l` = 12. The post-#3881 baseline is documented in plan `2026-05-16-fix-tenant-isolation-tests-3878-plan.md` AC8: total = 55 (= 42 + 3 + 10) post-fix. The "1 todo" count is provisional and may shift by #3881-followup; AC must tolerate `Tests N passed \| M todo` with N≥55 and totals reconciling to 56. | Plan AC requires exit 0 + summary parseable as `Test Files 12 passed (12)` AND total test count in the band [55, 56] passed/todo, not literal-byte equality. See SE1. |
| Default CI `test-webplat` shards silent-skip the suites. | Confirmed: `.github/workflows/ci.yml:191-241` `test-webplat` job invokes `bash scripts/test-all.sh webplat` which runs `vitest --shard` with no `TENANT_INTEGRATION_TEST` export. The 12 `*.tenant-isolation.test.ts` files all use `describe.skipIf(!INTEGRATION_ENABLED)`. | Plan rationale; no codebase change beyond the new workflow file. |
| Wrapper-vs-curl: `claude-code-action` or `peter-evans/create-pull-request`. | Not applicable — single-shot vitest invocation, no PR creation. | None. Workflow is direct `bun install` + `vitest run`, mirroring `scheduled-realtime-probe.yml`. |
| Vitest project assignment for `test/server/*.tenant-isolation.test.ts`. | `apps/web-platform/vitest.config.ts:25-30` `unit` project `include: ["test/**/*.test.ts", "lib/**/*.test.ts"]`. The tenant-isolation files match `test/server/*.tenant-isolation.test.ts` which is a subset of `test/**/*.test.ts`. They run under the `unit` project by default. | Invoke as `vitest run test/server/ --project unit` (explicit `--project unit` avoids the component project picking up `.test.tsx` siblings in adjacent dirs). |
| Bun vs npm install for `apps/web-platform`. | `.github/workflows/ci.yml:225` uses `bun install --frozen-lockfile`; vitest is invoked via `bash scripts/test-all.sh webplat` which internally calls `npm run test:ci` (per `scripts/test-all.sh:145-146`). `apps/web-platform/.bun-version` exists. | Use `bun install --frozen-lockfile` for cache + lock parity. Invoke vitest via `npm run test:ci -- …` for invocation parity with `test-webplat` (not `bun x` and not the binstub form — see SE3). |

## Files to Edit

(none)

## Files to Create

- `.github/workflows/tenant-integration.yml` — the workflow YAML

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open` for any open
scope-out touching `.github/workflows/tenant-integration.yml`,
`apps/web-platform/test/server/`, or `tenant-isolation`. Single hit:
**#3272 (review: pin authTagLength: 16 on byok.ts createDecipheriv calls)**
— matches on `tenant-isolation` only because the issue body cross-references
the BYOK isolation tests. Disposition: **acknowledge** — #3272 is a runtime
crypto pin under `apps/web-platform/lib/byok.ts`, not a CI workflow or test
concern. This PR's scope is one new workflow file; folding the BYOK pin in
would be unrelated scope creep. #3272 remains open.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1.** `.github/workflows/tenant-integration.yml` exists. **Local
  validation only** (no CI workflow lints workflows today — confirmed at
  deepen time, see Enhancement Summary §3-4): parses clean via
  `actionlint <file>` AND `yamllint -d relaxed <file>` AND `bash -c
  "<extracted vitest invocation>"` parses clean. (Per Sharp Edge: do NOT
  use `bash -n <file.yml>` — it parses the YAML header as bash and fails.)
  The PR-time gate is the workflow's own first-run success on `push:` or
  `pull_request:` to a path-filter match (AC6).
- **AC2.** Workflow triggers on:
  - `push:` to `main` with `paths:` filter matching
    `apps/web-platform/test/server/**.tenant-isolation.test.ts`,
    `apps/web-platform/server/**`, OR
    `apps/web-platform/supabase/migrations/**`
  - `pull_request:` against `main` with the same `paths:` filter
  - `workflow_dispatch: {}` (manual re-run + initial verification per
    `pre-merge verification of a new CI workflow` sharp-edge below)
- **AC3.** Workflow includes a Doppler-token precondition that **fails the
  job with `exit 1`** (NOT silent-skip) if `DOPPLER_TOKEN_DEV_SCHEDULED` is
  missing or empty. The error message names the secret and the canonical
  provisioning command (`gh secret set DOPPLER_TOKEN_DEV_SCHEDULED`). Per
  the `If DOPPLER_TOKEN_DEV is missing, abort the job with a clear error`
  task constraint and per `hr-dev-prd-distinct-supabase-projects`.
- **AC4.** Workflow includes a Doppler-config drift assertion that resolves
  `doppler configs get dev_scheduled -p soleur --json | jq -r
  '.environment // empty'` and **fails with exit 1** if the result is not
  literal `dev`. (Per `hr-dev-prd-distinct-supabase-projects` and the
  `scheduled-realtime-probe.yml:128-139` precedent.) The check resolves
  BEFORE any test invocation.
- **AC5.** Workflow runs against current `main` + dev Supabase via
  `npm run test:ci -- test/server/ --project unit --reporter=verbose`
  under `doppler run -p soleur -c dev_scheduled -- env
  TENANT_INTEGRATION_TEST=1 …` (working directory `apps/web-platform`).
  **Why npm not bun:** `scripts/test-all.sh:145-146` invokes
  `npm run test:ci` for the `test-webplat` job; using the same invocation
  guarantees byte-identical behavior (vitest binary resolution, env
  forwarding, exit-code propagation). Bun is used only for install (cache
  parity with `test-webplat`). See SE3 + Enhancement Summary §2.
- **AC6.** First successful workflow run (triggered via `gh workflow run
  tenant-integration.yml --ref feat-ci-tenant-integration-job` AFTER the PR
  is opened and BEFORE the PR is marked ready) reports exit 0 and a vitest
  summary parseable as:
  - `Test Files [\s]+12 passed \(12\)` (exact count of 12)
  - `Tests [\s]+5[5-6] passed( \| [01] todo)?` (band [55, 56] tolerates
    todo-count drift per Research Reconciliation row 3)
- **AC7.** `bash -c '<vitest invocation>'` is the locally-runnable form, NOT
  `bash -n <file.yml>`. (Per Sharp Edge `2026-05-11-multi-word-required-
  check-exposes-strip-all-whitespace-bug.md`.)
- **AC8.** Workflow YAML contains zero `gh pr merge`, zero `--auto`, zero
  `|| gh pr merge` fail-open patterns. (Per learning
  `2026-03-19-ci-squash-fallback-bypasses-merge-gates.md`.)
- **AC9.** Workflow uses only SHA-pinned actions for every `uses:` entry.
  Reuse the exact pins already in `scheduled-realtime-probe.yml`:
  - `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`
  - `actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0`
    (NOT load-bearing here since we use bun, but kept available)
  - `oven-sh/setup-bun@3d267786b128fe76c2f16a390aa2448b815359f3 # v2.1.2`
  - `actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830 # v4.3.0`
  - `DopplerHQ/cli-action@5351693ec144fc7f7a2d30025061acfc3c53c47c # v4`
    (matching `apply-deploy-pipeline-fix.yml:95` — the freshest pin)
- **AC10.** Workflow inherits the bun cache key from `test-webplat`:
  `bun-webplat-${{ runner.os }}-${{ hashFiles('apps/web-platform/bun.lock') }}`.
- **AC11.** Sanity check on the silent-skip gate: maintainer runs locally
  `TENANT_INTEGRATION_TEST=0 npm run test:ci -- test/server/ --project
  unit --reporter=verbose` in `apps/web-platform/` and confirms vitest
  reports the 12 files as `skipped` (NOT failed, NOT errored). Outcome
  recorded in the PR body under "Verification log".
- **AC12.** PR title is exactly
  `feat(ci): tenant-integration workflow (closes #3869 item 6, unblocks PR-D)`.
- **AC13.** PR body cites `Closes #3869` (not in title, per
  `wg-use-closes-n-in-pr-body-not-title-to`) AND `Ref #3244` AND `Ref #3883`.
- **AC14.** Workflow file size is ≤ 200 lines (forcing a small-PR shape;
  precedent `scheduled-realtime-probe.yml` is ~320 lines but includes a
  Sentry-monitor + issue-filing block this workflow deliberately omits per
  Out of Scope §2).
- **AC15.** No `workflow_call:` and no concurrency `cancel-in-progress: true`
  on `pull_request` triggers (test-integration runs should not cancel each
  other; a PR with two pushes in a minute gets two completed runs).
- **AC16.** Concurrency group is `tenant-integration-${{ github.ref }}` with
  `cancel-in-progress: false` (matches `apply-deploy-pipeline-fix.yml`
  cancel discipline).

### Post-merge (operator)

None. The workflow is self-contained; first post-merge run fires
automatically on the next PR that touches a path-filter glob.

## Verification Plan

### Local

1. From repo root: `actionlint .github/workflows/tenant-integration.yml`.
2. From repo root: `yamllint -d relaxed .github/workflows/tenant-integration.yml`.
3. Extract the vitest invocation as a bash snippet and verify shape with
   `bash -c 'cd apps/web-platform && echo npm run test:ci -- test/server/ --project unit --reporter=verbose'` (parse check only — no execution against live Supabase locally; the dev token is operator-scoped).
4. AC11 silent-skip sanity check (see above).

### Remote (post-PR-open, pre-ready)

1. `gh workflow run tenant-integration.yml --ref feat-ci-tenant-integration-job`.
   **Sharp Edge:** `workflow_dispatch` against a feature branch requires
   the workflow file to exist on the default branch first. **Mitigation:**
   the workflow's `pull_request:` trigger fires on the PR push itself, so
   the first remote run happens automatically via the PR's path-filter
   match. The `gh workflow run` manual form will only succeed after merge.
   Document this in the PR body so post-open verification uses the
   PR-event path, not `workflow_dispatch`.
2. Confirm green on the PR's `tenant-integration` check via `gh pr checks 3893`.
3. Inspect the vitest summary in the run log; assert AC6 parse.

## Test Strategy

- **Static:** actionlint + yamllint (covered by `infra-validation.yml` on
  PR — verify it auto-picks up the new file via its path filter; if not,
  add `tenant-integration.yml` to its `paths:`).
- **Dynamic:** the workflow itself IS the test. Its first run against the
  PR validates correctness end-to-end (Doppler resolution, env propagation,
  vitest gate, dev-Supabase reachability).
- **Negative:** AC11's `TENANT_INTEGRATION_TEST=0` sanity proves the gate
  reports `skipped` (not `passed`) when the env var is absent — proving
  the gate logic is the right side of the silent-skip trap.

## Implementation Phases

### Phase 0 — Preconditions (verify before writing the YAML)

- [ ] **P0.1** Confirm `DOPPLER_TOKEN_DEV_SCHEDULED` secret exists:
  `gh secret list | grep DOPPLER_TOKEN_DEV_SCHEDULED`. (Done at plan time:
  ✅ present, last rotated 2026-05-11.)
- [ ] **P0.2** Confirm `dev_scheduled` Doppler config exists and resolves
  to `environment=dev`. (Done at plan time: ✅ via `doppler configs -p
  soleur --json` — `dev_scheduled -> dev`.)
- [ ] **P0.3** Verify token can read the 4 required Supabase secrets:
  `doppler secrets get SUPABASE_URL NEXT_PUBLIC_SUPABASE_ANON_KEY
  SUPABASE_SERVICE_ROLE_KEY SUPABASE_JWT_SECRET -p soleur -c dev_scheduled
  --plain` returns 4 non-empty values. **DO NOT echo the values to logs**
  (per `hr-never-paste-secrets-via-bang-prefix`); use `wc -c` byte counts
  to confirm non-empty.
- [ ] **P0.4** Verify the 12 tenant-isolation files all gate on the SAME
  env-var name: `grep -lE 'process\.env\.TENANT_INTEGRATION_TEST.*"1"'
  apps/web-platform/test/server/*.tenant-isolation.test.ts | wc -l` must
  equal `12`. (Generalizes paraphrase-without-verification: the gate
  literal must match `=== "1"`, not `=== "true"` or truthy-coerce. Done
  at plan time: needs confirmation at implementation time.)
- [ ] **P0.5** Verify vitest project membership: invoke
  `cd apps/web-platform && npm run test:ci -- test/server/ --project unit
  --reporter=json --bail=0 --no-coverage 2>/dev/null | head -200` (the
  JSON reporter exits 0 even if individual files skip; `--project unit`
  confirms the include glob matches). Locally with
  `TENANT_INTEGRATION_TEST=0` this should produce a 12-file `skipped`
  summary.

### Phase 1 — Author the workflow YAML

- [ ] **P1.1** Create `.github/workflows/tenant-integration.yml` modeled on
  `scheduled-realtime-probe.yml` (Doppler precondition + drift assertion
  pattern) and `apply-deploy-pipeline-fix.yml` (path-filter + permission +
  concurrency pattern). See "Reference Implementation" below.
- [ ] **P1.2** Verify SHA pins match those listed in AC9.
- [ ] **P1.3** Verify path-filter globs against repo reality:
  `git ls-files | grep -cE 'apps/web-platform/test/server/.*tenant-
  isolation\.test\.ts$'` = 12 (✅ confirmed at plan time);
  `git ls-files | grep -cE 'apps/web-platform/server/'` = 104 (✅);
  `git ls-files | grep -cE 'apps/web-platform/supabase/migrations/'` = 55
  (✅).

### Phase 2 — Static validation

- [ ] **P2.1** `actionlint .github/workflows/tenant-integration.yml`.
- [ ] **P2.2** `yamllint -d relaxed .github/workflows/tenant-integration.yml`.
- [ ] **P2.3** Extract the vitest `run:` block and run `bash -c '<block>'`
  for shell parse-check ONLY (no execution). Per AC7 / Sharp Edges §SE6.

### Phase 3 — Push, open PR, verify CI fires

- [ ] **P3.1** Push the commit; PR #3893 (already open) re-validates checks.
- [ ] **P3.2** Confirm the `tenant-integration` workflow appears as a check
  on PR #3893 (the `pull_request` trigger fires because the new workflow
  file's own `paths:` filter does NOT match `.github/workflows/*` — the
  trigger filter governs the workflow's RE-runs, not its first
  registration). Verify via `gh pr checks 3893`.
- [ ] **P3.3** Confirm the workflow run is green: exit 0, AC6 vitest
  summary parse, no `::error::` annotations.
- [ ] **P3.4** AC11 silent-skip sanity (local).

### Phase 4 — PR body wiring

- [ ] **P4.1** Update PR body to include:
  - `Closes #3869` (covers item 6)
  - `Ref #3244` (umbrella) and `Ref #3883` (PR-D — this unblocks)
  - "Verification log" section pasting the green workflow run URL + AC6
    vitest summary screenshot/text + AC11 local-skip output
  - Explicit note: "small infra-only PR; no app code; explicit prerequisite
    for PR-D #3883"

### Phase 5 — Compound learning capture

- [ ] **P5.1** If implementation surfaces any unexpected behavior (vitest
  project assignment surprise, Doppler-token scope mismatch, bun-vs-npm
  invocation drift, `workflow_dispatch` rejection), capture as a learning
  under `knowledge-base/project/learnings/` per
  `wg-every-session-error-must-produce-either`.

## Reference Implementation

```yaml
# .github/workflows/tenant-integration.yml
#
# Runs apps/web-platform/test/server/*.tenant-isolation.test.ts under
# TENANT_INTEGRATION_TEST=1 with dev-Supabase secrets resolved via Doppler.
# Closes the silent-skip trap that lets vitest report green for tenant-
# isolation tests when the gate env var is unset (the default in ci.yml's
# test-webplat job). Unblocks PR-D #3883 which adds new Storage deny
# tests under the same describe.skipIf gate.
#
# Security: DOPPLER_TOKEN_DEV_SCHEDULED is scoped to the dev_scheduled
# Doppler config. A runtime assertion confirms the config resolves to
# environment=dev before any Supabase secret is touched, per
# hr-dev-prd-distinct-supabase-projects.
#
# Triggers (path-filtered): push to main + PRs touching the tenant-
# isolation tests, server/, or supabase/migrations/. The path filter is
# load-bearing — without it the job would run on every PR (~95% of which
# don't touch the tested surfaces) and burn dev-Supabase rate budget.
#
# Refs: #3869 item 6, #3244 (umbrella), #3883 (PR-D).

name: Tenant integration (dev-Supabase)

on:
  push:
    branches: [main]
    paths:
      - 'apps/web-platform/test/server/**.tenant-isolation.test.ts'
      - 'apps/web-platform/server/**'
      - 'apps/web-platform/supabase/migrations/**'
  pull_request:
    branches: [main]
    paths:
      - 'apps/web-platform/test/server/**.tenant-isolation.test.ts'
      - 'apps/web-platform/server/**'
      - 'apps/web-platform/supabase/migrations/**'
  workflow_dispatch: {}

concurrency:
  group: tenant-integration-${{ github.ref }}
  cancel-in-progress: false

permissions:
  contents: read

jobs:
  tenant-integration:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1

      - name: Setup Bun
        uses: oven-sh/setup-bun@3d267786b128fe76c2f16a390aa2448b815359f3 # v2.1.2
        with:
          bun-version-file: .bun-version

      - name: Cache bun install (apps/web-platform)
        uses: actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830 # v4.3.0
        with:
          path: |
            ~/.bun/install/cache
            apps/web-platform/node_modules
          key: bun-webplat-${{ runner.os }}-${{ hashFiles('apps/web-platform/bun.lock') }}
          restore-keys: |
            bun-webplat-${{ runner.os }}-

      - name: Install web-platform dependencies
        working-directory: apps/web-platform
        run: bun install --frozen-lockfile

      - name: Install Doppler CLI
        uses: DopplerHQ/cli-action@5351693ec144fc7f7a2d30025061acfc3c53c47c # v4

      - name: Verify DOPPLER_TOKEN_DEV_SCHEDULED is provisioned
        env:
          DOPPLER_TOKEN_CHECK: ${{ secrets.DOPPLER_TOKEN_DEV_SCHEDULED }}
        run: |
          set -uo pipefail
          if [[ -z "${DOPPLER_TOKEN_CHECK:-}" ]]; then
            echo "::error::DOPPLER_TOKEN_DEV_SCHEDULED is not set. Provision a dev-scoped Doppler service token (admin Doppler CLI access required) and 'gh secret set DOPPLER_TOKEN_DEV_SCHEDULED' from a separate terminal. Aborting — do NOT silent-skip (would re-create the gate trap this workflow closes)."
            exit 1
          fi

      - name: Assert Doppler config resolves to environment=dev
        env:
          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_DEV_SCHEDULED }}
        run: |
          set -uo pipefail
          env_name=$(doppler configs get dev_scheduled -p soleur --json 2>/dev/null \
            | jq -r '.environment // empty') || env_name=""
          if [[ -z "$env_name" ]]; then
            echo "::error::doppler configs get dev_scheduled -p soleur returned empty. Config does not exist or token lacks read access."
            exit 1
          fi
          if [[ "$env_name" != "dev" ]]; then
            # Strip CR/LF/Unicode-separators before echoing env_name into
            # ::error:: to avoid log-injection (per scheduled-realtime-probe.yml
            # strip_log_injection precedent).
            env_safe=$(printf '%s' "$env_name" | tr -d '\r\n\f\v\x7f\x85')
            echo "::error::dev_scheduled config resolves to environment=${env_safe} (expected: dev). Token rotated to wrong scope; reset before running tenant-integration."
            exit 1
          fi
          echo "Doppler config dev_scheduled -> environment=dev (verified)."

      - name: Run tenant-isolation tests
        working-directory: apps/web-platform
        env:
          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_DEV_SCHEDULED }}
        run: |
          set -uo pipefail
          # NOTE: invoke via `npm run test:ci` (not `bun x vitest`) for
          # byte-parity with .github/workflows/ci.yml `test-webplat` job
          # which calls `npm run test:ci` per scripts/test-all.sh:145-146.
          # `--` separates `npm run` args from vitest's args.
          doppler run -p soleur -c dev_scheduled -- \
            env TENANT_INTEGRATION_TEST=1 \
            npm run test:ci -- test/server/ --project unit --reporter=verbose
```

## Risks & Sharp Edges

### SE1 — Vitest summary line drift

Vitest 3.x's verbose-reporter "Test Files" / "Tests" summary lines are
considered stable but not byte-pinned by the project. The AC6 regex
tolerates `Tests N passed | M todo` with N ≥ 55 to absorb #3881-followup
todo-count shifts. If vitest bumps to 4.x and renames headers, AC6's
regex needs an update — flagged in the workflow comment block.

### SE2 — Vitest --project flag

`vitest run test/server/ --project unit` is required because the `unit`
and `component` projects share the `test/` prefix. Without `--project
unit`, vitest evaluates both project includes and the `component` project
(environment: happy-dom, setupFiles) is loaded unnecessarily, adding
startup cost and exposing the run to setup-dom side effects. Verify at
P0.5 that the explicit `--project unit` form runs only the 12 files.

### SE3 — `npm run test:ci` vs `bun x vitest` vs `./node_modules/.bin/vitest`

Task argument prescribed `./node_modules/.bin/vitest`. **Deepen-time
discovery:** `scripts/test-all.sh:144-147` runs the canonical
`test-webplat` shard via `npm run test:ci -- ${VITEST_SHARD:+--shard=…}`
inside the bun-installed `node_modules`. We mirror that form (npm
invocation, bun install) for byte-parity. Why not `bun x vitest`: bun's
`x` form re-resolves the package, which can re-trigger network fetches
under cache eviction, and (per the `bun install` reflink semantics in
this monorepo's `bun.lock@2026-05-16`) is not byte-equivalent to the
`npm run` form used in `test-webplat`. Why not the binstub form: parity
beats inventiveness — `test-webplat` uses `npm run test:ci` and that's
what gets tested on every PR.

### SE4 — workflow_dispatch pre-merge unreachability

Per the existing sharp edge in this skill: `gh workflow run
tenant-integration.yml --ref feat-ci-tenant-integration-job` returns 404
because the workflow file doesn't exist on `main` yet. **Mitigation:** the
PR's own `pull_request` trigger fires on push, so first-run verification
happens via the PR event automatically. Document in PR body.

### SE5 — Path-filter glob shape

The plan uses `apps/web-platform/test/server/**.tenant-isolation.test.ts`
NOT `apps/web-platform/test/server/*.tenant-isolation.test.ts`. The `**`
form matches at any depth; the `*` form matches only the immediate dir.
Currently all 12 files live at the immediate depth, but the `**` form is
future-proof against a tenant-isolation subfolder split. **Verification:**
git-ls-files grep at P1.3 confirms 12 matches against the `**` form.

### SE6 — Do NOT use `bash -n` for shell-block parse check

Per `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md`:
`bash -n <file.yml>` parses the YAML header (`name: Tenant integration …`)
as bash and fails with a confusing error. Use `bash -c '<extracted
snippet>'` for the shell-block parse check, OR rely on `actionlint`
(which handles embedded shell via shellcheck integration).

### SE7 — No CI-side workflow lint coverage

**Deepen-time discovery:** `.github/workflows/infra-validation.yml`
triggers ONLY on `paths: .github/workflows/infra-validation.yml` —
**it does NOT lint other workflows.** `grep -rE 'actionlint' .github/`
returns zero matches: no workflow runs `actionlint` against the workflow
corpus. The new `tenant-integration.yml` will get NO CI-side YAML
validation pre-merge. **Mitigation:** AC1 prescribes local
`actionlint` + `yamllint -d relaxed` as a hard pre-push gate.
**Follow-up:** OOS-09 below tracks adding repo-wide workflow lint to
`pr-quality-guards.yml` (out of scope here — separate concern + cross-
cutting change).

### SE8 — Bun vs npm install lock drift

`apps/web-platform/bun.lock` is the source of truth for the workflow's
cache key. If a future package.json change is committed without a
corresponding `bun install` regenerating `bun.lock`, the cache key shifts
silently. Out of scope for this PR (existing `test-webplat` has the same
property) but flagged.

### SE9 — Numeric-claim self-consistency

AC6 asserts "band [55, 56]" passed/todo. Per the planning skill's
aggregate-numeric-target sharp edge, the per-file contributions sum to
55 (= 42 + 3 + 10) per plan `2026-05-16-fix-tenant-isolation-tests-3878-plan.md`
AC8, OR 56 if the post-#3881 todo lands. Both numbers reconcile with the
12-file count. AC6 tolerates BOTH.

### SE10 — Filling the plan's "User-Brand Impact" threshold = `none`

This PR's threshold is `none`. Per the planning skill's gate, when
threshold = `none` AND diff touches a sensitive path, the section MUST
contain a `threshold: none, reason: <one-sentence non-empty reason>`
bullet. The diff touches `.github/workflows/` which is in the canonical
sensitive-path regex (per `plugins/soleur/skills/preflight/SKILL.md`
Check 6 Step 6.1). **Reason for `none`:** workflow is CI-only, gated to
dev-Supabase, runtime-asserted against env-drift, no user-data touch.

### SE11 — `requires_cpo_signoff` carry-forward

PR-D #3883 declared `single-user incident` threshold. This prerequisite
PR is a DIFFERENT artifact — its blast radius is "PR-D ships with vacuous
green" which is a workflow-quality issue, not a user-data incident.
Threshold `none` is correct for this PR; CPO sign-off is not required.
PR-D's CPO sign-off remains intact and unaffected.

## Out of Scope

1. **Sentry crons monitor block.** `scheduled-realtime-probe.yml` includes
   a Sentry check-in (in_progress / ok / error). This workflow is a
   per-PR check, not a scheduled cron — no Sentry monitor needed.
2. **Tracking-issue file/comment block.** Same rationale — PR-level failure
   surfaces in the PR check itself; no separate tracking issue needed.
3. **Email notification on failure.** Per item 1.
4. **Widening daily follow-through monitor's Doppler scope.** Per task
   argument: tracked separately in #3878's verification block.
5. **Migrating `test-webplat` to set `TENANT_INTEGRATION_TEST=1`.** Out of
   scope — would require Doppler-dev secrets on every shard, which is
   over-broad. Per the task argument: `path filter restricts to relevant
   changes`.
6. **Adding `tenant-integration` as a required status check on branch
   protection.** Out of scope for this PR (rule change separate from
   workflow addition). File as follow-up issue if PR-D / future PRs need
   it as a hard gate.
7. **Renaming `dev_scheduled` Doppler config to `ci_tenant_integration`.**
   Out of scope — `dev_scheduled` is multi-purpose (realtime probe +
   tenant-integration) and the rename has migration cost (token rotation,
   workflow updates).
8. **PR-D scope.** PR-D #3883 owns the runtime Storage RLS work; this PR
   is purely the CI prerequisite.
9. **OOS-09 — Repo-wide workflow lint in CI.** Per SE7 / Enhancement
   Summary §3-4: no CI workflow currently runs `actionlint` against the
   `.github/workflows/` corpus. Out of scope here — cross-cutting change
   that would benefit every workflow file, not specific to this PR.
   File as a follow-up issue labeled `chore` + `domain/engineering`
   if deferral is operationally felt (e.g., another fabricated-pin or
   bash-injection slip ships).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. The
artifact is a single workflow YAML; no user-facing UI, no schema change,
no API contract change, no legal/compliance surface, no CMO/CRO/CPO
positioning. Carry-forward from PR-D brainstorm is not warranted because
this PR's scope is mechanically distinct from PR-D's runtime tenant-client
swap.

## References

### Codebase precedents

- `.github/workflows/scheduled-realtime-probe.yml` — Doppler dev-token +
  `dev_scheduled` config + runtime `environment=dev` assertion +
  `strip_log_injection`. **Primary template.**
- `.github/workflows/apply-deploy-pipeline-fix.yml` — path-filter on
  `push: main`, concurrency group + `cancel-in-progress: false`, SHA pin
  on `DopplerHQ/cli-action@5351…` (v4 — freshest).
- `.github/workflows/ci.yml` `test-webplat` job (lines 191-241) —
  `bun install --frozen-lockfile` + `vitest --shard` + cache key shape.
- `apps/web-platform/vitest.config.ts:25-30` — `unit` project glob and
  `isolate: true` semantics.
- `apps/web-platform/test/server/cc-dispatcher.tenant-isolation.test.ts:31` —
  canonical `INTEGRATION_ENABLED = process.env.TENANT_INTEGRATION_TEST
  === "1"` gate.

### AGENTS.md rules

- `hr-dev-prd-distinct-supabase-projects` — runtime assertion required
  (AC4).
- `hr-never-paste-secrets-via-bang-prefix` — P0.3 uses `wc -c` not echo.
- `wg-use-closes-n-in-pr-body-not-title-to` — AC13.
- `cq-test-fixtures-synthesized-only` — tenant tests already use
  synthetic emails (`tenant-isolation-[hex]@soleur.test`); no action.

### Learnings

- `2026-03-19-ci-squash-fallback-bypasses-merge-gates.md` — no `||
  gh pr merge` fallback (AC8).
- `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md`
  — use `bash -c`, not `bash -n` (SE6, AC7).
- `2026-04-29-supabase-phx-join-handshake-shell-environment.md` —
  realtime-probe shell pattern (Reference Implementation borrows shape).

### Related PRs / issues

- `#3869 item 6` — this PR closes.
- `#3244` — umbrella (tenant isolation).
- `#3883` — PR-D (Storage tenant RLS) that this PR unblocks.
- `#3854` — PR-C (which added the 11 tenant-isolation tests + the
  `TENANT_INTEGRATION_TEST` gate, post-#3881 baseline `Test Files 12
  passed`).
- `#3881` — fix-tenant-isolation-tests-3878 (the post-fix baseline that
  AC6 reconciles against).
