---
title: "fix: ralph-loop stop hook fires awk error when no loop is active"
type: fix
date: 2026-03-09
semver: patch
---

# fix: ralph-loop stop hook fires awk error when no loop is active

## Overview

The ralph-loop stop hook (`plugins/soleur/hooks/stop-hook.sh`) produces an awk error and enters an infinite exit-blocking loop when no ralph loop is active. The relative path `.claude/ralph-loop.local.md` does not resolve correctly when the hook is invoked from a worktree directory, and `set -euo pipefail` causes the script to abort with a non-zero exit before reaching the file-existence guard on line 18.

## Problem Statement

Three interacting defects:

1. **Relative path resolution**: The stop hook uses `RALPH_STATE_FILE=".claude/ralph-loop.local.md"` (line 16) -- a bare relative path. Claude Code invokes hooks with CWD set to the project root, but in worktree scenarios the CWD may be the worktree directory (`.worktrees/feat-*`), not the repo root where `.claude/` lives. The welcome hook (`welcome-hook.sh`) already solves this with `git rev-parse --show-toplevel`, but the stop hook does not.

2. **`set -euo pipefail` + stdin read**: Line 13 (`HOOK_INPUT=$(cat)`) reads hook input from stdin. If the stop hook fires in a context where stdin is empty or closed (e.g., rapid session teardown), `cat` returns immediately with an empty string, which is fine. But the subsequent `jq -r '.transcript_path'` on line 66 fails on empty input, producing a non-zero exit that `set -e` catches, aborting the script before the `exit 0` on line 20. This abort causes Claude Code to interpret the hook as having "blocked" the stop, re-firing it in a loop.

3. **No early-exit on missing file before stdin read**: The file-existence check (line 18) runs after `HOOK_INPUT=$(cat)` (line 13). If the state file does not exist, the script still consumes stdin before exiting. This is not a bug per se, but reordering the check before the stdin read is more robust -- it avoids any stdin-related failures when the hook has nothing to do.

## Root Cause Analysis

The stop hook was ported from the upstream ralph-loop plugin which assumed a single-project-root working directory. The Soleur plugin operates in a worktree model where CWD varies. The welcome hook was updated with `git rev-parse --show-toplevel` but the stop hook was not.

The `set -euo pipefail` strict mode (correctly used per project conventions) amplifies the problem: any error in the pipeline before `exit 0` causes a non-zero exit, which the stop hook API interprets as "hook wants to block exit," re-triggering the hook.

## Proposed Solution

### Fix 1: Resolve project root (like welcome-hook.sh)

Add the same `PROJECT_ROOT` resolution pattern used in `welcome-hook.sh`:

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."
RALPH_STATE_FILE="${PROJECT_ROOT}/.claude/ralph-loop.local.md"
```

This ensures the state file path resolves correctly regardless of CWD.

### Fix 2: Move file-existence check before stdin read

Reorder the script so the `if [[ ! -f "$RALPH_STATE_FILE" ]]` check runs before `HOOK_INPUT=$(cat)`. When no ralph loop is active, the hook exits immediately without touching stdin, jq, or awk.

```bash
# Resolve project root
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."
RALPH_STATE_FILE="${PROJECT_ROOT}/.claude/ralph-loop.local.md"

# Check if ralph-loop is active BEFORE reading stdin
if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  exit 0
fi

# Only read hook input if we need it
HOOK_INPUT=$(cat)
```

### Fix 3: Apply PROJECT_ROOT to all file operations

The setup script (`plugins/soleur/scripts/setup-ralph-loop.sh`) also uses bare relative paths for `.claude/ralph-loop.local.md`. Apply the same `git rev-parse --show-toplevel` pattern there for consistency, so the state file is always created at the repo root regardless of CWD.

## Non-Goals

- Changing the ralph-loop state file format or location
- Adding new ralph-loop features
- Modifying the hook API contract

## Acceptance Criteria

- [ ] When `.claude/ralph-loop.local.md` does not exist, the stop hook exits 0 cleanly on the first invocation with no awk/jq errors (`plugins/soleur/hooks/stop-hook.sh`)
- [ ] The stop hook resolves the state file path using `git rev-parse --show-toplevel`, not a bare relative path (`plugins/soleur/hooks/stop-hook.sh`)
- [ ] The file-existence check runs before `HOOK_INPUT=$(cat)` so no stdin is consumed when no loop is active (`plugins/soleur/hooks/stop-hook.sh`)
- [ ] The setup script also resolves project root for state file creation consistency (`plugins/soleur/scripts/setup-ralph-loop.sh`)
- [ ] All existing tests in `plugins/soleur/test/ralph-loop-stuck-detection.test.sh` continue to pass
- [ ] New test: hook exits 0 from a non-root CWD when state file does not exist
- [ ] New test: hook exits 0 from a non-root CWD when state file exists at the repo root

## Test Scenarios

- Given no `.claude/ralph-loop.local.md` exists, when the stop hook fires from the repo root, then it exits 0 with no output on stdout or stderr
- Given no `.claude/ralph-loop.local.md` exists, when the stop hook fires from a subdirectory (simulating worktree CWD), then it exits 0 with no output
- Given a valid state file at `<project-root>/.claude/ralph-loop.local.md`, when the stop hook fires from a subdirectory, then it finds the file and processes normally (blocks exit, continues loop)
- Given no state file exists, when the stop hook fires with empty stdin, then it exits 0 (no crash from jq parsing empty input)
- Given all 15 existing tests, when run after the fix, then all pass unchanged

## MVP

### plugins/soleur/hooks/stop-hook.sh (lines 10-24, reordered)

```bash
set -euo pipefail

# Resolve project root (worktree-safe)
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."
RALPH_STATE_FILE="${PROJECT_ROOT}/.claude/ralph-loop.local.md"

# Check if ralph-loop is active BEFORE reading stdin
if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  # No active loop -- allow exit
  exit 0
fi

# Read hook input from stdin (advanced stop hook API)
HOOK_INPUT=$(cat)
```

### plugins/soleur/scripts/setup-ralph-loop.sh (add near top)

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."
# ... then use ${PROJECT_ROOT}/.claude/ for mkdir and state file creation
```

## References

- GitHub issue: #464
- Stop hook: `plugins/soleur/hooks/stop-hook.sh`
- Setup script: `plugins/soleur/scripts/setup-ralph-loop.sh`
- Welcome hook (reference pattern): `plugins/soleur/hooks/welcome-hook.sh`
- Existing tests: `plugins/soleur/test/ralph-loop-stuck-detection.test.sh`
- Learning: `knowledge-base/learnings/2026-03-05-awk-scoping-yaml-frontmatter-shell.md`
- Learning: `knowledge-base/learnings/2026-03-05-ralph-loop-stuck-detection-shell-counter.md`
- Prior PR: #456 (scoped frontmatter parser)
- Prior PR: #454 (stuck detection)
