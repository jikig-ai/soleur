---
title: "fix: suppress health scanner Gaps Found screen for Start Fresh projects"
type: fix
date: 2026-04-10
semver: patch
---

# fix: suppress health scanner Gaps Found screen for Start Fresh projects

## Enhancement Summary

**Deepened on:** 2026-04-10
**Sections enhanced:** 4 (Proposed Solution, Test Scenarios, Acceptance Criteria, Edge Cases)
**Research sources:** institutional learnings (2 applied), existing test patterns (project-scanner.test.ts, ready-state.test.tsx, repo-status-health-snapshot.test.ts), codebase analysis of origin/main

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

### Research Insights

**Pattern consistency:** This follows the same conditional guard pattern used for `suppressWelcomeHook` in the same `.then()` handler. The `isStartFresh` boolean is already derived from `body.source === "start_fresh"` and used for one guard -- extending it to a second guard is minimal code surface.

**Institutional learning (start-fresh-shows-import-screen-and-vision-sync-content-20260410):** The previous fix for #1872 established the pattern of using the `source` parameter to differentiate Start Fresh behavior. This fix is a continuation of the same principle: features designed for existing-project import (health scanning, welcome hook) should be gated behind `!isStartFresh`.

**Institutional learning (post-connect-sync-implementation-patterns-20260410):** The health scanner was implemented with a defense-in-depth posture -- `try/catch` around `scanProjectHealth()` so failure never blocks provisioning. The `if (!isStartFresh)` guard wraps the same block, maintaining this posture. When `isStartFresh` is true, the `healthSnapshot` variable remains `null` (its initial value), which flows correctly through the DB update and the status endpoint.

### Client-side change (not needed)

No client-side change required. When `healthSnapshot` is `null` in the DB, the status endpoint returns `null`, the connect-repo page does not call `setHealthSnapshot`, and `ReadyState` renders its null-fallback branch showing "Your AI Team Is Ready." with the simple project/agents summary card.

### Auto-triggered sync (no change)

The headless `/soleur:sync` still fires for Start Fresh projects. This is correct -- the sync populates the knowledge base, which is the actual onboarding value. The health snapshot is a read-only display concern that should not affect sync behavior.

## Acceptance Criteria

- [ ] Creating a project via "Start Fresh" shows the simple "Your AI Team Is Ready." ready state (no health badge, no DETECTED/MISSING signals, no recommendations)
- [ ] Creating a project via "Connect Existing" still shows the health snapshot with DETECTED/MISSING signals and category badge
- [ ] The headless `/soleur:sync` still fires for both flows
- [ ] Existing project-scanner and ready-state tests still pass
- [ ] New test: setup route does not call `scanProjectHealth` when source is `"start_fresh"`
- [ ] New test: setup route stores `health_snapshot: null` in the DB update when source is `"start_fresh"`

## Test Scenarios

- Given a Start Fresh project creation, when setup completes, then the setup route stores `health_snapshot: null` and the ReadyState shows "Your AI Team Is Ready."
- Given a Connect Existing project setup, when setup completes, then the setup route stores a non-null health_snapshot and the ReadyState shows the health category badge
- Given a Start Fresh project creation with no `source` parameter (defensive), when setup completes, then the setup route treats it as `connect_existing` and stores a health snapshot (backward compatible)

### Research Insights: Test Strategy

The setup route uses a fire-and-forget `.then()` handler after `provisionWorkspaceWithRepo`, which makes direct unit testing of the health scanner guard difficult -- the route returns `{ status: "cloning" }` immediately and the provisioning runs in the background.

**Recommended approach:** Test the `scanProjectHealth` conditional at the integration level by mocking `provisionWorkspaceWithRepo` to resolve immediately, then asserting the Supabase `.update()` call includes or excludes `health_snapshot`. Follow the existing mock patterns from `apps/web-platform/test/repo-status-health-snapshot.test.ts` for Supabase chain mocking and from `apps/web-platform/test/workspace-error-handling.test.ts` for provisioning mock patterns.

**Concrete test file:** `apps/web-platform/test/setup-route-health-scanner.test.ts`

```typescript
// Test: source=start_fresh skips health scanner
// 1. Mock provisionWorkspaceWithRepo to resolve immediately
// 2. Mock scanProjectHealth to track if called
// 3. POST /api/repo/setup with { repoUrl: "...", source: "start_fresh" }
// 4. Wait for .then() handler to complete (flush promises)
// 5. Assert scanProjectHealth was NOT called
// 6. Assert Supabase update includes health_snapshot: null

// Test: source=connect_existing runs health scanner
// Same setup but with source: "connect_existing"
// Assert scanProjectHealth WAS called
// Assert Supabase update includes the scanner result
```

**Edge case tests:**

- Missing `source` field defaults to `connect_existing` behavior (health scanner runs)
- `scanProjectHealth` throwing an error still results in `health_snapshot: null` stored (existing behavior preserved)

## Edge Cases

**1. Race with auto-triggered sync:** The headless `/soleur:sync` runs after provisioning regardless of `isStartFresh`. If the sync later populates the project with files (README, package.json), the `health_snapshot` remains `null` because it was set at provisioning time. This is acceptable because:

- The health snapshot is a one-time display on the ready-state screen
- The user will have already navigated past it by the time sync completes
- Issue #1808 (KB overview page) would be the correct place for a persistent, refreshable health report

**2. Returning to `/connect-repo` after Start Fresh:** If a user navigates back to `/connect-repo` after a Start Fresh setup, the status endpoint returns `health_snapshot: null`, and the ReadyState renders the simple fallback. This is correct -- the previous fix (PR #1876) added server-side status checks that redirect to `/dashboard` for completed setups, so this path is rarely hit.

**3. Browser sessionStorage cleared:** The `source` parameter is sent in the HTTP POST body, not from sessionStorage. Even if sessionStorage is cleared (private browsing), the `source` field is set by `startSetup("start_fresh")` which is an in-memory function argument, so it survives the request correctly.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- single conditional guard in an existing server route, no UI changes, no new user-facing pages, no infrastructure changes.

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
