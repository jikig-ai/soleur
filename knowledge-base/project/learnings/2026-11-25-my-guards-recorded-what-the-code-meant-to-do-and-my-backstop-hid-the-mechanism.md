---
title: My guards recorded what the code meant to do, and my backstop hid the mechanism it backed up
date: 2026-11-25
category: test-failures
module: apps/web-platform/infra/cf-account-migrate-job.test.sh
tags: [bash, test-harness, process-groups, signal-handling, mutation-testing, ci-parallelism, shard-legs]
issues: ["#13051", "#13052", "#13055", "#13062", "#13063", "#12958", "#12850"]
---

# Learning: my guards recorded what the code meant to do, and my backstop hid the mechanism it backed up

## Problem

PR #13052 made `cf-account-migrate-job.test.sh` end on a signal and run inside its CI bound, partly
with an in-suite row pool (`CFAM_MUT_JOBS`). The six-seat review panel found that the pool's two
headline properties were not true as built:

- "output and counts equal a serial run" held only for labels and totals. A row whose delta file
  counted its FAIL as a PASS turned green, and the only ordering check was a one-off golden diff.
- "a bound-kill leaves nothing behind" was enforced through a hand-kept PID list that missed the
  [signal] children and any row forked an instant before the signal.

Fixing them produced four more defects of the same family, each caught only by a mutant or by a
run in a configuration I had not been using.

## Solution

1. **Reap from the shell's own job table**, never a hand-kept list: `jobs -p`, TERM each job's
   process group (each was spawned under `set -m`), `wait`, then poll each group empty with
   `kill -0 -- -<pgid>` before a bounded KILL. `wait` only sees the shell's children; the job and
   stubs under a pooled row are grandchildren, and a dying job's EXIT trap still writes into the
   sandbox the EXIT trap is about to remove.
2. **Reconcile every pooled row's delta against the PASS/FAIL lines it printed**, and add a pooled
   instrument self-test (out-of-order finishing rows, a row that exits without a verdict, a row whose
   delta disagrees) that asserts registration order and the exact counter movement.
3. **Record where each job actually ran** (`run_job` writes `ran-in=pool|fg` into the case dir) and
   assert the SECONDS rule over that record, not over the routing function's own log.
4. **Prove the TERM reached the job with a marker outside the child's sandbox**
   (`CFAM_SIGT_MARK`), written by the fixture's TERM trap after a short delay.
5. Default the pool by core count (1 under 8 cores, 3 otherwise): on a 4-core CI leg the pool
   moved CPU from the leg's other suites rather than saving any.

## Key Insight

**A guard that logs the decision certifies the decision, not the behaviour.** The first version of
the SECONDS row read a ledger that `_pool_or_fg` wrote *before* branching; the mutant that replaced
the branch with an unconditional `_pool_run` left the ledger saying `fg` and the row green. Record
the observation at the point of execution (inside `run_job`), where the routing code cannot vouch
for itself.

**A backstop hides the mechanism it backs up.** With the group-TERM-then-drain reaper behind a final
`kill -KILL`, deleting the drain or downgrading the group kill to a plain kill still left no process
and no sandbox: the KILL cleaned up, and the job simply never ran its trap. Both mutants survived
until a row asserted the primary mechanism's own effect (the TERM trap's marker), not the end state
the backstop also produces.

**Test a parallelism knob at the value CI will use, not the value your machine picks.** The
pool-mode signal row passed at the local default (`CFAM_MUT_JOBS=3` on 16 cores) and failed at 1,
CI's default under the new core-count rule: the child's throttle blocked on its single 30 s row and
never printed `armed`. Only a serial local run caught it before CI did.

## Session Errors

1. **`_pool_snap` false FAIL on inline `fn_*` temp files** — Recovery: excluded them by name after a
   move broke the fixture scanner. **Prevention:** before relocating a temp file a scanner may count,
   run the repo-wide fixture ratchet (`fixture-relative-assert.test.sh`).
2. **Technical-ruling gate failed on a literal pipe in the ruling text** — Recovery: escaped `\|`.
   **Prevention:** run `technical-ruling-gate.sh` on `decision-challenges.md` after every row added.
3. **A push failed and `| tail -1` hid why** — Recovery: retried. **Prevention:** redirect push output
   to a log and print `RC=$?` before any convenience line (already a work-skill rule).
4. **GitHub outage: pushes raised no `pull_request` event** — Recovery: empty commit plus
   `gh workflow run infra-validation.yml --ref <branch>`. **Prevention:** none needed (vendor event);
   poll for a run on the pushed SHA before assuming CI started.
5. **Hooks blocked `pkill -f` and `pgrep -f` (self-matching)** — Recovery: `ps -eo args | awk` on the
   argv slot. **Prevention:** already hook-enforced.
6. **Hook blocked a foreground `sleep`** — Recovery: Monitor / detached scripts. **Prevention:** already
   hook-enforced.
7. **A Monitor expired at its 30-minute cap on a 40-minute gate run** — Recovery: re-armed.
   **Prevention:** arm long waits with an `until` loop and re-arm on expiry; expect the affected gate
   to take ~40 min.
8. **`"${fg:+fg}${fg:-bg}"` printed `fg1`** — Recovery: explicit `if`. **Prevention:** never compose a
   two-valued label from `:+`/`:-` on one variable; `:-` returns the value when set.
9. **The routing ledger recorded the decision; the `fg-rule-off` mutant survived** — Recovery:
   `run_job` records `ran-in`. **Prevention:** sharp-edges bullet (work skill), this learning.
10. **The pool-mode signal row failed at `CFAM_MUT_JOBS=1`, CI's default** — Recovery: the child runs
    at 2. **Prevention:** sharp-edges bullet: run a suite with a parallelism knob at its CI default.
11. **`reap-no-drain` and `reap-no-groupkill` mutants survived behind the KILL backstop** — Recovery:
    a TERM marker outside the child's sandbox. **Prevention:** sharp-edges bullet, this learning.
12. **Repricing ci-deploy reddened `test-all-corpus-weight-budget` (600 s cap)** — Recovery: an
    exemption row citing #13062. **Prevention:** already covered by the work skill's repo-global
    ratchet rule; run `test-all-corpus-weight-budget.test.sh` after any `suite-durations.tsv` edit.
13. **The issue-filing hook refused `gh issue create` three times** (no milestone; a `$F` body path it
    cannot read; a User-Impact exit for a machinery finding) — Recovery: literal path, `--milestone`,
    `--label meta/machinery`. **Prevention:** hook-enforced; a CI/test-bound finding is `meta/machinery`.
14. **Two suite paths guessed wrong (rc 127)** — Recovery: `git ls-files | grep`. **Prevention:** locate a
    suite with `git ls-files` before invoking it.
15. **The affected gate reddened on suites outside the diff** — census A3 saw a probe file another suite
    wrote mid-run (passes alone); `cloud-init-strip-helpers-mutation` is red on main (#12850).
    Recovery: re-ran each in isolation and on `origin/main`. **Prevention:** before reading a gate RED
    as yours, re-run the failing suite alone and on `origin/main`.
16. **The regenerator reset the hand-set 6000 ms host-kernel-marker floor rows to 4000 (twice)** —
    Recovery: restored by hand and re-checked `0 moved`. **Prevention:** filed as #13063
    (the generator should keep a committed floor row's value).
17. **Plan, tasks and session docs described design that was never built** (`derive_reach`, PID-list
    kills) — Recovery: "As built" notes. **Prevention:** sharp-edges bullet: when the built design
    departs from the plan, annotate the plan in the same commit.
18. **I wrote "the five named suites exit 0" before running one of them** — Recovery: ran it (116/116)
    before pushing. **Prevention:** write a pass claim only from a log produced in this round.
19. **A review seat could not delete its scratch copies (hook)** — Recovery: left in the scratchpad.
    **Prevention:** none (scratchpad is session-scoped).
20. **A Python edit step reported exit 1 from a trailing `grep -c` with zero matches** — Recovery: read
    the step's own output. **Prevention:** none; benign.

## Tags

category: test-failures
module: apps/web-platform/infra/cf-account-migrate-job.test.sh
