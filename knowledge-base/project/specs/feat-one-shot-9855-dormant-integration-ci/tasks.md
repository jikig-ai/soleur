# Tasks — feat: Wire dormant env-gated integration suites into scheduled CI (#9855 PR 2)

Plan: `knowledge-base/project/plans/2026-10-10-feat-dormant-integration-ci-plan.md`
Issue: #9855 (Closes) | PR 1: #9890 (merged) | Draft PR: #9947

Constraint: no live dev-Supabase writes in-session. Pre-merge verification is
static only (actionlint/YAML parse, shellcheck, sentinel battery, `git grep`
census). Live validation is the post-merge `workflow_dispatch` AC.

## Phase 0 — Preconditions

- [ ] 0.1 `gh issue view 9855` — confirm OPEN (this PR closes it).
- [ ] 0.2 Confirm no plan drift: `git log --oneline origin/main -- .github/workflows/tenant-integration.yml scripts/dev-suite-mutex.sh | head -5` — re-read any post-plan changes to the mirrored blocks before copying them.
- [ ] 0.3 Re-run the gate census to catch gates added since the plan: `git grep -hoE 'process\.env\.[A-Z0-9_]+ *(===|!==) *"1"' -- apps/web-platform/test/` | sort -u — reconcile against the plan's 12-var table; new vars get wired or allowlisted with reason+#N.

## Phase 1 — Sentinel (failing-test-first)

- [ ] 1.1 Create `scripts/lint-integration-env-gates.sh`:
  - Producer: `git grep -hoE 'process\.env\.[A-Z0-9_]+ *(===|!==) *"1"' -- apps/web-platform/test/` → deduped gate-var set. Zero found = error (anti-vacuity), not pass.
  - Consumer set: every file under `.github/workflows/` + in-script allowlist (`VAR|reason|#issue` entries).
  - Seed allowlist: `RLS_FUZZ_LOCAL`, `SOLEUR_ISOLATION_IN_IMAGE`, `SOLEUR_ISOLATION_TEST_HOST`, `ANTHROPIC_ISOLATION_TEST_OK` (reasons per plan §Proposed Solution).
  - Summary line: `env-gates: found=<N> wired=<W> allowlisted=<A> uncovered=<U>`; exit non-zero iff uncovered>0 or census empty.
- [ ] 1.2 Create `scripts/lint-integration-env-gates.test.sh` — mutation battery over a scratch fixture tree implementing the plan's Guard Contract rows 1-7 (incl. the `env:`-mapping must-PASS row and the battery's own anti-vacuity row).
- [ ] 1.3 Run both: sentinel RED on current tree (7 uncovered) = failing-test proof; battery GREEN.
- [ ] 1.4 Register in `scripts/test-all.sh` beside the `lint-orphan-test-suites*` `run_suite` block (~:5157-5188) — one registration each for the sentinel and the battery.

## Phase 2 — Workflow

- [ ] 2.1 Create `.github/workflows/scheduled-integration-suites.yml` per plan §Proposed Solution:
  - `on:` `schedule` `30 4 * * *` + `workflow_dispatch` only. NO `pull_request`/`merge_group`/`push`.
  - `permissions: {contents: read, issues: write}`; `concurrency.group: dev-supabase-${{ github.ref }}`, `cancel-in-progress: false`; `timeout-minutes: 30`.
  - Steps: checkout → Bun/Node/`npm ci` → Doppler CLI → token non-empty check → `environment=dev` + `SUPABASE_ACCESS_TOKEN`-absence assertion (verbatim tenant-integration block incl. `strip_log_injection`) → `dev-suite-mutex.sh acquire` (identity `di-${{ github.run_id }}-${{ github.ref_name }}`) → seed bot fixtures (soft-fail) → `run-migrations.sh --bootstrap=skip` with `MIGRATION_SCHEMA_PRECONDITION_PROBE=1` and NO `ALLOW_UNMERGED_DEV_APPLY` → 7 suite steps per the plan's file table, each `if: ${{ !cancelled() }}`, `doppler run -p soleur -c dev_scheduled -- env <GATE>=1 npm run test:ci -- <files> --project unit --reporter=verbose` → mutex release `if: always()` → issue file-or-comment `if: failure()` naming `steps.<id>.outcome` (mirrors `scheduled-realtime-probe.yml` filing shape; label `ci/integration-suites`).
- [ ] 2.2 Static-verify: `actionlint .github/workflows/scheduled-integration-suites.yml` (workflow — NOT a composite action, so actionlint applies) + `bash -n` is NOT valid for YAML; extract `run:` blocks for `bash -n` syntax check per the repo's workflow-lint convention.
- [ ] 2.3 Re-run sentinel: now GREEN — every non-allowlisted gate appears in a workflow file (`env-gates: … uncovered=0`).

## Phase 3 — CI wiring + docs

- [ ] 3.1 `ci.yml` `lint-bot-statuses` job: add `- name: Lint integration env gates` step `run: bash scripts/lint-integration-env-gates.sh` beside "Lint orphan test suites" (~:344). Advisory — do NOT touch `scripts/required-checks.txt` or `infra/github/ruleset-ci-required.tf`.
- [ ] 3.2 `apps/web-platform/test/README.md`: add "CI wiring" paragraph — workflow name, the seven gates it sets nightly, the shared-dev substrate decision + dedicated-project revisit trigger (per plan §Risks).
- [ ] 3.3 `bash scripts/lint-orphan-test-suites.sh` — passes with the new `.test.sh` tracked (registration proven by census).

## Phase 4 — Verification & ship prep

- [ ] 4.1 AC sweep against the plan's `## Acceptance Criteria` — all pre-merge items static-verifiable.
- [ ] 4.2 PR body: `Closes #9855` in body (not title) + `## Changelog` section; note PR-1 checkboxes on #9855 may be ticked.
- [ ] 4.3 Post-merge (pipeline step, not in-session): `gh workflow run scheduled-integration-suites.yml` on main + `gh run watch` — reaches suite steps; files `ci/integration-suites` issue on red.
- [ ] 4.4 If first nightly/dispatch fails on shared-dev substrate (grant divergence, cruft — NOT a real regression): file per-suite follow-up; do NOT weaken gates to force green. Two consecutive substrate-cruft filings → reopen dedicated-project evaluation (plan §Risks revisit trigger).
