# Dashboard Cold-Start Render Unblock — Brainstorm

**Date:** 2026-06-25
**Branch:** feat-dashboard-cold-start-render
**PR:** #5653 (draft)

## What We're Building

Stop gating the entire dashboard render on the `GET /api/kb/tree` fetch so the
app paints its real content on cold start instead of showing a full-screen
skeleton for several seconds. The KB-tree data only drives **foundation-card
completion checkmarks** — a secondary concern — yet it currently blocks the
whole page (including the primary conversation list) behind an early-return
skeleton.

## Why This Approach

Investigation traced the cold-start critical path. The full-screen skeleton in
the symptom screenshot is the `kbLoading` early-return at
`apps/web-platform/app/(dashboard)/dashboard/page.tsx:421`. It holds until
`/api/kb/tree` resolves.

What's actually slow after a **computer restart** (cause analysis, not assumed):

1. **JS bundle download — already cached.** `public/sw.js` does cache-first on
   `/_next/static/`; Cache Storage survives a restart. Only a fresh deploy
   (content-hashed filenames) forces a re-download. Not the dominant cost.
2. **Auth token refresh.** After the machine is off, the Supabase access token
   has typically expired → the first authenticated request pays a token-refresh
   round-trip.
3. **Uncached per-user auth waterfall (the long pole).** The service worker
   explicitly skips `/api/*` (`sw.js:47`), so `/api/kb/tree` always hits the
   network. `middleware.ts` runs a **serial 3-hop chain on every request**:
   `getUser()` (Supabase auth server) → `check_my_revocation` RPC (DB) →
   `users` SELECT for T&C/subscription (DB). The route then does workspace
   resolution (DB) + a disk tree-walk (`buildTree`).

Key insight: the operator's "store it in cache" intuition is half-right — the
*bundle* is already cached; the slow part is the per-user, security-sensitive
data waterfall the skeleton needlessly blocks on. The **highest-leverage,
lowest-risk** fix is to decouple the render from that fetch rather than to cache
or speed up the fetch itself (those are separate, larger, higher-risk follow-ups
— see Non-Goals / deferred).

## Key Decisions

| Decision | Choice |
|----------|--------|
| Direction | Unblock the render (operator-selected over persistent-cache / waterfall-speedup / both) |
| Gate the page on | The **conversation-list** load, not the **KB-tree** load |
| Foundation cards | Render async; show a localized loading/placeholder state for the cards only while `kbData === undefined` |
| First-run safety | Do **not** flash the first-run "Tell your organization what you're building" empty state while KB-tree is still loading — `visionExists` is unknown until the tree resolves, so the first-run branch must not trigger on a transient `false` |
| Provisioning / error states | Preserve existing `kbError === "provisioning"` (503) screen and error handling |
| Scope | Single-file change in `dashboard/page.tsx` (render-flow only); no middleware, no caching layer, no ADR-067 change |

## Open Questions

- While conversations exist but KB-tree is still loading, render the inbox view
  immediately with foundation cards in a placeholder state — confirm the
  foundation section degrades cleanly (no layout shift jank) when `allCards`
  is still resolving.
- Confirm there is no consumer other than foundation-card derivation that
  truly *requires* `kbFiles` before first paint (grep `kbFiles` / `visionExists`
  usages during implementation).

## Non-Goals (deferred)

- **Persistent client cache** (localStorage/IndexedDB stale-while-revalidate for
  conversations/KB) — revisits ADR-067's deliberate in-memory-only decision
  (CPO C1). Separate brainstorm if pursued.
- **Speeding up the middleware auth waterfall** (parallelizing / caching
  getUser + revocation RPC + T&C SELECT) — touches the security-sensitive
  revocation gate; higher risk, separate work.

## User-Brand Impact

- **Artifact:** the dashboard cold-start render path (`dashboard/page.tsx`
  loading gate).
- **Vector:** a render-flow change that mis-handles the unknown-KB-state window
  could flash a wrong empty/first-run state to an existing user, reading as data
  loss or a broken account.
- **Threshold:** single-user incident.
