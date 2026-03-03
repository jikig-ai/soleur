---
title: "chore: standardize shebang to #!/usr/bin/env bash across all scripts"
type: chore
date: 2026-03-03
---

# chore: standardize shebang to #!/usr/bin/env bash across all scripts

Standardize all shell scripts to use `#!/usr/bin/env bash` instead of `#!/bin/bash`, conforming to the constitution convention. This was flagged during code review of PR #399 and tracked as issue #403.

## Enhancement Summary

**Deepened on:** 2026-03-03
**Sections enhanced:** 1 (`set -euo pipefail` gap analysis)
**Method:** Source-level audit of `worktree-manager.sh` (624 lines) and `check_setup.sh` (61 lines)

### Key Improvements

1. **Scope expanded from shebang-only to full shell convention compliance** -- source audit confirmed both scripts with `set -e` are compatible with `set -euo pipefail`, so the upgrade is included in this PR instead of deferred
2. **Drive-by fix for bracket convention** -- `check_setup.sh` line 27 uses `[ ]` instead of `[[ ]]`, violating constitution convention; fixed alongside other changes
3. **Concrete evidence replaces speculative assessment** -- original plan hedged on `-uo pipefail` safety; deepened plan includes line-by-line audit results proving compatibility

## Problem Statement

The constitution (`knowledge-base/overview/constitution.md`, line 23) requires:

> Shell scripts must use `#!/usr/bin/env bash` shebang and declare `set -euo pipefail` at the top

Four scripts currently use `#!/bin/bash`:

| File | Shebang | `set` flags | Notes |
|------|---------|-------------|-------|
| `.claude/hooks/guardrails.sh` | `#!/bin/bash` | `set -euo pipefail` | Shebang only |
| `.claude/hooks/worktree-write-guard.sh` | `#!/bin/bash` | `set -euo pipefail` | Shebang only |
| `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` | `#!/bin/bash` | `set -e` | Shebang + missing `-uo pipefail` |
| `plugins/soleur/skills/rclone/scripts/check_setup.sh` | `#!/bin/bash` | `set -e` | Shebang + missing `-uo pipefail` |

The issue #403 specifically calls out the first two hooks. The audit found two additional scripts with the same problem.

## Proposed Solution

Replace `#!/bin/bash` with `#!/usr/bin/env bash` in all four files. For the two scripts missing `-uo pipefail`, evaluate whether upgrading is safe (unset variable traps, pipe behavior) or document why not.

## Acceptance Criteria

- [ ] All `.sh` files use `#!/usr/bin/env bash` shebang
- [ ] `.claude/hooks/guardrails.sh` shebang updated
- [ ] `.claude/hooks/worktree-write-guard.sh` shebang updated
- [ ] `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` shebang updated
- [ ] `plugins/soleur/skills/rclone/scripts/check_setup.sh` shebang updated
- [ ] `worktree-manager.sh` upgraded from `set -e` to `set -euo pipefail`
- [ ] `check_setup.sh` upgraded from `set -e` to `set -euo pipefail`
- [ ] `check_setup.sh` line 27: `[ -z "$REMOTES" ]` changed to `[[ -z "$REMOTES" ]]`
- [ ] `grep -r '#!/bin/bash' --include='*.sh'` returns zero results
- [ ] Existing tests pass (`bun test`)

## Test Scenarios

- Given any `.sh` file in the repo, when inspecting its first line, then it reads `#!/usr/bin/env bash`
- Given `guardrails.sh` with updated shebang, when a guarded command is executed (e.g., `git commit` on main), then the hook still blocks it correctly
- Given `worktree-write-guard.sh` with updated shebang, when a write to main repo is attempted with active worktrees, then the hook still blocks it
- Given `worktree-manager.sh` with updated shebang, when running `cleanup-merged`, then the script executes correctly
- Given `check_setup.sh` with updated shebang, when running the rclone setup check, then the script executes correctly

## Context

### Why `#!/usr/bin/env bash`

`#!/usr/bin/env bash` is the portable shebang. It locates `bash` via `$PATH` rather than hardcoding `/bin/bash`, which does not exist on some systems (NixOS, certain macOS Homebrew setups, FreeBSD). The constitution codifies this convention.

### `set -euo pipefail` gap analysis

Two scripts use `set -e` alone. Source-level audit of both scripts confirms they are **compatible with `-uo pipefail`** and should be upgraded in this PR alongside the shebang fix.

**`worktree-manager.sh`** (624 lines): All optional positional parameters use `${N:-default}` syntax (lines 72, 129, 543), which is safe under `nounset`. Associative array lookups use `${branch_to_worktree[$branch]:-}` (line 401). `|| true` guards on `git pull` (lines 106, 157) prevent `pipefail` failures. No bare `$1`/`$2` references without defaults. **Verdict: safe to upgrade to `set -euo pipefail`.**

**`check_setup.sh`** (61 lines): `REMOTES` is always assigned (line 25, with `|| true`). The `for remote in $REMOTES` loop (line 50) handles empty strings correctly (loop body is never entered). No unset variable references. **Verdict: safe to upgrade to `set -euo pipefail`.** Also note: line 27 uses `[ -z "$REMOTES" ]` instead of `[[ -z "$REMOTES" ]]`, which violates the constitution's double-bracket convention -- fix as a drive-by.

**Recommendation: Upgrade both scripts to `set -euo pipefail` in this PR.** The audit confirms zero incompatibilities, so deferring to a follow-up issue would be unnecessary process overhead for a safe change. Also fix the `[ ]` to `[[ ]]` in `check_setup.sh` line 27.

### Version bump

This touches `plugins/soleur/` files (`skills/git-worktree/scripts/worktree-manager.sh`, `skills/rclone/scripts/check_setup.sh`), so a PATCH version bump is required per the plugin versioning rules.

## MVP

### `.claude/hooks/guardrails.sh` (line 1)

```bash
#!/usr/bin/env bash
```

### `.claude/hooks/worktree-write-guard.sh` (line 1)

```bash
#!/usr/bin/env bash
```

### `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (lines 1, 7)

```bash
#!/usr/bin/env bash
```

```bash
set -euo pipefail
```

### `plugins/soleur/skills/rclone/scripts/check_setup.sh` (lines 1, 4, 27)

```bash
#!/usr/bin/env bash
```

```bash
set -euo pipefail
```

```bash
# Line 27: fix bracket convention
if [[ -z "$REMOTES" ]]; then
```

## SpecFlow Analysis

This is a mechanical find-and-replace with no conditional logic, no CI workflow changes, and no edge cases beyond validating that the updated scripts still execute. SpecFlow adds no value for this change type.

## Non-goals

- Changing shebangs in non-shell files or documentation code blocks
- Modifying any script logic or behavior beyond the shebang, `set` flags, and bracket convention fixes

## References

- Issue: #403
- Source PR: #399 (code review finding)
- Constitution convention: `knowledge-base/overview/constitution.md` line 23
- Conforming example: `.claude/hooks/pre-merge-rebase.sh` (uses `#!/usr/bin/env bash`)
