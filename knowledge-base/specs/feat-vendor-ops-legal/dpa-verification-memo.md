# DPA Verification Memo -- Web Platform Services

**Date:** 2026-03-18
**Updated:** 2026-03-19 (dashboard verification via Playwright, DPA execution initiated)
**Issue:** #670, #702
**Reviewed by:** Soleur CLO agent (automated review, not legal advice)

## Summary

PR #637 deployed four external services for the Soleur web platform (app.soleur.ai). This memo documents the DPA status of each vendor per GDPR Article 28 requirements. Resend was listed in issue #670 but has no integration code in the codebase -- excluded from scope.

**2026-03-19 Update:** Dashboard verification completed for all four vendors. Key finding: Supabase project is in **eu-west-1** (Ireland, EU), NOT us-east-1 -- eliminating Chapter V transfer concerns. Supabase DPA request submitted via PandaDoc. Cloudflare DPA confirmed self-executing. Hetzner DPA pending founder login. Telegram-bridge CX22 confirmed on same Hetzner Cloud Console account.

## Vendor DPA Status

| Vendor | DPA Status | Acceptance Mechanism | Transfer Mechanism | Data Categories | Action Required |
|--------|-----------|---------------------|-------------------|-----------------|-----------------|
| Hetzner Online GmbH | **NOT SIGNED** | Click-to-sign via Cloud Console (ToS 6.2) | N/A (EU-only: Germany/Finland) | Server compute, volume storage, user workspaces, encrypted API keys | **URGENT: Founder must log into console.hetzner.cloud and sign DPA (AVV)** |
| Supabase Inc | **DPA REQUESTED** (2026-03-19) | PandaDoc via dashboard "Legal Documents" -- request sent to ops@jikigai.com | N/A (EU-only: eu-west-1, Ireland) | Email addresses, hashed passwords, auth tokens, session data | Sign PandaDoc when it arrives (within 24h) |
| Stripe Inc | **VERIFIED** (2026-03-19) | Part of Stripe Services Agreement (automatic) | EU-US DPF + SCCs (EEA Module 2) | Customer email, subscription metadata (card data handled by Stripe, PCI SAQ-A) | None -- DPA is automatic |
| Cloudflare Inc | **VERIFIED** (2026-03-19) | Self-Serve Subscription Agreement constitutes "Main Agreement" (confirmed via dashboard) | DPF + SCCs (Module 2 & 3) + Global CBPR | IP addresses, request headers, TLS termination | None -- DPA is self-executing |

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
- **DPA PDF:** https://supabase.com/downloads/docs/Supabase+DPA+260317.pdf
- **TIA PDF:** https://supabase.com/downloads/docs/Supabase+TIA+250314.pdf (Supabase-provided)
- **Finding:** Supabase DPA available as PDF. Legally binding version obtainable through PandaDoc via project dashboard's "Legal Documents" section.
- **Tier coverage:** **CONFIRMED** -- Free tier supports DPA signing. Dashboard text: "All organizations can sign our Data Processing Addendum ("DPA") as part of their GDPR compliance." No Pro upgrade required.
- **Region:** **eu-west-1** (Ireland, EU) -- confirmed via Supabase dashboard (project: soleur-web-platform, AWS eu-west-1). **No international data transfer. No Chapter V concerns. No TIA required for this deployment.**
- **Data processed:** Email addresses, hashed passwords (bcrypt via GoTrue), auth tokens (JWT), session metadata.
- **DPA request status:** Submitted 2026-03-19 via dashboard to ops@jikigai.com. PandaDoc executable version will arrive within 24 hours.
- **Action:** Sign PandaDoc document when it arrives at ops@jikigai.com. No Pro upgrade needed. No transfer safeguards needed (EU-only).

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
- **Tier coverage:** **CONFIRMED** -- Self-Serve Subscription Agreement constitutes the "Main Agreement." Dashboard verified: account Jean.deruelle@jikigai.com with soleur.ai zone active on free tier. No explicit "sign DPA" UI exists -- the DPA is self-executing upon service use.
- **Region:** Global CDN. Transfer via DPF, SCCs (Module 2 and Module 3), and Global CBPR certification.
- **Data processed:** IP addresses, request headers, TLS termination for `app.soleur.ai`.
- **Verification date:** 2026-03-19 (Cloudflare dashboard confirmed)
- **Action:** None -- DPA is self-executing. Self-Serve Agreement = Main Agreement. Verified.

### Resend (NOT IN SCOPE)

- **Status:** Listed in issue #670 but zero integration code found in `apps/web-platform/`.
- **DPA URL:** https://resend.com/legal/dpa (DPF-certified, 21 US-based sub-processors)
- **Action:** When Resend integration PR is opened, trigger DPA review and expense ledger update at that time. This is exactly the type of gate Phase 6 of this issue creates.

### Telegram-Bridge Hetzner Server

- **Finding:** `apps/telegram-bridge/infra/` uses `hcloud` provider (Hetzner Cloud Console), NOT Robot.
- **Server type:** CX22, location fsn1 (Falkenstein, Germany, EU).
- **DPA coverage:** Same Hetzner Cloud Console account as web platform CX33. **One DPA covers both servers.**
- **Action:** None beyond signing the Cloud Console DPA (covers all servers under the account).

## Recommendations

1. **BLOCKING:** Sign Hetzner DPA via Cloud Console (console.hetzner.cloud > account settings > DPA/AVV). This covers both CX33 (web platform) and CX22 (telegram-bridge).
2. **PENDING (24h):** Sign Supabase PandaDoc DPA when it arrives at ops@jikigai.com.
3. **DONE:** Stripe DPA verified as automatic (2026-03-19).
4. **DONE:** Cloudflare DPA verified as self-executing via Self-Serve Agreement (2026-03-19).
5. **Future:** When Resend integration PR is opened, trigger DPA review and expense ledger update.
