# Learning: retiring a probe by file list left a derived baseline row and live runbook claims

## Problem

Stage 3b of #9703 deleted the superseded 8296 follow-through probe and every registration the plan
listed (the `run_suite` line, four `*.tsv` rows, the kb-consumers baseline rows, the `MUST_FIND`
entry, the runbook pointer). Review still found, on a diff whose local suites were green:

- **P1:** `scripts/test-affected-kb-consumers.baseline.txt` carried a third, DERIVED row
  (`inngest-probe-row.test.sh` -> the 6894 runbook). The oracle credits a test with a knowledge-base
  read made by a script it names; once `MUST_FIND` stopped naming the deleted script the hop vanished
  and a required suite (`b1: baseline differs from --write-baseline output`) went red. The plan said
  "the two baseline rows", so its own acceptance grep could not see it.
- **P2 x4:** the 6894 runbook still described the retired probe as a live reporter (verdict names in
  an incident table, a paragraph of probe verdicts, a heading kept "because the probe's text points
  at it") and a pointer to a bullet this PR had deleted.
- **P2:** the new retirement note said "no verification was lost". It was true of the LUKS cipher
  and false of the daily `data_mount_src` mapper-path cross-read, which nothing automated replaces
  (the wrong-volume alert keys on `data_mount_devid` only).

## Solution

- Deleted the one derived row and re-ran `bash scripts/test-affected-kb-consumers.test.sh` (23/23).
- Removed the live-probe claims and the dangling pointer from the runbook, and rewrote the
  retirement note to say what WAS lost, naming the surviving cover and calling the reconcile
  "twice-daily" (it runs `0 6,18 * * *`, not nightly).
- Left the closed-world legal audit record untouched (a ruled decision), and surfaced the one real
  coverage gap to the operator instead of editing a paging alert inside a retirement PR.

## Key Insight

Deleting a script has three kinds of consumers and a file-list sweep sees only the first: its
REGISTRATIONS (greppable by name), the DERIVED artifacts computed from what it reads (a baseline
regenerated from the tree, which never names the script), and the CLAIMS other documents make about
it being alive. After a deletion, run the derived-artifact generators in check mode, not just a
residual-name grep, and sweep the claim ("the probe reports X") rather than the filename.

## Session Errors

1. **Plan listed the baseline rows by name and missed the derived hop.** Recovery: deleted row 142.
   **Prevention:** after deleting any script a registered test names, run
   `scripts/test-affected-kb-consumers.test.sh` (and the other `--write-baseline` checkers) before
   committing; a residual-zero grep over the script name cannot see a derived row.
2. **Swept by file list, leaving live claims about a retired mechanism.** Recovery: rewrote the
   runbook sections. **Prevention:** grep the SUBJECT ("property probe", the verdict names) across
   the runbook and read every hit, as `work/SKILL.md` already prescribes for deletion rounds.
3. **Overclaimed "no verification was lost".** Recovery: reworded with the lost cross-read named.
   **Prevention:** for every "nothing lost" sentence, read the deleted script's check list and say
   which of its verdicts the replacement does not reproduce.
4. **A process-kill loop matched by worktree cwd and killed the agent's own shell (exit 144).**
   Recovery: verified the tree and that only this worktree's processes were gone.
   **Prevention:** use `plugins/soleur/scripts/lib/proc.sh kill_mine <pattern>`, which excludes self,
   ancestry and the process group, instead of a hand-rolled cwd match.
5. **Decision-class category invented instead of copied.** Recovery: the ruling gate rejected it;
   changed to `operator (production-mutating)`. **Prevention:** copy the category word from
   `technical-ruling-delegation.md` section 1 verbatim.
6. **Draft-run `test` row read as red before checking it was the draft run's.** No change needed;
   the lesson is already in the operator brief (`ci-head-verdict.sh verdict <PR>`).

## Tags
category: workflow-issues
module: inngest-probe-retirement
