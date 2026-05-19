---
title: Optimistic local-state ∧ server-prop conjunction needs router.refresh() on success
date: 2026-05-19
category: ui-bugs
tags: [next-app-router, optimistic-ui, router-refresh, react-server-components, pessimistic-ui-invariant]
issue: 4048
pr: 4059
related:
  - 2026-04-19-enoent-on-optional-mount-should-not-alarm.md
---

## Problem

A Next 15 App Router client component (`apps/web-platform/components/scope-grants/scope-grant-row.tsx`, shipped by PR-G #3984) derived its headline status paragraph from `committedTier && grantedAt` where:

- `committedTier` was **local state**, updated optimistically inside `onGrant` success after `setCommittedTier(selectedTier)`.
- `grantedAt` was a **server prop** passed from the parent server component (which reads it from `scope_grants.granted_at`).

After a successful Authorize click on a previously-unauthorized class, `committedTier` flipped truthy but `grantedAt` was still the pre-mutation `null` (the parent server component had not re-rendered, so the prop was stale). The conjunction `committedTier && grantedAt` short-circuited to false, the "Not authorized — Soleur will not act on this class." branch kept rendering, while the action button correctly read "Revoke" — the visible UI contradicted itself until a full page reload.

The pattern is silent under any unit-test harness that mocks `next/navigation`: a mocked `router.refresh()` is a no-op `vi.fn()`, so the server re-render never happens, and headline assertions cannot distinguish bug from fix at the unit layer. The bug only surfaces against the real Next runtime, which is why PR-G shipped with the defect green-CI'd.

## Solution

Call `router.refresh()` after the mutation success — strictly in the success branch, never after an error — so the parent server component re-executes and hands a fresh `grantedAt` back to the row:

```tsx
import { useRouter } from "next/navigation";
// ...
const router = useRouter();

function onGrant() {
  startTransition(async () => {
    try {
      const res = await fetch("/api/scope-grants/grant", { /* ... */ });
      if (!res.ok) {
        setError(`Failed to save (${res.status})`);
        setSelectedTier(committedTier);  // pessimistic revert
        setAcked(false);
        return;                          // ← no router.refresh on failure
      }
      setCommittedTier(selectedTier);
      setAcked(false);
      router.refresh();                  // ← only on success
    } catch (e) {
      // catch branch: also no router.refresh
      setError(e instanceof Error ? e.message : "Network error");
      setSelectedTier(committedTier);
      setAcked(false);
    }
  });
}
```

Apply the refresh symmetrically to `onRevoke` even when the immediate display path appears unaffected — the same-session re-Authorize-after-Revoke and tier-Update-with-stale-date scenarios trip the identical bug class.

## Key Insight

When a client component's displayed state is `derive(local_state, server_prop)`, optimistic mutations that update *only* the local state leave the conjunction reading stale server data until the next server render. The cure is `router.refresh()` (App Router) — but only on success, because triggering a refresh after a failed mutation would clobber the pessimistic-UI revert with stale-but-correct server state, producing confusing UX with no benefit.

**Detection heuristic:** grep client components for state-prop conjunctions:

```bash
git grep -nE '(use)?[A-Z][a-zA-Z]+ && [a-z]+At' apps/web-platform/components/
```

Any hit where the left operand is mutable local state and the right operand is a server prop is a candidate for this defect class. Pair with `git grep -L "router.refresh" <file>` to find the unfixed ones.

## Canonical Test Shape

For the unit layer, the testable invariant is **trigger** (refresh called once on success, zero on failure), not rendered-string outcome (the mocked refresh cannot drive a real server re-render in jsdom/happy-dom). Use `vi.hoisted` to share the mock between the `vi.mock("next/navigation", ...)` factory and the `expect` site — vitest hoists `vi.mock` above all imports, so a bare top-level `const refresh = vi.fn()` is undefined inside the factory at hoist time. Precedent: `apps/web-platform/test/api-usage-retry-button.test.tsx:4-26`.

```tsx
const { mockRefresh } = vi.hoisted(() => ({ mockRefresh: vi.fn() }));
vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: mockRefresh, push: vi.fn() }),
}));
```

Coverage shape: three success-path triggers (Authorize / Revoke / Update-tier) × `mockRefresh.toHaveBeenCalledTimes(1)`, plus two failure-path negative assertions — non-2xx response AND rejected-fetch (catch branch) — × `expect(mockRefresh).not.toHaveBeenCalled()`. The two failure tests are load-bearing for the pessimistic-UI invariant: a future refactor that hoists `router.refresh()` into a `finally` block, or removes the `!res.ok` early-return, would now break a test instead of silently clobbering revert state.

## Sharp Edges

- **`router.refresh()` inside `startTransition` is intentional, not a regression.** It extends `isPending` until the refreshed server payload arrives — the action button stays disabled across the round-trip, which is correct UX, not a stall. Reviewers may flag it as "the button feels slow after click"; document the choice in the PR body to pre-empt the comment.
- **`force-dynamic` parents pay one round-trip per mutation; no cache to bust.** If the parent is statically cached, `router.refresh()` will busts the route's RSC payload cache too, which is still cheaper than a hard reload.
- **`useState(prop)` only seeds on mount.** The local optimistic mirror does not re-sync from props on subsequent renders. This is fine for single-tab single-user flows but means concurrent-modification scenarios (another tab updates the tier) won't propagate without remounting the row (`key={grantedAt}` on the parent's `.map(...)`) or an explicit `useEffect` sync. This was raised at multi-agent review (PR #4059) as a single-agent advisory finding — pre-existing concern, multiple valid fix designs, scoped out of the fix.

## Session Errors

1. **Bash CWD non-persistence on tool re-entry.** Ran `./node_modules/.bin/vitest run ...` after a gap and got `EXIT=127: No such file or directory`. The Bash tool launches each call with the worktree root (or initial-conversation root) and does not durably persist `cd` across calls when significant time elapses or when intermediate state is reset. Recovery: re-chained `cd /abs/path/apps/web-platform && ./node_modules/.bin/vitest ...` in a single Bash call. **Prevention:** the `/work` skill already encodes this — "When running test/lint/budget commands from inside a worktree pipeline, chain `cd <worktree-abs-path> && <cmd>` in a single Bash call. The Bash tool does NOT persist CWD across calls." Reapply the rule to every test-runner invocation, not just the first.
