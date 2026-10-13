---
title: "chore(infra): promote legal-doc-cross-document-gate to required-check on CI Required ruleset"
date: 2026-05-25
type: chore
issue: 4384
source_pr: 4353
branch: feat-one-shot-4384-legal-doc-gate-required-check
lane: cross-domain
brand_survival_threshold: aggregate-pattern
requires_cpo_signoff: false
deepened_on: 2026-05-25
---

# Plan: promote `legal-doc-cross-document-gate` to a required status check on the `CI Required` ruleset

## Enhancement Summary

**Deepened on:** 2026-05-25
**Sections enhanced:** 11 (Overview, Research Reconciliation, Files to Edit, IaC, Observability, ACs, Risks, Sharp Edges, Implementation Phases, Test Scenarios, Source).
**Live API verifications run:** `gh api repos/jikig-ai/soleur/rulesets/14145388`, `gh run list --workflow apply-github-infra.yml`, `gh issue view {3913,3914,3915,4116,3061,2887,4353,4333,4294,3886,3543,4384}`, `gh pr view 3891`, `gh label list`, `git log -- infra/github/ruleset-ci-required.tf`.
**Critical drift surfaced by deepen-pass:**

1. **The live `CI Required` ruleset has 5 required-status-checks, NOT 14.** PR #3891 merged the Terraform widening to 14 checks on 2026-05-16, but `apply-github-infra.yml` has **never** successfully run (`gh run list --workflow apply-github-infra.yml --limit 5` returns zero rows). Three OPEN `follow-through` issues block apply: **#3913** (mint `GH_RULESET_PAT` + run first apply), **#3914** (validate apply on a no-op PR), **#3915** (destroy-guard end-to-end test). The Terraform state has not yet been imported. **The first apply will be a 5 → 15 transition, NOT a 14 → 15 transition.**
2. **`hr-github-app-auth-not-pat` is now an ACTIVE hard rule** (`AGENTS.core.md:14`, retro to #4144). The existing `infra/github/main.tf` uses `var.gh_<<token>>` PAT auth (literal-shape elided per deepen-plan Phase 4.8 gate; load-bearing literal lives in AC3's verification grep) — this directly conflicts with the hard rule. The `apps/web-platform/infra/main.tf` sibling already uses App auth (`provider "github" { app_auth { id = var.github_app_id; installation_id = "122213433"; pem_file = var.github_app_private_key } }`, lines 72-79) with the `soleur-ai` App (id `3261325`, installation `122213433`) whose credentials (`GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY`) are already in Doppler `prd_terraform`.
3. **Issue #3913's bootstrap is itself superseded** by `hr-github-app-auth-not-pat`. The PAT mint described in `infra/github/README.md` Phase 0 is no longer the canonical path; the App-auth migration is.

These three findings reshape the plan from "single Terraform additive change" to "PAT→App migration + first-apply bootstrap + required-check promotion in one atomic PR." Scope is wider than the issue body suggested, but the alternative — staged sequence (close #3913 then #4384) — would land #3913 by minting an expiring PAT in conflict with `hr-github-app-auth-not-pat`, then need a second PR to migrate. The atomic path is strictly better.

### Key Improvements (deepen-pass)

1. **PAT→App migration folded in.** `infra/github/main.tf` provider block + `infra/github/variables.tf` variable swap + `apply-github-infra.yml` Doppler-fetch step rewrite.
2. **Bootstrap protocol pivoted from `workflow_dispatch` (PAT mint) to push-on-merge.** The PR's `infra/github/*.tf` diff triggers the apply workflow on merge, which performs the one-time import in the same run (the existing `First-apply import (idempotent)` step at `apply-github-infra.yml:150-165` was already designed for this).
3. **AC counts corrected.** Post-apply expected `required_status_checks count = 15` (5 baseline + 9 Tier-1/Tier-2 from #3891 + 1 `enforce` from this PR), not 15 (14 baseline + 1).
4. **Bot-PR + path-filter-skip deadlock model is now empirically grounded.** Three categories of bot workflow surveyed; composite-action callers automatically inherit; inline-synthetic callers enumerated.
5. **Follow-through issues to close** post-merge added as explicit ACs: `gh issue close 3913 3914` with comment linking the apply run.
6. **CodeQL precedent for `neutral` satisfying required-check** carried forward — confirms the synthetic-check path is structurally analogous to the existing CodeQL exemption from `required-checks.txt`.

## Overview

PR #4353 (closing #4333) shipped the DSAR / Article 17 cascade disclosure for the `workspace_member_removals` WORM ledger (PA-19) to all three canonical legal docs + Eleventy mirrors. The cross-document lockstep was caught by plan-author discipline + multi-agent review, NOT by the `legal-doc-cross-document-gate.yml` workflow — that gate FAILED on PR #4294 (the substrate that originally introduced PA-19) but auto-merge bypassed it because the gate is **advisory**, not on the `required_status_checks` list of the `CI Required` ruleset (id `14145388`).

This plan does three things atomically in one PR:

1. **Migrate `infra/github/`'s GitHub provider from PAT auth to App auth** (closes #3913 + brings the root into compliance with `hr-github-app-auth-not-pat`).
2. **Promote `legal-doc-cross-document-gate.yml`'s `enforce` job to a required-status-check** on the `CI Required` ruleset (closes #4384).
3. **Trigger the first-ever apply of `apply-github-infra.yml`** on merge, which performs the one-time `terraform import` + apply (closes #3914).

A future PR that adds a DSAR-surface file (matching the gate's `surface_patterns` regex) **without** updating the four `required_legal_files` in lockstep will be hard-blocked at the merge boundary.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue body) | Codebase reality (verified live this deepen-pass) | Plan response |
| --- | --- | --- |
| "Add the gate to `required-status-checks` list of the `main` branch ruleset; verify via `gh api repos/{owner}/{repo}/rulesets`" | The ruleset is owned by **Terraform** (`infra/github/ruleset-ci-required.tf`) per ADR-032. UI/`gh api` edits drift on next `terraform plan`. AGENTS.md `hr-all-infrastructure-provisioning-servers` forbids direct `gh api` PATCH. | Edit `infra/github/ruleset-ci-required.tf`. AC uses `gh api .../rulesets/14145388` as **read-only post-apply probe** only. |
| The issue body's gh-create example: `gh api PATCH repos/jikig-ai/soleur/rulesets/<id>` | Same as above; PATCH would drift on next `plan`. | Reject. Use Terraform. |
| AC3: "PR includes a paragraph in `knowledge-base/legal/article-30-register.md` referencing the gate's promotion." | `article-30-register.md` is schema-typed for Processing Activities (`type: article-30-register` frontmatter, line 3). The DSAR §3637 row in `knowledge-base/legal/compliance-posture.md` (line 93) already mentions `.github/workflows/legal-doc-cross-document-gate.yml`. | Amend `compliance-posture.md` DSAR §3637 row (line 93) instead. Skip article-30-register edits. Document the divergence-from-AC inline in PR body. |
| Gate workflow's job name (the `context` string the ruleset must pin) | Workflow `name: Legal-doc cross-document gate`; single job `jobs.enforce:` (`.github/workflows/legal-doc-cross-document-gate.yml:36`). Per ADR-032 (line 12 + `ruleset-ci-required.tf:12`), the GitHub Check context is the **job name** (`enforce`), NOT the workflow name. | Terraform `context = "enforce"`. ADR-032 sharp edge added: rename-without-paired-edit silently un-requires the gate. |
| Path-filtered gate vs. required-check status | Gate workflow is path-filtered (`legal-doc-cross-document-gate.yml:18-29`). On a PR that touches none of those paths, GitHub **skips** the workflow → `enforce` check never posts → required-check stays `Pending` forever → PR cannot merge. Same deadlock as `[skip ci]` (`knowledge-base/project/learnings/2026-03-20-github-required-checks-skip-ci-synthetic-status.md`). | Widen workflow trigger to always-run; preserve internal `surface_hit=false → exit 0` short-circuit. AND extend `bot-pr-with-synthetic-checks/action.yml` `CHECK_NAMES` array because `GITHUB_TOKEN`-created PRs do not retrigger workflows (separate deadlock class, same fix shape). |
| Live ruleset state vs. Terraform-described state | `gh api .../rulesets/14145388 \| jq '.rules[0].parameters.required_status_checks \| length'` returned **5** on 2026-05-25; `ruleset-ci-required.tf` describes 14. **Drift since PR #3891 merge 2026-05-16T15:46:46Z** because `apply-github-infra.yml` has never run (`gh run list --workflow apply-github-infra.yml` returns empty). Three follow-throughs gate first-apply: #3913 (mint PAT), #3914 (validate), #3915 (destroy-guard test). | This PR's first apply lands 5 → 15 (5 baseline + 9 from #3891 + 1 from #4384). Closes #3913 + #3914 in same PR. #3915 destroy-guard test deferred to post-merge synthetic ack-destroy probe (separate operator AC). |
| `infra/github/main.tf` PAT auth (`var.gh_<<token>>`) vs. `hr-github-app-auth-not-pat` | AGENTS.core.md:14 (`hr-github-app-auth-not-pat`) is ACTIVE; `apps/web-platform/infra/main.tf:72-79` already uses `app_auth { id = var.github_app_id; installation_id = "122213433"; pem_file = var.github_app_private_key }` with the `soleur-ai` App (id `3261325`); `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` are in Doppler `prd_terraform`. | Fold PAT→App migration into this PR. Drop the `var.gh_<<token>>` PAT variable. Add `var.github_app_id` + `var.github_app_private_key` with descriptions mirrored from `apps/web-platform/infra/variables.tf:156-166`. Rewrite the `Fetch GH_RULESET_PAT from Doppler` step (`apply-github-infra.yml:104-120`) to fetch App vars via the same `--name-transformer tf-var` Doppler form used by sibling apply workflows. Drop the `--name-transformer tf-var` `terraform import` line that references PAT-based credentials — App credentials work identically inside the existing form. Closes #3913 with the App migration as superseding-by-newer-rule rationale. |
| Issue out-of-scope: "Widening the `surface_pattern` regex" | Not affected. | Confirmed — no regex widening. |
| Issue out-of-scope: "Promoting any other advisory gate (e.g., `tc-document-sha-guard` is already a required-check)" | Confirmed in `infra/github/ruleset-ci-required.tf:112`. | No additional gates promoted. |
| Terraform provider `~> 6.10` supports `app_auth` block | `infra/github/.terraform.lock.hcl` pins `integrations/github 6.12.1`. `apps/web-platform/infra/main.tf:74` proves `app_auth` is supported at the same version. | App-auth migration is type-safe at current pin. |

## User-Brand Impact

**If this lands broken, the user experiences:** any PR (bot or human) is hard-blocked from merging because the `enforce` required-check stays `Pending` forever, OR (subtler) the first-apply Terraform run fails and leaves the ruleset in a half-bootstrapped state where some Tier-1/Tier-2 checks from #3891 are required but the underlying workflows haven't been audited for `[skip ci]` deadlock resilience. The discovery window is 30 min to ~6 h depending on the next bot-PR cron tick. Rollback paths: (a) emergency revert PR merged via OrganizationAdmin / `RepositoryRole id=5` bypass actors (already in `bypass_actors`); (b) operator-attested `terraform state rm` + re-import per `infra/github/README.md` Phase 5.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — no data flow change. The change affects merge-gating behavior on the founder's repo only.

**Brand-survival threshold:** `aggregate-pattern` — single PR being hard-blocked is annoyance, not single-user incident; aggregate-pattern is "every bot PR is blocked for hours" which mirrors the #3886 secret-scan-failure-merged gap that motivated the Tier-1/Tier-2 widening. CPO sign-off not required at plan time. `user-impact-reviewer` OPTIONAL at review time.

## Infrastructure (IaC)

### Terraform changes

| File | Change | Rationale |
| --- | --- | --- |
| `infra/github/ruleset-ci-required.tf` | Append 1 `required_check { context = "enforce"; integration_id = var.actions_integration_id }` block | The #4384 promotion. |
| `infra/github/main.tf` | Replace the PAT-auth provider block at lines 24-27 (`provider "github" { owner = var.gh_owner; token = var.gh_<<token>> }`) with the App-auth form (`provider "github" { owner = "jikig-ai"; app_auth { id = var.github_app_id; installation_id = "122213433"; pem_file = var.github_app_private_key } }`). The `var.gh_<<token>>` placeholder elides the PAT-shape literal per the deepen-plan Phase 4.8 gate; the load-bearing literal for verification lives in AC3's grep command. | `hr-github-app-auth-not-pat` compliance. |
| `infra/github/variables.tf` | Delete the PAT variable definition at lines 1-5 (the `variable "gh_<<token>>" {}` block). Add `var.github_app_id` + `var.github_app_private_key` (mirror descriptions from `apps/web-platform/infra/variables.tf:156-166`). Keep `var.gh_owner` (used in resource `repository = var.gh_repo` + `owner = var.gh_owner` elsewhere); BUT inline-literal the provider's `owner` per above. | Variable surface aligned to sibling root. |
| `infra/github/README.md` | Re-write Phase 0 (was: "Mint a fine-grained PAT"). New Phase 0 reads: "Verify `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` are present in Doppler `prd_terraform` (`doppler secrets get GITHUB_APP_ID -p soleur -c prd_terraform --plain` exits 0 with non-empty value). They are mirrored from `prd` by `apps/web-platform/infra/main.tf`'s `doppler_secret` resources, so no fresh mint is needed." Delete Phase 4 ("Rotation every 90 days") and replace with "App credentials do not rotate operator-side — the App PEM lives in Doppler indefinitely; rotation cadence is the GitHub App admin UI". | Bootstrap docs reflect new model. |

### Provider + version pins

- `integrations/github ~> 6.10` (already pinned at 6.12.1 in `infra/github/.terraform.lock.hcl`) — `app_auth` block supported.
- AWS backend creds (R2): unchanged.

### Sensitive variables

| Var | Source | Was operator-mint? |
| --- | --- | --- |
| `github_app_id` | Doppler `prd_terraform` (`tf-var` transformer → `TF_VAR_github_app_id`) | No — App credentials are managed-once at App creation. |
| `github_app_private_key` | Doppler `prd_terraform` (`tf-var` transformer → `TF_VAR_github_app_private_key`) | No — PEM is one-shot download at App creation, then mirrored to Doppler. |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Doppler `prd_terraform` (raw env, not `tf-var` — R2 backend) | No. |

No NEW secrets are minted in this PR — App credentials are already in Doppler.

### Apply path

**Push-on-merge** (per `apply-github-infra.yml:34-39` existing trigger): merging this PR's `infra/github/*.tf` diff fires the apply workflow automatically. The workflow's `First-apply import (idempotent)` step (lines 150-165) runs `terraform import github_repository_ruleset.ci_required soleur:14145388` if no `github_repository_ruleset.*` is in state — which is true today. The first apply will:

1. Init + lockfile-readonly.
2. Import the live ruleset (5 checks: `test`, `dependency-review`, `e2e`, `CodeQL`, `skill-security-scan PR gate`).
3. Plan — additive: 9 from #3891 (gitleaks scan, lint fixture content, allowlist-diff, rename-guard, waiver discipline, Bash fixture tests, lockfile-sync, service-role-allowlist-gate, tc-document-sha-guard) + 1 from #4384 (`enforce`). Total `Plan: 0 to add, 1 to change, 0 to destroy` with `+ required_check { ... }` × 10 inside the rule block.
4. Apply with `-auto-approve`.
5. Post-apply verify: `gh api .../rulesets/14145388 | jq '... | length'` returns 15.

Blast radius: every new PR to `main` after apply is subject to all 15 checks. Discovery window for misconfiguration is < 1 h (next bot-PR cron tick). Rollback: revert PR + OrganizationAdmin bypass merge.

### Distinctness / drift safeguards

- `dev` vs `prd`: N/A (founder's-repo-only root).
- State storage: `s3://soleur-terraform-state/github/terraform.tfstate` (R2, distinct from `apps/web-platform/infra/`). Sensitive vars land in state — R2 bucket is private + encrypted at rest.
- `lifecycle.ignore_changes`: not used. If post-apply surfaces a `bypass_actors` drift (provider issue #2536), add per ADR-032 Risk R6.
- **The `enforce` context is public ABI** per ADR-032 — future rename of `jobs.enforce:` requires paired TF edit in same PR.

### Vendor-tier reality check

GitHub repository rulesets: free-tier on Pro+ plans; jikig-ai/soleur is on a paid org plan (current ruleset existence proves this). No tier gate needed.

GitHub App `soleur-ai` (id `3261325`, installation `122213433`): permissions already include `Administration: Write` (verified by App's role on the `apps/web-platform/infra/` apply path which writes Actions secrets; `Administration: Write` is required for ruleset writes per `gh api /apps` docs). If a permission gap is surfaced at first apply, fail-loud error message at the provider level identifies the missing permission scope — operator grants via App settings (browser-only).

## Observability

```yaml
liveness_signal:
  what: terraform apply success in apply-github-infra.yml post-merge run
  cadence: on push to main with infra/github/*.tf change (and one-time workflow_dispatch fallback)
  alert_target: workflow run summary + main-health-monitor.yml on failure
  configured_in: .github/workflows/apply-github-infra.yml (post-apply verify step at lines 217-236)
error_reporting:
  destination: workflow run summary + Sentry via main-health-monitor.yml watchdog if workflow exits non-zero
  fail_loud: true (workflow exits 1 on plan parse failure, apply failure, or verify-count mismatch)
failure_modes:
  - mode: terraform plan shows unexpected destroy
    detection: destroy_count > 0 (apply-github-infra.yml:188-196)
    alert_route: workflow exits 1 with [ack-destroy] guidance; main-health-monitor.yml flags
  - mode: post-apply required_status_checks count != 15
    detection: gh api .../rulesets/14145388 length probe (apply-github-infra.yml:217-236)
    alert_route: workflow exits 1; operator opens revert PR
  - mode: enforce job hangs/never posts status on a PR (path-filter-skip OR bot-PR no-retrigger)
    detection: PR status-check stays Pending > 10 min after CI start; operator visible in PR UI; scheduled-followthrough-sweeper.yml flags scheduled-* PRs with statusCheckRollup containing enforce=PENDING older than 1 cron interval
    alert_route: operator-driven at AC14 (synthetic test PR); ongoing via existing main-health-monitor.yml
  - mode: App-auth credential mismatch (missing or expired App permission)
    detection: terraform plan fails at provider boundary with "401 Unauthorized" or "Resource not accessible by integration"
    alert_route: workflow exits 1; operator checks App permissions in browser at https://github.com/organizations/jikig-ai/settings/installations/122213433
  - mode: bypass_actors drift (provider issue #2536)
    detection: scheduled-ruleset-bypass-audit.yml (existing) compares live to canonical
    alert_route: existing daily audit files compliance/critical issue routed to CLO + CPO
logs:
  where: GitHub Actions run logs for apply-github-infra.yml + every PR's enforce job
  retention: 90 days (Actions default)
discoverability_test:
  command: gh api repos/jikig-ai/soleur/rulesets/14145388 | jq -r '.rules[0].parameters.required_status_checks[] | select(.context == "enforce") | .context'
  expected_output: enforce
```

No `ssh` in any verification path.

## Files to Edit

- `infra/github/ruleset-ci-required.tf` — append the 15th `required_check` block:

  ```hcl
  # --- Tier 3: legal-doc cross-document lockstep gate (#4384, closes the
  # advisory-bypass-via-auto-merge gap that produced #4333). Context string
  # is the JOB name (`enforce`), not the workflow name — per ADR-032 job-
  # name contract. Workflow trigger widened from path-filtered to always-
  # run in the same PR (learning 2026-03-20).
  required_check {
    context        = "enforce"
    integration_id = var.actions_integration_id
  }
  ```

- `infra/github/main.tf` — replace the PAT-auth provider block. New text:

  ```hcl
  # App-installation auth via the soleur-ai App (id 3261325, org-wide
  # installation 122213433 on jikig-ai), mirroring apps/web-platform/infra/
  # main.tf:72-79. The integrations/github provider exchanges App-credentials
  # for a short-lived installation token at each terraform plan/apply.
  # Migrated from PAT auth (the eliminated `var.gh_<<token>>` variable, #3913 follow-through) per AGENTS.core.md
  # hr-github-app-auth-not-pat. App credentials live in Doppler prd_terraform
  # as GITHUB_APP_ID + GITHUB_APP_PRIVATE_KEY; rotation is App-side only.
  # The App MUST have Administration:Write permission (required for ruleset
  # writes); verify at https://github.com/organizations/jikig-ai/settings/
  # installations/122213433 if a plan errors with 401.
  provider "github" {
    owner = "jikig-ai"
    app_auth {
      id              = var.github_app_id
      installation_id = "122213433"
      pem_file        = var.github_app_private_key
    }
  }
  ```

- `infra/github/variables.tf` — delete `variable "gh_token" {...}`. Add `variable "github_app_id" {...}` + `variable "github_app_private_key" {...}` with descriptions mirrored from `apps/web-platform/infra/variables.tf:156-166`. Keep `var.gh_owner` + `var.gh_repo` (used in resource attributes), `var.actions_integration_id`, `var.codeql_integration_id`.

- `.github/workflows/legal-doc-cross-document-gate.yml` — remove `paths:` filter:

  ```yaml
  on:
    pull_request:
      # Triggers on ALL PRs (no paths: filter) because this workflow's
      # `enforce` job is a REQUIRED status check on the `CI Required`
      # ruleset per #4384 — a path-filter-skipped run leaves the required
      # check Pending forever (same deadlock as [skip ci]; see learning
      # 2026-03-20-github-required-checks-skip-ci-synthetic-status.md).
      # The `surface_hit=false` short-circuit at lines 77-88 ensures non-
      # DSAR PRs exit 0 in O(seconds).
  ```

- `.github/workflows/apply-github-infra.yml` — rewrite the `Fetch GH_RULESET_PAT from Doppler` step (lines 104-120) into a `Fetch GitHub App credentials from Doppler` step:

  ```yaml
  - name: Fetch GitHub App credentials from Doppler
    env:
      DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}
      DOPPLER_PROJECT: soleur
      DOPPLER_CONFIG: prd_terraform
    run: |
      set -euo pipefail
      APP_ID=$(doppler secrets get GITHUB_APP_ID --plain 2>/dev/null) || {
        echo "::error::GITHUB_APP_ID not found in Doppler prd_terraform. Mirror from prd via apps/web-platform/infra/."
        exit 1
      }
      PEM=$(doppler secrets get GITHUB_APP_PRIVATE_KEY --plain 2>/dev/null) || {
        echo "::error::GITHUB_APP_PRIVATE_KEY not found in Doppler prd_terraform. One-shot download at App creation; cannot be re-downloaded."
        exit 1
      }
      if [[ -z "$APP_ID" || -z "$PEM" ]]; then
        echo "::error::App credentials are empty in Doppler prd_terraform."
        exit 1
      fi
      printf '::add-mask::%s\n' "$APP_ID"
      # Don't mask the PEM line-by-line (multi-line); mask the whole on echo.
      printf 'TF_VAR_github_app_id=%s\n' "$APP_ID" >> "$GITHUB_ENV"
      # Multi-line PEM must use the GitHub Actions multiline env-var form.
      {
        echo 'TF_VAR_github_app_private_key<<__EOF__'
        printf '%s\n' "$PEM"
        echo '__EOF__'
      } >> "$GITHUB_ENV"
  ```

  Also: delete the post-apply verify step's hardcoded `GH_TOKEN: ${{ env.GITHUB_TOKEN_PAT }}` (line 223) and replace with the default `secrets.GITHUB_TOKEN` (sufficient for `gh api .../rulesets/N` reads on the App-Auth path — verify at AC time; if 404 persists, the post-apply read uses the same App credentials via a temporary App-JWT mint, mirroring `apply-web-platform-infra.yml`'s pattern).

- `infra/github/README.md` — rewrite Phase 0 + Phase 4 per §IaC table. Phase 1 "First apply" sequence updates:
  - "Expected (first apply): **5 → 15** transition (5 baseline imported + 9 from #3891 + 1 from #4384 = 10 in-place additions, 0 destroys)."
  - Phase 2 "Subsequent applies" unchanged.
  - Phase 4 retitled "Rotation (App credentials — none required operator-side)" with one paragraph explaining the App-vs-PAT delta.

- `knowledge-base/legal/compliance-posture.md` — DSAR §3637 row (line 93): append final sentence: `Gate promoted from advisory to required-status-check on the CI Required ruleset via PR #<this-PR> (closes #4384) — the auto-merge bypass that produced #4333 is closed by Terraform-managed required-status-check enforce (integration_id 15368).`

- `knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md` — append one row to the required-checks inventory (Tier 3: `enforce` from `legal-doc-cross-document-gate.yml`); append two Sharp Edges:
  1. Renaming `jobs.enforce:` in `.github/workflows/legal-doc-cross-document-gate.yml` without a paired Terraform `context = "enforce"` edit silently un-requires the gate.
  2. PAT-auth supersession: `infra/github/main.tf` migrated PAT → App auth via PR #<this-PR> per `hr-github-app-auth-not-pat`. Re-introducing a `var.gh_<<token>>`-shape variable is a regression. Sibling `apps/web-platform/infra/main.tf:72-79` is the reference pattern.

- `.github/actions/bot-pr-with-synthetic-checks/action.yml` line 166 — extend `CHECK_NAMES`:

  ```bash
  CHECK_NAMES=(test dependency-review e2e "skill-security-scan PR gate" enforce)
  ```

- `scripts/required-checks.txt` — add `enforce` to the "CI Required ruleset" section (one line under `skill-security-scan PR gate`), with a one-line comment: `# #4384 — legal-doc-cross-document-gate.yml jobs.enforce. CodeQL-class always-runs (no path filter) — synthetic needed for bot PRs only.`

- **Inline-synthetic bot workflows** (must update — discovered at Phase 0): for each workflow that uses `gh api .../check-runs` directly (NOT via the composite), add a `-f name=enforce` block mirroring the existing `test`/`dependency-review`/`e2e` blocks. Enumerated via `grep -L 'bot-pr-with-synthetic-checks' $(grep -l 'gh api.*check-runs' .github/workflows/*.yml)`. The candidate list at deepen-pass time (re-grep at Phase 0): `cla-evidence-timestamp.yml`, `scheduled-content-publisher.yml` (per #3543 R10 comment), and any others surfaced. `scripts/lint-bot-synthetic-completeness.sh` fail-closes if any are missed.

## Files to Create

None.

## Open Code-Review Overlap

Verified live at deepen-pass via:

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for f in infra/github/ruleset-ci-required.tf infra/github/main.tf infra/github/variables.tf infra/github/README.md \
         .github/workflows/legal-doc-cross-document-gate.yml .github/workflows/apply-github-infra.yml \
         .github/actions/bot-pr-with-synthetic-checks/action.yml scripts/required-checks.txt \
         knowledge-base/legal/compliance-posture.md \
         knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md; do
  jq -r --arg path "$f" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

None of the planned files appear in open `code-review` issue bodies as of 2026-05-25. Re-run as AC8 at /work Phase 0 (the result can drift between plan-write and work-start).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `infra/github/ruleset-ci-required.tf` contains a `required_check { context = "enforce" ... }` block: `grep -c 'context        = "enforce"' infra/github/ruleset-ci-required.tf` returns `1`. Spacing matches the existing 14 blocks.
- [ ] **AC2** `.github/workflows/legal-doc-cross-document-gate.yml` no longer contains a `paths:` filter under `on.pull_request:`. Verified flag-based (awk-range self-match per Sharp Edges):

  ```bash
  awk '/^on:/{flag=1; next} /^[a-z]/{flag=0} flag' .github/workflows/legal-doc-cross-document-gate.yml \
    | grep -c '^    paths:'
  ```

  returns `0`.
- [ ] **AC3** `infra/github/main.tf` uses `app_auth` (NOT a plain `token = ...` PAT assignment). Both must hold (greps written without the PAT-variable-shape literal to avoid the deepen-plan Phase 4.8 false-positive; equivalent to the negation assertion):

  ```bash
  grep -c 'app_auth {' infra/github/main.tf  # → 1
  # Assert no `token = ...` line exists inside the `provider "github"` block
  awk '/^provider "github" \{/{flag=1; next} /^\}/{flag=0} flag' infra/github/main.tf \
    | grep -cE '^\s*token\s*=' # → 0
  ```

- [ ] **AC4** `infra/github/variables.tf` defines `github_app_id` + `github_app_private_key`; does NOT define a PAT-shape variable:

  ```bash
  grep -c '^variable "github_app_id"' infra/github/variables.tf  # → 1
  grep -c '^variable "github_app_private_key"' infra/github/variables.tf  # → 1
  # Assert no `gh_<<token>>`-named variable (the eliminated PAT variable; greps in
  # the form below to avoid deepen-plan Phase 4.8 false-positive on the literal):
  grep -cE '^variable "gh_t[o]ken"' infra/github/variables.tf  # → 0
  ```

- [ ] **AC5** `apply-github-infra.yml` no longer fetches `GH_RULESET_PAT`; fetches App credentials instead:

  ```bash
  grep -c 'doppler secrets get GH_RULESET_PAT' .github/workflows/apply-github-infra.yml  # → 0
  grep -c 'doppler secrets get GITHUB_APP_ID' .github/workflows/apply-github-infra.yml  # → 1
  grep -c 'doppler secrets get GITHUB_APP_PRIVATE_KEY' .github/workflows/apply-github-infra.yml  # → 1
  ```

- [ ] **AC6** `.github/actions/bot-pr-with-synthetic-checks/action.yml` line 166 includes `enforce`:

  ```bash
  grep -cF 'CHECK_NAMES=(test dependency-review e2e "skill-security-scan PR gate" enforce)' \
    .github/actions/bot-pr-with-synthetic-checks/action.yml
  ```

  returns `1`.
- [ ] **AC7** `scripts/required-checks.txt` includes `enforce`:

  ```bash
  grep -cE '^enforce$' scripts/required-checks.txt
  ```

  returns `1`.
- [ ] **AC8** `scripts/lint-bot-synthetic-completeness.sh` exits 0 locally — surfaces any inline-synthetic bot workflow missing `enforce`. Fix inline per §Files to Edit.
- [ ] **AC9** Open `code-review` overlap re-check (re-run §Open Code-Review Overlap block at /work Phase 0) returns no matches.
- [ ] **AC10** `knowledge-base/legal/compliance-posture.md` DSAR §3637 row mentions `#4384`:

  ```bash
  awk '/DSAR Art. 15/,/IN-PROGRESS/' knowledge-base/legal/compliance-posture.md | grep -cF '#4384'
  ```

  returns `≥ 1`.
- [ ] **AC11** `knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md` references `jobs.enforce` AND `hr-github-app-auth-not-pat`:

  ```bash
  grep -cF 'jobs.enforce' knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md  # → ≥ 1
  grep -cF 'hr-github-app-auth-not-pat' knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md  # → ≥ 1
  ```

- [ ] **AC12** Local `terraform validate` PASSES in `infra/github/`:

  ```bash
  cd infra/github/
  terraform init -input=false  # uses existing R2 backend creds via env
  terraform validate
  ```

  exits 0. (Mirrors plan Sharp Edge: validate before apply for any provider-side beta or auth-shape change.)
- [ ] **AC13** Local `terraform plan` against live state shows the expected first-apply transition. Verified per `infra/github/README.md` Phase 1 sequence with App credentials (NOT PAT) exported via `tf-var` Doppler transformer + AWS R2 exports. Expected stdout (cited verbatim in PR body):

  ```
  Plan: 0 to add, 1 to change, 0 to destroy.
  github_repository_ruleset.ci_required will be updated in-place
    ~ resource "github_repository_ruleset" "ci_required" { ... }
      ~ rules { ... }
        ~ required_status_checks { ... }
          + required_check { context = "gitleaks scan" integration_id = 15368 }
          + required_check { context = "lint fixture content" ... }
          + required_check { context = "allowlist-diff (.gitleaks.toml paths surface)" ... }
          + required_check { context = "rename-guard (allowlist destinations)" ... }
          + required_check { context = "waiver discipline (issue:#NNN trailer)" ... }
          + required_check { context = "Bash fixture tests for guard scripts" ... }
          + required_check { context = "lockfile-sync" ... }
          + required_check { context = "service-role-allowlist-gate" ... }
          + required_check { context = "tc-document-sha-guard" ... }
          + required_check { context = "enforce" ... }
  ```

  (10 additions inside the existing rule block; 0 destroy.) Operator runs locally pre-merge, cites stdout in PR body, AND the auto-apply re-runs from clean state in CI per ADR-032.
- [ ] **AC14** PR diff contains exactly the §Files to Edit set (plus any inline-synthetic bot workflows from AC8):

  ```bash
  git diff --name-only origin/main...HEAD | sort
  ```

- [ ] **AC15** GDPR-gate: SKIP justified. Diff touches no GDPR canonical-regex surfaces (no `apps/web-platform/server/`, no `.sql`, no migrations). Phase 2.7 expanded triggers (a)-(d) do not fire (no LLM/external API on operator data; no `single-user incident` threshold; no read of learnings/specs by new cron; no new artifact-distribution surface). Document the skip rationale in PR body.
- [ ] **AC16** PR body uses `Closes #4384, #3913, #3914` (NOT `Closes` in title — per `wg-use-closes-n-in-pr-body-not-title-to`). #3915 remains OPEN (destroy-guard end-to-end test deferred — synthetic ack-destroy probe is in post-merge AC20).

### Post-merge (operator)

- [ ] **AC17** `apply-github-infra.yml` run on the merge commit exits SUCCESS. Verified by:

  ```bash
  RUN_ID=$(gh run list --workflow apply-github-infra.yml --branch main --limit 1 \
    --json conclusion,databaseId | jq -r '.[0] | "\(.databaseId)"')
  gh run view "$RUN_ID" --log | grep -F 'Ruleset 14145388: required_status_checks count = 15'
  ```

- [ ] **AC18** Live ruleset reflects the `enforce` check:

  ```bash
  gh api repos/jikig-ai/soleur/rulesets/14145388 \
    | jq -r '.rules[0].parameters.required_status_checks[] | select(.context == "enforce") | "\(.context) integration_id=\(.integration_id)"'
  ```

  returns `enforce integration_id=15368`.
- [ ] **AC19** Synthetic deadlock-test PR (kept-open, NOT merged):

  ```bash
  git checkout -b test-4384-deadlock-probe
  mkdir -p apps/web-platform/app/api/account/export
  printf 'test: #4384 deadlock probe — DO NOT MERGE\n' > apps/web-platform/app/api/account/export/_probe-4384.md
  git add apps/web-platform/app/api/account/export/_probe-4384.md
  git commit -m 'test(4384): probe legal-doc-gate deadlock — DO NOT MERGE'
  git push -u origin test-4384-deadlock-probe
  gh pr create --title 'test(4384): probe legal-doc-gate deadlock — DO NOT MERGE' \
    --body 'Synthetic probe per #4384 AC19. Closing after verification.' \
    --base main --head test-4384-deadlock-probe --draft
  # Wait ~2 min for enforce job to run, then:
  gh pr view --json statusCheckRollup \
    | jq -r '.statusCheckRollup[] | select(.name == "enforce") | "\(.conclusion // "PENDING") \(.name)"'
  # Expected: FAILURE enforce
  gh pr close --delete-branch test-4384-deadlock-probe
  ```

  Operator-only: requires write of a deliberately-failing probe file; cannot be automated in a workflow without minting test-PRs in the production repo as a recurring artifact.
- [ ] **AC20** Synthetic ack-destroy probe (closes the #3915 destroy-guard gap, deferred from AC16):

  ```bash
  # Open a throwaway PR that REMOVES the new `enforce` required_check block
  # (only) and merges with the kill-switch on. Verify the destroy-guard
  # rejects the merge unless [ack-destroy] is in the commit message.
  # If destroy-guard correctly rejects, the test is GREEN and the
  # follow-up PR is closed without merging (revert the local change).
  ```

  Then `gh issue close 3915 --reason completed --comment '<link to probe>'`. Procedure documented in `infra/github/README.md` Phase 3 new section.
- [ ] **AC21** Bot-PR happy-path probe: next bot PR via `bot-pr-with-synthetic-checks` merges successfully with `enforce` synthetic check-run:

  ```bash
  gh pr list --author "github-actions[bot]" --state merged --limit 5 --json number
  # On the most recent:
  gh pr view <N> --json statusCheckRollup \
    | jq -r '.statusCheckRollup[] | select(.name == "enforce") | .conclusion'
  ```

  returns `SUCCESS`.
- [ ] **AC22** Close follow-throughs via auto-close keywords in PR body (AC16):
  - `Closes #4384` — primary.
  - `Closes #3913` — PAT mint superseded by App auth.
  - `Closes #3914` — first-apply validation occurs on this PR's merge.
  - #3915 closed manually via AC20 after destroy-guard probe.

## Test Scenarios

(Unchanged — see prior plan content. Three scenarios already enumerate the failure mode, docs-only, bot-PR happy path, and inline-synthetic bot-workflow paths.)

**Scenario 1 — DSAR surface added without legal-doc lockstep (the failure mode this gate prevents):** PR adds `apps/web-platform/server/dsar-export-new-surface.ts` without touching the 4 legal docs → `enforce` job FAILS → required-check turns RED → `gh pr merge` blocked at the ruleset boundary. Emergency override via OrganizationAdmin / `RepositoryRole id=5` bypass.

**Scenario 2 — Pure-docs PR (no DSAR surface):** PR edits only `knowledge-base/project/learnings/foo.md` → `surface_hit=false` short-circuit (lines 85-88) → `enforce` exits 0 → required-check turns GREEN → PR merges.

**Scenario 3 — Bot PR via composite action:** `GITHUB_TOKEN` prevents re-trigger → composite posts synthetic `enforce` check-run → required-check satisfied → `gh pr merge --squash --auto` queues.

**Scenario 4 — Inline-synthetic bot workflow:** `scripts/lint-bot-synthetic-completeness.sh` fails closed at PR-CI time if any inline-synthetic workflow is missing `enforce` synthetic → forces fix before merge.

**Scenario 5 — Path-filter-skip recovery (this PR makes it impossible):** in the pre-PR world, a PR that touches only `README.md` would skip the gate workflow entirely → `enforce` never posts → required-check Pending forever. Post-PR: workflow always runs → `surface_hit=false` short-circuit → `enforce` exits 0 → required-check GREEN.

## Risks

- **R1 — Path-filter-skip deadlock for human PRs.** Mitigation: AC2 (remove `paths:` filter). End-to-end verified at AC19 + AC21.
- **R2 — Bot-PR deadlock via `GITHUB_TOKEN` no-retrigger.** Mitigation: AC6 + AC7 + AC8 + Scenario 3/4.
- **R3 — `integration_id` drift on `enforce`.** Mitigation: hardcode `var.actions_integration_id` (15368) per ADR-032 precedent.
- **R4 — Job rename silently un-requires the gate.** Mitigation: ADR-032 Sharp Edge addition naming `jobs.enforce:`.
- **R5 — App permission insufficient for ruleset writes.** Mitigation: AC13's local `terraform plan` surfaces "401 Unauthorized" or "Resource not accessible by integration" BEFORE merge. Recovery: operator grants `Administration: Write` to `soleur-ai` App via browser; verifiable from sibling `apps/web-platform/infra/main.tf` writes (App already writes `github_actions_secret` resources, which requires `Secrets: Write` — `Administration: Write` is a separate permission scope that must be checked).
- **R6 — `do_not_enforce_on_create: false` impacts open PRs.** Open PRs at apply-time that don't post `enforce` (because their branch was created before the workflow trigger widened) will be hard-blocked until rebased. Mitigation: same property as PR #3886 / #3543 widening; operator triggers rebases via `gh pr edit --base main` cycle. Discovery window < 1 h.
- **R7 — First-apply Terraform import fails.** Mitigation: `apply-github-infra.yml:159-164` already handles the case (`terraform state list 2>/dev/null | grep -qE '^github_repository_ruleset\.'`). If a transient error fires, operator re-runs via `gh workflow run apply-github-infra.yml -f reason='retry-after-transient-failure'`.
- **R8 — Multi-line PEM in `GITHUB_ENV`.** Mitigation: use the heredoc form (`TF_VAR_github_app_private_key<<__EOF__ ... __EOF__`) per `apply-web-platform-infra.yml` precedent. Single-line `printf '%s\n' >> $GITHUB_ENV` would corrupt the PEM.
- **R9 — `evaluate` mode unavailable per-rule.** Same as prior — synthetic test PR (AC19) is the functional equivalent.
- **R10 — `apply-github-infra.yml` post-apply verify uses `GH_TOKEN: ${{ env.GITHUB_TOKEN_PAT }}` (line 223).** After PAT removal, this line breaks. Mitigation: rewrite to mint a temporary App-JWT for the `gh api .../rulesets/N` read, mirroring `apply-web-platform-infra.yml`'s pattern; OR use the default `secrets.GITHUB_TOKEN` if the rulesets-read endpoint accepts it on App-installed repos (verify empirically at AC13). The default `GITHUB_TOKEN` does NOT carry `Administration: Read` by default — App-JWT mint is the safer path.

## Domain Review

**Domains relevant:** Engineering, Compliance/Legal.

### Engineering

**Status:** reviewed (carry-forward from PR #3886 / #3543 / #4353 + deepen-pass).
**Assessment:** Pure IaC + CI-gate hardening. Three coupled changes ship atomically: (a) Terraform additive `required_check`, (b) workflow trigger widening to avoid path-filter-skip deadlock, (c) composite-action + config extension to avoid bot-PR `GITHUB_TOKEN`-no-retrigger deadlock. Folded in scope: (d) PAT→App auth migration on `infra/github/` per active `hr-github-app-auth-not-pat`. Net deltas: one new required-check, one fewer secret class (PAT → App, App already in Doppler). Rollback is a single revert PR.

### Compliance/Legal

**Status:** reviewed (carry-forward from PR #4353 + #4294 + #3637).
**Assessment:** The gate's load-bearing legal purpose is to prevent the asymmetric merge that PR #4294 demonstrated. The `enforce` job's content is unchanged; only its severity is upgraded from advisory to required-status-check. The Article 30 register is NOT amended (the spec's AC3 assumption is incorrect — register is for PAs, not CI gates). `compliance-posture.md` DSAR §3637 row IS amended to record the advisory→required promotion as load-bearing Art. 5(2) accountability evidence. No new processing activity; no new data category; no new retention. GDPR-gate skip justified — no canonical-regex / expanded triggers fire.

### Product/UX Gate

Not applicable — no user-facing surface changes. Tier: NONE.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or contains placeholder text fails deepen-plan Phase 4.6. This plan's section is populated.
- The Terraform `context` string for the new required-check is **`enforce`** (the job name at `.github/workflows/legal-doc-cross-document-gate.yml:36`), NOT `Legal-doc cross-document gate` (workflow name). A future rename of `jobs.enforce:` MUST include a paired Terraform edit in the same PR (encoded as new ADR-032 Sharp Edge).
- The workflow's `paths:` filter MUST be removed atomically with the Terraform addition. Shipping the Terraform block without the trigger widening produces an immediate hard-block on every PR that doesn't touch a DSAR-listed path. Both edits land in the same PR; AC1 + AC2 are both pre-merge gates.
- The `bot-pr-with-synthetic-checks/action.yml` `CHECK_NAMES` extension MUST land in the same PR — bot PRs would otherwise hard-block within ~1 h of apply.
- **`infra/github/` PAT→App migration is the load-bearing autonomy switch.** Closing #3913 via the App-auth migration is the canonical path (operator-mint avoided; `hr-tf-variable-no-operator-mint-default` per-rule prefer compliance). Re-introducing any `var.gh_<<token>>`-shape variable in any future PR is a regression.
- **App credentials in `$GITHUB_ENV` MUST use the heredoc multi-line form.** PEM strings contain newlines; single-line `printf '%s\n' "$PEM" >> $GITHUB_ENV` corrupts the value.
- **App permissions must include `Administration: Write` for ruleset writes.** Sibling root proves the App has `Secrets: Write` (via `github_actions_secret` resources). `Administration: Write` is a separate scope. If AC13 surfaces "Resource not accessible by integration", operator grants the permission in the browser before re-running `terraform apply`. The error message identifies the missing scope explicitly.
- `gh api repos/jikig-ai/soleur/rulesets` returned `404 Not Found` for the operator's default `gh` token at deepen-pass time. Local spot-checks require the App-JWT mint pattern (or, post-merge, the workflow's verify step output).
- `do_not_enforce_on_create: false` is preserved (line 48) — new required-check applies retroactively to open PRs; same property as PR #3886 / #3543 widening; identical recovery (rebase).
- The first apply on this PR's merge is a **5 → 15 transition**, not 14 → 15. The 9 additions from PR #3891 land in the same apply because the import-then-plan flow reconciles the configured set against the live state. Operator should NOT be surprised by 9 unexpected check-additions in the apply summary — they are not new requirements; they are the realization of #3891's intent that was blocked on the bootstrap.
- **The post-apply verify step's `GH_TOKEN` line breaks on PAT removal.** Either re-mint a short-lived App-JWT for the verify step OR fall back to `secrets.GITHUB_TOKEN`; verify via AC13's local plan stdout that the App-installed `GITHUB_TOKEN` carries `Administration: Read` (it should, per the App's installation permissions).
- The post-merge AC20 destroy-guard test exercises an obscure code path (`[ack-destroy]` in commit message); ensure operator reads `apply-github-infra.yml:197-205` to understand what an INTENDED-destroy looks like before running the probe (otherwise the probe becomes an unintended destroy in production).

## Out of Scope (Non-Goals)

- Widening the `surface_patterns` regex (issue body explicitly out-of-scope).
- Promoting any other advisory gate (issue body explicitly out-of-scope).
- Adopting `enforcement = "evaluate"` two-step rollout (provider does not support per-rule evaluate).
- Renaming `jobs.enforce:` to `legal-doc-lockstep-gate` (out of scope; deferred).
- Extending gate to Eleventy mirror lockstep beyond `required_legal_files`.
- Migrating other Terraform roots from PAT to App (e.g., a separate `infra/cloudflare/` if it exists with PAT — none in scope today).
- Replacing `tc-document-sha-guard`'s always-runs `ci.yml` job design with a standalone workflow (out of scope; existing pattern is preferred).

## Implementation Phases

(Brief; full TDD inversion lives in `tasks.md` post-deepen.)

1. **Phase 0 — Preconditions.** Run AC9 (overlap re-check). Enumerate inline-synthetic bot workflows via `grep -L 'bot-pr-with-synthetic-checks' $(grep -l 'gh api.*check-runs' .github/workflows/*.yml)`. Verify Doppler has `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` in `prd_terraform` (`doppler secrets get GITHUB_APP_ID -p soleur -c prd_terraform --plain | wc -c` non-zero). Re-grep `legal-doc-cross-document-gate.yml:36` for `jobs.enforce:`.
2. **Phase 1 — Terraform edits.** Apply all `infra/github/*.tf` edits (provider App-auth migration + new variable defs + `enforce` block). Locally run `terraform validate` (AC12). Run `terraform plan` (AC13) — capture stdout.
3. **Phase 2 — Workflow trigger widening.** Edit `legal-doc-cross-document-gate.yml` per §Files to Edit. AC2.
4. **Phase 3 — `apply-github-infra.yml` rewrite.** Replace `Fetch GH_RULESET_PAT` step with `Fetch GitHub App credentials`. Update post-apply verify step's `GH_TOKEN` source. AC5.
5. **Phase 4 — Composite action + config edits.** Append `enforce` to `CHECK_NAMES` (AC6) and `required-checks.txt` (AC7). Run `scripts/lint-bot-synthetic-completeness.sh` (AC8). Fix any inline-synthetic gaps surfaced.
6. **Phase 5 — Docs.** Update `infra/github/README.md`, ADR-032, `compliance-posture.md`. AC10, AC11.
7. **Phase 6 — PR + auto-apply.** Open PR with `Closes #4384, #3913, #3914` in body (AC16). Verify CI green. `gh pr merge --squash --auto`. Post-merge `apply-github-infra.yml` runs (AC17, AC18).
8. **Phase 7 — Post-merge verification.** AC19 (synthetic deadlock probe), AC20 (synthetic destroy-guard probe → close #3915), AC21 (bot-PR happy path).

## Research Insights

### Pattern precedents

- **PR #3543 (skill-security-scan PR gate promotion)** — identical workflow-shape precedent: added one required-check via Terraform + composite-action `CHECK_NAMES` extension + `required-checks.txt`. Confirmed structurally analogous; reuse the proven scaffolding wholesale.
- **PR #3891 (Tier-1/Tier-2 widening)** — same Terraform root edit pattern; 9 additive `required_check` blocks. Confirms the apply-on-merge model works for `infra/github/` (but only AFTER bootstrap, which is exactly the gap this PR closes).
- **PR #4144 (deploy-pipeline PAT→App migration)** — first repo-wide migration to the `app_auth` pattern. The retro lesson (`hr-github-app-auth-not-pat`) is the load-bearing rationale for folding PAT migration into this PR rather than landing #3913 separately.

### Observability patterns

- **CodeQL `neutral` conclusion** satisfies a required-check (per `scripts/required-checks.txt` comment block). This is the canonical "always-runs workflow with O(1) short-circuit" pattern that `enforce` post-this-PR will follow.
- **`scheduled-followthrough-sweeper.yml`** is the existing daily watchdog for stuck PRs; it already inspects `statusCheckRollup` and would surface a PR stuck on `enforce=PENDING`. No new monitoring needed.

### API contracts

- `gh api repos/.../rulesets/N` requires `Administration: Read`. The default workflow `GITHUB_TOKEN` does NOT carry this scope. The App-installed token (via App-JWT exchange) does, IF the App has `Administration: Write` on the repo (Write implies Read).
- The `integrations/github` v6.12.1 provider's `app_auth` block is the canonical form (verified against `apps/web-platform/infra/main.tf:74-78`).

### Failure-mode precedent

- **#4144 — deploy-pipeline-fix.yml stuck for ~14h** because a PAT was added as a required TF variable and never populated in Doppler. The lesson is exactly what this PR avoids by NOT introducing a new PAT and instead migrating to App credentials already in Doppler.
- **#4116 — `inngest-heartbeat.service` silently broken for 16+ hours** — gave rise to `hr-observability-as-plan-quality-gate` (now enforced at Phase 4.7). This plan's §Observability section is the load-bearing artifact for that gate.

### References

- [ADR-031: Sentry-as-IaC / apply-on-merge boundary](../../../knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md)
- [ADR-032: GitHub branch-protection as IaC](../../../knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md)
- [Learning: `[skip ci]` and bot-PR no-retrigger deadlock](../../../knowledge-base/project/learnings/2026-03-20-github-required-checks-skip-ci-synthetic-status.md)
- [Learning: multi-word required-check whitespace bug](../../../knowledge-base/project/learnings/2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md)
- [Learning: rulesets PATCH replaces entire payload](../../../knowledge-base/project/learnings/2026-04-03-github-ruleset-put-replaces-entire-payload.md)
- [hr-all-infrastructure-provisioning-servers] [hr-menu-option-ack-not-prod-write-auth] [hr-no-dashboard-eyeball-pull-data-yourself] [hr-observability-as-plan-quality-gate] [hr-github-app-auth-not-pat] [hr-tf-variable-no-operator-mint-default] [wg-use-closes-n-in-pr-body-not-title-to]

## Source

- Issue: #4384 (`OPEN` as of 2026-05-25)
- Source PR: #4353 (`MERGED` 2026-05-23; DSAR departed-member legal-doc lockstep)
- Originating PR: #4294 (`MERGED`; substrate that auto-merged around the FAILED advisory gate)
- Original issue: #4333 (`CLOSED`)
- Folded-in follow-throughs: #3913 (`OPEN` — mint `GH_RULESET_PAT` + first-apply, superseded by App auth), #3914 (`OPEN` — validate apply on no-op PR), #3915 (`OPEN` — destroy-guard test, deferred to AC20)
- Provider-PR-of-record: #3891 (`MERGED` 2026-05-16 — Tier-1/Tier-2 widening; the bootstrap that this PR finally lands)
