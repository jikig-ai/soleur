# Learning: Bare repo helper extraction and shell script path arithmetic

## Problem
When extracting a shared sourceable helper (`resolve-git-root.sh`) for bare repo detection, multiple issues emerged: wrong relative paths in the plan, test regressions from implicit git context requirements, temp file naming collisions, and shell CWD corruption.

## Solution

### Path arithmetic for source statements
Count directory levels from the script to the helper by tracing each `../` step explicitly. Community scripts at `plugins/soleur/skills/community/scripts/` need 3 levels up (`../../../`) to reach `plugins/soleur/scripts/`, not 4. Verify by tracing: `../` = `community/`, `../../` = `skills/`, `../../../` = `soleur/`, `../../../scripts/` = target. The plan prescribed the wrong path and it was implemented verbatim -- review agents caught it, but neither the plan phase, implementation, nor tests did.

### Sourceable helper design constraints
- Use `return` not `exit` (exit kills the caller when sourced)
- Never call `set` (overrides caller's shell options)
- Use `unset` on temp variables to avoid namespace pollution
- Include a `BASH_SOURCE[0]` guard for accidental direct execution
- Validate resolved paths exist on disk (`[[ -d "$GIT_ROOT" ]]`)

### Test regression from implicit dependencies
When hooks start sourcing a helper that calls `git rev-parse`, test harnesses that create temp directories without `git init` will fail. Always ensure test setup creates a valid git context when testing code that sources git-dependent helpers.

### Temp file naming with basename collisions
`$(basename "$file").$$` collides when the file list contains files with the same name in different directories (e.g., `AGENTS.md` and `plugins/soleur/AGENTS.md`). Use `${file//\//_}` to create unique names from the full path.

### Shell CWD corruption in persistent shells
Never `cd` to a temp directory in a persistent shell session without wrapping in a subshell. Use `(cd "$dir" && command)` instead of `cd "$dir" && command`. A deleted CWD makes all subsequent commands fail with no recovery path except spawning a new agent.

## Key Insight
Plan-generated relative paths must be verified by tracing each `../` step. Review agents caught a path arithmetic error that the plan phase, implementation, and tests all missed. The error was in the plan itself (deepen-plan prescribed the wrong path), and was implemented verbatim. This validates the multi-agent review step as a critical safety net for plan-level errors, not just implementation errors.

## Session Errors
1. Plan prescribed wrong path (../../../../ instead of ../../../) -- caught only by review agents
2. Plan claimed tests would pass without modification -- false, required adding git init to test setup
3. Shell CWD corrupted by cd to deleted temp dir -- required subagent to recover
4. Temp file naming collision from basename on same-named files in different dirs -- caught by review agents

## Tags
category: shell-scripts
module: bare-repo-detection
