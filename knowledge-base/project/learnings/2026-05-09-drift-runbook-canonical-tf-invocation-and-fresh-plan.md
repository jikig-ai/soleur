---
date: 2026-05-09
problem_type: integration_issue
component: terraform_runbook
module: web-platform
severity: medium
tags: [terraform, drift-remediation, doppler, prd_terraform, runbook-authoring, tf-var]
issue: "#3371"
followup: "#3485"
synced_to: [plan]
---

# Learning: Drift-remediation runbooks must (a) prescribe the canonical Doppler+Terraform invocation triplet AND (b) re-run `terraform plan` against live state before publishing

## Problem

Two distinct gaps surfaced while executing the #3371 ops-remediation runbook (`knowledge-base/project/plans/2026-05-09-fix-terraform-drift-seo-page-redirects-3371-plan.md`). Both came from the same plan author missing patterns documented in the precedent runbook for #3061.

### Gap 1 — Plan prescribed an incomplete `terraform plan` invocation

The plan's Phase 1 prescribed:

```bash
doppler run --project soleur --config prd_terraform -- terraform plan -no-color -input=false
```

Running this produced ~13 immediate `Error: No value for required variable` failures:

```text
Error: No value for required variable
  on variables.tf line 74:
  74: variable "cf_api_token_bot_management" {
The root module input variable "cf_api_token_bot_management" is not set, ...
```

…and the same for `cf_zone_id`, `cf_account_id`, `webhook_deploy_secret`, `doppler_token`, `cf_notification_email`, `resend_api_key`, plus 6 more.

**Cause:** the invocation lacked two pieces that the precedent runbook (`knowledge-base/project/plans/2026-04-30-fix-terraform-drift-deploy-pipeline-fix-3061-plan.md` Phase 1) prescribes:

1. `--name-transformer tf-var` — Doppler's renamer that converts `CF_API_TOKEN` → `TF_VAR_cf_api_token` (the form `terraform` expects). Without it, secrets are loaded under their raw uppercase names and Terraform sees zero `TF_VAR_*` env vars. See the complementary learning `2026-03-21-doppler-tf-var-naming-alignment.md` for *why* the variable names match.
2. Separate `export AWS_ACCESS_KEY_ID=...` / `AWS_SECRET_ACCESS_KEY=...` lines for the R2 backend creds. The `tf-var` transformer would otherwise rewrite them to `TF_VAR_aws_access_key_id` (which Terraform's S3 backend doesn't read). They must be exported as raw `AWS_*` *before* the `doppler run --name-transformer tf-var` wrapper fires.

### Gap 2 — Plan referenced a 3-day-old drift snapshot without re-running `terraform plan` before publishing

The plan was authored on 2026-05-09 referencing the drift-detector output captured at 2026-05-06 19:48 UTC. By apply-time:

- The original target — `cloudflare_ruleset.seo_page_redirects` — was **already in state** with id `68dfde060e28478ebd419926fb1107de`. Some operator had applied it between 2026-05-06 and 2026-05-09. The plan was unaware.
- Two unrelated drifts had accumulated in the meantime:
  - `cloudflare_ruleset.seo_response_headers` — a description-only edit from PR #3378 / commit `556fa567` (`docs(infra): document api.soleur.ai X-Robots-Tag no-op`).
  - `terraform_data.deploy_pipeline_fix` — the recurring `triggers_replace` class identical to #3061 / #2618 / #2881.

The plan's own halt condition (Phase 1 step 4: "if the plan output contains *any* additional `+ / ~ / -` action [...], STOP and file a follow-up triage issue") correctly fired and prevented an out-of-scope apply. But Phase 1 had to be entirely re-scoped at execution time — the runbook itself was no longer a runbook for *the actual current drift*.

## Solution

### For Gap 1 — canonical invocation triplet

Use this exact pattern in any plan whose Phase 1 talks to `apps/web-platform/infra/` via Doppler `prd_terraform`:

```bash
# 1. Export R2 backend creds RAW (name-transformer would otherwise mangle them).
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)

# 2. Init (no name-transformer needed — backend reads AWS_* env vars directly).
terraform init -input=false

# 3. Plan / apply with --name-transformer tf-var so Doppler renames CF_API_TOKEN_RULESETS -> TF_VAR_cf_api_token_rulesets, etc.
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform plan -no-color -input=false
# or
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform apply -auto-approve
```

**Why the `export` happens outside `doppler run`:** the S3 backend (R2-via-S3-API per `apps/web-platform/infra/main.tf:1-15`) reads its creds from the standard AWS env vars during `terraform init`, before any provider config evaluates `var.*`. If you put `AWS_ACCESS_KEY_ID` inside the `doppler run --name-transformer tf-var` wrapper, it becomes `TF_VAR_aws_access_key_id` and the backend silently fails to authenticate.

### For Gap 2 — fresh-plan precondition for drift-remediation runbooks

Before publishing any drift-remediation runbook (i.e., any plan whose Acceptance Criteria asserts an exact `Plan: N to add, M to change, K to destroy` line copied from a drift-detector snapshot), the author MUST run `terraform plan` against live state immediately before publishing. If the live plan diverges from the snapshot:

- If the drift has been resolved in the interim (the original target is now in state): close the parent issue with a verification command (e.g., curl loop, file hash check, systemd unit check) and skip the runbook entirely. There is nothing to apply.
- If new drifts have accumulated: either widen the runbook's scope explicitly (and re-acknowledge per `hr-menu-option-ack-not-prod-write-auth`) or file a follow-up issue for the accumulated drifts and keep the runbook scoped narrowly.

**Why:** drift-detector cron snapshots are read-only artifacts captured at a single instant. The cadence at this repo is `0 6,18 * * *` — up to 12 hours of staleness even on a fast author. Days of staleness are common when triage runs multiple days after the auto-filed issue. The runbook's halt condition catches the divergence at execute time, but at that point Phase 1 has to be re-scoped from scratch, the operator-ack chain is dirty, and the time savings the runbook was supposed to deliver are gone.

## Recovery Used in This Session

1. Stopped after the first `terraform plan` failure. Diagnosed the missing `--name-transformer tf-var` by grep-comparing the #3371 plan's Phase 1 against the #3061 precedent.
2. Re-ran with the canonical invocation triplet. Plan succeeded in <30s and produced `Plan: 1 to add, 1 to change, 1 to destroy`.
3. Diagnosed that the `+1 add` was the destroy/create side of `-/+ terraform_data.deploy_pipeline_fix` (not `cloudflare_ruleset.seo_page_redirects`) by grepping for the target resource in the plan output. Found it only in the "Refreshing state" phase with id `68dfde060e28478ebd419926fb1107de` — already applied.
4. Honored the plan's Phase 1 halt condition and did NOT apply. Filed #3485 covering the two out-of-scope drifts.
5. Verified the original target was live by running the plan's 10-URL curl loop. All 10 paths returned `301 → canonical`. Closed #3371 with the truthful comment.

## Key Insight

Both gaps share a single root cause: the plan author **referenced** the precedent (#3061 runbook) in the enhancement section but did not **execute it** during plan authorship. Specifically:

1. The author cited the precedent's invocation pattern but copy-pasted only the Doppler-config name (`prd_terraform`), not the `--name-transformer tf-var` flag or the AWS export lines.
2. The author cited the drift-detector snapshot but did not run `terraform plan` once at the keyboard before publishing.

The fix isn't to add more rules to AGENTS.md — both gaps are discoverable via clear command-line errors in <30s, so per the discoverability exit in `wg-every-session-error-must-produce-either` they belong in skill instructions, not session-loaded rules. The fix is a precondition checklist baked into `/soleur:plan` (or its terraform-runbook reference): for any plan touching `apps/*/infra/`, the plan-author skill must (a) emit the canonical invocation triplet verbatim, and (b) require a fresh `terraform plan` re-run signal before declaring the runbook complete.

## Session Errors

1. **`gh` GraphQL auth token invalid** during plan-phase research — Recovery: used REST endpoints which still worked. **Prevention:** none warranted; cross-session auth-token health is outside the planning skill's scope and the failure mode is loud.
2. **`WebFetch` returned empty content** for Terraform Registry + Cloudflare docs URLs during plan phase — Recovery: fell back to in-repo precedent (sibling state proof, `.terraform.lock.hcl` pin verification). **Prevention:** the precedent-first heuristic should be the *default*, not a fallback. Add a one-liner to the plan skill's research checklist: "For provider-specific behavior, prefer in-repo precedent (sibling resource state, lock-file pin) over external docs — empirical proof beats provider-doc theory."
3. **`terraform plan` first invocation failed** with 13 `No value for required variable` errors — Recovery: re-ran with `--name-transformer tf-var` + `export AWS_*`. **Prevention:** see Gap 1 above + the proposed plan-skill reference edit (canonical invocation triplet).
4. **Plan was authored against a 3-day-old drift snapshot without re-running `terraform plan`** — Recovery: halted at Phase 1, filed #3485, verified original target was live via curl, closed #3371. **Prevention:** see Gap 2 above + the proposed plan-skill checklist edit (fresh-plan precondition before publishing drift-remediation runbooks).

## References

- Plan executed: `knowledge-base/project/plans/2026-05-09-fix-terraform-drift-seo-page-redirects-3371-plan.md`
- Precedent referenced (and incompletely copied): `knowledge-base/project/plans/2026-04-30-fix-terraform-drift-deploy-pipeline-fix-3061-plan.md`
- Complementary prior learning (the *why* behind tf-var): `knowledge-base/project/learnings/2026-03-21-doppler-tf-var-naming-alignment.md`
- Issue closed: `#3371`
- Follow-up filed: `#3485`
- Related issues for the recurring `triggers_replace` class: `#3061`, `#2881` (closed), `#3043` (open follow-through)
- Hard rules in scope: `hr-menu-option-ack-not-prod-write-auth`, `hr-all-infrastructure-provisioning-servers`, `wg-every-session-error-must-produce-either` (discoverability exit invoked)
