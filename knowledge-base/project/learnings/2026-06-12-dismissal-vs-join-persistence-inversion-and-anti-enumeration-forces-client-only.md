# Learning: "Remember me" durability inverts between a dismissal and a conversion; an anti-enumeration API forecloses the server path

## Problem

Brainstorm of the shared-doc waitlist CTA banner (`apps/web-platform/components/shared/cta-banner.tsx`):
the banner should "remember the visitor is already on the waitlist and not show the banner."
Two non-obvious constraints shaped the design and could mis-route a future similar feature.

## Solution

Client-only `localStorage["soleur:shared:waitlist-joined"]="1"`, written **only** on a confirmed
`status==="success"`, read in a lazy `useState` initializer to render `null` on return. No server
path. See spec `feat-shared-doc-waitlist-dismiss/spec.md`.

## Key Insight

1. **Persistence-durability inverts between a *dismissal* and a *conversion*.** PR #5075 deliberately
   *reverted* sessionStorage dismissal-persistence on this exact banner to protect the growth funnel —
   a mere collapse should not suppress the CTA forever. The naive read is "this codebase decided not to
   persist banner state, so don't persist." That is wrong for a *join*: a confirmed subscriber *should*
   be remembered durably (localStorage, no expiry). When reusing a "we decided not to persist X" prior
   decision, check whether X was a *dismissal* (funnel-protective, transient) or a *conversion*
   (funnel-complete, durable) — they take opposite storage choices. The existing close-test still guards
   the dismissal contract (legacy key `soleur:shared:cta-dismissed` must stay ignored), so the new
   durable flag must use a *distinct* key, not reuse the legacy one.

2. **A deliberately anti-enumeration API structurally forecloses the server path.** `/api/waitlist`
   folds Buttondown's already-subscribed 400 (`email_already_exists`) into an identical `{ok:true}` so a
   new signup and an existing one are indistinguishable to the client — intentional, to prevent
   membership enumeration. Therefore *no* server-side "is this email subscribed?" check can drive
   banner-suppression without re-opening the enumeration oracle (CLO prohibits it). For an anonymous
   public-page visitor, "remember they converted" can *only* be a per-browser client flag. Recognise the
   anti-enumeration pattern (uniform success response) early — it eliminates an entire option branch
   before leaders are spawned.

3. **A banner rendered as `{data && <Component/>}` on a `"use client"` page is never in SSR HTML**
   (`app/shared/[token]/page.tsx:150`), so reading storage in a lazy `useState` initializer cannot
   hydration-mismatch — no `mounted`-gate needed. Verify the render-after-fetch flow still holds before
   relying on it.

## Session Errors

- **`AskUserQuestion` rejected `preview: null`** — Recovery: omit the `preview` field entirely on
  options that lack one (never pass `null`). Prevention: when only some options in a question have a
  preview, omit the key on the rest rather than setting it null. One-off.
- **zsh glob-expanded a literal `[token]` Next.js dynamic-route path** in Bash (`sed`/`grep`/`head` →
  "no such file"). Recovery: use the Read tool, or `git ls-files`/`find`/`printf` to obtain the path.
  Prevention: for paths containing `[param]` brackets, prefer the Read tool or quote+noglob. Mildly
  recurring (Next.js dynamic routes are common). Not hook-worthy.
- **Bash working-directory persisted across tool calls** — a repeated `cd <rel>` failed after the first
  moved cwd. Recovery: prefer absolute paths / check `pwd`. One-off (documented behavior).

## Tags
category: logic-errors
module: web-platform/shared/cta-banner
related: ["#5035", "#5075", "#5076", "#5153", "#5207"]
