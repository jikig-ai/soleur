# Tasks: Verify PreToolUse Hooks in claude-code-action

## Phase 1: Setup

### 1.1 Create test workflow file
- Create `.github/workflows/test-pretooluse-hooks.yml`
- `workflow_dispatch` trigger only (no schedule)
- Use `anthropics/claude-code-action@64c7a0ef71df67b14cb4471f4d9c8565c61042bf` (same SHA as bug-fixer)
- Pin `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5` (same SHA as existing workflows)
- `claude-sonnet-4-6`, `--max-turns 15`, `timeout-minutes: 15`
- Include `id-token: write` and `contents: write` in permissions
- Include `Bash,Read,Write,Edit,Glob,Grep` in `--allowedTools`
- Include `plugin_marketplaces` and `plugins` inputs to match real workflow conditions
- Use `ref: main` in checkout step (not default detached HEAD)

### 1.2 Add prerequisite verification step
- Add a `run:` step BEFORE the claude-code-action step
- `chmod +x .claude/hooks/*.sh` to ensure execute permissions
- `ls -la .claude/hooks/` to log hook files
- `jq --version` to verify jq availability
- `git rev-parse --abbrev-ref HEAD` to verify branch checkout (must show `main`, not `HEAD`)
- `cat .claude/settings.json` to verify hook configuration is present

### 1.3 Design test prompt
- Write deterministic prompt that instructs the agent to run specific commands in sequence
- Each test: attempt a hook-triggering action, report PASS/FAIL based on whether hook blocked it
- Agent must NOT work around blocked actions -- a blocked action IS the PASS condition
- Agent outputs a structured markdown results table at the end
- Include Test 0 (prerequisites) to verify environment before running tests

## Phase 2: Core Implementation

### 2.1 Test Guard 1 (commit on main)
- Agent verifies `git rev-parse --abbrev-ref HEAD` returns `main`
- Attempts `git commit --allow-empty -m "test: hook verification guard 1"`
- If blocked with "BLOCKED: Committing directly to main" -> PASS
- If the commit succeeds -> FAIL
- **Edge case**: If branch is `HEAD` (detached), test is invalid -- report SKIP with reason

### 2.2 Test Guard 2 (rm -rf worktrees)
- Agent creates `mkdir -p .worktrees/test-hook-verification`
- Attempts `rm -rf .worktrees/test-hook-verification`
- If blocked with "BLOCKED: rm -rf on worktree paths" -> PASS
- If the removal succeeds -> FAIL
- Clean up test directory regardless of outcome

### 2.3 Test Guard 4 (conflict markers)
- Agent creates a file test-conflict.txt containing a line with `<<<<<<<`
- Stages the file with `git add test-conflict.txt`
- Attempts `git commit -m "test: conflict marker guard"`
- If blocked with "BLOCKED: Staged content contains conflict markers" -> PASS
- If the commit succeeds -> FAIL

### 2.4 Test worktree-write-guard
- Agent creates `mkdir -p .worktrees/test-write-guard`
- Attempts to use the Write tool to write a file at the repo root (NOT inside .worktrees/)
- If blocked with "BLOCKED: Writing to main repo checkout" -> PASS
- If the write succeeds -> FAIL
- Clean up: `rm -rf .worktrees/test-write-guard test-write-guard.txt`

### 2.5 Verify hook files loaded
- Agent runs `cat .claude/settings.json` to confirm hooks are in the settings
- Agent checks if `$CLAUDE_PROJECT_DIR` is set (for path resolution understanding)
- This is informational -- no PASS/FAIL, just documentation of the environment

## Phase 3: Analysis and Documentation

### 3.1 Create learning file
- Write `knowledge-base/project/learnings/2026-03-05-pretooluse-hooks-ci-verification.md`
- Document which hooks fire and which don't
- Document the `cwd` value from hook JSON input (runner workspace path)
- Include the actual workflow run URL for evidence
- Add YAML frontmatter: `tags: [claude-code-action, hooks, ci, pretooluse]`
- Note: create this file regardless of outcome (both results are valuable knowledge)

### 3.2 Conditional: Add inline fallback guards
- Only if hooks don't fire in Phase 2
- Add branch guard to `plugins/soleur/skills/ship/SKILL.md` before commit phase
- Add branch guard to `plugins/soleur/skills/compound/SKILL.md` before constitution promotion
- Add branch guard to `plugins/soleur/skills/work/SKILL.md` before first file write
- Each guard: check branch name, abort if main/master
- Align with `--headless` convention from headless mode plan

### 3.3 Conditional: Investigate competitive-analysis workflow impact
- Only if Guard 1 fires (hooks work)
- The competitive-analysis workflow commits directly to main
- If Guard 1 blocks commits on main, this workflow may break
- Check whether the workflow uses detached HEAD (which bypasses Guard 1)
- If Guard 1 would break it: file a follow-up issue to fix the workflow (use feature branch)

### 3.4 Update constitution.md
- If hooks fire: add note confirming hooks work in claude-code-action
- If hooks don't fire: add note about fallback guard requirement for CI-invoked skills
- Either way: document the detached HEAD bypass edge case for Guard 1

## Phase 4: Testing and Cleanup

### 4.1 Commit test workflow and push
- Commit `.github/workflows/test-pretooluse-hooks.yml`
- Push to the feature branch
- Merge to main (the workflow must be on main to test hooks on main)

### 4.2 Run test workflow
- Trigger with `gh workflow run test-pretooluse-hooks.yml`
- Monitor with `gh run watch` or poll `gh run list`
- Capture logs with `gh run view <run-id> --log`

### 4.3 Review results and commit
- Analyze workflow logs for PASS/FAIL on each test
- Write learning file with results
- Add any fallback guards if needed
- Run compound before commit
- Remove or disable the test workflow after verification (it's a one-time test)
