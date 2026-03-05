---
title: "chore: Verify PreToolUse Hooks in claude-code-action"
type: fix
date: 2026-03-05
deepened: 2026-03-05
---

# chore: Verify PreToolUse Hooks in claude-code-action

## Enhancement Summary

**Deepened on:** 2026-03-05
**Research sources:** Claude Code hooks reference (code.claude.com), claude-code-action source (setup-claude-code-settings.ts, action.yml), 6 institutional learnings, SpecFlow analysis

### Key Improvements
1. Strong hypothesis formed: hooks likely DO fire because Claude Code loads project `.claude/settings.json` independently of the action's `settings` input -- the action only writes to `~/.claude/settings.json` (user-level), not project-level
2. Detached HEAD bypass identified as the highest-risk edge case -- Guard 1 returns `HEAD` (not `main`) in detached state, silently passing
3. Test workflow design refined: must use `actions/checkout` with `ref: main` to get a real branch checkout, not detached HEAD
4. `$CLAUDE_PROJECT_DIR` environment variable confirmed available for hook path resolution
5. `PermissionRequest` hooks confirmed NOT to fire in non-interactive mode, but `PreToolUse` hooks are documented as firing normally

### New Considerations Discovered
- The competitive-analysis workflow already commits directly to main with a prompt override ("AGENTS.md rule does NOT apply here") -- if Guard 1 fires, it would block this workflow's push unless the agent is in detached HEAD state
- Hook scripts must be executable (`chmod +x`) -- the CI runner may not preserve execute bits from the Git checkout; verify with `ls -la .claude/hooks/`
- All matching hooks for the same matcher run in parallel, and identical commands are deduplicated

## Overview

Empirically verify whether PreToolUse hooks (`.claude/settings.json`) fire when skills run inside `claude-code-action` (GitHub Actions). If they don't, add inline fallback branch-safety checks to ship, compound, and work skills. This is a prerequisite for the headless mode scheduled workflows descoped from #393.

## Problem Statement / Motivation

PreToolUse hooks are the primary safety mechanism for the Soleur plugin:

- **guardrails.sh** blocks commits on main, rm -rf on worktrees, --delete-branch with active worktrees, and commits with conflict markers
- **pre-merge-rebase.sh** auto-syncs feature branches with origin/main before `gh pr merge`
- **worktree-write-guard.sh** blocks file writes to the main repo when worktrees exist

Whether these hooks fire in `claude-code-action` is unknown and untested. Four existing workflows already use `claude-code-action` (daily-triage, bug-fixer, competitive-analysis, code-review), but none exercise hook-triggering scenarios (commits, merges, file writes). If hooks silently don't fire in CI, the competitive-analysis workflow (which commits directly to main) and future headless ship/compound workflows operate without safety guards.

The brainstorm for #393 (headless mode) explicitly flagged this as a risk: "PreToolUse hooks MUST be verified to fire under `claude -p` / GitHub Actions."

### Research Insights: Hook Loading Architecture

**Hypothesis: Hooks likely DO fire.** Analysis of the claude-code-action source code reveals:

1. **Settings layer separation**: `claude-code-action`'s `setupClaudeCodeSettings()` writes the action's `settings` input to `~/.claude/settings.json` (user-level). It does NOT touch project-level `.claude/settings.json`.
2. **Claude Code loads both**: Claude Code's settings resolution loads from multiple locations in priority order: managed policy > project `.claude/settings.json` > user `~/.claude/settings.json`. Since the action checks out the repo (with `actions/checkout`), the project's `.claude/settings.json` is present in the working directory, and Claude Code should load it.
3. **Hooks merge across locations**: Hooks from user and project settings are merged, not replaced. Multiple hooks on the same matcher all fire in parallel.

**Risk: This is inference, not verification.** The source analysis is strong evidence but not proof. The action may have sandboxing, `disableAllHooks`, or other overrides not visible in the public source. Empirical testing remains necessary.

### Research Insights: Institutional Learnings

**Applicable learnings from knowledge-base/learnings/:**

- **Guardrails chained commit bypass** (`2026-02-24`): Guard 1 was previously bypassed by `&&`-chained commands. The fix uses `(^|&&|\|\||;)` pattern. In CI, the agent may chain commands the same way -- the fix already handles this.
- **Guardrails grep false positive** (`2026-02-24`): Guard 2 had false positives when `.worktrees/` appeared in comment text (e.g., `gh issue comment`). The single-pattern fix enforces proximity. In CI, agents may include `.worktrees/` in issue bodies -- the fix already handles this.
- **claude-code-action token revocation** (`2026-03-02`): The action revokes its token in post-step cleanup. Any git push must happen INSIDE the agent prompt, not in a subsequent step. The test workflow should keep all assertions within the agent prompt.
- **Schedule skill CI plugin discovery** (`2026-02-27`): `claude-code-action` has no local plugin discovery -- must use `plugin_marketplaces` and `plugins` inputs. The test workflow should include plugin installation to match real workflow conditions.
- **GitHub Actions workflow security patterns** (`2026-02-21`): Pin actions to commit SHAs, validate inputs, check exit codes explicitly.

## Proposed Solution

### Phase 1: Create a Test Workflow

Create `.github/workflows/test-pretooluse-hooks.yml` -- a `workflow_dispatch`-only workflow that invokes `claude-code-action` with a prompt designed to trigger each hook and report results.

**Test matrix:**

| Hook | Trigger | Expected Behavior | Verification |
|------|---------|-------------------|-------------|
| guardrails.sh Guard 1 | `git commit -m "test" --allow-empty` on main | Blocked with "BLOCKED: Committing directly to main" | Check workflow logs for deny message |
| guardrails.sh Guard 2 | `rm -rf .worktrees/test-dir` (after creating dummy dir) | Blocked with "BLOCKED: rm -rf on worktree paths" | Check workflow logs for deny message |
| guardrails.sh Guard 4 | Stage a file with `<<<<<<<` markers, then commit | Blocked with "BLOCKED: Staged content contains conflict markers" | Check workflow logs for deny message |
| pre-merge-rebase.sh | `gh pr merge` on a branch behind main | Auto-syncs and allows merge | Check logs for "merged origin/main" message |
| worktree-write-guard.sh | Write to main repo path with `.worktrees/` dir present | Blocked with "BLOCKED: Writing to main repo checkout" | Check workflow logs for deny message |

#### Research Insights: Workflow Design

**Best Practices:**
- Use `workflow_dispatch` only (no schedule) to avoid unnecessary recurring costs
- Pin `actions/checkout` and `claude-code-action` to exact SHAs matching existing workflows
- Include `id-token: write` in permissions (required for OIDC auth)
- Set `timeout-minutes: 15` to cap runaway billing
- Use `claude-sonnet-4-6` with `--max-turns 15` for cost control

**Performance Considerations:**
- Keep the test prompt deterministic: list exact commands the agent must run in sequence
- Do NOT use open-ended exploration prompts -- the agent should execute a fixed checklist
- Include `jq --version` as the first check to verify the dependency

**Edge Cases:**
- **Detached HEAD state**: `actions/checkout` with `fetch-depth: 1` creates a detached HEAD by default. Guard 1 checks `git rev-parse --abbrev-ref HEAD` which returns `HEAD` in detached state, NOT `main`. This means Guard 1 would pass-through even if the agent is on the main commit. Fix: the test must use `actions/checkout` with explicit `ref: main` and then run `git checkout main` to get a real branch checkout.
- **Execute permission on hooks**: Git stores the execute bit, but `actions/checkout` may not preserve it on all platforms. The test prompt should include `chmod +x .claude/hooks/*.sh` as a safety step, and also check `ls -la .claude/hooks/` to verify permissions.
- **Plugin loading**: Include `plugin_marketplaces` and `plugins` inputs to match real workflow conditions (hooks fire in the context of plugin-loaded sessions).

**Implementation Details:**

```yaml
# .github/workflows/test-pretooluse-hooks.yml
name: "Test: PreToolUse Hooks"

on:
  workflow_dispatch:

permissions:
  contents: write
  id-token: write

jobs:
  test-hooks:
    runs-on: ubuntu-latest
    timeout-minutes: 15

    steps:
      - name: Checkout repository
        uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
        with:
          ref: main

      - name: Verify hook scripts are executable
        run: |
          chmod +x .claude/hooks/*.sh
          ls -la .claude/hooks/
          jq --version

      - name: Test hooks
        uses: anthropics/claude-code-action@64c7a0ef71df67b14cb4471f4d9c8565c61042bf # v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          plugin_marketplaces: 'https://github.com/jikig-ai/soleur.git'
          plugins: 'soleur@soleur'
          claude_args: >-
            --model claude-sonnet-4-6
            --max-turns 15
            --allowedTools Bash,Read,Write,Edit,Glob,Grep
          prompt: |
            You are testing whether PreToolUse hooks fire in this CI environment.
            Run each test below in order. For each test, report PASS (hook blocked
            the action) or FAIL (action succeeded without hook intervention).

            IMPORTANT: Do NOT attempt to work around any blocked actions. If a hook
            blocks a command, that is the expected PASS result.

            ## Test 0: Prerequisites
            Run: jq --version
            Run: ls -la .claude/hooks/
            Run: cat .claude/settings.json
            Run: git rev-parse --abbrev-ref HEAD
            Report: which branch you are on and whether hook files exist.

            ## Test 1: Guard 1 - Commit on main
            Run: git commit --allow-empty -m "test: hook verification guard 1"
            If blocked with "BLOCKED: Committing directly to main" -> PASS
            If the commit succeeds -> FAIL

            ## Test 2: Guard 2 - rm -rf worktrees
            Run: mkdir -p .worktrees/test-hook-verification
            Run: rm -rf .worktrees/test-hook-verification
            If blocked with "BLOCKED: rm -rf on worktree paths" -> PASS
            If the removal succeeds -> FAIL

            ## Test 3: Guard 4 - Conflict markers
            Create a file test-conflict.txt containing a line with <<<<<<<
            Run: git add test-conflict.txt
            Run: git commit -m "test: conflict marker guard"
            If blocked with "BLOCKED: Staged content contains conflict markers" -> PASS
            If the commit succeeds -> FAIL

            ## Test 4: Write guard
            Run: mkdir -p .worktrees/test-write-guard
            Then use the Write tool to write a file at the repo root (NOT
            inside .worktrees/). For example, write to test-write-guard.txt.
            If blocked with "BLOCKED: Writing to main repo checkout" -> PASS
            If the write succeeds -> FAIL
            Clean up: rm -rf .worktrees/test-write-guard test-write-guard.txt

            ## Summary
            Output a markdown table:
            | Test | Hook | Result | Details |
            |------|------|--------|---------|
            Fill in each row with the test results.
```

### Phase 2: Analyze Results and Document

After running the test workflow:

1. **If hooks fire**: Document confirmation in a learning file, close the issue
2. **If hooks don't fire**: Proceed to Phase 3

#### Research Insights: Documentation Pattern

**Best Practices:**
- Create the learning file regardless of outcome -- both "hooks fire" and "hooks don't fire" are valuable institutional knowledge
- Include the workflow run URL as evidence
- Tag with `[claude-code-action, hooks, ci, pretooluse]` for future discoverability
- If hooks fire, also document which hooks fire (some may fire while others don't due to matcher or permission differences)

### Phase 3: Inline Fallback Guards (Conditional)

If hooks don't fire, add lightweight inline checks to the skills that depend on them:

**ship SKILL.md** -- Add before commit phase:
```bash
# Fallback branch guard (defense-in-depth when PreToolUse hooks unavailable)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  echo "ERROR: Cannot ship from main/master" >&2; exit 1
fi
```

**compound SKILL.md** -- Add before constitution promotion:
```bash
# Fallback branch guard
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  echo "ERROR: Cannot run compound on main/master" >&2; exit 1
fi
```

**work SKILL.md** -- Add before first file write:
```bash
# Fallback branch guard
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  echo "ERROR: Cannot run work on main/master" >&2; exit 1
fi
```

#### Research Insights: Fallback Guard Design

**Best Practices:**
- Fallback guards should be defense-in-depth, not replacements for hooks. Even if hooks fire, adding the guards is cheap insurance.
- Use `exit 2` (not `exit 1`) if the guard is in a script that Claude Code may interpret as a hook output -- but in SKILL.md inline blocks, `exit 1` is correct since these run as regular bash commands.
- The `$BRANCH = "HEAD"` case (detached HEAD) is ambiguous -- detached HEAD could be on any commit. In CI, it's likely on the main branch tip. Consider adding `|| [ "$BRANCH" = "HEAD" ]` to the guard for CI safety, but this would break legitimate detached-HEAD work locally.

**Edge Cases:**
- `git rev-parse --abbrev-ref HEAD` returns `HEAD` in detached state (not `main`). This is a bypass vector in CI where `actions/checkout` creates detached HEAD. Constitution.md should document this edge case.
- Skills invoked by competitive-analysis workflow explicitly override the "no commits on main" rule. Fallback guards must check for a `--headless` or `--ci-override` flag to allow this pattern.

**Implementation Details:**
- Consider adding guards even if hooks fire (defense-in-depth principle from constitution.md line 199)
- The headless mode plan already includes a branch guard for compound (`--headless` aborts on main/master). Align the fallback guard pattern with the headless convention.

## Technical Considerations

### Hook Loading in claude-code-action

The critical unknown: does `claude-code-action` load `.claude/settings.json` from the checked-out repository? The action checks out the repo, then invokes Claude Code. If Claude Code reads `.claude/settings.json` from the working directory (standard behavior), hooks should load. But if the action operates in a sandboxed mode that ignores project settings, hooks won't fire.

#### Research Insights: Settings Architecture

**Source code analysis of `setup-claude-code-settings.ts`:**
- The action's `settings` input is written to `~/.claude/settings.json` (user-level home directory)
- The function reads existing user settings, merges with input settings via object spread, then writes back
- It always forces `enableAllProjectMcpServers: true`
- **It does NOT read or modify project-level `.claude/settings.json`**

**Claude Code settings resolution (from docs):**
Settings load from multiple locations with a merge hierarchy:
1. Managed policy settings (highest priority)
2. Project `.claude/settings.json` (committed to repo)
3. Project `.claude/settings.local.json` (gitignored)
4. User `~/.claude/settings.json` (home directory)

Since `claude-code-action` only writes to user-level and Claude Code independently loads project-level, hooks defined in project `.claude/settings.json` should load. The action's `settings` input adds to (not replaces) project hooks.

**Environment variables available to hooks:**
- `$CLAUDE_PROJECT_DIR`: project root directory
- `$CLAUDE_CODE_REMOTE`: set to `"true"` in remote web environments (not set in local CLI)
- `cwd` field in JSON input: working directory when the hook fired

**References:**
- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks)
- [Claude Code hooks guide](https://code.claude.com/docs/en/hooks-guide)

### Hook Dependencies

All three hooks require `jq` on the runner. `ubuntu-latest` includes `jq` by default, but this is an implicit dependency. The test workflow should verify `jq` availability.

#### Research Insights

**Best Practices:**
- Always verify `jq` as the first test step before running hook tests
- The hooks guide recommends: "Install it with `apt-get install jq` (Debian/Ubuntu)" as a fallback
- Consider adding `which jq` to the prerequisite check for diagnostic output

### Git State in CI

GitHub Actions checkout creates a detached HEAD state by default. Guard 1 (block commits on main) uses `git rev-parse --abbrev-ref HEAD`, which returns `HEAD` in detached state -- this would bypass the guard. The test must verify behavior in both detached HEAD and checked-out branch states.

#### Research Insights: Checkout Behavior

**Best Practices:**
- Use `ref: main` in `actions/checkout` to get a clean branch checkout
- After checkout, verify with `git rev-parse --abbrev-ref HEAD` that the result is `main` (not `HEAD`)
- The `fetch-depth: 1` default is acceptable since Guard 1 only needs the current branch name

**Edge Cases:**
- PR-triggered workflows check out the merge commit, creating a detached HEAD pointing at a temporary merge ref. Guard 1 returns `HEAD` in this case -- it will NOT block commits in PR-context workflows.
- `workflow_dispatch` on the default branch checks out that branch directly. With `ref: main`, the checkout should produce `main` as the branch name.
- If the test uses `ref: ${{ github.sha }}`, it creates a detached HEAD. Use `ref: main` for branch-name testing.

### Multiple Hooks on Same Matcher

Two hooks match the `Bash` tool (guardrails.sh and pre-merge-rebase.sh). The test must verify that all matching hooks execute, not just the first.

#### Research Insights

**Per the hooks reference:** "All matching hooks run in parallel, and identical hook commands are automatically deduplicated." This means both guardrails.sh and pre-merge-rebase.sh should fire simultaneously on every Bash tool call. They cannot conflict because they check different conditions (guardrails checks command patterns, pre-merge-rebase checks for `gh pr merge`).

### SpecFlow Edge Cases (from analysis)

1. **Hook path resolution**: Hooks are referenced as relative paths (`.claude/hooks/guardrails.sh`). In CI, the working directory is the repo root after checkout -- this should resolve correctly, but needs verification. The hooks guide recommends using `"$CLAUDE_PROJECT_DIR"/.claude/hooks/script.sh` for robustness.
2. **stdin JSON contract**: Hooks receive `session_id`, `cwd`, `hook_event_name`, `tool_name`, and `tool_input` on stdin. The `cwd` field contains the working directory when the event fired -- in CI, this will be the runner workspace path (e.g., `/home/runner/work/soleur/soleur`).
3. **Exit code semantics**: Exit 0 with JSON `permissionDecision: "deny"` blocks the tool. Exit 2 with stderr message also blocks (stderr becomes Claude's feedback). Any other exit code is a non-blocking error that allows execution to continue. The test must verify deny actually blocks tool execution.
4. **Worktree absence in CI**: Guards 2, 3, and the write guard check for worktrees. In CI there are no worktrees -- these guards should pass-through (allow). Test should verify no false denials.
5. **Execute permission**: Git stores the execute bit, but the CI checkout may not preserve it. The workflow must `chmod +x .claude/hooks/*.sh` before the agent runs.
6. **Shell profile contamination**: If the runner's shell profile contains unconditional `echo` statements, that output gets prepended to hook JSON, causing parse failures. The ubuntu-latest runner should be clean, but worth noting.

## Acceptance Criteria

- [ ] Test workflow `.github/workflows/test-pretooluse-hooks.yml` created and runs successfully
- [ ] Guard 1 (commit on main) behavior documented for claude-code-action
- [ ] Guard 2 (rm -rf worktrees) behavior documented for claude-code-action
- [ ] Guard 4 (conflict markers) behavior documented for claude-code-action
- [ ] pre-merge-rebase.sh behavior documented for claude-code-action
- [ ] worktree-write-guard.sh behavior documented for claude-code-action
- [ ] If hooks don't fire: inline fallback branch guards added to ship, compound, and work skills
- [ ] If hooks do fire: learning file documenting confirmation created
- [ ] Results documented in knowledge-base/learnings/ regardless of outcome

## Test Scenarios

- Given the test workflow runs on ubuntu-latest with `ref: main`, when the agent runs `git rev-parse --abbrev-ref HEAD`, then the result is `main` (not `HEAD`), confirming a real branch checkout
- Given the test workflow runs on ubuntu-latest, when the agent attempts `git commit` on main branch, then either (a) the hook blocks with "BLOCKED" message or (b) the commit succeeds -- documenting which outcome occurs
- Given the test workflow runs, when the agent creates a `.worktrees/` directory and attempts to write a file to the repo root, then either the write guard blocks or allows -- documenting the outcome
- Given the test workflow runs, when the agent stages a file with conflict markers and attempts to commit, then either Guard 4 blocks or the commit succeeds -- documenting the outcome
- Given hooks don't fire in CI, when inline fallback guards are added to ship/compound/work, then those skills abort when run on main/master regardless of hook availability
- Given hooks do fire in CI, when all guards are verified as operational, then a learning file is created confirming the behavior and the issue is closed
- Given the competitive-analysis workflow commits to main with a prompt override, when Guard 1 fires, then the workflow may be blocked -- investigate whether detached HEAD bypasses it or whether the prompt override is insufficient

## Non-Goals

- Fixing or improving the existing hooks (separate issues if needed)
- Adding hooks to the scheduled workflows that already exist (daily-triage, bug-fixer, etc.)
- Making all skills headless (that's #393's scope, already shipped)
- Testing `claude -p` (non-Action CLI) hook behavior (different runtime, different issue)
- Migrating hook paths to use `$CLAUDE_PROJECT_DIR` (improvement, not verification)

## Success Metrics

- Binary: hooks fire or they don't. The outcome determines the next action.
- If hooks fire: issue closes immediately with learning documentation.
- If hooks don't fire: PR adds fallback guards to 3 skills (ship, compound, work).

## Dependencies & Risks

**Risk: Test workflow costs API credits.** Mitigation: use `claude-sonnet-4-6` (cheaper), limit `--max-turns 15`, and make the test prompt deterministic (explicit commands to run, not open-ended exploration).

**Risk: Test modifies repo state.** Mitigation: all test operations use `--allow-empty` commits or temporary files, test runs on a disposable branch created by the workflow.

**Risk: Hook behavior differs between claude-code-action versions.** Mitigation: pin the same action version used by existing workflows (v1).

**Risk: Detached HEAD bypasses Guard 1.** Even if hooks fire, Guard 1 may silently pass because the checkout produces `HEAD` instead of `main`. The test must explicitly verify the branch name after checkout.

**Risk: Competitive-analysis workflow breaks if Guard 1 fires.** The workflow commits directly to main. If Guard 1 fires and the checkout is on the `main` branch (not detached HEAD), the agent's commit would be blocked. This is actually the DESIRED behavior -- but the workflow's prompt override says "AGENTS.md rule does NOT apply here." A PreToolUse hook does not read prompt instructions; it enforces mechanically. If this breaks the competitive-analysis workflow, it should be fixed by having that workflow use a feature branch, not by disabling the guard. File a follow-up issue if this happens.

**Semver intent:** `semver:patch` if hooks fire (docs only). `semver:patch` if fallback guards needed (defensive improvement, no new capability).

## References & Research

### Internal References

- PreToolUse hooks: `.claude/settings.json:14-44`
- guardrails.sh: `.claude/hooks/guardrails.sh`
- pre-merge-rebase.sh: `.claude/hooks/pre-merge-rebase.sh`
- worktree-write-guard.sh: `.claude/hooks/worktree-write-guard.sh`
- Headless mode plan: `knowledge-base/plans/2026-03-03-feat-headless-mode-repeatable-workflows-plan.md`
- Headless mode brainstorm: `knowledge-base/brainstorms/2026-03-03-headless-mode-brainstorm.md`
- Existing claude-code-action workflows: `.github/workflows/scheduled-bug-fixer.yml`, `.github/workflows/scheduled-daily-triage.yml`, `.github/workflows/scheduled-competitive-analysis.yml`, `.github/workflows/claude-code-review.yml`
- Hook learning (worktree write guard): `knowledge-base/learnings/2026-02-26-worktree-enforcement-pretooluse-hook.md`
- Hook learning (pre-merge rebase): `knowledge-base/learnings/2026-03-03-pre-merge-rebase-hook-implementation.md`
- Hook learning (SessionStart contract): `knowledge-base/learnings/2026-03-04-sessionstart-hook-api-contract.md`
- Guardrails chained commit bypass: `knowledge-base/learnings/2026-02-24-guardrails-chained-commit-bypass.md`
- Guardrails grep false positive: `knowledge-base/learnings/2026-02-24-guardrails-grep-false-positive-worktree-text.md`
- Token revocation in claude-code-action: `knowledge-base/learnings/2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md`
- CI plugin discovery: `knowledge-base/learnings/2026-02-27-schedule-skill-ci-plugin-discovery-and-version-hygiene.md`
- GitHub Actions security patterns: `knowledge-base/learnings/2026-02-21-github-actions-workflow-security-patterns.md`

### External References

- Claude Code hooks reference: https://code.claude.com/docs/en/hooks
- Claude Code hooks guide: https://code.claude.com/docs/en/hooks-guide
- claude-code-action repository: https://github.com/anthropics/claude-code-action
- claude-code-base-action settings setup: https://github.com/anthropics/claude-code-base-action/blob/main/src/setup-claude-code-settings.ts

### Related Work

- Parent issue: #393 (headless mode)
- This issue: #419
- Constitution hook preference: `knowledge-base/overview/constitution.md:199` ("Prefer hook-based enforcement over documentation-only rules")
