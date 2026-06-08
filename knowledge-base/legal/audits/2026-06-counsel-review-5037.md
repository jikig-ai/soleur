---
date: 2026-06-08
issue: 5037
pr: 5035
reviewer: clo (v1 internal counsel-review attestation)
artifact: knowledge-base/legal/article-30-register.md (Processing Activity 6)
brand_survival_threshold: single-user incident
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
disposition: DISCHARGED
---

# Counsel Review — PR #5035 (Article 30 Register, PA6)

Attestation of the legal-doc change in PR #5035: the broadening of Article 30
Processing Activity 6 to cover the new shared-document waitlist email-capture
surface. Verified against the implementation diff (route, Buttondown client,
banner, `PUBLIC_PATHS`, the unchanged Vendor-DPA row, and the existing Privacy
Policy newsletter/waitlist disclosure).

## Verdicts

- **Q1 — Record accuracy / broaden-vs-new-PA:** PASS. Same processor (Buttondown,
  `embed-subscribe/soleur`), same purpose bucket (`tag=pricing-waitlist`), same
  data category (email + Buttondown technical metadata). A new collection
  surface on an existing activity — broadening PA6 (not a new PA) is correct.
  The added "Collection surfaces" row is good Art. 30 hygiene.
- **Q2 — Lawful basis:** PASS. Art. 6(1)(a) consent via affirmative submit +
  Buttondown double opt-in is correct and sufficient for an anonymous-visitor
  marketing-waitlist capture. No separate checkbox required (EDPB 05/2020
  §75–78); the submission IS the consented purpose, and purpose is clear at the
  point of collection. Withdrawal via unsubscribe (Art. 7(3)) unchanged.
- **Q3 — Implementation matches record:** PASS. Banner path, anonymous/cookieless
  surface (`/shared` + `/api/waitlist` in `PUBLIC_PATHS`), single Buttondown
  endpoint, visible point-of-collection notice + Privacy Policy link, and
  marketing framing (not a condition of document access — Art. 7(4) intact) all
  verified. SCCs Module 2 transfer matches the unchanged Vendor-DPA row.
- **Q4 — Disclosure gap:** FLAG (out of PR scope, non-blocking). Privacy Policy
  §4.6 still narrows collection to "the signup form on the Docs Site" and frames
  the purpose as newsletter-only. Post-PR, email is also collected via the
  pricing-page form and the shared-document banner on the Web Platform — an
  Art. 13(1)(c) completeness gap. Non-blocking because the banner carries its
  own at-point-of-collection notice + Privacy Policy link (Art. 13 baseline met
  at the surface). Filed as a follow-up issue to keep register ↔ Privacy Policy
  in lockstep.

## Disposition

**DISCHARGED** — the register edit is legally sound, accurately reflects the
implementation, and the ship may proceed. The operator retains an optional veto;
no sign-off action required. External counsel re-review remains reserved for the
register's frontmatter re-evaluation triggers (first arms-length user, EEA-out,
regulated industry), none of which this edit crosses.

**Follow-up (separate PR):** broaden Privacy Policy §4.6 + heading to disclose the
pricing-page and shared-document collection surfaces and the one-time early-access
notification purpose, mirroring the broadened PA6 purpose (b).
