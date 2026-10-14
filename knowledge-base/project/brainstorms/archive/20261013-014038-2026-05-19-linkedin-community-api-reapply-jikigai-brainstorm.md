---
title: LinkedIn Community Management API Re-Application (Jikigai Page Track)
date: 2026-05-19
issue: 4046
parent_issue: 799
branch: feat-linkedin-api-reapply-4046
pr: 4047
status: brainstorm-complete
brand_survival_threshold: single-user incident
lane: cross-domain
---

# Brainstorm: LinkedIn Community Management API Re-Application

## What We're Building

A full re-application track for LinkedIn Community Management API access (app 229658411), under the **Jikigai** legal entity rather than the Soleur product name, plus the engineering fixes the rejection investigation surfaced as independent latent bugs.

In-scope for this PR:

1. **Publisher bugs (independent of vendor decision):**
   - Fix `scripts/content-publisher.sh:539` — pre-check tests `LINKEDIN_ACCESS_TOKEN` instead of `LINKEDIN_ORG_ACCESS_TOKEN` for the company-page path; will silently fall through to fail-fast at the API client level.
   - Add Sentry mirror to `create_linkedin_fallback_issue` per `cq-silent-fallback-must-mirror-to-sentry`.
   - Replace per-post fallback-issue creation with a rolling-tracker dedup: when the failure cause is missing `LINKEDIN_ORG_ACCESS_TOKEN` (or HTTP 401/403 + `w_organization_social`), append/update **one** rolling tracker issue (default: #4046) with the affected case name instead of filing a new issue per blog post.

2. **Terraform: onboard jikigai.com:**
   - Add `jikigai.com` Cloudflare zone to `apps/web-platform/infra/` (currently only soleur.ai is managed).
   - Provision the LinkedIn DNS TXT verification record via `cloudflare_record` (value will be sourced from the LinkedIn Page Verifications step).
   - Add `cloudflare_zone_id_jikigai_com` to `variables.tf`.

3. **Issue-body correction:**
   - Edit #4046 to remove the conflation between Community Management API (grants `w_organization_social` only) and Marketing Developer Platform (gates `fetch-metrics` / `fetch-activity` stubs — separate approval).

4. **Backlog cleanup:**
   - Close #3765, #3467, #3284, #3073, #2863, #2738, #2489, #1886, #1082 as superseded by #4046 with a comment pointing to the new rolling-tracker dedup.

5. **Operator runbook execution (driven from this PR, async over days):**
   - Create the Jikigai Company Page (Playwright-assisted where LinkedIn permits; manual otherwise).
   - Apply DNS TXT via terraform, then click verify in LinkedIn UI.
   - Microsoft business verification using Jikigai's legal-entity registration documents (manual, founder-driven).
   - Associate verified Page with app 229658411.
   - Re-submit Community Management API access request.
   - Post-approval: rotate `LINKEDIN_ORG_ACCESS_TOKEN` via `linkedin-setup.sh generate-token`; update Doppler.
   - Re-trigger publisher for the 9 closed-as-superseded articles via `gh workflow run scheduled-content-publisher.yml`.

## Why This Approach

**Entity choice — Jikigai over Soleur (CLO).** Microsoft business verification cross-references the registered business; the entity that actually exists in business registries is Jikigai. Verifying as "Soleur" would fail unless Soleur becomes a registered DBA of Jikigai (premature). Page transferability is also cleaner: a Jikigai-owned Page asset transfers via LinkedIn support if Soleur ever spins out; a "Soleur" Page tied to Jikigai's verification creates an attribution mismatch we'd have to unwind.

**Domain choice — jikigai.com over soleur.ai (CLO).** Microsoft verification cross-references the verified domain against the registered business; soleur.ai would create the same name-mismatch flag that contributed to the original rejection. `jikigai.com` will be added to the existing Cloudflare terraform root so future jikigai.com DNS changes are durable (compound interest on the IaC investment).

**Ship the publisher bugs in the same PR (CTO).** The env-var pre-check bug and the Sentry-mirror gap are real defects today, independent of the vendor decision. They are also load-bearing for the rolling-tracker dedup: without the fix, post-approval rotation that touches only `LINKEDIN_ACCESS_TOKEN` (which the workflow exports) would pass the wrong pre-check, hit fail-fast in `linkedin-community.sh:281`, and re-start the silent-noise problem.

**Pursue rather than park (operator override of CPO).** CPO recommended parking the track citing the 56-day silent gap as validation that org-posting has no audience. Operator accepts the cost/benefit asymmetry on the LinkedIn side but values the Jikigai Page asset as a brand-presence stake separate from immediate-audience math; founder-grade SOC2-readiness posture also benefits from having credential-rotation runbooks battle-tested. Disagreement recorded in the Domain Assessments section.

**Rolling-tracker dedup as proto-pattern (CTO productize candidate).** The "vendor-approval-gated capability with stale fallback noise" pattern recurs for X API tier upgrades, Marketing Developer Platform (the stub-claim error in #4046 itself), Stripe Connect verification, Apple Developer enrollment. Build the dedup narrow for LinkedIn now; extract to a `soleur:vendor-approval-track` skill on the 2nd recurrence, not the 1st.

## User-Brand Impact

**Artifact:** LinkedIn org-page distribution channel and `LINKEDIN_ORG_ACCESS_TOKEN` credential.

**Vector:** (a) sloppy re-application metadata (wrong entity name, wrong domain) could get app 229658411 flagged or banned, foreclosing org-page access for the lifetime of the app; (b) silent fallback on a wrong env-var pre-check has been producing 9+ stale fallback issues over 56 days and would continue post-approval if not fixed; (c) 60-day token rotation with no programmatic refresh is a known credential-hygiene gap, currently mitigated by a Discord-alert-at-14-days monitor.

**Threshold:** single-user incident. The "single user" here is the Soleur operator (Jean) and indirectly any tenant whose content gets posted; a credential leak during regeneration or a wrongly-attributed Page post would impact founder/brand trust directly.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Pursue re-application under **Jikigai** entity, not Soleur | Microsoft business verification matches legal entity; Soleur is a product mark, not a registered DBA |
| 2 | Use **jikigai.com** for DNS TXT verification | Must match entity; soleur.ai mismatch contributed to the original rejection |
| 3 | Onboard jikigai.com to terraform in this PR | Compound IaC investment; no manual Cloudflare drift |
| 4 | Ship publisher env-var fix + Sentry mirror in this PR | Independent latent bugs; load-bearing for the rolling-tracker dedup |
| 5 | Replace per-post fallback issues with a rolling tracker (#4046 by default) | 9 distinct issues over 56 days is dedup failure; one rolling tracker per vendor-approval-gated capability is the right shape |
| 6 | Close 9 stale fallback issues as superseded; re-trigger publisher post-approval | They are auto-artifacts of the missing API, not user requests; re-trigger produces correct attribution to the new Page |
| 7 | Edit #4046 body to remove Marketing API conflation | Marketing Developer Platform is a separate approval gating `fetch-metrics`/`fetch-activity`; future agents shouldn't inherit the misframing |
| 8 | Defer extraction of `soleur:vendor-approval-track` skill | Productize candidate — extract on 2nd recurrence (X API tier upgrade likely), not 1st |
| 9 | Founder-driven Microsoft business verification (manual) | Legal-entity document upload cannot be Playwright-driven safely |
| 10 | Token rotation post-approval via existing `linkedin-setup.sh generate-token` | Already automated; no new code path needed |

## Open Questions

1. **LinkedIn Page Verifications UI surface coverage.** Whether DNS TXT verification can be triggered fully via Playwright vs. requires login-bound human interaction is undetermined; the runbook will record actual coverage on first execution.
2. **Article 30 register update timing.** CLO flagged that LinkedIn Ireland becomes an independent controller (controller-to-controller, not processor) for posted content. Update the register on first successful org post, not on application acceptance, to avoid premature entry.
3. **`fetch-metrics`/`fetch-activity` deferred work.** Confirmed as Marketing Developer Platform-gated; do we file a sibling tracker for Marketing API re-application after Community Management API approval lands, or wait until analytics is genuinely needed?
4. **9 backlog re-trigger ordering.** When re-triggering the publisher post-approval, do we re-publish in original schedule order (oldest first) or skip the oldest (e.g., #1082 from 2026-03-24 is 56 days stale and may not be relevant anymore)?

## Productize Candidate

- **`soleur:vendor-approval-track`** — pattern: rolling tracker issue per vendor-approval-gated capability, dedup of failure-mode fallback issues, optional cron probe to detect approval landing. Defer extraction; build narrow inline for LinkedIn now.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO)

### Product (CPO)

**Summary:** Recommended **parking the track** (close #4046 + #799 + 9 backlog as `wontfix`, re-open trigger at 500 personal-LinkedIn followers OR 3 inbound LinkedIn leads). Cited the 56-day silent gap as validation that org-posting infrastructure runs ahead of audience. **Operator overrode** — pursuing re-application because the Jikigai Page is a brand-presence stake separate from immediate audience math and the credential-rotation runbook is load-bearing for SOC2 readiness. Disagreement recorded explicitly.

### Legal (CLO)

**Summary:** If pursuing, **Jikigai entity + jikigai.com domain** is the only viable pairing for Microsoft business verification (no DBA, no mismatch). LinkedIn (Ireland) becomes an independent controller — not processor — once org posting goes live; add to Article 30 register at that point, not at application acceptance. Posts containing user/tenant-derived content require consent under the lawful-basis analysis. 60-day token rotation is defensible as a SOC2 compensating control if documented (the Discord-alert-at-14 monitor is the compensating mechanism).

### Engineering (CTO)

**Summary:** Found **two independent bugs** that should ship regardless of the vendor decision: (a) `scripts/content-publisher.sh:539` checks the wrong env var for the company-page path; (b) `create_linkedin_fallback_issue` lacks Sentry mirror, violating `cq-silent-fallback-must-mirror-to-sentry`. **DNS TXT automatable** via Cloudflare terraform (jikigai.com needs onboarding — currently only soleur.ai zone is managed). **1 of 5** runbook steps (DNS TXT) is meaningfully automatable; the other 4 are LinkedIn-UI-bound. Issue #4046 body has a factual error conflating Community Management API with Marketing Developer Platform; should be corrected.

## Capability Gaps

None — every capability needed for this work exists or is being added in scope:

- DNS TXT automation: Cloudflare terraform root exists at `apps/web-platform/infra/` (verified — `variables.tf:81` confirms `cloudflare_zone_id_soleur_ai`); adding `jikigai.com` is an in-scope additive change, not a missing capability.
- Token regeneration: `plugins/soleur/skills/community/scripts/linkedin-setup.sh generate-token` exists (verified — file present in worktree).
- Token validation: `linkedin-setup.sh validate-credentials` uses LinkedIn's introspection endpoint (verified per `2026-03-13-linkedin-api-scripts-brainstorm.md`).
- Sub-processor / Article 30 register: `knowledge-base/legal/article-30-register.md` and `knowledge-base/legal/tenant-dpa-register.md` exist (per CLO grep) — additive entry, not new infrastructure.

## Re-evaluation Criteria

Pursue path becomes a re-park candidate if **all** of the following hold simultaneously at the 90-day mark (2026-08-17):

- Microsoft business verification has been rejected ≥2 times
- Personal LinkedIn account still under 100 followers
- Zero inbound leads attributed to LinkedIn in any quarter

In that case, close #4046 as `wontfix` and absorb the publisher fixes / terraform changes as standalone keep-arounds (they have value independent of LinkedIn).
