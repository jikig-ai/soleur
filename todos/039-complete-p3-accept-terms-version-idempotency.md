---
status: pending
priority: p3
issue_id: 039
tags: [code-review, quality, legal]
dependencies: []
---

# Accept-terms API: add version-scoped idempotency guard

## Problem Statement

The accept-terms API (`POST /api/accept-terms`) unconditionally overwrites `tc_accepted_at` and `tc_accepted_version` on every call. A user who double-clicks or a buggy client could churn the `tc_accepted_at` timestamp without changing the version. The timestamp would reflect the last call, not the first acceptance of the current version.

Found during security review of PR #952 (T&C version tracking).

## Findings

- **File:** `apps/web-platform/app/api/accept-terms/route.ts`
- The old `.is("tc_accepted_at", null)` guard was correctly removed for version tracking (re-acceptance on version bump needs to overwrite). But no replacement guard was added.
- Impact is low: the middleware only redirects users with stale versions, so the API is only reachable when re-acceptance is needed.

## Proposed Solutions

**Option A: Skip write if already on current version**
Add a pre-check: if `tc_accepted_version === TC_VERSION`, return success without updating.
- Pros: Preserves timestamp integrity, saves a DB write
- Cons: Adds one read before the write
- Effort: Small

## Acceptance Criteria

- [ ] `POST /api/accept-terms` is a no-op when user already has `tc_accepted_version === TC_VERSION`
- [ ] Re-acceptance after version bump still works

## Work Log

- 2026-03-20: Created during code review of PR #952
