---
title: The per-line probe I wrote to tighten the guard passed an uncompilable pattern
date: 2026-09-25
category: test-failures
module: .claude/hooks/grep-q-pipe-guard.test.sh
issue: 8807
pr: 8866
tags: [grep, exit-code, negated-grep, non-vacuity, guard, sigpipe, review]
---

# Learning: a negated grep reads "pattern did not compile" as "no match"

## Problem

#8807: `grep-q-pipe-guard.test.sh` flagged `|| grep -q … <<<"$x"` (a logical OR followed by the
safe herestring form) because its PATTERN `\|[[:space:]]*grep…` matched the second bar of `||`.
The fix anchored the pipe as `(^|[^|])\|&?…` and, per the plan, replaced a one-line probe with
4-line bad/good heredocs checked per line:

```bash
[[ -s bad && -s good ]] && ! grep -qvE "$PATTERN" bad && ! grep -qE "$PATTERN" good
```

RED (old pattern: 3/4 forbidden, 3 fixed matched) and GREEN (3 PASS lines) both checked out. The
test-design review then dropped one `)` from PATTERN: grep printed `Unmatched ( or \(`, and the
guard reported three PASS lines and exited 0. Both negated greps turn grep's rc 2 into "no match",
and both repo sweeps end in `|| true`. The old probe (`grep -qE p bad && …`) had failed on rc 2,
so the rewrite removed the only check that caught a broken regex.

## Solution

- Compile pre-check: `rc=0; grep -E -- "$PATTERN" </dev/null >/dev/null 2>&1 || rc=$?`; anything
  but rc 1 exits 3 (UNRESOLVED).
- Compare COUNTS instead of negating: `grep -c` hits must equal the bad file's line count and be
  `0` for the good file. On error `grep -c` prints nothing, which can equal neither.
- Two more bad lines (`done|grep -iq`, `$(f)|grep -sq`) killed the surviving mutants
  `(^|[ "])` and `-[A-Z]*q`.
- The sibling copy in `test-lint-supabase-deprecated-endpoints.sh` row 10 now holds the regex in
  one variable, with a planted-pipe / `||` self-check (the planted pipe is built from a `$_qp_bar`
  variable so the suite's own source scan does not flag it).
- Mutation battery after the fix: 6/6 on the guard, 2/2 on the sibling self-check.

## Key Insight

Tightening a probe from "any line matches" to "every line matches" is a real gain, but writing it
as a negation (`! grep -qv`) trades one failure direction for another: the new check sees a
pattern that misses line 2, and goes blind to a pattern that does not parse. A guard's
non-vacuity check has three outcomes, match, no match and could not evaluate, and a negation
merges the last two. Count comparisons keep all three apart.

## Session Errors

1. **Filing the #8869 deferral was refused once by the milestone hook.** Recovery: retried with
   `--milestone`. **Prevention:** already hook-enforced; pass `--milestone` on the first call.
2. **The brief said the FILES_8664 block had merged; it lives only on open draft #8848.**
   Recovery: a test merge against #8848's head confirmed no conflict. **Prevention:** existing
   rule (plan-quoted premises are preconditions); `gh pr view --json state` before trusting.
3. **Planning cost ~363k tokens for a 3-line fix.** Recovery: none. **Prevention:** keep
   deepen-plan for a one-file test fix to one review pass; the plan ran 361 lines and restated
   its own code blocks.
4. **The plan-prescribed negated-grep probe passed an uncompilable PATTERN (the P1).** Recovery:
   count comparison plus a compile pre-check. **Prevention:** new bullet in
   `plugins/soleur/skills/plan/references/plan-sharp-edges.md`: a check rewritten as a negated
   grep must still fail on rc 2.
5. **`git rev-parse origin/<branch>` after a push printed `fatal: Needed a single revision`.**
   The push had succeeded; the remote-tracking ref did not exist. **Prevention:** verify pushes
   with `git ls-remote origin refs/heads/<branch>`, which reads the remote.
6. **`test-all.sh --capacity` plus `--print-affected-set` exceeded the 120s tool limit on a
   contended box.** Recovery: read the backgrounded output. **Prevention:** run `--capacity` alone;
   it is the ~3 s probe, and the affected-set preview is not.
7. **The stop hook fired twice on a first-person "I'll fix after the seats return".** Recovery:
   applied the fixes instead of waiting, since the remaining seat only read scratch files.
   **Prevention:** when legitimately waiting, state the blocker with a `<stop>BLOCKED: …</stop>`
   line and no future-tense commitment.
8. **A Python heredoc wrote `\\grep` into a shell comment.** Recovery: `sed` back to `\grep` and
   grep the line. **Prevention:** after a scripted edit that carries backslashes, print the edited
   line back.

## Tags
category: test-failures
module: .claude/hooks
