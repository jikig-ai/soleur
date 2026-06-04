---
title: "Extracting a fetch-effect into a useCallback silently drops the effect's cancellation guard"
date: 2026-06-04
category: best-practices
module: apps/web-platform/components
tags: [react, useEffect, useCallback, race-condition, stale-response, multi-agent-review]
---

# Learning: Extracting a fetch-effect into a useCallback drops the effect's cancellation guard

## Problem

While fixing the KB share popover (`apps/web-platform/components/kb/share-popover.tsx`,
PR #4947), I needed to reuse the "read existing share status" GET logic in two places:
the open-effect AND a new 409-concurrent-retry recovery path. I extracted the effect's
inner `async function checkShare()` into a `useCallback`.

The original effect carried a deliberate cancellation guard:

```tsx
useEffect(() => {
  if (!open) return;
  let cancelled = false;
  async function checkShare() {
    ...
    if (!cancelled && existing) setState({ status: "active", ... });
  }
  checkShare();
  return () => { cancelled = true; };
}, [open, documentPath]);
```

When I lifted `checkShare` out into a `useCallback([documentPath])`, the `cancelled`
flag and the effect's `return () => { cancelled = true; }` cleanup went with it — the
new effect was just `useEffect(() => { if (open) void checkShare(); }, [open, checkShare])`
with no cleanup. tsc passed, all targeted unit tests passed, the full suite passed.

The regression: the component does NOT unmount when the popover closes (only the
`open && (...)` JSX subtree unmounts), so a GET that resolves after a close→reopen or a
`documentPath` switch can call `setState` and clobber newer state — e.g. show document
A's share link while document B is open. Silent, narrow window, invisible to the tests.

## Root cause

A cancellation guard scoped to a `useEffect` body is part of the *effect's lifecycle*
(set on run, flipped on cleanup). Moving the async body into a `useCallback` strips it of
that lifecycle — the callback has no cleanup hook of its own. The extraction looks
purely mechanical ("same code, now reusable") but silently changes concurrency
semantics. `cq-ref-removal-sweep-cleanup-closures` is the ref-shaped sibling of this
class; this is the effect-cleanup-shaped version.

## Solution

Keep the callback reusable but thread the liveness signal back in via a predicate the
caller owns:

```tsx
const checkShare = useCallback(
  async (isCurrent: () => boolean = () => true): Promise<boolean> => {
    setState((s) => ({ ...s, status: "loading" }));
    try {
      const res = await fetch(...);
      if (!isCurrent()) return false;        // guard after every await
      ...
      const data = await res.json();
      if (!isCurrent()) return false;
      ...
    } catch {
      if (isCurrent()) setState((s) => ({ ...s, status: "idle" }));
      return false;
    }
  },
  [documentPath],
);

// open-effect owns its liveness flag (restores the original guard)
useEffect(() => {
  if (!open) return;
  let active = true;
  void checkShare(() => active);
  return () => { active = false; };
}, [open, checkShare]);

// synchronous caller (409 recovery) uses the default always-current predicate
```

The default `() => true` lets a synchronous user-initiated caller (which owns its own
flow) reuse the same function without ceremony, while the effect re-establishes the
exact cancellation behavior the original author coded.

## Key Insight

When you extract an `async` body out of a `useEffect` into a `useCallback`/helper,
audit for state the effect's *cleanup* was guarding (cancellation flags, AbortControllers,
interval/timeout handles, subscription teardown). The mechanical "lift and reuse" loses
the effect lifecycle; restore it by passing a liveness predicate/AbortSignal the caller
controls. tsc and happy-path tests will not catch the dropped guard — only a test that
resolves a stale response after the precondition changed, or multi-agent review, will.

Caught here by three orthogonal review agents (pattern-recognition, test-design,
git-history) concurring on the dropped guard while a fourth (code-quality) judged it
benign — the cross-reconcile triad working as designed.

## Tags
category: best-practices
module: apps/web-platform/components
