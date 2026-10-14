---
title: "Legal-track PR — LIA + Privacy Policy + DPD updates for LinkedIn Company Page publication"
type: spec
status: draft-requires-counsel-review
date: 2026-05-19
issue: 4051
branch: feat-legal-linkedin-page-4051
lane: cross-domain
domains: [legal, marketing, infra]
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
requires_clo_signoff: true
blocks: 4046
plan: knowledge-base/project/plans/2026-05-19-feat-legal-linkedin-page-4051-plan.md
---

# Specification — Legal-track PR for LinkedIn Company Page publication (#4051)

## Problem

Article 30 PA15 of the GDPR register (`knowledge-base/legal/article-30-register.md`) documents the LinkedIn Company Page publication processing activity. PA15 cross-references a **legitimate interest assessment (LIA)** that does not yet exist, and the controller's **Privacy Policy** and **Data Protection Disclosure (DPD)** do not yet name `LinkedIn Ireland Unlimited Company` or `Microsoft Ireland Operations Ltd` as recipients under Art. 13(1)(e), nor disclose the Art. 17 carve-out for LinkedIn-published content.

Without these three artifacts in place, Article 30(1) accountability is incomplete and the controller cannot proceed with **Phase 5.4** of the parent runbook (`knowledge-base/project/plans/2026-05-19-feat-linkedin-api-reapply-jikigai-plan.md`) — the K-bis appeal upload at `https://www.linkedin.com/help/linkedin/ask/dsapi` constitutes the first cross-controller personal-data transfer triggered by PA15 and would create regulatory exposure if the lawful-basis documentation is missing at the moment of transfer.

Separately, the LinkedIn Developer app (229658411) currently advertises a privacy-policy URL on `soleur.ai`. The named controller in K-bis is `Jikigai SARL`. The entity↔domain mismatch is a documented LinkedIn appeal-rejection class and should be resolved by redirecting `jikigai.com/legal/privacy-policy` → `soleur.ai/pages/legal/privacy-policy.html` (canonical-source-of-truth preserved on soleur.ai).

## Scope (IN)

1. **New LIA file** at `knowledge-base/legal/legitimate-interest-assessments/2026-05-19-linkedin-org-page-lia.md`, structured per the `2026-05-14-tenant-deploy-substrate-lia.md` template (Purpose / Necessity / Balancing H2s + Outstanding counsel-review items + Re-evaluation triggers).
2. **Privacy Policy update** at `docs/legal/privacy-policy.md` — new §4.10 data-class block; new §5.12 LinkedIn Ireland sub-processor row; new §5.13 Microsoft Ireland sub-processor row; §6 dual-basis disclosure; §7 retention row; §8.1 Art. 17 carve-out; §10 international-transfers rows.
3. **DPD update** at `docs/legal/data-protection-disclosure.md` — mirror of (2) in DPD structured form (§2.3(p), §4.2, §6.4, §10.3).
4. **PA15 cross-reference promotion** in `knowledge-base/legal/article-30-register.md` — replace the forward-looking "documented in the follow-up legal-track PR #4051" substring with the concrete LIA path.
5. **`compliance-posture.md` row** — Active Item during counsel review; moved to Completed at merge.
6. **Cloudflare ruleset redirect** in `apps/web-platform/infra/jikigai-com.tf` — single `cloudflare_ruleset` resource on the existing aliased `cloudflare.jikigai_com` provider, narrow-scoped 301 from `jikigai.com/legal/privacy-policy` to `soleur.ai/pages/legal/privacy-policy.html`.

## Scope (OUT)

- **Duplicate hosting of the privacy policy at jikigai.com.** Single source of truth remains `docs/legal/privacy-policy.md` rendered onto `soleur.ai` (redirect-only at jikigai.com).
- **Joint-controller (Art. 26) arrangement with LinkedIn Ireland.** Fires at first Page Insights API call — separate follow-up issue.
- **GDPR Policy** (`docs/legal/gdpr-policy.md`) **and other docs/legal/** files. **Privacy Policy + DPD are the load-bearing surfaces under Art. 13(1)(e); the GDPR Policy is summary-form and does not require an edit at this milestone (carried-forward decision from parent brainstorm; reassess if counsel disagrees).
- **Phases 5.4 + 5.5 + 6 of the parent runbook** — those are operator runbook steps, not in this PR's diff.

## User roles affected

1. **LinkedIn Page followers / engagers** — data subjects under §4.10 / §2.3(p). Receive disclosure via the updated Privacy Policy.
2. **Jikigai SARL gérant (Jean Deruelle)** — data subject for the K-bis transfer. Receives disclosure via §5.13 + §6 + §10.
3. **LinkedIn appeal reviewer** — implicit "user" of the privacy-policy URL alignment. Receives the canonical-domain redirect at jikigai.com.

## Success criteria

- AC-Legal-1 through AC-Legal-6 in the plan pass at PR-ready time.
- AC-Compliance-1 passes.
- AC-Infra-1 through AC-Infra-3 pass.
- AC-Spec-Tasks-1 passes (this file + tasks.md exist).
- CLO + CPO sign-off recorded in `knowledge-base/legal/audits/2026-05-counsel-review-4051.md`.
- After merge: operator completes the runbook (expand Cloudflare token scope; update LinkedIn app URL; submit appeal at /help/linkedin/ask/dsapi).

## Domains touched

- **Legal** (lead — CLO required)
- **Product** (CPO required, brand-survival threshold)
- **Marketing** (advisory — CMO carried forward)
- **Infra** (advisory — one Cloudflare ruleset; CTO carried forward)
