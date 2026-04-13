---
title: "Push notification review findings — subscription limits, test granularity, tag collapsing, and build pipeline"
category: integration-issues
module: web-platform/notifications
date: 2026-04-13
tags: [push-notifications, testing, docker, ci, supabase, service-worker]
issues: [2043, 2044, 2045, 2051, 2052]
pull_request: 2035
---

# Learning: Push notification review findings batch fix

## Problem

Five issues from PR #2035 code review needed resolution: an unbounded per-user subscription fan-out, weak test assertions that wouldn't catch payload-shaping bugs, notification tag collapsing that hid concurrent alerts, a dead `last_used_at` column, and a missing `NEXT_PUBLIC_VAPID_PUBLIC_KEY` build-arg preventing client-side push subscription.

## Solution

### Per-user subscription limit (#2043)

Added a `SELECT count(*)` check (with `{ count: "exact", head: true }`) before the upsert in `app/api/push-subscription/route.ts`. Cap set at 20. If at limit, a secondary query checks whether the incoming endpoint already exists (update case allowed, new endpoint rejected with 400).

### Conversation-specific notification tags (#2045)

Changed `sw.js` tag from hardcoded `"review-gate"` to `review-gate-${payload.data.conversationId}`. This allows concurrent review gate notifications from different conversations to show separately instead of collapsing into one.

### last_used_at update on delivery (#2045)

After the `Promise.allSettled` loop in `sendPushNotifications()`, collect IDs of successfully delivered subscriptions into a `deliveredIds` array, then batch-update `last_used_at` with `.update().in("id", deliveredIds)`. This makes staleness cleanup queries viable.

### Test assertion granularity (#2044)

Added `toHaveBeenCalledWith` assertions to verify:
- Push notification endpoint and payload content (including conversationId)
- Email recipient address and deep link URL
- Upsert payload (user_id, endpoint, p256dh, auth, onConflict)
- Delete query chain (user_id and endpoint eq checks)
- New test: subscription limit enforcement returns 400

### VAPID build-arg (#2052)

Three touchpoints for `NEXT_PUBLIC_VAPID_PUBLIC_KEY`:
1. Doppler prd config (`doppler secrets set`)
2. GitHub secret (`gh secret set`)
3. Dockerfile `ARG` + CI workflow `build-args` in `reusable-release.yml`

## Session Errors

1. **Stale local main in bare repo** — `cleanup-merged` couldn't fast-forward local main because `feat-one-shot-issue-1796` worktree had main checked out. Worktree was created from stale main (missing PR #2035 code). **Recovery:** `git rebase origin/main` in the worktree. **Prevention:** When `cleanup-merged` warns about a stale main, always rebase the new worktree onto `origin/main` before starting work.

2. **Missing web-push package after worktree creation** — Worktree was created from stale main (before web-push was added to package.json), so `npm install` during creation didn't install it. After rebasing onto origin/main, the package was in package.json but not in node_modules. **Recovery:** `npm install` after rebase. **Prevention:** After rebasing a worktree, always re-run `npm install` to pick up new dependencies.

3. **Mock chain mismatch in Supabase mock** — Used `mockReturnValue` which returned the same mock for all `mockFrom` calls. The subscription limit code calls `mockFrom` twice (count check, then existing endpoint check), requiring `mockReturnValueOnce` for sequential calls. **Recovery:** Switched to `mockReturnValueOnce` chaining. **Prevention:** When a Supabase mock function is called multiple times in a code path, use `mockReturnValueOnce` for each call instead of `mockReturnValue`.

## Key Insight

**NEXT_PUBLIC_ vars require three touchpoints:** Doppler (runtime), GitHub secret (CI), and Dockerfile ARG + CI build-arg (build time). Missing any one silently produces `undefined` at runtime with no build error. When adding a new client-side env var, grep the Dockerfile and CI workflow in the same commit.

**Test assertions should verify content, not just occurrence.** `toHaveBeenCalledTimes(1)` proves a function ran; `toHaveBeenCalledWith(...)` proves it did the right thing. Every mock assertion on an external boundary (API call, notification dispatch, database write) should include at least one argument-level assertion.

**Deduplication keys must include entity identifiers.** A generic constant like `"review-gate"` deduplicates across unrelated items. Include the entity ID (conversationId, resourceId) that distinguishes one event from another.

## Tags

category: integration-issues
module: web-platform/notifications
