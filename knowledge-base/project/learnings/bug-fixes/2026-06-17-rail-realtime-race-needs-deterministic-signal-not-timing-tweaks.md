---
title: "A new-conversation that won't appear in the rail is a realtime-miss race — fix it with a deterministic signal, and verify in a real browser (3 client-timing fixes failed without one)"
date: 2026-06-17
category: bug-fixes
module: apps/web-platform/hooks/use-conversations, components/chat/chat-surface
tags: [realtime, supabase, react, race-condition, verification, headless-browser, rail]
prs: [5391, 5421, 5436]
---

# Learning: rail "new conversation doesn't appear" is a realtime-miss race — needs a deterministic signal + real-browser verification

## Problem

A freshly-started conversation did not appear in the Recent Conversations rail until a page
reload. **Three** successive client-side fixes (#5391 INSERT subscription + SUBSCRIBED backfill;
#5421 `pendingScopeRecoveryRef` gated backfill; #5436 unconditional + quiet `null→id` backfill)
all failed — the operator re-reported it after each.

## Why the first three fixes failed: unverified hypotheses + mock-based tests

Each fix assumed the realtime own-channel INSERT reaches the rail and tuned the *timing* of the
fetch/backfill around it. Their tests **mocked the realtime channel**, which always "delivers"
cleanly — so the tests passed while production still broke. None reproduced the failure in a real
browser, so the actual gap was never observed.

## The actual root cause (proven, not hypothesized)

A live, layered investigation against prod ruled out every server/transport layer:
- Realtime publication + REPLICA IDENTITY FULL: correct.
- The RESTRICTIVE jti-deny RLS policy (mig 068): does **not** block realtime.
- CSP `connect-src`: allows the WSS.
- Realtime delivery **is auth-gated** (anon receives nothing; authed receives the INSERT) — and
  supabase-js 2.99.2 **auto-authenticates** realtime on subscribe (the app's `createBrowserClient`
  path receives INSERTs without any manual `setAuth`).

A **headless-browser repro against the deployed app** then isolated it: a service-role INSERT into
a *settled* rail renders live, but the **new-conversation UI flow** (click "+ New" → send first
message) does **not** — the row is created during the rail's navigation/re-subscribe window, the
INSERT lands in the **pre-`SUBSCRIBED` gap supabase-js never replays**, and the rail's mount-time
backfills already ran *before* the row existed. So nothing surfaces it until a reload refetches.
This is a race none of the client-timing fixes could close because **they cannot observe the one
window in which the row is born.**

## Solution: a deterministic signal, not more timing

`chat-surface.tsx` already knows the new conversation's real id (`realConversationId`, set the
moment the server creates the row). On a fresh conversation (`conversationId === "new"`) it now
emits `window.dispatchEvent(new CustomEvent("soleur:conversation-created", …))`. The rail's
`useConversations` listens and refetches once via the quiet/background path. The refetch
(authenticated PostgREST, the scoped list query) deterministically returns the new in-scope row —
independent of realtime timing, preserving F3 isolation (a refetch can only return rows the list
query already permits). The realtime path stays as the fast path; the event is the guaranteed
backstop.

## Key Insights

1. **When you cannot reliably fix a race by tuning timing, add a deterministic signal that fires
   after the racy state is guaranteed settled.** The producer (chat-surface) knows exactly when the
   row exists; let it tell the consumer (rail) instead of making the consumer guess.
2. **A bug that survives multiple fixes is a signal the fixes were never verified against the real
   failure surface.** For realtime/WS/React-lifecycle bugs, a mock-based unit test is not
   verification — a **headless browser against the deployed app** is. The repro harness
   (`createServerClient` to mint correctly-formatted `@supabase/ssr` cookies → inject into real
   Chromium → drive the deployed app → capture WS frames + DOM) is the asset that finally pinned it
   and is the post-deploy verification for the fix. Keep it.
3. **Falsify server-side layers with live tests before touching client code.** Auth-gated-delivery,
   anon-vs-authed, and the app's exact client pattern were each provable in ~20-line Node scripts;
   they ruled out four plausible-but-wrong fix directions (RLS, CSP, unauthenticated realtime,
   channel-churn) before any code changed.

## Tags
category: bug-fixes
module: apps/web-platform/hooks/use-conversations
