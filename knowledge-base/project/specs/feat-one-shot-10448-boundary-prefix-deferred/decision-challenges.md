# Decision Challenges — feat-one-shot-10448-boundary-prefix-deferred

Append-only decision-class ledger for this branch (ADR-084 channel;
`brainstorm-techniques/references/decision-principles.md`). Rows added by
`soleur:plan` / `soleur:deepen-plan` headless phases; `soleur:ship` Phase 6
renders them into the PR body and files `action-required` issues as needed.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Resolution arm for the swept-scope `glob:` coverage deferred item on #10448 (`plugins/soleur/test/boundary-prefix.test.sh`, 4 dir globs ~164 files): (a) install-under-amendment of the PR4b row-6 >25%-selection bar, (a') measured-duration rerun letting `glob_decide` produce the policy verdict itself (`always_on` if the real duration lands ≤10 s at the measured ~48% rate), or (b) explicit accepted-gap ruling leaving the unnamed-swept-file residual as the audit's documented lower bound | technical | Ruled by CTO agent, 2026-11-05: arm (a') — the measured-verdict path. Obtain a `measured` duration row at work time per the runbook §7 whole-tree/glob-reader procedure (timed runs → `scripts/regenerate-shard-manifest.py` → `scripts/suite-durations.tsv`), re-run `glob-rate` on a recorded `origin/main` SHA, and install the verdict `glob_decide` returns — at the measured figures `always_on`, implemented as an `ALWAYS_ON_SUITES` entry at `scripts/lib/test-affected-paths.sh:132` with the edge block at :4165 left in place (deferred-item AC 6). The 25% constant is NOT amended in any case; if the work-time measured row lands above `GLOB_ALWAYS_MAX_MS=10000`, `glob_decide` returns `baselined` and the same PR documents the accepted gap in runbook §7 (arm b as the arm's terminal state) - the 25% figure is a routing threshold, not a cap (`glob_decide` at `scripts/ci-pr-affected-replay.py:2179-2201`: ≤25%→`glob`, >25%+measured≤10s→`always_on`, >25%+>10s→`baselined`); the measured rate exceeds the bar on both readings (97/200 conservative, 48/151 excluded — PR5d `receipts/glob-rate/glob-rate.tsv`), so the policy's own answer was never `glob:`; live Class R check measured 3 runs 1295/2477/1966 ms all RC=0 (54 tests passed) under `LOCAL_FAST_CAP_MS=10000` with >4× headroom, and 116 always-on suites total 170,738 ms against `LOCAL_FAST_TOTAL_CAP_MS=300000` (~2 s de minimis, lint-enforced at `test-all-fast-tier-budget.test.sh:55-69`); `always_on` is the strictest correct resolution — it eliminates the residual outright (a new `.sh` under the four swept dirs adding a boundary pattern while naming no tracked path can never again produce an unseen pair); the drain-rubric reservation binds drain PRs only, and this is the named follow-up PR. Dissent: `always_on` spends ~2 s on every `pull_request` and `merge_group` including docs-only PRs, and carries a re-pricing tail — if measured weight drifts over 10 s the budget lint reds and the #11648 demotion precedent (`test-affected-paths.sh:2463`,`:4584`) demotes it, reviving the rejected arm-(a) amendment question. |
| #10859 entry condition 2 (ruled rename-carry design) status under strict zero | technical | Ruled by CTO agent, 2026-11-05: dissolved — recorded as vacuously satisfied under strict zero; the PR3b plan does not re-rule it; the condition revives automatically if a base baseline is ever re-adopted (a state change already blocked twice over: `baseline-reintroduced` exit 1 on the job, and entry condition (c)'s cumulative shrink-only check at merge time), so the revival needs no separate re-rule trigger - the condition's governing domain (pairs in the base baseline, PR3a decision-challenges row 25) is the empty set: PR5z deleted `scripts/ci-pr-affected-audit.baseline.tsv`; the loophole cannot re-open silently (`baseline-reintroduced` exit 1 unconditionally, `ci-pr-affected-replay.py:151`,`:2059`; condition (c) blocks PR3b on any added line); interim rename handling is already binding (runbook :213-214 — a rename of a covered path reads `new-pair` and must declare or accept in the same PR; accept rows stale on rename rather than carry). Dissent: the dissolution is conditional — it rests on strict zero remaining the end-state; any future ruled relaxation re-adopting a baseline ends the vacancy and the condition must be re-examined before PR3b; ADR-276 item 9(d) still names it, so "dissolved" must not be read as "repealed". |
| Posting the fresh observation-window measurement to #10865 now (rather than waiting for the window to advance) | taste | Recorded 2026-11-05: the probe is read-only and posting is cheap evidence hygiene — the run this session measured `window opened=2026-11-05T01:27:24Z units=115 wall_p95_s=269 wall_max_s=279` with three `NOT YET` lines (paused on red merge_group run 42084778935 `exit=1 new-pair`; no bot PR yet; p95 269 s > 240 s ruled ceiling — a further whole-population breach data point for #12129). The work phase re-runs the probe and posts the then-current measurement. |

## Notes

- Planning ran headless under the one-shot pipeline on the Devin harness: the
  planning-time rows were left `pending - assumed` per
  `technical-ruling-delegation.md`, and the work-time CTO consult (one batched
  spawn) resolved them to `Ruled by CTO agent, 2026-11-05` — arm (a') the
  install path, arm B dormant (measured 718 ms ≤ 10 s).
- Premise validation (2026-11-05): #10448 OPEN with the deferred item mirrored
  (comment 2026-11-05T00:03Z); #10859 OPEN held for the budget owner; #10865
  OPEN, window restarted at the #12116 merge 2026-11-05T01:27:24Z; #12129 OPEN
  money decision; #12149 OPEN overlapping subsystem (disjoint edit surface);
  #12155 OPEN context. Collision precheck on #10448: only this branch's own
  draft PR #12199 names it; foreign `proc.sh` hits were unrelated `test-all.sh`
  runs in sibling worktrees.
