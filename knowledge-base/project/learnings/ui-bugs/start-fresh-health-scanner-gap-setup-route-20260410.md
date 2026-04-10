---
module: Web Platform
date: 2026-04-10
problem_type: ui_bug
component: service_object
symptoms:
  - "Start Fresh projects show Gaps Found screen with 6 MISSING items"
  - "ReadyState renders health snapshot instead of simple ready screen"
root_cause: logic_error
resolution_type: code_fix
severity: medium
tags: [health-scanner, start-fresh, onboarding, ready-state]
---

# Troubleshooting: Start Fresh projects show misleading "Gaps Found" health snapshot

## Problem

After creating a project via "Start Fresh", the ready-state screen shows a "Gaps Found" badge with 6 MISSING items (Package manager, Test suite, CI/CD, Linting, CLAUDE.md, Documentation) instead of the simple "Your AI Team Is Ready." screen. The health scanner runs on an empty repo and correctly reports gaps — but those gaps are expected and misleading for a brand-new project.

## Environment

- Module: Web Platform — setup route and ReadyState component
- Affected Component: `apps/web-platform/app/api/repo/setup/route.ts` (server), `apps/web-platform/components/connect-repo/ready-state.tsx` (client)
- Date: 2026-04-10

## Symptoms

- After "Create Project" via Start Fresh, UI shows "Gaps Found" badge
- 6 MISSING items displayed: Package manager, Test suite, CI/CD, Linting, CLAUDE.md, Documentation
- Only 2 DETECTED items: README, Knowledge Base
- Happens on all new Start Fresh projects, not just recreated ones

## What Didn't Work

**Direct solution:** The problem was identified and fixed on the first attempt. The `isStartFresh` boolean already existed (derived from `body.source === "start_fresh"`) and was used for `suppressWelcomeHook`. The fix extended the same pattern to gate the health scanner.

## Session Errors

**Wrong path for setup-ralph-loop.sh**
- **Recovery:** Globbed for the correct path (`plugins/soleur/scripts/setup-ralph-loop.sh`)
- **Prevention:** One-shot skill should use `$SCRIPT_DIR`-relative paths instead of hardcoded paths

**CWD confusion during test run — `cd apps/web-platform` failed**
- **Recovery:** Ran vitest without the cd prefix since CWD was already correct
- **Prevention:** Use absolute paths or verify CWD before cd commands

**Transient git exit 128 during parallel bash calls**
- **Recovery:** Retried the command successfully
- **Prevention:** Avoid parallel git commands on the same worktree

## Solution

Wrapped `scanProjectHealth()` in an `if (!isStartFresh)` guard in the setup route's post-provision `.then()` handler.

**Code changes:**

```typescript
// Before (broken):
let healthSnapshot = null;
try {
  healthSnapshot = scanProjectHealth(workspacePath);
} catch (scanErr) {
  // error handling...
}

// After (fixed):
let healthSnapshot = null;
if (!isStartFresh) {
  try {
    healthSnapshot = scanProjectHealth(workspacePath);
  } catch (scanErr) {
    // error handling...
  }
}
```

When `isStartFresh` is true, `healthSnapshot` stays `null`. The null value flows through the DB update and status endpoint. The `ReadyState` component already had a null-fallback branch rendering "Your AI Team Is Ready."

## Why This Works

1. **Root cause:** `scanProjectHealth()` ran unconditionally after provisioning, regardless of whether the project was Start Fresh (empty by design) or Connect Existing (has real code to scan).
2. **Why the fix works:** The `isStartFresh` guard skips the scanner for empty repos. The `healthSnapshot` variable stays at its initial `null` value, which is a valid state throughout the entire data flow (DB column defaults to NULL, status endpoint coalesces to null, ReadyState has explicit null guard).
3. **Pattern consistency:** This follows the same `isStartFresh` gating pattern already used for `suppressWelcomeHook` in the same handler. Both are features designed for existing-project import that should not run for Start Fresh flows.

## Prevention

- When adding features to shared onboarding endpoints that serve multiple flows (Start Fresh vs Connect Existing), gate display-only features behind flow-type checks
- The `source` parameter infrastructure exists — use it for any flow-specific behavior
- ReadyState's null-fallback branch should remain the default path for any flow where the health scanner is irrelevant

## Related Issues

- See also: [post-connect-sync-implementation-patterns](../2026-04-10-post-connect-sync-implementation-patterns.md) — established the `source` parameter infrastructure
- GitHub: #1872 (original report), PR #1876 (partial fix for import screen), PR #1771 (introduced health scanner)
