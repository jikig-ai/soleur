---
title: "Middleware revocation gate is defense-in-depth; RLS is_workspace_member is the actual removal boundary"
date: 2026-06-15
category: security-issues
module: apps/web-platform/middleware.ts
tags: [auth, middleware, rls, revocation, fail-open, fail-closed, supabase, "#4307"]
related:
  - knowledge-base/project/learnings/2026-03-20-middleware-error-handling-fail-open-vs-closed.md
  - knowledge-base/project/plans/2026-06-15-fix-session-disconnect-and-login-rate-limit-blocking-plan.md
---

# Learning: the #4307 revocation gate is defense-in-depth, not the removal boundary

## Problem
Two production symptoms: (1) users bounced to `/login` mid-session; (2) login codes
blocked after a few attempts. Symptom 1 traced to the #4307 workspace-member revocation
gate in `middleware.ts`, which fail-CLOSED to **503-for-all** on any `check_my_revocation`
RPC error and force-logged-out on JWT-decode hiccups. The instinct when relaxing a
fail-closed security gate is to treat ANY relaxation as re-opening the leak the gate exists
to prevent. The plan itself framed the gate as THE boundary ("a removed member regains
`is_workspace_member`-routed RLS read/write"), which made grace-on-transient-error look
strictly dangerous.

## Solution
Grant **grace** on transient RPC errors and decode hiccups (allow the request through,
emit a distinct Sentry op, re-check next request); keep ONLY the genuine `revoked === true`
row fail-CLOSED. This is safe because of a defense-in-depth property the plan under-credited.

## Key Insight
**The middleware revocation gate is defense-in-depth + UX, NOT the sole removal boundary.**
The actual data-plane boundary for a *removed* member is RLS: `remove_workspace_member`
DELETEs the `workspace_members` row, and every `conversations`/`messages`/`attachments`/BYOK
read/write is gated by `is_workspace_member(...)` against the **live** table. So even during
a grace window, a fully-removed member is RLS-denied at the data layer — grace does **not**
re-open the removal leak. The gate just saves a round-trip and gives a clean `/login` bounce.

The one **bounded, accepted residual**: a *role-changed* member's row PERSISTS (only `role`
is UPDATEd), so `is_workspace_member` still returns true. During a transient
`check_my_revocation` outage a just-demoted member retains their pre-demotion effective role
for actions gated solely by the middleware gate, until the RPC recovers (next-request
re-check) or the JWT expires (~≤1h). Not client-inducible (the RPC takes no client input
beyond the JWT iat); strictly better than the 503-for-all it replaced.

**Generalizable rule:** before classifying a fail-closed→grace relaxation on an
access-control middleware gate as a leak, identify whether a *lower* layer (RLS, a row-level
check, a DB constraint) independently enforces the same boundary. If it does, the middleware
gate is defense-in-depth and grace-on-transient is safe; enumerate only the cases the lower
layer does NOT cover (here: role-change, because the row survives) as the real residual.
Multi-agent review (security-sentinel + user-impact-reviewer concurring) reliably surfaces
this where plan-time framing inverts the gate-vs-RLS relationship.

Corollary (verified this session): `getUser()` authenticates against the auth server but does
NOT expose the raw access-token bytes — `getSession()` after `getUser()` is the correct way
to read the token for a local `iat` decode, and is NOT the redundant re-validation the
@supabase/ssr docs warn against.

## Session Errors
- **`tsc --noEmit | head` left the exit-capture var empty** — Recovery: re-ran with
  `> log 2>&1; rc=$?`. Prevention: for load-bearing exit codes, capture `rc=$?` on the
  command directly, never via a `| head`/`| tail` pipe (the pipe's exit is the pager's).
  One-off.
- **`Edit` on `constants.ts` failed "File has not been read yet"** — I had read it via `cat`
  in a Bash command, which does NOT register the file for the Edit tool. Recovery: Read tool
  then Edit. Prevention: already enforced by `hr-always-read-a-file-before-editing-it`; when
  you intend to Edit, use the Read tool (not `cat`) so the read is registered. One-off.

## Tags
category: security-issues
module: apps/web-platform/middleware.ts
