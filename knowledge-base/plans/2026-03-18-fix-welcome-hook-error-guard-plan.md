---
title: "fix: add error guard to welcome-hook.sh source of resolve-git-root.sh"
type: fix
date: 2026-03-18
semver: patch
---

# fix: add error guard to welcome-hook.sh source of resolve-git-root.sh

Closes #692

## Overview

`plugins/soleur/hooks/welcome-hook.sh` sources `resolve-git-root.sh` on line 6 without an `|| { exit 0; }` error guard. Under `set -euo pipefail`, if `resolve-git-root.sh` returns 1 (not inside a git repo), the hook aborts with a non-zero exit code, which blocks Claude Code session startup.

Both sibling scripts that source the same helper already have guards:
- `stop-hook.sh:14` -- `|| { exit 0; }` (allows session exit)
- `setup-ralph-loop.sh:13` -- `|| { exit 1; }` (fails explicitly)

The welcome hook should use `exit 0` (not `exit 1`) because a welcome hook must never block session startup -- silently skipping is the correct degradation behavior.

## Acceptance Criteria

- [ ] `welcome-hook.sh` line 6 has `|| { exit 0; }` guard after the `source` command
- [ ] Hook exits cleanly (exit 0) when run outside a git repo
- [ ] Existing behavior is unchanged when run inside a git repo (sentinel check, welcome JSON output)
- [ ] Shell script conventions maintained (`set -euo pipefail`, `#!/usr/bin/env bash`)

## Test Scenarios

- Given welcome-hook.sh is executed outside a git repository, when resolve-git-root.sh returns 1, then the hook exits 0 without printing errors to stdout (no JSON error in session)
- Given welcome-hook.sh is executed inside a git repo with an existing sentinel file, when sourcing succeeds, then the hook exits 0 after the sentinel check (unchanged behavior)
- Given welcome-hook.sh is executed inside a git repo without a sentinel file, when sourcing succeeds, then the hook outputs welcome JSON and creates the sentinel file (unchanged behavior)

## Implementation

### `plugins/soleur/hooks/welcome-hook.sh` (line 6)

Change:

```bash
source "$SCRIPT_DIR/../scripts/resolve-git-root.sh"
```

To:

```bash
source "$SCRIPT_DIR/../scripts/resolve-git-root.sh" || {
  # Not in a git repo -- skip welcome silently
  exit 0
}
```

This matches the exact pattern used in `stop-hook.sh:14-17`.

## Non-Goals

- Adding guards to `bsky-setup.sh`, `discord-setup.sh`, `x-setup.sh` -- these are user-invoked scripts, not session hooks; they should fail visibly when not in a git repo
- Modifying `resolve-git-root.sh` itself -- its `return 1` behavior is correct and intentional

## References

- Issue: #692 (found during review of #659)
- Pattern reference: `plugins/soleur/hooks/stop-hook.sh:14-17`
- Pattern reference: `plugins/soleur/scripts/setup-ralph-loop.sh:13-16`
- Helper: `plugins/soleur/scripts/resolve-git-root.sh:34-37` (the `return 1` path)
