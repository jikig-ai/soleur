---
title: "chore: migrate existing hooks to hookSpecificOutput JSON format"
type: fix
date: 2026-03-03
deepened: 2026-03-03
---

## Enhancement Summary

**Deepened on:** 2026-03-03
**Sections enhanced:** 3 (Proposed Solution, Test Scenarios, Context)

### Key Improvements

1. Clarified `hookEventName` field is NOT part of the API spec -- omit it from migrated hooks (diverges from `pre-merge-rebase.sh` reference but aligns with documented API)
2. Added `systemMessage` as optional top-level field for providing context to Claude after denial
3. Added verification commands for testing JSON output validity post-migration

### New Considerations Discovered

- The `pre-merge-rebase.sh` reference includes an undocumented `hookEventName` field; the migrated hooks should NOT copy this to stay spec-compliant
- The `permissionDecisionReason` field name is used by `pre-merge-rebase.sh` but the official API docs do not list it -- the documented way to explain denials is via `systemMessage` at the top level; however, `permissionDecisionReason` is used in the existing reference implementation and appears to work, so this plan uses it for consistency with `pre-merge-rebase.sh`

# chore: Migrate Existing Hooks to hookSpecificOutput JSON Format

## Overview

Two PreToolUse hooks (`guardrails.sh`, `worktree-write-guard.sh`) use the deprecated `{"decision":"block","reason":"..."}` JSON output format. The Claude Code hooks API requires PreToolUse hooks to use `hookSpecificOutput` with `permissionDecision`/`permissionDecisionReason` fields. The newer `pre-merge-rebase.sh` (PR #399) already uses the correct format and serves as the reference implementation.

## Problem Statement

The deprecated format still works but is inconsistent with the documented API and the project's own `pre-merge-rebase.sh`. Three reviewers flagged this during PR #399 review (pattern-recognition-specialist, architecture-strategist, code-quality-analyst). Inconsistency risks:

- Future Claude Code updates may drop support for the deprecated format
- New hooks copy-pasted from existing ones will inherit the wrong pattern
- Mixed formats make auditing and understanding hook behavior harder

## Affected Files

| File | Hook Type | Occurrences | Notes |
|------|-----------|-------------|-------|
| `.claude/hooks/guardrails.sh` | PreToolUse (Bash) | 3 echo statements (lines 37, 47, 55) | Static strings, use `echo` |
| `.claude/hooks/worktree-write-guard.sh` | PreToolUse (Write\|Edit) | 1 echo statement (line 36) | Dynamic string with variable interpolation |

### Not in scope

| File | Hook Type | Reason |
|------|-----------|--------|
| `.claude/hooks/pre-merge-rebase.sh` | PreToolUse (Bash) | Already uses correct format |
| `plugins/soleur/hooks/stop-hook.sh` | Stop | Stop hooks use `decision`/`reason` format (correct per API docs) |

## Proposed Solution

Migrate each deprecated output from:

```json
{"decision":"block","reason":"BLOCKED: <message>"}
```

To:

```json
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: <message>"
  }
}
```

### Research Insights

**API Spec vs Reference Implementation:**

The Claude Code hooks API documents three fields inside `hookSpecificOutput`:
- `permissionDecision` (required): `"allow"`, `"deny"`, or `"ask"`
- `updatedInput` (optional): object to modify tool input before execution
- `systemMessage` (optional, top-level): explanation for Claude

The existing `pre-merge-rebase.sh` reference includes two undocumented fields:
- `hookEventName: "PreToolUse"` -- not in the API spec, likely echoed from input
- `permissionDecisionReason` -- not documented but functional; the spec suggests using `systemMessage` at the top level instead

**Decision:** Omit `hookEventName` (not spec-compliant). Keep `permissionDecisionReason` for consistency with `pre-merge-rebase.sh` -- it works and is more ergonomic than `systemMessage` for denial explanations.

**Edge Case -- `jq` availability:**

All hooks already depend on `jq` for parsing input (`jq -r '.tool_input.command // ""'`). Switching output from `echo` to `jq -n` adds no new dependency.

**Edge Case -- stdout contamination:**

Per `knowledge-base/learnings/2026-03-03-pre-merge-rebase-hook-implementation.md`: git commands that produce output to stdout corrupt JSON output from hooks. The migrated hooks do not run git commands between guard detection and JSON output, so this is not a risk here. However, `jq -n` is safer than `echo` because `jq` always produces valid JSON regardless of shell quoting context.

### guardrails.sh (3 changes)

All three guards use static `echo` with single-quoted strings. Replace each with `jq -n` for consistent, safe JSON generation (matching `pre-merge-rebase.sh` pattern):

**Guard 1 (line 37)** -- commit on main:

```bash
# Before
echo '{"decision":"block","reason":"BLOCKED: Committing directly to main/master is not allowed. Create a feature branch first."}'

# After
jq -n '{
  hookSpecificOutput: {
    permissionDecision: "deny",
    permissionDecisionReason: "BLOCKED: Committing directly to main/master is not allowed. Create a feature branch first."
  }
}'
```

**Guard 2 (line 47)** -- rm -rf worktrees:

```bash
# Before
echo '{"decision":"block","reason":"BLOCKED: rm -rf on worktree paths is not allowed. Use git worktree remove or worktree-manager.sh cleanup-merged instead."}'

# After
jq -n '{
  hookSpecificOutput: {
    permissionDecision: "deny",
    permissionDecisionReason: "BLOCKED: rm -rf on worktree paths is not allowed. Use git worktree remove or worktree-manager.sh cleanup-merged instead."
  }
}'
```

**Guard 3 (line 55)** -- delete-branch with worktrees:

```bash
# Before
echo '{"decision":"block","reason":"BLOCKED: --delete-branch with active worktrees will orphan them. Remove worktrees first, then merge."}'

# After
jq -n '{
  hookSpecificOutput: {
    permissionDecision: "deny",
    permissionDecisionReason: "BLOCKED: --delete-branch with active worktrees will orphan them. Remove worktrees first, then merge."
  }
}'
```

### worktree-write-guard.sh (1 change)

This guard uses variable interpolation (`$WORKTREE_NAMES`, `$GIT_ROOT`, `$RELATIVE_PATH`). The current `echo` with escaped double quotes is fragile -- variable values containing quotes or special characters will break the JSON. Migrate to `jq -n --arg` for safe interpolation (same pattern as `pre-merge-rebase.sh`):

```bash
# Before
echo "{\"decision\":\"block\",\"reason\":\"BLOCKED: Writing to main repo checkout while worktrees exist ($WORKTREE_NAMES). Write to the worktree path instead: $GIT_ROOT/.worktrees/<name>/$RELATIVE_PATH\"}"

# After
jq -n --arg names "$WORKTREE_NAMES" --arg path "$GIT_ROOT/.worktrees/<name>/$RELATIVE_PATH" '{
  hookSpecificOutput: {
    permissionDecision: "deny",
    permissionDecisionReason: ("BLOCKED: Writing to main repo checkout while worktrees exist (" + $names + "). Write to the worktree path instead: " + $path)
  }
}'
```

## Non-goals

- Migrating `plugins/soleur/hooks/stop-hook.sh` -- Stop hooks use `decision`/`reason` (confirmed correct per Claude Code API docs)
- Changing hook logic, guard conditions, or grep patterns -- this is a pure output format migration
- Adding new guards or modifying existing guard behavior
- Updating `pre-merge-rebase.sh` -- already correct
- Adding `shebang` standardization (tracked in separate worktree `feat/standardize-shebang`)

## Acceptance Criteria

- [ ] `guardrails.sh` uses `hookSpecificOutput` with `permissionDecision: "deny"` for all 3 guards
- [ ] `worktree-write-guard.sh` uses `hookSpecificOutput` with `permissionDecision: "deny"` and `jq -n --arg` for safe variable interpolation
- [ ] No remaining `"decision":"block"` patterns in PreToolUse hooks (`.claude/hooks/guardrails.sh`, `.claude/hooks/worktree-write-guard.sh`)
- [ ] `stop-hook.sh` is NOT modified (Stop hooks use different format)
- [ ] All hooks still produce valid JSON output (no stdout corruption)
- [ ] Guard behavior is unchanged -- same conditions trigger, same messages displayed

## Test Scenarios

- Given a `git commit` command on the main branch, when guardrails.sh runs, then it outputs valid `hookSpecificOutput` JSON with `permissionDecision: "deny"` and the original reason message
- Given an `rm -rf .worktrees/feat-x` command, when guardrails.sh runs, then it outputs valid `hookSpecificOutput` JSON with `permissionDecision: "deny"`
- Given a `gh pr merge --delete-branch` command with active worktrees, when guardrails.sh runs, then it outputs valid `hookSpecificOutput` JSON with `permissionDecision: "deny"`
- Given a Write tool call targeting the main repo with active worktrees, when worktree-write-guard.sh runs, then it outputs valid `hookSpecificOutput` JSON with the worktree names and correct path interpolated safely via `jq --arg`
- Given worktree names containing special characters (quotes, ampersands), when worktree-write-guard.sh runs, then `jq --arg` escapes them correctly (bonus improvement: the old `echo` format would produce invalid JSON)
- Given a command that passes all guards, when guardrails.sh runs, then it exits 0 with no stdout (behavior unchanged)
- Given the migrated hooks, when checking for deprecated format, then `grep -E '"decision".*"block"' .claude/hooks/guardrails.sh .claude/hooks/worktree-write-guard.sh` returns zero matches

### Verification Commands

After migration, run these to confirm correctness:

```bash
# Verify no deprecated format remains in PreToolUse hooks
grep -c '"decision"' .claude/hooks/guardrails.sh .claude/hooks/worktree-write-guard.sh
# Expected: 0 for both files

# Verify new format is present
grep -c 'permissionDecision' .claude/hooks/guardrails.sh .claude/hooks/worktree-write-guard.sh
# Expected: guardrails.sh:3, worktree-write-guard.sh:1

# Verify stop-hook.sh was NOT modified
git diff plugins/soleur/hooks/stop-hook.sh
# Expected: no output (unchanged)

# Smoke-test JSON validity for guardrails.sh Guard 1
echo '{"tool_input":{"command":"git commit -m test"}}' | bash .claude/hooks/guardrails.sh | jq .
# Expected: valid JSON with hookSpecificOutput (only works when on main branch)
```

## Context

- Issue: #402
- Reference implementation: `.claude/hooks/pre-merge-rebase.sh` (PR #399)
- API docs: `hookSpecificOutput` with `permissionDecision` (allow/deny/ask) and optional `permissionDecisionReason`
- Learning: `knowledge-base/learnings/2026-03-03-pre-merge-rebase-hook-implementation.md`
- Version bump: PATCH (bug fix / consistency improvement, no new functionality)

## References

- Related issue: #402
- Reference PR: #399
- `.claude/hooks/guardrails.sh` -- 3 deprecated outputs
- `.claude/hooks/worktree-write-guard.sh` -- 1 deprecated output
- `.claude/hooks/pre-merge-rebase.sh` -- correct format (reference)
- `plugins/soleur/hooks/stop-hook.sh` -- Stop hook, different format (not in scope)
