---
status: pending
priority: p3
issue_id: 040
tags: [code-review, quality]
dependencies: []
---

# Extract getRedirectDestination to shared module

## Problem Statement

The "has valid API key → dashboard or setup-key" redirect logic is duplicated between the accept-terms API route (extracted as `getRedirectDestination`) and the callback route (inlined). The callback route also silently swallows the API key query error.

Found during code quality review of PR #952.

## Findings

- **Duplicate:** `apps/web-platform/app/api/accept-terms/route.ts:6-19` vs `apps/web-platform/app/(auth)/callback/route.ts:37-48`
- **Missing error handling:** Callback destructures `{ data: keys }` and discards `error`. On DB failure, `keys` is null → user silently redirected to `/setup-key`.

## Proposed Solutions

**Option A: Extract to `lib/auth/redirect-destination.ts`**
- Pros: Single source of truth, proper error handling in one place
- Cons: New file
- Effort: Small

## Acceptance Criteria

- [ ] Redirect logic in a shared module imported by both routes
- [ ] API key query errors are logged in both paths

## Work Log

- 2026-03-20: Created during code review of PR #952
