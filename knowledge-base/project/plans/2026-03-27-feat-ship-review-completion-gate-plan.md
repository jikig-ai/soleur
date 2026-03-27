---
title: "fix: ship skill should enforce review gate even for hotfixes"
type: fix
date: 2026-03-27
deepened: 2026-03-27
updated: 2026-03-27
---

# fix: ship skill should enforce review gate even for hotfixes

[Updated 2026-03-27] Expanded scope from intra-skill gates to hook-level enforcement after brainstorm identified the real gap: `/ship` can be bypassed entirely.

## Overview

During the sign-in fix session, 4 PRs (#1213, #1214, #1219, #1220) were merged via raw `gh pr create` + `gh pr merge`, bypassing all skill-level review gates. PR #1219 shipped a TypeScript error that only CI caught. The `/ship` Phase 1.5 review gate (already implemented on this branch) only fires when `/ship` is invoked — it cannot catch direct `gh pr merge` bypass.

This plan adds:

1. **Guard 6** — a PreToolUse hook on `gh pr merge` that hard-denies merging without review evidence
2. **Hotfix label escape hatch** — bypass Guard 6 by adding a `hotfix` label to the PR
3. **Phase 5.5 consolidation** — remove the redundant review check (Phase 1.5 is the single gate)
4. **Hotfix protocol** — brief procedure in AGENTS.md

## Problem Statement

Three enforcement gaps exist (numbered from original plan):

1. ~~**Direct `/ship` invocation**~~ — Fixed: Phase 1.5 review gate (already on this branch)
2. ~~**Direct `/work` invocation**~~ — Fixed: Work Phase 4 now chains review before compound/ship (already on this branch)
3. **Direct `gh pr merge` bypass** — **NEW FIX:** Nothing prevents an agent from running `gh pr create` + `gh pr merge` without ever invoking `/ship`. This is the gap that caused the incident.

Additionally:

4. **Phase 1.5/5.5 inconsistency** — Phase 1.5 aborts in headless; Phase 5.5 auto-invokes review in headless. Different detection methods (exact commit message vs loose grep). Should be consolidated.

## Proposed Solution

### Guard 6: Review Evidence Gate on `gh pr merge`

Add Guard 6 to `.claude/hooks/guardrails.sh` that intercepts all `gh pr merge` commands and checks for review evidence before allowing the merge.

**Detection flow:**

1. Match `gh pr merge` in the command (same chain-operator pattern as Guards 1-5)
2. Resolve the working directory (`.cwd` from hook input, same as pre-merge-rebase.sh)
3. Check for review evidence locally:
   - `grep -rl "code-review" todos/ 2>/dev/null | head -1` (todo files tagged code-review)
   - `git log origin/main..HEAD --oneline | grep "refactor: add code review findings"` (review commit)
4. If evidence found → allow (exit 0)
5. If no evidence → extract PR number and check for `hotfix` label:
   - Extract PR number from command (`gh pr merge 123 ...`) or resolve from current branch (`gh pr view --json number`)
   - `gh pr view <N> --json labels --jq '.labels[].name'` → check for `hotfix`
6. If `hotfix` label present → allow with warning (additionalContext)
7. If no evidence AND no hotfix label → deny

**Deny message:**

```
BLOCKED: No review evidence found on this branch. Run /review before merging.
To bypass for hotfixes: gh pr edit <N> --add-label hotfix
See AGENTS.md hotfix protocol.
```

**Edge cases:**

- PR number not extractable (ambiguous command) → fail open with warning (don't block on hook parsing failure)
- Network failure on `gh pr view` → fail open with warning (same pattern as pre-merge-rebase.sh)
- Branch has no commits beyond main → skip check (nothing to review)

### Remove Phase 5.5 Code Review Completion Gate

Delete the "Code Review Completion Gate (mandatory)" subsection from Phase 5.5 in ship SKILL.md (lines 221-242). Keep the other Phase 5.5 gates (CMO Content-Opportunity, CMO Website Framing Review, COO Expense-Tracking) intact.

**Why remove:** Phase 1.5 already handles this check earlier and more correctly. Phase 5.5's review gate had inconsistent behavior:

- Headless: auto-invoked review (Phase 1.5 correctly aborts instead)
- Detection: loose grep `--grep="review"` (Phase 1.5 uses exact commit message match)
- Position: too late (after compound, tests, documentation — wasted work if review finds blockers)

### Hotfix Protocol in AGENTS.md

Add to the Hard Rules section, after the existing hook awareness line:

```markdown
- Hotfix protocol [hook-enforced: guardrails.sh Guard 6]: (1) `gh pr edit <N> --add-label hotfix`, (2) merge normally, (3) follow-up review within 24h (create a GitHub issue to track). The `hotfix` label is the only escape hatch for Guard 6 — it is auditable in PR history.
```

### Update AGENTS.md Hook Awareness

Update the PreToolUse hooks list to include Guard 6:

```markdown
- PreToolUse hooks block: commits on main, rm -rf on worktrees, --delete-branch with active worktrees, writes to main repo when worktrees exist, commits with conflict markers in staged content, gh issue create without --milestone, gh pr merge without review evidence (bypass: hotfix label). Work with these guards, not around them.
```

## Technical Approach

### Files to Modify

| File | Change | Status |
|------|--------|--------|
| `plugins/soleur/skills/ship/SKILL.md` | Add Phase 1.5 review gate | Done |
| `plugins/soleur/skills/work/SKILL.md` | Update Phase 4 direct-invocation chain | Done |
| `.claude/hooks/guardrails.sh` | Add Guard 6 (review evidence on `gh pr merge`) | **TODO** |
| `plugins/soleur/skills/ship/SKILL.md` | Remove Phase 5.5 Code Review Completion Gate subsection | **TODO** |
| `AGENTS.md` | Add hotfix protocol, update hook awareness line | **TODO** |

### Guard 6 Implementation Detail

Insert after Guard 5 (line 128), before the `# All checks passed` comment.

**PR number extraction logic:**

```bash
# Extract explicit PR number: gh pr merge 123 ...
PR_NUM=$(echo "$COMMAND" | grep -oE 'gh\s+pr\s+merge\s+([0-9]+)' | grep -oE '[0-9]+')

# If no explicit number, resolve from current branch
if [[ -z "$PR_NUM" ]]; then
  PR_NUM=$(gh pr view --json number --jq .number 2>/dev/null || echo "")
fi
```

**Review evidence check (same logic as Phase 1.5):**

```bash
# Check for review todo files
REVIEW_TODOS=$(grep -rl "code-review" "$WORK_DIR/todos/" 2>/dev/null | head -1 || true)

# Check for review commit
REVIEW_COMMIT=$(git -C "$WORK_DIR" log origin/main..HEAD --oneline 2>/dev/null | grep "refactor: add code review findings" || true)
```

**Hotfix label check (only if no review evidence):**

```bash
HOTFIX_LABEL=$(gh pr view "$PR_NUM" --json labels --jq '.labels[].name' 2>/dev/null | grep -x "hotfix" || true)
```

**Full Guard 6 pattern follows Guards 1-5 style:** early-exit regex match, resolve context, check conditions, emit deny JSON or exit 0.

### Phase 5.5 Removal Detail

In `plugins/soleur/skills/ship/SKILL.md`, delete lines 221-242 (the "Code Review Completion Gate (mandatory)" subsection). The Phase 5.5 heading and its other subsections (CMO Content-Opportunity Gate, CMO Website Framing Review Gate, COO Expense-Tracking Gate) remain unchanged. Also remove the `- [ ] Code review completed (Phase 5.5 gate)` checklist item from Phase 5 (line 214).

## Acceptance Criteria

### Already Implemented (from original plan)

- [x] `/ship` Phase 1.5 detects `todos/` files tagged `code-review` as review evidence
- [x] `/ship` Phase 1.5 detects `refactor: add code review findings` commit message as review evidence
- [x] `/ship` in headless mode aborts when no review evidence is found
- [x] `/ship` in interactive mode presents Run/Skip/Abort options when no review evidence is found
- [x] `/work` Phase 4 direct-invocation path includes review and resolve-todo-parallel before compound and ship
- [x] One-shot pipeline continues to work unchanged

### New (from brainstorm #1227)

- [ ] Guard 6 denies `gh pr merge` when no review evidence exists on the branch
- [ ] Guard 6 allows merge when `hotfix` label is present on the PR
- [ ] Guard 6 deny message includes bypass instructions (`gh pr edit <N> --add-label hotfix`)
- [ ] Guard 6 fails open on network errors and unparseable PR numbers
- [ ] Phase 5.5 Code Review Completion Gate removed (Phase 1.5 is the single gate)
- [ ] Phase 5 checklist updated (no Phase 5.5 code review reference)
- [ ] AGENTS.md hotfix protocol added with `[hook-enforced: guardrails.sh Guard 6]` annotation
- [ ] AGENTS.md hook awareness line updated to include Guard 6

## Test Scenarios

### Guard 6 Tests

- Given `gh pr merge 42 --squash --auto` with no review evidence and no hotfix label → deny with bypass instructions
- Given `gh pr merge --squash --auto` (no explicit PR number) with no review evidence → resolve PR from branch, deny
- Given `gh pr merge 42` with review todos in `todos/` tagged `code-review` → allow silently
- Given `gh pr merge 42` with `refactor: add code review findings` commit → allow silently
- Given `gh pr merge 42` with no review evidence but `hotfix` label on PR → allow with warning
- Given `gh pr merge 42` with `gh pr view` failing (network error) → fail open with warning
- Given a command that doesn't contain `gh pr merge` → skip check entirely

### Phase 5.5 Removal Tests

- Given `/ship` runs after Phase 1.5 passes, Phase 5.5 no longer re-checks review evidence
- Given `/ship` runs in headless mode, Phase 5.5 no longer auto-invokes review (Phase 1.5 handles this)
- Given `/ship` Phase 5 checklist, the "Code review completed (Phase 5.5 gate)" item is absent

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Carry-forward from brainstorm. CTO identified that the real interception point is `gh pr merge`, not `git push` or `/ship` internals. The hook follows the proven PreToolUse pattern (Guards 1-5, pre-merge-rebase.sh). User chose hard deny + hotfix label escape hatch over warning-only. Risk is low — Guard 6 fails open on infrastructure errors (network, unparseable commands), consistent with pre-merge-rebase.sh design.

## References

- Issue: #1227
- Brainstorm: `knowledge-base/project/brainstorms/2026-03-27-ship-review-gate-brainstorm.md`
- Original issue: #1170 (intra-skill gates, now complete)
- Learning: `knowledge-base/project/learnings/2026-03-19-ci-squash-fallback-bypasses-merge-gates.md` (fail-closed pattern)
- Learning: `knowledge-base/project/learnings/2026-02-24-guardrails-chained-commit-bypass.md` (chain operator matching)
- Learning: `knowledge-base/project/learnings/2026-03-19-skill-enforced-convention-pattern.md` (enforcement tiers)
- Learning: `knowledge-base/project/learnings/2026-03-03-headless-mode-skill-bypass-convention.md` (headless forwarding)
- Guardrails: `.claude/hooks/guardrails.sh` (Guards 1-5 pattern)
- Pre-merge hook: `.claude/hooks/pre-merge-rebase.sh` (`gh pr merge` interception pattern)
- Ship SKILL.md: `plugins/soleur/skills/ship/SKILL.md` (Phase 1.5 at line 72, Phase 5.5 at line 221)
