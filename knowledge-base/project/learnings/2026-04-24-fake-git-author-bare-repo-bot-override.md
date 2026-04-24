# Learning: bare-repo CI-bot identity silently overrides worktree commits → `test@test` authorship

## Problem

In this repo, `core.bare=true` at the repository root, and the root-level git config frequently carries a CI-bot identity such as:

```text
user.email=41898282+github-actions[bot]@users.noreply.github.com
user.name=github-actions[bot]
```

This originates from GitHub Actions runs that ran `git config user.email …` at the repo level (not `--global`), or from `actions/checkout`'s default committer-injection side-effects. New worktrees created beneath the bare root **inherit the repo-level config**, which silently overrides the operator's `--global` identity. The operator never notices until a commit is made — at which point every commit inside the worktree is authored as the bot.

In PR #2815, this produced four commits authored as `test@test` (a placeholder identity the operator had momentarily set at the repo level to work around an "Author identity unknown" error). The CLA bot rejected the PR at ship time because `test@test` is not a signed email on any CLA. Recovery required:

1. Reset the worktree's local git identity to the operator's real identity.
2. `git commit --amend --reset-author` on the tip commit.
3. `git rebase -i` / cherry-pick to rewrite the earlier three commits with the correct author.
4. **Destructive force-push** (`git push --force-with-lease`) to replace the bot-authored commits on the remote branch.

The force-push is the blast-radius cost: any reviewer who had already fetched the branch was left with dangling commits, and any in-progress review comments anchored to those SHAs were invalidated.

## Solution

`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` gained `ensure_worktree_identity` (around line 181), called from both `create` and `cleanup-merged` paths (lines ~409 and ~473). The function:

1. Reads the operator's `--global` `user.email` and `user.name`.
2. If no global identity exists, returns silently — the operator is responsible for their own config.
3. Compares the global identity to the worktree's `--local` identity.
4. If they differ, writes the global identity onto the worktree's `--local` config, overriding whatever the bare repo inherited.

This makes the worktree self-correcting: every `create` and every `cleanup-merged` sweep re-asserts the operator's identity before any commit can land with the bot's email.

## Key Insight

**Bare repos change the blast radius of repo-level git config.** In a non-bare clone, setting `user.email` at the repo level only affects that clone; worktrees are already isolated. In a bare repo, the repo-level config is the parent config for every worktree and every transient scratch-clone inside `.worktrees/`. A `git config user.email test@test` run once in the bare root — for any reason, including a one-off CI experiment — poisons every worktree that gets created afterward.

The silent part is the killer: git does not warn when `--local` config overrides `--global` config. The first signal is either (a) the commit's `author` field in `git log`, which the operator usually doesn't inspect during normal work, or (b) a CLA bot rejection three PR minutes later.

**Never fake the git author to make a commit succeed.** `-c user.email=<fake> -c user.name=<fake>` on the `git commit` line bypasses the symptom (author identity unknown) without fixing the root cause (wrong repo-level config). The fake identity then propagates through the entire session, which is exactly the PR #2815 failure mode.

## Prevention

- **Never pass `-c user.email=<fake>` / `-c user.name=<fake>` to `git commit`.** Covered by AGENTS.md rule `hr-never-fake-git-author`.
- **If a commit rejects with "Author identity unknown", fix the worktree's local config:**

  ```bash
  git -C <worktree-path> config --local user.email "$(git config --global user.email)"
  git -C <worktree-path> config --local user.name "$(git config --global user.name)"
  ```

  This is exactly what `ensure_worktree_identity` does — it's the correct remediation, not a workaround.
- **When creating a worktree through any path other than `worktree-manager.sh create`,** re-run `ensure_worktree_identity` manually, or expect to inherit the bare-repo identity.
- **Never rewrite history to fix authorship on a branch that has already been pushed and reviewed.** If authorship is wrong on a pushed branch, the choice is: (a) live with it and document the mis-attribution, or (b) force-push and accept the reviewer blast radius. `ensure_worktree_identity` makes option (b) rare.

## Tags

category: bug-fixes
module: git-worktree
prs:
  - "2815"
