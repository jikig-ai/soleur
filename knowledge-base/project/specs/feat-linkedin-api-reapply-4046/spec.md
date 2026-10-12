---
title: LinkedIn Community Management API Re-Application (Jikigai Page Track)
date: 2026-05-19
issue: 4046
parent_issue: 799
branch: feat-linkedin-api-reapply-4046
pr: 4047
brainstorm: knowledge-base/project/brainstorms/2026-05-19-linkedin-community-api-reapply-jikigai-brainstorm.md
brand_survival_threshold: single-user incident
lane: cross-domain
---

# Spec: LinkedIn Community Management API Re-Application

## Problem Statement

LinkedIn rejected Community Management API access for developer app **229658411** on 2026-05-19 with "Business verification failed". The rejection blocks `w_organization_social` scope, which is required for posting to a LinkedIn Company Page. Since 2026-03-24, the `scheduled-content-publisher.yml` workflow has been creating one fallback GitHub issue per blog post that fails to autopost to the (nonexistent) Soleur Company Page — accumulating 9 OPEN issues (#3765, #3467, #3284, #3073, #2863, #2738, #2489, #1886, #1082) and exposing two independent latent bugs in the publisher.

Re-application requires creating a verified **Jikigai** Company Page (LinkedIn's Microsoft-backed business verification cross-references the registered legal entity), DNS TXT verification on **jikigai.com** (must match entity), Microsoft business verification using Jikigai's legal-entity registration, associating the verified Page with the developer app, and re-submitting access request.

## Goals

1. **Re-apply for Community Management API access** under the Jikigai entity with jikigai.com domain verification, with the highest probability of approval given the 2026-05-19 rejection signal.
2. **Fix two independent publisher bugs** that exist regardless of the vendor decision and are load-bearing for the post-approval state.
3. **Eliminate fallback-issue noise** via a rolling-tracker dedup pattern; close the 9 stale fallback issues as superseded.
4. **Onboard jikigai.com to Cloudflare terraform** so DNS TXT verification (and future DNS changes on the zone) are durable IaC.
5. **Establish the post-approval token-rotation + re-trigger runbook** so when approval lands, the 9 superseded articles can be re-published to the new Company Page.

## Non-Goals

- Marketing Developer Platform access (separate approval, gates `fetch-metrics`/`fetch-activity` stubs in `linkedin-community.sh`). Tracked as Open Question 3 in the brainstorm — not in scope here.
- Extracting a `soleur:vendor-approval-track` skill — productize candidate; defer to 2nd recurrence per Phase 2.5.
- Personal LinkedIn audience-growth strategy (CPO's "500 followers or 3 inbound leads" trigger applies if this path is later re-parked).
- LinkedIn analytics ingestion / Sentry posting metrics.
- Multi-Page support; this is a single-Page (Jikigai) implementation.

## Functional Requirements

- **FR1:** `scripts/content-publisher.sh` MUST check `LINKEDIN_ORG_ACCESS_TOKEN` (not `LINKEDIN_ACCESS_TOKEN`) in the company-page pre-check at line 539; current behavior produces a silent fall-through to the fail-fast guard in `linkedin-community.sh:281`.
- **FR2:** `create_linkedin_fallback_issue` (or its caller in `content-publisher.sh`) MUST emit a Sentry event on every silent failure, per `cq-silent-fallback-must-mirror-to-sentry`. Include error reason and case name as event tags.
- **FR3:** When the failure cause is missing `LINKEDIN_ORG_ACCESS_TOKEN` OR an HTTP 401/403 referencing `w_organization_social`, the publisher MUST append/update the rolling tracker issue (default #4046) rather than creating a per-post fallback issue. Append the case name + section to a checklist in the tracker body.
- **FR4:** `apps/web-platform/infra/` MUST add `jikigai.com` as a managed Cloudflare zone with `cloudflare_zone_id_jikigai_com` variable and at minimum the LinkedIn DNS TXT verification record (`cloudflare_record` resource). Apply via the standard `tofu plan` + operator-reviewed apply.
- **FR5:** Issue #4046 body MUST be edited to remove the claim that `fetch-metrics`/`fetch-activity` stubs unblock with Community Management API. Replace with: "Community Management API grants `w_organization_social` only. Analytics stubs are gated on Marketing Developer Platform (separate approval, tracked separately)."
- **FR6:** Issues #3765, #3467, #3284, #3073, #2863, #2738, #2489, #1886, #1082 MUST be closed as `not planned` with a closing comment pointing to #4046 + the new rolling-tracker dedup behavior.
- **FR7:** A LinkedIn Company Page MUST be created under **"Jikigai"** (not "Soleur") with `jikigai.com` listed as the official website.
- **FR8:** The Jikigai Page MUST complete LinkedIn Page Verifications including (a) domain verification via DNS TXT on `jikigai.com` and (b) Microsoft business verification with Jikigai's legal-entity registration.
- **FR9:** The verified Jikigai Page MUST be associated with developer app 229658411 via the LinkedIn Developer Portal.
- **FR10:** Community Management API access MUST be re-submitted via the LinkedIn Developer Portal product-access form.
- **FR11:** Post-approval, `LINKEDIN_ORG_ACCESS_TOKEN` MUST be regenerated via `plugins/soleur/skills/community/scripts/linkedin-setup.sh generate-token` with scope `openid profile w_member_social w_organization_social` and persisted in Doppler.
- **FR12:** Post-token-rotation, the publisher MUST be re-triggered for the 9 superseded articles via `gh workflow run scheduled-content-publisher.yml`.

## Technical Requirements

- **TR1:** Code changes (FR1–FR3) and terraform changes (FR4) are bundled in PR #4047 alongside the brainstorm and spec.
- **TR2:** No new env vars or secrets are introduced; the dual-token model in `linkedin-community.sh` is preserved. Only the **value** of `LINKEDIN_ORG_ACCESS_TOKEN` changes post-approval; the secret name and Doppler path are stable.
- **TR3:** Rolling-tracker append uses idempotent body edit via `gh issue edit <tracker> --body-file -` reading current body + new line; guard against duplicate appends by checking whether the case name is already in the body.
- **TR4:** Sentry mirror uses the existing publisher Sentry-emit pattern (e.g., `content-publisher.sh:323`) — do not introduce a new SDK call style.
- **TR5:** Terraform addition for `jikigai.com` follows the existing `soleur.ai` zone pattern; reuse Cloudflare provider config; no new providers.
- **TR6:** The DNS TXT record value will be sourced from LinkedIn's Page Verifications UI at runtime; the terraform resource will be parameterized via a `linkedin_verification_txt` variable so the actual TXT string is not committed (kept in `terraform.tfvars` or Doppler-injected at apply time).
- **TR7:** Microsoft business verification cannot be Playwright-driven (legal-document upload); operator handles via LinkedIn Page admin UI.
- **TR8:** Article 30 register update (add LinkedIn Ireland as independent controller) happens on **first successful org post**, NOT on application acceptance. Captured as Open Question 2 in the brainstorm.
- **TR9:** After approval and token rotation, verify with `linkedin-setup.sh validate-credentials` that the new token returns `w_organization_social` in the granted-scopes list before any re-trigger.

## Acceptance Criteria

- [ ] `scripts/content-publisher.sh:539` checks `LINKEDIN_ORG_ACCESS_TOKEN`; manual smoke test with the env var unset shows pre-check rejection, not API-layer fail-fast.
- [ ] Sentry receives an event when the publisher hits the company-page silent-failure path (verified via Sentry dashboard after a forced test run).
- [ ] A test run with `LINKEDIN_ORG_ACCESS_TOKEN` unset across two scheduled blog posts produces **one** rolling-tracker update on #4046 (not two new issues).
- [ ] `tofu plan` shows the jikigai.com zone added with the LinkedIn TXT record; `tofu apply` succeeds.
- [ ] #4046 body no longer contains the Marketing API conflation; the corrected text is in place.
- [ ] All 9 listed backlog issues are CLOSED with `state:not planned` and a comment referencing #4046.
- [ ] Jikigai LinkedIn Company Page exists with jikigai.com domain verification complete.
- [ ] Microsoft business verification status on the Page shows verified.
- [ ] Page is associated with developer app 229658411 in LinkedIn Developer Portal.
- [ ] Community Management API access request submitted (screenshot or confirmation captured in PR comments).
- [ ] **Post-approval (async):** `LINKEDIN_ORG_ACCESS_TOKEN` regenerated, `validate-credentials` returns `w_organization_social`, Doppler updated, 9 articles re-published via `gh workflow run`.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Microsoft business verification rejects again (different reason) | Capture the rejection reason verbatim in #4046 comments; CLO + operator iterate on entity/domain/document changes. Re-evaluation criteria in brainstorm trigger a park at ≥2 rejections + 90-day mark. |
| LinkedIn UI changes break Playwright OAuth flow (`linkedin-setup.sh generate-token`) post-approval | Validated against `linkedin-setup.sh` before token rotation; operator runs manual OAuth via browser if Playwright path fails. |
| Approval lands but operator forgets Doppler update | `linkedin-setup.sh generate-token` writes to `.env` AND prints a Doppler upload command; the post-approval checklist in this spec is the operator's runbook. |
| Re-triggering 9 articles produces duplicate posts if some succeeded silently | None of the 9 succeeded — they all created fallback issues, which are auto-filed only on failure. Cross-check before re-trigger. |
| jikigai.com terraform onboarding causes drift with existing manually-managed records on the zone | Pre-onboarding: export current Cloudflare zone state for jikigai.com via the Cloudflare MCP server or dashboard; import records before applying. |

## Out of Scope (Tracked Separately)

- **Marketing Developer Platform re-application** — file as a sibling issue if analytics ingestion becomes needed (Open Question 3 in brainstorm).
- **`soleur:vendor-approval-track` skill extraction** — productize candidate; defer to 2nd recurrence.
- **LinkedIn Sentry posting-metric ingestion** — analytics path, not part of this work.
- **Multi-Page support** — single-Page (Jikigai) only.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-19-linkedin-community-api-reapply-jikigai-brainstorm.md`
- Original scoping brainstorm: `knowledge-base/project/brainstorms/2026-03-13-linkedin-api-scripts-brainstorm.md`
- Scope-calibration learning: `knowledge-base/project/learnings/2026-03-13-platform-integration-scope-calibration.md`
- Silent-fallback learning: `knowledge-base/project/learnings/2026-04-26-linkedin-org-token-fallback-silent-400.md`
- Dual-token learning: `knowledge-base/project/learnings/2026-04-09-linkedin-org-access-token-for-company-page-posts.md`
- Parent vendor track: GitHub issue #799
- Symptom backlog (to close): #3765, #3467, #3284, #3073, #2863, #2738, #2489, #1886, #1082
- LinkedIn community script: `plugins/soleur/skills/community/scripts/linkedin-community.sh`
- LinkedIn setup script: `plugins/soleur/skills/community/scripts/linkedin-setup.sh`
- Publisher script: `scripts/content-publisher.sh`
- Publisher workflow: `.github/workflows/scheduled-content-publisher.yml`
- Cloudflare terraform root: `apps/web-platform/infra/`
