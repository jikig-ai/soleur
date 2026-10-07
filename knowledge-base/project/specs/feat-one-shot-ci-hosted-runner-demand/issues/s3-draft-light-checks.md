## Problem

Stage 3 of the #9721 hosted-runner demand plan (lever 2): draft PRs run only a light check set and the full required set runs on `ready_for_review` and again in `merge_group`. Measured 2026-10-07 (6h window, runner-bound jobs): draft-state `CI` is 1,319 of 3,094 PR-event `CI` job-minutes (18 runs, 73 each); expected net saving about 600 job-minutes per 6h at the plan's inputs (180 to 730 as ready transitions go 7 to 3; formula and sensitivity table in the plan), against a measured mean of 2.6 draft pushes per draft PR. It only pays above about 2.2 to 3 draft pushes per PR, so the saving is marginal until the draft-push distribution is measured.

## Entry gates (resolve on a throwaway PR before any `ci.yml` edit)

Preconditions: ADR-270 is `accepted`, and this stage's PR appends its dated `## Amendment` to ADR-276 (Decision 3(g), (h)) before any switch is flipped.

1. How the required-status rollup treats two same-name check runs on one SHA (draft light green, then ready pending).
2. A `gh pr ready` with an ordinary user token versus `GITHUB_TOKEN` (the latter triggers no workflow).
3. Whether repository variables reach a fork `pull_request` run.
4. The arm-then-register window: ship Phase 6 runs `gh pr ready` then `gh pr merge --squash --auto` within seconds; the head already carries the draft run's greens. Ship Phase 6 must wait for a non-draft `CI` run on HEAD created after the ready call and fail closed (same in `drain-prs` and `merge-pr`).
5. The agent `--admin` merge path skips the queue: `plugins/soleur/scripts/admin-merge-ready.sh` and its wiring test are in scope, because the `test` aggregator is created only after every shard ends and the draft run's `test` is the newest row until then.
6. First check the cheaper alternative, with its pass criterion: the measured distribution of draft pushes per PR (30-day census), after the policy "no draft push before a local `--affected` run passes" is applied first, has a mean of at least 3; otherwise do not build this stage.

Design (Option R is the decision, ADR-276 Decision 4): the draft aggregator concludes red ("full battery owed at ready"), which needs no tolerance arm. Option T (a tolerance arm plus a marker) is rejected: the ruleset cannot enforce a marker, and a required marker would land in `required-checks.txt` and be posted green for bot PRs by `bot-pr-with-synthetic-checks` and `SYNTHETIC_CHECK_NAMES` in `_cron-safe-commit.ts`. Consumers (`monitor-pr-checks.sh`, ship Phase 7 `required_failed`, `drain-prs` triage, `gh pr checks` readers, `admin-merge-ready.sh --wait`) must, for a non-draft head with a red `test` and the newest `CI` `pull_request` run still in progress, resolve the verdict from the newest non-draft run at HEAD, not the check row. Variable: `CI_DRAFT_LIGHT`, accepted value exactly `on` (unset, empty, `ON`, `on` with surrounding whitespace or any other string means full CI). Fork PRs always run full.

## Scope

`ci.yml` adds the full `types:` list with `ready_for_review`, resolves the draft state live (a re-run reuses the original payload), gates heavy families on it behind a repository variable (unset means full CI, set with `gh variable set`, removed after 30 days with zero escapes), and the draft `test` aggregator concludes red. `battery-owed.sh` must not read a light `test` as full (a mutation row either way). A follow-through probe in `scripts/followthroughs/` raises an owner-visible signal for a PR whose ready run is never created (the ADR-270 stall probe watches queue entries only). Files: `ci.yml`, `battery-owed.sh` and its test, `admin-merge-ready.sh` and its wiring test, `monitor-pr-checks.sh`, ship Phase 6/7 (`plugins/soleur/skills/ship/SKILL.md`), `drain-prs`, `merge-pr`, the Guard 1 aggregator harness, the probe, and the ledger row. `e2e` keeps its step-level gating. Guard 1 of the plan carries the mutation matrix; the harness reuses the existing aggregator-over-synthetic-triples suite. `scripts/pr-fanout-ledger.txt` needs a row bump if a job is added (`ci.yml` is at its declared ceiling of 24).

User-Impact: PR checks on draft pull requests (`.github/workflows/ci.yml`, `plugins/soleur/skills/ship/scripts/battery-owed.sh`); merge_group stays the full battery
Fix-Size: 450 lines / 12 files

Exit: draft `CI` minutes per draft push down at least 80%; zero queue stalls; zero PRs entering the queue with a heavy family unrun on a non-draft head; and net: total `CI` minutes on PRs that went draft then ready, before versus after, down at least 25% (threshold confirmed from the S1 census). Stop rule: if pushes per draft PR fall below 3, turn the variable off and close the stage.

Rollback: unsetting the variable restores full draft CI but does not undo the `ready_for_review` entry in `types` (one extra full run of about 95 to 137 job-minutes per drafted-then-readied PR while it is unset), the Phase 6 / `drain-prs` / `merge-pr` wait step, or the `admin-merge-ready.sh`, `battery-owed.sh` and consumer changes; those need a revert.

Re-evaluation: after the S1 census exists and the entry gates are answered.

Refs #9721
