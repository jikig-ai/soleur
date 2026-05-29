---
title: "Middleware T&C gate does not fire for PUBLIC_PATHS — routing a new signup to a public route can bypass server-recorded T&C"
date: 2026-05-29
category: security-issues
module: apps/web-platform/middleware.ts
tags: [auth, middleware, t-and-c, public-paths, open-redirect, otp, rate-limit, invite]
related:
  - knowledge-base/project/plans/2026-05-29-fix-invited-user-signin-otp-rate-limit-plan.md
  - knowledge-base/project/learnings/2026-04-11-map-supabase-errors-to-friendly-messages.md
---

# Middleware T&C enforcement is scoped OUT of PUBLIC_PATHS

## Problem

While fixing the invited-user OTP rate-limit bug (PR #4638), the deepened plan
asserted as a *verified* precondition:

> "middleware (`middleware.ts:325-326`) redirects any unaccepted-T&C user to
> `/accept-terms` from **ANY** route, so pushing a freshly-created
> (T&C-unaccepted) user to `/invite/<token>` is safe."

On the strength of that claim the fix routed a freshly-signed-up invited user
straight to `/invite/<token>` after OTP verify. Multi-agent review
(security-sentinel + user-impact-reviewer, concurring) showed the precondition
was **false**.

## Root cause

`middleware.ts` has an early return for public paths BEFORE the T&C gate:

```ts
// middleware.ts:129
if (PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"))) {
  return NextResponse.next();   // ← returns here; T&C gate at L293-326 never runs
}
```

`/invite` is in `PUBLIC_PATHS` (`lib/routes.ts:32`). So for `/invite/<token>`
the middleware never reaches the `tc_accepted_version !== TC_VERSION →
/accept-terms` check. Neither the invite page (`app/(public)/invite/[token]/page.tsx`)
nor the accept route (`app/api/workspace/accept-invite/route.ts`) checks T&C
either. Net effect: a brand-new account (whose T&C acceptance is recorded
server-side only by `POST /api/accept-terms`, NOT by the signup checkbox) could
accept a workspace invitation **before** any server-recorded T&C acceptance.

## Solution

Route signup verify THROUGH `/accept-terms` (which records T&C) and thread the
validated `redirectTo` to the terminal hop:

```ts
// signup/page.tsx — after verifyOtp success
router.push(
  redirectTo
    ? `/accept-terms?redirectTo=${encodeURIComponent(redirectTo)}`
    : "/accept-terms",
);
```

`/api/accept-terms` re-validates `redirectTo` via `safeReturnTo` and returns it
as the terminal destination only once a key exists (no key → `/setup-key` takes
precedence; the invitee re-opens the invite post-onboarding, and an
authenticated re-open needs no OTP). T&C is recorded before the invite is
acceptable. (This was the plan's "deferred Phase 4b" — review promoted it from
polish to required.)

## Key insight

**A plan claim of the form "middleware enforces X from any route" must be
verified against the `PUBLIC_PATHS` early-return, not assumed.** Any auth/consent
gate that lives AFTER the public-paths short-circuit does not protect public
routes. When a fix newly routes an authenticated-but-not-fully-onboarded user
TO a public route, ask: "does any gate that the plan relies on sit behind the
public-paths early return?" If yes, the gate does not fire there.

Corollary for the OAuth path: the `/callback` route enforces the same gates
**server-side itself** (it is not public), so honoring a `next` param there as
the terminal hop is safe — the asymmetry is that client-side `router.push` to a
public route has no equivalent server gate.

## Session Errors

1. **Plan precondition factually wrong (middleware/PUBLIC_PATHS).** — Recovery:
   routed signup through `/accept-terms` (Phase 4b), closed #4643 by implementing
   it. **Prevention:** see Key Insight; added a Sharp Edge to the plan skill.
2. **`gh issue create` rejected — missing `--milestone`, then invalid label
   `type/enhancement`.** — Recovery: added milestone, resolved label to
   `type/feature` via `gh label list`. **Prevention:** resolve labels against the
   live set before filing; always pass `--milestone`.
3. **Bash CWD did not persist across calls** (anti-slop scan + `git add` ran from
   bare root). — Recovery: chain `cd <abs> && cmd` in one call / `git -C <abs>`.
   **Prevention:** documented worktree-CWD rule; always single-call `cd && cmd`.
4. **Full-suite contention timeout** on `run-migrations-unmerged-gate.test.ts`
   (passes 3/3 in isolation). — Recovery: confirmed pre-existing flake, not a
   regression. **Prevention:** none for this PR (CI sharded).

## Tags
category: security-issues
module: apps/web-platform/middleware.ts
