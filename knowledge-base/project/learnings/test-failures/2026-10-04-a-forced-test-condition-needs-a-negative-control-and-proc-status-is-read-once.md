# Learning: a forced test condition needs a negative control, and /proc/<pid>/status is read once

## Problem

`cron-egress-self-heal.test.sh` was red on main in the Infra Validation
`deploy-script-tests (2/4)` leg. Its nft reproducer shim relied on dying of
SIGPIPE (rc 141), and a CI runner starts jobs with SIGPIPE ignored, so the shim
exited 0. The SIGPIPE disposition story itself is in Instance 3c of
`2026-08-20-the-check-failed-because-the-thing-it-checked-for-was-there.md`.
This note is about what the FIX got wrong on the way, because both defects are
reusable.

## Solution

Two things the first version of the fix shipped, found by the review panel and
the targeted fix round (not by any suite):

1. **The forced condition was self-attested.** A helper forced SIGPIPE ignored
   and a `/proc` canary proved the helper, but nothing could say `default`: the
   canary and the shim's own recorder could print `ignored` unconditionally and
   stay green, the direct forced control had no routing proof (unwrap it, still
   green), and the default half was only asserted by whatever the ambient happened
   to be. Fix: a converse helper (`with_sigpipe_default`: python restores the
   default, which bash cannot), a negative control on each side of every
   detector, and a routing proof read back from the shim for every forced path.
2. **`while read ...; done < /proc/$$/status` is not safe under load.** `/proc`
   regenerates the file per `read()`, and the line-by-line loop returned no
   `SigIgn:` line 8 times in 4500 isolated runs (about 1 to 2 percent of
   suite runs under the CI ambient). The detector printed `unknown`, so the
   gate this change exists to turn green would have flaked. Fix: read the file
   once, `st=$(</proc/$$/status)`, and parse the snapshot (0 of 4500, then 0 of
   1500 again).

## Key Insight

A forced condition is evidence only if every detector of it can also say the
opposite, and a measurement read from a regenerating file must be read in one
call. Both are cheap to build and invisible to a green run: the unwrapped
control and the always-`ignored` canary both ran 126/0.

## Session Errors

1. **The brief placed the earlier red at `b77bee370` on leg 2/4; it was a
   different job, and `c6ae165d0e` was leg 4/4.** Recovery: read the failing
   steps per run before assuming a cause. **Prevention:** a resume brief's
   "measured" facts are preconditions (already in `work` Phase 1); the
   per-run `gh api .../jobs` step listing is the cheap check.
2. **`gh api .../actions/jobs/<id>/logs` printed a terminal-escape refusal
   instead of the log.** Recovery: `gh run view <run> --job <id> --log-failed |
   sed 's/\x1b\[[0-9;]*m//g'`. **Prevention:** use that form first.
3. **My first fix read `/proc/$$/status` line by line (flaky under load).**
   Recovery: single snapshot read. **Prevention:** read any `/proc/<pid>/*`
   status file once into a variable; stress the detector in isolation (thousands
   of runs), because a 1 to 2 percent flake never shows in the 3 to 5 runs that
   precede a push.
4. **The first fix's forced-condition evidence had no negative control or
   routing proof.** Recovery: converse helper, negative controls, routing rows.
   **Prevention:** for every forced condition ask "what does the detector print
   when the forcing is absent", and unwrap the helper once to confirm a row reds
   under the ambient where the unwrap is observable (an unwrapped
   forced-default control is only visible under an ignored ambient).
5. **Mutation row 9 did not land (the mask text occurs in both the probe and
   the shim).** Recovery: the battery's landing assertion refused it; re-ran
   with unique anchors. **Prevention:** keep the `count == 1` landing assertion
   in every battery.
6. **Foreground battery and lint runs exceeded the 300 s tool cap under sibling
   contention and were moved to the background.** Recovery: read the output
   file and re-armed a monitor. **Prevention:** run batteries behind a monitor
   from the start when `test-all.sh --capacity` reports contention.
7. **The stop hook blocked two turn endings that named a future action.**
   Recovery: an explicit stop tag naming what was blocking. **Prevention:** end
   a waiting turn with the stop tag, not a prose promise.
8. **A review seat wrote scratch copies into the live worktree despite the
   sandbox rule.** Recovery: it deleted them; `git status` verified clean.
   **Prevention:** brief seats with the allocator command (already in the
   review skill) and verify `git status` after the panel returns.
9. **Plan and tasks carried pre-review numbers (121/24) after the review
   changed the design (127/25).** Recovery: an append-only Review Amendment
   plus a banner in `tasks.md`. **Prevention:** after a review round that
   changes counts, grep the plan and tasks for the old figures before pushing.

## Tags

category: test-failures
module: apps/web-platform/infra
