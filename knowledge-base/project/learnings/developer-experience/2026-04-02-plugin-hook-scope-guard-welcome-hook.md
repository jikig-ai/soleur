---
module: Plugin Hooks
date: 2026-04-02
problem_type: developer_experience
component: tooling
symptoms:
  - ".claude/soleur-welcomed.local created in every project"
  - ".claude/ directory pollutes non-Soleur repositories"
root_cause: scope_issue
resolution_type: code_fix
severity: medium
tags: [plugin-hooks, scope-guard, welcome-hook, session-start]
---

# Troubleshooting: Plugin welcome hook creates files in every project

## Problem

The Soleur plugin's `welcome-hook.sh` creates `.claude/soleur-welcomed.local` in every git repository the user opens, even projects that have nothing to do with Soleur. This pollutes unrelated projects with an unexpected `.claude/` directory.

## Environment

- Module: Plugin Hooks
- Affected Component: `plugins/soleur/hooks/welcome-hook.sh`
- Date: 2026-04-02

## Symptoms

- `.claude/soleur-welcomed.local` appears in every git repository
- `.claude/` directory created in projects that don't use Soleur
- Reported by external user in GitHub issue #1383

## What Didn't Work

**Direct solution:** The problem was identified and fixed on the first attempt. The plan originally included a CLAUDE.md grep heuristic as a secondary detection method, but reviewers (DHH, Kieran, code-simplicity) unanimously recommended dropping it as unnecessary complexity.

## Session Errors

**Plan subagent output format mismatch** -- The plan+deepen subagent did not return the exact `## Session Summary` format specified in the one-shot contract. The plan file was committed to the branch but the session summary extraction required a fallback glob search.

- **Recovery:** Found the plan file via `Glob` pattern matching and proceeded normally.
- **Prevention:** One-shot subagent contracts should include a verification step that checks for the expected output format before returning, or the caller should always fall back to artifact discovery rather than relying solely on structured output parsing.

## Solution

Added a single early-exit guard to `welcome-hook.sh` after `PROJECT_ROOT` is resolved and before the sentinel file check:

**Code changes:**

```bash
# Before (broken):
PROJECT_ROOT="$GIT_ROOT"
SENTINEL_FILE="${PROJECT_ROOT}/.claude/soleur-welcomed.local"

# After (fixed):
PROJECT_ROOT="$GIT_ROOT"

# Only run in projects that have the Soleur plugin installed locally.
# Plugin hooks are global -- without this guard, every project gets a sentinel file.
[[ -d "${PROJECT_ROOT}/plugins/soleur" ]] || exit 0

SENTINEL_FILE="${PROJECT_ROOT}/.claude/soleur-welcomed.local"
```

## Why This Works

1. **Root cause:** Plugin hooks are global. Claude Code merges plugin hooks with user and project hooks when the plugin is enabled. The welcome hook had no check for whether the current project actually uses Soleur -- it ran unconditionally in every git repository.
2. **Why the fix works:** The `plugins/soleur/` directory is the canonical marker for a Soleur-enabled project. Checking for its presence before creating any artifacts ensures the hook only fires in projects that have Soleur installed locally.
3. **Why not CLAUDE.md grep:** The CLAUDE.md detection was dropped because (a) it adds grep overhead on every session start, (b) CLAUDE.md content is not a reliable indicator (users may reference `soleur:` in notes without having the plugin installed), and (c) the `plugins/soleur/` check alone solves the reported problem completely.

## Prevention

- All new plugin hooks that create project-local artifacts (files, directories) must include a project-scope guard as the first check after resolving the project root.
- The `stop-hook.sh` does not need this guard because it self-scopes via its session state file (`ralph-loop.PID.local.md`) -- the file only exists if the ralph loop was explicitly activated.
- When adding new hooks, check `hooks.json` for the event type -- `SessionStart` hooks are especially prone to scope issues since they fire on every project open.

## Related Issues

- GitHub issue: #1383
- Related prior fix: `knowledge-base/project/plans/2026-03-18-fix-welcome-hook-error-guard-plan.md` (error guard, different scope)
