# Tasks: Merge Conflict Targeted Fixes

**Issue:** #395
**Plan:** `knowledge-base/project/plans/2026-03-03-fix-merge-conflict-gaps-plan.md`

[Updated 2026-03-03] Scope reduced from 4 fixes to 2 after plan review.

## Phase 1: Canonicalize merge strategy

### 1.1 Update pre-merge hook to use merge
- [x] Edit `.claude/hooks/pre-merge-rebase.sh` in place (no rename)
- [x] Replace `git rebase origin/main` with `git merge origin/main`
- [x] Replace `git rebase --abort` with `git merge --abort`
- [x] Replace `git push --force-with-lease --force-if-includes` with `git push origin HEAD`
- [x] Update file header comment to reflect merge strategy
- [x] Update any rebase-specific error messages

### 1.2 Update documentation
- [x] `AGENTS.md:14` — Change rebase rule to merge rule, remove vestigial "Never use interactive rebase" clause
- [x] `knowledge-base/overview/constitution.md:107` — Change rebase to merge

## Phase 2: Conflict marker pre-commit hook

### 2.1 Add Guard 4 to guardrails.sh
- [x] Add guard after Guard 3 (after line 73) matching `git commit` AND `git merge --continue`
- [x] Check `git diff --cached 2>/dev/null | grep -qE '^\+(<{7}|={7}|>{7})'`
- [x] Use correct JSON schema: `hookSpecificOutput.permissionDecision/permissionDecisionReason` (matching Guards 1-3)
- [x] Use `jq -n` for JSON output (matching existing guard patterns)

### 2.2 Cross-reference documentation
- [x] `knowledge-base/overview/constitution.md:83` — Add "(enforced by guardrails.sh Guard 4)"

## Phase 3: Cleanup

### 3.1 Fix pre-existing stash reference
- [x] `plugins/soleur/skills/merge-pr/SKILL.md` Phase 1.2 — Change "Commit or stash" to "Commit changes"

### 3.2 Commit and verify
- [x] Run compound (skill: soleur:compound)
- [x] Commit all changes
- [x] Push and verify PR #414
