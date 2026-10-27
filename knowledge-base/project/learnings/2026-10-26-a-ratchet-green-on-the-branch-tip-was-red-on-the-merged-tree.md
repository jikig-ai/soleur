# Learning: a ratchet that was green on the branch tip was red on the merged tree (S4 PR4c)

## Problem

PR4c (#11131) drained 9 held-back affected-index edges. The ratchet exited 0 on the branch tip, and the audit showed `stale=0`. The review panel (security, data-integrity, code-quality, git-history, and my own scratch merge) then showed that on the tree that would actually merge, the ratchet exited 1 `stale-accept`: origin/main had rewritten `.claude/hooks/git-commit-secret-scan.sh` (#10893), three accept anchors (12-hex hashes of the mention line) no longer matched, and five new mention lines appeared. The same review found that one declared edge was unsound.

Main then moved a third time (#11124 appended 13 accept rows and 19 index lines) and the PR flipped to `CONFLICTING`.

## Solution

- Merge origin/main, then rebuild from main's copies: take main's accept file and add the PR's rows afresh (additions only), regenerate the baseline with `ratchet --print-baseline` (prune-only), and verify with `ratchet --base origin/main` plus `audit --accept` on the merged tree.
- Re-run the audit after every merge, even a clean one: a sibling that rewrites a file the accept rows point into invalidates anchors without producing a textual conflict.
- A conflict on the accept file after a sibling append is a plain union (no row is removed); check `0 removed` against origin/main.
- The unsound edge: `rung2 -> git-data-rung2-evidence-capture.sh` was declared because the script is the suite's SUT, but the script reaches `cloud-init-git-data.yml` only through a default that every suite arm overrides with `--cloud-init "$FIX/..."`. An accept row would have sat on a hot file (15 commits), so the whole edge was held (`real-read-unproven`).

## Key Insight

Branch-tip evidence is not merged-tree evidence for anything keyed to the content of lines in files other PRs touch. Anchor-keyed rows (accept file) are exactly that. The check that matters runs on `git merge-tree`/the real merge result, immediately before arming, and again after every sibling merge while queued. Separately: when a script is the SUT, "reads file X" is true only for the arms that do not override X's default; read the suite arms before declaring the edge.

## Session Errors

1. **Branch-tip ratchet green, merged-tree ratchet red (P1).** Recovery: merged main, rebuilt rows and baseline on the merged state. Prevention: ship Phase 5.1 order stays "merge origin/main, re-insert accept rows, regenerate baseline, verify on the merged tree"; the review's scratch-merge check (`merge-tree` then ratchet in a scratch worktree) belongs in the plan's verification list for any anchor-keyed artifact.
2. **Over-declared edge (SUT default always overridden).** Recovery: dropped the edge and its two reveal reads. Prevention: before declaring an edge for a SUT's default input, grep the suite arms for an override flag.
3. **Worktree vanished mid-run (second time in this series; cause unidentified).** Recovery: `git worktree prune`, re-add from the pushed branch, re-acquire lease. Prevention: push before every wait (done); evidence added to the existing tracker #11162 (see also #11099), not a new issue.
4. **Hook denied `git commit` because the path was a shell variable (`$W`).** Recovery: literal absolute `cd <path> && git commit -F file`. Prevention: never use `$VAR`/`$(...)` for the repo path in a commit command.
5. **Hook denied a Bash call whose awk text looked like a git commit target.** Recovery: Python script file. Prevention: put awk/regex text in a script file, not the Bash command line.
6. **`gh` run from a non-repo directory failed ("not a git repository").** Recovery: run from the worktree. Prevention: always run `gh` from inside the worktree.
7. **A 120 s Bash timeout on a cold `ratchet --print-baseline` (180 s cold).** Recovery: it moved to the background and a Monitor waited. Prevention: run the cold ratchet with `run_in_background` and a Monitor from the start.
8. **Issue #10959 and the #10861 comment carried first-cut numbers (9 edges, 5 reads, 25 rows, 1620).** Recovery: rewrote the status section, posted a correction comment. Prevention: write issue status text from the final receipts after the review fix round, not before it.
9. **Write tool refused to overwrite a file not read in this context.** Recovery: new filename. Prevention: use fresh scratch filenames per iteration.

## Tags

category: workflow-issues
module: ci-pr-affected-activation
