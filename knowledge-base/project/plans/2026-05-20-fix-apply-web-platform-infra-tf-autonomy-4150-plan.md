---
title: "fix(infra): autonomous resolution of apply-web-platform-infra terraform variables (#4150)"
type: fix
date: 2026-05-20
lane: single-domain
brand_survival_threshold: none
requires_cpo_signoff: false
closes: 4150
---

# fix(infra): autonomous resolution of apply-web-platform-infra terraform variables (#4150)

## Enhancement Summary

**Deepened on:** 2026-05-20
**Sections enhanced:** Research Reconciliation, Phase 1.4 (kb-drift wiring), Phase 3 (canonical TF invocation), Risks (R4 expanded), Sharp Edges (R4 enforcement), Prior Art (Inngest IaC sibling).

### Key Improvements (vs. initial plan)

1. **Phase 3 canonical TF invocation** — replaced the simplified `doppler run … terraform plan` form with the AWS-exports-first triplet per `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`. Without `AWS_ACCESS_KEY_ID/SECRET` exported plain, the R2 backend silently fails to authenticate and emits a confusing error.
2. **Risk R4 → enforced fix** — confirmed `kb-drift.tf:60` currently carries `lifecycle.ignore_changes = [plaintext_value]`. This MUST be removed in Phase 1.4 or in-band rotation would never propagate. Promoted from Risks to a hard Phase 1.4 sub-step.
3. **Prior-art linkage** — explicitly reference `inngest.tf:97-104`'s policy comment as the precedent pattern (workplace-token-mints-config-token, `ignore_changes` discipline). The Inngest IaC migration (#3973) collapsed 4 operator-mint variables to 4 `random_id` resources using the same autonomy reasoning.
4. **App permissions verification step** — verify both `administration:write` AND `secrets:write` on the soleur-ai App at Phase 0.2 (publishing `github_actions_secret` requires `secrets:write`, the brief asserted only `administration:write`).
5. **Plan-output structural verification** — added `terraform show -json tfplan | jq` to Phase 3 so the expected `+ create / - destroy / ~ update` shape can be asserted against the actual plan, not just the human-readable summary line.

### New Considerations Discovered

- **Workflow apply-step also has the allow-list** — Phase 1.5 mirrors the `-target=` changes to both the plan step AND the apply step (verified at lines 195 + 303). A one-side edit ships a plan/apply mismatch that surfaces at apply time only.
- **The OPERATOR NOTE in `kb-drift.tf:14-22` about `prd_kb_drift_walker` config-existence stays** — the in-band Doppler service token mint depends on the config existing, which is still operator-only because the doppler_environment resource manages environment+configs as a unit. This is acceptable under `hr-never-label-any-step-as-manual-without` because the config already exists (verified at Phase 0.1) and creating a new Doppler config is a fresh-credential-bootstrap-class operation per `2026-05-15-operator-only-step-canonical-list.md`.
- **Github App installation token has a 1-hour TTL** — `app_auth` issues fresh tokens per terraform invocation. Drift detection (`scheduled-terraform-drift.yml`) and ad-hoc applies all get fresh tokens; this is strictly better than a long-lived PAT.

## Problem

`.github/workflows/apply-web-platform-infra.yml` fails at the `Terraform plan` step because four variables defined in `apps/web-platform/infra/variables.tf` have no value source in Doppler `prd_terraform`:

- `var.github_app_client_id` (`variables.tf:168`)
- `var.github_app_client_secret` (`variables.tf:174`)
- `var.github_actions_token` (`variables.tf:180`)
- `var.doppler_token_kb_drift` (`variables.tf:186`)

Failed run: <https://github.com/jikig-ai/soleur/actions/runs/26157459893>.

The path-of-least-resistance fix (issue #4150's "Operator actions required") is to ask the operator to mint each of these four credentials in vendor dashboards (GitHub App OAuth, GitHub PAT mint, Doppler service-token mint) and paste them into Doppler `prd_terraform`. **This plan rejects that path** because every one of the four is autonomously resolvable: two are dead plumbing the app never reads, one can be replaced by App-installation auth using credentials Terraform already has, and the last is mintable by `doppler_service_token` resource (the workplace-scope token already in `prd_terraform`). Per `hr-exhaust-all-automated-options-before` and `hr-never-label-any-step-as-manual-without`, this is squarely Soleur's responsibility — not the operator's.

## User-Brand Impact

- **If this lands broken, the user experiences:** the `apply-web-platform-infra.yml` workflow continues to fail on every infra-touching merge, accruing operator-attention debt; no end-user-visible regression because `terraform plan` aborts before any state mutation.
- **If this leaks, the user's data is exposed via:** N/A — this PR removes operator-minted credentials from variables and replaces them with provider-side mints; the App-auth migration moves from a long-lived PAT (`var.github_actions_token`) to a short-lived App installation token (issued by the provider per `terraform plan/apply`), which is a net narrowing of secret surface.
- **Brand-survival threshold:** `none`

*Scope-out override:* `threshold: none, reason: this refactor only deletes / restructures the terraform credential surface; the `apply-web-platform-infra.yml` workflow operates on infra only, and the four variables involved have no user-data path through them. The new `doppler_service_token` resource issues a Doppler token narrowly scoped to `prd_kb_drift_walker` (KB-drift cron only), and the github_app installation token replaces a broader-scope PAT.*

## Observability

```yaml
liveness_signal:
  what: "GitHub Actions workflow `apply-web-platform-infra.yml` exit-code (post-merge run on main)"
  cadence: "per-merge to main when paths under apps/web-platform/infra/** change; manual workflow_dispatch on demand"
  alert_target: "GitHub Actions UI + (failure) Sentry web-platform via existing `apply-web-platform-infra` notification webhook (see alerts-github-webhook.tf)"
  configured_in: ".github/workflows/apply-web-platform-infra.yml:177-269 (plan step) + 271-360 (apply step)"

error_reporting:
  destination: "GitHub Actions step output `::error::` annotations; the workflow's existing `cloudflare_notification_policy` routes failure to ops email"
  fail_loud: "step `Terraform plan (allow-list, non-SSH resources only)` emits `::error::terraform plan failed (exit $rc).` on failure; PR auto-merge does not gate on apply, but next merge on main re-runs the workflow"

failure_modes:
  - mode: "github provider's app_auth block returns 401 (App is uninstalled, App ID mismatched, or installation_id stale)"
    detection: "terraform plan step emits a non-zero exit, `::error::terraform plan failed` annotation"
    alert_route: "GitHub Actions UI; operator triages via run-link in PR comments"
  - mode: "doppler_service_token resource fails to mint (prd_kb_drift_walker config missing, or DOPPLER_TOKEN_TF scope insufficient)"
    detection: "terraform plan emits `Error: Could not create service token` against `doppler_service_token.kb_drift`"
    alert_route: "GitHub Actions UI; recovery is to verify `prd_kb_drift_walker` exists in Doppler (read-only check via `doppler configs --project soleur`)"
  - mode: "github_actions_secret.doppler_token_kb_drift fails to publish (App lacks `secrets:write` on the soleur repo)"
    detection: "terraform plan emits `Error: PUT .../actions/secrets/DOPPLER_TOKEN_KB_DRIFT: 403`"
    alert_route: "GitHub Actions UI; recovery is to verify App permissions at https://github.com/organizations/jikig-ai/settings/apps/soleur-ai/permissions"

logs:
  where: "GitHub Actions run logs for `apply-web-platform-infra.yml` (retained 90 days per GH default)"
  retention: "90 days"

discoverability_test:
  command: "gh run list --workflow=apply-web-platform-infra.yml --limit 1 --json conclusion,databaseId,headSha --jq '.[0]'"
  expected_output: "JSON object with conclusion=\"success\" for the post-merge run of this PR's commit"
```

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #4150) | Reality (verified at plan-write time) | Plan response |
|---|---|---|
| `GITHUB_APP_CLIENT_ID` / `GITHUB_APP_CLIENT_SECRET` must be operator-minted in vendor dashboard for the multi-source webhook ingress | `git grep "GITHUB_APP_CLIENT_ID\|GITHUB_APP_CLIENT_SECRET\|github_app_client" apps/web-platform/** --include="*.ts" --include="*.tsx"` returns ZERO TS/TSX consumers. Only writers are `github-app.tf:51-72` (write to Doppler `prd`) and Doppler `prd_terraform` (set as operator workaround). The values are dead plumbing — never read by the app. | Delete the 2 variables, 2 `doppler_secret` resources, the 2 `-target=` lines in apply workflow, and the orphan `GITHUB_APP_CLIENT_ID` in `prd_terraform`. |
| `GITHUB_ACTIONS_TOKEN` (operator-minted fine-grained PAT) is required by the `integrations/github` provider to publish `DOPPLER_TOKEN_KB_DRIFT` | `integrations/github` v6.12.1 supports `app_auth` block (App-installation auth) — verified at <https://registry.terraform.io/providers/integrations/github/6.12.1/docs#authenticating-via-github-app-installation>. The `soleur-ai` GitHub App (id 3261325, installation 122213433 on jikig-ai) already has `administration:write` + has `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` stored in Doppler `prd`. | Switch `provider "github"` to `app_auth { id, installation_id, pem_file }`; copy the two GITHUB_APP_* secrets from `prd` to `prd_terraform` (one-time mirror — both configs need them, terraform reads `prd_terraform` via `--name-transformer tf-var`). Verify `secrets:write` is present in App permissions (required to publish `github_actions_secret`). |
| `DOPPLER_TOKEN_KB_DRIFT` (operator-minted service token) is required to publish the Actions secret | DopplerHQ/doppler v1.21.2 provider supports `doppler_service_token` resource (verified at <https://registry.terraform.io/providers/DopplerHQ/doppler/1.21.2/docs/resources/service_token>). The provider authenticates via `var.doppler_token_tf` (workplace-scope personal token in `prd_terraform`) which has scope to mint config-scoped tokens. The `prd_kb_drift_walker` config already exists in Doppler. | Add `doppler_service_token.kb_drift` resource → wire `.key` into `github_actions_secret.doppler_token_kb_drift.plaintext_value`. Delete `var.doppler_token_kb_drift`. |
| All 4 variables are independently needed | The four variables collapse into ZERO net-new operator credentials. 2 are dead plumbing; 1 reuses already-present App credentials; 1 is mintable by an already-present workplace token. | This PR closes the operator gate entirely for the `apply-web-platform-infra.yml` workflow's variable resolution. |

## Files to Edit

1. `apps/web-platform/infra/variables.tf` — delete 4 variable blocks: `github_app_client_id` (168-172), `github_app_client_secret` (174-178), `github_actions_token` (180-184), `doppler_token_kb_drift` (186-190). Update PR-H header comment at line 154 to reflect new var count (was "5 net-new vars for PR-H", now "2 net-new vars: github_app_id + github_app_private_key").
2. `apps/web-platform/infra/main.tf` — replace `provider "github"` block at 59-62 with `app_auth { id, installation_id, pem_file }` form. Update the PR-H comment at 58 to cite the App-auth migration (this PR #).
3. `apps/web-platform/infra/github-app.tf` — delete `doppler_secret.github_app_client_id` (51-61) and `doppler_secret.github_app_client_secret` (63-73). Update header at 1-22 to reflect 2 operator-supplied secrets (App ID + PEM) down from 4, and add a note linking to the new App-auth provider config in `main.tf`.
4. `apps/web-platform/infra/kb-drift.tf` — replace operator-mint reference (lines 14-22 OPERATOR NOTE keeps the `prd_kb_drift_walker` config-existence caveat; lines 48-58 swap `var.doppler_token_kb_drift` for `doppler_service_token.kb_drift.key`). Add a new `resource "doppler_service_token" "kb_drift"` block referencing `project = "soleur"`, `config = "prd_kb_drift_walker"`, `name = "kb-drift-ci-tf"`, `access = "read"`.
5. `.github/workflows/apply-web-platform-infra.yml` — remove the two `-target=doppler_secret.github_app_client_id` / `..._secret` lines at 204-205. Add `-target=doppler_service_token.kb_drift` next to the existing `-target=github_actions_secret.doppler_token_kb_drift` at 248.
6. `apps/web-platform/infra/inngest.test.sh` — verify no test assertions break (read first; the file only asserts `doppler_token_tf` existence — confirmed at plan-write).
7. `knowledge-base/operations/runbooks/github-app-provisioning.md` — update lines 59-60 (export `TF_VAR_github_app_client_id` / `_secret`) and line 106 (Client Secret rotation procedure) to remove references to the deleted variables. Add a note explaining the App auth migration eliminates the PAT dependency.
8. `AGENTS.core.md` — add new hard rule `hr-tf-variable-no-operator-mint-default` (body ≤ 600 bytes per `cq-agents-md-tier-gate`). See "AGENTS.md Rule" section below.
9. `AGENTS.md` — add the rule id pointer line under `## Hard Rules` (alphabetical insertion order is not enforced; place near other tf-* rules).
10. `knowledge-base/project/learnings/best-practices/2026-05-20-tf-operator-mint-variables-are-design-smell.md` — new learning file. See "Learning File" section below.

## Files to Create

- `knowledge-base/project/learnings/best-practices/2026-05-20-tf-operator-mint-variables-are-design-smell.md` (see §Learning File).

## Implementation Phases

### Phase 0 — Verify preconditions (no writes yet)

0.1 Verify the `prd_kb_drift_walker` Doppler config exists: `doppler configs --project soleur --json | jq '.[] | select(.name == "prd_kb_drift_walker") | .name'` returns `"prd_kb_drift_walker"`.

0.2 Verify the `soleur-ai` GitHub App has BOTH required permissions on the soleur repo:
- `administration:write` (needed for ruleset/repository APIs the kb-drift workflow may touch in the future)
- `secrets:write` (needed for `github_actions_secret.doppler_token_kb_drift` to publish — this is the load-bearing one for this PR)

Command (user-context auth):
```bash
gh api /repos/jikig-ai/soleur/installation --jq '.app_slug + " perms=" + (.permissions | tojson)'
```
Expected: `app_slug = "soleur-ai"`, `permissions` JSON includes both `administration: "write"` and `secrets: "write"`.

If the call returns 401 (JWT-only endpoint), fall back to the App settings page at <https://github.com/organizations/jikig-ai/settings/apps/soleur-ai/permissions> (operator-visible via Playwright if needed; the brief asserts these are present).

Confirm installation_id `122213433` is current:
```bash
gh api /orgs/jikig-ai/installations --jq '.installations[] | select(.app_slug == "soleur-ai") | .id'
```
Expected output: `122213433`. If different, update `main.tf` with the new value in Phase 1.2.

0.3 Verify `DOPPLER_TOKEN_TF` (workplace personal token) can mint a service token in `prd_kb_drift_walker`. The provider docs say workplace-scope tokens can create config-scoped service tokens; verify by running `terraform plan` locally (see Phase 4) rather than minting upfront.

0.4 Re-grep for any stray TS/TSX consumer of the deleted variables:
```bash
git grep -nE "GITHUB_APP_CLIENT_ID|GITHUB_APP_CLIENT_SECRET" apps/web-platform/app/ apps/web-platform/lib/ apps/web-platform/server/ apps/web-platform/src/ 2>/dev/null
```
Expected output: empty. If any match returns, ABORT Phase 1 and re-classify the variable as in-use (would invalidate the plan's design choice).

### Phase 1 — TF code edits (mechanical)

1.1 Edit `apps/web-platform/infra/variables.tf`: delete the 4 variable blocks (168-190). Edit the PR-H header comment at line 154 to read:
```
# --- PR-H (#3244) — GitHub App + KB-drift -----------------------------------
# Post-#4150: client_id / client_secret / github_actions_token / doppler_token_kb_drift
# variables were deleted — see plan
# knowledge-base/project/plans/2026-05-20-fix-apply-web-platform-infra-tf-autonomy-4150-plan.md
# (provider switched to App-installation auth; kb-drift Doppler token minted via
# doppler_service_token resource).
```

1.2 Edit `apps/web-platform/infra/main.tf:59-62` to:
```hcl
# PR-H (#3244) — GitHub provider for Actions-secret publishing (kb-drift).
# Post-#4150: switched from PAT auth (var.github_actions_token, deleted) to
# App-installation auth — reuses the soleur-ai App credentials already in
# Doppler `prd`. App id 3261325, installation 122213433 on jikig-ai org.
provider "github" {
  owner = "jikig-ai"
  app_auth {
    id              = var.github_app_id
    installation_id = "122213433"
    pem_file        = var.github_app_private_key
  }
}
```

1.3 Edit `apps/web-platform/infra/github-app.tf`: delete resources at lines 51-73. Update the header (lines 1-22) to:
- "Provisions 2 operator-supplied doppler_secret resources" (was 4).
- Add a note: "Post-#4150: the github_app_client_id / github_app_client_secret resources were deleted — never read by any app code (TS/TSX grep returned zero); the values are leftover OAuth plumbing not used by the App-installation webhook flow."
- Keep the random_id-derived webhook secret intact.

1.4 Edit `apps/web-platform/infra/kb-drift.tf`:
- Add new resource (before the existing github_actions_secret block, ~line 48):
  ```hcl
  # Doppler service token minted in-band by Terraform. Workplace-scope
  # DOPPLER_TOKEN_TF (provider auth) has scope to create config-scoped
  # service tokens. Closes the operator-mint requirement called out in #4150.
  resource "doppler_service_token" "kb_drift" {
    project = "soleur"
    config  = "prd_kb_drift_walker"
    name    = "kb-drift-ci-tf"
    access  = "read"
  }
  ```
- Replace line 57 `plaintext_value = var.doppler_token_kb_drift` with `plaintext_value = doppler_service_token.kb_drift.key`.
- **Delete the `lifecycle { ignore_changes = [plaintext_value] }` block at lines 59-61** (verified present in current file). Reason: the operator-mint flow needed ignore_changes to suppress drift from out-of-band rotation. In-band rotation via `terraform apply -replace=doppler_service_token.kb_drift` is now the canonical path, and the published Actions secret MUST update when the source token rotates — otherwise the kb-drift cron will continue using a revoked token until someone notices. This is Risk R4's enforcement clause: ignore_changes removal is mandatory, not optional.
- Update the OPERATOR NOTE at lines 14-22 to drop the "operator mints token" sentence at line 50 and replace lines 48-58 header with: "GH Actions secret for the cron workflow. Token minted in-band by `doppler_service_token.kb_drift` (above) — workplace-scope DOPPLER_TOKEN_TF authenticates the provider, which has scope to mint config-scoped tokens. Pre-existing config `prd_kb_drift_walker` is still a precondition (see operator note above). NO ignore_changes — rotation is `terraform apply -replace=doppler_service_token.kb_drift` and the new value MUST propagate to the Actions secret."

1.5 Edit `.github/workflows/apply-web-platform-infra.yml`:
- Delete lines 204-205 (`-target=doppler_secret.github_app_client_id` and `..._secret`).
- Insert `-target=doppler_service_token.kb_drift \` immediately before line 248 (`-target=github_actions_secret.doppler_token_kb_drift`).
- Mirror the change in the `apply` step's `-target=` list (search the file for the second occurrence of the same allow-list — apply step lives after plan).

1.6 Edit `knowledge-base/operations/runbooks/github-app-provisioning.md`:
- Lines 59-60: delete the `TF_VAR_github_app_client_id` / `_secret` export lines.
- Line 106: rewrite the "Client Secret rotation" bullet to remove the TF_VAR reference, replace with: "App Client Secret is no longer terraform-managed (no app code reads it). If the App needs OAuth-Client functionality later, re-add the doppler_secret resources and the corresponding variables."
- Add a section near the top explaining the App-auth migration (`integrations/github` provider now uses `app_auth` block; no PAT required).

### Phase 2 — Pre-flight: Doppler secret moves (read+write, idempotent)

These three Doppler mutations are state-shape changes that the `terraform apply` step depends on. They run BEFORE the PR opens because: (a) they're idempotent (re-running them with the same value is a no-op), (b) they're read-only against the source config (`prd` → `prd_terraform`), and (c) running them post-merge would force a second iteration through the apply workflow.

2.1 Mirror `GITHUB_APP_ID` from `prd` to `prd_terraform`:
```bash
doppler secrets get GITHUB_APP_ID -p soleur -c prd --plain | \
  doppler secrets set GITHUB_APP_ID -p soleur -c prd_terraform --visibility masked --no-interactive
```

2.2 Mirror `GITHUB_APP_PRIVATE_KEY` from `prd` to `prd_terraform`:
```bash
doppler secrets get GITHUB_APP_PRIVATE_KEY -p soleur -c prd --plain | \
  doppler secrets set GITHUB_APP_PRIVATE_KEY -p soleur -c prd_terraform --visibility masked --no-interactive
```

2.3 Delete the orphan `GITHUB_APP_CLIENT_ID` from `prd_terraform` (set earlier by operator workaround):
```bash
doppler secrets delete GITHUB_APP_CLIENT_ID -p soleur -c prd_terraform --yes
```

2.4 Verify the four soon-deleted vars are absent from `prd_terraform`:
```bash
doppler secrets -p soleur -c prd_terraform --only-names 2>&1 | \
  grep -E "GITHUB_APP_CLIENT_SECRET|GITHUB_ACTIONS_TOKEN|DOPPLER_TOKEN_KB_DRIFT|GITHUB_APP_CLIENT_ID" || \
  echo "OK: no operator-mint vars remain"
```
Expected: `OK: no operator-mint vars remain`.

(Note: `DOPPLER_TOKEN_KB_DRIFT` is still going to appear in `prd_terraform` if the operator pre-set it; if so, delete it too in 2.3 — terraform reads it via `--name-transformer tf-var` and the in-band mint replaces it.)

### Phase 3 — Local `terraform plan` smoke test

3.1 From repo root, use the canonical TF invocation triplet per `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md` — AWS exports MUST be plain (not under `tf-var` transform) or the R2/S3 backend silently fails to authenticate:

```bash
cd apps/web-platform/infra
# (1) AWS creds for R2 backend — plain, NOT under tf-var transform
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
# (2) Init against the R2 backend
terraform init -input=false
# (3) Plan with --name-transformer tf-var (~13 TF_VAR_* inputs needed)
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform plan -no-color -input=false -out=tfplan
# Inspect the structured plan to confirm expected diff shape
terraform show -json tfplan | jq '[.resource_changes[] | {address, actions: .change.actions}] | sort_by(.address)'
```

Expected diff shape:
- `+ create doppler_service_token.kb_drift`
- `- destroy doppler_secret.github_app_client_id`
- `- destroy doppler_secret.github_app_client_secret`
- `~ update in-place github_actions_secret.doppler_token_kb_drift` (plaintext_value changes from operator-mint to doppler_service_token.kb_drift.key — only if `lifecycle.ignore_changes = [plaintext_value]` was removed per Risk R4)

No `Error: No value for required variable` lines should appear. If they do, the cause is almost always a leftover `TF_VAR_*` that wasn't deleted — re-verify Phase 1.1 and Phase 2.

3.2 If plan fails:
- `Error: 401` from github provider → app_auth misconfigured (verify installation_id matches `gh api /orgs/jikig-ai/installations` lookup).
- `Error: insufficient scope` from doppler_service_token → DOPPLER_TOKEN_TF lacks workplace-write scope; file a separate issue and revert to the workplace token used elsewhere.
- `Error: prd_kb_drift_walker not found` → Phase 0.1 verification missed; the config has been deleted out-of-band; recreate via Doppler UI and re-run.

### Phase 4 — Acceptance Criteria

#### Pre-merge (PR)

1. [ ] `apps/web-platform/infra/variables.tf` no longer contains `variable "github_app_client_id" { ... }`, `variable "github_app_client_secret" { ... }`, `variable "github_actions_token" { ... }`, or `variable "doppler_token_kb_drift" { ... }`. Verified by:
   ```bash
   git grep -nE '^variable "(github_app_client_id|github_app_client_secret|github_actions_token|doppler_token_kb_drift)"' apps/web-platform/infra/variables.tf
   ```
   returns empty.
2. [ ] `apps/web-platform/infra/main.tf` `provider "github"` block contains an `app_auth {` block and does NOT contain `token = var.github_actions_token`. Verified by:
   ```bash
   awk '/^provider "github"/,/^}/' apps/web-platform/infra/main.tf | grep -qE '^\s*app_auth\s*\{' && \
     ! awk '/^provider "github"/,/^}/' apps/web-platform/infra/main.tf | grep -qE 'var\.github_actions_token'
   ```
3. [ ] `apps/web-platform/infra/kb-drift.tf` declares `resource "doppler_service_token" "kb_drift"` and references `doppler_service_token.kb_drift.key` in `github_actions_secret.doppler_token_kb_drift.plaintext_value`. Verified by:
   ```bash
   grep -qE 'resource "doppler_service_token" "kb_drift"' apps/web-platform/infra/kb-drift.tf && \
     grep -qE 'plaintext_value\s*=\s*doppler_service_token\.kb_drift\.key' apps/web-platform/infra/kb-drift.tf
   ```
4. [ ] `apps/web-platform/infra/github-app.tf` no longer contains the two deleted resources. Verified by:
   ```bash
   ! grep -qE 'resource "doppler_secret" "github_app_client_(id|secret)"' apps/web-platform/infra/github-app.tf
   ```
5. [ ] `.github/workflows/apply-web-platform-infra.yml` no longer targets the deleted resources and adds the new one. Verified by:
   ```bash
   ! grep -qE '\-target=doppler_secret\.github_app_client_(id|secret)' .github/workflows/apply-web-platform-infra.yml && \
     grep -qE '\-target=doppler_service_token\.kb_drift' .github/workflows/apply-web-platform-infra.yml
   ```
6. [ ] `doppler secrets -p soleur -c prd_terraform --only-names` shows `GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY` present, and `GITHUB_APP_CLIENT_ID` / `GITHUB_APP_CLIENT_SECRET` / `GITHUB_ACTIONS_TOKEN` / `DOPPLER_TOKEN_KB_DRIFT` absent.
7. [ ] Local `terraform plan` (Phase 3.1) succeeds against `prd_terraform`; the structured plan output shows `+ create doppler_service_token.kb_drift`, `- destroy doppler_secret.github_app_client_id`, `- destroy doppler_secret.github_app_client_secret`.
8. [ ] New `AGENTS.core.md` rule `hr-tf-variable-no-operator-mint-default` is registered in `AGENTS.md`'s `## Hard Rules` index and lints clean: `python3 scripts/lint-rule-ids.py` exits 0; `python3 scripts/lint-agents-rule-budget.py` exits 0.
9. [ ] New learning file `knowledge-base/project/learnings/best-practices/2026-05-20-tf-operator-mint-variables-are-design-smell.md` exists with YAML frontmatter (problem_type / component / synced_to).
10. [ ] PR body uses `Closes #4150` (not `Ref #4150` — this is a code-class plan whose merge IS the fix, no post-merge operator action; the post-merge workflow run on main is the verification, not the remediation).

#### Post-merge (verifier)

11. [ ] `apply-web-platform-infra.yml` post-merge run succeeds. Verified by:
    ```bash
    gh run list --workflow=apply-web-platform-infra.yml --branch=main --limit 1 --json conclusion,databaseId,headSha --jq '.[0]'
    ```
    `.conclusion == "success"` AND `.headSha == <merge SHA>`.
12. [ ] `gh api repos/jikig-ai/soleur/actions/secrets/DOPPLER_TOKEN_KB_DRIFT --jq '.updated_at'` returns a timestamp newer than the merge.
13. [ ] `doppler secrets get GITHUB_APP_CLIENT_ID -p soleur -c prd_terraform --plain` exits non-zero (NotFound).
14. [ ] `gh api repos/jikig-ai/soleur/environments/web-platform-infra-apply --jq '.protection_rules'` still contains deruelle reviewer + main-only branch policy (no regression to the environment gate).
15. [ ] No new Sentry events for `apply-web-platform-infra` in the 30 minutes after merge.

## AGENTS.md Rule

**New rule:** `[id: hr-tf-variable-no-operator-mint-default]` → core

**Pointer line** (add to `AGENTS.md` under `## Hard Rules`, near `hr-fresh-host-provisioning-reachable-from-terraform-apply`):
```
- [id: hr-tf-variable-no-operator-mint-default] → core
```

**Body** (add to `AGENTS.core.md`; target ≤ 600 bytes per `cq-agents-md-tier-gate`):
```
- [id: hr-tf-variable-no-operator-mint-default] Before adding a new `variable "..." { sensitive = true }` block to any terraform root, exhaust three autonomous paths in this order: (1) provider-side mint (`doppler_service_token`, `random_id`, `*_app_token_from_*` for App-installation tokens, vendor APIs accepting operator-chosen randoms per ADR-030); (2) reuse already-stored credentials at a different config/scope (App-installation auth instead of a fresh PAT, mirrored secrets across Doppler configs); (3) operator mint as last resort, gated by `hr-never-label-any-step-as-manual-without` (CAPTCHA / SSO / fresh-credential bootstrap / payment). PR reviewers MUST verify (1) and (2) were considered before approving the new variable. Sentinel: any new sensitive variable lacking an inline `# autonomy-considered: <none|provider-mint-rejected|reuse-rejected|operator-only-per-...>` comment fails review. Why: #4150 — 4 new variables added at PR-H landed without autonomy analysis, all 4 were autonomously resolvable.
```

(If 600B budget is tight at write-time, run `wc -c` on the body and trim — preferred trim: collapse the "Sentinel" sentence into the "PR reviewers" sentence.)

## Learning File

Path: `knowledge-base/project/learnings/best-practices/2026-05-20-tf-operator-mint-variables-are-design-smell.md`

Frontmatter:
```yaml
---
module: Web Platform Infrastructure
date: 2026-05-20
problem_type: workflow_drift
component: tooling
symptoms:
  - "terraform plan fails with `Error: No value for required variable` on `apply-web-platform-infra.yml` post-merge"
  - "PR adds 4 new `variable \"...\" { sensitive = true }` blocks; issue body asks operator to mint each in vendor dashboards"
root_cause: design_smell
resolution_type: rule_addition
severity: medium
tags: [terraform, doppler, github-app, iac, autonomy, operator-mint]
synced_to: []
---
```

Body sections:
- **Problem**: PR-H #4066 added 4 new sensitive variables to `apps/web-platform/infra/variables.tf` without considering provider-side mint or credential reuse. Three weeks later, `apply-web-platform-infra.yml` (added by #4122) failed at plan-time because none of the four had values in Doppler `prd_terraform`. The issue tracker (#4150) proposed operator-mint for all four.
- **Root cause**: A `variable { sensitive = true }` block is the *least flexible* secret-supply path — every consumer (dev workstation, CI runner, drift detector) needs its own copy of the credential. The IaC providers Soleur already loads have higher-affinity primitives: `doppler_service_token`, `random_id`, App-installation-token derivations. Skipping these in favor of `var.X` is a design smell because the variable-shaped solution looks cheap at PR time but loads cost onto every downstream consumer in perpetuity.
- **Resolution**: 4 variables → 0 net-new operator-mints. Two were dead plumbing (deleted). One was replaceable by App-installation auth (`app_auth { ... }` on `integrations/github` provider, reusing `var.github_app_id` + `var.github_app_private_key` already in scope). One was mintable in-band by `doppler_service_token` resource (workplace-scope `DOPPLER_TOKEN_TF` already authenticates the doppler provider).
- **Prevention**: New rule `hr-tf-variable-no-operator-mint-default` requires PR reviewers to verify provider-side mint + reuse were considered before approving a new sensitive variable. The rule's sentinel (`# autonomy-considered: ...` inline comment) makes the analysis visible at review time.
- **Key insight**: The cheapest path at PR-write time is rarely the cheapest path at lifecycle level. A `variable { sensitive = true }` block is 5 lines; the operator-onboarding runbook to feed it is 50; the recurring debt across CI runners + drift detectors + new contributors is unbounded.

## Open Code-Review Overlap

Query:
```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in apps/web-platform/infra/variables.tf apps/web-platform/infra/main.tf apps/web-platform/infra/github-app.tf apps/web-platform/infra/kb-drift.tf .github/workflows/apply-web-platform-infra.yml; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

Findings: **None** — no open `code-review`-labeled issue references the 5 edited files. (Verified at plan-write; re-run at /work time as a freshness check.)

## Infrastructure (IaC)

### Terraform changes

- **Files**: `apps/web-platform/infra/{variables,main,github-app,kb-drift}.tf` (existing root; no new TF root).
- **Required providers (already pinned in `.terraform.lock.hcl`)**: `integrations/github 6.12.1` (supports `app_auth` per docs URL above), `DopplerHQ/doppler 1.21.2` (supports `doppler_service_token` per docs URL above). No version bumps required.
- **Sensitive variables remaining for kb-drift / github-app**:
  - `var.github_app_id` (already in `prd_terraform`; will also be in `prd_terraform` after Phase 2.1).
  - `var.github_app_private_key` (already in `prd_terraform` after Phase 2.2; same value as `prd`).
  - `var.doppler_token_tf` (workplace-scope personal token; pre-existing).

### Apply path

- **Path (c) idempotent-rerun via existing workflow**: this is purely TF code edits + Doppler value moves. No host downtime, no replace, no taint. The post-merge `apply-web-platform-infra.yml` run executes the changes against existing state.
- Expected blast radius: 2 `doppler_secret` resources destroyed (GITHUB_APP_CLIENT_ID / _SECRET in `prd`), 1 `doppler_service_token` created (kb-drift), 1 `github_actions_secret` updated in place (new plaintext_value from the service token).
- Downtime: zero (Doppler service token publishing → GH Actions secret update is atomic; the next `kb-drift-walker.yml` cron run uses the new token).

### Distinctness / drift safeguards

- `provider "github"`'s `app_auth` block has no `dev` vs `prd` discriminator — it authenticates against the org-level App installation. Acceptable because the only `github_actions_secret` resource it writes (`doppler_token_kb_drift`) is repo-level on `jikig-ai/soleur` — there is no dev equivalent.
- `doppler_service_token.kb_drift` pins `project = "soleur"` and `config = "prd_kb_drift_walker"` explicitly. Cannot land in `dev` without an edit to this file (caught at PR review). Mirrors the policy on every other `doppler_*` resource in this root (e.g., `inngest.tf:50-66`).
- State storage: the service token's `.key` value lands in `terraform.tfstate` (encrypted at rest in R2 + `key` only decryptable with `AWS_*` creds in Doppler). Mirrors the existing `random_id`-derived secret pattern.

### Vendor-tier reality check

- **GitHub App**: free for the jikig-ai org. No tier gate needed.
- **Doppler**: workplace-scope tokens can mint config-scoped service tokens on all paid tiers (Team / Pro / Enterprise). Soleur is on the Team tier — verified via dashboard at plan-write. No tier gate needed.
- **GitHub Actions secret publishing**: free on public + private repos. No tier gate.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)

**Status:** reviewed (inline).
**Assessment:** This is a pure IaC refactor. The architectural impact is positive: (a) collapses an unused OAuth client surface, (b) replaces a long-lived PAT with short-lived App-installation tokens (narrower secret surface, automatic rotation per GitHub's App installation token lifecycle of 1 hour), (c) shifts a Doppler service token from operator-minted (long-lived, unrotated) to terraform-managed (rotation = `terraform apply -replace=doppler_service_token.kb_drift`). All three are net wins under the existing `hr-all-infrastructure-provisioning-servers` rule.

No Product/UX impact (infra-only). No legal/compliance impact (the variables in question were operator credentials, not user data). No data-integrity impact (no DB schema). No security-sensitive boundary changes beyond the App-vs-PAT narrowing described above.

## GDPR / Compliance Gate

Skipped. Plan touches no regulated-data surfaces: no schemas / migrations / auth flows / API routes / `.sql` files; no new processing of operator-session data; brand-survival threshold is `none`; no new cron/workflow reads of `knowledge-base/`; no new artifact distribution surface.

## Risks

- **R1 — installation_id drift**: hardcoding `installation_id = "122213433"` couples this provider to the current jikig-ai installation. If the App is uninstalled+reinstalled, the ID changes. Mitigation: monitor via the existing `apply-web-platform-infra.yml` workflow's failure annotation; recovery is a single TF edit. Probability: very low (App installations are durable).
- **R2 — DOPPLER_TOKEN_TF scope**: the workplace-scope personal token's ability to mint config-scoped service tokens depends on the workplace's RBAC settings. Mitigation: Phase 3 local plan smoke test fails early if scope is insufficient, before the merge. Recovery would be to grant the workspace personal token a wider scope (operator action).
- **R3 — terraform `-replace` semantics on doppler_service_token**: if the operator runs `terraform apply -replace=doppler_service_token.kb_drift`, the old token is revoked and a new one is issued; there is a brief (<1s) window where the published Actions secret holds the new value but a kb-drift cron run started before the publish hits the old (revoked) token. Mitigation: the kb-drift workflow runs daily, not hourly; the rotation event is rare. Acceptable.
- **R4 — github_actions_secret.plaintext_value churn on rotation (ENFORCED in Phase 1.4)**: when `doppler_service_token.kb_drift` is re-created (e.g., manual `-replace`), the published `plaintext_value` MUST change. The current `lifecycle.ignore_changes = [plaintext_value]` at `kb-drift.tf:59-61` was correct for the operator-mint flow but now would BLOCK propagation of the in-band rotation, leaving the cron with a revoked token. **Action — promoted from Risk to mandatory Phase 1.4 sub-step**: delete the entire `lifecycle { ignore_changes = [plaintext_value] }` block. The drift detector's daily run will catch any out-of-band churn.
- **R5 — `app_auth` provider call latency adds to plan time**: each terraform invocation makes a JWT-RS256 sign + installation-token-exchange API call (~200-500ms). On the apply workflow's 15-minute budget this is negligible; on long-running drift detection runs (hourly, in the apply workflow path) it adds ~1 sec/run. Acceptable — token reuse within a single `terraform plan` invocation is handled by the provider.
- **R6 — operator's existing `prd_terraform` Doppler secrets for the deleted vars**: if `GITHUB_APP_CLIENT_SECRET`, `GITHUB_ACTIONS_TOKEN`, or `DOPPLER_TOKEN_KB_DRIFT` are still present in `prd_terraform`, they leak into `TF_VAR_*` env vars but don't bind to any TF variable (the variables are deleted). Terraform 1.6+ tolerates extra `TF_VAR_*` env vars silently. Phase 2.3 deletes them as cleanup; not load-bearing for plan success.

## Research Insights

**Prior art — Inngest IaC (#3973):**

This plan is structurally identical to the `inngest.tf` migration that closed #3960 (PR-F operator follow-through). That migration collapsed 4 operator-mint variables (Inngest signing/event keys for `prd` + `dev`) to 4 `random_id` resources, using the same workplace-scope Doppler token to author Doppler secrets. The pattern transfers cleanly: where Inngest's keys were operator-chosen-randoms (per ADR-030 self-hosted), this plan's `doppler_service_token` is a vendor-issued-but-API-mintable token. The autonomy classification differs (random_id vs. provider-mint), but the variable-collapse result is the same. See [`inngest.tf:1-21`](apps/web-platform/infra/inngest.tf) for the canonical comment block this plan should mirror.

**Provider docs verified:**

- `integrations/github` v6.12.1 `app_auth` block: <https://registry.terraform.io/providers/integrations/github/6.12.1/docs#authenticating-via-github-app-installation>. Required fields: `id` (App ID), `installation_id`, `pem_file` (PEM contents OR file path). The provider exchanges these for an installation token at every invocation.
- `DopplerHQ/doppler` v1.21.2 `doppler_service_token` resource: <https://registry.terraform.io/providers/DopplerHQ/doppler/1.21.2/docs/resources/service_token>. Required: `project`, `config`, `name`. Optional: `access` (default `read`, alt `read/write`).

**Best practices:**

- Authenticate the `integrations/github` provider via App installation rather than PAT when the App already exists — narrower scope, automatic rotation, no operator-secret-lifecycle to manage.
- For Doppler service tokens published to GitHub Actions secrets, mint via `doppler_service_token` resource rather than operator action — TF state captures the token value (encrypted in R2), enabling deterministic re-publish on `-replace`.
- For any sensitive variable, write an inline comment `# autonomy-considered: <none|provider-mint-rejected|reuse-rejected|operator-only-per-...>` so the rationale is visible at PR review (per new `hr-tf-variable-no-operator-mint-default`).

**Anti-patterns to avoid:**

- Reusing `lifecycle.ignore_changes = [plaintext_value]` on a `github_actions_secret` whose source value rotates in-band — silently strands the consumer on the previous token (Risk R4).
- Hardcoding `installation_id` without a comment explaining the lookup path (`gh api /repos/<owner>/<repo>/installation --jq '.id'`) — future maintainers can't refresh it without re-discovering the API.
- Adding `--name-transformer tf-var` to BOTH outer and inner `doppler run` invocations (the inner-must-be-tf-var, outer-must-be-plain pattern is documented in `main.tf:1-13` and `2026-03-21-doppler-tf-var-naming-alignment.md`).

**Performance considerations:**

- App-installation token exchange adds ~200-500ms per `terraform plan`/`apply`. Within the 15-min workflow budget — negligible.
- `doppler_service_token` creation is a one-shot at first apply; subsequent applies are no-ops unless the resource is `-replace`'d. State storage: token value lands in `terraform.tfstate` (R2-encrypted-at-rest).

**Edge cases:**

- **`prd_kb_drift_walker` config deletion out-of-band**: Phase 0.1 verifies presence; Phase 3 plan would fail loud with `Error: 404 config not found` if it disappears between verification and apply.
- **Soleur-AI App uninstalled and reinstalled**: `installation_id` changes; plan fails with 401 at first invocation. Recovery is a single-line edit + new apply.
- **DOPPLER_TOKEN_TF rotation**: workplace personal tokens have no automatic rotation; if the operator rotates it manually, the provider authentication breaks until `prd_terraform`'s value is updated. Out of scope for this PR.

**References:**

- App installation auth in `integrations/github` provider: <https://registry.terraform.io/providers/integrations/github/6.12.1/docs#authenticating-via-github-app-installation>
- Doppler service token resource: <https://registry.terraform.io/providers/DopplerHQ/doppler/1.21.2/docs/resources/service_token>
- Canonical TF invocation triplet for `apps/web-platform/infra/`: `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`
- Vendor-token-mint patterns and the in-band random_id precedent: `knowledge-base/project/learnings/2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md`
- Operator-only step canonical list (the exclusions): `knowledge-base/project/learnings/2026-05-15-operator-only-step-canonical-list.md`
- Inngest IaC sibling pattern (#3973): `apps/web-platform/infra/inngest.tf`, in-repo
- Doppler TF-var naming alignment: `knowledge-base/project/learnings/2026-03-21-doppler-tf-var-naming-alignment.md`

## Non-Goals (deferred)

- **Lifting `prd_kb_drift_walker` Doppler config to terraform management**: the provider's `doppler_environment` resource manages env+configs as a unit; the operator's existing environment isn't TF-managed. Tracked in existing OPERATOR NOTE in `kb-drift.tf`; no new issue needed.
- **Rotating `GITHUB_APP_PRIVATE_KEY`**: orthogonal to this PR. The PEM in `prd` / `prd_terraform` is unchanged.
- **Removing `--name-transformer tf-var` from the apply workflow**: still needed for ~10 other TF_VAR_* inputs (cf_api_token, hcloud_token, webhook_deploy_secret, etc.). No change.
- **Auditing other terraform roots for similar operator-mint anti-patterns** (e.g., `infra/github/`'s `var.gh_token` PAT). Defer to a follow-up sweep triggered by the new hard rule's adoption.

## Sharp Edges

- The brief's snippet uses `--visibility masked` on the doppler mirror commands; verify the source secret's visibility (`doppler secrets get GITHUB_APP_PRIVATE_KEY -p soleur -c prd --json | jq '.[].visibility'`) and match it — secrets stored as `restricted` cannot be `--plain`-read by non-owner identities. If the PEM is `restricted`, use an alternative copy path (the operator's authenticated Doppler CLI session).
- `doppler_service_token.kb_drift`'s `access = "read"` is correct for the kb-drift cron (read-only access to `prd_kb_drift_walker` secrets). Do NOT widen to `"write"` — minting tokens with broader access than the consumer needs is a blast-radius regression.
- The PR-H plan at `knowledge-base/project/plans/2026-05-19-feat-daily-priorities-multi-source-pr-h-plan.md:290-291` lists `GITHUB_APP_CLIENT_ID` / `GITHUB_APP_CLIENT_SECRET` as "operator-supplied" — that plan is already merged and won't be retroactively updated, but the new learning file should link back to it as the antecedent design choice.
- Removing `lifecycle.ignore_changes = [plaintext_value]` from `github_actions_secret.doppler_token_kb_drift` (per Risk R4) is a behavior change at the next `terraform apply`: it will detect drift between the published Actions secret and the freshly-minted token and update the secret. This is the intended behavior — verify the apply output shows the update at Phase 3 smoke test.
- `cq-agents-md-tier-gate` enforces a 600-byte budget on `AGENTS.core.md` rule bodies. Run `awk '/hr-tf-variable-no-operator-mint-default/,/^$/' AGENTS.core.md | wc -c` after the edit to verify; trim the "Sentinel" sentence if needed.

## PR Body Template

```markdown
Closes #4150

## Summary

Refactor `apps/web-platform/infra/` so `apply-web-platform-infra.yml` succeeds without operator-minted secrets. Four variables collapse to zero net-new operator credentials:

- `github_app_client_id` / `github_app_client_secret` — dead plumbing (zero TS/TSX consumers); deleted.
- `github_actions_token` (PAT) — replaced by App-installation auth on the `integrations/github` provider, reusing the existing soleur-ai App credentials.
- `doppler_token_kb_drift` — replaced by `doppler_service_token.kb_drift` resource, minted in-band by terraform using the workplace-scope `DOPPLER_TOKEN_TF` already in `prd_terraform`.

## Design choice: autonomy over runbook

Issue #4150 proposed a 4-step operator runbook (mint each credential in vendor dashboards, paste into `prd_terraform`). This PR eliminates the operator gate instead, per the new hard rule `hr-tf-variable-no-operator-mint-default` ([AGENTS.core.md](AGENTS.core.md)). The variable-shaped solution loads cost onto every downstream consumer (CI runners, drift detector, new contributors) in perpetuity; provider-side mint and credential reuse are one-time author costs at PR time.

See also: [learning](knowledge-base/project/learnings/best-practices/2026-05-20-tf-operator-mint-variables-are-design-smell.md).

## Test plan

- [ ] Local `terraform plan` (Phase 3.1) succeeds against `prd_terraform`.
- [ ] Post-merge `apply-web-platform-infra.yml` run exits 0.
- [ ] `gh api repos/jikig-ai/soleur/actions/secrets/DOPPLER_TOKEN_KB_DRIFT --jq '.updated_at'` returns a timestamp newer than the merge.
- [ ] `doppler secrets get GITHUB_APP_CLIENT_ID -p soleur -c prd_terraform` returns NotFound.
- [ ] `gh api repos/jikig-ai/soleur/environments/web-platform-infra-apply --jq '.protection_rules'` unchanged (deruelle reviewer + main branch policy intact).

🤖 Generated with Claude Code one-shot
```
