---
title: "infra(cleanup): remove orphan jikigai-com.tf"
date: 2026-05-19
type: infra-cleanup
lane: single-domain
issue: 4084
pr: 4088
related_issues: [4046, 4047, 4051, 4052, 4081]
brand_survival_threshold: none
requires_cpo_signoff: false
---

# infra(cleanup): remove orphan `jikigai-com.tf` — jikigai.com DNS is on Google Cloud, not Cloudflare

## Enhancement Summary

**Deepened on:** 2026-05-19
**Sections enhanced:** 3 (Research Reconciliation, Implementation Phases, Acceptance Criteria)
**Verification surface:**

- Rule IDs cited: `hr-menu-option-ack-not-prod-write-auth`, `hr-weigh-every-decision-against-target-user-impact` — both verified active in AGENTS sidecars.
- Labels cited: `domain/engineering`, `chore` — both verified via `gh label list`.
- Related issues/PRs cited: `#4046` (OPEN), `#4047` (MERGED), `#4051` (OPEN), `#4081` (MERGED), `#4052` (OPEN, will be closed post-merge), `#4084` (OPEN, target of this PR), `#4088` (OPEN, the draft PR).
- DNS authority claim re-verified: `dig +short +time=3 +tries=1 NS jikigai.com` → `ns-cloud-c[1-4].googledomains.com.` (Google Cloud DNS, not Cloudflare).
- File-list completeness audit: `git grep -lE 'jikigai-com\.tf|cf_(api_token|zone_id)_jikigai_com|linkedin_page_verification_txt|cloudflare\.jikigai_com|jikigai_com_redirects|linkedin_verification' -- ':!knowledge-base' ':!*.lock*'` returns exactly the three files named in `## Files to Edit` (`jikigai-com.tf`, `main.tf`, `variables.tf`). Zero workflows, hooks, scripts, or app-code consumers — confirms the cleanup is structurally orphan and merge has no runtime fan-out.
- `terraform fmt -check` already passes at HEAD; the Phase 1 edits introduce no formatting drift.

### Key Improvements

1. **Caught the fourth orphan surface (`main.tf:20`) at plan time, not /work time.** The issue body enumerated 3 surfaces (the file + 3 variables); the plan's Research Reconciliation table extends the file list to include `main.tf`'s `configuration_aliases = [cloudflare.jikigai_com]` declaration. Without this, `terraform validate` would fail post-edit because the alias is declared in `required_providers` but its `provider "cloudflare" { alias = "jikigai_com" ... }` block has been deleted. Pre-merge AC1 (`terraform validate`) is now the canonical mechanical catch.
2. **Bounded the post-merge blast radius.** Sharp Edges entry pre-empts the common over-eager `terraform apply` mistake — `terraform plan` returning `No changes` is the verdict; any unrelated drift surfacing during plan goes to a separate issue per `hr-menu-option-ack-not-prod-write-auth`, not into this PR.
3. **Defended the legal/compliance posture.** The Compliance Gate section establishes that removing the TXT verification stub and `/legal/privacy-policy` redirect does NOT invalidate the #4081 LIA — the load-bearing Art. 13 controller-identity disclosure lives in the Privacy Policy content (§2 + §4.10), not in the URL domain alignment cue that was the motivation for the orphan code. The substantive compliance disclosure is unchanged.

### New Considerations Discovered

- **Historical KB doc references stay intact (out of scope).** `knowledge-base/legal/article-30-register.md`, `compliance-posture.md`, the 2026-05-19 LIA, the brainstorm, and the two parent plans all reference `jikigai-com.tf`. Out-of-scope rationale is explicit: these are historical audit-trail records of the #4046 → #4051 → #4081 → #4084 decision chain. Rewriting them would erase context the auditor needs.
- **The closure semantic for #4084 vs #4052 is deliberate.** This PR uses `Closes #4084` (the cleanup completes at merge — code change is the whole fix) but `gh issue close 4052 --reason "not planned"` as a post-merge step rather than `Closes #4052` in the PR body. Different reasons: #4084 is fixed by the merge; #4052 is being declined as not-pursuing-this-direction, which is semantically different from "this PR resolved it" and benefits from a manually-authored closure comment that explains the underlying premise reversal.

## Overview

`apps/web-platform/infra/jikigai-com.tf` and three supporting variables were added in #4046 / #4051 on the premise that jikigai.com would be migrated to Cloudflare. That premise is wrong: `dig +short NS jikigai.com` returns Google Cloud DNS nameservers (`ns-cloud-c[1-4].googledomains.com`). The orphan resources reference a zone that does not exist on Cloudflare, the supporting Doppler variables (`TF_VAR_cf_api_token_jikigai_com`, `TF_VAR_cf_zone_id_jikigai_com`, `TF_VAR_linkedin_page_verification_txt`) were never populated, and a `terraform plan` in `prd_terraform` would currently fail with `no value for required variable`.

This PR removes the orphan code so the next operator does not waste time chasing missing variables, and closes the sibling follow-up #4052 which was based on the same incorrect premise.

**Runtime impact:** zero. The orphan resources were never applied (no Doppler values → `terraform plan` fails before reaching `apply`). The TXT verification and `/legal/privacy-policy` redirect from #4081 were not load-bearing for any live production path — the LinkedIn appeal flow accepted the privacy-policy URL staying at `soleur.ai/pages/legal/privacy-policy.html` (the Privacy Policy content itself names Jikigai SARL as data controller in §2 + §4.10, which is the substantive Art. 13 disclosure).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing. The deleted code never ran in production; there is no user-facing artifact. The only operator-visible failure mode is `terraform validate` failing locally (caught by Pre-merge AC1).
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A — no data is processed by the deleted code. The deletion removes three variable declarations (one sensitive) but none had values in Doppler.
- **Brand-survival threshold:** none. Reason: cleanup-only of unapplied IaC; zero production code path is affected; no operator action required post-merge other than closing the sibling stale issue #4052.

## Research Reconciliation — Spec vs. Codebase

| Issue body claim | Codebase reality | Plan response |
| --- | --- | --- |
| "Delete `jikigai-com.tf` + the three orphan variables in `variables.tf` (recommended — cleanup-only, no behavior change)" | `main.tf:20` also references `configuration_aliases = [cloudflare.jikigai_com]` inside the `required_providers { cloudflare {} }` block. The aliased provider declaration in `jikigai-com.tf` (`provider "cloudflare" { alias = "jikigai_com" ... }`) is wired through `main.tf`'s `configuration_aliases` declaration. | Plan **extends scope** to also remove the `configuration_aliases = [cloudflare.jikigai_com]` line in `main.tf:20`. Without this fourth edit, `terraform validate` fails because the alias is declared in `required_providers` but its provider block has been deleted. The issue body's 3-surface enumeration is incomplete. |
| "`terraform plan` in `prd_terraform` reports `No changes`" | Currently, `terraform plan` in `prd_terraform` FAILS with `no value for required variable` (the three `*_jikigai_com` / `linkedin_page_verification_txt` vars are not in Doppler). After this PR's variable removal, the failure goes away and `plan` proceeds; the expected result on the soleur.ai resources is `No changes`. | AC2 phrased as: `terraform validate` passes locally pre-merge; post-merge operator runs `terraform plan` and confirms `No changes` on the remaining (soleur.ai-only) resource set. |
| "linkedin_page_verification_txt deferred-scope-out follow-up (#4052) jikigai.com DNS import to Cloudflare" | jikigai.com is on Google Cloud DNS (`ns-cloud-c[1-4].googledomains.com`). The #4052 acceptance criteria ("enumerate jikigai.com DNS records via Cloudflare MCP") is unworkable — the zone is not on Cloudflare. | Plan adds AC3: close #4052 with reason "not pursuing — jikigai.com stays on Google Cloud DNS". Closure command in Post-merge ACs. |

## Files to Edit

- `apps/web-platform/infra/jikigai-com.tf` — **DELETE** (file removal; 93 lines).
- `apps/web-platform/infra/variables.tf` — remove three blocks: `cf_zone_id_jikigai_com` (lines 161-164), `cf_api_token_jikigai_com` (lines 166-170), `linkedin_page_verification_txt` (lines 172-176). Also remove the leading section comment block (lines 154-159) since it loses its referent. Net: ~24 lines removed.
- `apps/web-platform/infra/main.tf` — remove line 20: `configuration_aliases = [cloudflare.jikigai_com]`. The surrounding `required_providers { cloudflare = { source = ..., version = "~> 4.0" } }` block stays.

## Files to Create

None.

## Open Code-Review Overlap

None. No open `code-review`-labeled issues touch `apps/web-platform/infra/jikigai-com.tf`, `apps/web-platform/infra/variables.tf`, or `apps/web-platform/infra/main.tf` (verified at plan time via `gh issue list --label code-review --state open` cross-referenced against the file list above).

## Research Insights

**Terraform aliased-provider lifecycle.** When a child module / aliased provider block is removed, three layers must be aligned in the same commit or `terraform validate` fails:

1. The aliased `provider "cloudflare" { alias = "jikigai_com" ... }` block (lives in `jikigai-com.tf`, deleted by file removal).
2. The consumer resources that pin `provider = cloudflare.jikigai_com` (also in `jikigai-com.tf`, deleted by file removal).
3. The root-module declaration `configuration_aliases = [cloudflare.jikigai_com]` inside `required_providers { cloudflare {} }` (lives in `main.tf:20`, removed by the targeted line edit).

This is the most common cause of "I deleted the .tf file but `terraform validate` still fails" — the `configuration_aliases` list survives the file deletion and produces `Provider configuration not present` errors at the next validate. The plan's Pre-merge AC1 (`terraform validate`) is the canonical mechanical catch.

**Why state poisoning is not a concern here.** Neither `cloudflare_record.linkedin_verification` nor `cloudflare_ruleset.jikigai_com_redirects` ever made it into `terraform.tfstate` — apply was never run successfully because `TF_VAR_cf_zone_id_jikigai_com` / `TF_VAR_cf_api_token_jikigai_com` / `TF_VAR_linkedin_page_verification_txt` were never populated in Doppler `prd_terraform`, so every `apply` attempt would fail at the variable-resolution step before any provider call. Removing the resources from code therefore needs no corresponding `terraform state rm` / `removed { ... }` block. (If state had ever contained these resources, the canonical safe-deletion pattern would be either (a) Terraform 1.7+ `removed { from = ..., lifecycle { destroy = false } }` blocks in the same PR, or (b) a paired `terraform state rm` step in a post-merge runbook. Neither is needed here.)

**Why this PR doesn't need a feature flag or kill-switch.** The orphan code has no production traffic, no dashboard reads, no operator workflows depending on it. Deletion is structurally reversible by `git revert` if some unforeseen consumer surfaces — but the plan-time grep sweep across `apps/`, `.github/`, `scripts/`, `.claude/hooks/` returned exactly the three files in the Files-to-Edit list and nothing else, so no unforeseen consumer is expected.

**Institutional learnings applied:**

- `hr-menu-option-ack-not-prod-write-auth` — informs the Sharp Edges entry that post-merge `terraform plan` is the verdict, NOT `terraform apply`; any unrelated drift surfaces during plan goes to a separate issue rather than expanding this PR's scope.
- `hr-weigh-every-decision-against-target-user-impact` — informs the `## User-Brand Impact` section's `threshold: none` plus explicit reason; the scope-out is well-formed even though the diff touches the sensitive-path canonical regex (`apps/[^/]+/infra/`).
- `cq-rule-ids-are-immutable` / retired-rule registry — informs the verification step in the Enhancement Summary that both cited rule IDs are active (not retired, not fabricated).
- AGENTS.md hard rule on `Closes #N` semantics for ops-remediation classes — does NOT apply here. This is a code-change cleanup, not an ops-only-prod-write remediation. The closure happens at merge (the code change IS the fix); `Closes #4084` in PR body is correct. The contrast: #4052 is being declined as a not-pursuing decision, which uses `gh issue close 4052 --reason "not planned"` post-merge, not `Closes #4052` in the PR body.

**References:**

- Terraform docs on `configuration_aliases` requirement when removing aliased providers: <https://developer.hashicorp.com/terraform/language/modules/develop/providers#provider-aliases-within-modules>
- AGENTS.md rule registry (live grep): `AGENTS.md`, `AGENTS.core.md`, `AGENTS.docs.md`, `AGENTS.rest.md`
- Canonical Doppler-Terraform invocation triplet for `prd_terraform`: documented in `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md` (cited verbatim in Phase 3 tasks).

## Implementation Phases

### Phase 1 — Delete orphan IaC (atomic)

All four edits ship in one commit. Order does not matter for the file system but `main.tf` MUST be edited in the same commit as the deletion of `jikigai-com.tf` to keep `terraform validate` green at HEAD.

```bash
cd apps/web-platform/infra
git rm jikigai-com.tf

# Edit variables.tf — remove section comment (lines 154-159) + three variable blocks (lines 161-176).
# Edit main.tf — remove the single line `configuration_aliases = [cloudflare.jikigai_com]`.
```

Verification before commit:

```bash
cd apps/web-platform/infra
terraform fmt -check
terraform validate    # MUST pass; the configuration_aliases removal is what gates this.
```

### Phase 2 — Post-merge: close sibling #4052

After PR #4088 merges to main:

```bash
gh issue close 4052 --reason "not planned" --comment "Closing — based on the same incorrect premise as #4084 (jikigai.com DNS is on Google Cloud DNS, not Cloudflare). The acceptance criteria (enumerate jikigai.com DNS records via Cloudflare MCP) is unworkable for the same reason. Resolved alongside #4084 by removing the orphan jikigai-com.tf entirely (PR #4088)."
```

This step is automatable via `gh` CLI — handled as a Post-merge AC, executed by the operator (or `/soleur:ship` post-merge verification) immediately after merge.

## Acceptance Criteria

### Pre-merge (PR)

1. **`terraform validate` passes locally.** Run from `apps/web-platform/infra/`: `terraform validate` exits 0. (Direct check that the `main.tf:20` `configuration_aliases` removal is paired with the `jikigai-com.tf` deletion.)
2. **`terraform fmt -check` passes.** Run from `apps/web-platform/infra/`: `terraform fmt -check` exits 0.
3. **No dangling references to the removed symbols.** `git grep -nE 'jikigai-com\.tf|cf_(api_token|zone_id)_jikigai_com|linkedin_page_verification_txt|cloudflare\.jikigai_com|jikigai_com_redirects|linkedin_verification' apps/web-platform/infra/` returns zero matches. (KB docs and historical plans/learnings under `knowledge-base/` are out of scope — historical references are intentional.)
4. **File deletion is recorded.** `git diff --stat origin/main..HEAD -- apps/web-platform/infra/jikigai-com.tf` shows the file fully removed.
5. **PR body cites #4084 and #4081 for cross-reference.** `Closes #4084` (the cleanup completes at merge — no post-merge prod-write required for the closure semantics). Reference (not Closes) for #4081 since this is downstream cleanup, not a fix for #4081 itself.

### Post-merge (operator)

1. **Run `terraform plan` against `prd_terraform`.** Expected: `No changes. Your infrastructure matches the configuration.` on the soleur.ai-only resource set. Automation: `/soleur:ship` post-merge verification handles `terraform plan` runs for modified infra paths if configured; otherwise operator runs the canonical triplet (export AWS R2 creds + `terraform init -input=false` + `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan`).
2. **Close #4052.** `gh issue close 4052 --reason "not planned" --comment "..."` (full comment text in Phase 2). Automation: feasible via `gh` CLI; automatable in /soleur:ship post-merge or manual single command.
3. **(Optional, hygiene)** Operator may delete the unused Doppler secret stubs if any were created. Inventory check: `doppler secrets --project soleur --config prd_terraform 2>&1 | grep -iE 'JIKIGAI_COM|LINKEDIN_PAGE_VERIFICATION'` should return zero. If matches found, `doppler secrets delete --project soleur --config prd_terraform <NAME>` for each. (Issue body confirmed zero such secrets exist; this is a fail-safe.)

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Removing `configuration_aliases` line in `main.tf` is forgotten in the same commit as the file deletion | Low (caught by Pre-merge AC1) | Local + CI `terraform validate` fails | Plan explicitly enumerates all 4 surfaces; AC1 runs `terraform validate` |
| A future cron / drift-detector still references one of the removed variables | Negligible | Workflow failure at next run | Plan AC3 greps the whole infra tree; no `.github/workflows/` or `apps/web-platform/server/` consumers exist (verified at plan time) |
| KB docs that reference `jikigai-com.tf` (article-30-register, compliance-posture, brainstorms, plans) become stale | Low | Historical-doc drift; operator confusion | Out of scope. Historical KB references are intentional records of the decision trail (#4046 → #4051 → #4081 → #4084). Drift remediation belongs in a separate audit, not this cleanup. |
| Post-merge `terraform plan` reveals unrelated drift | Low | Distracts from this PR's verdict | Operator should triage per `hr-menu-option-ack-not-prod-write-auth` — file a separate issue, do not expand this PR's scope at apply time |
| #4052 closure produces audit-trail gap | Negligible | None | The closure comment includes the reason and references this PR; future readers see the complete trail in the issue history |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure cleanup of unapplied code with zero runtime impact. The deletion does not affect privacy/legal posture (the Privacy Policy + LIA + Article 30 Register at #4081 stand; their canonical hosting on `soleur.ai/pages/legal/privacy-policy.html` is unchanged), does not affect any user-facing surface, and does not change billing, security, or compliance.

## Infrastructure (IaC)

This plan removes IaC; it does not introduce new infrastructure. No new Terraform root, no new resources, no new providers, no new secrets. Skip rationale: the IaC routing gate (Phase 2.8) is the inverse of what this plan does — the gate ensures new operator-facing actions are baked into Terraform; this plan removes orphan Terraform that should never have shipped without paired Doppler values.

### Terraform changes

- Files: `apps/web-platform/infra/jikigai-com.tf` (deleted), `apps/web-platform/infra/variables.tf` (3 variable blocks + 1 section comment removed), `apps/web-platform/infra/main.tf` (1 `configuration_aliases` entry removed).
- Required providers: unchanged (cloudflare ~> 4.0, hcloud ~> 1.49, random ~> 3.0, doppler ~> 1.21, betteruptime ~> 0.20).
- Sensitive variables removed: `cf_api_token_jikigai_com`, `linkedin_page_verification_txt` (both were `sensitive = true`, never populated in Doppler).

### Apply path

No `apply` for this PR. Code change only. Post-merge verification is `terraform plan` (Post-merge AC1), expected outcome `No changes` since neither `jikigai-com.tf` resource was ever in state.

### Distinctness / drift safeguards

N/A — no resources are being added or modified.

### Vendor-tier reality check

N/A — no vendor resources affected.

## GDPR / Compliance Gate

This plan removes the Cloudflare TXT verification stub and `/legal/privacy-policy` redirect that the #4081 LIA cited as alignment mechanics for the LinkedIn appeal flow. Compliance posture analysis:

- **The Privacy Policy itself remains hosted at `soleur.ai/pages/legal/privacy-policy.html`** (unchanged). Article 13 disclosure (controller identity = Jikigai SARL, K-bis-named) lives in the policy CONTENT (§2 + §4.10), not in the URL domain.
- **The LIA (`knowledge-base/legal/legitimate-interest-assessments/2026-05-19-linkedin-org-page-lia.md`)** referenced the jikigai.com → soleur.ai redirect as a domain-alignment cue. Removing the redirect does not invalidate the LIA — the controller-identity disclosure in the policy content is the load-bearing Art. 13 element; the URL domain is a soft signal that the LinkedIn appeal-flow reviewer was already documented (in the issue body) as not enforcing strictly.
- **Article 30 Register entry** referencing `jikigai-com.tf` becomes a historical reference. The Register may want a `[Resolved YYYY-MM-DD]` annotation on that entry pointing to PR #4088, but that is a hygiene update for a separate doc-cleanup PR (out of scope here per the "no KB doc drift remediation" risk-table entry).

**Lawful basis:** unchanged. No new processing introduced; this is removal of unapplied infrastructure.

**Skip rationale for full gate:** the deletion does not touch any of the canonical regex surfaces (`*.sql`, migrations, auth flows, API routes). It does not introduce new processing activity, does not change brand-survival threshold (already `none`), does not add a cron/workflow that reads operator-session data, and does not add a new artifact distribution surface. The full `/soleur:gdpr-gate` invocation is not warranted at plan time; the compliance analysis above suffices.

## Test Strategy

**No new tests.** The pre-merge ACs are direct mechanical verifications (`terraform validate`, `terraform fmt -check`, `git grep` for dangling references) — these are stronger than any test could be since they assert on the actual artifact state, not a synthetic harness.

Existing test infrastructure under `apps/web-platform/infra/*.test.sh` is unaffected (none of the deleted resources had test coverage; they were never apply-eligible).

## Out of Scope

- Migrating jikigai.com DNS from Google Cloud DNS to Cloudflare (would require infra-consolidation roadmap entry; not justified by this issue alone per issue body).
- Updating KB docs that reference the deleted file (`knowledge-base/legal/article-30-register.md`, `knowledge-base/legal/compliance-posture.md`, `knowledge-base/legal/legitimate-interest-assessments/2026-05-19-linkedin-org-page-lia.md`, the brainstorm at `2026-05-19-linkedin-community-api-reapply-jikigai-brainstorm.md`, and the two plans at `2026-05-19-feat-legal-linkedin-page-4051-plan.md` + `2026-05-19-feat-linkedin-api-reapply-jikigai-plan.md`). These are historical records of the decision trail; rewriting them would erase audit context.
- Removing the `apps/web-platform/infra/sentry` / other infra paths.
- Any change to Cloudflare's soleur.ai zone, the LinkedIn integration, or the privacy-policy canonical URL.

## Sharp Edges

- The `main.tf:20` `configuration_aliases` line is the easiest line to miss — it lives 100+ lines away from `jikigai-com.tf` and isn't named in the issue body. Pre-merge AC1 (`terraform validate`) is the canonical mechanical catch for this; trust the validator, don't trust the issue's enumeration.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares `threshold: none, reason: cleanup-only of unapplied IaC; zero production code path is affected; no operator action required post-merge other than closing the sibling stale issue #4052.`
- Post-merge, do NOT run `terraform apply` against `prd_terraform` as part of "verifying" this PR. `terraform plan` returning `No changes` is the verdict; running `apply` would only be appropriate if there were unrelated drift to resolve, in which case file a separate issue per `hr-menu-option-ack-not-prod-write-auth`.

## PR Body Reminder

```
Closes #4084
Ref #4081 (the orphan was extended in #4051 → #4081)
Ref #4046 / #4047 (original orphan introduction)

Post-merge: close #4052 with reason "not pursuing — jikigai.com stays on Google Cloud DNS".
```

Labels: `domain/engineering`, `chore`.
