# Tasks: Context-Aware Agent Gating

## Phase 1: Review Skill Binary Gate

### 1.1 RED: Write test scenario for non-code gating

- [ ] Define expected behavior: non-code PRs spawn 4 agents, code PRs spawn 8
- [ ] No automated test file — this is prose-level validation against SKILL.md content

### 1.2 GREEN: Add classification gate to review SKILL.md

- [ ] Read `plugins/soleur/skills/review/SKILL.md`
- [ ] Insert a "Change Classification" section before `#### Parallel Agents to review the PR:` (line 63)
- [ ] Classification runs `git diff --name-only origin/main...HEAD | head -n 200`
- [ ] Single LLM judgment: "Does this diff contain source code files (`.ts`, `.js`, `.rb`, `.py`, `.go`, `.rs`, `.swift`, `.kt`, etc.)?"
- [ ] If **no source code**: spawn 4 agents — git-history-analyzer, pattern-recognition-specialist, security-sentinel, code-quality-analyst
- [ ] If **source code present**: spawn all 8 agents (unchanged behavior)
- [ ] Add override check: scan `$ARGUMENTS` and `gh pr view --json body,title` for "deep review" or "full review" — if found, skip classification and spawn all 8
- [ ] Explicitly state: "The conditional agents block (agents 9-14) is unaffected by this gate. Both gates run independently."

### 1.3 REFACTOR: Clean up and lint

- [ ] `npx markdownlint-cli2 --fix plugins/soleur/skills/review/SKILL.md`
- [ ] Read modified SKILL.md end-to-end to verify coherence
- [ ] Verify the classification does not interfere with the existing conditional agents block (lines 80-151)
- [ ] `bun test plugins/soleur/test/components.test.ts` — verify skill description budget

### 1.4 Run full test suite and lint

- [ ] `npx markdownlint-cli2 --fix plugins/soleur/skills/review/SKILL.md`
- [ ] `bun test plugins/soleur/test/components.test.ts`
