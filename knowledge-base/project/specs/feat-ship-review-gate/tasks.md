# Tasks: feat-ship-review-gate

## Phase 1: Ship SKILL.md -- Add Review Evidence Gate

- [ ] 1.1 Read `plugins/soleur/skills/ship/SKILL.md` fully
- [ ] 1.2 Add Phase 1.5: Review Evidence Gate section after Phase 1 (Validate Artifact Trail)
  - [ ] 1.2.1 Step 1: Check for `todos/` files tagged `code-review` via `grep -rl "code-review" todos/`
  - [ ] 1.2.2 Step 2: Check commit history for `refactor: add code review findings` pattern
  - [ ] 1.2.3 Gate behavior: headless mode aborts, interactive mode presents Run/Skip/Abort
  - [ ] 1.2.4 Document zero-finding review edge case in Skip option text
- [ ] 1.3 Verify Phase 1.5 references do not use `$()` command substitution (ship CRITICAL rule)
- [ ] 1.4 Verify Phase 1.5 uses separate Bash calls for multi-step detection (ship pattern)

## Phase 2: Work SKILL.md -- Update Direct-Invocation Chain

- [ ] 2.1 Read `plugins/soleur/skills/work/SKILL.md` Phase 4 section
- [ ] 2.2 Update direct-invocation chain from (compound -> ship) to (review -> resolve-todo-parallel -> compound -> ship)
- [ ] 2.3 Verify one-shot invocation path remains unchanged (hand off to orchestrator)
- [ ] 2.4 Forward `--headless` flag to review and resolve-todo-parallel when headless

## Phase 3: Validation

- [ ] 3.1 Run `bun test` to verify no regressions
- [ ] 3.2 Verify SKILL.md markdown passes lint (no MD032 violations)
- [ ] 3.3 Review both modified files for consistency with existing Phase N.5 patterns
