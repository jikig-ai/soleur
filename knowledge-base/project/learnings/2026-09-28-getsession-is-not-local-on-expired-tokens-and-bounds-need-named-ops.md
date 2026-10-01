---
title: supabase getSession() is not a local call on expired tokens — bounding "local" reads requires knowing what they do on the cold path
date: 2026-09-28
category: performance-issues
module: apps/web-platform/middleware.ts, apps/web-platform/server/request-auth.ts
tags: [supabase, getsession, promise-race, abortsignal-timeout, token-refresh, cold-start, observability-ops]
issue: 8978
pr: 9034
---

# Learning: `getSession()` is not a local call on expired tokens

## Problem

`supabase.auth.getSession()` reads the session from the cookie — locally, on the
warm path. But `GoTrueClient.__loadSession()` *refreshes* an expired token via a
remote `/auth/v1/token` call inside the same await. Every comment in the
codebase called it "a LOCAL cookie read"; every one was right on warm and wrong
on the exact idle-then-cold shape the cold-start work was attacking — an
unbounded remote leg sitting *ahead* of all the bounds added around it.

Two separate arm dialects compound the trap: PostgREST calls accept
`.abortSignal(AbortSignal.timeout(ms))` and settle to an **error object**
(`{error: {message, hint: "Request was aborted …"}}`), while GoTrue exposes no
abort and needs `Promise.race`. A timeout so produced is not abort-shaped — a
joiner-side `Promise.race` timeout was misclassified as generic
`transient_grace` until tagged with its own op.

## Solution

- Race `getSession()` (middleware + `sessionJwtEmailForVerifiedUser`) against
  the auth bound: timeout/threw → `accessToken = undefined` → revocation leg
  `skipped`, `getUser()` still verifies inside its own race.
- Every timeout arm gets a **named op** (`session_get.timeout`/`session_get.threw`,
  `revocation_gate.dedup_joiner_timeout`, `auth.getuser.bounded_timeout`) — a
  bounded wait that degrades silently is the same "stall visible only via SSH"
  class the bounds were added to kill.
- Grace is *bounded* fail-open: per-sub strike counter (`MW_GRACE_STRIKE_LIMIT`)
  so a sustained outage escalates to a session-preserving `/login` bounce —
  unbounded grace would let a mid-session-revoked member ride it forever.

## Key Insight

"Local read" is a warm-path description, not a guarantee — for any auth/session
API, check what it does on the *expired/cold* branch before treating it as
zero-cost. Two more quiet landmines this session: `AbortSignal.timeout(-5)`
throws (floor env-derived bounds with `Math.max(…, 1)`), and vitest fake timers
cannot drive `AbortSignal.timeout`'s runtime-internal timer — timeout fixtures
must stub small real bounds via env.

## Tags

category: performance-issues
module: apps/web-platform/middleware.ts, apps/web-platform/server/request-auth.ts
