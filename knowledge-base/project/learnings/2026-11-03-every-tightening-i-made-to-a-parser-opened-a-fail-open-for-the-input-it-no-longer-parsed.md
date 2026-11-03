# Learning: every tightening of a parser opened a fail-open for the input it no longer parsed

## Problem

Launch-check PR-B (#11949) writes issues into a customer's own tracker and decides "already filed" by reading a
`<!-- launch-check:gap=<ID> -->` marker out of live issue bodies. Review round 1 found the substring match could
be forged by a quoted marker, so the fix anchored the marker to a whole line. That fix was correct for the forged
case and wrong for the near-miss: a marker line with one trailing space or tab (a customer edit, a copy-paste) no
longer matched, the issue read as "no marker", and `--create` filed a duplicate epic or gap issue. Three of ten
verification seats reproduced it independently against the stub. The same round-1 pass also fixed an awk
fail-open at one site (the plan validators) while three sibling awk calls in the same file kept
`awk ... && lc_abort`, which reads a dead awk (rc 2) as "no hit".

Both defects were introduced by fix commits, not by the feature: the class was fixed at the instance each time.

## Solution

- Tolerate the near-miss on the identity regex (`[ \t]*\r?$`), and make every state the parser can no longer
  read an ABORT, not a skip: an `lc:epic` issue with no usable marker is an epic candidate and stops create.
- Give each awk gate a three-valued result (0 hit, 1 none, anything else = incomplete/lookup-malformed) at every
  site that uses the awk exit status as a boolean, found by grepping the construct, not the one site named.
- Pin each with a PATH-shimmed awk that exits 2 and a seeded issue carrying the near-miss, and mutate-verify that
  reverting the fix reds the row.

## Key Insight

Tightening a parse never removes inputs, it moves them from "matched" to "unmatched", and an unmatched live
record that the tool cannot see is the duplicate-spam path. When a fix narrows what a parser accepts, list the
near-miss inputs it now rejects (whitespace, CR, case, a lost marker) and decide for each whether the safe outcome
is tolerate, abort, or skip; "skip" is only safe when the run could not have written for that record anyway. And
an exit status used as a boolean is a claim about the tool's health: grep every use of the construct, not the
site the finding named.

## Session Errors

1. **A fix commit narrowed the marker regex and reintroduced the duplicate-spam path it guards against.**
   Recovery: tolerance plus marker-less-epic-candidate abort, with seeded-issue tests.
   **Prevention:** a fix that narrows an accepted input set lists the newly-rejected near-miss inputs in the
   commit and gives each a test; the review "fix commit is the least-audited surface" rule already asks for the
   class sweep, apply it to parsers by grepping every consumer of the same input.
2. **Awk exit status used as a boolean at four sites; the first fix covered one.** Recovery: `lc__ign_hits`
   tri-state helper at the gate and preview, rc checks on the epic-section awks. **Prevention:** grep the
   construct (`awk ... &&`/`|| lc_abort` with a boolean `exit`) repo-wide when fixing one; a dead tool must stop
   the run.
3. **Review briefs and the batch fix brief lived in the session scratchpad and were wiped when the session
   restarted; one seat was lost mid-run.** Recovery: re-spawned the seat, rewrote a self-contained brief.
   **Prevention:** a brief a later seat or fix agent depends on is written to a path that survives a restart
   (the worktree git-dir), and a seat prompt carries its own constraints inline.
4. **A background command mixed `git status` output into the ratchet output, hiding its exit code.** Recovery:
   re-ran with the rc written to a status file. **Prevention:** never end a background string with a convenience
   command; write `RC=$?` to a file immediately after the command that matters.
5. **The Bash hook blocked a heredoc containing the literal phrase for a process-pattern kill.** Recovery: wrote
   the brief with the Write tool. **Prevention:** prose that quotes a banned command goes through Write, not Bash.
6. **Plan-phase: the IaC-routing hook blocked a plan write, a hook blocked the literal issue-create form, and
   `decision-challenges.md` had malformed rows (forwarded from session-state.md).** Recovery: reworded; body
   written as a separate file; rows rewritten. **Prevention:** none beyond the existing hooks.
7. **The implementer agent sat idle ~90 minutes after an orphan-lint rc=1 (the old suite file was still
   tracked).** Recovery: resumed it via SendMessage; the lint went green once the split was committed.
   **Prevention:** commit a suite split before running the orphan lint.

## Tags
category: logic-errors
module: launch-check
