# Tasks: Merge Conflict Targeted Fixes

**Issue:** #395
**Plan:** `knowledge-base/plans/2026-03-03-fix-merge-conflict-gaps-plan.md`

## Phase 1: Canonicalize merge strategy

### 1.1 Rename and update pre-merge hook
- [ ] Copy `.claude/hooks/pre-merge-rebase.sh` to `.claude/hooks/pre-merge-sync.sh`
- [ ] In `pre-merge-sync.sh`: replace `git rebase origin/main` with `git merge origin/main`
- [ ] In `pre-merge-sync.sh`: replace `git rebase --abort` with `git merge --abort`
- [ ] In `pre-merge-sync.sh`: replace `git push --force-with-lease --force-if-includes` with `git push`
- [ ] In `pre-merge-sync.sh`: update comments/messages referencing "rebase" to "merge/sync"
- [ ] Delete `.claude/hooks/pre-merge-rebase.sh`
- [ ] Update `.claude/settings.json` hook path from `pre-merge-rebase.sh` to `pre-merge-sync.sh`

### 1.2 Update documentation
- [ ] `AGENTS.md:14` — Change rebase rule to merge rule
- [ ] `knowledge-base/overview/constitution.md:107` — Change rebase to merge

## Phase 2: Conflict marker pre-commit hook

### 2.1 Add Guard 4 to guardrails.sh
- [ ] Add guard after Guard 3 (after line 73) matching `git commit` and `git merge --continue`
- [ ] Guard checks `git diff --cached | grep -qE '^\+(<{7}|={7}|>{7})'`
- [ ] Returns block JSON with message about conflict markers
- [ ] Redirect git diff stdout/stderr appropriately (TR5)

### 2.2 Cross-reference documentation
- [ ] `knowledge-base/overview/constitution.md:83` — Add "(enforced by guardrails.sh Guard 4)"

## Phase 3: Worktree refresh command

### 3.1 Implement refresh_worktree() function
- [ ] Add function to `worktree-manager.sh` before the main dispatch
- [ ] Guard: refuse on main/master
- [ ] Guard: refuse on dirty working tree
- [ ] Fetch origin/main
- [ ] Merge origin/main; on conflict run `git merge --abort` and report

### 3.2 Wire up dispatch and help
- [ ] Add `refresh` case to main dispatch (after cleanup-merged, before draft-pr)
- [ ] Add `refresh` entry to show_help()

## Phase 4: Pre-push sync in /ship

### 4.1 Add Phase 5.5 to ship SKILL.md
- [ ] Insert Phase 5.5 "Pre-Push Sync" between Phase 5 and Phase 6
- [ ] Fetch origin/main and check divergence
- [ ] If diverged: merge origin/main
- [ ] If conflicts: route by file pattern (CHANGELOG, README, else Claude-assisted)
- [ ] If low confidence or markers remain: `git merge --abort`, print structured summary, STOP
- [ ] If clean: commit merge, continue to Phase 6

### 4.2 Annotate Phase 6.5 as fallback
- [ ] Add note to Phase 6.5: "Safety net — Phase 5.5 handles the common case"

## Phase 5: Cleanup

### 5.1 Fix pre-existing stash reference
- [ ] `plugins/soleur/skills/merge-pr/SKILL.md` Phase 1.2 — Change "Commit or stash" to "Commit changes"

### 5.2 File pre-existing issue
- [ ] Create GitHub issue for merge-pr stash wording (pre-existing, surfaced by SpecFlow)

### 5.3 Commit and verify
- [ ] Run compound (skill: soleur:compound)
- [ ] Commit all changes
- [ ] Push and verify PR #414
