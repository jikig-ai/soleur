# Tasks: rehearsal skip monitor streak persistence (PR #10916)

Plan: `knowledge-base/project/plans/2026-10-23-fix-rehearsal-skip-monitor-streak-persistence-plan.md`
Follow-up (not in this PR): #10917 (release BuildKit gha cache export churn).

## Phase 1: Tests first (RED)

- 1.1 Create `scripts/monitor-streak-state.test.sh` (one suite, two sections)
  - 1.1.1 Section A: fake `gh` on PATH (numeric JSON ids), real `unzip`/`jq`; cases T1-T11, T13, T14 (listing vs empty distinction, branch filter, newest-wins, run-id exclusion, octal-safe parse, malformed, single-member zip, verdict-aware seal, strict `BOOTSTRAP` literal)
  - 1.1.2 Chain row T15: restored `2` reaches the REAL `t5-skip-persistence-bound-7510.sh` with a broken `gh` -> `3/3`, exit 1; no restore -> `1/3`, exit 2
  - 1.1.3 Section B: PyYAML wiring properties (no `actions/cache`; order fetch < probe < seal < assert < upload; `!cancelled()` per step; five `STREAK_FILE` occurrences equal and non-hidden; upload gating/strictness; `bootstrap` input shape) plus Guard 2 mutation rows on a sandbox copy
  - 1.1.4 Assertion-count floor, append-only failure ledger, harness rows (fake-`gh` edit goes RED; must-PASS non-canonical inputs)
- 1.2 Register one `run_suite` line in `scripts/test-all.sh`; run `python3 scripts/regenerate-shard-manifest.py --incremental --write`; commit exactly what it writes
- 1.3 Confirm the suite is RED

## Phase 2: Script (GREEN)

- 2.1 Create `scripts/monitor-streak-state.sh` (`fetch`, `seal`, `assert`) with the xtrace credential refusal first, `set -uo pipefail`, `${X:-}` defaults, listing written to a file (no `$?` through a pipe)
- 2.2 `chmod +x`; `shellcheck`; `python3 -I scripts/lint-shell-trace-credential-refusal.py scripts/monitor-streak-state.sh`
- 2.3 Section A green

## Phase 3: Workflow

- 3.1 Edit `.github/workflows/scheduled-rehearsal-skip-monitor.yml`: `bootstrap` dispatch input, workflow-level `STREAK_ARTIFACT_NAME`/`STREAK_BRANCH`, replace cache restore/save with fetch/seal/assert/upload, `STREAK_FILE` under `runner.temp` in five places, `mkdir -p` in probe and fetch, upload gated on fetch and seal, rewrite header comments (measured eviction cause, reseed runbook)
- 3.2 Lint sweep: `actionlint`, `lint-workflow-step-env-refs.py`, `lint-workflow-issue-write-scope.py`, `lint-gh-argv-arg.py`, `alarm-issue-filing-guard.test.sh`, `lint-orphan-test-suites.sh`
- 3.3 Section B green, every mutation row RED when applied

## Phase 4: Retire, document, record

- 4.1 Delete `scripts/followthroughs/monitor-streak-cache-roundtrip-7574.sh` and its row in `scripts/lint-shell-trace-credential-refusal.baseline.txt`
- 4.2 Comment-only edit of `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` lines 84-89
- 4.3 `soleur:architecture create` ADR-296 (short form, `accepted`, re-verify the ordinal on `origin/main`); one-line pointer in ADR-188's carrier note
- 4.4 Re-run `bash plugins/soleur/test/c4-count-parity.test.sh`
- 4.5 PR body: render `decision-challenges.md`; `Ref #10917` (no closing keyword)

## Phase 5: Post-merge verification (agent-run)

- 5.0 Read the stored value; proceed only while it is `0`
- 5.1 Dispatch `bootstrap=true`, arm a Monitor watch; fetch/assert/upload `success`; artifact listing prints `false`; record `expires_at`
- 5.2 Dispatch `bootstrap=false`; assert step `success`, log shows `restored=true`
- 5.3 Fallback if `GITHUB_TOKEN` cannot list artifacts: App-token mint for the two read calls (never the cache)
- 5.4 Next scheduled run: assert step `success` (job may remain red for the real FAIL, alert issue #8856)
