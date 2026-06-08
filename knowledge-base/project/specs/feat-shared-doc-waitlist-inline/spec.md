---
feature: shared-doc-waitlist-inline
date: 2026-06-08
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-shared-doc-waitlist-inline
pr: 5035
brainstorm: knowledge-base/project/brainstorms/2026-06-08-shared-doc-waitlist-inline-brainstorm.md
wireframes: knowledge-base/product/design/shared-document/cta-banner-waitlist.pen
---

# Spec: Inline waitlist email capture on the shared-document banner

## Problem Statement

The fixed bottom CTA banner on the public shared-document viewer
(`apps/web-platform/app/shared/[token]/page.tsx`) reads "Sign up for the
waitlist" but its button is `<Link href="/signup">`
(`apps/web-platform/components/shared/cta-banner.tsx:30`), so clicking it opens
the **account-creation page** instead of joining a waitlist. The label and the
destination are mismatched, leaking the visitor's intent at a high-value first
brand contact.

## Goals

- Fix the mismatch: clicking the waitlist CTA must join a waitlist, not open
  account creation.
- Capture the visitor's email **inline in the banner** (no navigation away from
  the shared document).
- Reuse the existing Buttondown waitlist mechanism with `tag=pricing-waitlist`.
- Show an inline "You're on the list ✓" confirmation on success.
- Rearrange the banner (two-tier desktop, stacked mobile) to fit the email
  field without cramping.
- Keep the email capture legally compliant (visible privacy notice + Privacy
  Policy link; purpose disambiguation).

## Non-Goals

- A new waitlist backend or Supabase table (reuse Buttondown).
- A distinct `shared-doc-waitlist` Buttondown tag (decided: reuse
  `pricing-waitlist`).
- Plausible / analytics event parity with the docs-site form (deferred — see
  Open Questions; default drop for v1).
- Article 30 register / Privacy Policy disclosure updates (flagged to
  `legal-compliance-auditor`, out of scope for this PR).
- Changing the banner's dismissal/session-storage behavior.

## Functional Requirements

- **FR1** — Replace the `<Link href="/signup">` CTA in `cta-banner.tsx` with an
  inline email-capture form (email input + "Join" button + dismiss X).
  *Wireframe: desktop-idle, mobile-idle.*
- **FR2** — Desktop layout is two-tier: message line + dismiss X on top; email
  input + Join button below; value-prop microcopy + privacy line beneath.
  *Wireframe: 01-desktop-idle-two-tier.*
- **FR3** — Mobile (<768px) layout is stacked: message + X, full-width email
  input, full-width Join button, compacted privacy line. *Wireframe:
  03-mobile-idle-stacked.*
- **FR4** — On successful submit, replace the input row with an inline
  "You're on the list ✓" confirmation; dismiss X remains. *Wireframe:
  02-desktop-success, 04-mobile-success.*
- **FR5** — On error, surface a generic "Something went wrong. Please try
  again." message in an aria-live status region; the form stays usable.
  *Wireframe: 05-desktop-error.*
- **FR6** — A visible privacy/frequency notice ("No spam. We email you once
  when early access opens.") and a "Privacy Policy" link are present in every
  idle frame, not hidden behind hover/tooltip.
- **FR7** — Copy is unambiguously a *product marketing waitlist* (not document
  access). Verbatim copy in the brainstorm doc.

## Technical Requirements

- **TR1** — Submission goes through a **same-origin Next.js route handler**
  (e.g. `app/api/waitlist/route.ts`) that forwards to Buttondown's embed
  endpoint server-side. The browser only talks to `'self'`. Do **not** add
  buttondown.com to the CSP `connect-src` allowlist (`lib/csp.ts:99`).
- **TR2** — Forward `application/x-www-form-urlencoded` with `email`,
  `tag=pricing-waitlist`, `embed=1`, mirroring `newsletter-form.njk` /
  `handleSignupForm` (`base.njk:297-353`).
- **TR3** — Honeypot field enforced **server-side** in the route handler (a
  client-only honeypot in a hydrated React component is bypassable).
- **TR4** — Lightweight per-IP rate-limit in the route handler (reuse an
  existing web-platform rate-limit helper if available).
- **TR5** — React client component state machine: `idle → submitting →
  success | error`; disable submit while in-flight; native `type="email"` +
  `required` validation (no hand-rolled regex).
- **TR6** — Route handler exports only HTTP method handlers
  (`cq-nextjs-route-files-http-only-exports`); any silent fallback mirrors to
  Sentry (`cq-silent-fallback-must-mirror-to-sentry`).
- **TR7** — Preserve the existing dismiss button + `safeSession` dismissal
  logic in `cta-banner.tsx`.
- **TR8** — Reflect existing design tokens: `bg-soleur-bg-surface-1/95`,
  `border-soleur-border-default`, `bg-soleur-accent-gold-fill`,
  `text-soleur-text-on-accent`, `rounded-lg`.

## Brand-Survival Threshold

`single-user incident` — one visitor's email mishandled, or one
misleading-context capture, is a brand-survival event on this public surface.
See the brainstorm's `## User-Brand Impact` section for the full framing
(artifact, vector, controls).

## Open Questions

See brainstorm `## Open Questions`: Plausible parity, rate-limit helper
availability, canonical Privacy Policy URL, Article 30 coverage.
