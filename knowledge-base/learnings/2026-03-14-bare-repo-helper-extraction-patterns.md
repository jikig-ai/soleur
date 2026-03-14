# Learning: Bare repo helper extraction and shell script path arithmetic

## Problem
When extracting a shared sourceable helper (`resolve-git-root.sh`) for bare repo detection, multiple issues emerged: wrong relative paths in the plan, test regressions from implicit git context requirements, temp file naming collisions, and shell CWD corruption.

## Solution

### Path arithmetic for source statements
Count directory levels from the script to the helper. Community scripts at `plugins/soleur/skills/community/scripts/` need 3 levels up (`../../../`) to reach `plugins/soleur/scripts/`, not 4. Verify by tracing: `../` = `community/`, `../../` = `skills/`, `../../../` = `soleur/`, `../../../scripts/` = target.

### Sourceable helper design constraints
- Use `return` not `exit` (exit kills the caller)
- Never call `set` (overrides caller's options)
- Use `unset` on temp variables to avoid namespace pollution
- Include a `BASH_SOURCE[0]` guard for accidental direct execution
- Validate resolved paths exist on disk (`[[ -d "$GIT_ROOT" ]]`)

### Test regression from implicit dependencies
When hooks start sourcing a helper that calls `git rev-parse`, test harnesses that create temp directories without `git init` will fail. Always ensure test setup creates a valid git context when testing code that sources git-dependent helpers.

### Temp file naming with basename collisions
`$(basename "$file").$$` collides when the file list contains files with the same name in different directories (e.g., `AGENTS.md` and `plugins/soleur/AGENTS.md`). Use `${file//\//_}` to create unique names from the full path.

### Shell CWD corruption
Never `cd` to a temp directory in a persistent shell session without a subshell. Use `(cd "$dir" && command)` instead of `cd "$dir" && command`. A deleted CWD makes all subsequent commands fail with no recovery path.

## Key Insight
Plan-generated relative paths must be verified by tracing each `../` step. Review agents caught a path arithmetic error that the plan phase, implementation, and tests all missed. The error was in the plan itself (deepen-plan prescribed the wrong path), and was implemented verbatim. This validates the multi-agent review step as a critical safety net.

## Tags
category: shell-scripts
module: bare-repo-detection
