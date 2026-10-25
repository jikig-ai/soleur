# Learning: a fix round reintroduced the defect class it was closing, and the worktree was reaped under uncommitted edits

## Problem

PR #10948 (#10832, Ref #9454) made `sync-pr-behind.sh` judge an armed BEHIND PR against its own base branch. Two process
findings came out of the review fix round, neither about the feature itself.

1. **The fix round introduced a defect of the class it was sanitising.** Round 1 added
   `sdisp="$(printf '%s' "$state_line" | head -c 200 | qb_clean)"` to cut and sanitise gh's raw `2>&1` answer in the standalone
   loop. It is an assignment under `set -euo pipefail`: when `head -c 200` exits early on a long answer (reliably at 64 kB and
   above, intermittently from about 8 kB) `printf` takes SIGPIPE, the pipeline status is 141, and the loop dies with no
   `kind=` line. The panel SHA returned rc 0 at every size, so the regression was the fix round's own. A second instance of
   the same class sat one function away: `qw_foreign` echoed the loop's raw multi-line answer, unsanitised, into a
   model-visible line (found independently by six seats).
2. **The worktree was reaped between turns.** While the lead waited on background suites and seats, the checked-out worktree
   directory and its registration disappeared. The branch and its pushed commits survived; the fix-round edits, which were
   uncommitted at that point, did not. They were replayed from the session transcript.

## Solution

1. Cut by substring, not by a head pipe, in any assignment: `sdisp="$(printf '%s' "${state_line:0:200}" | qb_clean)"`. A pipe
   inside a `tag ... "$(...)"` argument is safe because the substitution status is ignored there. Add a row that feeds a
   70 kB answer (and a mutant that restores the `head -c` form) so the instrument sees it. `qw_foreign` now takes the first
   line of its argument, cuts it to 60 characters and sanitises it, with a row (a forged tag line plus an ESC byte in a
   multi-line state) and a mutant.
2. Recreate with `git worktree add <path> <existing-branch>` and replay; then commit before waiting again.

## Key Insight

- A pipe into `head -c N` inside a plain assignment under `pipefail` is a latent kill switch whose trigger is input length;
  tests with short fixtures never reach it. Search the class (`| head -c .* |` in an assignment) whenever a fix adds a
  bounded echo, and prefer `${var:0:N}` for the cut.
- A fix commit is the least-audited surface in the diff: grade it for the class it claims to close, and grep every other
  consumer of the same input (here, every place that echoes a raw gh answer).
- Uncommitted work in a worktree is not durable across a long wait: the worktree reaper and other sessions' cleanup can
  remove it. Commit (even a local WIP commit) before blocking on background suites or review seats.

## Session Errors

1. **Fix round's `sdisp` assignment SIGPIPEs under pipefail (rc 141 on a long answer)** — Recovery: substring cut,
   row `lsh` + mutant G6-8 — Prevention: when adding a bounded echo, use `${var:0:N}`; grep new `| head -c` pipes for
   assignment context before committing.
2. **`qw_foreign` echoed the loop's raw multi-line gh answer** — Recovery: first line only, cut to 60, `qb_clean`; row `lsg` +
   mutant G6-7 — Prevention: when sanitising echoes of an input, enumerate every consumer of that input, including helpers
   that receive it as an argument.
3. **Worktree removed outside the session with uncommitted edits** — Recovery: `git worktree add` on the pushed branch and
   replay of every edit; suites re-run (272/0) — Prevention: commit a WIP before waiting on long background work.
4. **Commit blocked by the commit-on-main hook because the shell cwd had reset to the bare repo root** — Recovery: run
   `cd <worktree> && git commit` with a literal path in the same command — Prevention: none needed; the hook's message
   names the repair.
5. **Commit message file never written, because its heredoc lived in the command the hook blocked** — Recovery: re-wrote it
   with the Write tool — Prevention: write commit-message files in their own call, not in the same command as the commit.
6. **Python replace scripts failed on quoting** (a `'` decoded inside a normal string; an apostrophe ended a raw string)
   — Recovery: build the escape with `chr(92)+'u0027'` and use unambiguous quoting — Prevention: apply byte-exact edits
   with the Edit tool or a quoted-heredoc script that asserts each anchor occurs exactly once.
7. **Mutant anchors went stale after the text they target changed** (`G3-2`, `G3-4`, `G3-9`) — Recovery: the mutation
   helper reports an absent anchor as a failure, so they were caught on the first run and re-anchored — Prevention: none
   needed; the harness already fails loudly.

## Tags
category: workflow-issues
module: plugins/soleur/scripts/sync-pr-behind.sh
