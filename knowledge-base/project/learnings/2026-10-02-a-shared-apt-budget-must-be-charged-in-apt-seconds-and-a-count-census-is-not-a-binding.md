---
title: A shared apt budget must be charged in apt-seconds, and a count census is not a binding
date: 2026-10-02
category: test-failures
tags: [ci, docker, apt, timeout, shared-budget, mutation-battery, assembly-guard, git-data]
issue: 9379
---

# Learning: a shared apt budget must be charged in apt-seconds, and a count census is not a binding

## Problem

`deploy-script-tests (1/4)` went red on every branch and on `main` (2026-10-01 ~15:00 UTC) because
`git-data-runcmd-rehearsal.test.sh` (bound 600 s) and `git-data-ownership.test.sh` (bound 300 s) hit
`rc=124` with an empty log. Both run `apt-get` inside fresh `ubuntu:24.04` containers; #8744 had bounded
the NUMBER of attempts and not their elapsed time, so one stalled fetch consumed a whole suite budget.

## Solution

`apps/web-platform/infra/lib/apt-bounded.sh` gives every in-container apt cycle a budget of APT SECONDS
shared across all containers of a suite (a host-owned state dir mounted at `/work/apt`: `budget`, plus one
`spent` line per attempt) and a 90 s per-attempt cap with retry. Expiry prints the scrubbed tail, a
`FIXTURE_APT_CAUSE:` line and the bare `FIXTURE_APT_FAILED` marker and exits 100, the shape apt exhaustion
already produced, so every classifier and the existing `arm_skip` routing are unchanged. No arm becomes
skip-eligible (ownership stays fail-closed per #8744). Stall reproduction: ownership ends in a named failure
at 180 s (was killed at 300 s), rehearsal ends in its own verdict at 429 s (was killed at 600 s).

## Key Insight

1. **Charge the budget to the resource that stalls, not to the clock.** The plan specified one absolute
   wall-clock deadline. The first real-docker run falsified it: the suite's NON-apt container time (tarball
   downloads, sshd) spent the deadline and later healthy primary arms starved. A second measurement
   falsified "apt's own `Acquire::http::Timeout=20` covers a stall": about one apt cycle in three stalled for
   the full allotted time and a fresh attempt succeeded in ~15 s, so a shared budget alone lets one stalled
   first attempt eat a third of it. Both were visible only by running the suites against real docker; the
   plan's Phase 4 reproduction was scheduled after the wiring, and should come first for any bound whose
   numbers are inferred.
2. **A derived assembly row that counts lines is a census, not a binding.** The first A10 asserted
   `mounts == calls == arms`. Three review seats independently showed it green under a read-only mount,
   a `/work/apt2` typo, a dropped `|| exit 97`, a hardcoded `|| exit 100` (which launders 97/98/137 into the
   environment decline), a misplaced arm, an unmounted docker site and a raw `apt-get -y install`. The
   author's own 12-mutant battery mutated only the helper, so it could not see any of them. The fix binds
   each docker site to its exact mount token, its arm directly before it, its source line and a pass-through
   rc, and the battery gained a consumer-edit axis (13 mutants, all killed).
3. **Half the lib was never executed.** The host functions (`gd_apt_state_arm`, `gd_apt_state_summary`)
   were hand-built in the unit suite's harness, so deleting the idempotence guard (which would re-zero the
   budget at each of 6 sites and make it 6x) survived. A harness that builds the state a function creates
   cannot test that function.
4. **Validate numeric knobs the way `timeout` reads them.** `timeout 0` means no timeout, so a cap of 0
   silently defeats the bound; `08` is an octal arithmetic error; a backward clock step is a negative
   charge. Each was a one-line validation once named.

## Session Errors

1. **A Bash heredoc containing the text `pgrep -f` was denied by the process-match hook** — Recovery: wrote
   the file with the Write tool — Prevention: prose files go through Write, not a Bash heredoc, so hook
   sentinels in the text cannot trip a command hook.
2. **Write failed three times with "modified since read" after my own scripted edits** — Recovery: re-read,
   then write — Prevention: after any `sed`/`python` edit of a file, Read it again before a full-file Write.
3. **The plan's wall-clock deadline design was wrong** — Recovery: measured, redesigned as apt-seconds —
   Prevention: for a bound whose constants are inferred, run the real-environment reproduction before wiring
   the consumers.
4. **The plan called a per-attempt cap unnecessary on an unmeasured premise** — Recovery: added the cap on
   evidence — Prevention: the same measure-first rule; a claim that justifies OMITTING a mechanism is as
   unmeasured as one that justifies adding it.
5. **Budget constants assumed ~7 s per container; the slow box measured ~32 s** — Recovery: 300 -> 420 s and
   a `GD_APT: spent=` summary line so each run records its own headroom — Prevention: calibrate against the
   slowest measured environment, and print the used fraction on green runs.
6. **The local gate queued behind a sibling for 31 minutes, then went red from a stale base** — Recovery:
   operator chose CI; merged `origin/main`, census green — Prevention: merge `origin/main` before launching
   the gate, and read `--capacity` before a full run on a contended box.
7. **New files tripped `fixture-relative-assert` (9 unguarded redirect sites) and the vacuity-guard deferral
   ledger** — Recovery: canonical `assert_fixture_dir` in the lib, promotion entry for the new suite —
   Prevention: run those two ratchets before the first commit of a new `.test.sh` or sourced lib (work §6.6).
8. **ADR-188 and the vacuity guard conflicted with sibling appends** — Recovery: kept both sides —
   Prevention: none beyond the existing `merge-tree` check before the panel.
9. **My first battery mutated only the helper; the assembly row's weakness was found by three review seats** —
   Recovery: wider battery incl. consumer edits — Prevention: any derived assembly row gets a battery arm
   that edits the CONSUMERS it reads, one mutant per property it claims.
10. **Python mutation snippets with `\$` did not land** — Recovery: caught by the landing assertion, re-ran —
    Prevention: unchanged; the landing check is what made it visible.
11. **Two review seats ran `git checkout --detach` against a report-only brief** — Recovery: no files
    changed — Prevention: brief "use `git worktree add --detach` only" instead of "run no git writes".
12. **The stop hook flagged turns that were waiting on background jobs** — Recovery: `<stop>` tags —
    Prevention: end such turns with the explicit BLOCKED form from the start.

## Tags
category: test-failures
module: apps/web-platform/infra
