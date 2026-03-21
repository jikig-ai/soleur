# Learning: T&C enforcement must be consistent across all surfaces

## Problem

When adding T&C version tracking to the middleware, the ws-handler was initially left checking `tc_accepted_at` (null check) while the middleware checked `tc_accepted_version !== TC_VERSION` (exact match). This created an enforcement gap: a user who accepted T&C v1.0.0 could establish new WebSocket connections after a version bump because their `tc_accepted_at` was non-null, even though their version was stale.

The plan explicitly declared ws-handler enforcement as a "non-goal," but the architecture review correctly identified it as a P0 fix -- enforcement surface consistency is not optional for compliance features.

## Solution

Update all three enforcement surfaces (middleware, callback, ws-handler) to use the same version comparison:

```typescript
// All surfaces use the same pattern:
import { TC_VERSION } from "@/lib/legal/tc-version";
// ...
if (userRow?.tc_accepted_version !== TC_VERSION) {
  // redirect (middleware/callback) or close socket (ws-handler)
}
```

The fix was 3 lines in ws-handler.ts -- trivial to implement but easy to miss when the plan says "non-goal."

## Key Insight

When a plan declares an enforcement surface as "non-goal," challenge that decision during implementation. If the feature is a compliance gate (GDPR, legal, security), all enforcement surfaces must be consistent. A plan's scope optimization should not create enforcement gaps. The review agent caught this -- multi-agent review is valuable precisely for these cross-cutting consistency checks.

Also: when adding a column check to one query, grep for all queries on the same table column to find other enforcement surfaces that need updating.

## Session Errors

1. Plan prescribed metadata-based trigger approach, but PR #940 had already switched to server-side acceptance -- implementation correctly deviated from plan
2. Vitest `@/` path alias not configured -- use relative imports in test files
3. `soleur:plan_review` skill doesn't exist -- referenced in plan template but not implemented

## Tags

category: architecture
module: web-platform
