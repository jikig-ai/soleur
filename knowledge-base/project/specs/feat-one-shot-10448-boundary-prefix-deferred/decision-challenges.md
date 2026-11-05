# Decision Challenges — feat-one-shot-10448-boundary-prefix-deferred

Append-only decision-class ledger for this branch (ADR-084 channel;
`brainstorm-techniques/references/decision-principles.md`). Rows added by
`soleur:plan` / `soleur:deepen-plan` headless phases; `soleur:ship` Phase 6
renders them into the PR body and files `action-required` issues as needed.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Resolution arm for the swept-scope `glob:` coverage deferred item on #10448 (`plugins/soleur/test/boundary-prefix.test.sh`, 4 dir globs ~164 files): (a) install-under-amendment of the PR4b row-6 >25%-selection bar, (a') measured-duration rerun letting `glob_decide` produce the policy verdict itself (`always_on` if the real duration lands ≤10 s at the measured ~48% rate), or (b) explicit accepted-gap ruling leaving the unnamed-swept-file residual as the audit's documented lower bound | technical | pending - assumed: arm (b), explicit accepted-gap ruling. Rationale for the assumption: the suite's duration src is `floor` (the 1222 ms row is the generated default-weight placeholder, not a measurement — no `glob:`/`always_on` verdict is reachable today, and arm a' dies if the real duration exceeds the 10 s fast-tier cap); the measured 48% selection rate is roughly double the ruled 25% bar, so arm (a) means amending a CTO-ruled policy constant for a ~50%-selecting edge; the same-class argv-bearer-sweep whole-tree census residual is already the documented residual; and arm (b) keeps the 7 named pairs' dispositions and the declared `glob:.claude/hooks/*guardrails*.sh` edge valid either way (deferred-item AC 6). The ruling itself is a selection-policy call reserved to the CTO (PR5d decision-challenges row 10) — implementation Phase 0 spawns `soleur:engineering:cto` with the evidence packet including per-arm disqualifying facts, and the plan carries all three arms. If the CTO rules arm (a)/(a') instead, the plan's install arm and reconciliation steps execute. |
| #10859 entry condition 2 (ruled rename-carry design) status under strict zero | technical | pending - assumed: unmet and stale — no ruled rename-carry design exists (verified by repo grep 2026-11-05), and its ruled precondition ("a pair already in the base baseline", PR3a decision-challenges row 25) is empty-set under strict zero since the baseline file was deleted by PR5z; the PR5z review already flagged the runbook's rename-carry wording as dead vocabulary. Whether the condition dissolves or needs re-ruling is itself a CTO call; this PR records the status, does not rule it. |
| Posting the fresh observation-window measurement to #10865 now (rather than waiting for the window to advance) | taste | Recorded 2026-11-05: the probe is read-only and posting is cheap evidence hygiene — the run this session measured `window opened=2026-11-05T01:27:24Z units=115 wall_p95_s=269 wall_max_s=279` with three `NOT YET` lines (paused on red merge_group run 42084778935 `exit=1 new-pair`; no bot PR yet; p95 269 s > 240 s ruled ceiling — a further whole-population breach data point for #12129). The work phase re-runs the probe and posts the then-current measurement. |

## Notes

- Planning ran headless under the one-shot pipeline on the Devin harness: no
  `run_subagent` capability in this session, so the technical rulings above are
  `pending - assumed` per `technical-ruling-delegation.md` and the plan's first
  implementation phase performs the CTO consult.
- Premise validation (2026-11-05): #10448 OPEN with the deferred item mirrored
  (comment 2026-11-05T00:03Z); #10859 OPEN held for the budget owner; #10865
  OPEN, window restarted at the #12116 merge 2026-11-05T01:27:24Z; #12129 OPEN
  money decision; #12149 OPEN overlapping subsystem (disjoint edit surface);
  #12155 OPEN context. Collision precheck on #10448: only this branch's own
  draft PR #12199 names it; foreign `proc.sh` hits were unrelated `test-all.sh`
  runs in sibling worktrees.
