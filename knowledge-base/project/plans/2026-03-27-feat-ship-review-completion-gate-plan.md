---
title: "fix: ship skill should enforce review gate even for hotfixes"
type: fix
date: 2026-03-27
deepened: 2026-03-27
updated: 2026-03-27
---

# fix: ship skill should enforce review gate even for hotfixes

[Updated 2026-03-27] Expanded scope from intra-skill gates to hook-level enforcement. Simplified after plan review: dropped hotfix escape hatch (YAGNI), moved guard into pre-merge-rebase.sh (eliminates ordering dependency).

## Overview

During the sign-in fix session, 4 PRs (#1213, #1214, #1219, #1220) were merged via raw `gh pr create` + `gh pr merge`, bypassing all skill-level review gates. PR #1219 shipped a TypeScript error that only CI caught. The `/ship` Phase 1.5 review gate (already implemented on this branch) only fires when `/ship` is invoked — it cannot catch direct `gh pr merge` bypass.

This plan adds:

1. **Review evidence gate** — an early-exit check in `pre-merge-rebase.sh` that hard-denies `gh pr merge` without review evidence
2. **Phase 5.5 consolidation** — remove the redundant review check (Phase 1.5 is the single gate; Phase 5.5 auto-invoked review in headless mode, which is wrong behavior — not just redundant)
3. **AGENTS.md updates** — hook awareness line and guardrails header

## Problem Statement

Three enforcement gaps exist (numbered from original plan):

1. ~~**Direct `/ship` invocation**~~ — Fixed: Phase 1.5 review gate (already on this branch)
2. ~~**Direct `/work` invocation**~~ — Fixed: Work Phase 4 now chains review before compound/ship (already on this branch)
3. **Direct `gh pr merge` bypass** — **NEW FIX:** Nothing prevents an agent from running `gh pr create` + `gh pr merge` without ever invoking `/ship`. This is the gap that caused the incident.

Additionally:

4. **Phase 1.5/5.5 inconsistency** — Phase 1.5 aborts in headless; Phase 5.5 auto-invokes review in headless. Different detection methods (exact commit message vs loose grep). Phase 5.5's auto-invoke is wrong behavior: it silently adds a full code review to the ship pipeline as a hidden side effect, rather than forcing the caller to make an explicit decision.

## Proposed Solution

### Review Evidence Gate in pre-merge-rebase.sh

Add a review evidence check as an early-exit block at the top of `.claude/hooks/pre-merge-rebase.sh`, before the existing fetch/merge/push logic. This co-locates the guard with the side-effecting logic it should gate, eliminating any hook execution order dependency.

**Detection flow (purely local, zero network calls):**

1. `pre-merge-rebase.sh` already matches `gh pr merge` — reuse existing match
2. Resolve working directory from `.cwd` (already done by existing hook)
3. Check for review evidence locally:
   - `grep -rl "code-review" "$WORK_DIR/todos/" 2>/dev/null | head -1` (todo files tagged code-review)
   - `git -C "$WORK_DIR" log origin/main..HEAD --oneline | grep "refactor: add code review findings"` (review commit)
4. If either check finds evidence → continue to existing fetch/merge/push logic
5. If no evidence → deny

**Deny message:**

```
BLOCKED: No review evidence found on this branch. Run /review before merging.
```

**No escape hatch.** If a genuine hotfix need arises, the agent runs `/review` first (even a quick self-review produces evidence). If the need for a bypass becomes real, add it then. YAGNI.

**Note on coupling:** The commit message grep (`"refactor: add code review findings"`) is coupled to review SKILL.md Step 5. This is the same coupling that exists in ship Phase 1.5, documented with a comment in both locations. The coupling is minimal (one string literal) and intentionally documented rather than abstracted.

### Remove Phase 5.5 Code Review Completion Gate

Delete the "Code Review Completion Gate (mandatory)" subsection from Phase 5.5 in ship SKILL.md. Keep the other Phase 5.5 subsections (CMO Content-Opportunity, CMO Website Framing Review, COO Expense-Tracking) intact. Also remove the `- [ ] Code review completed (Phase 5.5 gate)` checklist item from Phase 5.

**Why remove (strengthened per DHH review):** Phase 5.5's code review gate auto-invokes review in headless mode. This is *wrong behavior*, not just redundancy — it silently adds a full code review to the ship pipeline as a hidden side effect that changes runtime characteristics. Phase 1.5 correctly aborts instead, forcing the caller to make an explicit decision. Additionally:

- Detection: loose `--grep="review"` (Phase 1.5 uses exact commit message match)
- Position: too late (after compound, tests, documentation — wasted work if review finds blockers)

Locate the subsection by its heading text ("Code Review Completion Gate (mandatory)"), not line numbers.

### Update AGENTS.md

**Hook awareness line** — update to include the review evidence gate:

```markdown
- PreToolUse hooks block: commits on main, rm -rf on worktrees, --delete-branch with active worktrees, writes to main repo when worktrees exist, commits with conflict markers in staged content, gh issue create without --milestone, gh pr merge without review evidence. Work with these guards, not around them.
```

**Guardrails header comment** — update `pre-merge-rebase.sh` file header to document the review evidence gate alongside the existing rebase description.

## Technical Approach

### Files to Modify

| File | Change | Status |
|------|--------|--------|
| `plugins/soleur/skills/ship/SKILL.md` | Add Phase 1.5 review gate | Done |
| `plugins/soleur/skills/work/SKILL.md` | Update Phase 4 direct-invocation chain | Done |
| `.claude/hooks/pre-merge-rebase.sh` | Add review evidence early-exit check before fetch/merge/push | **TODO** |
| `plugins/soleur/skills/ship/SKILL.md` | Remove Phase 5.5 Code Review Completion Gate subsection | **TODO** |
| `AGENTS.md` | Update hook awareness line | **TODO** |

### Review Evidence Gate Implementation Detail

Insert after the existing early exits in `pre-merge-rebase.sh` (skip if on main, skip if detached HEAD), before the uncommitted changes check. The hook already resolves `$WORK_DIR` from `.cwd` and `$CURRENT_BRANCH`.

```bash
# Review evidence gate: block gh pr merge without review evidence.
# Check for review todo files tagged code-review
REVIEW_TODOS=$(grep -rl "code-review" "$WORK_DIR/todos/" 2>/dev/null | head -1 || true)

# Check for review commit (coupled to review SKILL.md Step 5 commit message)
REVIEW_COMMIT=$(git -C "$WORK_DIR" log origin/main..HEAD --oneline 2>/dev/null \
  | grep "refactor: add code review findings" || true)

if [[ -z "$REVIEW_TODOS" ]] && [[ -z "$REVIEW_COMMIT" ]]; then
  jq -n '{
    hookSpecificOutput: {
      permissionDecision: "deny",
      permissionDecisionReason: "BLOCKED: No review evidence found on this branch. Run /review before merging."
    }
  }'
  exit 0
fi
```

**Why `-C "$WORK_DIR"` on git log:** The hook's CWD may differ from the worktree. Using `-C` ensures the git log checks the correct repository, consistent with how the existing hook resolves branch and diff state.

**Why `(\s|$)` word boundary:** The existing `gh pr merge` regex in `pre-merge-rebase.sh` already uses `(\s|$)` to prevent false positives on hypothetical `gh pr merge-*` subcommands. The review evidence check runs inside the same match block — no new regex needed.

### Phase 5.5 Removal Detail

In `plugins/soleur/skills/ship/SKILL.md`, locate the "Code Review Completion Gate (mandatory)" subsection by heading text (not line numbers — they shift with prior edits). Delete from `### Code Review Completion Gate (mandatory)` through the `**Why:**` paragraph, stopping before `### Pre-Ship Domain Review (conditional)`. Also locate the Phase 5 checklist and remove the `Code review completed (Phase 5.5 gate)` item.

Verify that the AGENTS.md Phase 5.5 description ("Phase 5.5 runs three conditional domain leader gates in parallel") still matches the post-removal SKILL.md structure. It should — the description already references only the three conditional gates.

## Acceptance Criteria

### Already Implemented (from original plan)

- [x] `/ship` Phase 1.5 detects `todos/` files tagged `code-review` as review evidence
- [x] `/ship` Phase 1.5 detects `refactor: add code review findings` commit message as review evidence
- [x] `/ship` in headless mode aborts when no review evidence is found
- [x] `/ship` in interactive mode presents Run/Skip/Abort options when no review evidence is found
- [x] `/work` Phase 4 direct-invocation path includes review and resolve-todo-parallel before compound and ship
- [x] One-shot pipeline continues to work unchanged

### New (from brainstorm #1227, simplified after plan review)

- [ ] `pre-merge-rebase.sh` denies `gh pr merge` when no review evidence exists on the branch
- [ ] `pre-merge-rebase.sh` allows merge when review evidence is found (todo files or commit)
- [ ] Review evidence check uses `-C "$WORK_DIR"` consistently for both grep and git log
- [ ] Phase 5.5 Code Review Completion Gate subsection removed (Phase 1.5 is the single gate)
- [ ] Phase 5 checklist updated (no Phase 5.5 code review reference)
- [ ] AGENTS.md hook awareness line updated to include review evidence gate

## Test Scenarios

### Review Evidence Gate Tests

- Given `gh pr merge 42 --squash --auto` with no review evidence → deny
- Given `gh pr merge 42` with review todos in `todos/` tagged `code-review` → allow, continue to fetch/merge/push
- Given `gh pr merge 42` with `refactor: add code review findings` commit → allow, continue to fetch/merge/push
- Given a command that doesn't contain `gh pr merge` → skip check entirely (existing behavior)
- Given `--auto` flag on the merge command → guard fires at invocation time (before command executes), `--auto` does not change behavior

### Hook Interaction Tests

- Given Guard 6 denies in pre-merge-rebase.sh → fetch/merge/push logic does NOT execute (no branch pollution)
- Given Guard 6 allows → existing pre-merge-rebase logic runs normally (fetch origin/main, merge, push)

### Phase 5.5 Removal Tests

- Given `/ship` runs after Phase 1.5 passes, Phase 5.5 no longer re-checks review evidence
- Given `/ship` runs in headless mode, Phase 5.5 no longer auto-invokes review (Phase 1.5 handles this)
- Given `/ship` Phase 5 checklist, the "Code review completed" item is absent

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Carry-forward from brainstorm, updated after plan review. CTO identified `gh pr merge` as the real interception point. Three plan reviewers recommended: (1) drop hotfix escape hatch (YAGNI — eliminates all network calls), (2) move guard into pre-merge-rebase.sh (eliminates hook ordering dependency), (3) strengthen Phase 5.5 removal rationale (auto-invoke is wrong behavior, not just redundant). All three accepted.

## References

- Issue: #1227
- Brainstorm: `knowledge-base/project/brainstorms/2026-03-27-ship-review-gate-brainstorm.md`
- Original issue: #1170 (intra-skill gates, now complete)
- Learning: `knowledge-base/project/learnings/2026-03-19-ci-squash-fallback-bypasses-merge-gates.md` (fail-closed pattern)
- Learning: `knowledge-base/project/learnings/2026-02-24-guardrails-chained-commit-bypass.md` (chain operator matching)
- Learning: `knowledge-base/project/learnings/2026-03-19-skill-enforced-convention-pattern.md` (enforcement tiers)
- Pre-merge hook: `.claude/hooks/pre-merge-rebase.sh` (existing `gh pr merge` interception, Guard 6 location)
- Ship SKILL.md: `plugins/soleur/skills/ship/SKILL.md` (Phase 1.5, Phase 5.5 Code Review Completion Gate)
