# Decision Challenges — feat-one-shot-11776-machinery-batch

Plan: knowledge-base/project/plans/2026-11-02-ci-machinery-batch-sweep-plan.md

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| #10859 required-context flip (delete `continue-on-error` on `affected-index-ratchet`; add it to `scripts/required-checks.txt`, canonical JSON, `infra/github/ruleset-ci-required.tf`, count pin, fixtures, `tests/scripts/test-audit-ruleset-bypass.sh`, `scripts/pr-fanout-ledger.txt`) | operator (money) | **Operator hold, recorded in-plan.** The issue says "held for the budget owner" — a required context multiplies per-PR CI spend AND changes the merge gate for every PR through the auto-applied ruleset. Two of three entry conditions are measurably unmet on 2026-11-02: (1) #10865 soak window still OPEN — probe (`GH_TOKEN=… bash scripts/followthroughs/ratchet-observation-window-10865.sh`) printed three `NOT YET` lines: latest merge_group unit red (`exit=1 new-pair`), wall max 284 s > provisional 270 s ceiling, read budget truncated; (2) the rename-carry design and (3) the jobs-API canary unverified at plan time. This PR lands NO activation diff; the flip needs the budget owner's explicit go-ahead naming the PR. |
| #10865 provisional wall ceiling (270 s) vs measured max 284 s | technical | Ruled by CTO agent, 2026-11-02: raise now — set `P95_MAX=240` and `MAX_MAX=285` in `scripts/followthroughs/ratchet-observation-window-10865.sh` (constants only) - ratifies the ruling already posted on #10865 at 08:31:45Z; the breach is a distribution shift, not an outlier (372-job post-PR5 population p95 218 s / max 284 s, corroborated by an independent ~50-unit jobs-API sample of 130–243 s walls); `MAX_MAX=285` keeps a 5 s guard under the `PR_AFFECTED_REPLAY_SELECT_TIMEOUT=290` cliff; `P95_MAX=240` carries the tail-watch. |
| #11776 "schedule" interpretation — post an ordered slice-map comment + runbook pointer vs draining a bounded slice in this PR | technical | Ruled by CTO agent, 2026-11-02: post the ordered slice-map comment mapping the re-measured gap_suites=279 / gap_refs=1697 remainder onto open slices #10860/#10861/#10959 plus a named uncovered remainder and a `ci-pr-affected-activation.md` pointer; no drain in this PR - the issue's deliverable is a schedule (Fix-Size L); a baseline drain merged mid-window triggers the probe's RESTART FLOOR and discards ~10 days of accumulated soak units. |
| #11789 fix locus — gate the armed/disarmed classification in `sync-pr-behind.sh` + `monitor-pr-checks.sh` vs building a new watch | technical | Ruled by CTO agent, 2026-11-02: gate armed/disarmed classification on queue state at the existing chokepoints (`queue_state_read`/`queue_wait_eval`/`qw_snapshot` in `plugins/soleur/scripts/sync-pr-behind.sh`, the `monitor-pr-checks.sh` emission, the `ready-run-wait.md` armed probe); no new watch - `gh pr view --json isInMergeQueue` verified absent on gh 2.103.3 so REST snapshots cannot self-serve the flag; `queue_state_read` is deliberately the one copy of the merge-queue GraphQL read. |
| #9457 current "did not complete" mode — realign leg step ceilings vs split the over-long leg | technical | Ruled by CTO agent, 2026-11-02: realign step ceilings by the workflow's own TIMEOUT BUDGET formula — `test-scripts` step 15→60 min and job `timeout-minutes` 35→80; `test-webplat` step 10→30 min and job 30→50; `test-bun` unchanged; no split - uncensored ci.yml run 41408788451 measured leg_max ≈37.6 min (scripts 5/8) and ≈17.2 min (webplat 2/2); the documented `leg_step = roundup5(leg_max × 1.5)`, `leg_job = leg_step + 20` rule yields 60/80 and 30/50, both under the 85-min `test-scripts-heavy` leg_job. |
| #9830 target red rate — the number to declare | technical | Ruled by CTO agent, 2026-11-02: declare target ≤2% of push runs on main red (rolling 50-run window), added as a tracked rate line in the monitor report - merge queue makes 0 the asymptote, flakes bound the floor; current steady state already measures 1/50 = 2% while the 8% figure was a churn window (Oct 5–9); ≤2% keeps every red earning the per-run cause label, looser would bless ~one red/day. |
| #3926 label bootstrap mechanism — `gh label create --force` vs provisioned label | technical | Ruled by CTO agent, 2026-11-02: `gh label create timestamp-failure --description … --color … 2>/dev/null \|\| true` inside the `if: failure()` step before the `gh issue list/create` calls - `timestamp-failure` confirmed absent (147 repo labels); `gh issue create --label` dies on a missing label and silently loses the tracking issue; the job already carries `issues: write`; `gh label create … \|\| true` is the established self-healing pattern at 6+ workflow sites. |

## Not Yet Specified candidates

None — no product-scope fog surfaced; the one genuinely open scope question
(#10859) is classified as an operator authorization hold above, which is its
correct home.

## Headless-pipeline note

This session ran as a stateless subagent with no `Task`/`run_subagent` tool;
all agent spawns the plan skill prescribes (research fan-out, domain leaders,
spec-flow, advisor consult, CTO rulings) were performed inline by the
orchestrator where feasible, or recorded as `pending - assumed:` above where a
genuine ruling was required. Findings derived by direct measurement (`gh`,
audit/ratchet runs, probe scripts) are cited with their commands in the plan.
