# Tasks: Verify PreToolUse Hooks in claude-code-action

## Phase 1: Setup

### 1.1 Create test workflow file
- Create `.github/workflows/test-pretooluse-hooks.yml`
- `workflow_dispatch` trigger only (no schedule)
- Use `anthropics/claude-code-action` with same version as existing workflows
- `claude-sonnet-4-6`, `--max-turns 15`, `timeout-minutes: 15`
- Include `id-token: write` in permissions
- Include `Bash,Read,Write,Edit,Glob,Grep` in `--allowedTools`
- Pin checkout action to same SHA as existing workflows

### 1.2 Design test prompt
- Write deterministic prompt that instructs the agent to run specific commands
- Test each hook in sequence with clear pass/fail output
- Agent must output a structured results table at the end
- Include `jq --version` check as first command

## Phase 2: Core Implementation

### 2.1 Test Guard 1 (commit on main)
- Agent checks out main branch
- Attempts `git commit --allow-empty -m "test: hook verification"`
- Captures whether the hook blocks the commit or it succeeds
- Reports: "Guard 1: BLOCKED" or "Guard 1: NOT BLOCKED"

### 2.2 Test Guard 2 (rm -rf worktrees)
- Agent creates `mkdir -p .worktrees/test-hook-verification`
- Attempts `rm -rf .worktrees/test-hook-verification`
- Captures whether the hook blocks the removal or it succeeds
- Reports result
- Cleans up the test directory regardless of outcome

### 2.3 Test Guard 4 (conflict markers)
- Agent creates a file with `<<<<<<<` markers
- Stages the file with `git add`
- Attempts `git commit -m "test: conflict markers"`
- Captures whether the hook blocks the commit or it succeeds
- Reports result

### 2.4 Test worktree-write-guard
- Agent creates `mkdir -p .worktrees/test-write-guard`
- Attempts to write a file to the repo root (not inside .worktrees/)
- Captures whether the Write tool is blocked or succeeds
- Reports result
- Cleans up the test directory

### 2.5 Test multiple hooks on same matcher
- Verify both guardrails.sh and pre-merge-rebase.sh fire for Bash tool calls
- Use a command that should trigger both hooks and check if both execute

## Phase 3: Analysis and Documentation

### 3.1 Create learning file
- Write `knowledge-base/learnings/2026-03-05-pretooluse-hooks-ci-verification.md`
- Document which hooks fire and which don't
- Include the actual workflow run URL for evidence
- Add `tags: [claude-code-action, hooks, ci]`

### 3.2 Conditional: Add inline fallback guards
- Only if hooks don't fire in Phase 2
- Add branch guard to `plugins/soleur/skills/ship/SKILL.md` before commit phase
- Add branch guard to `plugins/soleur/skills/compound/SKILL.md` before constitution promotion
- Add branch guard to `plugins/soleur/skills/work/SKILL.md` before first file write
- Each guard: check branch name, abort if main/master

### 3.3 Update constitution.md
- If hooks fire: add note that hooks are verified in claude-code-action
- If hooks don't fire: add note about fallback guard requirement for CI-invoked skills

## Phase 4: Testing and Cleanup

### 4.1 Run test workflow
- Trigger with `gh workflow run test-pretooluse-hooks.yml`
- Monitor with `gh run watch`
- Capture logs for documentation

### 4.2 Review results and commit
- Analyze workflow logs
- Commit learning file and any fallback guards
- Run compound before commit
