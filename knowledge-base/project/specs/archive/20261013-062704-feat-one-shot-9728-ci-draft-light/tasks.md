# Tasks: ADR-276 S3 draft-PR light checks (#9728)

Plan: `knowledge-base/project/plans/2026-10-09-ci-s3-draft-pr-light-checks-plan.md`
Branch: feat-one-shot-9728-ci-draft-light (draft PR 9885). Sequence is load-bearing: gate 6 first, other gates and the ADR amendment before any `ci.yml` edit, tests before code.

## Phase 0: Preflight
- [ ] 0.1 Work only in the worktree; never touch the main checkout
- [ ] 0.2 Re-read variables (`CI_DRAFT_LIGHT` unset), ADR-276 `status: adopting`, ci.yml job count 25 and ledger row 25; sync `origin/main` by merge
- [ ] 0.3 Look for an enforced "no draft push before local --affected" policy and its date; record the result

## Phase 1: Gate 6 census (read-only, no ci.yml edit)
- [ ] 1.1 Failing suite `scripts/ci-draft-push-census.test.sh` with synthesized fixtures (Guard 3 rows), then `scripts/ci-draft-push-census.sh`
  - [ ] 1.1.1 Register: `scripts/test-all.sh`, `suite-durations.tsv`, `suite-shard-legs.tsv`; `bash scripts/lint-orphan-test-suites.sh`
- [ ] 1.2 Run live over a closed 30-day window; commit output under `measurements/`
- [ ] 1.3 Per-job minutes via `scripts/ci-demand-census.sh` in 12-hour windows (gated families, light set, test-bun, e2e)
- [ ] 1.4 Apply the verdict table (integer comparison, lower of the two bases); attach the census to #9728
- [ ] 1.5 Gate 5b read-only check (App `workflow_run` delivery for this repository)

## Phase 2: Branch A (FAIL) or Branch C (INDETERMINATE), no ci.yml change
- [ ] 2.1 ADR-276 amendment (append only): S3 closed/held, numbers, `S1 live` line, flip unconfirmed, status stays `adopting`
- [ ] 2.2 Branch A: closure comment on #9728, notes on #9729 and #9730, PR body `Closes #9728`; Branch C: dated re-measure comment, `Refs #9728`
- [ ] 2.3 Go to Phase 10

## Phase 3: Branch B entry gates 1 to 5 on a throwaway PR
- [ ] 3.1 Scratch branch deletes PR workflows, adds one probe workflow; draft PR titled DO NOT MERGE, never armed
- [ ] 3.2 Gate 1 (rollup, three read points), gate 2 (user token vs GITHUB_TOKEN), gate 3 (answered by design), gate 4 (3 timing samples), gate 5 (stubbed fixtures)
- [ ] 3.3 Record in `measurements/gate-results.md`; close the throwaway PR and delete its branch; any STOP closes the stage with no ci.yml change

## Phase 4: Branch B ADR-276 amendment (before any ci.yml edit)
- [ ] 4.1 Append the S3 amendment (kill-switch, 3(a) to (h), exit criterion, dark cost, rollback footprint, Option T rejection, gate results) and the `S1 live` and `S3 amended` lines
- [ ] 4.2 Stateless check: ci.yml mentioning `draft-light` requires the ADR heading; ADR-032 pointer line; supersession block for the two Decision 4 wordings

## Phase 5: Branch B tests first (RED)
- [ ] 5.1 `scripts/ci-draft-light.test.sh` (executed step bodies, gated-set parity both directions, Guard 1 rows)
- [ ] 5.2 Aggregator draft-arm rows in `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`; update pins in `scripts/ci-push-dedupe.test.sh`
- [ ] 5.3 `plugins/soleur/test/ci-head-verdict.test.sh` (Guard 2), reader fixtures (`admin-merge-ready*.test.sh`, `monitor-pr-checks.test.sh`, `drain-prs.test.sh`, `ship-phase-7-poll-fixtures.test.sh`), `ship-battery-owed.test.sh` rows
- [ ] 5.4 Probe suite `scripts/followthroughs/ci-draft-light-soak-9728.test.sh`
- [ ] 5.5 Register every new suite; run `bash scripts/lint-orphan-test-suites.sh`

## Phase 6: Branch B ci.yml
- [ ] 6.1 `types: [opened, synchronize, reopened, ready_for_review]`
- [ ] 6.2 Job `draft-light` (`if` pull_request, continue-on-error, timeout 3, live read, exact `on`)
- [ ] 6.3 Gate `test-webplat`, `test-scripts`, `test-scripts-heavy`, `shard-totality-mutations`; `test` aggregator draft arm before the final fail check; e2e untouched
- [ ] 6.4 Ledger 25 to 26; header comment; actionlint; `c4-count-parity.test.sh`

## Phase 7: Branch B readers
- [ ] 7.1 `plugins/soleur/scripts/ci-head-verdict.sh` (`verdict` with the closed state set `n/a|full-decided|pending-full|no-run|stalled|awaiting-approval`, `wait-ready-run --before-count`)
- [ ] 7.2 Readers, each from a failing fixture: monitor-pr-checks, admin-merge-ready (`--wait`), triage-prs and drain-prs SKILL, ship Phase 7 and merge-pr poll copy
- [ ] 7.3 Ship Phase 6, drain-prs and merge-pr: wait-ready-run between `gh pr ready` and arming; settle-then-admin-merge pointer; skill byte and word budgets
- [ ] 7.4 `battery-owed.sh` rows; `pr-battery-gate-saving-9323.sh` fixture check

## Phase 8: Branch B probe
- [ ] 8.1 `scripts/followthroughs/ci-draft-light-soak-9728.sh`: stall (N=75), dark deadline (1 day), activation order check, live invariants, exit criterion (exit 2 until activation + 7 days); CODEOWNERS lines; tracker #9728 label and directive (`earliest=` merge + 1 day)

## Phase 9: Branch B canary and activation
- [ ] 9.1 Canary on this PR only with the operator's go and gate 5b clear; variable deleted right after
- [ ] 9.2 Arm the merge only when activation can follow (or an authorized dark merge, bounded to 1 day)
- [ ] 9.3 Activation outside the PR: `S3-CONFIRMED`, `gh variable set`, `S3-ACTIVATED`; 7-day soak; exit census; 30-day removal trigger

## Phase 10: Ship (both branches)
- [ ] 10.1 Run directly: `scripts/test-affected-kb-consumers.test.sh`, `.claude/hooks/grep-q-pipe-guard.test.sh`, `scripts/guard-vacuity-floor.test.sh`, plus the stage suites; never `test-all.sh --affected`
- [ ] 10.2 Trailer and PR-body ending; no stash, no force-push; Monitor-tool polling; `net-issue-flow.sh` <= 0
- [ ] 10.3 PR body: Branch A `Closes #9728`; B and C `Refs #9728`
- [ ] 10.4 Post-merge checks from a detached `origin/main` worktree
