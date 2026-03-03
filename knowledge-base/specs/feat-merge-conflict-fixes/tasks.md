# Tasks: Merge Conflict Targeted Fixes

**Issue:** #395
**Plan:** `knowledge-base/plans/2026-03-03-fix-merge-conflict-gaps-plan.md`

[Updated 2026-03-03] Scope reduced from 4 fixes to 2 after plan review.

## Phase 1: Canonicalize merge strategy

### 1.1 Update pre-merge hook to use merge
- [ ] Edit `.claude/hooks/pre-merge-rebase.sh` in place (no rename)
- [ ] Replace `git rebase origin/main` with `git merge origin/main`
- [ ] Replace `git rebase --abort` with `git merge --abort`
- [ ] Replace `git push --force-with-lease --force-if-includes` with `git push origin HEAD`
- [ ] Update file header comment to reflect merge strategy
- [ ] Update any rebase-specific error messages

### 1.2 Update documentation
- [ ] `AGENTS.md:14` — Change rebase rule to merge rule, remove vestigial "Never use interactive rebase" clause
- [ ] `knowledge-base/overview/constitution.md:107` — Change rebase to merge

## Phase 2: Conflict marker pre-commit hook

### 2.1 Add Guard 4 to guardrails.sh
- [ ] Add guard after Guard 3 (after line 73) matching `git commit` AND `git merge --continue`
- [ ] Check `git diff --cached 2>/dev/null | grep -qE '^\+(<{7}|={7}|>{7})'`
- [ ] Use correct JSON schema: `hookSpecificOutput.permissionDecision/permissionDecisionReason` (matching Guards 1-3)
- [ ] Use `jq -n` for JSON output (matching existing guard patterns)

### 2.2 Cross-reference documentation
- [ ] `knowledge-base/overview/constitution.md:83` — Add "(enforced by guardrails.sh Guard 4)"

## Phase 3: Cleanup

### 3.1 Fix pre-existing stash reference
- [ ] `plugins/soleur/skills/merge-pr/SKILL.md` Phase 1.2 — Change "Commit or stash" to "Commit changes"

### 3.2 Commit and verify
- [ ] Run compound (skill: soleur:compound)
- [ ] Commit all changes
- [ ] Push and verify PR #414
