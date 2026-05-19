---
title: Tasks — LinkedIn Community Management API Re-Application (Jikigai)
date: 2026-05-19
issue: 4046
plan: knowledge-base/project/plans/2026-05-19-feat-linkedin-api-reapply-jikigai-plan.md
branch: feat-linkedin-api-reapply-4046
pr: 4047
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks — feat-linkedin-api-reapply-4046

Derived from the plan. Track each task by checking the box. Plan + brainstorm + spec are the source of truth for context; this file is the actionable breakdown.

## Phase 0 — Preconditions

- [x] **0.1** Sentry-mirror rule scope confirmed (TS/pino only, not bash) — verified in plan authoring
- [x] **0.2** Article 30 register next PA slot confirmed = PA15
- [x] **0.3** `.github/workflows/scheduled-linkedin-token-check.yml` existence + current env-var coverage confirmed
- [x] **0.4** OQ1/OQ2 resolved by terraform-architect (mint narrow token; defer zone-import)

## Phase 1 — Workflow + publisher contract change (single atomic commit)

- [x] **1.1** Edit `.github/workflows/scheduled-content-publisher.yml` — add `LINKEDIN_ORG_ACCESS_TOKEN` to env block (line ~63), with one-line comment
- [x] **1.2** Edit `scripts/content-publisher.sh:539` — change pre-check env var to `LINKEDIN_ORG_ACCESS_TOKEN`; update warning text; replace `return 0` with `append_to_linkedin_tracker` call + `return 0` (forward reference to Phase 2)
- [x] **1.3** Edit `.github/workflows/scheduled-linkedin-token-check.yml`:
  - [x] **1.3.1** Add `LINKEDIN_ORG_ACCESS_TOKEN` to env block (line ~30)
  - [x] **1.3.2** Convert introspection logic to iterate over both tokens (lines ~36-46)
  - [x] **1.3.3** Update alert body template to name which token expired (lines ~52-66)
- [x] **1.4** Commit: `feat(content-publisher): wire LINKEDIN_ORG_ACCESS_TOKEN through publisher + token monitor`

## Phase 2 — Rolling-tracker dedup + error-class routing

- [x] **2.1** Add script-level constant `LINKEDIN_TRACKER_REASON_MISSING_TOKEN` to `scripts/content-publisher.sh`
- [x] **2.2** Add `classify_linkedin_error(error_reason)` function returning `vendor-blocked` or `content-rejected` (drop the `transient` class per code-simplicity review)
- [x] **2.3** Add `append_to_linkedin_tracker(case_name, section, error_reason)` function (no recursion guard — log + `return 1` on failure)
- [x] **2.4** Modify `create_linkedin_fallback_issue` to route via `classify_linkedin_error`: vendor-blocked → `append_to_linkedin_tracker`; default → existing `create_dedup_issue`
- [x] **2.5** Smoke test: token unset + valid tracker → tracker grows by 1 line, second run no-op
- [x] **2.6** Smoke test: invalid tracker → stderr warning + return 1 (no recursion)
- [x] **2.7** Commit: `feat(content-publisher): rolling-tracker dedup with explicit error-class routing`

## Phase 3 — Terraform jikigai.com onboarding + Article 30 register

- [x] **3.1** Edit `apps/web-platform/infra/variables.tf` — append 3 variables (`cf_zone_id_jikigai_com`, `cf_api_token_jikigai_com` sensitive, `linkedin_page_verification_txt` sensitive) with descriptions per plan
- [x] **3.2** Edit `apps/web-platform/infra/main.tf` — extend `terraform.required_providers.cloudflare.configuration_aliases` with `cloudflare.jikigai_com`
- [x] **3.3** Create `apps/web-platform/infra/jikigai-com.tf`:
  - [x] **3.3.1** 5th `provider "cloudflare"` block aliased as `jikigai_com`
  - [x] **3.3.2** `cloudflare_record "linkedin_verification"` resource (no `lifecycle.ignore_changes`)
  - [x] **3.3.3** `comment = "managed_by:terraform; purpose:linkedin-page-verification; issue:#4046"`
- [x] **3.4** Edit `knowledge-base/legal/article-30-register.md` — append PA15 entry with full Art. 30(1)(a-g) coverage including K-bis natural-person disclosure footnote
- [x] **3.5** Validate config-phase: `terraform init -input=false` + `doppler run … -- terraform validate` from `apps/web-platform/infra/`
- [x] **3.6** Commit: `feat(infra): onboard jikigai.com Cloudflare zone for LinkedIn verification + Art. 30 PA15`

## Phase 4 — Backlog closure + follow-up issues

- [x] **4.1** Verify #4046 body correction present (done in brainstorm phase): `gh issue view 4046 --json body --jq .body | grep -F "Marketing Developer Platform"`
- [x] **4.2** Close 9 superseded backlog issues with `gh issue close … --reason "not planned"` loop
- [x] **4.3** Verify all 9 are CLOSED with `stateReason: NOT_PLANNED`
- [x] **4.4** Commit: `chore(content-publisher): close 9 LinkedIn-API fallback issues superseded by #4046`
- [x] **4.5** Filed 2 follow-up issues during plan authoring:
  - [x] **4.5.1** F1 = #4051 — Legal-track PR (LIA + Privacy Policy + DPD); blocks Phase 5.4
  - [x] **4.5.2** F6 = #4052 — jikigai.com existing-DNS terraform import
- [x] **4.6** Update PR #4047 body: `Ref #4046`, `Closes #3765 #3467 #3284 #3073 #2863 #2738 #2489 #1886 #1082`, links to #4051 + #4052, Post-merge checklist for Phases 5-6

## Phase 5 — Post-merge operator runbook (async, days; tracked in PR body)

- [ ] **5.1** Create Jikigai LinkedIn Company Page via Playwright (operator OAuth-consents once; Playwright drives form fields)
- [ ] **5.2** Apply DNS TXT via Terraform:
  - [ ] **5.2.1** Set `TF_VAR_linkedin_page_verification_txt`, `TF_VAR_cf_zone_id_jikigai_com`, `TF_VAR_cf_api_token_jikigai_com` in Doppler `prd_terraform`
  - [ ] **5.2.2** From `apps/web-platform/infra/`: `terraform init -input=false`; `doppler run … -- terraform plan -target=cloudflare_record.linkedin_verification`; confirm `1 to add`
  - [ ] **5.2.3** `doppler run … -- terraform apply -target=cloudflare_record.linkedin_verification`
  - [ ] **5.2.4** Post-targeted-apply: `doppler run … -- terraform plan` (untargeted); confirm `No changes` (per AC24)
- [ ] **5.3** Verify TXT via LinkedIn UI (Playwright clicks "Verify"); on failure, `dig +short +time=5 +tries=2 TXT <fqdn>`
- [ ] **5.4** **(BLOCKED until F1 merges)** Microsoft business verification: upload Jikigai K-bis + tax + address proof via LinkedIn Page admin UI
- [ ] **5.5** Associate verified Page with developer app 229658411 (Playwright)
- [ ] **5.6** Re-submit Community Management API access (Playwright); capture confirmation screenshot to PR comments
- [ ] **5.7** Await LinkedIn approval (1-5 business days)

## Phase 6 — Post-approval token rotation + 9-article re-trigger

- [ ] **6.1** Regenerate token via `plugins/soleur/skills/community/scripts/linkedin-setup.sh generate-token` with scope `openid profile w_member_social w_organization_social`
- [ ] **6.2** Validate: `linkedin-setup.sh validate-credentials` returns `w_organization_social` in granted scopes
- [ ] **6.3** Persist:
  - [ ] **6.3.1** `doppler secrets set LINKEDIN_ORG_ACCESS_TOKEN=<new-token> -p soleur -c prd`
  - [ ] **6.3.2** `printf '%s' <new-token> | gh secret set LINKEDIN_ORG_ACCESS_TOKEN`
- [ ] **6.4** Burst-publish 9 superseded articles: set `publish_date: <today>` in all 9 files, commit + push, `gh workflow run scheduled-content-publisher.yml --ref main`
- [ ] **6.5 (gated on F1 PR landed)** Verify each post landed on Page via Playwright (`https://www.linkedin.com/company/jikigai/posts/`); check off `- [ ] Re-publish: ...` lines in #4046 body
- [ ] **6.6** Close #4046 with `--reason completed` once all 9 verified live

## Acceptance Criteria mapping

See plan's `## Acceptance Criteria` section. Pre-merge AC1-AC14 map to Phases 1-4. Post-merge AC15-AC24 map to Phases 5-6.

## Risks

See plan's `## Risks & Mitigations` section. Top risk: Microsoft business verification rejects again (≥2 rejections + 90-day mark → re-park per brainstorm Re-evaluation Criteria).
