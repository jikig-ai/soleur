# Learning: the probe went blind when its suite moved INTO the capturing runner, not when capture began

## Problem

The daily skip-persistence probe (`scripts/followthroughs/t5-skip-persistence-bound-7510.sh`) returned
TRANSIENT from 2026-09-28 ("none containing 'git-data-runcmd-rehearsal:'"). Issue #10786 asked whether the
marker moved or the suite genuinely skipped. Measured on real runs: the marker moved. The suite ran and
passed; its stdout never reached the Actions log.

The mechanism was misattributed for most of the session. The plan said the runner's per-suite capture
started with #8763. History says otherwise: the capture and the reap-on-green date from #7423 (2026-08-10/11).
What #8763 (2026-09-25) changed is that the rehearsal suite stopped running as its own workflow step, with
its output going straight to the log, and moved inside the already-capturing runner. The wrong sentence
reached the runner header, the probe header, ADR-188, ADR-252, a plan table cell and a test-suite header
before the history seat falsified it.

## Solution

The runner (`apps/web-platform/infra/run-registered-suites.sh`) relays the evidence the probe needs, after
the suites finish and before the log dir is reaped: every column-0 `SKIP (loud):` line of any suite
(capped per suite) and the rehearsal suite's terminal summary line, as `SOLEUR| relay <basename>: <line>`.
The probe's literals are unchanged (CTO-ruled). The relay read is bounded at the source
(`grep -m`, `cut -b`) and control characters become spaces.

The chain suite text -> relay regex -> probe literal is pinned by value, not by presence:

- the real suite's terminal `echo` is expanded with sample numbers and matched against the runner's regex;
- the real `arm_skip` echo is expanded with the T5 arm name and matched against the runner's skip regex and
  the probe's own marker;
- an end-to-end section feeds the REAL runner's stdout to the probe (skip -> 1, terminal only -> 0,
  neither -> 2), and an edit-the-pair harness proves that editing either end turns the terminal-only case
  from 0 into exit 2.

## Key Insight

1. **A causal sentence of the form "since #N, X happens" names what #N CONTAINS, not what it CHANGED.** Before
   it enters a plan, an ADR or a comment, run `git log -S` on the mechanism and read what the commit removed
   or moved. Here #8763 removed a workflow step; it added no capture. A fix whose root cause is "the
   observation channel changed" is only as good as the date the channel changed.
2. **An observer is blind from the moment its subject moves behind an unobserved boundary, and a positive
   control that shares the failing path reports TRANSIENT, not FAIL.** The probe did the right thing by
   refusing a verdict; the defect was that nothing pinned the path it relied on, so the loss was silent for
   three weeks.
3. **Pin an emitter by VALUE.** The terminal line was pinned and the skip line was not, so a one-word edit to
   `arm_skip`'s prefix would have zeroed the relay and the probe while the terminal-line control kept
   reporting a healthy PASS. A hand-written fixture echo cannot catch that.
4. **Two seats found P2s the author's own 4-row battery could not reach**, all of them fixture-shape gaps:
   `grep -a` with a NUL byte earlier in the capture, terminal-looking decoys under the mapped basename
   (a decoy that is indented, or has the wrong shape, is invisible to a counter that expects a single
   space), sanitiser classes beyond CR, and `mapfile -t`.

## Session Errors

1. **Read-only `git stash list` denied by the stash hook** — Recovery: dropped the call. Prevention: the hook
   already covers it; probe for stashes with `git rev-parse --verify --quiet refs/stash` (work Phase 0.5).
2. **A persistent `cd` into a sibling worktree and into the infra directory drifted the shell CWD** —
   Recovery: re-`cd` to the worktree in each command. Prevention: chain `cd <abs> && cmd` in one call and use
   absolute paths (already in work/SKILL.md).
3. **`git commit` into a scratch repo through a `$VAR` path blocked by the commit-target hook** — Recovery:
   `git init` alone is enough for the suite (no commit needed). Prevention: name repositories as literal
   absolute paths when a hook has to resolve the target.
4. **`pgrep -f` blocked as self-matching** — Recovery: stopped probing processes; used rc marker files.
   Prevention: already enforced by `pkill-self-match-guard.sh`.
5. **The first skip-emitter pin anchored on a line-start `echo`, but the real emitter is inline after `;`** —
   Recovery: matched the exact statement with `grep -oF`. Prevention: pin an emitter by the statement text
   inside the real file and run the pin once against the real file before trusting it (a pin that never saw
   a positive is silence).
6. **T13o asserted "exactly 1" blank line after a relay line, coupling it to the note below** — Recovery:
   bounded it with `<= 1`. Prevention: assert a property (no doubled blank lines), not the layout around it.
7. **`rm -rf "$var"` in a new test raised the fixture-relative ratchet by one** — Recovery: pointed the
   runner's `TMPDIR` inside the suite's own `$TMP` instead of deleting a path by variable. Prevention:
   already documented in work/SKILL.md section 6.6; use the owned-root redirect.
8. **Ticked an acceptance criterion whose second half (PR body) was not yet true** — Recovery: unticked it
   in the same edit cycle. Prevention: tick an AC only by running the command it names.
9. **The affected gate ended `rc=6` (budget deferred) rather than a verdict** — Recovery: ran every suite the
   diff could reach by hand and recorded CI as the authoritative gate. Prevention: none; the contract names
   rc 6 and says never to label it passed.
10. **A scratch-repo mutation run of the runner suite derived 0 suites** — Recovery: used the `SUT=` seam
    from the worktree root instead. Prevention: a sandbox for a guard that reads `git ls-tree HEAD` must be
    a repo with a commit, or use the seam the suite already provides.
11. **Inherited causal attribution ("#8763 introduced the capture") copied from the plan into six artifacts**
    — Recovery: history seat, then a sweep of the PARAPHRASES across the touched files. Prevention: verify
    any "since #N" sentence with `git log -S` before it is written (plan Sharp Edges bullet added).
12. **Closing line named a pending action without taking it (stop hook)** — Recovery: ended with a `Paused:`
    sentence naming what was awaited. Prevention: end a waiting turn with the labelled sentence.
13. **A background launcher's "completed (exit code 0)" notification was nearly read as the suite's verdict**
    — Recovery: watched an rc marker file instead. Prevention: already documented (read the rc file, never
    the notification).

## Tags

category: logic-errors
module: infra-test-runner, followthrough-probes
