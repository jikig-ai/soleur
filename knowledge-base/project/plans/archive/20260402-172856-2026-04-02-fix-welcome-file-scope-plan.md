---
title: "fix: scope welcome-hook sentinel file to Soleur projects only"
type: fix
date: 2026-04-02
semver: patch
---

# fix: scope welcome-hook sentinel file to Soleur projects only

Closes #1383

## Overview

The Soleur plugin's `welcome-hook.sh` runs on every `SessionStart` event across all projects. It creates `.claude/soleur-welcomed.local` in whichever git repository the user happens to be in -- even projects that have nothing to do with Soleur. This pollutes unrelated projects with an unexpected `.claude/` directory and sentinel file.

## Problem Statement

The welcome hook (`plugins/soleur/hooks/welcome-hook.sh`) is registered as a `SessionStart` hook in `hooks.json`. When the Soleur plugin is installed at user scope, Claude Code merges plugin hooks with user/project hooks (per the plugin spec: "Plugin hooks are merged with user and project hooks when the plugin is enabled"). This means the hook fires in **every** project.

The hook's current logic:

1. Resolves the git root of the current project via `resolve-git-root.sh`
2. Checks if `.claude/soleur-welcomed.local` exists -- if so, exits
3. Creates `.claude/` directory and sentinel file in the project root
4. Outputs welcome JSON

There is no check to determine whether the current project is actually a Soleur project (i.e., has the Soleur plugin installed locally or uses Soleur in any way). The sentinel file and `.claude/` directory are created unconditionally.

## Proposed Solution

Add a guard condition to `welcome-hook.sh` that checks whether the current project is a Soleur project before creating the sentinel file and emitting the welcome message. The check should verify the presence of the Soleur plugin directory structure.

### Detection Strategy

A project is a "Soleur project" if any of the following are true:

1. **Local plugin directory exists:** `plugins/soleur/` exists in the project root (the plugin is part of the repo -- development scenario)
2. **CLAUDE.md references Soleur:** The project's `CLAUDE.md` contains a reference to Soleur skills, agents, or commands (installed plugin scenario -- users who followed setup instructions)

The simplest and most reliable check is option 1: test for `plugins/soleur/` or a Soleur-specific marker file. However, this only covers the development/monorepo case. For external users who installed the plugin via marketplace, the plugin fires from the cached install, not from the project tree.

The key insight: the welcome message is only useful when the user is in a project that uses Soleur. If the user opens a random project, they do not need to be told about `/soleur:sync` or `/soleur:help`. The welcome is contextually irrelevant.

**Recommended approach:** Use `CLAUDE_PLUGIN_ROOT` (available to hook scripts as the expanded path) to check if the plugin is installed in the current project's context. If the project root differs from the plugin's expected context, skip the welcome. Alternatively, check for a simpler heuristic:

- If `$PROJECT_ROOT/CLAUDE.md` exists and references `soleur:` or `@AGENTS.md` patterns typical of Soleur projects, this is a Soleur project.
- If `$PROJECT_ROOT/plugins/soleur/` exists, this is the Soleur monorepo.
- Otherwise, skip.

This two-condition check is lightweight (two filesystem tests + one grep) and avoids false positives.

### Implementation

#### `plugins/soleur/hooks/welcome-hook.sh`

After `PROJECT_ROOT` is set (line 10) and before the sentinel check (line 13), add:

```bash
# --- Soleur Project Check ---
# Only create sentinel and emit welcome in projects that use Soleur.
# Without this guard, the hook runs in every project (plugin hooks are global).
is_soleur_project=false
if [[ -d "${PROJECT_ROOT}/plugins/soleur" ]]; then
  is_soleur_project=true
elif [[ -f "${PROJECT_ROOT}/CLAUDE.md" ]] && grep -q 'soleur:' "${PROJECT_ROOT}/CLAUDE.md" 2>/dev/null; then
  is_soleur_project=true
fi

if [[ "$is_soleur_project" == "false" ]]; then
  exit 0
fi
```

This block exits cleanly before the sentinel check for non-Soleur projects, preventing both the `.claude/` directory creation and the sentinel file.

### Files Changed

| File | Change |
|------|--------|
| `plugins/soleur/hooks/welcome-hook.sh` | Add Soleur project detection guard after line 10 |

## Acceptance Criteria

- [x] Running the welcome hook in a non-Soleur git repository does NOT create `.claude/` directory or `soleur-welcomed.local` file
- [x] Running the welcome hook in a project with `plugins/soleur/` directory still shows the welcome message on first run
- [ ] Running the welcome hook in a project whose `CLAUDE.md` references `soleur:` commands still shows the welcome message on first run
- [x] The sentinel file check (`[[ -f "$SENTINEL_FILE" ]]`) still prevents repeat welcomes in Soleur projects
- [x] The hook exits 0 (clean) in all cases -- never blocks session startup

## Test Scenarios

- Given a git repository with no `plugins/soleur/` directory and no `CLAUDE.md`, when the welcome hook runs, then it exits 0 without creating `.claude/soleur-welcomed.local`
- Given a git repository with a `CLAUDE.md` that does NOT reference `soleur:`, when the welcome hook runs, then it exits 0 without creating `.claude/soleur-welcomed.local`
- Given a git repository with `plugins/soleur/` directory, when the welcome hook runs for the first time, then it creates `.claude/soleur-welcomed.local` and outputs the welcome JSON
- Given a git repository whose `CLAUDE.md` contains `soleur:help`, when the welcome hook runs for the first time, then it creates `.claude/soleur-welcomed.local` and outputs the welcome JSON
- Given a Soleur project where `.claude/soleur-welcomed.local` already exists, when the welcome hook runs, then it exits 0 immediately (no duplicate output)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

- The welcome hook was introduced in the onboarding blockers fix (#692 plan at `knowledge-base/project/plans/2026-03-18-fix-welcome-hook-error-guard-plan.md`)
- The hook runs via `hooks.json` `SessionStart` event with `startup` matcher
- `CLAUDE_PLUGIN_ROOT` is expanded by the plugin loader, not available as a shell variable inside the hook script itself -- the hook receives it as part of the command path but cannot read it at runtime
- The `resolve-git-root.sh` helper correctly resolves to the user's current project root, not the plugin's root
- The `.gitignore` in the Soleur repo already ignores `.claude/soleur-welcomed.local` (line 32)

## References

- Issue: #1383
- Hook registration: `plugins/soleur/hooks/hooks.json:6-11`
- Hook script: `plugins/soleur/hooks/welcome-hook.sh`
- Git root resolver: `plugins/soleur/scripts/resolve-git-root.sh`
- Related prior fix: `knowledge-base/project/plans/2026-03-18-fix-welcome-hook-error-guard-plan.md` (error guard, different scope)
- Plugin hook spec: "Plugin hooks are merged with user and project hooks when the plugin is enabled" (`knowledge-base/project/specs/external/claude-code.md:45`)
