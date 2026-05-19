---
title: worktree-manager.sh feature silently announces success when git worktree add partially fails — needs positive registration check
date: 2026-05-18
category: workflow-issues
tags:
  - worktree-manager
  - silent-failure
  - git-worktree
  - tooling-bug
  - session-start
  - brainstorm-skill
related:
  - "#3947 (PR-G — surfaced during brainstorm)"
  - 2026-04-21-concurrent-cleanup-merged-wipes-active-worktree
---

# Problem

Running `SOLEUR_SKILL_NAME=brainstorm ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh feature pr-g-cohort-onboarding` printed `Feature setup complete!` and offered next-step hints, but the worktree was not registered with git: `git worktree list` did not show it, the `.git/worktrees/feat-pr-g-cohort-onboarding/` admin directory did not exist, and the worktree contained no source files past the spec directory the script created itself (`apps/web-platform/` was ENOENT). The downstream `worktree-manager.sh draft-pr` invocation then crashed with `fatal: not a git repository: /home/jean/git-repositories/jikig-ai/soleur/.git/worktrees/feat-pr-g-cohort-onboarding`.

The script's stdout contained a partial signal — `SOLEUR_FEATURE_PUSH_FAILED branch=feat-pr-g-cohort-onboarding` plus a buried bun error about `apps/web-platform/: ENOENT` — but the **prominent banner** was `Feature setup complete!` (green) and the **default next-step hint** was `cd .worktrees/feat-pr-g-cohort-onboarding`. An operator following the success banner is sent into a directory that looks like a worktree (it has a `.git` gitlink file) but is functionally a dead drop.

# Symptoms

- `git worktree list` does not include the new branch despite `Feature setup complete!`.
- `cd .worktrees/feat-<name>` succeeds but `git status` (or any git operation) fails with `fatal: not a git repository`.
- The `.git` gitlink file in the worktree points to `<bare>/.git/worktrees/feat-<name>` but that target directory does not exist.
- Spec directory `knowledge-base/project/specs/feat-<name>/` was created (the script makes this BEFORE the `git worktree add` step or in a separate code path).
- The worktree contains the `.env` symlink but no source tree (`apps/`, `plugins/`, etc. are missing).
- Buried in the script output: a `SOLEUR_FEATURE_PUSH_FAILED branch=<name>` marker and a `bun install` ENOENT error.

# Root Cause

The script's success/failure detection is **negative-only**: it checks for `git push -u` failure (line 608: `if ! git -C "$worktree_path" push -u origin "$branch_name" ...`) but does NOT positively verify that the `git worktree add` call actually registered the worktree in `git worktree list`. When `git worktree add` (line 565) succeeds in writing the worktree directory tree but fails to populate the `.git/worktrees/<name>/` admin directory (the cause of which is environment-specific — possibly a stale prior worktree state, a permissions issue, or a `cleanup-merged` interaction), the script proceeds to dependency installs, push attempt, and the final banner without detecting the inconsistency.

The push-failure detection IS in place, but `SOLEUR_FEATURE_PUSH_FAILED` is treated as a non-fatal warning (the script continues to print the success banner). When `git worktree add` is broken AND push fails (always together because there's nothing committable in a non-functional worktree), the operator sees the push-failure marker as an isolated networking warning, not as evidence the entire feature setup is broken.

# Solution (proposed; not applied in this session)

Add a positive-registration check after `git worktree add`:

```bash
# After: git worktree add $track_flag -b "$branch_name" "$worktree_path" "$base_ref"

# Positive registration check — `git worktree add` can succeed enough to
# create the directory but fail to register the admin entry. The only
# reliable signal is the registration itself.
if ! git -C "$REPO_ROOT" worktree list --porcelain | grep -q "^branch refs/heads/${branch_name}$"; then
  echo -e "${RED}✗ git worktree add did not register branch ${branch_name}. Aborting.${NC}" >&2
  echo -e "${YELLOW}Hint: rm -rf '${worktree_path}' && git worktree prune && retry${NC}" >&2
  exit 2
fi
```

Add a similar check before printing `Feature setup complete!`:

```bash
# Final guard — re-verify registration before the success banner.
if ! git -C "$REPO_ROOT" worktree list --porcelain | grep -q "^branch refs/heads/${branch_name}$"; then
  echo -e "${RED}✗ feature setup failed (worktree not registered)${NC}" >&2
  exit 2
fi
echo ""
echo -e "${GREEN}Feature setup complete!${NC}"
```

Also: treat `SOLEUR_FEATURE_PUSH_FAILED` as **at least** WARNING-level in the final banner. Today it is emitted via `headless_or_stderr warn` which an operator scanning green text easily misses. Move the warning into a yellow-highlighted summary block printed AFTER the next-step hints.

# Prevention

- Add positive-registration check as above. A negative-only failure-detection model is unsafe for any step that has multiple failure modes including silent ones.
- Per AGENTS.md `hr-when-a-command-exits-non-zero-or-prints`: a command that prints failure markers should be treated as failed, regardless of exit code. The script today prints the marker but continues — this rule applies to the script's own logic, not just to the operator.

# Workaround (used in this session)

```bash
# 1. Clean up the dead worktree
rm -rf .worktrees/feat-<name>
git branch -D feat-<name>
git worktree prune

# 2. Recreate via direct git command
git worktree add .worktrees/feat-<name> -b feat-<name> main

# 3. Push immediately to avoid the cleanup-merged race
cd .worktrees/feat-<name>
git commit --allow-empty -m "chore: start brainstorm feat-<name>"
git push -u origin feat-<name>

# 4. Open draft PR manually
gh pr create --draft --title "..." --body "..."
```

# Session Errors

This learning IS the session error.

# References

- Script: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (line 565 = `git worktree add` call; line 608 = push-failure check; line 621 = success banner)
- Related learning: `knowledge-base/project/learnings/2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md` (the race-window pattern that motivated the existing push-failure detection)
- Rule: AGENTS.md `hr-when-a-command-exits-non-zero-or-prints`
- Brainstorm where surfaced: `knowledge-base/project/brainstorms/2026-05-18-pr-g-cohort-onboarding-brainstorm.md`
