# Tasks — feat-one-shot-12089-congestion-relief

Plan: `knowledge-base/project/plans/2026-11-06-chore-ci-congestion-relief-plan.md`
Issue: #12089 (tracker; the PR relieves the breaches it reports) | Draft PR: #12250

## Phase 1 — Umbrella design + membership census

- [ ] 1.1 Finalize fold membership per plan Phase 1 (homogeneous `runs-on`/permissions/checkout-depth/install needs per umbrella); confirm `affected-index-ratchet`, `encryption-posture`, `oracle-*`, `pr-selection`, `draft-light`, `push-dedupe`, `detect-changes`, `lint-webplat`, `e2e`, `test`, `dependency-review`, `skill-security-scan PR gate`, tenant/sentry/vendor aggregators, CLA contexts stay separate.
- [ ] 1.2 Write the umbrella step contract: every member a named step with `if: ${{ !cancelled() }}`; final aggregate step exits non-zero iff any member failed and prints member names (lint-bot-statuses precedent).
- [ ] 1.3 No `if:` on `github.event_name` on any umbrella producing a required context (pend-forever precondition).

## Phase 2 — Required-context ABI swap (atomic)

- [ ] 2.1 `.github/workflows/ci.yml`: fold 6 docs/ruleset guards → `guards-ruleset`; lockfile-sync + grok-fidelity → `guards-env`; advisory folds per plan.
- [ ] 2.2 `.github/workflows/pr-quality-guards.yml`: fold enforce + markdown-lint + Bash-fixture-tests → `quality-guards`; advisory Block family → `quality-advisory`.
- [ ] 2.3 `.github/workflows/secret-scan.yml`: fold gitleaks + lint-fixture + waiver + rename-guard + allowlist-diff → `secret-guards`.
- [ ] 2.4 `infra/github/ruleset-ci-required.tf`: remove 16 context names, add umbrella names (merge_queue block untouched).
- [ ] 2.5 `scripts/ci-required-ruleset-canonical-required-status-checks.json`: same swap.
- [ ] 2.6 `scripts/required-checks.txt`: 16 → 3 umbrella entries with #6049 compound justifications.
- [ ] 2.7 `scripts/required-check-wallclock-bounds.tsv`: umbrella rows, seed `max(member bound) + Σ member p90_dur`, margin 0.30.
- [ ] 2.8 `infra/github/README.md` + `scripts/create-ci-required-ruleset.sh` comment updates (counts/inventory; no skeleton-param edits).
- [ ] 2.9 Consumer sweep: `git grep` each old context name; edit hard-coded literals in `scripts/pr-fanout-ledger.txt`, `scripts/post-bot-statuses.sh`, `lefthook.yml`, `plugins/soleur/skills/ship/scripts/battery-owed.sh`, `plugins/soleur/scripts/monitor-pr-checks.sh`, `plugins/soleur/skills/drain-prs/scripts/triage-prs.sh`, `plugins/soleur/scripts/ci-head-verdict.sh`, ship SKILL.md, `merge-queue-dequeue.md` — or record why each is derived-from-file and safe.
- [ ] 2.10 `scripts/lib/test-affected-paths.sh`: verify edge declarations for touched files cover renamed-name consumers.
- [ ] 2.11 Verify `scripts/probe-merge-group-coverage.sh` finds each new umbrella `name:` as a merge_group producer BEFORE the ruleset swap (run it on the branch).
- [ ] 2.12 ADR-032 dated amendment: consolidation record + paired-edit contract + transition recipe + new name↔job inventory.
- [ ] 2.13 `.github/actions/bot-pr-with-synthetic-checks/action.yml`: verify Phase-4 reproduction coverage for umbrella members (credential-path, gitleaks, lint-fixture); comment updates only if needed (CHECK_NAMES is derived).

## Phase 3 — Guards, tests, transition canary

- [ ] 3.1 Run locally: `bash tests/scripts/test-audit-ruleset-bypass.sh`, `plugins/soleur/test/required-checks-canonical-parity.test.sh`, `scripts/probe-merge-group-coverage.sh`, `scripts/watch-wallclock-p90-11774.sh --dry-run` (zero stale-bound warnings), `bash scripts/ci-oracle-lane.test.sh` (untouched sanity), Guard-1 member-failure fixture.
- [ ] 3.2 `terraform plan` output for `infra/github` shows in-place `update`, `0 destroy` (no `[ack-destroy]` needed).
- [ ] 3.3 Merge-time: after `apply-github-infra.yml` completes, inspect the queue for pending-on-old-name entries; re-queue recipe (dequeue or 120-min ejection; stall probe at 45 min is the net).
- [ ] 3.4 Post-merge canary: umbrella contexts green on the first post-merge `merge_group` run.
- [ ] 3.5 Baseline census before merge + post-merge window: `bash scripts/ci-demand-census.sh --summary` per workflow; attach job-count delta to #12089.

## Phase 4 — Deferred follow-ups

- [ ] 4.1 File `max_entries_to_build 2→1` measured-experiment issue under epic #11556.
- [ ] 4.2 Oracle-lane activation PR (separate, per runbook): would_skip audit on ≥1 real oracle-only run → remove ONLY `scripts/ci-oracle-lane.sh:73` lock → three sentinel suites → evidence to #10865 → ADR-276 dated Stage-status line → first-active-run canary.
