# Tasks: Migrate Hook-Enforced Rules from AGENTS.md to Constitution.md

**Issue:** #1316
**Plan:** `knowledge-base/project/plans/2026-04-06-chore-rule-audit-migration-plan.md`

## Phase 1: Remove Rules from AGENTS.md

- [ ] 1.1 Remove L7: Never commit directly to main rule from AGENTS.md Hard Rules
- [ ] 1.2 Remove L8: Never --delete-branch with gh pr merge rule from AGENTS.md Hard Rules
- [ ] 1.3 Remove L9: Never edit files in main repo when worktree active rule from AGENTS.md Hard Rules
- [ ] 1.4 Remove L11: Never rm -rf on worktree paths rule from AGENTS.md Hard Rules
- [ ] 1.5 Remove L14: Before merging, merge origin/main rule from AGENTS.md Hard Rules
- [ ] 1.6 Remove L15: gh issue create must include --milestone rule from AGENTS.md Hard Rules
- [ ] 1.7 Remove L18: PreToolUse hooks block summary rule from AGENTS.md Hard Rules
- [ ] 1.8 Verify AGENTS.md rule count is 56 (`grep -c '^- ' AGENTS.md`)

## Phase 2: Add Net-New Rules to Constitution.md

- [ ] 2.1 Add --delete-branch rule to constitution.md Architecture > Never section (blanket block semantics -- "whenever ANY worktree exists", not conditional on the specific branch)
- [ ] 2.2 Add rm -rf rule to constitution.md Architecture > Never section (with hook tag and rationale)
- [ ] 2.3 Update existing --milestone rule (L82) with `[hook-enforced: guardrails.sh Guard 5]` annotation
- [ ] 2.4 Verify constitution.md rule count is 253 (`grep -c '^- ' knowledge-base/project/constitution.md`)

## Phase 3: Update Hook Script and Audit Script Comments

- [ ] 3.1 Update guardrails.sh header: Guards 1, 2, 3, 5 now reference constitution.md instead of AGENTS.md; Guard 6 (git stash) stays referencing AGENTS.md
- [ ] 3.2 Update pre-merge-rebase.sh header: Remove AGENTS.md "Before merging any PR" reference; keep review evidence gate reference (Guard 6 in pre-merge-rebase.sh -- NOT migrated); keep constitution.md reference
- [ ] 3.3 Update worktree-write-guard.sh header: Remove AGENTS.md reference, keep constitution.md reference
- [ ] 3.4 Update scripts/rule-audit.sh header: Change AGENTS.md --milestone reference to constitution.md

## Phase 4: Validate

- [ ] 4.1 Run `npx markdownlint-cli2 --fix AGENTS.md knowledge-base/project/constitution.md`
- [ ] 4.2 Verify no behavioral change: hooks still block all 7 original scenarios
- [ ] 4.3 Run `bash scripts/rule-audit.sh` to verify updated budget report
- [ ] 4.4 Verify comment-only changes: `git diff .claude/hooks/ scripts/rule-audit.sh` shows only comment line changes, no code/pattern modifications
