---
plan: knowledge-base/plans/2026-03-03-chore-add-workflow-constraint-rules-plan.md
issue: "#389"
branch: feat/claude-md-constraints
---

# Tasks: Add Workflow Constraint Rules to CLAUDE.md

## Phase 1: AGENTS.md Hard Rule Additions

- [ ] 1.1 Add rebase-before-merge rule to `## Hard Rules` section
- [ ] 1.2 Add read-before-edit rule to `## Hard Rules` section
- [ ] 1.3 Add hook awareness rule listing Guards 1-4 to `## Hard Rules` section
- [ ] 1.4 Verify AGENTS.md stays under 40 lines total

## Phase 2: Constitution.md Additions

- [ ] 2.1 Add rebase-before-PR rule to `## Architecture > ### Always`
- [ ] 2.2 Add never-edit-without-read rule to `## Architecture > ### Never`
- [ ] 2.3 Verify no duplicate rules between AGENTS.md and constitution.md

## Phase 3: Verification

- [ ] 3.1 Run `bun test` to verify existing hook tests still pass
- [ ] 3.2 Run markdownlint on modified files
- [ ] 3.3 Count AGENTS.md lines and confirm under 40
- [ ] 3.4 Run compound (`skill: soleur:compound`)
- [ ] 3.5 Commit and push
