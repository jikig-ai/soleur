# Decision Challenges — feat-one-shot-11776-machinery-batch

Plan: knowledge-base/project/plans/2026-11-02-ci-machinery-batch-sweep-plan.md

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| #10859 required-context flip (delete `continue-on-error` on `affected-index-ratchet`; add it to `scripts/required-checks.txt`, canonical JSON, `infra/github/ruleset-ci-required.tf`, count pin, fixtures, `tests/scripts/test-audit-ruleset-bypass.sh`, `scripts/pr-fanout-ledger.txt`) | operator (money / production-mutating authorization) | **Operator hold, recorded in-plan.** The issue says "held for the budget owner" — a required context multiplies per-PR CI spend AND changes the merge gate for every PR through the auto-applied ruleset. Two of three entry conditions are measurably unmet on 2026-11-02: (1) #10865 soak window still OPEN — probe (`GH_TOKEN=… bash scripts/followthroughs/ratchet-observation-window-10865.sh`) printed three `NOT YET` lines: latest merge_group unit red (`exit=1 new-pair`), wall max 284 s > provisional 270 s ceiling, read budget truncated; (2) the rename-carry design and (3) the jobs-API canary unverified at plan time. This PR lands NO activation diff; the flip needs the budget owner's explicit go-ahead naming the PR. |
| #10865 provisional wall ceiling (270 s) vs measured max 284 s | technical | pending - assumed: ceiling is re-ruled upward against the measured series when #10865 is next evaluated (the tracker itself assigns this re-rule to the CTO agent at window close / 30-day trigger; subagent spawn unavailable on this harness so the ruling was not obtained at plan time) |
| #11776 "schedule" interpretation — post an ordered slice-map comment + runbook pointer vs draining a bounded slice in this PR | technical | pending - assumed: "schedule" means the recorded ordered plan onto existing slice issues (#10860/#10861/#10959) + named remainder — NOT a slice drain. Rationale: Fix-Size L (279 suites/1697 refs) cannot drain in one shared PR; the slice issues already exist and are open. |
| #11789 fix locus — gate the armed/disarmed classification in `sync-pr-behind.sh` + `monitor-pr-checks.sh` vs building a new watch | technical | pending - assumed: fix the existing classification chokepoints (`queue_state_read`/`qw_snapshot`/`queue_wait_eval` + monitor emission), no new watcher — the queue flag read already exists in `queue_state_read`; `gh pr view --json isInMergeQueue` does not exist (verified gh 2.103.3). |
| #9457 current "did not complete" mode — realign leg step ceilings vs split the over-long leg | technical | pending - assumed: realign ceilings to measured leg wall time with headroom first (cheaper, keeps the monitor's leg structure); split only if a leg's measured time exceeds the job's `timeout-minutes` budget minus setup. Decide from the failed runs' staged leg-report elapsed_s values at work time. |
| #9830 target red rate — the number to declare | technical | pending - assumed: target ≤2% of push runs on main (the 8% measured Oct 5–9 is ~4× that; merge queue makes 0 the asymptote, flakes bound the floor). Stated on the issue; the monitor's report surface gains the tracked rate line. |
| #3926 label bootstrap mechanism — `gh label create --force` vs provisioned label | technical | pending - assumed: `gh label create <name> … || true` inside the escalation step (self-healing, no operator provisioning step, idempotent under `--force`/already-exists tolerance). |

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
