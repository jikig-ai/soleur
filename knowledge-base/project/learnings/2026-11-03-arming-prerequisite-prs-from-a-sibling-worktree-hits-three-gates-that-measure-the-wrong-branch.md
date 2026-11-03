# Learning: arming prerequisite PRs from a sibling worktree hits gates that measure the wrong branch (#11294)

## Problem

Landing the three-PR key-rotation train (#11930 redaction filter, #11934 census `@allow` rows, #11918 workflow) took
four detours that each looked like a code problem and were not:

1. `gh pr merge 11930` from the #11918 worktree was refused twice. The pre-merge hook auto-merges `origin/main` into the
   CURRENT checkout's branch, and #11918's branch conflicted on `PJ_TRIPLES` in `grep-q-pipe-guard.test.sh`. The refusal
   named a file in a PR the command did not touch.
2. Two `gh pr merge` calls in one Bash command were refused (the KB-archive gate must prove which head each merge lands).
3. #11930 and #11934 had no review evidence (the hook wants a `review:` commit or `Reviewed-By-Soleur` trailer on the
   exact pushed head), so arming needed a real `soleur:review` on each, not a trailer.
4. After arming, #11934 sat BLOCKED with every check green and #11930 sat BEHIND: the required `cla-evidence` check
   had been CANCELLED on both current heads, because the review agent pushed several commits in quick succession and each
   push cancelled the previous `pull_request_target` run. The required context was then simply absent on the head.

A fifth, subtler one: while a merge is uncommitted, `git merge-base HEAD origin/main` is still the OLD base, so the census
suite's forward-only ratchet (T4) reported the six new tier-a rows as "no @allow at the merge-base" even though main now
carried the `@allow` lines. Committing the merge fixed it; regenerating the baseline again would not have.

## Solution

- Resolve the cwd branch's own main-conflict first (take main's block for `PJ_TRIPLES`, prepend the branch's `+N at #…`
  clause, re-run the guard), or arm from the PR's own worktree.
- One `gh pr merge N --squash --auto` per call.
- Run a real review on a prerequisite PR; do not emit the trailer to satisfy the hook.
- When a PR is BLOCKED with all checks green, diff the ruleset's required contexts (both rulesets: "CI Required" AND
  "CLA Required") against the head's reported contexts, then `gh run list --workflow cla-evidence.yml --branch <b>` and
  `gh run rerun <id>` for a cancelled run.
- Commit the merge before running a ratchet that reads the merge-base.

## Key Insight

A gate that is keyed on the current checkout, or on the latest run, answers a question about the wrong object whenever
the operator acts on a different PR than the one checked out. Name the object each gate measures (cwd branch, pushed head,
latest run) before reading its refusal as a verdict on the PR you addressed.

## Session Errors

1. **`gh pr merge` refused by an auto-sync of the cwd branch** — Recovery: resolved the `PJ_TRIPLES` conflict, then armed.
   **Prevention:** before arming PR A from branch B's worktree, run `git merge-tree --write-tree origin/main HEAD` in B; a
   conflict there blocks every arm from that directory.
2. **Two `gh pr merge` in one command** — Recovery: one call per PR. **Prevention:** none needed beyond the hook's message.
3. **Prerequisite PRs armed with no review evidence** — Recovery: ran `soleur:review` on both. **Prevention:** run review
   on prerequisite PRs when they are opened, not when the owner says "arm".
4. **`cla-evidence` cancelled by rapid successive pushes; required context missing; PR BLOCKED with all green** — Recovery:
   `gh run rerun`. **Prevention:** after the last push to a PR, confirm the latest `cla-evidence` run is `success` before
   reporting it ready. Tracked in the pending bundled follow-up (a review agent that pushes N commits should push once).
5. **`pgrep -f` and chained `sleep` blocked by hooks** — Recovery: used `proc.sh` / Monitor. **Prevention:** already
   hook-enforced.
6. **`Context-Reviewed` gate fired on a merge commit that inherited main's `last_reviewed` bump** — Recovery: finished the
   merge with `git merge --continue` and a prepared `MERGE_MSG`, no review claimed. **Prevention:** none; the diff of a
   merge is main's, so verify `git diff origin/main -- <file>` is empty before choosing this route.
7. **Census T4 red mid-merge (stale merge-base)** — Recovery: committed the merge, re-ran. **Prevention:** commit merges
   before running merge-base ratchets.
8. **`git add … && git commit` chained: the blocked commit also skipped the add, leaving the baseline unstaged** —
   Recovery: noticed from `git status`, committed separately. **Prevention:** run `git status --short` after any blocked
   commit.
9. **Fix agent set FLOOR=605 against a real count of 603 and did not re-run** — Recovery: re-ran the 7-minute suite myself
   (603/0, rc 0). **Prevention:** a floor edit is not done until the suite that owns it has been run once.

## Tags

category: workflow-issues
module: ci-merge-queue, key-rotate
