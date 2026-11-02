# Learning: a tree-scan guard needs linear-time matching, a counted canary, and a proportionality check before it is built

## Problem

PR #10891 (Ref #10664 Site C) removed a read-only-then-read/write Hetzner token fallback and added a tree-wide
scanner so the fallback cannot return. The first build of the scanner (533 lines plus a 370-line suite) passed its
own 42-case suite and a 4-mutation battery, and a 10-seat review panel still found real defects, all in the guard:

- The rule was a regex chain `doppler SEG secrets SEG get SEG tail`. It backtracked catastrophically (53 s on a 9.6 KB
  line with many `secrets get` tokens) inside an always-on suite that runs on every PR.
- The suite's `expect_all` fed expectations to `read` from `printf '%s'` with no trailing newline, so the LAST
  `~`-separated expectation of every row was never checked. Every row stayed green.
- The suite's verdict helper, `expect_all` and floor chain could each be neutered with the suite still exiting 0
  (no canary), and the canary added afterwards could itself be deleted because it unwound its own counters.
- The population excluded files production executes (`tests/scripts/lib/*-gate.sh` is sourced by Tier-B workflow
  jobs, workflows themselves, `test-*` scripts that CI runs), and a trailing-backslash inline comment glued the next
  line so a real read hid (a regression introduced by the fix for mid-word continuation splits).

## Solution

- Split-and-find-earliest instead of a regex chain: split each logical line on the command boundaries, take the
  earliest `doppler`, then the earliest `secrets` after it, then the earliest `get`; the tail is searched once.
  Linear, and complete (the earliest triple has the widest tail). A differential test against the old regexes on
  tens of thousands of random lines gave zero lost matches.
- Make every harness helper that owns a verdict self-testing: a canary that drives `verdict()` with a deliberately
  wrong rc and a wrong expectation and requires failures, ends in a COUNTED pass, and sits under an exact floor.
- Pin the population claim in both directions with rows (a violation in each file class is found; each excluded
  class is not scanned), including "workflows are scanned".
- Bash-exact line continuation (delete backslash-newline) but end the logical line at a comment start.
- Ask the proportionality question at plan time: a CTO-settled 900-line scanner shrank to ~290 lines after a
  design-validity pass asked "which requirement does each mechanism satisfy, and does a simpler one already do it".

## Key Insight

A guard's own test harness is the least-reviewed code in the diff, and a regex over untrusted lines is a latent
hang in an always-on suite. Build the harness canary, the linear matcher and the per-class population rows first;
run the design-validity (proportionality) pass before the panel, not after.

## Session Errors

1. **Seat briefs mandated a report file under the main checkout's `.git/worktrees/...`; a PreToolUse hook denied
   it.** Recovery: the seat delivered in its final message. **Prevention:** `review/SKILL.md` Sharp Edges now says
   brief "final message IS the deliverable" and name no file there.
2. **`expect_all` never checked the last expectation of any row** (`printf '%s'` without a trailing newline into
   `read`). Recovery: found by the new harness canary, fixed with `printf '%s\n'`. **Prevention:** a harness canary
   that feeds a deliberately missing LAST item; build it before the matrix.
3. **Catastrophic regex backtracking in the scanner rule.** Recovery: split-and-find. **Prevention:** time every
   tree-scan regex on a ~100 KB line with many repeated keywords before registering it always-on; keep a
   `timeout 3` row that also ends in a real match (so a skip-long-lines shortcut fails it).
4. **A continuation fix regressed comments** (deleting backslash-newline after `# comment` glued two commands).
   Recovery: end the logical line at a comment start. **Prevention:** when switching a join from space to
   bash-exact deletion, add a row where the previous line ends in a comment.
5. **First `git push` after a rebase was rejected** (remote held the pre-rebase commits). Recovery:
   `--force-with-lease` with the expected remote sha on my own feature branch. **Prevention:** none beyond the
   existing lease practice.
6. **A single `test-all-affected` failure (227/228) did not reproduce and its log was lost** (it lived in a
   `mktemp` dir created inside the same command whose output was discarded). **Prevention:** run long suites with
   the log under a known `/var/tmp` path from the start so a one-off failure is attributable.
7. **A foreground verification chain exceeded the 600 s tool limit** and was backgrounded. **Prevention:** start
   anything containing the affected-selection suite (about 40 minutes) in the background with a monitor.
8. **The plan-time CTO ruling accepted a 533-line scanner** and the design-validity pass cut it by half.
   **Prevention:** put the proportionality question ("what is the cheapest mechanism that holds the property, and
   what does the always-on cost?") into the plan's guard section; the rule exists in the review skill but fires
   too late to save the build.
9. **I drafted "228/228" in the PR body before re-running on the final head** and re-ran before publishing.
   **Prevention:** fill numeric claims in a PR body only from a run on the head the body names.
10. **A Stop-hook "unkept promise" block fired** on closing text that named an action. **Prevention:** end a turn
    that waits on a background task with `Paused: <what is awaited>` rather than a future-tense plan.

## Tags

category: workflow-issues
module: scripts/lint-hcloud-token-readonly-no-fallback.sh
