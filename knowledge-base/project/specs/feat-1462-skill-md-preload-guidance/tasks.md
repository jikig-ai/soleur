# Tasks: Add Bun Preload Execution-Order Guidance

## Phase 1: Implementation

### 1.1 Add bullet to SKILL.md

- [ ] Edit `plugins/soleur/skills/work/SKILL.md` Phase 2 > Task Execution Loop > "Test environment setup" paragraph
- [ ] Insert the bun preload guidance bullet after the existing paragraph
- [ ] Include back-reference to source learning file

### 1.2 Validate

- [ ] Run `npx markdownlint-cli2 --fix plugins/soleur/skills/work/SKILL.md` -- no errors
- [ ] Verify learning file path exists: `knowledge-base/project/learnings/test-failures/2026-04-03-bun-test-dom-preload-execution-order.md`
- [ ] Visual check: bullet renders correctly with proper indentation under the Test environment setup section
