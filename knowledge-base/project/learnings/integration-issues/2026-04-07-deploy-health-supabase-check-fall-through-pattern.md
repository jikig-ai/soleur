# Learning: Shell fall-through pattern breaks when adding inner conditions

## Problem

The deploy health verification loop in `web-platform-release.yml` used a fall-through pattern: if version matched, `exit 0`; otherwise fall through to the version-mismatch log message. When adding a supabase connectivity check inside the version-match block, the supabase-not-connected path no longer called `exit 0`, causing it to fall through to the version-mismatch message -- printing misleading output ("version mismatch" when the version actually matched).

## Solution

Restructured the version check from fall-through to explicit if/else:

```bash
# BEFORE (fall-through): version match -> exit 0, then mismatch message after fi
if [ "$DEPLOYED_VERSION" = "$VERSION" ]; then
  exit 0
fi
echo "version mismatch"

# AFTER (if/else): both paths explicit
if [ "$DEPLOYED_VERSION" = "$VERSION" ]; then
  # supabase check here
else
  echo "version mismatch"
fi
```

## Key Insight

When a shell `if` block relies on `exit 0` (or `continue`/`break`) to prevent fall-through to code after `fi`, adding inner conditions that don't always exit creates a silent logic bug. The fix is to restructure to if/else so both paths are explicit. This is especially important in CI workflows where misleading log output can waste debugging time.

## Session Errors

**Logic bug in initial implementation** -- First edit preserved the fall-through pattern, which would have printed misleading "version mismatch" when version matched but supabase was not connected. Caught during self-review before commit. **Prevention:** When modifying shell blocks that rely on `exit`/`continue` for flow control, trace all paths through the modified block before committing.

## Tags

category: integration-issues
module: github-actions
