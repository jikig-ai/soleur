---
title: "fix: suppress health scanner Gaps Found screen for Start Fresh projects"
type: fix
date: 2026-04-10
semver: patch
---

# fix: suppress health scanner Gaps Found screen for Start Fresh projects

## Problem Statement

After creating a brand new project via "Start Fresh", the ready-state screen shows a "Gaps Found" badge with 6 MISSING items (Package manager, Test suite, CI/CD, Linting, CLAUDE.md, Documentation) and only 2 DETECTED items (README, Knowledge Base). This is misleading because the project was just created from scratch -- it is empty by design and will naturally be missing everything.

The health scanner (`server/project-scanner.ts`) runs unconditionally after provisioning in `POST /api/repo/setup` regardless of whether the source is `start_fresh` or `connect_existing`. The health snapshot is then stored in the database and displayed by the `ReadyState` component via `data.healthSnapshot` from the status polling endpoint.

**Root cause:** The `source` parameter is already passed from the client to the server (line 333 of connect-repo/page.tsx sends `source` in the setup POST body), and the server already reads it (`body.source === "start_fresh"` in setup/route.ts), but it only uses it to suppress the welcome hook -- it does NOT use it to suppress or modify the health scanner behavior.

**Ref:** #1872 (closed -- addressed import screen and vision.md but not this symptom), PR #1771 (introduced health scanner)

## Proposed Solution

Skip storing the health snapshot for Start Fresh projects so the `ReadyState` component falls through to its null-healthSnapshot fallback UI ("Your AI Team Is Ready.").

### Server-side change (setup/route.ts)

Skip `scanProjectHealth()` when `isStartFresh` is true. The empty-project scan adds no value -- the user knows the project is empty because they just created it.

```typescript
// apps/web-platform/app/api/repo/setup/route.ts
// In the .then() handler after provisionWorkspaceWithRepo:

let healthSnapshot = null;
if (!isStartFresh) {
  try {
    healthSnapshot = scanProjectHealth(workspacePath);
  } catch (scanErr) {
    logger.error(
      { err: scanErr, userId: user.id },
      "Project health scan failed -- continuing without snapshot",
    );
    Sentry.captureException(scanErr);
  }
}
```

### Client-side change (not needed)

No client-side change required. When `healthSnapshot` is `null` in the DB, the status endpoint returns `null`, the connect-repo page does not call `setHealthSnapshot`, and `ReadyState` renders its null-fallback branch showing "Your AI Team Is Ready." with the simple project/agents summary card.

### Auto-triggered sync (no change)

The headless `/soleur:sync` still fires for Start Fresh projects. This is correct -- the sync populates the knowledge base, which is the actual onboarding value. The health snapshot is a read-only display concern that should not affect sync behavior.

## Acceptance Criteria

- [ ] Creating a project via "Start Fresh" shows the simple "Your AI Team Is Ready." ready state (no health badge, no DETECTED/MISSING signals, no recommendations)
- [ ] Creating a project via "Connect Existing" still shows the health snapshot with DETECTED/MISSING signals and category badge
- [ ] The headless `/soleur:sync` still fires for both flows
- [ ] Existing project-scanner and ready-state tests still pass
- [ ] New test: setup route does not store health_snapshot when source is "start_fresh"

## Test Scenarios

- Given a Start Fresh project creation, when setup completes, then the setup route stores `health_snapshot: null` and the ReadyState shows "Your AI Team Is Ready."
- Given a Connect Existing project setup, when setup completes, then the setup route stores a non-null health_snapshot and the ReadyState shows the health category badge
- Given a Start Fresh project creation with no `source` parameter (defensive), when setup completes, then the setup route treats it as `connect_existing` and stores a health snapshot (backward compatible)

## Context

- `apps/web-platform/app/api/repo/setup/route.ts` -- setup endpoint that runs scanner and stores snapshot
- `apps/web-platform/server/project-scanner.ts` -- `scanProjectHealth()` function
- `apps/web-platform/components/connect-repo/ready-state.tsx` -- ReadyState component with null-fallback branch
- `apps/web-platform/app/(auth)/connect-repo/page.tsx` -- connect-repo page that passes `source` and polls status
- `apps/web-platform/app/api/repo/status/route.ts` -- status endpoint that returns healthSnapshot

## References

- Issue: #1872 (original report -- closed, partially fixed by PR #1876)
- PR #1771 (introduced health scanner and revamped ready state)
- PR #1876 (fixed import screen and vision.md, did not address health snapshot)
- Issue #1808 (deferred KB overview page -- depends on health snapshot engagement measurement)
