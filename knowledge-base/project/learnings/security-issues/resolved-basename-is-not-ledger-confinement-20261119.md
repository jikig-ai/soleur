---
module: retry-budget-ruling
date: 2026-11-19
problem_type: security_issue
component: tooling
symptoms:
  - "A ledger whose parent is a same-basename directory symlink still appends"
  - "O_NOFOLLOW on the leaf follows every directory component above it"
  - "A child-session path ending in slash or /. hides a symlink from test -L"
root_cause: missing_validation
resolution_type: code_fix
severity: high
status: open
tags: [path-confinement, symlink, o-nofollow, retry-budget]
---

# Troubleshooting: Resolved basename is not ledger confinement

## Problem

The retry-budget ledger refused a path whose resolved directory name was not the branch. An in-tree directory symlink whose target still ended in that branch name passed the check, and the append followed the link. `O_NOFOLLOW` on the leaf open does not apply to earlier components.

## Environment

- Module: `plugins/soleur/scripts/retry-budget-ruling.sh`
- Affected Component: ledger open and `--child-session` confinement
- Date: 2026-11-19
- Issue: #12526
- PR: #12815

## Symptoms

- `goto plan` against a same-basename parent symlink exited 0 and wrote the other tree's `session-state.md`.
- An ancestor directory symlink under the git toplevel did the same when the resolved parent was still named the branch.
- `--child-session` ending in `/` or `/.` passed `[[ -L ]]` because the trailing slash made the test see the directory through the link.

## What Didn't Work

**Attempted Solution 1:** Compare `realpath` of the parent to the branch name.

- **Why it failed:** `realpath` follows the symlink. The resolved name can still equal the branch, so the check agrees with the alias it was meant to refuse.

**Attempted Solution 2:** `os.open` of the full path with `O_NOFOLLOW` on the leaf.

- **Why it failed:** `O_NOFOLLOW` applies to the final component only. Every directory above the leaf is followed.

## Session Errors

**`gh pr view 12526` treated the issue number as a pull request.**

- **Recovery:** Used PR #12815.
- **Prevention:** Open the PR from the branch head, not from the issue number.

**Session-start hook exceeded the 30s tool wait and then exited 0.**

- **Recovery:** Continued after the late exit 0.
- **Prevention:** A slow clean exit is not a failed start. Do not re-run it as if it had failed.

**`CLAUDE_PLUGIN_ROOT` was empty in a fresh shell.**

- **Recovery:** Exported the worktree plugin root before plugin scripts.
- **Prevention:** Set the root in every fresh shell. The worktree does not inherit it.

**The binding CTO spawn outlived the foreground wait and then exited 0.**

- **Recovery:** Read the completed result. Did not spawn a third time.
- **Prevention:** A wait timeout is not a failed ruling. Resume or read the result. The two-spawn cap stays spent.

**Git commands in the bare checkout exited 128.**

- **Recovery:** Literal `cd` into the feature worktree.
- **Prevention:** A `$WT` variable is not a worktree check. The path in the command must be literal.

**The first review commit was refused because `cd` used a shell variable.**

- **Recovery:** Retried with a literal worktree path. That commit is `50bcd4d141`.
- **Prevention:** `precommit-guard.sh` judges the command text. A variable hides the directory.

**`lint-shell-capture-exit.py` was invoked under `plugins/soleur/scripts/`.**

- **Recovery:** Re-ran `scripts/lint-shell-capture-exit.py` with the repo baseline. 0 new findings.
- **Prevention:** The linter lives at the repo `scripts/` root, not under the plugin scripts directory.

**The main-panel `Reviewed-By-Soleur` trailer was never emitted.**

- **Recovery:** Emitted only `Reviewed-Fix-Round` for `69169594b3..a205b43d34`. The PR comment does not say `coverage=full`.
- **Prevention:** Emit the branch trailer when the main panel returns. A fix-round attestation never writes `Reviewed-Coverage`.

## Solution

Walk from the git toplevel. Refuse a symlink component before any append. In Python, open the toplevel, then each relative directory with `O_DIRECTORY|O_NOFOLLOW` and `dir_fd`, then the leaf from that directory fd. A symlink component is `reason=identity` (exit 5), not `reason=write-failed`. In bash, strip a trailing slash and a final `/.` before `[[ -L ]]`, and use that walk for the ledger parent and for `--child-session`.

```bash
# Before: resolved name can still be the branch.
real_base=$(basename "$(realpath -e "$parent")")
[[ "$real_base" == "$branch" ]] || emit fail identity

# After: a symlink anywhere from the toplevel through the parent is identity.
path_has_symlink "$top" "$parent" && emit fail identity
```

The same-basename link, the ancestor link, and `--child-session` values `link/` and `link/.` exit 2 with `verb=fail reason=identity` and leave the other file's digest unchanged. Commit `a205b43d34`.

## Why This Works

The check that failed compared a name after the kernel had already followed the link. Opening each directory from the previous file descriptor, with `O_NOFOLLOW`, refuses the link at the component that is a link. Starting at the git toplevel leaves a symlink above that toplevel alone, so a symlink on `/tmp` does not refuse an ordinary ledger. The bash walk is the early exit. The Python walk is the open that cannot follow what the early exit missed.

## Prevention

- A confinement check on a resolved basename does not see an alias whose target has the same final name.
- `O_NOFOLLOW` on a full-path open covers the leaf only. Cover the parents with a directory-fd walk.
- `[[ -L path/ ]]` does not see a symlink directory. Strip trailing slashes and a final `/.` before the test.
- Pin the identity line and the other file's digest. A sibling digest alone does not lock the verdict.

## Related Issues

- Sibling shape, different tool: [2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself.md](../best-practices/2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself.md) (an intermediate-directory symlink was untested on a hash registry).
- Plan and rulings stay in `knowledge-base/project/plans/2026-11-16-feat-retry-budget-ruling-plan.md` and `knowledge-base/project/specs/feat-12526-retry-budget-arbitration/decision-challenges.md`.
