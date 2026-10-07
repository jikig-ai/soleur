## Problem

Stage 3 of the #9721 hosted-runner demand plan (lever 2): draft PRs run only a light check set and the full required set runs on `ready_for_review` and again in `merge_group`. Measured 2026-10-07 (6h window, runner-bound jobs): draft-state `CI` is 1,319 of 3,094 PR-event `CI` job-minutes (18 runs, 73 each); expected net saving about 600 job-minutes per 6h (range 350 to 850), and it only pays above about 3 draft pushes per PR.

## Entry gates (resolve on a throwaway PR before any `ci.yml` edit)

1. How the required-status rollup treats two same-name check runs on one SHA (draft light green, then ready pending).
2. A `gh pr ready` with an ordinary user token versus `GITHUB_TOKEN` (the latter triggers no workflow).
3. Whether repository variables reach a fork `pull_request` run.
4. The arm-then-register window: ship Phase 6 runs `gh pr ready` then `gh pr merge --squash --auto` within seconds; the head already carries the draft run's greens. Ship Phase 6 must wait for a non-draft `CI` run on HEAD created after the ready call and fail closed (same in `drain-prs` and `merge-pr`).
5. The agent `--admin` merge path skips the queue: `plugins/soleur/scripts/admin-merge-ready.sh` and its wiring test are in scope, because the `test` aggregator is created only after every shard ends and the draft run's `test` is the newest row until then.
6. First check the cheaper alternative: no draft push before a local `--affected` run passes.

Design preference (Option R): the draft aggregator concludes red ("full battery owed at ready"), which needs no tolerance arm; first confirm `monitor-pr-checks.sh`, `drain-prs` triage and ship Phase 7 do not misread a red draft `test`. Option T (tolerance arm plus a distinct marker that `battery-owed.sh` and `admin-merge-ready.sh` require) is the fallback. Variable: `CI_DRAFT_LIGHT`. Fork PRs always run full.

## Scope

`ci.yml` adds the full `types:` list with `ready_for_review`, resolves the draft state live (a re-run reuses the original payload), gates heavy families on it behind a repository variable (unset means full CI, set with `gh variable set`, removed after 30 days with zero escapes), and the `test` aggregator names the one skip reason it tolerates. `battery-owed.sh` must not read a light `test` as full. `e2e` keeps its step-level gating. Guard 1 of the plan carries the mutation matrix; the harness reuses the existing aggregator-over-synthetic-triples suite. `scripts/pr-fanout-ledger.txt` needs a row bump if a job is added (`ci.yml` is at its declared ceiling of 24).

User-Impact: PR checks on draft pull requests (`.github/workflows/ci.yml`, `plugins/soleur/skills/ship/scripts/battery-owed.sh`); merge_group stays the full battery
Fix-Size: 300 lines / 7 files

Exit: draft `CI` minutes per draft push down at least 80%, zero queue stalls, zero PRs entering the queue with a heavy family unrun on a non-draft head.

Re-evaluation: after the S1 census exists and the entry gates are answered.

Refs #9721
