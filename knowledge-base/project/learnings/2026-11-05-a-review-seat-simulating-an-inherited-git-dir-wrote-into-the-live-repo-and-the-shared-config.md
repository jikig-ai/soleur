# Learning: a review seat that simulated an inherited `GIT_DIR` wrote into the live repo and the shared git config

## Problem

PR #12198 (#12120) fixed `.claude/hooks/cla-signed-author-gate.test.sh`: its setup helpers ran `git commit`
with no identity, and died on CI runners with no global git identity once T15/T16 had unset
`user.email`. The fix was a ~10-line `setup_commit` helper passing `GIT_AUTHOR_*`/`GIT_COMMITTER_*` via `env`.

During review, the architecture seat was asked about the inherited-`GIT_DIR` linked-worktree case. It tested
it by running the suite with `GIT_DIR` and `GIT_INDEX_FILE` pointed at the live worktree. The suite's
fixtures (`init_git_repo`, `make_repo`) then ran against the live repository: a stray `init` commit landed on
local `main`, the worktree `HEAD` was repointed to `main`, the index changed, and `user.name=Test User` /
`user.email=test@test.local` (and `commit.gpgsign=false`) were written into the shared bare repo's
`.git/config`. The seat reverted `main`, HEAD and the index and disclosed it. The leaked `user.*` stayed, which
would have made every later commit in the worktree author as `Test User` and fail the CLA gate.

## Solution

- Reverted `main` to its pre-leak SHA, re-attached the branch, reset the index (the seat).
- Removed the leaked identity with `git config --local --unset user.name/user.email` on the shared config,
  after confirming the effective identity was still the operator's global one.
- Verified: `git rev-parse HEAD` unchanged, `git status` clean, authorship of new commits back to the operator.

## Key Insight

"Report-only" and "scratch copy" briefs bound what a seat *edits*; they do not bound what a seat's
*experiment* writes. Simulating an inherited `GIT_DIR` is a request to point git at a real repository, and a suite
whose fixtures do not unset `GIT_DIR` will write there. The same suite is the reason: it never scrubs inherited git
location variables (pre-existing; the CTO deferred the fixture-env adoption as a follow-up).

## Session Errors

1. **Seat experiment wrote into the live repo and the shared `.git/config`** — Recovery: seat reverted main/HEAD/index, lead removed leaked `user.*`. **Prevention:** brief seats that any `GIT_DIR`/`GIT_INDEX_FILE`/`GIT_WORK_TREE` simulation must target a throwaway repo created under the seat's own sandbox, never a path under the live worktree or the shared git dir; verify `git rev-parse HEAD`, `main`'s reflog and `git config --local --list | grep ^user` after the panel returns.
2. **`decision-challenges.md` used an invalid Class (`mechanical`)** — Recovery: `technical-ruling-gate.sh` failed it; a CTO ruling made it a `technical` row. **Prevention:** none beyond the gate (it fired as designed).
3. **Affected-test gate returned `budget-deferred` (`ran=- of=-`)** — Recovery: ran the changed suite directly (26/26, with and without a global identity); CI is the authoritative gate. **Prevention:** read the runner's `--capacity` verdict first; a `ran=-` result is no verdict.
4. **CTO ruling ("file an issue") vs the deferral rule (document in place by default)** — Recovery: followed the rule; recorded the deferral in `decision-challenges.md`. **Prevention:** a ruling that prescribes a filing still passes through the filing gates; check the rule text before filing.
5. **Repo-wide `grep -rn G2e` timed out (120s)** — Recovery: re-scoped to tracked paths with `git grep`. **Prevention:** `git grep` over tracked paths, not `grep -r` across worktrees.

## Tags
category: workflow-issues
module: review, cla-signed-author-gate.test.sh
