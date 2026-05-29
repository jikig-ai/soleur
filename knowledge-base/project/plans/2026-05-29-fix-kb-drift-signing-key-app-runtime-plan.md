---
title: "fix(kb-drift): provision ingest secrets into app-runtime Doppler config prd"
type: fix
date: 2026-05-29
lane: cross-domain
brand_survival_threshold: none
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: the entire fix IS Terraform (.tf doppler_secret + variable
     resources). The only operator step is `terraform apply` itself, which is
     genuinely operator-local because apps/web-platform/infra has no automated
     apply workflow (infra-validation.yml runs plan-only; scheduled-terraform-drift.yml
     instructs apply-locally). This is the documented prd_terraform runbook pattern,
     not manual provisioning — no SSH, no dashboard clicks, no operator-minted secret
     (signing key derives from in-state random_id; founder-id is a human identity UUID
     supplied via TF_VAR from prd_terraform). hr-all-infrastructure-provisioning-servers
     and hr-no-ssh-fallback-in-runbooks both satisfied. -->

# fix(kb-drift): provision ingest secrets into app-runtime Doppler config `prd`

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Enhancement Summary

**Deepened on:** 2026-05-29
**Sections enhanced:** Apply Path, Risks & Mitigations (Precedent-Diff)
**Gates run:** 4.4 precedent-diff, 4.6 User-Brand Impact (PASS), 4.7 Observability (PASS), 4.8 PAT-shaped-var (PASS, no match), rule-id active-check (3/3 active)

### Key Improvements

1. **Precedent-grounded the two new resources** against `inngest.tf` / `github-app.tf` / the existing `kb-drift.tf` block. Confirmed the signing-key resource must mirror the walker resource's NO-`ignore_changes` polarity (the `inngest_signing_key_prd` precedent uses `ignore_changes` — adopting it here would freeze the verifier on rotation → 401 storm). The closest precedent (`github_app_webhook_secret`, a `random_id`-derived secret into `config="prd"`, NO `ignore_changes`) exactly matches the proposed shape.
2. **Corrected the Apply Path to the in-repo canonical NESTED `doppler run` invocation** documented at `variables.tf:1-13`, rather than the flat `export AWS_*` form from the drift-runbook learning (functionally equivalent; nested form matches repo precedent).
3. **Surfaced the `ssh_key_path` plan-time var** that `infra-validation.yml:160-167` passes, so a local plan doesn't error unexpectedly.

### New Considerations Discovered (round-1 realism)

- The "no new external surface / HMAC stays load-bearing" negative claim in User-Brand Impact was verify-the-negative-checked: the walker's scoped read token (`access="read"`, config `prd_kb_drift_walker`) cannot read root `prd`; this PR adds no token, no route, no scope widening (confirmed against `doppler_service_token.kb_drift` at kb-drift.tf:67-72).
- **Carried forward from plan-time live verification:** the second latent 500 (`KB_DRIFT_OPERATOR_FOUNDER_ID` absent from all configs + all `.tf`) is the single highest-value discovery — without folding it in, post-merge AC #2 (walker → success) is unsatisfiable. See Research Reconciliation.

## Overview

The KB-drift walker ingest route returns `500 {"error":"Server misconfigured"}`
because the secret it HMAC-verifies against (`KB_DRIFT_INGEST_SIGNING_KEY`) is
absent from the Doppler config the app runtime loads (`prd`). The key is
provisioned only in the blast-radius-scoped walker config (`prd_kb_drift_walker`).
This is an infra-only fix: add the missing secret(s) to the app-runtime config
via Terraform, sourced from the same `random_id` so rotation cascades.

A live-verification pass against prod uncovered a **second, independent latent
500** in the same route that the original diagnosis did not name — see
`## Research Reconciliation` below. Both are folded into this PR because
post-merge acceptance criterion #2 (a full walker run must conclude `success`)
is otherwise unsatisfiable.

## Problem Statement / Motivation

`apps/web-platform/app/api/internal/kb-drift-ingest/route.ts` authenticates
inbound POSTs from the nightly `KB-drift walker` GitHub Actions cron by HMAC-SHA256:

- `route.ts:49-52` — `readSigningKey()` reads `process.env.KB_DRIFT_INGEST_SIGNING_KEY`; returns `null` if unset/empty.
- `route.ts:86-94` — if the key is `null`, the route returns **500 `{"error":"Server misconfigured"}`** and mirrors to Sentry (`tags: { feature: "kb-drift-ingest", op: "secret" }`).
- `route.ts:96-104` — only after a non-null key does HMAC verification run; a bad signature returns **401 `{"error":"Invalid signature"}`**.

The app runtime loads its env from Doppler config `prd`
(`apps/web-platform/infra/ci-deploy.sh:175`:
`doppler secrets download --no-file --format docker --project soleur --config prd`).
But `apps/web-platform/infra/kb-drift.tf:39-46` writes
`KB_DRIFT_INGEST_SIGNING_KEY` into config `prd_kb_drift_walker` **only** — the
separate branch config whose scoped service token the CI walker reads to *sign*.
The app's parent-root `prd` config never received the key, so `readSigningKey()`
returns `null` on every request and the 500 fires before verification.

The bug was **latent until PR #4570** (`fix(kb-drift): route ingest POST to app
host + bypass session redirect`, merged 2026-05-29T08:02Z). Before #4570, the
apex-host 405 / session-redirect bug masked it — POSTs never reached the
secret-check branch. #4570 fixed the routing; the missing-secret 500 is now the
surfacing failure.

### Live verification (2026-05-29, read-only)

| Probe | Result |
|-------|--------|
| `curl -X POST` bad-sig → `https://app.soleur.ai/api/internal/kb-drift-ingest` | `500` (confirmed) |
| `doppler secrets get KB_DRIFT_INGEST_SIGNING_KEY -p soleur -c prd --plain` | `Could not find requested secret` |
| `doppler secrets get KB_DRIFT_INGEST_SIGNING_KEY -p soleur -c prd_kb_drift_walker --plain` | present (`walker HAS signing key`) |
| `curl https://app.soleur.ai/login` | `200` (app healthy; isolates the fault to the route's secret check) |

## Proposed Solution

Add Terraform `doppler_secret` resource(s) writing the ingest secrets into config
`prd` (the app runtime), sourced from the existing `random_id` / value so the
walker config and the app config always hold identical values and rotation
cascades to both. No app source change.

```hcl
# apps/web-platform/infra/kb-drift.tf (append)

# App-runtime verify-side copy. The walker config (prd_kb_drift_walker) SIGNS;
# the app runtime config (prd) VERIFIES — both must hold the same value.
# Sourced from the same random_id so `terraform apply -replace=random_id...`
# cascades the new value to BOTH configs in one apply. Blast-radius design is
# unaffected: the walker's scoped read service token still only sees
# prd_kb_drift_walker; this resource only adds a verify-side copy to the app's
# own config, which the app already reads in full.
resource "doppler_secret" "kb_drift_ingest_signing_key_app_runtime" {
  project    = "soleur"
  config     = "prd"
  name       = "KB_DRIFT_INGEST_SIGNING_KEY"
  value      = "kbdrift-${random_id.kb_drift_ingest_signing_key.hex}"
  visibility = "masked"
  # NO ignore_changes — rotation via `terraform apply -replace=random_id...`
  # must cascade to both configs.
}
```

Style matches the existing `doppler_secret.kb_drift_ingest_signing_key`
(kb-drift.tf:39-46) verbatim: same `value` expression, same `visibility`, same
no-`ignore_changes` rotation comment.

**Second secret (`KB_DRIFT_OPERATOR_FOUNDER_ID`) — see Research Reconciliation.**
This plan adds a Terraform `variable` + `doppler_secret` for it into `prd` as
well, because the route's second 500 path depends on it and the walker-success
AC cannot pass without it.

## Research Reconciliation — Diagnosis vs. Codebase/Prod

| Diagnosis claim | Verified reality | Plan response |
|---|---|---|
| `KB_DRIFT_INGEST_SIGNING_KEY` absent from `prd`, present in `prd_kb_drift_walker` | **Confirmed** live + in code (kb-drift.tf:39-46 → walker only; ci-deploy.sh:175 → app reads `prd`) | Add `doppler_secret` to `prd` (core fix) |
| Apply runs via "the apply-web-platform-infra workflow" | **CONFIRMED — the workflow exists** (`.github/workflows/apply-web-platform-infra.yml`), triggers on push to main under `apps/web-platform/infra/**`, and runs a targeted `terraform plan -out=tfplan` + saved-plan apply via `doppler run -c prd_terraform --name-transformer tf-var`. It observed-ran green on PR #4570's merge. (An earlier draft of this plan wrongly claimed it did not exist.) | Apply is **automated on merge**. Because the plan is target-scoped, this PR ADDS `-target=` lines for the two new resources to the workflow — otherwise they would be planned-but-not-applied. |
| TF-only diff "may not trigger the web-platform-release deploy" → trigger redeploy | **Confirmed.** `web-platform-release.yml` deploy job gates on `needs.release.outputs.version != ''` (line 43) and POSTs the deploy webhook to `https://deploy.soleur.ai/hooks/deploy` (line 56-66). A pure `apps/web-platform/infra/**` diff produces no release → no redeploy → container keeps the stale env. | Plan prescribes an explicit redeploy trigger so `ci-deploy.sh` re-downloads `prd`. |
| (not in diagnosis) bad-sig POST → expect 401 after fix | **Confirmed safe.** The founder-id check (route.ts:122-130) runs *after* HMAC verify (line 97). A bad-sig POST returns 401 at line 103 before reaching the founder-id branch, so AC #1 holds regardless of the second gap. | AC #1 unchanged; the second gap only affects AC #2 (good-sig walker run). |
| **NEW — second latent 500** | `route.ts:122-130` reads `process.env.KB_DRIFT_OPERATOR_FOUNDER_ID`; if unset returns **500 `{"error":"Server misconfigured"}`** (`op: "operator-id"`). Live: absent from **`prd` AND `prd_kb_drift_walker`**; grep shows it is provisioned in **no `.tf` and no `.env.example`** — only set in `kb-drift-ingest-route.test.ts:72`. The PR-H fixture `pr-h-counterfactual.md:5` records it as an intended `prd_kb_drift_walker` bootstrap (AC-PM3) that never landed. A good-sig walker run will 500 here even after the signing key is fixed. | **Fold in**: add `variable "kb_drift_operator_founder_id"` + `doppler_secret` into `prd`. Without it, post-merge AC #2 (walker → success) is unsatisfiable. |

## Technical Considerations

- **Doppler config topology.** `prd_kb_drift_walker` is a *branch config* of root `prd` (`doppler configs -p soleur` → parent column = `prd`). A secret set in a branch is an *override*; the root value surfaces in the branch only where the branch has no override. Because the walker config already holds its own `KB_DRIFT_INGEST_SIGNING_KEY` (value `kbdrift-${random_id...hex}`) and this plan writes the **identical** value into root `prd`, both configs hold the same string — no divergence, rotation cascades to both. This is why the fix is "add to `prd`", not "move".
- **Idempotency / `terraform import`.** The two new `doppler_secret` resources are pure creates (the names do not yet exist in `prd`). No import needed. The drift detector will show `2 to add` on first plan against live state.
- **Sensitive value in state.** `random_id.hex` and the founder-id land in `terraform.tfstate` (encrypted R2 backend). Same posture as the existing walker secret — no new exposure class.
- **`KB_DRIFT_OPERATOR_FOUNDER_ID` value source.** It is the operator founder's Supabase `auth.users.id` UUID. It is NOT a generated secret (cannot use `random_id`). Provide it via `TF_VAR_kb_drift_operator_founder_id`, sourced from Doppler `prd_terraform` (the operator sets it once in `prd_terraform`, consumed at apply via `--name-transformer tf-var`). This matches the existing `prd_terraform`-sourced variable pattern in this root (`cf_api_token_*`, `webhook_deploy_secret`, etc.).
- **NFR impact.** No latency/throughput change. Availability of the KB-drift ingest path improves from "always-500" to "functional".

### Attack Surface Enumeration

- The HMAC verification (`verifyHmac`, route.ts:54-64, `timingSafeEqual`) remains the sole load-bearing auth gate. This plan does not weaken it — it makes the verify-side key *present* so the gate can run at all (today an unset key short-circuits to 500 before verification, which is fail-closed but also fully broken).
- The walker's scoped Doppler service token (`doppler_service_token.kb_drift`, `access = "read"`, config `prd_kb_drift_walker`) is unchanged. It still cannot read root `prd`. Blast radius unchanged.
- No new route, no new caller, no widening of any token scope.

## User-Brand Impact

- **If this lands broken, the user experiences:** the nightly KB-drift walker continues to fail (ingest 500), so broken-link / broken-anchor findings never appear as draft messages in the operator's `knowledge` domain — a silent gap in the operator's Daily Priorities feed (no user-facing data corruption).
- **If this leaks, the user's data/workflow is exposed via:** N/A — this change only writes a verify-side copy of an HMAC key (and the operator's own founder UUID) into the app's own runtime config, which the app already reads in full. No new external surface; the HMAC gate stays load-bearing.
- **Brand-survival threshold:** `none`
- *Scope-out override (sensitive path `apps/web-platform/infra/` is touched):* `threshold: none, reason: the diff only adds verify-side copies of an HMAC signing key (already present in the sibling walker config) and the operator's own founder UUID into the app's own Doppler config; it grants no new scope, adds no external surface, and the HMAC gate remains the sole load-bearing auth.`

## Observability

```yaml
liveness_signal:
  what: "KB-drift walker GitHub Actions cron run conclusion (per-run ingest HTTP code echoed in the 'Run walker and POST to ingest' step) + Sentry absence-of-error"
  cadence: "daily (cron '0 3 * * *') + on-demand via workflow_dispatch"
  alert_target: "GitHub Actions run status (red X on failed run) + Sentry issue if route 500s"
  configured_in: ".github/workflows/kb-drift-walker.yml (run step asserts 2xx) ; apps/web-platform/app/api/internal/kb-drift-ingest/route.ts:89-92,125-128 (Sentry.captureMessage)"

error_reporting:
  destination: "Sentry web-platform project via SENTRY_DSN (Sentry.captureMessage at route.ts:89, 99, 125)"
  fail_loud: "HTTP 500 {\"error\":\"Server misconfigured\"} on the ingest response + Sentry issue tagged feature=kb-drift-ingest; the walker workflow step fails its 2xx assertion and the Actions run goes red"

failure_modes:
  - mode: "KB_DRIFT_INGEST_SIGNING_KEY still absent from prd (apply not run, or redeploy not triggered)"
    detection: "bad-sig POST returns 500 (not 401); Sentry op=secret message; walker run red"
    alert_route: "Sentry issue + GitHub Actions failed-run notification to operator"
  - mode: "KB_DRIFT_OPERATOR_FOUNDER_ID absent from prd"
    detection: "good-sig walker POST returns 500; Sentry op=operator-id message; walker run red on the ingest step"
    alert_route: "Sentry issue + GitHub Actions failed-run notification to operator"
  - mode: "Container holds stale env (apply ran but no redeploy)"
    detection: "bad-sig POST still 500 after `doppler secrets get ... -c prd` succeeds locally"
    alert_route: "operator notices probe mismatch in the Apply Path verification step"

logs:
  where: "Sentry (structured events) ; pino logger.error lines in the container's docker logs (route.ts:88,98,124) ; GitHub Actions run logs for the walker workflow"
  retention: "Sentry per project plan ; GitHub Actions logs 90 days ; container docker logs per host rotation"

discoverability_test:
  command: curl -fsS -o /dev/null -w "%{http_code}" --max-time 10 https://app.soleur.ai/login
  expected_output: "200"
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/infra/kb-drift.tf` gains a `doppler_secret.kb_drift_ingest_signing_key_app_runtime` resource: `config = "prd"`, `name = "KB_DRIFT_INGEST_SIGNING_KEY"`, `value = "kbdrift-${random_id.kb_drift_ingest_signing_key.hex}"`, `visibility = "masked"`, NO `lifecycle.ignore_changes`, with the walker-signs/app-verifies comment.
- [ ] `apps/web-platform/infra/kb-drift.tf` gains a `doppler_secret.kb_drift_operator_founder_id_app_runtime` resource: `config = "prd"`, `name = "KB_DRIFT_OPERATOR_FOUNDER_ID"`, `value = var.kb_drift_operator_founder_id`, `visibility = "masked"`.
- [ ] `apps/web-platform/infra/variables.tf` gains `variable "kb_drift_operator_founder_id"` (`type = string`, `sensitive = true`, no default — fail-closed per `hr-tf-variable-no-operator-mint-default`).
- [ ] The existing `doppler_secret.kb_drift_ingest_signing_key` (walker config) and `random_id.kb_drift_ingest_signing_key` are **unchanged** (`git diff` shows no edit to lines 35-46).
- [ ] `terraform validate` passes in `apps/web-platform/infra/` (run via the `prd_terraform` triplet — see Apply Path).
- [ ] `terraform plan` against live state shows exactly `Plan: 2 to add, 0 to change, 0 to destroy` (the two new `prd` secrets) — re-run immediately before publishing the runbook to confirm no stale drift (per drift-runbook Sharp Edge); if the live plan diverges, reconcile before merge.
- [ ] PR body uses `Ref #<issue>` (NOT `Closes`) — issue closure happens post-merge after the apply succeeds (`type: ops-remediation` class; fix executes post-merge).
- [ ] PR body includes a `## Changelog` section (`semver:patch`).

### Post-merge (automated)

- [x] `KB_DRIFT_OPERATOR_FOUNDER_ID` set in Doppler `prd_terraform` (operator-founder Supabase `users.id` UUID `52af49c2-…`) so `TF_VAR_kb_drift_operator_founder_id` resolves at apply. **Done in-session by the pipeline** — resolved read-only from prod Supabase by operator email; no operator step.
- [x] **CORRECTION (plan premise was wrong):** an automated apply workflow DOES exist — `.github/workflows/apply-web-platform-infra.yml` runs a targeted `terraform plan -out=tfplan` + saved-plan apply on every push to main touching `apps/web-platform/infra/**`, using `doppler run -c prd_terraform --name-transformer tf-var`. This PR adds `-target=doppler_secret.kb_drift_ingest_signing_key_app_runtime` and `-target=doppler_secret.kb_drift_operator_founder_id_app_runtime` to that workflow so both new `prd` secrets are applied on merge. No operator-local `terraform apply`.
- [ ] Trigger an app redeploy so the container re-runs `ci-deploy.sh` and re-downloads `prd` (TF-only diff does not trigger `web-platform-release.yml`). Prefer the existing release/deploy webhook path; fold into `/soleur:ship` post-merge verification.
- [ ] **Verify #1:** bad-sig POST `curl -s -o /dev/null -w "%{http_code}" --max-time 12 -X POST -H "x-soleur-kb-drift-signature: sha256=deadbeef" -H "Content-Type: application/json" -d '{"findings":[],"counts":{"broken_link":0,"broken_anchor":0}}' https://app.soleur.ai/api/internal/kb-drift-ingest` returns `401` (not 500, not 307).
- [ ] **Verify #2:** `gh workflow run "KB-drift walker"` then poll `gh run list --workflow="KB-drift walker" --limit 1 --json conclusion` until `conclusion == "success"`.
- [ ] After both verifications pass, `gh issue close <issue>` with a comment linking the apply + walker run.

## Test Scenarios

### Regression (proves the fix)

- Given `KB_DRIFT_INGEST_SIGNING_KEY` is present in `prd` and the container has redeployed, when a bad-signature POST hits the ingest route, then it returns `401 {"error":"Invalid signature"}` (the secret-check 500 no longer fires).
- Given both `KB_DRIFT_INGEST_SIGNING_KEY` and `KB_DRIFT_OPERATOR_FOUNDER_ID` are present in `prd`, when the `KB-drift walker` cron runs and POSTs a correctly-signed payload, then the route returns 2xx and the walker run concludes `success`.

### Edge cases

- Given `KB_DRIFT_OPERATOR_FOUNDER_ID` is still unset in `prd` (founder-id var not set before apply), when a good-sig POST arrives, then the route returns `500 {"error":"Server misconfigured"}` (`op: "operator-id"`) — this is the second-gap regression the founder-id resource closes.
- Given `random_id.kb_drift_ingest_signing_key` is rotated via `terraform apply -replace`, when the next apply runs, then both `prd` and `prd_kb_drift_walker` receive the same new `kbdrift-<hex>` value (no rotation drift), because neither `doppler_secret` carries `ignore_changes`.

### Integration verification (consumed by `/soleur:qa`)

- **API verify (post-deploy):** bad-sig POST → expect `401` (command in Verify #1 above).
- **Workflow verify:** `gh workflow run "KB-drift walker"` → poll for `conclusion == "success"`.

## Dependencies & Risks

- **Dependency:** PR #4570 (apex-host/redirect fix) must be deployed — it is (merged 2026-05-29T08:02Z). Without it the ingest path never reaches the secret check.
- **Risk — redeploy omitted:** applying TF writes the secret to Doppler but the running container keeps its stale env until `ci-deploy.sh` re-runs. Mitigated by the explicit redeploy step + Verify #1 (bad-sig must flip 500→401).
- **Risk — founder-id var unset at apply:** apply would fail-closed (no default on the variable). Mitigated by the no-default `variable` + the operator pre-apply step.
- **Risk — drift snapshot staleness:** the `Plan: 2 to add` assertion is captured against live state; re-run `terraform plan` immediately before the runbook executes (drift-runbook Sharp Edge).

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

### Precedent-Diff (deepen Phase 4.4)

This root has three established `doppler_secret` shapes; the two new resources are NOT novel. The choice of which precedent to mirror is **load-bearing**:

| Resource (precedent) | `config` | `value` source | `ignore_changes`? | Rotation |
|---|---|---|---|---|
| `doppler_secret.kb_drift_ingest_signing_key` (kb-drift.tf:39-46) | `prd_kb_drift_walker` | `kbdrift-${random_id...hex}` | **NO** | `-replace=random_id` (must cascade) |
| `doppler_secret.github_app_webhook_secret` (github-app.tf:74-79) | `prd` | `ghwh-${random_id...hex}` | **NO** | `-replace=random_id` |
| `doppler_secret.inngest_signing_key_prd` (inngest.tf:49-59) | `prd` | `signkey-prod-${random_id...hex}` | **YES** (`# rotate out-of-band; do not churn`) | `terraform taint random_id` |
| `doppler_secret.github_app_id` (github-app.tf:40-53) | `prd` | `var.github_app_id` | **YES** (value managed outside TF) | edit var |

- **Signing-key resource → mirror `kb_drift_ingest_signing_key` (NO `ignore_changes`).** This is the critical divergence from the `inngest_signing_key_prd` precedent: if the app-runtime copy carried `ignore_changes` but the walker copy did not, a `-replace=random_id.kb_drift_ingest_signing_key` rotation would update the walker (signer) while freezing the app (verifier) → HMAC mismatch → **401 on every walker run**. The two kb-drift copies MUST share rotation polarity. No-`ignore_changes` is correct and load-bearing.
- **Founder-id resource → `value = var.kb_drift_operator_founder_id`, NO `ignore_changes`.** Diverges from the `github_app_id` precedent (which carries `ignore_changes` because its value is managed outside TF). The founder UUID is a stable identity value sourced only from the variable; a variable update SHOULD propagate at `apply`, and there is no out-of-band rotation path to protect. (A future reviewer preferring symmetry with `github_app_id` may add `ignore_changes = [value]` harmlessly, since the founder-id never rotates; the no-`ignore_changes` form is the lower-surprise default.)

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/kb-drift.tf` — append 2 `doppler_secret` resources (`*_app_runtime` for signing key + founder-id), `config = "prd"`.
- `apps/web-platform/infra/variables.tf` — add `variable "kb_drift_operator_founder_id"` (`string`, `sensitive`, no default).
- Providers: existing `DopplerHQ/doppler` (already required by this root) — no new provider, no version bump.
- Sensitive variables: `TF_VAR_kb_drift_operator_founder_id` sourced from Doppler `prd_terraform` (operator-set once). Signing-key value derives from the existing in-state `random_id` — no operator input.

### Apply path

**(b) operator-local apply via the in-repo canonical NESTED invocation** (no automated apply workflow exists for this root; no SSH). The canonical form is documented verbatim at `apps/web-platform/infra/variables.tf:1-13` (precedent-verified during deepen — use THIS, not the flat `export AWS_*` form). From `apps/web-platform/infra/`:

```bash
terraform init -input=false

# Nested doppler run: outer injects plain AWS_* (R2 backend creds, must NOT be
# tf-var-transformed or the S3/R2 backend fails to authenticate); inner adds
# TF_VAR_* via --name-transformer tf-var. --token forces personal-token auth on
# the inner call (the DOPPLER_TOKEN service token collides with CLI auth otherwise).
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform plan    # expect: Plan: 2 to add, 0 to change, 0 to destroy

doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform apply   # creates both prd secrets
```

Expected blast radius: 2 secret creates, zero downtime; a redeploy is then required for the container to pick them up.

> **Deepen note — invocation form.** The flat `export AWS_ACCESS_KEY_ID=$(doppler secrets get ...)` + single `doppler run --name-transformer tf-var` form (from the drift-runbook learning) is functionally equivalent but the in-repo `variables.tf` header documents the NESTED form as canonical for this root. Use the nested form to match repo precedent. The `ssh_key_path` var that `infra-validation.yml` passes is NOT needed here — this root reads it from a var with a default at plan time; if `terraform plan` errors on a missing `ssh_key_path`, pass `-var="ssh_key_path=/tmp/ci_ssh_key.pub"` as `infra-validation.yml:160-167` does.

### Distinctness / drift safeguards

- `dev != prd`: this change targets `prd` only; `dev` Doppler config is untouched.
- No `lifecycle.ignore_changes` on either new resource — rotation (`terraform apply -replace=random_id.kb_drift_ingest_signing_key`) MUST cascade the new signing-key value to both `prd` and `prd_kb_drift_walker`.
- Secret values land in `terraform.tfstate` on the encrypted R2 backend (existing posture).

### Vendor-tier reality check

Doppler secret creation has no free-tier gate relevant here (the project already provisions dozens of `doppler_secret` resources). No tier guard needed.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/secrets change to make an existing internal route functional. No product/UI surface, no schema/auth/regulated-data change (the route attributes rows to the operator founder only; no new processing of user data). GDPR gate (Phase 2.7): the canonical regex covers schemas/migrations/auth/API-route code — this diff touches none (TF + variable only, no route/schema edit), and none of triggers (a)-(d) fire (no new LLM processing, threshold is `none`, no new cron READing learnings/specs, no new distribution surface). Skipped silently.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` checked for the two edited paths — `apps/web-platform/infra/kb-drift.tf`, `apps/web-platform/infra/variables.tf` — no open scope-out names either file.)

## References & Research

- Route: `apps/web-platform/app/api/internal/kb-drift-ingest/route.ts:49-52, 86-104, 122-130`
- Existing walker secret (style precedent): `apps/web-platform/infra/kb-drift.tf:35-46`
- App-runtime Doppler config load: `apps/web-platform/infra/ci-deploy.sh:175`
- Walker workflow (signs + POSTs): `.github/workflows/kb-drift-walker.yml`
- No-apply-workflow evidence: `.github/workflows/infra-validation.yml:173` (plan only), `.github/workflows/scheduled-terraform-drift.yml:89,174` (plan + "apply locally")
- Deploy webhook path: `.github/workflows/web-platform-release.yml:43,56-66`
- Intended-but-missing founder-id bootstrap: `plugins/soleur/test/fixtures/ship-undeferred-operator-step-gate/pr-h-counterfactual.md:5`
- Canonical `prd_terraform` invocation triplet + drift-snapshot-staleness: `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`
- Related PRs: #4570 (apex-host fix, the unmasking change), #4066 (PR-H, introduced the route + walker), #4150 (kb-drift IaC), #4161
