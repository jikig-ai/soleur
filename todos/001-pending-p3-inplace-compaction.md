---
status: done
priority: p3
tags: [performance, rate-limiting]
file: apps/web-platform/server/rate-limiter.ts
---

# Replace Array.filter with in-place compaction in SlidingWindowCounter

## Problem

`isAllowed()` creates a new array via `Array.filter()` on every call. Under sustained high request rates, this creates short-lived arrays that feed V8 young-gen GC.

## Fix

Replace `timestamps.filter(t => t > cutoff)` with a forward-write pointer that compacts in place:

```typescript
let write = 0;
for (let i = 0; i < timestamps.length; i++) {
  if (timestamps[i] > cutoff) {
    timestamps[write++] = timestamps[i];
  }
}
timestamps.length = write;
```

Apply the same pattern to `prune()`.

## Impact

Eliminates per-call array allocation on the hot path. Marginal at current scale but good practice.

## Source

Performance oracle review of PR #1283.
