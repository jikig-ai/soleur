# Tasks: Ship Review Gate Enforcement

**Issue:** #1227
**Branch:** feat-ship-review-gate

## Phase 1: Ship SKILL.md -- Add Review Evidence Gate (DONE)

- [x] 1.1 Add Phase 1.5: Review Evidence Gate section after Phase 1
- [x] 1.2 Gate behavior: headless mode aborts, interactive mode presents Run/Skip/Abort

## Phase 2: Work SKILL.md -- Update Direct-Invocation Chain (DONE)

- [x] 2.1 Update direct-invocation chain to: review -> resolve-todo-parallel -> compound -> ship
- [x] 2.2 Forward `--headless` flag to review step

## Phase 3: Guard 6 Implementation

- [ ] 3.1 Add Guard 6 to `.claude/hooks/guardrails.sh` after Guard 5
  - [ ] 3.1.1 Match `gh pr merge` with chain operator pattern
  - [ ] 3.1.2 Resolve working directory from `.cwd` hook input
  - [ ] 3.1.3 Check review evidence: `grep -rl "code-review" todos/` and `git log` for review commit
  - [ ] 3.1.4 Extract PR number from command or resolve via `gh pr view --json number`
  - [ ] 3.1.5 Check `hotfix` label via `gh pr view <N> --json labels`
  - [ ] 3.1.6 Deny with bypass instructions if no evidence and no hotfix label
  - [ ] 3.1.7 Fail open on network errors and unparseable PR numbers
- [ ] 3.2 Update guardrails.sh header comment to include Guard 6

## Phase 4: Ship Phase 5.5 Consolidation

- [ ] 4.1 Remove "Code Review Completion Gate (mandatory)" subsection from Phase 5.5 (lines 221-242)
- [ ] 4.2 Remove `Code review completed (Phase 5.5 gate)` from Phase 5 checklist (line 214)
- [ ] 4.3 Verify remaining Phase 5.5 gates (CMO, COO) are intact

## Phase 5: AGENTS.md Updates

- [ ] 5.1 Add hotfix protocol to Hard Rules section with `[hook-enforced: guardrails.sh Guard 6]` annotation
- [ ] 5.2 Update PreToolUse hooks awareness line to include Guard 6
- [ ] 5.3 Update spec.md to reflect final implementation

## Phase 6: Validation

- [ ] 6.1 Run `bun test` to verify no regressions
- [ ] 6.2 Verify markdown passes lint
- [ ] 6.3 Test Guard 6 manually with a `gh pr merge` command on this PR
