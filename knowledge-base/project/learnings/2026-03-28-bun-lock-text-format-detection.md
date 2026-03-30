# Learning: bun.lock text format requires explicit detection alongside bun.lockb

## Problem

The worktree-manager.sh `install_deps()` function only checked for `bun.lockb` (the legacy binary lockfile format). Since bun 1.2, the default lockfile is `bun.lock` (a text-based format). This repo uses bun 1.3.11, so all bun lockfiles are `bun.lock`. The detection silently failed for `apps/telegram-bridge/`, printing a misleading "has package.json but no lockfile" warning.

Additionally, the plan's reference implementation used string-based command construction (`install_cmd="bun install --cwd $app_dir"`) executed via `$($install_cmd 2>&1)`. This is a shell antipattern: unquoted string expansion causes word splitting on paths with spaces.

## Solution

1. Check both formats: `[[ -f "$app_dir/bun.lockb" ]] || [[ -f "$app_dir/bun.lock" ]]`
2. Use bash arrays for command construction: `local -a install_cmd=(bun install --frozen-lockfile --cwd "$app_dir")` executed via `"${install_cmd[@]}"`

Both issues were caught by review agents (security-sentinel, code-simplicity-reviewer, architecture-strategist) before merge.

## Key Insight

When detecting tool-specific lockfiles, check the tool's version history for format changes. Bun's transition from binary (`bun.lockb`) to text (`bun.lock`) in v1.2 is not widely documented. Review agents are effective at catching these domain-specific gaps that plans miss.

## Session Errors

1. **Plan prescribed wrong lockfile name** (`bun.lockb` instead of `bun.lock`) — the plan author (deepen-plan agent) did not verify which lockfile format exists in the repo. **Prevention:** Deepen-plan should `ls` for actual lockfile names rather than assuming from documentation.
2. **Plan reference implementation used string-based command execution** — a known shell antipattern that review agents caught. **Prevention:** Constitution already covers `set -euo pipefail` but should add "use arrays for dynamic commands" as a shell convention.

## Tags

category: build-errors
module: git-worktree
