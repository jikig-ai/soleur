# DPA Verification Memo -- Web Platform Services

**Date:** 2026-03-18
**Issue:** #670
**Reviewed by:** Soleur CLO agent (automated review, not legal advice)

## Summary

PR #637 deployed four external services for the Soleur web platform (app.soleur.ai). This memo documents the DPA status of each vendor per GDPR Article 28 requirements. Resend was listed in issue #670 but has no integration code in the codebase -- excluded from scope.

## Vendor DPA Status

| Vendor | DPA Status | Acceptance Mechanism | Transfer Mechanism | Data Categories | Action Required |
|--------|-----------|---------------------|-------------------|-----------------|-----------------|
| Hetzner Online GmbH | **NOT SIGNED** | Click-to-sign via Cloud Console (ToS 6.2) | N/A (EU-only: Germany/Finland) | Server compute, volume storage, user workspaces, encrypted API keys | **URGENT: Sign DPA (AVV) via Hetzner Console** |
| Supabase Inc | Available | PandaDoc via project dashboard "Legal Documents" | SCCs (Module 2, C2P); US-based (AWS) | Email addresses, hashed passwords, auth tokens, session data | Verify free-tier coverage; sign via dashboard |
| Stripe Inc | **Automatic** | Part of Stripe Services Agreement | EU-US DPF + SCCs (EEA Module 2) | Customer email, subscription metadata (card data handled by Stripe, PCI SAQ-A) | None -- DPA is automatic |
| Cloudflare Inc | Available | Self-Serve Subscription Agreement constitutes "Main Agreement" | DPF + SCCs (Module 2 & 3) + Global CBPR | IP addresses, request headers, TLS termination | Verify free-tier applicability in dashboard |

## Detailed Findings

### Hetzner Online GmbH

- **DPA URL:** https://www.hetzner.com/legal/terms-and-conditions/ (Section 6.2)
- **Finding:** Hetzner ToS Section 6.2 states: "We only process personal data as a processor of orders pursuant to Art. 28 GDPR if the Customer concludes a contract for processing orders with us. This contract for processing orders is not concluded automatically."
- **Tier coverage:** Applies to all plans including CX33.
- **Region:** Helsinki (hel1), Finland -- EU jurisdiction. No international transfer concerns.
- **Data processed:** Server compute, volume storage (20 GB), user workspaces, Docker containers, encrypted API keys (AES-256-GCM).
- **Action:** Log into Hetzner Cloud Console, navigate to account settings, execute the DPA (Auftragsverarbeitungsvertrag / AVV). This is a click-to-sign process. **The web platform should not accept user registrations until this is signed.**

### Supabase Inc

- **DPA URL:** https://supabase.com/legal/dpa
- **Finding:** Supabase DPA available as PDF. Legally binding version obtainable through PandaDoc via project dashboard's "Legal Documents" section.
- **Tier coverage:** Needs verification -- free-tier projects may not have access to the PandaDoc signing flow. If unavailable, upgrading to Pro ($25/mo) may be required.
- **Region:** Determined by `NEXT_PUBLIC_SUPABASE_URL` env var. Default is `us-east-1` (US). If US-based, transfer mechanism is SCCs (Module 2, Controller to Processor).
- **Data processed:** Email addresses, hashed passwords (bcrypt via GoTrue), auth tokens (JWT), session metadata.
- **Action:** Check Supabase dashboard for DPA availability on free tier. Verify project region. Sign DPA if available; if not, document gap and plan Pro upgrade.

### Stripe Inc

- **DPA URL:** https://stripe.com/legal/dpa
- **Finding:** Stripe's DPA is incorporated into the Stripe Services Agreement automatically. No separate execution required.
- **PCI scope:** Code review of `apps/web-platform/app/api/checkout/route.ts` confirms Stripe Checkout integration (`stripe.checkout.sessions.create()` with `window.location.href = data.url`). Card data never touches Jikigai servers. **SAQ-A eligible** (simplest PCI self-assessment).
- **Tier coverage:** Applies to all Stripe accounts.
- **Region:** US-based (Stripe, LLC). Transfer via EU-US DPF (adequacy decision) and SCCs (EEA Module 2) as supplementary safeguard.
- **Data processed:** Customer email (passed via `customer_email: user.email`), subscription metadata. Card data handled exclusively by Stripe.
- **Source files reviewed:** `apps/web-platform/lib/stripe.ts`, `apps/web-platform/app/api/checkout/route.ts`, `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx`
- **Action:** None required.

### Cloudflare Inc

- **DPA URL:** https://www.cloudflare.com/cloudflare-customer-dpa/
- **Finding:** Cloudflare DPA applies "where Cloudflare processes Personal Data as a Processor... on behalf of Customer to provide the Services" and is tied to the "Main Agreement."
- **Tier coverage:** The Self-Serve Subscription Agreement likely constitutes the "Main Agreement" for free-tier users. The existing `soleur.ai` zone relationship already establishes a service relationship -- the `app.soleur.ai` subdomain extends the same processing.
- **Region:** Global CDN. Transfer via DPF, SCCs (Module 2 and Module 3), and Global CBPR certification.
- **Data processed:** IP addresses, request headers, TLS termination for `app.soleur.ai`.
- **Action:** Verify DPA acceptance status in Cloudflare dashboard. Document analysis that Self-Serve Agreement constitutes Main Agreement.

### Resend (NOT IN SCOPE)

- **Status:** Listed in issue #670 but zero integration code found in `apps/web-platform/`.
- **DPA URL:** https://resend.com/legal/dpa (DPF-certified, 21 US-based sub-processors)
- **Action:** When Resend integration PR is opened, trigger DPA review and expense ledger update at that time. This is exactly the type of gate Phase 6 of this issue creates.

## Recommendations

1. **Immediate:** Sign Hetzner DPA via Cloud Console before accepting user registrations.
2. **This week:** Check Supabase dashboard for free-tier DPA availability. If unavailable, budget $25/mo for Pro upgrade.
3. **This week:** Verify Cloudflare DPA acceptance status in dashboard.
4. **No action:** Stripe DPA is automatic.
5. **Future:** When Resend integration is added, run a new DPA verification cycle.
