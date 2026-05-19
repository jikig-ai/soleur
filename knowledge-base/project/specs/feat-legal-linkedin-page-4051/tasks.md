---
title: "Tasks — Legal-track PR (#4051)"
type: tasks
date: 2026-05-19
issue: 4051
branch: feat-legal-linkedin-page-4051
plan: knowledge-base/project/plans/2026-05-19-feat-legal-linkedin-page-4051-plan.md
spec: knowledge-base/project/specs/feat-legal-linkedin-page-4051/spec.md
---

# Tasks — #4051 Legal-track PR

## Phase 1 — LIA draft + spec scaffolding

- [x] **T1.1** Write `knowledge-base/legal/legitimate-interest-assessments/2026-05-19-linkedin-org-page-lia.md` using template `2026-05-14-tenant-deploy-substrate-lia.md`. Frontmatter (status: draft-requires-counsel-review; controller: Jikigai SARL; processing_activity: LinkedIn Company Page publication; lawful_basis: Art. 6(1)(f); data_subjects: LinkedIn Page followers + engagers; related: [article-30-register, 4046, 4047]). H2s: Purpose, Necessity, Balancing (with (i)-(vi) subsections), Outstanding counsel-review items (3 carried-forward items), Re-evaluation triggers. Reference TOMs from PA15 row (g).
- [x] **T1.2** Verify against AC-Legal-3: `grep -E "^## (Purpose|Necessity|Balancing|Outstanding counsel-review items|Re-evaluation triggers)$"` returns 5 matches; each H2 ≥3 sentences.

## Phase 2 — Privacy Policy + DPD edits

- [x] **T2.1** Read `docs/legal/privacy-policy.md` sections that need amending (§4, §5, §6, §7, §8.1, §10) before any Edit calls.
- [x] **T2.2** Insert §4.10 "LinkedIn Company Page publication" data-class block in `docs/legal/privacy-policy.md` between §4.9 and §5.
- [x] **T2.3** Append §5.12 "LinkedIn Ireland Unlimited Company" sub-processor row to `docs/legal/privacy-policy.md`.
- [x] **T2.4** Append §5.13 "Microsoft Ireland Operations Ltd" sub-processor row to `docs/legal/privacy-policy.md`.
- [x] **T2.5** Extend `docs/legal/privacy-policy.md` §6 legal-basis paragraph with dual-basis disclosure (Art. 6(1)(c) for K-bis transfer + Art. 6(1)(f) for Page operation).
- [x] **T2.6** Extend `docs/legal/privacy-policy.md` §7 retention with LinkedIn Page row.
- [x] **T2.7** Extend `docs/legal/privacy-policy.md` §8.1 with Art. 17 LinkedIn-published-content carve-out bullet (include phrase "cannot guarantee removal from LinkedIn's cached or replicated systems").
- [x] **T2.8** Extend `docs/legal/privacy-policy.md` §10 international-transfers with LinkedIn Ireland EU + Microsoft Ireland EUDB rows.
- [x] **T2.9** Bump `docs/legal/privacy-policy.md` "Last Updated" header with one-line summary of #4051 changes.
- [x] **T2.10** Read `docs/legal/data-protection-disclosure.md` sections that need amending (§2.3, §4.2, §6.4, §10.3) before any Edit calls.
- [x] **T2.11** Insert §2.3(p) "LinkedIn Company Page publication" activity row in DPD between §2.3(o) and the closing paragraph.
- [x] **T2.12** Add two rows (LinkedIn Ireland + Microsoft Ireland) to DPD §4.2 Web Platform Processors table.
- [x] **T2.13** Extend DPD §6.4 with LinkedIn Ireland EU + Microsoft Ireland EUDB rows.
- [x] **T2.14** Extend DPD §10.3 with Art. 17 LinkedIn-cache carve-out paragraph.
- [x] **T2.15** Bump DPD "Last Updated" header.
- [x] **T2.16** Verify against AC-Legal-4, AC-Legal-5, AC-Legal-6 with the grep commands listed in the plan.

## Phase 3 — Article 30 PA15 cross-reference

- [x] **T3.1** Read `knowledge-base/legal/article-30-register.md` lines around 275 (lawful-basis row entry) and 281 (closing paragraph) before Edit.
- [x] **T3.2** Replace `LIA documented in the follow-up legal-track PR #4051 per CLO High-1` at the lawful-basis row site with the concrete LIA path.
- [x] **T3.3** Replace the closing-paragraph forward-looking sentence with a resolved-state version naming the concrete LIA path + the Privacy Policy / DPD sections.
- [x] **T3.4** Verify AC-Legal-2: `grep -F "LIA documented in the follow-up legal-track PR #4051"` returns 0 matches; `grep -F "knowledge-base/legal/legitimate-interest-assessments/2026-05-19-linkedin-org-page-lia.md"` returns ≥2 matches in the file.

## Phase 4 — Cloudflare ruleset redirect

- [x] **T4.1** Read `apps/web-platform/infra/jikigai-com.tf` before Edit.
- [x] **T4.2** Extend the file-header comment block with the apply-time caveat per AC-Infra-3 (includes operator-action note for `Zone:Ruleset:Edit` token expansion).
- [x] **T4.3** Append the `cloudflare_ruleset.jikigai_com_redirects` resource block per Plan §Phase 4.
- [x] **T4.4** Run `terraform fmt -check` (rc=0) and `terraform init -backend=false` + `terraform validate` (Success).
- [x] **T4.5** Verify AC-Infra-1 (2 `provider = cloudflare.jikigai_com` matches), AC-Infra-2 (status_code = 301 + canonical target), AC-Infra-3 (apply-time caveat present).

## Phase 5 — compliance-posture.md row

- [x] **T5.1** Read `knowledge-base/legal/compliance-posture.md` Active Compliance Items section.
- [x] **T5.2** Add Active Item row for `#4051 | IN-PROGRESS | Blocks #4046 Phase 5.4 (K-bis appeal)`.
- [x] **T5.3** Add `LinkedIn Page LIA` row to the Legal Documents table.
- [x] **T5.4** Bump Last Updated columns for Privacy Policy + DPD + Article 30 Register rows; bump top-of-file `last_updated:` frontmatter.
- [x] **T5.5** Add HTML-comment merge-log row at top of file with one-line summary linking to #4051.
- [x] **T5.6** Verify AC-Compliance-1: row present with `#4051 | IN-PROGRESS` substring.

## Phase 6 — PR body + counsel-review audit stub

- [x] **T6.1** Create `knowledge-base/legal/audits/2026-05-counsel-review-4051.md` stub with three reserved sign-off rows (LIA, Privacy Policy, DPD).
- [x] **T6.2** Opened draft PR #4081 with body per Plan §Phase 6 (Summary + Refs #4051 + User-Brand Impact + Counsel review checkboxes + Operator runbook). https://github.com/jikig-ai/soleur/pull/4081
- [x] **T6.3** Pushed branch `feat-legal-linkedin-page-4051` to origin (commit 4ccd526b).

## Pre-merge gates (do not run before counsel sign-off)

- [x] **T7.1** Counsel review LIA → operator-attested sign-off recorded (Jean Deruelle, Jikigai SARL gérant; external counsel re-review at first Page Insights call OR first non-Soleur tenant).
- [x] **T7.2** Counsel review Privacy Policy → same operator-attested sign-off.
- [x] **T7.3** Counsel review DPD → same operator-attested sign-off.
- [x] **T7.4** CPO sign-off carried forward from #4046 brainstorm + operator confirmation at ship time.
- [x] **T7.5** Moved `compliance-posture.md` Active Items row to Completed Compliance Work entry with 2026-05-19 date and PR #4081 reference.
- [x] **T7.6** Mark PR ready and run `gh pr merge --squash --auto`.

## Post-merge operator runbook (tracked in PR body, not blocking merge)

- [ ] **OP1** In Cloudflare dashboard, expand `cf_api_token_jikigai_com` API token scope from `Zone:DNS:Edit on jikigai.com` to `Zone:DNS:Edit + Zone:Ruleset:Edit on jikigai.com`. Re-paste into Doppler `prd` under the same secret name.
- [ ] **OP2** Run `terraform apply -target=cloudflare_ruleset.jikigai_com_redirects` in `apps/web-platform/infra/`. Follow with untargeted `terraform plan` confirming zero soleur.ai drift.
- [ ] **OP3** Verify redirect: `curl -sI https://jikigai.com/legal/privacy-policy | head -3` returns `301` with `Location: https://soleur.ai/pages/legal/privacy-policy.html`.
- [ ] **OP4** Update LinkedIn Developer app 229658411 privacy-policy URL from `https://soleur.ai/pages/legal/privacy-policy.html` → `https://jikigai.com/legal/privacy-policy`.
- [ ] **OP5** Proceed with Phase 5.4 of parent runbook at `https://www.linkedin.com/help/linkedin/ask/dsapi` (K-bis appeal upload).
