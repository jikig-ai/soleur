# Learning: require_jq startup check consistency across shell scripts

## Problem

`discord-community.sh` was missing a `require_jq` startup check that sibling scripts `discord-setup.sh` and `x-community.sh` both had. Without the check, the script fails mid-execution at the first `jq` call with a confusing error rather than a clear "jq is not installed" message at startup.

## Solution

Added a `require_jq()` function to `discord-community.sh` that matches the exact pattern used by sibling scripts, and called it in `main()` before `validate_env`:

```bash
require_jq() {
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed." >&2
    echo "Install it: https://jqlang.github.io/jq/download/" >&2
    exit 1
  fi
}
```

Called early in `main()`:
```bash
require_jq
validate_env
```

## Key Insight

When a group of scripts share the same external dependency, all of them should fail-fast with the same startup check. Inconsistency across sibling scripts means one script gives confusing errors while others give clear ones. Code review of PRs touching a script family should check for startup-check parity.

## Tags
category: logic-errors
module: community-scripts
