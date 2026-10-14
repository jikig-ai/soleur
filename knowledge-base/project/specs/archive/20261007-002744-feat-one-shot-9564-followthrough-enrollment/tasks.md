# Tasks: watch the #9564 re-evaluation trigger and notify once (never close)

Plan: `knowledge-base/project/plans/2026-10-06-chore-registration-narrowing-reeval-watch-plan.md`
Issue: #9564 (reference only; the PR body uses `Ref #9564`, no closing keyword)

## Phase 1 — Failing suite first

- 1.1 Create `scripts/watch-registration-narrowing-9564.test.sh` with a PATH-prepended recording mock `gh` and a fixture git repo builder (base commit passed via `WATCH_BASE_SHA`, touching and non-touching commits, a merge commit, a commit with a deleted line).
  - 1.1.1 Scenarios S1-S11 from the plan, the H1 recorder self-check, H2, and a scenario-count floor (`PASS + FAIL >= N`).
  - 1.1.2 Confirm the suite is RED against the missing script.

## Phase 2 — Watcher script

- 2.1 Create `scripts/watch-registration-narrowing-9564.sh` (`set -uo pipefail`, xtrace refusal in the prologue).
  - 2.1.1 Constants `ISSUE=9564`, `BASE_SHA=2cfef66506c67207fc65b4250689842ff5ea20ba`, `THRESHOLD=3`, the two runner paths; single test seam `WATCH_BASE_SHA`.
  - 2.1.2 `--print-count` mode: print `threshold=3 base=<short>` first, then `count=<N>` or `count=unknown (<reason>)`; exit 0.
  - 2.1.3 Order: issue state and comments read first (read failure exit 3; not OPEN exit 0), then base-is-ancestor check (exit 3 on failure), then the measurement.
  - 2.1.4 Count = commits since the base touching the two paths with zero deleted lines (`git log --no-merges --numstat`); also report the number of excluded touching commits. Below threshold: print and exit 0.
  - 2.1.5 Dedup: bot-authored (`github-actions` or `github-actions[bot]`) comment containing the per-threshold sentinel means exit 0.
  - 2.1.6 Post exactly one notice with `gh issue comment 9564 --body-file -` (subjects truncated to 100 chars; part (b) hand-off text with the 653 s / 54.4 min arithmetic); failure exit 1. Only `issue view` and `issue comment` verbs appear in the file.
- 2.2 Suite GREEN; apply each Guard 1 mutation M1-M8 and harness row H1 once, confirm RED, revert, record the matrix result for the PR body.

## Phase 3 — Workflow and registration

- 3.1 Create `.github/workflows/registration-narrowing-watch.yml` (weekly cron + `workflow_dispatch`, `concurrency` group with `cancel-in-progress: false`, `contents: read`, `issues: write`, pinned checkout with `fetch-depth: 0` and `persist-credentials: false`, `timeout-minutes: 5`, one `run:` step; header with `RETIREMENT:` block).
- 3.2 Register the suite: `run_suite` line in `scripts/test-all.sh` beside `scripts/watch-live-verify-pass` (not the ALWAYS_ON line), rows in `scripts/suite-durations.tsv` and `scripts/suite-shard-legs.tsv`; run the shard totality/parity tests.
- 3.3 Run `bash scripts/lint-orphan-test-suites.sh` and `bash scripts/test-all.sh --print-selection` (`AFFECTED_SELECTED` value `1`); add the `AFFECTED_*_PATHS` array in `scripts/lib/test-affected-paths.sh` only if the census names the suite unclassified.
- 3.4 Lints: `python3 scripts/lint-workflow-issue-write-scope.py`, `bash scripts/lint-workflows.sh` (no new finding), `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`, `bash plugins/soleur/test/c4-count-parity.test.sh`, `npx markdownlint-cli2` on the plan and this file.
- 3.5 Record this PR's own local-gate wall time (a registration-only run) for the PR body; PR body explains why the sweeper was not used and uses `Ref #9564`.

## Phase 4 — Post-merge (agent-run via `gh`)

- 4.1 `gh workflow run registration-narrowing-watch.yml`; read the run log: `count=` line present, run green; if count is 3 or more, exactly one bot comment with the sentinel exists on #9564 and the issue is still OPEN with unchanged labels; a second manual run posts nothing.
- 4.2 `gh issue comment 9564` with the plain-text pointer paragraph (no follow-through label, no directive token, no HTML-comment opener, no body edit).
