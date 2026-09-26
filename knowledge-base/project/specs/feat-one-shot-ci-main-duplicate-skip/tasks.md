# Tasks: ci(workflows) duplicate main-push gate skip (tree-identity proof)

Plan: `knowledge-base/project/plans/2026-09-25-feat-ci-main-duplicate-skip-plan.md`
PR: #8919 (draft) · Branch: `feat-one-shot-ci-main-duplicate-skip`

Fail-OPEN invariant: every ambiguity emits `duplicate=false`. Never skip on
unproven equivalence.

## Phase 1: Shared proof script + tests (test-first)

- [ ] 1.1 Write `tests/scripts/test-main-duplicate-skip.sh` FIRST (failing): stubbed `gh` per `tests/scripts/test-registry-delivery-change.sh` precedent — per-SHA fixture files, `*/pulls` dispatched before `commits/<sha>`, unfixtured argv → exit 64, call LOG + anti-vacuity assertion floor
- [ ] 1.2 Fixture rows: squash-merge identical tree + green run → true; tree differs → false; no associated PR → false; `pulls` API failure → false; latest PR run failure/cancelled → false; required job `skipped` on the PR run → false; multi-PR response bound on `merge_commit_sha`; `deploy-script-tests`/`deploy-script-tests-done` prefix-collision row; missing head.sha → false
- [ ] 1.3 Implement `scripts/main-push-duplicate-skip.sh` (`set -uo pipefail`, never `-e`; single `duplicate=true|false` output line; `::notice::` reason to stderr)
- [ ] 1.4 Run the suite green, then the six-mutant battery (plan Guard 1) — each mutation must RED
- [ ] 1.5 Register the suite in `scripts/test-all.sh` (`run_suite "tests/scripts/main-duplicate-skip" bash tests/scripts/test-main-duplicate-skip.sh`) — tests/scripts/ is NOT auto-globbed

## Phase 2: Aggregator-pattern workflows (fold into detect-changes; no ledger bump)

- [ ] 2.1 `tenant-integration.yml`: in `detect-changes` filter step, replace the unconditional push-arm `tenant=true` with the script call (required-job prefix `tenant-integration`); proven → `tenant=false`; add `actions: read` + `pull-requests: read` to the job's permissions
- [ ] 2.2 `vendor-pin-verify.yml`: same fold → `vendor=false`; required-job prefix `verify-upstream-blobs`
- [ ] 2.3 Verify `tenant-integration-required` / `vendor-pin-required` aggregators need no edit — their suite=skipped PASS branch (merge_group precedent) applies

## Phase 3: infra-validation (fold; notify guard is load-bearing)

- [ ] 3.1 `detect-changes`: add `pr_duplicate` output + push-arm proof step (required-job prefixes: `validate`, `deploy-script-tests`, `deploy-script-tests-fixed`); add the two read perms
- [ ] 3.2 Add `&& needs.detect-changes.outputs.pr_duplicate != 'true'` to `validate`, `registry-userdata-budget`, `inngest-userdata-budget`
- [ ] 3.3 Add `needs: [detect-changes]` + the `if:` conjunct to `deploy-script-tests`, `deploy-script-tests-fixed`; add `detect-changes` to `deploy-script-tests-done`'s needs + conjunct
- [ ] 3.4 Add the conjunct to `notify-main-failure`'s `if:` (skipped≠success would else email ops) — pin with a grep-assert in the new test file
- [ ] 3.5 Confirm `check-secrets`/`plan` untouched; confirm `plugins/soleur/test/infra-validation-detect.test.sh` still green (additive output)

## Phase 4: Single-job workflows (new detect-duplicate job; ledger bump 1→2)

- [ ] 4.1 `validate-vector-config.yml`: add `detect-duplicate` job (no required-job prefixes — run conclusion suffices) + `needs`/`if` on `validate-vector-config`
- [ ] 4.2 `skill-security-scan-corpus.yml`: same on `calibration`
- [ ] 4.3 `scripts/pr-fanout-ledger.txt`: raise the two rows 1→2 with named consequence `detect-duplicate job: tree-identity proof gating the push arm (#8919)`

## Phase 5: Verify + ship

- [ ] 5.1 `bash plugins/soleur/test/pr-fanout-ledger.test.sh` exits 0
- [ ] 5.2 `bash scripts/test-all.sh --affected` green (registers the new suite)
- [ ] 5.3 Exclusion diff empty: `git diff origin/main -- .github/workflows/` touches ONLY the five gated files (AC3 list)
- [ ] 5.4 PR body: `## Changelog`, before-measurement table, the 18-file keep-list with one-line reasons, and the fail-open statement
- [ ] 5.5 Post-merge (non-blocking): confirm AC4 — a normal squash merge shows `duplicate=true` + skipped heavy jobs; a direct push shows `duplicate=false`; zero false `[ALERT] Infra Validation` emails
