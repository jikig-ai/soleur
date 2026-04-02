# Tasks: fix one-shot resolve-todo-parallel dead step

Source plan: `knowledge-base/project/plans/2026-04-02-fix-one-shot-resolve-todo-parallel-dead-step-plan.md`

## Phase 1: Core Fix

### 1.1 Replace Step 5 in one-shot SKILL.md

- [ ] Read `plugins/soleur/skills/one-shot/SKILL.md`
- [ ] Replace the `soleur:resolve-todo-parallel` invocation (line 107) with inline GitHub-issue resolution logic
- [ ] New Step 5 must: list `code-review` + `priority/p1-high` issues scoped to current PR via `Source: PR #<number>` body filter, spawn parallel `pr-comment-resolver` agents for each P1, commit fixes, close resolved issues
- [ ] Ensure no-op path when zero P1 issues exist (proceed immediately to Step 5.5)
- [ ] End Step 5 prose with explicit continuation: "Do NOT end your turn. Proceed to Step 5.5." (pipeline continuation safety -- see learnings `2026-03-03-and-stop-halt-language-breaks-pipeline.md`, `2026-03-03-pipeline-continuation-stalls.md`)
- [ ] Do NOT use finality language ("done", "complete", "stop", "announce") in the step prose
- [ ] Verify step numbering remains consistent (5, 5.5, 6, 7, 8, 9, 10)

### 1.2 Update resolve-todo-parallel body text

- [ ] Read `plugins/soleur/skills/resolve-todo-parallel/SKILL.md`
- [ ] Add a legacy scope note to the SKILL.md **body** (not YAML description field) clarifying it handles `todos/*.md` only
- [ ] Use the same note format as triage skill: `> **Note:** The /soleur:review skill now creates GitHub issues...`
- [ ] Do NOT modify the YAML `description:` field (word budget constraint -- see learning `2026-03-30-skill-description-word-budget-awareness.md`)

## Phase 2: Validation

### 2.1 Lint and budget checks

- [ ] Run `npx markdownlint-cli2 --fix` on both modified SKILL.md files
- [ ] Verify zero lint errors
- [ ] Run `bun test plugins/soleur/test/components.test.ts` to verify skill description word budget is not exceeded

### 2.2 Manual review

- [ ] Re-read modified `one-shot/SKILL.md` to verify step flow is coherent
- [ ] Verify the `pr-comment-resolver` agent input mapping is documented in the step instructions
- [ ] Verify issue scoping by PR number (`Source: PR #`) is specified
- [ ] Verify no finality language exists in the new Step 5 prose
- [ ] Verify `review-todo-structure.md` template includes `Source: PR #<pr_number>` line (confirmed at line 24)
