---
title: "fix: update health endpoint comment to reflect deploy verification gating"
type: fix
date: 2026-04-07
---

# fix: Update health endpoint comment to reflect deploy verification gating

## Problem

The comment in `apps/web-platform/server/index.ts` (lines 29-32) says:

```typescript
// Always return 200 — the server is running and serving traffic.
// Supabase/Sentry status is informational; a degraded dependency should not
// cause deploy verification or load balancer health checks to fail.
```

This is inaccurate since PR #1706 introduced a Supabase connectivity gate in `web-platform-release.yml`. The CI deploy verification workflow now explicitly checks `supabase == "connected"` and fails the deploy if Supabase is not reachable (lines 108-126 of the workflow). A future maintainer reading the server comment might conclude Supabase status is purely advisory and remove the workflow check.

The comment is correct that HTTP 200 is always returned (for load balancer compatibility), but wrong that Supabase status is purely informational -- CI deploy verification gates on it.

## Proposed Fix

Update the comment block at lines 30-32 in `apps/web-platform/server/index.ts` to clarify the dual-purpose design:

1. HTTP 200 is always returned for load balancer probes (unchanged behavior)
2. CI deploy verification (`web-platform-release.yml`) uses the JSON response body to gate on version match and Supabase connectivity

Suggested replacement comment:

```typescript
// Always return 200 for load balancer probes.
// CI deploy verification (web-platform-release.yml) reads the response body
// to gate on version match and supabase connectivity.
```

## Acceptance Criteria

- [x] Comment in `apps/web-platform/server/index.ts` accurately reflects that deploy verification gates on supabase status
- [x] Comment still explains why HTTP 200 is always returned (load balancer compatibility)
- [x] No code logic changes -- comment-only update
- [x] Sentry mention removed from the comment (Sentry status is not gated by CI; it remains purely informational in the response body)

## Test Scenarios

- Given the updated comment, when a developer reads lines 29-32 of `server/index.ts`, then the comment accurately describes the dual-purpose design (HTTP 200 for LB, response body for CI gating)
- Given the change is comment-only, when `npx tsc --noEmit` runs, then TypeScript compilation succeeds with no errors

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- comment-only code change.

## Context

- **Source:** PR #1706 review finding, tracked as issue #1709
- **Affected file:** `apps/web-platform/server/index.ts:29-32`
- **Related workflow:** `.github/workflows/web-platform-release.yml:108-126`
- **Related module:** `apps/web-platform/server/health.ts` (builds the JSON response with `supabase: "connected" | "error"`)
- **Effort:** Trivial -- single comment block update

## References

- Issue: #1709
- PR that introduced supabase gating: #1706
