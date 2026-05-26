---
title: "Legal-track PR — LIA + Privacy Policy + DPD updates for LinkedIn Company Page publication"
type: plan
status: draft-requires-counsel-review
date: 2026-05-19
issue: 4051
branch: feat-legal-linkedin-page-4051
worktree: .worktrees/legal-linkedin-org-page-4051
blocks: 4046
related: [4046, 4047, 4052]
parent_brainstorm: knowledge-base/project/brainstorms/2026-05-19-linkedin-community-api-reapply-jikigai-brainstorm.md
parent_plan: knowledge-base/project/plans/2026-05-19-feat-linkedin-api-reapply-jikigai-plan.md
lane: cross-domain
domains: [legal, marketing, infra]
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
requires_clo_signoff: true
---

> **DRAFT — This plan describes the creation and amendment of legal documents that constitute the controller's accountability evidence under GDPR Art. 5(2). Counsel review is REQUIRED before merge per Soleur policy (acceptance criterion AC-Legal-1 below).**

# Legal-track PR — LIA + Privacy Policy + DPD updates for LinkedIn Company Page publication

## Overview

Issue **#4051** files the legal-track artifacts that gate **Phase 5.4** of the operator runbook attached to merged PR **#4047** (LinkedIn Community Management API re-application as Jikigai SARL). Phase 5.4 is the K-bis appeal upload at `https://www.linkedin.com/help/linkedin/ask/dsapi` — the **first cross-controller personal-data transfer** triggered by Processing Activity 15 of the Article 30 register. Article 30(1) requires the controller's accountability record to be in place **before** processing begins; the K-bis upload constitutes the start of regular processing, so the LIA / Privacy Policy / DPD updates must land first.

Three legal artifacts are in scope per the issue body:

1. **Legitimate Interest Assessment** — a new file documenting the Art. 6(1)(f) three-part test (purpose / necessity / balancing) for processing Page-follower personal data surfaced by LinkedIn Page Insights. Template: `knowledge-base/legal/legitimate-interest-assessments/2026-05-14-tenant-deploy-substrate-lia.md`.
2. **Privacy Policy update** — `docs/legal/privacy-policy.md` extended with (i) Art. 13(1)(e) recipient disclosure naming **LinkedIn Ireland Unlimited Company** and **Microsoft Ireland Operations Ltd**, and (ii) an Art. 17 carve-out clause for LinkedIn-published content (Soleur deletes its source copy and issues a deletion request, but cannot guarantee removal from LinkedIn's cached / replicated systems).
3. **Data Protection Disclosure (DPD) update** — `docs/legal/data-protection-disclosure.md` mirroring the Privacy Policy changes in the structured DPD format (new `2.3(p)` activity row + processor-table addition in `4.2` + processor flow-down in `4.2 Web Platform Processors` table).

One additional in-scope item, folded in per planning-time decision (alternative was to defer to a follow-up issue):

4. **`jikigai.com/legal/privacy-policy` redirect** — a Cloudflare ruleset rule on the existing `jikigai.com` zone (provisioned in #4046's `apps/web-platform/infra/jikigai-com.tf`) so the operator can update the LinkedIn Developer app (229658411) privacy-policy URL from `https://soleur.ai/pages/legal/privacy-policy.html` → `https://jikigai.com/legal/privacy-policy` (canonical-domain alignment for the appeal reviewer). The redirect is a 301 to the existing soleur.ai page; **no duplicate hosting**, so the single source of truth remains `docs/legal/privacy-policy.md` rendered onto `soleur.ai`.

Counsel review is the load-bearing acceptance gate: AC-Legal-1 blocks merge until counsel has signed the three primary artifacts.

## Brand-survival posture

**Threshold:** `single-user incident` — carried forward from parent plan `2026-05-19-feat-linkedin-api-reapply-jikigai-plan.md` and Article 30 PA15. The LinkedIn Page is Jikigai's primary B2B marketing surface and the named-controller relationship; any plan-level accuracy defect in the LIA / Privacy Policy / DPD propagates to a **regulatory** incident (CNIL / DPC complaint, Art. 83 administrative fine exposure) and a **reputational** incident (LinkedIn appeal denial, Page suspension, founder identity exposed without compliant Art. 13(1)(e) disclosure to data subjects).

**CPO + CLO sign-off:** required. Sign-off carried forward from the parent brainstorm (`2026-05-19-linkedin-community-api-reapply-jikigai-brainstorm.md`) which assessed this artifact pair at the high-water mark.

## User-Brand Impact

Concrete user-facing failure modes the plan must mitigate, per `user-impact-reviewer` template (artifact / vector / mitigation):

1. **`page_follower.display_name` + `page_follower.profile_url` surfaced by Page Insights → undisclosed-processor failure mode**
   - **Vector:** A LinkedIn Page follower exercises Art. 15 (access) against Jikigai and we cannot demonstrate Art. 13(1)(e) recipient disclosure for LinkedIn Ireland (joint-controller posture under C-210/16 *Wirtschaftsakademie*).
   - **Mitigation:** Privacy Policy §5 adds a `LinkedIn Ireland Unlimited Company` row; DPD §2.3(p) and §4.2 mirror; LIA §Necessity documents that aggregate-only consumption is necessary for the marketing purpose.

2. **`linkedin_post.body` (user-visible content) → erasure-impossibility failure mode**
   - **Vector:** A user requests Art. 17 erasure of a post that references them; the post is replicated on LinkedIn's CDN / cached on third-party search indices; Soleur deletes the source but cannot evidence cascade.
   - **Mitigation:** Privacy Policy §7 and §8.1 add an Art. 17 carve-out paragraph; DPD §10.3 carries the same wording in structured form; LIA §Balancing names the carve-out as a residual-risk safeguard.

3. **`k_bis_extract.gerant_name` → identity-disclosure-without-Art-13 failure mode**
   - **Vector:** The K-bis names the gérant (Jean Deruelle) as a natural person. Microsoft Ireland Operations Ltd receives this during the appeal. The data subject (the gérant himself) requires Art. 13(1)(e) disclosure of the recipient before the transfer begins.
   - **Mitigation:** Privacy Policy §5 names Microsoft Ireland; DPD §2.3(p) names Microsoft Ireland; LIA §Purpose explicitly addresses the controller-to-controller transfer mode (Art. 6(1)(c) legal-obligation basis, not the Art. 6(1)(f) basis the LIA primarily addresses).

4. **Privacy-policy URL mismatch → appeal-denial failure mode**
   - **Vector:** LinkedIn appeal reviewer sees a privacy policy URL at `soleur.ai` and a controller named `Jikigai SARL` in the K-bis; the entity↔domain mismatch is a documented rejection class.
   - **Mitigation:** Cloudflare ruleset rule at `jikigai.com/legal/privacy-policy → soleur.ai/pages/legal/privacy-policy.html` (301); operator updates the LinkedIn app URL post-merge.

5. **LIA absence at the time of first Page Insights call → Art. 30(1) timing failure mode**
   - **Vector:** Art. 5(2) accountability + Art. 30(1) RoPA both require the controller to demonstrate the lawful basis is documented *before* processing. The first Page Insights call (separate follow-up issue #4053 for joint-controller assessment, see Re-evaluation Triggers) creates exposure if the LIA isn't merged first.
   - **Mitigation:** This plan blocks #4046 Phase 5.4. Phase 5.4 is the operator-runbook step that **enables** Phase 6 (publishing + Page Insights consumption); the merge sequence is enforced by the parent plan's runbook order, not just by this plan.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Codebase reality | Plan response |
|---|---|---|
| Issue body names files: LIA at `knowledge-base/legal/legitimate-interest-assessments/2026-05-19-linkedin-org-page-lia.md`, Privacy Policy at `docs/legal/privacy-policy.md`, DPD at `docs/legal/data-protection-disclosure.md` | All three paths exist and are writable; template LIA exists at `2026-05-14-tenant-deploy-substrate-lia.md` (verified Read). | Use exact paths from issue. |
| Issue body cites Privacy Policy "Section" without specifying location | Privacy Policy §5 enumerates third-party services / sub-processors with `5.1`-`5.11` rows; §4 enumerates data categories; §7 covers retention; §8.1 covers Art. 17. | Privacy Policy edits land in §5 (new `5.12 LinkedIn Ireland Unlimited Company` row + `5.13 Microsoft Ireland Operations Ltd` row for K-bis flow), §4 (new §4.10 "LinkedIn Page publication"), and §8.1 (new bullet under Art. 17 for LinkedIn-published content carve-out). |
| Issue body cites DPD mirror | DPD §2.3 enumerates lettered processing activities `(a)`-`(o)`; §4.2 enumerates processors in tables; §10.3 covers Web Platform account deletion. | DPD edits add §2.3(p) "LinkedIn Company Page publication", extend the Web Platform Processors table with two new rows, and add a §10.3-style note for the Art. 17 LinkedIn-published-content carve-out. |
| Issue body cites Article 30 PA15 cross-reference | PA15 exists in `knowledge-base/legal/article-30-register.md` and explicitly cites "follow-up legal-track PR (#4051)" in its closing paragraph. PA15 names the LIA path the issue body specifies. | This plan amends PA15's lawful-basis row (ii) to cross-reference the new LIA file path (currently "documented in the follow-up legal-track PR #4051 per CLO High-1") and changes status from `draft (counsel review pending — LIA path pre-shipped)` → `draft (counsel review pending — LIA shipped at <path>; counsel-review pending across PA15 + LIA + Privacy Policy + DPD as a single bundle)`. |
| Folded jikigai.com privacy-policy redirect — planning-time decision (not in issue body) | `apps/web-platform/infra/jikigai-com.tf` provisions the aliased `cloudflare.jikigai_com` provider + the LinkedIn verification TXT record. Variables `cf_zone_id_jikigai_com` + `cf_api_token_jikigai_com` already exist in `variables.tf`. | Extend `jikigai-com.tf` with a single `cloudflare_ruleset` resource (Single Redirects phase) of type `http_request_dynamic_redirect`, narrowly scoped to `http.host eq "jikigai.com" and http.request.uri.path eq "/legal/privacy-policy"`. Status 301, static target `https://soleur.ai/pages/legal/privacy-policy.html`. No drift suppression (per terraform-architect P1-3 already absorbed into parent plan). |

## Open Code-Review Overlap

```bash
# Files this plan will touch:
#   knowledge-base/legal/legitimate-interest-assessments/2026-05-19-linkedin-org-page-lia.md   (CREATE)
#   docs/legal/privacy-policy.md                                                                (EDIT)
#   docs/legal/data-protection-disclosure.md                                                    (EDIT)
#   knowledge-base/legal/article-30-register.md                                                 (EDIT)
#   knowledge-base/legal/compliance-posture.md                                                  (EDIT)
#   apps/web-platform/infra/jikigai-com.tf                                                      (EDIT)
#   apps/web-platform/infra/variables.tf                                                        (no edit — already declared)
#
# Query gh issue list --label code-review --state open against these paths:
```

**Disposition:** Will be filled in at `/work` time per skill phase 1.7.5 — a fresh query is required at the moment the plan executes because the issue list is hot. The plan's pre-flight Check 9 in `/work` Phase 0.5 verifies overlap; this section records the procedure rather than the snapshot.

`None expected` is the planning-time expectation: the issue list as of 2026-05-19 contains no open code-review issues against `docs/legal/**` or `knowledge-base/legal/**` (these are docs-only, not source code; code-review label is bound to source-code reviewers).

## Hypotheses

Not applicable — this is a docs + thin-infra PR, not a debugging or diagnostic plan.

## Domain Review

Per Phase 2.5 Domain Review Gate. Domain leaders carried forward from the parent brainstorm's `## Domain Assessments` section, with delta-only re-assessment for the #4051 narrowing.

### CLO (Legal/Compliance) — REQUIRED — `legal-compliance` lead

**Status:** in-progress (this plan IS the CLO follow-through on the High-1 finding from the parent brainstorm).

**Findings:**
- Confirms the three-artifact scope is necessary and sufficient under Art. 30(1) + Art. 13(1)(e) + Art. 17.
- LIA template is the right starting point — `2026-05-14-tenant-deploy-substrate-lia.md` covers the three-prong structure cleanly; the LinkedIn case differs primarily in (a) data subjects are LinkedIn members not operators, (b) joint-controller posture under C-210/16 is in play, (c) Art. 17 cascade is operationally impossible across LinkedIn's CDN and must be disclosed not engineered.
- **Outstanding counsel-review item carried forward:** the LIA's `## Outstanding counsel-review items` section MUST include (1) joint-controller assessment under Art. 26 — currently deferred to a separate follow-up triggered at first Page Insights call; (2) whether the K-bis K-1 disclosure to Microsoft Ireland is properly captured as Art. 6(1)(c) legal-obligation basis (the LIA primarily documents Art. 6(1)(f); the K-bis transfer is a separate lawful basis the LIA references for completeness but does not re-derive); (3) the Art. 17 carve-out wording — counsel to confirm "best-effort deletion + non-guarantee" is sufficient under EDPB Guidelines 5/2019 on the criteria for the right to be forgotten.

### CPO (Product) — REQUIRED — `cpo` lead (because `brand_survival_threshold: single-user incident`)

**Status:** sign-off carried forward from parent brainstorm. Re-confirmation required at PR-ready time (a delta is possible if the operator wants additional disclosures around the appeal flow itself).

**Findings:**
- The redirect fold-in (jikigai.com/legal/privacy-policy → soleur.ai) is the right call for appeal-reviewer alignment. The alternative (host a duplicate page at jikigai.com) creates a maintenance fork.
- Brand-survival framing: the LinkedIn Page is the named-controller surface; getting the appeal accepted on first re-submission is the load-bearing user-experience metric. Plan delivers all three appeal-prerequisite artifacts.

### CMO (Marketing) — relevant, advisory-only

**Status:** no blocking findings. The LinkedIn Page is marketing-owned post-publication; CMO assessment carried forward from parent brainstorm validates the Page-Insights legitimate-interest basis (marketing analytics on Soleur's owned Page is a recognized Art. 6(1)(f) use case).

### CTO (Engineering) — relevant, advisory-only

**Status:** no blocking findings. The thin-infra add (one Cloudflare ruleset rule) reuses the aliased provider + narrow API token already provisioned in #4046; blast radius is the same as the verification-TXT shipped under PR #4047.

**Agents invoked:** clo, cpo, cmo, cto (all carried forward from parent brainstorm — no fresh spawn needed at planning time).
**Skipped specialists:** none (all 8-domain leaders relevant; CFO / CRO / CCO / COO have no findings on a legal-track docs PR per parent brainstorm).
**Decision:** reviewed (full).

## Plan-Time Gates Absorbed

The following gates were run inline at planning time and their findings are folded into the AC list below — do not re-spawn:

1. **gdpr-gate** — this plan IS the gdpr-gate Critical fold-in from the parent plan (#4046). The Critical finding ("LIA not present at first Page Insights call; Art. 13(1)(e) recipient disclosure missing; Art. 17 cascade undocumented") is closed by the three primary artifacts. **Status: applied.**
2. **terraform-architect** — single `cloudflare_ruleset` resource on the existing aliased provider; no new variables; no `lifecycle.ignore_changes`; targeted-apply caveat documented in the file header (mirror of `jikigai-com.tf` pattern). **Findings folded into AC-Infra-1/2/3 below.**
3. **spec-flow-analyzer** — happy path: counsel reviews artifacts → CPO/CLO sign off → PR merges → operator runs Phase 5.4 of parent runbook → appeal accepted → Phase 6 enabled. Unhappy paths: counsel returns substantive edits (loop until accepted); LinkedIn rejects despite alignment (separate ops issue, not in this plan's scope). **No new AC needed beyond AC-Legal-1.**
4. **code-simplicity-reviewer** — three simplifications applied: (i) no duplicate-hosted privacy policy at jikigai.com (redirect-only); (ii) DPD adds **one** new lettered activity `(p)` rather than fragmenting across multiple subsections; (iii) compliance-posture row is one Active Item, closed by single merge event. **Status: applied.**

## Files to Edit

| Path | Change | Why |
|---|---|---|
| `docs/legal/privacy-policy.md` | Add §4.10 "LinkedIn Company Page publication" data-class block; add §5.12 "LinkedIn Ireland Unlimited Company" sub-processor row; add §5.13 "Microsoft Ireland Operations Ltd" sub-processor row; extend §6 "Legal Basis" to enumerate the LinkedIn-Page-publication dual-basis (Art. 6(1)(c) K-bis transfer + Art. 6(1)(f) Page operation); extend §7 retention with LinkedIn-Page row; extend §8.1 right-to-erasure with a new bullet "LinkedIn-published content carve-out" (Art. 17 wording); extend §10 international-transfers with LinkedIn Ireland EU + Microsoft Ireland EUDB rows; bump "Last Updated" header. | Issue scope item 2. |
| `docs/legal/data-protection-disclosure.md` | Add §2.3(p) "LinkedIn Company Page publication" activity row (mirror of Privacy Policy §4.10 + §6); extend §4.2 Web Platform Processors table with `LinkedIn Ireland Unlimited Company` row (controller-to-controller, EU, DPF + SCCs M2) and `Microsoft Ireland Operations Ltd` row (controller-to-controller, EUDB, intra-EU; KYC-equivalent custody); extend §6.4 with LinkedIn EU + Microsoft Ireland EUDB; extend §10.3 with Art. 17 LinkedIn-cache carve-out; bump "Last Updated" header. | Issue scope item 3. |
| `knowledge-base/legal/article-30-register.md` | Amend PA15 row "Lawful basis" entry (ii) so the in-flight `"LIA documented in the follow-up legal-track PR #4051 per CLO High-1"` substring is replaced with the concrete path: `LIA documented at \`knowledge-base/legal/legitimate-interest-assessments/2026-05-19-linkedin-org-page-lia.md\` (this PR — #4051)`. Amend the PA15 closing paragraph similarly. **No structural change** — just promotes the in-flight reference to the resolved one. | AC-Legal-2: cross-reference must be live, not forward-looking. |
| `knowledge-base/legal/compliance-posture.md` | Add one Active Item row referencing #4051 / `compliance/critical` label / status `IN-PROGRESS` while counsel reviews. Add a new row to the "Legal Documents" table for the LIA file. Bump `Privacy Policy` and `Data Protection Disclosure` `Last Updated` columns to today's date. Bump top-of-file `last_updated` frontmatter to today's date. Add a HTML comment row at top of file with one-line summary linking to #4051. | AC-Compliance-1: posture must reflect in-progress state during counsel review, then move to Completed on merge. |
| `apps/web-platform/infra/jikigai-com.tf` | Append one `cloudflare_ruleset` resource (single redirect rule on the existing aliased provider). No `variable` additions — uses existing `var.cf_zone_id_jikigai_com`. File header comment extends to note the redirect was added in #4051. | Scope-decision fold-in (recommended option chosen at AskUserQuestion time). |

## Files to Create

| Path | Purpose |
|---|---|
| `knowledge-base/legal/legitimate-interest-assessments/2026-05-19-linkedin-org-page-lia.md` | The Legitimate Interest Assessment file. Structure: frontmatter (controller, processing_activity, lawful_basis, data_subjects, related: [article-30-register PA15, ADR-N/A — no ADR for this activity since it's marketing-track], status: draft-requires-counsel-review). Body H2s: `## Purpose`, `## Necessity`, `## Balancing` (with `(i)`-`(vi)` sub-sections matching the template's structure). Plus `## Outstanding counsel-review items` and `## Re-evaluation triggers` per template. Counsel-review items MUST include the three carried-forward CLO items. |
| `knowledge-base/project/specs/feat-legal-linkedin-page-4051/spec.md` | Lightweight spec mirroring the issue body (1 page max) per the project convention that every `feat-*` branch has a spec. Frontmatter: `lane: cross-domain`, `brand_survival_threshold: single-user incident`, `requires_cpo_signoff: true`, `requires_clo_signoff: true`. |
| `knowledge-base/project/specs/feat-legal-linkedin-page-4051/tasks.md` | Tasks breakdown for `/work` mode — one task per file in "Files to Edit" + "Files to Create" + one PR-body-write task + one operator-runbook task at the bottom. |

## Acceptance Criteria

### AC-Legal-1 — Counsel review (HARD GATE)

The three primary artifacts (LIA + Privacy Policy + DPD updates) MUST be reviewed by legal counsel before merge. The PR body must include a `### Counsel review` section with one checkbox per artifact, each ticked only after counsel's written sign-off (email or PandaDoc) is filed in `knowledge-base/legal/audits/2026-05-counsel-review-4051.md`.

**Verification:** Reviewer reads the PR body for the section; reads the audit file; confirms three boxes are ticked with date and counsel identifier.

### AC-Legal-2 — Article 30 PA15 cross-reference is live, not forward-looking

`grep -F "LIA documented in the follow-up legal-track PR #4051"` MUST return zero matches in `knowledge-base/legal/article-30-register.md` after this PR's edits. The replacement substring `LIA documented at \`knowledge-base/legal/legitimate-interest-assessments/2026-05-19-linkedin-org-page-lia.md\`` MUST appear at least once.

### AC-Legal-3 — LIA structure matches template

`grep -E "^## (Purpose|Necessity|Balancing|Outstanding counsel-review items|Re-evaluation triggers)$"` on the LIA file MUST return 5 matches. Each H2 section MUST be non-empty (≥3 sentences).

### AC-Legal-4 — Privacy Policy Art. 13(1)(e) disclosure complete

`grep -F "LinkedIn Ireland Unlimited Company"` in `docs/legal/privacy-policy.md` MUST return ≥2 matches (one in §5 sub-processor row, one in §10 international-transfers row).
`grep -F "Microsoft Ireland Operations Ltd"` MUST return ≥2 matches (same locations).

### AC-Legal-5 — Privacy Policy Art. 17 carve-out present

`grep -F "LinkedIn-published content"` in `docs/legal/privacy-policy.md` MUST return ≥1 match in the §8.1 right-to-erasure subsection. The matched paragraph MUST include the phrase `cannot guarantee removal from LinkedIn's cached or replicated systems` (or equivalent counsel-approved wording).

### AC-Legal-6 — DPD mirrors Privacy Policy

For each of the four assertions above (LinkedIn Ireland recipient, Microsoft Ireland recipient, Art. 17 carve-out, dual-basis disclosure), `grep -F` on `docs/legal/data-protection-disclosure.md` MUST return ≥1 match each.
DPD `### 2.3(p)` heading MUST exist (`grep -E '^- \*\*\(p\)\*\* \*\*LinkedIn Company Page publication\*\*' docs/legal/data-protection-disclosure.md`).

### AC-Compliance-1 — compliance-posture.md reflects in-progress → resolved transition

PR-open state: `knowledge-base/legal/compliance-posture.md` contains a row matching `| .* | #4051 | IN-PROGRESS |` in the Active Compliance Items table.
Pre-merge state: the same row's Status moves to a Completed Compliance Work entry (separate section per the file's existing convention) AND the Active Items row is removed in the same commit as PR-ready.
Top-of-file `last_updated:` frontmatter is bumped to merge-day date.

### AC-Infra-1 — Cloudflare redirect ruleset is on the narrow aliased provider

`grep -E 'provider\s*=\s*cloudflare\.jikigai_com'` on the new `cloudflare_ruleset` resource block MUST match. The `cf_api_token_jikigai_com` variable in `variables.tf` MUST NOT be amended (the narrow `Zone:DNS:Edit on jikigai.com` token must be expanded to include `Zone:Ruleset:Edit on jikigai.com` — verified separately at apply-time per AC-Infra-3; no `variables.tf` text change).

### AC-Infra-2 — Redirect target is the canonical soleur.ai privacy-policy URL

The `cloudflare_ruleset` rule action MUST set `status_code = 301` and `target_url.value = "https://soleur.ai/pages/legal/privacy-policy.html"`. The expression MUST be `http.host eq "jikigai.com" and http.request.uri.path eq "/legal/privacy-policy"` (no broader catch-all that might shadow future jikigai.com sub-paths).

### AC-Infra-3 — Targeted-apply blast radius safeguard documented

The file header comment in `jikigai-com.tf` MUST be extended with a sentence: "Apply this resource via `terraform apply -target=cloudflare_ruleset.jikigai_com_redirects` and follow with an untargeted `terraform plan` confirming zero soleur.ai drift (mirror of the verification-TXT pattern from #4046)."

### AC-Spec-Tasks-1 — spec.md + tasks.md exist for the branch

Per project convention (`/plan` Phase 0 step 4), `knowledge-base/project/specs/feat-legal-linkedin-page-4051/spec.md` and `tasks.md` MUST exist at PR-open time so `/work` can detect and read them.

## Implementation Phases

### Phase 1 — LIA draft + spec.md + tasks.md scaffolding (no counsel touch)

Files: `knowledge-base/legal/legitimate-interest-assessments/2026-05-19-linkedin-org-page-lia.md`, `knowledge-base/project/specs/feat-legal-linkedin-page-4051/spec.md`, `knowledge-base/project/specs/feat-legal-linkedin-page-4051/tasks.md`.

Drafting the LIA against the template — substitute:
- Processing Activity → "LinkedIn Company Page publication (Jikigai)"
- Data subjects → "LinkedIn Page followers + engagers + the Jikigai SARL gérant (named via K-bis at the appeal step)"
- Lawful basis → Art. 6(1)(f) for the Page operation; cross-reference Art. 6(1)(c) for the K-bis transfer (the K-bis transfer is NOT the subject of this LIA — it is Art. 6(1)(c) and noted only for completeness)
- Safeguards (vi) → list TOMs from PA15 row (g) (Doppler-only token storage, per-token expiry monitor, rolling-tracker error class, Terraform-managed DNS, targeted-apply safeguard, `LINKEDIN_ALLOW_POST` kill-switch)
- Outstanding counsel-review items → 3 carried-forward items (joint-controller assessment, K-bis transfer lawful-basis confirmation, Art. 17 carve-out wording)
- Re-evaluation triggers → first Page Insights API call (joint-controller assessment fires); any new LinkedIn product activation beyond `w_organization_social` posting; quarterly review per compliance-posture cadence

### Phase 2 — Privacy Policy + DPD edits

Files: `docs/legal/privacy-policy.md`, `docs/legal/data-protection-disclosure.md`.

Privacy Policy: insert §4.10 between §4.9 and §5; insert §5.12 + §5.13 at end of §5 (preserving §5.11 ordering); extend §6 paragraph on legal bases with the LinkedIn-Page dual-basis; extend §7 retention table with `LinkedIn Page publication` row; extend §8.1 right-to-erasure with the Art. 17 carve-out bullet; extend §10 international-transfers with LinkedIn / Microsoft Ireland rows; bump Last Updated header to 2026-05-19 (or merge day) with a one-line summary of the change.

DPD: insert `(p)` activity row in §2.3 between `(o)` and the closing paragraph; insert two rows in §4.2 Web Platform Processors table; extend §6.4 with two new rows (LinkedIn / Microsoft Ireland); extend §10.3 with `(i)` paragraph for Art. 17 LinkedIn-cache carve-out; bump Last Updated header.

### Phase 3 — Article 30 PA15 cross-reference promotion

File: `knowledge-base/legal/article-30-register.md`.

Single-substring replacement: `LIA documented in the follow-up legal-track PR #4051 per CLO High-1` → `LIA documented at \`knowledge-base/legal/legitimate-interest-assessments/2026-05-19-linkedin-org-page-lia.md\` (this PR — #4051)`. Same substring also appears in the PA15 closing paragraph; replace both. No structural change.

### Phase 4 — Cloudflare ruleset redirect

File: `apps/web-platform/infra/jikigai-com.tf`.

Append a `cloudflare_ruleset` resource:

```hcl
resource "cloudflare_ruleset" "jikigai_com_redirects" {
  provider    = cloudflare.jikigai_com
  zone_id     = var.cf_zone_id_jikigai_com
  name        = "jikigai-com-static-redirects"
  description = "Static redirects for jikigai.com. Added in #4051 (LinkedIn appeal privacy-policy URL alignment)."
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules {
    expression = "http.host eq \"jikigai.com\" and http.request.uri.path eq \"/legal/privacy-policy\""
    action     = "redirect"
    description = "Privacy policy → soleur.ai canonical URL for LinkedIn appeal alignment (#4051)."

    action_parameters {
      from_value {
        status_code = 301
        target_url {
          value = "https://soleur.ai/pages/legal/privacy-policy.html"
        }
        preserve_query_string = false
      }
    }
  }
}
```

Extend the file header comment with the apply-time caveat (per AC-Infra-3).

**Operator action required at apply time** (NOT a code change in this PR — call out in the PR body operator-runbook section): expand the `cf_api_token_jikigai_com` Cloudflare API token scope from `Zone:DNS:Edit` (only) to `Zone:DNS:Edit + Zone:Ruleset:Edit` on the `jikigai.com` zone. Token expansion is done in the Cloudflare dashboard and re-pasted into Doppler `prd` under the same secret name.

### Phase 5 — compliance-posture.md row

File: `knowledge-base/legal/compliance-posture.md`.

PR-open: add Active Compliance Items row `| LinkedIn org-page legal-track (LIA + Privacy Policy + DPD) | #4051 | IN-PROGRESS | <merge_target_date> | Blocks #4046 Phase 5.4 |`. Add LIA row to Legal Documents table. Bump Last Updated columns for Privacy Policy + DPD.

Pre-merge (separate commit OR same commit, operator's choice): move the Active Items row's resolved-form into a Completed Compliance Work entry at the bottom of the file (per the file's existing convention with HTML-comment-prefixed merge log entries) AND remove the Active Items row.

### Phase 6 — PR body + counsel-review handshake

Files: `gh pr create --draft` body; new `knowledge-base/legal/audits/2026-05-counsel-review-4051.md` audit file.

PR body structure:
- `## Summary` — three artifacts + redirect, blocks #4046 Phase 5.4.
- `## Closes` — `Closes #4051`. (NOT `Closes #4046` — the parent issue must stay open until Phase 5.4 + 6 of the runbook also complete.)
- `## User-Brand Impact` — copy from this plan's section.
- `## Counsel review` — three checkboxes (LIA, Privacy Policy, DPD), each pointing at the audit file's line for that artifact.
- `## Operator runbook (post-merge)` — three steps: (1) expand Cloudflare API token scope per AC-Infra-3 operator note; (2) update LinkedIn Developer app 229658411 privacy-policy URL from `https://soleur.ai/pages/legal/privacy-policy.html` → `https://jikigai.com/legal/privacy-policy`; (3) proceed with Phase 5.4 of parent runbook (K-bis appeal upload at `https://www.linkedin.com/help/linkedin/ask/dsapi`).

Audit file is a stub at PR-open with three lines reserved for counsel's signature; filled in after counsel reviews each artifact.

## Re-evaluation triggers

The LIA itself contains `## Re-evaluation triggers` — those govern the LIA's standalone validity. This plan-level list governs when to re-open #4051's broader scope:

- First Page Insights API call (joint-controller assessment under Art. 26 + C-210/16 fires — separate follow-up issue to be filed at that time).
- Any expansion of the Soleur ↔ LinkedIn relationship beyond `w_organization_social` posting (e.g., Pages-API, Sponsored Content API, Lead Gen Forms) — requires fresh CLO assessment.
- Any LinkedIn / Microsoft policy change to the appeal-flow document custody (currently Microsoft Ireland EUDB) — invalidates PA15(e) and the Privacy Policy §10 row.
- Quarterly compliance-posture review (the LIA's quarterly cadence trigger also fires this plan's re-evaluation).

## Mandatory Plan Review

Per `/plan` Phase 6, three reviewers (DHH + Kieran + code-simplicity) MUST be run on this plan before tasks are written. **Note:** this plan is a *legal-doc* plan, not a Rails or source-code plan. The Rails reviewers' value-add on a docs-only plan is low; code-simplicity is the load-bearing reviewer.

**Planned reviewer set (operator decides at `/work` time whether to override):**
- `code-simplicity-reviewer` (required) — verify the redirect fold-in stays minimal; verify no duplicate-hosting; verify DPD's single `(p)` row pattern.
- `legal-compliance-auditor` (substituting for DHH/Kieran on this docs-only plan) — pre-counsel triage of the LIA + Privacy Policy + DPD edits against EDPB Guidelines 5/2019 + EDPB Guidelines 1/2024 (Art. 6(1)(f)) + CNIL Référentiel — substantive but advisory; counsel review under AC-Legal-1 remains the hard gate.

If `/work` runs the standard DHH + Kieran pair as a procedural matter, expect "out of scope — this is a docs PR" responses; that is acceptable and not a blocker.

## Pre-flight Check 6 Anchors (for /work)

- `Brand-survival threshold: single-user incident` — canonical bullet form is the H1-frontmatter line above (`brand_survival_threshold: single-user incident`) AND the `## Brand-survival posture` section's first sentence.
- `requires_cpo_signoff: true` — frontmatter line above.
- `requires_clo_signoff: true` — frontmatter line above.
- `## User-Brand Impact` — section heading above.

## Sharp Edges

1. **PA15 cross-reference replacement is text-substring sensitive.** The two replace sites in `article-30-register.md` are similar but not identical (one in the lawful-basis row entry, one in the closing paragraph). Use `Edit replace_all=false` twice with the correct surrounding context, not `replace_all=true` — the surrounding context differs by adjacent prose.
2. **`docs/legal/privacy-policy.md` is large.** Section IDs and ordering matter — read the relevant chunk before each insertion. Section numbering must remain contiguous (§5.12 must exist before §5.13 is added; do not skip).
3. **DPD section `(p)` letter is determined by the current state of `(a)`-`(o)`.** Read §2.3 first; if a parallel PR has already taken `(p)`, use the next available letter. (Currently `(o)` is the last per the 2026-05-18 read above.)
4. **Counsel-review file path convention.** The directory `knowledge-base/legal/audits/` exists per the directory listing earlier — the audit file follows the naming convention `<YYYY-MM>-<topic>-<issue>.md`. Confirm path collision before write.
5. **Cloudflare ruleset provider scope.** The narrow `cf_api_token_jikigai_com` API token in Doppler currently has `Zone:DNS:Edit on jikigai.com` only. Adding a ruleset requires `Zone:Ruleset:Edit` on the same zone. This is an OPERATOR action at apply-time, not a code change. Documented in Phase 4 + AC-Infra-1 operator note + PR-body operator-runbook step (1).

## Resume Prompt (for /work)

```
knowledge-base/project/plans/2026-05-19-feat-legal-linkedin-page-4051-plan.md

Branch: feat-legal-linkedin-page-4051. Worktree: .worktrees/legal-linkedin-org-page-4051/. Issue: #4051. Blocks: #4046 Phase 5.4 (operator-runbook K-bis appeal upload). Related: #4047 (merged parent PR), #4052 (DNS import, follow-up).

State: plan committed; spec.md + tasks.md must be written in Phase 1 alongside the LIA draft (per AC-Spec-Tasks-1). No code changes yet.

Phases 1-6 are docs + thin-infra; no test suite touches; counsel review is the load-bearing gate (AC-Legal-1).

Plan-time gates absorbed (do not re-spawn): gdpr-gate (this plan IS the Critical fold-in from parent #4046), terraform-architect (single ruleset resource on existing aliased provider), spec-flow-analyzer (no new ACs needed beyond AC-Legal-1), code-simplicity-reviewer (3 simplifications applied — redirect-only, single DPD letter, single compliance row).

Sign-off: CLO required (carried forward + this PR is the deliverable); CPO required (carried forward, brand-survival threshold single-user incident); CMO/CTO advisory.

Operator action at apply-time (Phase 4): expand `cf_api_token_jikigai_com` Cloudflare API token scope to add `Zone:Ruleset:Edit on jikigai.com`; re-paste into Doppler `prd`.

A fresh session reading this resume prompt + tasks.md + plan has everything needed to execute Phases 1-6 cleanly.
```
