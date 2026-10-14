---
date: 2026-06-12
topic: shared-doc-waitlist-dismiss
status: complete
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
related_prs: ["#5035", "#5075", "#5076", "#5153"]
---

# Brainstorm: Remember "already joined" on the shared-doc waitlist banner

## What We're Building

A per-browser durable memory so the shared-document CTA waitlist banner
(`apps/web-platform/components/shared/cta-banner.tsx`) **does not render at all**
for a visitor who has already joined the waitlist from that browser. Today the
banner's expanded/collapsed and success states are in-memory `useState` only — a
reload restores the full empty form even immediately after a successful join, so
a returning visitor is re-prompted and the system "forgets" them.

Scope is a single client component. No API change, no migration, no new
server surface.

## Why This Approach

The shared-doc page is **public** and the visitor is **anonymous** (no auth
session, no known email until they type one). The `/api/waitlist` route
**deliberately returns an identical `{ok:true}` for a new signup and an
already-subscribed email** (`waitlist.ts` folds Buttondown's 400
`email_already_exists` into success) — an intentional anti-enumeration design.

Given an anonymous visitor and an anti-enumeration API, the **only** way to know
"this person already joined" is a client-side, per-browser marker written after a
successful Join. Every server-side alternative was rejected: the CLO **prohibits**
a server existence-check because it would convert the uniform `{ok:true}` into an
enumeration oracle (leaking whether an arbitrary email is on Soleur's list).

The CPO + CLO + CTO triad and the learnings researcher converged unanimously on
client-only `localStorage`. The prior #5075 revert that removed *dismissal*
persistence does **not** apply here: that revert protected the growth funnel
(a mere collapse shouldn't suppress forever), and that reasoning **inverts for an
actual join** — a confirmed subscriber *should* be remembered durably.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Client-only `localStorage` flag; **no server path** | Anonymous visitor + anti-enumeration API; CLO prohibits server existence-check |
| 2 | Key `soleur:shared:waitlist-joined`, value `"1"` | Distinct from the legacy in-memory `soleur:shared:cta-dismissed` (whose non-persistence is guarded by the existing close-test) |
| 3 | Store a boolean only — **never the email** | Shared docs open on shared machines; email-at-rest would be a PII exposure |
| 4 | Write the flag **only on confirmed `status==="success"`** | Never on error/submit — a false flag suppresses the CTA = a lost lead (the worst single-user outcome) |
| 5 | Remembered render: **hide the banner entirely** (render `null` on mount when flag present) | Operator's literal ask ("does not show the banner"); maximally un-naggy |
| 6 | In-session just-joined visitors keep today's "You're on the list ✓" confirmation; flag written so the **next** load hides | No abrupt mid-interaction unmount; preserves immediate feedback |
| 7 | Durability: **permanent** (no expiry) | A confirmed subscriber should not be re-prompted on this browser |
| 8 | Read storage in a lazy `useState` initializer; **no `mounted`-gate** | Banner is `{data && <CtaBanner />}` on a `"use client"` page → never in SSR HTML → no hydration mismatch (re-verified at `app/shared/[token]/page.tsx:150`) |
| 9 | All storage access wrapped in try/catch; fall back to in-memory (banner shows) on failure | Private-mode / storage-disabled must never throw |
| 10 | No cookie-consent banner; no Art. 30 change | Functional/strictly-necessary storage, no identifier (CLO + cookie-free-analytics precedent) |
| 11 | Visual design | Wireframe: see Phase 3.55 `.pen` (linked in spec FRs) |

## Open Questions

- **Privacy-policy courtesy line** ("we store a local preference to remember
  you've joined") — not legally required (CLO); defer to an optional
  `legal-document-generator` micro-task, not a blocker.
- **Reset affordance** — none in scope; clearing browser storage resets it.

## Non-Goals

- **Cross-device / cross-browser / incognito memory** — would require the
  PII/enumeration server path the operator flagged as a risk and the CLO
  prohibited. Accepted limitation: a returning visitor on a different
  browser/device sees the banner again (re-submit is idempotent server-side).
- **A distinct "you're already subscribed" message** — keeps anti-enumeration;
  both new-join and already-subscribed land on the same success/hidden state.
- **Persisting a manual collapse/dismiss** — unchanged; stays in-memory per the
  deliberate #5075 decision. Only a *confirmed join* is remembered.

## User-Brand Impact

- **Artifact:** the shared-doc waitlist CTA banner + the `localStorage` flag it
  writes.
- **Vector:** (a) a flag written on a *failed* signup silently suppresses the CTA
  so a genuine prospect never joins (lost lead); (b) persisting the entered email
  in client storage would expose PII on a shared machine; (c) any server-side
  "is this email subscribed?" check would leak waitlist membership (enumeration).
- **Threshold:** `single-user incident`. Mitigations: write the flag only on a
  confirmed 2xx success; store a boolean, never the email; client-only — no
  server existence-check (CLO-prohibited).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Concurs client-only `localStorage` is correct; no defensible server
path. Render `null` on the remembered state via a lazy initializer (banner is
never in SSR HTML, so no `mounted`-gate flash). Highest-risk path: writing the
flag on anything other than a confirmed success. Single-file blast radius; no
migration. Complexity: small (hours).

### Product (CPO)

**Summary:** Per-browser scope is acceptable for v1 (cross-device re-show is a
benign re-ask, not data loss). No distinct already-subscribed message
(anti-enumeration feature, not a gap). Worst single-user outcome is a genuine
prospect wrongly suppressed — mitigate by writing the flag only on confirmed
success. (CPO recommended a thin "You're on the list ✓" bar; operator chose full
hide — recorded as the v1 decision.)

### Legal (CLO)

**Summary:** Client-only boolean flag — **PERMIT**. Functional/strictly-necessary
storage under ePrivacy Art. 5(3); no cookie-consent banner, not personal data
(device-local, no identifier), no Art. 30 change. Server existence-check —
**PROHIBIT** (breaks the deliberate anti-enumeration design; would disclose list
membership of arbitrary emails).

## Session Errors

- None blocking. The existing close-test (`shared-cta-banner-close.test.tsx`)
  asserts no `setItem` on *toggle* and that the legacy `soleur:shared:cta-dismissed`
  key is ignored — our new write is on *submit-success* under a different key, so
  the two contracts do not conflict (verify both stay green).
