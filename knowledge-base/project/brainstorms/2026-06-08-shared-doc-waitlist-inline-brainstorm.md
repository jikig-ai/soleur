---
date: 2026-06-08
topic: shared-doc-waitlist-inline
status: complete
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-shared-doc-waitlist-inline
pr: 5035
---

# Inline waitlist email capture on the shared-document banner

## What We're Building

The fixed bottom CTA banner on the public shared-document viewer
(`apps/web-platform/app/shared/[token]/page.tsx`) currently shows
**"Sign up for the waitlist"** but its button is `<Link href="/signup">`
(`apps/web-platform/components/shared/cta-banner.tsx:30`) — so it wrongly
sends visitors to **account creation** instead of a waitlist signup. This is
the bug.

We replace the link with an **inline email-capture form inside the banner**.
An anonymous visitor types their email and joins the marketing waitlist
without leaving the document. On success, the form is replaced by an inline
**"You're on the list ✓"** confirmation. The banner is rearranged (two-tier
on desktop, stacked on mobile) to make room for the email field.

## Why This Approach

- The shared-doc viewer is a high-intent, zero-account surface — the visitor
  is already engaging with Soleur output. A redirect to `/signup` leaks that
  intent and is semantically wrong ("waitlist" ≠ "create account").
- Inline capture matches the visitor's mental model and the user's request.
- Reuse the **proven Buttondown waitlist mechanism** already used by the
  pricing page (`tag=pricing-waitlist`, honeypot, double opt-in) rather than
  building new backend infrastructure.

## Key Decisions

| Decision | Choice | Source |
|----------|--------|--------|
| Fix the bug | Replace `<Link href="/signup">` with inline email form | User |
| Backend | Reuse Buttondown, **`tag=pricing-waitlist`** (no new tag) | User |
| Architecture | **Same-origin Next.js API route proxy** (`/api/waitlist` → Buttondown), NOT direct client POST | User + CTO |
| Why proxy | Prod CSP `connect-src` (`lib/csp.ts:99`) excludes buttondown.com → direct client POST fails closed; proxy keeps browser on `'self'` and enables real server-side honeypot + rate-limit | CTO |
| Success state | Inline "You're on the list ✓" confirmation, dismissible | User |
| Desktop layout | Two-tier inside the bar: message line on top, email + "Join" + dismiss X below | CPO |
| Mobile layout | Stacked: message → full-width email input → full-width "Join" button; X pinned top-right | CPO |
| Privacy notice | **Mandatory** visible privacy/frequency notice + Privacy Policy link in the banner | CLO |
| Purpose copy | Must read unmistakably as a *product marketing waitlist*, not document-access notification (dark-pattern risk) | CLO |
| Consent record | Buttondown double opt-in = the consent record; no separate checkbox required | CLO |
| Visual design | Pencil wireframes: `knowledge-base/product/design/shared-document/cta-banner-waitlist.pen` (5 frames: desktop idle/success/error + mobile idle/success; screenshots in `screenshots/`) | ux-design-lead |

### Proposed copy (carry-forward, CMO to confirm)

- Message (desktop top tier): "Built with Soleur — AI agents for every department of your startup."
- Field microcopy: "Join the waitlist for early access."
- Placeholder: `you@company.com`
- Button: "Join" (or "Join waitlist" if width allows)
- Privacy line: "No spam. We email you once when early access opens. [Privacy Policy]"
- Success: "You're on the list ✓"

## User-Brand Impact

- **Artifact:** the visitor's email address (personal data) captured on the
  public shared-document banner.
- **Vector:** email PII forwarded to a third party (Buttondown); mishandling,
  mis-tagging, or capture without a visible privacy notice/consent. Secondary:
  a confusing or misleading capture on first brand contact erodes trust.
- **Threshold:** `single-user incident`. One visitor's email mishandled, or
  one misleading-context capture, is a brand-survival event on this surface.
- **Controls:** server-side proxy (no third-party origin in client CSP),
  visible privacy notice + Privacy Policy link, purpose-disambiguating copy,
  Buttondown double opt-in as the consent record, server-side honeypot.

## Open Questions

1. **Plausible parity:** the docs-site form fires a `Waitlist Signup`
   Plausible event on success; web-platform has no wired Plausible equivalent.
   Drop the analytics event, or wire web-platform analytics? (Plan decision —
   default: drop for v1.)
2. **Rate-limit shape:** lightweight per-IP throttle in the new route handler —
   reuse an existing rate-limit helper if one exists in web-platform, else a
   minimal in-memory/edge guard. (Plan to confirm helper availability.)
3. **Privacy Policy URL:** confirm the canonical web-platform Privacy Policy
   route to link from the banner (docs site uses `/legal/privacy-policy/`).
4. **Article 30 / Privacy Policy coverage:** if "marketing waitlist / early-
   access email collection" is not already disclosed, `legal-compliance-auditor`
   should add an entry (out of scope for this PR; flagged by CLO).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Inline capture is the right call for a high-intent zero-account
surface; the one big risk is a cramped sub-200px input in a one-row fixed
bottom bar — solved by a two-tier desktop layout and a stacked mobile layout.
Provided concrete per-breakpoint layout and copy.

### Engineering (CTO)

**Summary:** Prod CSP `connect-src` excludes buttondown.com, so a direct client
POST fails closed — use a same-origin Next.js route proxy instead (no CSP
edit, real server-side honeypot + rate-limit). Re-implement the docs-site
vanilla pattern as a React client component with an idle→submitting→success/
error state machine; keep `tag=pricing-waitlist` and the `embed=1`,
urlencoded contract. Small (hours), no migration, no ADR.

### Legal (CLO)

**Summary:** Lawful, but informed consent requires a visible privacy notice +
Privacy Policy link in the banner and copy that disambiguates this as a
product marketing waitlist (not document access) to avoid a dark-pattern risk
specific to this surface. Buttondown double opt-in is the consent record; no
separate checkbox needed. Keep purpose-limitation parity with the pricing form.

## Session Errors

None.
