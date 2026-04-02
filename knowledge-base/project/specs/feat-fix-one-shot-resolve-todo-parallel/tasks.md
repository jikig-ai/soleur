# Tasks: fix one-shot resolve-todo-parallel dead step

Source plan: `knowledge-base/project/plans/2026-04-02-fix-one-shot-resolve-todo-parallel-dead-step-plan.md`

## Phase 1: Core Fix

### 1.1 Replace Step 5 in one-shot SKILL.md

- [ ] Read `plugins/soleur/skills/one-shot/SKILL.md`
- [ ] Replace the `soleur:resolve-todo-parallel` invocation (line 107) with inline GitHub-issue resolution logic
- [ ] New Step 5 must: list `code-review` + `priority/p1-high` issues scoped to current PR, spawn parallel `pr-comment-resolver` agents for each P1, commit fixes, close resolved issues
- [ ] Ensure no-op path when zero P1 issues exist (proceed immediately to Step 5.5)
- [ ] Verify step numbering remains consistent (5, 5.5, 6, 7, 8, 9, 10)

### 1.2 Update resolve-todo-parallel description

- [ ] Read `plugins/soleur/skills/resolve-todo-parallel/SKILL.md`
- [ ] Add a legacy scope note to the description and/or body, clarifying it handles `todos/*.md` only (consistent with triage skill's existing note)

## Phase 2: Validation

### 2.1 Lint check

- [ ] Run `npx markdownlint-cli2 --fix` on both modified SKILL.md files
- [ ] Verify zero errors

### 2.2 Manual review

- [ ] Re-read modified `one-shot/SKILL.md` to verify step flow is coherent
- [ ] Verify the `pr-comment-resolver` agent input mapping is documented in the step instructions
- [ ] Verify issue scoping by PR number is specified
