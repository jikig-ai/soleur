# Tasks: Ship Review Gate Enforcement

**Issue:** #1227
**Branch:** feat-ship-review-gate

## Phase 1: Ship SKILL.md -- Add Review Evidence Gate (DONE)

- [x] 1.1 Add Phase 1.5: Review Evidence Gate section after Phase 1
- [x] 1.2 Gate behavior: headless mode aborts, interactive mode presents Run/Skip/Abort

## Phase 2: Work SKILL.md -- Update Direct-Invocation Chain (DONE)

- [x] 2.1 Update direct-invocation chain to: review -> resolve-todo-parallel -> compound -> ship
- [x] 2.2 Forward `--headless` flag to review step

## Phase 3: Review Evidence Gate in pre-merge-rebase.sh

- [ ] 3.1 Add early-exit review evidence check to `.claude/hooks/pre-merge-rebase.sh`
  - [ ] 3.1.1 Insert after existing early exits (skip main, skip detached HEAD), before uncommitted changes check
  - [ ] 3.1.2 Check `grep -rl "code-review" "$WORK_DIR/todos/"` for review todo files
  - [ ] 3.1.3 Check `git -C "$WORK_DIR" log origin/main..HEAD --oneline | grep "refactor: add code review findings"` for review commit
  - [ ] 3.1.4 Deny with clear message if no evidence found
- [ ] 3.2 Update `pre-merge-rebase.sh` header comment to document review evidence gate

## Phase 4: Ship Phase 5.5 Consolidation

- [ ] 4.1 Remove "Code Review Completion Gate (mandatory)" subsection from Phase 5.5 (locate by heading text)
- [ ] 4.2 Remove `Code review completed (Phase 5.5 gate)` from Phase 5 checklist
- [ ] 4.3 Verify remaining Phase 5.5 gates (CMO, COO) are intact

## Phase 5: AGENTS.md Updates

- [ ] 5.1 Update PreToolUse hooks awareness line to include review evidence gate

## Phase 6: Validation

- [ ] 6.1 Run `bun test` to verify no regressions
- [ ] 6.2 Verify markdown passes lint
- [ ] 6.3 Test review evidence gate with a `gh pr merge` command on this PR
