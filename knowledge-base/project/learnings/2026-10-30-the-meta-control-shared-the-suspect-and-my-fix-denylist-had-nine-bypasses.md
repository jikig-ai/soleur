# Learning: the meta-control reported through the function it proves, and my fix for a finding was a denylist with nine bypasses

## Problem

Residuals 2 and 3 of #10932 added three guards to one test suite
(`tests/scripts/test-registry-d10-workflow-wiring.sh`): a run of the workflow's "Restore summary"
step body, a die/exit word census over the restore engine, and a nested-run meta-control proving
the suite goes red when its W9 verdict is swapped. The suite was green at 63/0 with a 16-mutant
battery reporting everything killed. Two things were still wrong, and a seven-seat review plus a
second battery found both.

1. **The meta-control reported through `w9_verdict`**, the function it exists to catch. With
   `w9_verdict` rewritten to `echo ok`, the real W9 row printed ok and the nested run printed no
   FAIL line, but the meta-control's own verdict also went through `w9_verdict`, so it passed:
   63/0, exit 0. The inverted-verdict mutant looked caught only because two errors cancelled (the
   outer row failed, and the meta-control inverted with it).
2. **My fix for a review finding was a denylist.** The census pinned the `die()` body by banning
   `return` and rewrites of `code`. The verification seat showed nine edits that change every
   `die` site's real exit status and pass it: delete or repeat `local code="$1"; shift`, add a
   literal `exit 3` before the final exit, `read -r code <<<3`, `printf -v code`, `unset code`,
   a line-continued assignment. A fix is written while holding the defect in mind, so it bans the
   spelling of the defect it just met.

Smaller instances of the same family: the `drop1` handoff variables were unset when the control
did not land (three seats, `set -u` abort and a dead guard line); a summary-env control used an
extra key that sorts before `RESTORE_RESULT`, so a suffix-glob loosening of the pin survived; 14
rejection limbs of the summary checker and the `die()` scope bounds had no control at all.

## Solution

- The meta-control reports inline (`if [[ -z "$w9_mp" ]]`), with a comment saying why. The same
  mutant is now killed, and the inverted verdict produces two FAIL lines.
- The `die()` body is compared as a **closed sequence** against its reviewed text (`W9_DIE_BODY`),
  comments and blank lines dropped. Any change is reported and the pin is updated on purpose.
  Controls: rewrite, return, deleted line, repeated line, literal exit, line appended after the
  echo, exit relocated out of the body, exit before the definition, exit injected into the body.
- One control per rejection limb: outcome text per arm (each limb isolated by its own fixture),
  heading, body exit code, stderr output, no catch-all arm (so the empty outcome is driven), one
  per forbidden step key, extra env keys in both sort directions.
- `w9_expect` refuses an empty needle; `w9_verdict` has its own canary on three inputs.
- Suite: 47 to 89 assertions; every new control was mutation-proved on a sandbox copy
  (52 mutant runs across four batteries, control green each time, pristine copy compared at the end).

## Key Insight

Three rules from one suite, all of the shape "the instrument was shown only the cases its author
was thinking about":

1. A control that proves a verdict function must not report through that function. Ask of every
   verdict site: if this helper always said ok, which line would notice, and does that line call
   the helper? (The repo already says a positive control on `pass()`/`fail()` proves dispatch and
   not the helper that owns the verdict; this is the same shape one level up.)
2. A fix for a finding is the least-audited part of the diff. When the property is "nothing in
   this region changes the outcome", pin the region as a closed sequence; a denylist only bans
   the spellings already seen. The verification seat that re-drives the fix, not the original
   finding, is what found the nine bypasses.
3. A fixture direction is a coverage axis: an extra key that sorts before the pinned one cannot
   tell an equality from a suffix glob. Build the fixture on each side of the thing being pinned.

## Session Errors

1. **Meta-control shared the suspect** — Recovery: reported inline, mutant re-killed — Prevention:
   when adding a control that proves function F, grep the control's own report line for F.
2. **Denylist fix for the `die()` body** — Recovery: closed-sequence pin plus four more controls —
   Prevention: for a "nothing changes the outcome" property, write the pin as the whole region,
   then run the finding's own bypass corpus against the fix before committing.
3. **`drop1` handoff unset under `set -u`** — Recovery: initialised before the loop, meta-control
   requires both non-empty — Prevention: a variable assigned inside a loop that a later block
   reads must be initialised before the loop.
4. **Env control fixture sorted on one side only** — Recovery: second control with the key on
   the other side — Prevention: for a pinned map compared as a sorted string, fixture an extra
   key before and after.
5. **A commit blocked by the repo-targeting hook** because the same Bash call held a heredoc and a
   `bash -c "$var"` loop, so the commit-message file was never written and the retry failed `128`
   — Recovery: wrote the file with the Write tool, committed in its own call — Prevention: the
   `work` rule already says never heredoc into the same call as a hook-gated command; write the
   message with Write first.
6. **`ps … | awk '/pattern/'` blocked as self-matching** — Recovery: used the load average and rc
   files — Prevention: existing hook text names the argv-slot form.
7. **Overwrote a driver file with a prefix rebuild** — Recovery: rewrote it from the earlier
   message and then kept the driver in its own file — Prevention: keep generated prefixes and
   hand-written drivers in separate files.
8. **Plan-phase hook block on draft wording (forwarded)** — Recovery: reworded.
9. **Verifier killed by a transient network error** — Recovery: resumed with `SendMessage`, which
   kept its context — Prevention: resume a dead seat, do not respawn it (existing review rule).

## Tags

category: test-failures
module: tests/scripts, registry restore, review
