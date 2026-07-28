---
date: 2026-07-28
category: best-practices
module: apps/web-platform/infra, scripts/test-all.sh
issue: 7014
pr: TBD
tags: [drift-guard, mutation-testing, vacuity, fail-open, contention, review]
---

# Learning: I asserted six properties in a PR whose entire subject was asserting properties

## Problem

#7014 asked for five battery-completeness gaps to be closed in
`web-host-provisioner-parity.test.sh` and its mutation battery. The issue was explicit that
none was a present fail-open — they were future-erosion risks.

The fix ran green the whole way: guard 13/0, battery 43/43, infra suites 76/76, `test-all.sh`
233/233. A four-agent review panel then found **14 defects in the fix**, including three live
fail-opens the green run could not see, and two of those were the *same class the PR existed
to remove*.

## Root cause

Every one of the serious findings reduces to a single sentence: **I wrote down a property
instead of measuring it.** Six times, in a change about exactly that habit.

1. **"The probe can only ADD failures, never suppress one."** Asserted twice in prose, verified
   by nothing. A reviewer added one line merging the probe into the real `ALLOWLIST` and
   suppressed a genuine uncovered destination — while P1–P3 still scored 3/3. The disclaimer
   described an intention, not a mechanism.
2. **"`apps/…` sorts near the front of any diff, so the SIGPIPE early match is the common
   case."** Wrong mechanism entirely. SIGPIPE needs the producer's output to exceed the ~64 KiB
   pipe buffer; match *position* is irrelevant. Measured: matched correctly at 100/1,000/5,000
   paths, fail-open only past ~1,300 changed files. The herestring fix was right; the reason
   given for it was not, and as a template it teaches the wrong rule.
3. **"`tc_epilogue` fires the LOW_TMP_HEADROOM / SIBLING_RUN_DETECTED /
   LOCK_CONTENDED_PROCEEDING banners."** They fire in `tc_preamble` and `tc_acquire`, at the
   *top* of the log. I wrote this into the very bullet telling readers where to look.
4. **"This floor cannot be exercised in ISOLATION … shrinking the intersection *necessarily*
   moves another check."** An over-claim stated as a theorem. It happens to hold for today's
   delivery layout (instrumentation found zero destinations with two fresh-boot channels), but
   that is a property of the current tree, not a proof.
5. **"The derivation keeps the battery CORRECT under drift."** It does not — it *aborts*.
6. **`M33b` asserted the summary line** to prove the §0 early exit. `print(summary)` runs
   *before* `sys.exit(1)`, so neutering the exit left the assertion green. The case pinned the
   thing that was already there.

Plus a seventh of the same shape: the guard fix for `destination = ""` shipped with **no
covering mutation**. The neuter matrix scored it UNCOVERED — a fix with nothing behind it.

## Solution

**Neuter every assertion site and require the battery to go red on the case named for it.**
Not "run the battery and see green" — remove each check in a sandbox copy of the guard and
confirm a *specific* named case fails. 14 sites, 14 confirmations. That is what found M33b's
vacuity and the uncovered empty-destination fix; nothing else would have.

Specific fixes worth carrying forward:

- **A test hook that could suppress a finding is a fail-open switch.** The probe injects into a
  *separate* dict consumed only by the hygiene function; it can never reach the coverage loop.
  `P4` is the negative control that proves it: break §2 for real, hand the probe an entry naming
  that exact path, require the finding to survive.
- **Anchor structural regexes to structure.** The unresolvable-destination regex ran unanchored
  over the whole resource body, so `logger --destination=/var/log/audit.log` produced a bogus
  "HCL REFERENCE" finding. An HCL attribute is the first token on its line; a shell flag is not.
- **Remediation advice is part of the assertion.** Both the unresolvable and interpolated
  messages advised `ALLOWLIST` — which neither branch consults, and which trips the stale-entry
  check. Following the advice turned one failure into two.
- **A margin is an erosion window.** `FLOOR_DESTS` at 50 against a real 52 absorbed two silent
  losses; `FLOOR_SEEDED` at 30 against 36 absorbed six. Both pinned to exact baseline. This also
  produced an unplanned second defence: breaking `strip_comments`' string-awareness drops the
  sweep to 50, which the *old* floor passed silently and the new one catches.

## Key Insight

**A green mutation battery is evidence about the mutations you imagined, not about the guard.**
The battery reported 43/43 while `strip_comments` had zero coverage, two `ALLOWLIST` wirings
were deletable, and an unsandboxed fifth input could be read tolerantly with the whole run
clean. Two agents independently drove that fifth-input bypass — using the shape *the issue
itself described* — past all three of my new assertions.

The generalisation: **for every property a comment claims, ask "what would fail if this were
false?"** If the answer is "nothing", it is documentation wearing a guard's clothes. That test
is cheap, it is mechanical, and it caught all six here when applied after the fact by other
readers. It should have been applied at write time by me.

## Session Errors

1. **Worktree and branch reaped mid-session** by a sibling `cleanup-merged` before any commit
   existed; the session lease did not protect it. Recovery: recreated + `git worktree lock`.
   **Prevention:** lock the worktree immediately after `create`, or land a commit before any
   long-running step.
2. **CWD drift** — a relative `cd` in a later Bash call resolved against a persisted CWD and
   failed. Recovery: absolute paths throughout. **Prevention:** already a documented trap; use
   worktree-absolute paths in every call.
3. **Neuter mutator used a global `@`→`'` replace**, corrupting the guard so its baseline went
   red and one case's result was void. Recovery: rebuilt the mutator with `chr(39)`.
   **Prevention:** never use a placeholder-substitution trick on a file whose content you do not
   control; a red baseline voids every result measured against it.
4. **Verification runs exceeded the Bash timeout twice** (2 min, then 10 min), once leaving the
   guard mutated on disk. Recovery: restored from a pristine backup. **Prevention:** back up to
   an echoed `mktemp` path before mutating, and put the restore in a *separate* Bash call so a
   killed run cannot skip it.
5. **The scratch verification harness was silently emptied between sessions.** Recovery:
   rewrote it. **Prevention:** the repo already records that ad-hoc verification evidence is as
   perishable as uncommitted code — a matrix that backs a shipped claim belongs in the repo.
6. **Backticks inside a double-quoted bash label** ran `local.` and `var.` as commands, blanking
   two mutation labels the split existed to distinguish. Caught by shellcheck SC2288.
   **Prevention:** run shellcheck before committing a `.test.sh`; a file-scoped `SC2016` disable
   makes it easy to assume quoting is already handled.
7. **Nearly accepted battery flakiness as "stable — ran twice".** Three runs of an unchanged
   tree gave three different failure sets. **Prevention:** a flaky *gate* is a defect to
   diagnose, never a re-run to repeat; the cause here was real (below).
8. **Six properties asserted rather than measured** (see Root cause). **Prevention:** for every
   claim in a comment, name the input that would make it fail.
9. **A background-task notification reported "exit code 0" while the real exit was 1 — twice.**
   The trailing `echo` supplies the notification's status. Recovery: read `rc` from the output
   file. **Prevention:** already an `hr` rule; it fired twice anyway because the notification is
   the more salient signal.
10. **The empty-destination guard fix shipped with no covering mutation.** Recovery: added M29d,
    proven load-bearing. **Prevention:** every guard change gets a case in the same commit; the
    neuter matrix is what surfaces the omission.
11. **`git stash list` denied by hook.** Recovery: removed it. **Prevention:** the rule is
    hook-enforced; use `git show <commit>:<path>`.

## Bonus: the flaky gate was itself a silent-corruption vector

The battery's flakiness had a real cause worth its own note. `/tmp` is a machine-global 4 GiB
tmpfs shared by parallel worktrees and sat at **94% (255 MB free)** under three sibling
`test-all.sh` runs. `test-all.sh` and `run-registered-suites.sh` both default `TMPDIR` to
`/var/tmp`; the battery did not, so a **direct** invocation — the documented inner loop while
editing the guard — put its sandbox on the contended tmpfs.

`restore()` then had no error checking. A failed `cp` left the *previous* case's mutation in the
sandbox, and every later case ran against a fixture nobody chose. The observable symptom was a
case reporting **"guard still PASSED with the invariant broken"** — a confident verdict about
the guard, produced by a harness that could not copy a file.

Both halves fixed: `TMPDIR` defaults to `/var/tmp`, and `restore()` aborts the run rather than
continuing over a fixture it failed to reset. 4/4 clean runs under the same conditions that
produced three different failure sets.

**Generalisable:** a harness that fails to set up must abort, never continue. Silent setup
failure is indistinguishable from a real result, and it produces the most confident-sounding
wrong answers.
