---
title: "feat: re-apply LinkedIn Community Management API as Jikigai + publisher hardening + jikigai.com onboarding"
date: 2026-05-19
issue: 4046
parent_issue: 799
branch: feat-linkedin-api-reapply-4046
worktree: .worktrees/feat-linkedin-api-reapply-4046/
pr: 4047
spec: knowledge-base/project/specs/feat-linkedin-api-reapply-4046/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-19-linkedin-community-api-reapply-jikigai-brainstorm.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
type: feature
classification: ops-and-vendor-admin-mixed
---

# Plan: LinkedIn Community Management API Re-Application (Jikigai)

## Overview

LinkedIn rejected Community Management API access for developer app **229658411** with "Business verification failed". Re-applying requires the Page to be owned by **Jikigai SARL** (the registered legal entity, not Soleur) with **jikigai.com** domain verification (per the CLO assessment; entity-domain mismatch is the most likely root cause of the original rejection). The investigation surfaced two latent publisher bugs that have produced one fallback GitHub issue per failed blog post for 56 days (9 OPEN: #3765, #3467, #3284, #3073, #2863, #2738, #2489, #1886, #1082) and one credential-rotation symmetry bug in `scheduled-linkedin-token-check.yml` that would silently leave the future `LINKEDIN_ORG_ACCESS_TOKEN` unmonitored.

This PR ships engineering decoupled from vendor approval (publisher env-var fix, rolling-tracker dedup with explicit error-class routing matrix, jikigai.com Terraform onboarding via a narrow new Cloudflare API token, Article 30 register entries per CLO's Critical finding, backlog cleanup, #4046 body correction), then drives the operator runbook to token rotation + 9-article re-publish post-approval. A separate follow-up legal-track PR (LIA + Privacy Policy + DPD updates) must land **before Phase 6.5** (first content post).

## Research Insights

### From repo + learnings (carry-forward from brainstorm, verified by direct read)

- `plugins/soleur/skills/community/scripts/linkedin-community.sh:279-286` — fail-fast for missing `LINKEDIN_ORG_ACCESS_TOKEN` (per `2026-04-26-linkedin-org-token-fallback-silent-400.md`).
- `plugins/soleur/skills/community/scripts/linkedin-setup.sh` — exposes `generate-token` (Playwright OAuth) and `validate-credentials` (token introspection).
- `scripts/content-publisher.sh:641 create_dedup_issue` — dedups on exact title match only; LinkedIn fallback titles include `$CASE_NAME` → no dedup → 9 separate issues.
- `.github/workflows/scheduled-content-publisher.yml:60-63` exports `LINKEDIN_ACCESS_TOKEN` + `LINKEDIN_PERSON_URN` + `LINKEDIN_ORG_ID` + `LINKEDIN_ALLOW_POST` but **never `LINKEDIN_ORG_ACCESS_TOKEN`**. Workflow has `concurrency.group: scheduled-content-publisher` (line 19-21), so concurrent-publisher races on the rolling tracker are mitigated at the workflow level.
- `.github/workflows/scheduled-linkedin-token-check.yml:30-43` — only monitors `LINKEDIN_ACCESS_TOKEN`. Post-approval, `LINKEDIN_ORG_ACCESS_TOKEN` would have no expiry monitoring. **Fix inline** (was OQ4, resolved P0).
- `apps/web-platform/infra/main.tf:55-90` declares 4 `provider "cloudflare"` blocks scoped to soleur.ai narrow tokens. `required_providers` needs `cloudflare/cloudflare ~> 4.0` and the new provider alias added to `configuration_aliases` to satisfy `terraform init` cleanly.
- `apps/web-platform/infra/dns.tf` is the canonical site for `cloudflare_record`; the new jikigai.com resources land in a sibling file to keep zone-scoped concerns isolated.
- `knowledge-base/legal/article-30-register.md` is at version 0.1.0-draft, controller = "Jikigai SARL", 14 existing Processing Activities. Next PA number = **PA15**.

### Skipped agents

- **repo-research-analyst + learnings-researcher (Phase 1.1)** — brainstorm 30 min earlier ran both with full scope; CTO assessment provided file:line evidence verified here by direct Read. Plan-time re-invocation would duplicate.
- **External research (Phase 1.6b)** — strong local context (4 LinkedIn learnings, prior shipped scripts, CLO entity/domain pairing decision). LinkedIn docs load-bearing only for the operator runbook; captured at runbook execution time.
- **`functional-discovery`** ran and returned no useful community alternative (closest hit `@sjnims/requirements-expert/shared-patterns` is Tier 3 unverified, scoped to a `/re:*` taxonomy unrelated to vendor-gated CI capabilities). Proceed inline.

### Skill description budget

- No `plugins/soleur/skills/*/SKILL.md description:` edits are candidate in this PR. Phase 1 baseline + Step 2 re-check both N/A.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "Add Sentry mirror to `content-publisher.sh` per `cq-silent-fallback-must-mirror-to-sentry`" (CTO) | Rule body in `AGENTS.rest.md` reads: "mirror the pino `logger.error`/`warn` to Sentry … Use `reportSilentFallback(err, { feature, op?, extra? })` from `@/server/observability`." Scope is **TypeScript/Next.js server with pino**, not bash. The publisher's failure mode is also not silent — issue + workflow annotation. | **DROPPED.** Defect is per-post-issue noise (dedup gap), not silent failure. Spec FR2 dropped; no Sentry phase. |
| "`scripts/content-publisher.sh:539` checks `LINKEDIN_ACCESS_TOKEN`" (CTO) | Line 539 confirmed; workflow `:60-63` never exports `LINKEDIN_ORG_ACCESS_TOKEN`. | **Two-file atomic fix in Phase 1**, plus 3rd file (`scheduled-linkedin-token-check.yml`) added by spec-flow P2-3 fold-in. |
| "Onboard jikigai.com to Cloudflare terraform" | Four `cf_api_token*` are soleur.ai-scoped; `cloudflare/cloudflare ~> 4.0` is in use; `required_providers` block needs `configuration_aliases` extension. | **OQ1/OQ2 RESOLVED by terraform-architect P1 fold-ins:** mint NEW narrow `cf_api_token_jikigai_com` (DNS:Edit on jikigai.com only); defer zone-import; scope PR to TXT-only via aliased provider. |
| "Article 30 register update for LinkedIn Ireland on first post" (CLO brainstorm) | GDPR Art. 30(1) is a pre-processing obligation; EDPB Guidelines 1/2021 §31, CNIL guidance; *Wirtschaftsakademie* C-210/16 establishes joint-controller for Page Insights. **First cross-controller transfer is Microsoft business verification (Phase 5.4), not first post.** | **CRITICAL fold-in:** Article 30 entries added in **Phase 3** (this PR) before Phase 5.4. LIA + Privacy Policy + DPD updates deferred to **follow-up legal-track PR that must land before Phase 5.4**. |
| "Microsoft business verification is outside Art. 28 processor scope" (CLO brainstorm) | Jikigai SARL has named gérant (Jean) on the K-bis extract Microsoft ingests. CNIL délibération SAN-2024-006 treated K-bis transmission as personal-data processing. | **HIGH fold-in:** Phase 3 Article 30 entry treats this as controller-to-controller transfer of Jean's personal data; documented in PA15. |
| "`linkedin-token-check.yml` env-var fix as follow-up" (brainstorm OQ4) | Workflow exists at `.github/workflows/scheduled-linkedin-token-check.yml`; it only checks `LINKEDIN_ACCESS_TOKEN`. Post-approval, the org token would have no expiry monitor — same symmetry defect as the publisher. | **Promoted to Phase 1.3** (in-PR fix); the rotation safety-net must cover both tokens before Phase 6.3 rotates the org token. |
| "Per-section `status: published` flag for re-trigger idempotency" (spec-flow P1-3) | `knowledge-base/marketing/distribution-content/*.md` files use a single `status` frontmatter field today; no per-section state. | **DEFER to follow-up issue.** This is a schema change touching every distribution-content file + the publisher's frontmatter parser; over-scope for this PR. Phase 6.5 uses a manual cross-check (the 9 articles are known by name) instead. |

## User-Brand Impact

**If this lands broken, the user experiences:** the operator continues to lose LinkedIn Company Page distribution. If the publisher env-var bug or the token-check env-var bug are not fixed in this PR, post-approval token rotation silently regresses to the pre-fix state (workflow exports wrong token name → publisher pre-check passes on wrong env → API returns 400 → rolling tracker accumulates again, OR token expires unmonitored at day 60).

**If this leaks, the user's credentials are exposed via:** the regenerated `LINKEDIN_ORG_ACCESS_TOKEN` lifecycle. 60-day expiry, no programmatic refresh tokens (LinkedIn platform limitation). Mitigation: extended `linkedin-setup.sh validate-credentials` + `scheduled-linkedin-token-check.yml` (after Phase 1.3 fix, covers both tokens; 14/7-day Discord alerts) + Doppler-only storage. Microsoft business verification flow surfaces Jikigai's K-bis (including gérant Jean's name) to LinkedIn Ireland / Microsoft Ireland (controller-to-controller per CLO, NOT B2B-only — natural-person disclosure per CNIL SAN-2024-006).

**Brand-survival threshold:** `single-user incident`

The "single user" is the Soleur operator (Jean) and any tenant whose content is later posted. **`requires_cpo_signoff: true`** in frontmatter. CPO covered framing in brainstorm Domain Assessments (recommendation overridden; sign-off carries forward). `user-impact-reviewer` invoked at PR review per `plugins/soleur/skills/review/SKILL.md` conditional-agent block.

## Domain Review

**Domains relevant:** Product (CPO), Engineering (CTO), Legal (CLO), Operations (vendor admin)

**Carry-forward source:** `knowledge-base/project/brainstorms/2026-05-19-linkedin-community-api-reapply-jikigai-brainstorm.md` `## Domain Assessments` + plan-time augmentation from terraform-architect, gdpr-gate (legal-compliance-auditor), and spec-flow-analyzer.

### Product (CPO)

**Status:** reviewed (carry-forward)
**Assessment:** Recommended park; operator overrode for Jikigai-Page brand-stake + SOC2 runbook value. Sign-off carries forward as plan-time CPO ack.

### Legal (CLO) — plan-time deepened by gdpr-gate

**Status:** reviewed (carry-forward + plan-time augmentation)
**Assessment:** Jikigai SARL entity + jikigai.com pairing is the only viable verification path. Plan-time deepening surfaced **1 Critical, 3 High, 3 Medium, 2 Low** findings. CRITICAL Art. 30 timing folded inline (Phase 3 in this PR). HIGH findings (LIA, Privacy Policy, DPD) routed to a follow-up legal-track PR that must land before Phase 5.4 operator action. MEDIUM findings (Page Insights joint-controller, tenant consent capture, OQ4 inline) — first two follow-up, last folded as Phase 1.3.

### Engineering (CTO) — plan-time deepened by terraform-architect + spec-flow-analyzer

**Status:** reviewed (carry-forward + plan-time augmentation)
**Assessment:** Sentry-mirror recommendation dropped (rule out of scope for bash). Three engineering defects (publisher env-var, workflow secret export, token-check env-var symmetry) all folded into this PR. Terraform onboarding hardened: mint new narrow token, defer zone-import, drop `ignore_changes`, document `-target` apply caveat, add `configuration_aliases` to `main.tf`. Rolling-tracker error-class routing matrix expanded to cover token-expired (401) and scope-revoked (403) paths so post-rotation drift cannot silently regress to per-post issue noise.

### Product/UX Gate

**Tier:** NONE — no user-facing UI surface (publisher is server-side cron; LinkedIn UI is vendor's). Skip.

## Infrastructure (IaC)

Per `hr-all-infrastructure-provisioning-servers` and Phase 2.8 routing gate: new DNS lives in terraform, not the Cloudflare dashboard.

### Terraform changes

**Files to edit:**

- `apps/web-platform/infra/variables.tf` — add `cf_zone_id_jikigai_com`, `cf_api_token_jikigai_com` (sensitive, narrow), `linkedin_page_verification_txt` (sensitive).
- `apps/web-platform/infra/main.tf` — extend `terraform.required_providers.cloudflare.configuration_aliases` to include `cloudflare.jikigai_com` (per terraform-architect P2-1).

**Files to create:**

- `apps/web-platform/infra/jikigai-com.tf` — (a) 5th `provider "cloudflare" { alias = "jikigai_com"; api_token = var.cf_api_token_jikigai_com }`, (b) `resource "cloudflare_record" "linkedin_verification"` with `provider = cloudflare.jikigai_com`, `zone_id = var.cf_zone_id_jikigai_com`, `comment = "managed_by:terraform; purpose:linkedin-page-verification; issue:#4046"`. **No `lifecycle.ignore_changes`** per terraform-architect P1-3 (LinkedIn verification tokens are stable post-verification; ignoring would silently absorb dashboard drift).

**Required providers + version pins:** reuse existing `cloudflare/cloudflare ~> 4.0`. No new providers. Provider 5.x renames the resource to `cloudflare_dns_record`; flagged for forward-migration follow-up by terraform-architect P2-4.

**Sensitive variable sources (TF_VAR_* via Doppler `prd_terraform`):**

- `TF_VAR_cf_zone_id_jikigai_com` — Cloudflare zone ID; mint at Cloudflare dashboard after onboarding jikigai.com to the Soleur Cloudflare account; copy to Doppler.
- `TF_VAR_cf_api_token_jikigai_com` — narrow token, **DNS:Edit on jikigai.com only** (per terraform-architect P1-1; do NOT widen existing soleur.ai token).
- `TF_VAR_linkedin_page_verification_txt` — TXT value provided by LinkedIn at Page Verifications step. Not committed. Set via `doppler secrets set` immediately before `terraform apply`.

### Apply path

**Chosen path:** (a) cloud-init-only — jikigai.com is not yet in TF state.

**OQ2 resolved (defer zone-import):** jikigai.com carries existing MX/SPF/DKIM for ops@jikigai.com (per `disk-monitor.sh:75`). Importing those records carries footgun risk for ops@ email. Scope this PR to the LinkedIn TXT only via the aliased narrow-token provider, leave pre-existing records dashboard-managed. File deferred-scope-out: "import jikigai.com existing DNS to terraform".

**Apply caveat (terraform-architect P1-4):** Phase 5.2 applies via `terraform apply -target=cloudflare_record.linkedin_verification`. This is acceptable because the aliased provider isolates blast radius to jikigai.com. **Post-targeted-apply, run an untargeted `terraform plan` (same session) and confirm `No changes`** on soleur.ai resources; this surfaces any cross-zone state drift the targeted apply silently missed.

**Expected blast radius:** zero existing-records change. One new TXT record at `_linkedin-challenge.<TBD-prefix>.jikigai.com` (exact subdomain provided by LinkedIn at Verifications time).

### Distinctness / drift safeguards

- New zone logically separate from soleur.ai; no cross-zone `lifecycle.ignore_changes`.
- `terraform.tfstate` (R2 backend at `web-platform/terraform.tfstate`) holds the TXT value; sensitive variable already marked `sensitive` in the schema. R2 encrypts at rest by default with provider-managed AES-256 keys; LinkedIn verification token is single-purpose + becomes public TXT post-verification (low residual sensitivity).
- `dev != prd` precondition: this PR's TF changes apply only via Doppler `prd_terraform`. No `dev_terraform` mirror needed.

### Vendor-tier reality check

- Cloudflare DNS zone onboarding + records: free tier.
- LinkedIn Page Verifications + Microsoft business verification: free.

## GDPR / Compliance Gate Output

Brand-survival threshold = `single-user incident` triggers the gate. Plan-time invocation of `legal-compliance-auditor` returned (full report in CLO Domain Review):

- **Critical:** Article 30(1) timing — register entry MUST exist before Phase 5.4 Microsoft business verification (the first cross-controller personal-data transfer). Folded inline in **Phase 3** (this PR adds PA15 + recipient rows).
- **High-1:** LIA + new PA-row for org-page posts pre-Phase-6.5. **Routed to follow-up legal-track PR (must land before Phase 5.4).**
- **High-2:** Jikigai SARL has named gérant; Microsoft K-bis ingestion IS controller-to-controller personal-data transfer (Jean's name). Folded into PA15 row in Phase 3.
- **High-3:** Privacy Policy + DPD updates (Art. 13(1)(e) LinkedIn recipient disclosure; Art. 17 carve-out for LinkedIn-published content). **Routed to follow-up legal-track PR (must land before Phase 5.4 or Phase 6.5).**
- **Medium-1:** OQ4 `scheduled-linkedin-token-check.yml` env-var symmetry — folded as Phase 1.3.
- **Medium-2:** Joint-controller assessment with LinkedIn Page Insights (C-210/16). Follow-up issue.
- **Medium-3:** Tenant-consent capture for tenant-derived posts. Follow-up issue.
- **Low-1/2:** jikigai.com cookie posture; K-bis personal-data scope verification. Follow-up.

**Follow-up issue list filed at Phase 4.5** (see below).

## Files to Edit

1. `scripts/content-publisher.sh`
   - **Line 539** (`post_linkedin_company` pre-check): change `LINKEDIN_ACCESS_TOKEN` → `LINKEDIN_ORG_ACCESS_TOKEN`; update warning text.
   - **Lines 485-504** (`create_linkedin_fallback_issue`): add explicit **error-class routing matrix** (per spec-flow P1-1):
     - `vendor-blocked` class (missing-token OR HTTP 401/403 + `w_organization_social`) → `append_to_linkedin_tracker`.
     - `transient` class (5xx, 429) → return without filing any issue; next cron run retries.
     - `content-rejected` class (4xx not matching vendor-blocked patterns) → `create_dedup_issue` (per-post fallback retained — these ARE distinct user actions).
   - **New function `append_to_linkedin_tracker(case_name, section, error_reason, internal_fallback=0)`** placed adjacent to `create_linkedin_fallback_issue`. The `internal_fallback` arg prevents mutual recursion: if the tracker write fails AND `internal_fallback=0`, fall back ONCE to `create_linkedin_fallback_issue` with `internal_fallback=1`; if `internal_fallback=1`, branch directly to `create_dedup_issue` and skip the tracker path entirely (per spec-flow P1-2).
   - **Function `post_linkedin_company` (lines 536-573):** when `LINKEDIN_ORG_ACCESS_TOKEN` is unset, call `append_to_linkedin_tracker "$CASE_NAME" "LinkedIn Company Page" "$LINKEDIN_TRACKER_REASON_MISSING_TOKEN"` then `return 0`.

2. `.github/workflows/scheduled-content-publisher.yml`
   - **Line 60-63 env block:** add `LINKEDIN_ORG_ACCESS_TOKEN: ${{ secrets.LINKEDIN_ORG_ACCESS_TOKEN }}` with comment noting the secret is post-approval-mint and the publisher handles its absence via Phase 2 rolling-tracker. No `concurrency:` changes needed — group already present (line 19-21).

3. `.github/workflows/scheduled-linkedin-token-check.yml` (per spec-flow P2-3 + GDPR Medium-1)
   - **Line 30:** add `LINKEDIN_ORG_ACCESS_TOKEN: ${{ secrets.LINKEDIN_ORG_ACCESS_TOKEN }}` to the env block.
   - **Lines 36-46:** convert the single-token introspection loop to iterate over `[LINKEDIN_ACCESS_TOKEN, LINKEDIN_ORG_ACCESS_TOKEN]`; for each set token, call the introspection endpoint and emit per-token Discord alerts at 14/7-day expiry thresholds. Skip if a token is unset (returns 0 — covers the pre-approval period).
   - **Lines 52-66:** update the alert-body template to name which token expired.

4. `apps/web-platform/infra/variables.tf` — append 3 variable blocks (`cf_zone_id_jikigai_com`, `cf_api_token_jikigai_com` sensitive, `linkedin_page_verification_txt` sensitive). Description for the API-token block per terraform-architect P2-2: `"Cloudflare API token narrowed to Zone:DNS:Edit on jikigai.com (cloudflare_record resources; see jikigai-com.tf). Current consumers: jikigai-com.tf (LinkedIn Page Verifications TXT)."`

5. `apps/web-platform/infra/main.tf` (per terraform-architect P2-1)
   - Locate `terraform.required_providers.cloudflare` block; add `configuration_aliases = [cloudflare.zone_settings, cloudflare.rulesets, cloudflare.bot_management, cloudflare.jikigai_com]` (preserving existing aliases if present; this PR's alias is the new tail entry).

6. `knowledge-base/legal/article-30-register.md` (per CLO Critical)
   - Append new **PA15 — LinkedIn Company Page publication (Jikigai)** with full Art. 30(1)(a-g) coverage:
     - Purpose: org-page marketing / community / case-study distribution
     - Categories of data subjects: Page followers, post engagers (commenters/reactors)
     - Categories of personal data: identifiers (display name, profile URL), interaction metadata (timestamps, reaction type), engagement signals from Page Insights API
     - Recipients: LinkedIn Ireland Unlimited Company (independent controller); Microsoft Ireland Operations Ltd (for business-verification document custody — including K-bis with named gérant)
     - Third-country transfers: Microsoft routes to US-region infra under EU Data Boundary commitments; LinkedIn Ireland operates EU-region for Page data with US fallback
     - Retention: aligned with LinkedIn's Page-data retention policies (controller-to-controller)
     - Security measures: token in Doppler `prd` + GitHub Actions secrets (AES-256 at rest); 60-day token rotation via `linkedin-setup.sh generate-token`; expiry monitor in `scheduled-linkedin-token-check.yml`
   - Update §0 if Joint Controllers (Art. 26) is "None" — re-evaluate after first Page Insights API call; for now keep "None" since pre-Insights surfaces are marketing-only.

## Files to Create

7. `apps/web-platform/infra/jikigai-com.tf` — described in `## Infrastructure (IaC)` § Files to Create above.

## Open Code-Review Overlap

**Checked:** ran the canonical two-stage `gh issue list --label code-review --state open` + per-path `jq` grep against the 5 files in `## Files to Edit` (paths: `scripts/content-publisher.sh`, `.github/workflows/scheduled-content-publisher.yml`, `.github/workflows/scheduled-linkedin-token-check.yml`, `apps/web-platform/infra/variables.tf`, `apps/web-platform/infra/main.tf`, `apps/web-platform/infra/jikigai-com.tf`).

**Result:** None. No open `code-review`-labeled issues mention any of the targeted file paths. No fold-in, acknowledge, or defer items.

## Implementation Phases

### Phase 0: Preconditions (precommit-verifiable)

- **0.1** Confirm `cq-silent-fallback-must-mirror-to-sentry` does NOT apply to bash — verified in plan authoring (rule scope is TS/pino).
- **0.2** Confirm Article 30 register's PA15 slot — verified (current max = PA14).
- **0.3** Confirm `scheduled-linkedin-token-check.yml` exists at `.github/workflows/scheduled-linkedin-token-check.yml` — verified.
- **0.4** OQ1 + OQ2 resolved by terraform-architect (mint narrow token; defer zone-import). No Phase 0 probes needed.

### Phase 1: Workflow + publisher contract change (atomic, single commit)

- **1.1** Edit `.github/workflows/scheduled-content-publisher.yml:63` — add `LINKEDIN_ORG_ACCESS_TOKEN: ${{ secrets.LINKEDIN_ORG_ACCESS_TOKEN }}` after `LINKEDIN_ALLOW_POST`, with one-line comment: `# Post-approval-mint (#4046); publisher routes to rolling tracker when unset.`
- **1.2** Edit `scripts/content-publisher.sh:539` — change env var name to `LINKEDIN_ORG_ACCESS_TOKEN`; update warning to: `"Warning: LINKEDIN_ORG_ACCESS_TOKEN not set. LinkedIn Company Page posting blocked on Community Management API approval (#4046). Routing to rolling tracker."` Replace `return 0` with `append_to_linkedin_tracker "$CASE_NAME" "LinkedIn Company Page" "$LINKEDIN_TRACKER_REASON_MISSING_TOKEN"; return 0`. (Forward reference to Phase 2 function — phases land together in this commit.)
- **1.3** Edit `.github/workflows/scheduled-linkedin-token-check.yml` (per spec-flow P2-3): add `LINKEDIN_ORG_ACCESS_TOKEN` to env (line 30); convert introspection logic to iterate over both tokens; per-token Discord alert template (lines 52-66).
- **1.4** Commit: `feat(content-publisher): wire LINKEDIN_ORG_ACCESS_TOKEN through publisher + token monitor`.

### Phase 2: Rolling-tracker dedup + explicit error-class routing matrix

- **2.1** Add script-level constant: `LINKEDIN_TRACKER_REASON_MISSING_TOKEN="LINKEDIN_ORG_ACCESS_TOKEN unset — vendor approval pending (#4046)"`.
- **2.2** Add function `classify_linkedin_error(error_reason)` returning `vendor-blocked` or `content-rejected`:
  ```bash
  classify_linkedin_error() {
    local err="$1"
    if [[ "$err" == *"LINKEDIN_ORG_ACCESS_TOKEN is required"* ]] || \
       [[ "$err" == *"w_organization_social"* ]] || \
       [[ "$err" =~ HTTP\ (401|403) ]]; then
      echo "vendor-blocked"; return
    fi
    echo "content-rejected"
  }
  ```
  This covers (a) missing-token at script level, (b) token expired/revoked at day 60 (HTTP 401), (c) scope-revoked (HTTP 403). Transient (5xx, 429) intentionally falls through to per-post `create_dedup_issue` — silently swallowing 5xx would be worse than current behavior; the operator sees the issue and the cron retries next day. Code-simplicity recommendation accepted.
- **2.3** Add function `append_to_linkedin_tracker(case_name, section, error_reason)` adjacent to `create_linkedin_fallback_issue`:
  ```bash
  append_to_linkedin_tracker() {
    local case_name="$1"
    local section="$2"
    local error_reason="$3"
    local tracker="${LINKEDIN_TRACKER_ISSUE:-4046}"
    local marker="- [ ] Re-publish: ${case_name} (${section})"
    local current_body
    current_body=$(gh issue view "$tracker" --json body --jq .body 2>/dev/null) || {
      echo "Warning: failed to fetch tracker #$tracker body. Will retry next cron." >&2
      return 1
    }
    if printf '%s' "$current_body" | grep -qF -- "$marker"; then
      echo "[info] Tracker #$tracker already lists \"$case_name ($section)\" — skip append."
      return 0
    fi
    local updated_body
    updated_body=$(printf '%s\n%s\n' "$current_body" "$marker")
    if printf '%s' "$updated_body" | gh issue edit "$tracker" --body-file - >/dev/null; then
      echo "[ok] Appended \"$case_name ($section)\" to tracker #$tracker"
    else
      echo "Warning: failed to update tracker #$tracker. Will retry next cron." >&2
      return 1
    fi
  }
  ```
  Uses `gh issue edit --body-file -` (heredoc-safe). No recursion guard — if `gh` is down, log + `return 1`; the cron retries tomorrow. Code-simplicity recommendation accepted (mutual-recursion concern was YAGNI for a rare path on a daily cron).
- **2.4** Modify `create_linkedin_fallback_issue` to route via `classify_linkedin_error`:
  ```bash
  # ... near top of function ...
  local error_class
  error_class=$(classify_linkedin_error "$error_reason")
  if [[ "$error_class" == "vendor-blocked" ]]; then
    append_to_linkedin_tracker "$CASE_NAME" "$section" "$error_reason"
    return $?
  fi
  # ... existing create_dedup_issue call for content-rejected (default) ...
  ```
- **2.5** Smoke test (local): with `LINKEDIN_ORG_ACCESS_TOKEN` unset + `LINKEDIN_TRACKER_ISSUE` set to a test issue, invoke `post_linkedin_company` against a fixture distribution-content file. Verify (a) no API call, (b) tracker grows by exactly one line, (c) second invocation is no-op.
- **2.6** Smoke test (graceful degradation): with `LINKEDIN_TRACKER_ISSUE` set to a non-existent issue, invoke the same. Verify single fallback issue + no infinite recursion.
- **2.7** Commit: `feat(content-publisher): rolling-tracker dedup with explicit error-class routing`.

### Phase 3: Terraform jikigai.com onboarding + Article 30 register

- **3.1** Edit `apps/web-platform/infra/variables.tf` — append 3 variables (`cf_zone_id_jikigai_com`, `cf_api_token_jikigai_com` sensitive with the description above, `linkedin_page_verification_txt` sensitive).
- **3.2** Edit `apps/web-platform/infra/main.tf` — extend `terraform.required_providers.cloudflare.configuration_aliases` to include `cloudflare.jikigai_com` (preserve existing aliases).
- **3.3** Create `apps/web-platform/infra/jikigai-com.tf` per `## Files to Create` §7.
- **3.4** Edit `knowledge-base/legal/article-30-register.md` — append PA15 entry per CLO Critical fold-in. Include the K-bis natural-person disclosure footnote (per CLO HIGH-2): "Microsoft business-verification flow ingests K-bis extract which names the SARL gérant (Jean Deruelle) — controller-to-controller transfer of natural-person data per CNIL délibération SAN-2024-006."
- **3.5** Validate (config-phase only — no plan/apply pre-merge):
  ```bash
  cd apps/web-platform/infra/
  export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
  export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
  terraform init -input=false
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform validate
  ```
  Expect: no errors. `terraform plan` is intentionally deferred until Phase 5.2 when `TF_VAR_linkedin_page_verification_txt` is available.
- **3.6** Commit: `feat(infra): onboard jikigai.com Cloudflare zone for LinkedIn verification + Art. 30 PA15`.

### Phase 4: Issue body correction + backlog closure + follow-up issues

- **4.1** Verify #4046 body correction (done in brainstorm phase): `gh issue view 4046 --json body --jq .body | grep -F "Marketing Developer Platform"` — confirm corrected text present.
- **4.2** Close 9 superseded backlog issues:
  ```bash
  for n in 3765 3467 3284 3073 2863 2738 2489 1886 1082; do
    gh issue close "$n" --reason "not planned" \
      --comment "Superseded by #4046 (LinkedIn Community Management API re-application). Per the new rolling-tracker dedup in scripts/content-publisher.sh, future blocked LinkedIn Company Page posts will append to #4046 rather than create per-post fallback issues. Once Community Management API access is granted and \`LINKEDIN_ORG_ACCESS_TOKEN\` is rotated, the affected content will be re-triggered via \`gh workflow run scheduled-content-publisher.yml\`."
  done
  ```
- **4.3** Verify all 9 are CLOSED with `stateReason: NOT_PLANNED`.
- **4.4** Commit: `chore(content-publisher): close 9 LinkedIn-API fallback issues superseded by #4046`.
- **4.5** File the 2 follow-up issues that have concrete triggers (per code-simplicity-reviewer; dropped 5 speculative follow-ups that should be filed when their trigger fires, not pre-filed):
  - **(F1) #4051 — Legal-track PR (BLOCKS Phase 5.4):** LIA for org-page posts, Privacy Policy Art. 13(1)(e) recipient disclosure + Art. 17 carve-out, DPD update.
  - **(F6) #4052 — jikigai.com existing-DNS terraform import:** import MX/SPF/DKIM/etc. for ops@jikigai.com email into TF state. Trigger = next operator-driven jikigai.com DNS change.

  **Dropped follow-ups (deferred-scope-out, not pre-filed):** per-section status frontmatter (F2 — file when a 2nd re-publish event arises), Page Insights joint-controller assessment (F3 — file when consuming the API), tenant consent capture (F4 — file when first tenant-derived post is planned), jikigai.com cookie posture (F5 — file when first jikigai.com user-facing page ships), Cloudflare provider 5.x migration (F7 — handled by whatever forces the 5.x bump). Captured here in plan prose so future planners can re-discover the triggers.
- **4.6** Commit follow-up references as part of PR body (no file changes).

### Phase 5: Post-merge operator runbook (async, days)

Starts after PR #4047 merges to `main`. **Phase 5.4 is BLOCKED until follow-up F1 (legal-track PR) lands.** Tracked as PR-body checklist on #4047.

- **5.1 Create Jikigai LinkedIn Company Page (Playwright-driven).** Navigate to `https://www.linkedin.com/setup/business/new/`. Operator OAuth-consents once (manual gate). Playwright drives: name = "Jikigai"; primary website = `https://jikigai.com`; industry/size per Jikigai's K-bis registration; logo upload (operator provides local path); tagline references Soleur as the product.
- **5.2 Apply DNS TXT via Terraform.**
  - From LinkedIn Page Verifications, copy TXT host + content.
  - `doppler secrets set TF_VAR_linkedin_page_verification_txt=...` + `TF_VAR_cf_zone_id_jikigai_com=...` + `TF_VAR_cf_api_token_jikigai_com=...`.
  - From `apps/web-platform/infra/`:
    - `export AWS_ACCESS_KEY_ID=...; export AWS_SECRET_ACCESS_KEY=...`
    - `terraform init -input=false`
    - `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -target=cloudflare_record.linkedin_verification`
    - Confirm output: `1 to add, 0 to change, 0 to destroy`.
    - `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply -target=cloudflare_record.linkedin_verification`
  - **Post-targeted-apply (terraform-architect P1-4):** in the same session, `doppler run … -- terraform plan` (untargeted) and confirm `No changes`. If the untargeted plan shows soleur.ai drift, investigate before exiting the session.
- **5.3 Verify TXT via LinkedIn UI (Playwright).** Return to LinkedIn Page Verifications, click "Verify". Playwright captures response. On failure: `dig +short +time=5 +tries=2 TXT <fqdn>` to confirm propagation.
- **5.4 Microsoft business verification (BLOCKED until F1 legal-track PR lands).** Operator uploads Jikigai K-bis + tax registration + registered-address proof via LinkedIn Page admin UI. **Automation: not feasible — document upload requires operator-attested legal documents.** **Pre-requisite check:** verify F1 PR is merged BEFORE this step (per CLO Critical Art. 30 timing).
- **5.5 Associate verified Page with developer app 229658411 (Playwright).** Navigate to `https://www.linkedin.com/developers/apps/229658411/settings`, select Jikigai Page under "Associated Company".
- **5.6 Re-submit Community Management API access (Playwright).** Products tab → "Request access" on Community Management API → confirm. Capture confirmation screenshot to PR comments.
- **5.7 Await LinkedIn approval (1-5 business days, non-blocking).** LinkedIn does not expose approval status API. Operator monitors email + Developer Portal. The publisher's rolling tracker idempotently no-ops in the meantime.

### Phase 6: Post-approval token rotation + 9-article re-trigger

Starts on LinkedIn approval email.

- **6.1** Regenerate token via `linkedin-setup.sh generate-token` (scope: `openid profile w_member_social w_organization_social`).
- **6.2** Validate: `LINKEDIN_ORG_ACCESS_TOKEN=<new-token> bash plugins/soleur/skills/community/scripts/linkedin-setup.sh validate-credentials` — confirm `w_organization_social` in granted scopes.
- **6.3** Persist:
  - `doppler secrets set LINKEDIN_ORG_ACCESS_TOKEN=<new-token> -p soleur -c prd`
  - `printf '%s' <new-token> | gh secret set LINKEDIN_ORG_ACCESS_TOKEN`
- **6.4** Re-trigger publisher for the 9 superseded articles via **burst-publish**: set `publish_date: <today>` in all 9 files in one commit, push, and trigger the workflow (`gh workflow run scheduled-content-publisher.yml --ref main`). LinkedIn Page posting limit is ~150/day/token; 9 in one burst is well within. Code-simplicity recommendation accepted (1-per-day was cargo-culted against undocumented limits).
- **6.5 (gated on F1 PR landed)** After ~30 minutes, verify each post landed on the Page (Playwright nav to `https://www.linkedin.com/company/jikigai/posts/`); check off the corresponding `- [ ] Re-publish: ...` line in #4046 body. If any failed, space those out 1-per-hour with diagnostic logging.
- **6.6** Close #4046 with `--reason completed` once all 9 are verified live.

## Acceptance Criteria

### Pre-merge (PR #4047)

- [ ] **AC1** `scripts/content-publisher.sh:539` checks `LINKEDIN_ORG_ACCESS_TOKEN`. Verify: `grep -n 'LINKEDIN_ORG_ACCESS_TOKEN.*Skipping' scripts/content-publisher.sh` returns the pre-check line.
- [ ] **AC2** `.github/workflows/scheduled-content-publisher.yml` env block exports `LINKEDIN_ORG_ACCESS_TOKEN`. Verify: `grep 'LINKEDIN_ORG_ACCESS_TOKEN: \${{ secrets' .github/workflows/scheduled-content-publisher.yml` returns the export line.
- [ ] **AC3** `.github/workflows/scheduled-linkedin-token-check.yml` exports AND iterates over both `LINKEDIN_ACCESS_TOKEN` and `LINKEDIN_ORG_ACCESS_TOKEN`. Verify: `grep -c 'LINKEDIN_ORG_ACCESS_TOKEN' .github/workflows/scheduled-linkedin-token-check.yml` returns ≥ 2 (env export + iteration body).
- [ ] **AC4** `scripts/content-publisher.sh` defines `classify_linkedin_error`, `append_to_linkedin_tracker`, and routes via the error-class matrix. Verify: `grep -c 'classify_linkedin_error' scripts/content-publisher.sh` returns ≥ 2 (def + call); `grep -c 'append_to_linkedin_tracker' scripts/content-publisher.sh` returns ≥ 3 (def + ≥2 call sites).
- [ ] **AC5** `append_to_linkedin_tracker` is idempotent. Local smoke: invoke twice on same case_name with `LINKEDIN_TRACKER_ISSUE=<test-N>`; tracker body length grows by exactly one line.
- [ ] **AC6** `apps/web-platform/infra/variables.tf` declares all 3 new variables. Verify: `grep -cE '^variable "(cf_zone_id_jikigai_com|cf_api_token_jikigai_com|linkedin_page_verification_txt)"' apps/web-platform/infra/variables.tf` returns 3.
- [ ] **AC7** `apps/web-platform/infra/main.tf` `configuration_aliases` extended with `cloudflare.jikigai_com`. Verify: `grep -A 5 'required_providers' apps/web-platform/infra/main.tf | grep -F 'cloudflare.jikigai_com'` returns the alias line.
- [ ] **AC8** `apps/web-platform/infra/jikigai-com.tf` exists, declares the aliased provider AND `cloudflare_record.linkedin_verification`, AND does NOT include `lifecycle.ignore_changes`. Verify: `test -f apps/web-platform/infra/jikigai-com.tf && grep -q 'alias = "jikigai_com"' apps/web-platform/infra/jikigai-com.tf && grep -q 'cloudflare_record" "linkedin_verification"' apps/web-platform/infra/jikigai-com.tf && ! grep -q 'lifecycle' apps/web-platform/infra/jikigai-com.tf`.
- [ ] **AC9** `terraform validate` passes from `apps/web-platform/infra/` per Phase 3.5.
- [ ] **AC10** `knowledge-base/legal/article-30-register.md` includes a `## Processing Activity 15 — LinkedIn Company Page publication (Jikigai)` section with Microsoft Ireland + LinkedIn Ireland recipient rows AND the K-bis natural-person disclosure footnote. Verify: `grep -q 'Processing Activity 15' knowledge-base/legal/article-30-register.md && grep -q 'Microsoft Ireland' knowledge-base/legal/article-30-register.md && grep -q 'K-bis' knowledge-base/legal/article-30-register.md`.
- [ ] **AC11** All 9 backlog issues (#3765, #3467, #3284, #3073, #2863, #2738, #2489, #1886, #1082) are CLOSED with `stateReason: NOT_PLANNED`.
- [ ] **AC12** #4046 body no longer contains the Marketing API conflation. Verify: `gh issue view 4046 --json body --jq .body | grep -F "Marketing Developer Platform (separate approval"` returns the corrected text.
- [ ] **AC13** PR #4047 body uses `Ref #4046` (not `Closes #4046`). Verify: `gh pr view 4047 --json body --jq .body | grep -E '^Refs? #4046'` returns a line; `gh pr view 4047 --json body --jq .body | grep -E '^Closes #4046'` returns nothing.
- [ ] **AC14** PR body lists follow-up issues F1 (legal-track) and F6 (jikigai.com DNS import). Verify: `gh pr view 4047 --json body --jq .body | grep -cE 'F[16]: #[0-9]+'` returns 2.

### Post-merge (operator)

- [ ] **AC15** Follow-up F1 legal-track PR merged BEFORE Phase 5.4 starts. Verify: `gh pr view <F1-PR-N> --json mergedAt` returns a valid timestamp.
- [ ] **AC16** Jikigai LinkedIn Company Page exists with `jikigai.com` as primary website.
- [ ] **AC17** Domain verification status: **Verified** for jikigai.com.
- [ ] **AC18** Microsoft business verification status: **Verified**.
- [ ] **AC19** App 229658411 "Associated Company" shows the verified Jikigai Page.
- [ ] **AC20** Community Management API access re-submitted (confirmation screenshot in PR comments).
- [ ] **AC21** (Async, post-approval) `linkedin-setup.sh validate-credentials` against regenerated token returns `w_organization_social` in granted scopes.
- [ ] **AC22** (Async, post-approval) `doppler secrets get LINKEDIN_ORG_ACCESS_TOKEN -p soleur -c prd --plain | wc -c` returns > 0; `gh secret list | grep LINKEDIN_ORG_ACCESS_TOKEN` returns the GH secret.
- [ ] **AC23** (Async, post-approval) All 9 articles re-published to the Page; corresponding `- [ ] Re-publish: ...` lines in #4046 body checked off.
- [ ] **AC24** Post-Phase-5.2 untargeted `terraform plan` returns `No changes` on soleur.ai resources.

## Test Scenarios

- **TS1 (Phase 2 happy path):** `LINKEDIN_ORG_ACCESS_TOKEN` unset + `LINKEDIN_TRACKER_ISSUE` = test-N. Run publisher. Expected: zero API calls; tracker body +1 line; second run no-op.
- **TS2 (Phase 2 tracker fetch failure):** `LINKEDIN_TRACKER_ISSUE` = non-existent-N. Run publisher. Expected: stderr warning, exit 1 from `append_to_linkedin_tracker`; publisher proceeds (next cron retries).
- **TS3 (Phase 2 error-class routing):** Mock `LINKEDIN_SCRIPT` to return HTTP 401 (token-expired), then HTTP 422 (content-rejected). Expected: 401 routes to tracker (vendor-blocked); 422 creates a per-post fallback (default fall-through).
- **TS4 (Phase 3 terraform validate):** Phase 3.5 command exits 0.
- **TS5 (Phase 4 backlog closure idempotency):** Re-running close-9 loop on already-closed issues produces 9 "already closed" notices, exit 0.

No new test framework introduced; convention is shell + manual smoke.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Microsoft business verification rejects Jikigai again | Capture rejection verbatim in #4046 comments. Re-park trigger at ≥2 rejections + 90-day mark (brainstorm Re-evaluation Criteria). |
| Pre-existing jikigai.com DNS records cause apply drift on `-target=cloudflare_record.linkedin_verification` | Per OQ2 resolution (terraform-architect P1-2): aliased provider isolates blast radius; no import of existing records. Post-apply untargeted `terraform plan` (Phase 5.2 + AC26) confirms zero soleur.ai drift. |
| LinkedIn UI breaks Playwright selectors at Phase 5.1/5.5/5.6 | Operator falls back to manual browser-driven equivalents; PR comments capture each step. |
| Operator forgets Doppler + GH-secret rotation post-approval | Rolling tracker is the safety net — even if rotation forgotten, the workflow doesn't accumulate noise. `scheduled-linkedin-token-check.yml` (after Phase 1.3 fix) alerts at 14/7 days remaining once token is set. |
| Re-trigger duplicates posts | Per OQ3 resolution: 1-per-day re-publish over 9 days, with Playwright verification at AC25 before next iteration. None of the 9 succeeded originally (each created a fallback). |
| TXT value leaks into `terraform.tfstate` | R2 backend AES-256 at rest; value is single-purpose and becomes public TXT post-verification (low residual sensitivity). |
| Token-rotation cadence drifts after first rotation | `scheduled-linkedin-token-check.yml` (Phase 1.3 fix) covers both tokens with 14/7-day Discord alerts. |
| Article 30 register entry lands but F1 legal-track PR (LIA/Privacy Policy/DPD) stalls before Phase 5.4 | AC16 gates Phase 5.4 on F1 merge. Operator cannot start business verification without it. |
| Concurrent publisher invocations race on rolling-tracker update | Workflow already has `concurrency.group: scheduled-content-publisher cancel-in-progress: false`. Operator-initiated `workflow_dispatch` during Phase 6.4 inherits the same group. |

## Open Questions

(All previously-listed OQs resolved by terraform-architect, spec-flow-analyzer, gdpr-gate fold-ins.)

No remaining open questions for this PR. Phase 5/6 decisions deferred to execution time are explicitly listed as such in the runbook steps.

## Sharp Edges

- **Cloudflare `cloudflare_record` apex naming.** TXT uses LinkedIn's specified prefix (e.g., `_linkedin-challenge.<subdomain>`), NOT `@`. Apex `@` causes Terraform drift.
- **Doppler nested-invocation triplet.** Required for `terraform plan`/`apply` (per `variables.tf:1-13` comment). Phase 3.5 + Phase 5.2 reference the exact form.
- **`gh issue close --reason "not planned"` enum.** Per `hr-github-api-endpoints-with-enum`, verify the exact accepted value before the close-9 sweep (`not planned` with space per GitHub CLI docs).
- **Provider 5.x deprecation.** `cloudflare_record` renames to `cloudflare_dns_record` in v5. Plan locks 4.x; the next planner who bumps the provider migrates this file alongside the rest.
- **F1 gate enforcement.** Phase 5.4 BLOCKED until F1 merges. Operator + AC15 are the human checkpoint; no automated gate.

## Phase Execution Plan (now → PR merge)

1. ✅ Phase 0 reads + verification (done)
2. ✅ Spawn gdpr-gate + terraform-architect + spec-flow-analyzer; fold findings (done)
3. ⏭ Spawn plan-review (code-simplicity-reviewer) for final YAGNI lens
4. ⏭ Generate `tasks.md` from final plan
5. ⏭ Commit plan + tasks; push
6. ⏭ Hand off to `/soleur:work`

## References

- Spec: `knowledge-base/project/specs/feat-linkedin-api-reapply-4046/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-19-linkedin-community-api-reapply-jikigai-brainstorm.md`
- Prior learnings: `2026-04-09-linkedin-org-access-token-for-company-page-posts.md`, `2026-04-26-linkedin-org-token-fallback-silent-400.md`, `2026-03-13-platform-integration-scope-calibration.md`, `2026-03-13-linkedin-api-scripts-brainstorm.md`
- LinkedIn community script: `plugins/soleur/skills/community/scripts/linkedin-community.sh:279-286`
- LinkedIn setup script: `plugins/soleur/skills/community/scripts/linkedin-setup.sh`
- Publisher: `scripts/content-publisher.sh:485-573, 641-663`
- Content workflow: `.github/workflows/scheduled-content-publisher.yml:60-77`
- Token-check workflow: `.github/workflows/scheduled-linkedin-token-check.yml`
- Cloudflare TF root: `apps/web-platform/infra/` (variables.tf, dns.tf, main.tf)
- Article 30 register: `knowledge-base/legal/article-30-register.md`
- Parent vendor track: #799
- Marketing API deferred tracker: #4049
