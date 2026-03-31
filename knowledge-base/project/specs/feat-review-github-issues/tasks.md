---
feature: feat-review-github-issues
issue: "#1288"
date: 2026-03-30
status: not-started
---

# Tasks: Review Skill GitHub Issue Creation

## Phase 1: Update Reference Document

- [ ] 1.1 Rewrite `plugins/soleur/skills/review/references/review-todo-structure.md`
  - [ ] 1.1.1 Add `code-review` label prerequisite check (`gh label create` if missing)
  - [ ] 1.1.2 Define simplified GitHub issue body template (Problem, Location, Proposed Fix, Acceptance Criteria) using `--body-file` pattern (not inline `--body`)
  - [ ] 1.1.3 Define label selection logic: `code-review` always + `priority/*` mapping + default `domain/engineering`
  - [ ] 1.1.4 Define milestone selection: P1 gets current active milestone, P2/P3 get `Post-MVP / Later`
  - [ ] 1.1.5 Define batch creation strategy using parallel `gh issue create` calls (sequential fallback for 15+ findings)
  - [ ] 1.1.6 Document `--milestone` enforcement per AGENTS.md Guard 5
  - [ ] 1.1.7 Add error handling pattern: log failure and continue to next finding (from compound-capture pattern)
  - [ ] 1.1.8 Add duplicate detection: check for existing `code-review` issues referencing same PR before creating
  - [ ] 1.1.9 Add active milestone detection command for P1 findings

## Phase 2: Update Review Skill SKILL.md

- [ ] 2.1 Update Step 5 heading from "Findings Synthesis and Todo Creation Using file-todos Skill" to "Findings Synthesis and GitHub Issue Creation"
  - [ ] 2.1.1 Replace `<critical_requirement>` block to reference GitHub issues as output
  - [ ] 2.1.1b Add `code-review` label existence check before first `gh issue create`
  - [ ] 2.1.2 Replace Step 2 (Create Todo Files) with "Create GitHub Issues"
  - [ ] 2.1.3 Replace file-todos skill references with `gh issue create --body-file` commands
  - [ ] 2.1.4 Add issue title format: `review: <description>` (PR link in body, not title)
  - [ ] 2.1.5 Add label flags: `--label code-review --label priority/p{n}-{level} --label domain/{domain}`
  - [ ] 2.1.6 Add milestone flag: `--milestone "Post-MVP / Later"` (or current active for P1)
- [ ] 2.2 Update Summary Report template
  - [ ] 2.2.1 Replace todo file paths with GitHub issue URLs in "Created Todo Files" section
  - [ ] 2.2.2 Rename section to "Created GitHub Issues"
  - [ ] 2.2.3 Update "Next Steps" to reference `gh issue list --label code-review` instead of `ls todos/*-pending-*.md`
  - [ ] 2.2.4 Remove `/triage` reference from primary flow; note it's for legacy local todos only

## Phase 3: Update Triage Skill Description

- [ ] 3.1 Update `plugins/soleur/skills/triage/SKILL.md` description
  - [ ] 3.1.1 Clarify scope: triage handles legacy local `todos/*.md` files only
  - [ ] 3.1.2 Note that `/soleur:review` now creates GitHub issues directly
  - [ ] 3.1.3 Cross-reference `ticket-triage` agent for GitHub issue classification

## Phase 4: Verification

- [ ] 4.1 Run `npx markdownlint-cli2 --fix` on all changed `.md` files
- [ ] 4.2 Create `code-review` label if missing: `gh label create code-review --description "Finding from code review" --color 0E8A16`
- [ ] 4.3 Verify all referenced labels exist: `gh label list | grep -E "code-review|priority/|domain/"`
- [ ] 4.4 Verify `--milestone` flag is present in every `gh issue create` example in changed files
- [ ] 4.5 Read back all modified files to confirm no formatting issues
