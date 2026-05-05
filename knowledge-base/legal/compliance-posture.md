---
last_updated: 2026-05-05
---

# Legal Compliance Posture

Living status document for vendor DPAs, legal documents, and compliance action items. Domain leaders read this during assessment to avoid asserting stale or incorrect status.

## Legal Documents

| Document | Location | Last Updated | Status |
|----------|----------|-------------|--------|
| Terms & Conditions | `docs/legal/terms-and-conditions.md` | 2026-03-20 | Active |
| Privacy Policy | `docs/legal/privacy-policy.md` | 2026-03-20 | Active |
| Cookie Policy | `docs/legal/cookie-policy.md` | 2026-03-20 | Active |
| GDPR Policy | `docs/legal/gdpr-policy.md` | 2026-03-20 | Active |
| Acceptable Use Policy | `docs/legal/acceptable-use-policy.md` | 2026-03-20 | Active |
| Data Protection Disclosure | `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | 2026-03-20 | Active |
| Disclaimer | `docs/legal/disclaimer.md` | 2026-03-20 | Active |
| Individual CLA | `docs/legal/individual-cla.md` | 2026-03-20 | Active |
| Corporate CLA | `docs/legal/corporate-cla.md` | 2026-03-20 | Active |

## Vendor DPA Status

Source: `knowledge-base/project/specs/feat-vendor-ops-legal/dpa-verification-memo.md`

| Vendor | DPA Status | Signed/Verified | Transfer Mechanism | Data Region | Notes |
|--------|-----------|----------------|-------------------|-------------|-------|
| Hetzner Online GmbH | SIGNED | 2026-03-19 | N/A (EU-only) | hel1 (Finland) | Covers CX33 (web platform) |
| Supabase Inc | SIGNED | 2026-03-19 | N/A (EU-only) | eu-west-1 (Ireland) | DPA version: August 5, 2025. SCCs Module 2+3. Governing law: Irish |
| Stripe Inc | AUTO | 2026-03-19 | EU-US DPF + SCCs | US-based | Automatic via Services Agreement. SAQ-A eligible (PCI) |
| Cloudflare Inc | AUTO | 2026-03-19 | DPF + SCCs + CBPR | Global CDN | Self-executing via Self-Serve Agreement |
| Resend Inc | AUTO | 2026-04-13 | DPF + SCCs | US-based | Automatic DPA via Terms of Service (Section 7: Data Processing). Transactional email for review gate notifications |
| Doppler Inc | AUTO (MSA + DPA addendum — verification pending) | 2026-05-05 | EU-US Data Privacy Framework | US-based | Holds GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 (brand-survival credential — single-user incident threshold). RBAC review tracked in #3228. PR #3224 introduces the drift-guard secret; Doppler→GH Actions sync is the documented bootstrap path |

## Active Compliance Items

| Item | Issue | Status | Deadline | Notes |
|------|-------|--------|----------|-------|
| T&C blanket statement contradictions | #736 | OPEN | - | Identified during #670 review |

## Completed Compliance Work

| Item | Issue/PR | Completed | Notes |
|------|----------|-----------|-------|
| Supabase DPA update (Braintrust sub-processor) | #1056 / PR #1298 | 2026-04-07 | Supabase confirmed (Tracy Lane, 2026-04-07): Braintrust tracing disabled for EU-hosted projects (eu-west-1). No cross-border transfer. No data sent to Braintrust. No re-signing required — existing DPA (signed 2026-03-19) remains in effect. Sub-processor accepted via Section 6.5 notification mechanism. |
| Web platform vendor DPA review | #670 / PR #732 | 2026-03-18 | All 4 vendor DPAs signed/verified. Expense ledger updated. Legal docs updated |
| Vendor checklist gate added | #670 / PR #732 | 2026-03-18 | PR template and constitution updated with vendor compliance section |

## How to Update This Document

- When a DPA is signed, updated, or revoked: update the Vendor DPA Status table
- When a new compliance item arises: add to Active Compliance Items with issue reference
- When a compliance item is resolved: move from Active to Completed
- Update `last_updated` frontmatter date on every change
