---
title: "chore: standardize shebang to #!/usr/bin/env bash across all scripts"
type: chore
date: 2026-03-03
---

# chore: standardize shebang to #!/usr/bin/env bash across all scripts

Standardize all shell scripts to use `#!/usr/bin/env bash` instead of `#!/bin/bash`, conforming to the constitution convention. This was flagged during code review of PR #399 and tracked as issue #403.

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
- [ ] `set -euo pipefail` gap assessed for `worktree-manager.sh` and `check_setup.sh`
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

Two scripts use `set -e` alone:

**`worktree-manager.sh`**: Uses `set -e` only. The script uses unquoted variable expansions and conditional patterns that may break with `-u` (unset variable errors). A full `-uo pipefail` upgrade should be assessed but is a separate concern from the shebang fix. If `-uo pipefail` would require refactoring variable handling, file a follow-up issue rather than blocking this PR.

**`check_setup.sh`**: Uses `set -e` only. Similar assessment needed. The script checks for `rclone` installation and may have patterns incompatible with strict `-u` mode.

Recommendation: Fix the shebang in this PR. If `-uo pipefail` upgrade requires non-trivial refactoring, file a separate issue to avoid scope creep.

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

### `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (line 1)

```bash
#!/usr/bin/env bash
```

### `plugins/soleur/skills/rclone/scripts/check_setup.sh` (line 1)

```bash
#!/usr/bin/env bash
```

## SpecFlow Analysis

This is a mechanical find-and-replace with no conditional logic, no CI workflow changes, and no edge cases beyond validating that the updated scripts still execute. SpecFlow adds no value for this change type.

## Non-goals

- Upgrading `set -e` to `set -euo pipefail` in scripts that currently lack it (separate issue if needed)
- Changing shebangs in non-shell files or documentation code blocks
- Modifying any script logic or behavior

## References

- Issue: #403
- Source PR: #399 (code review finding)
- Constitution convention: `knowledge-base/overview/constitution.md` line 23
- Conforming example: `.claude/hooks/pre-merge-rebase.sh` (uses `#!/usr/bin/env bash`)
