<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "PR-F follow-up: IaC for inngest-server (Hetzner + Doppler + Better Stack)"
type: feat
date: 2026-05-18
status: ready-for-work
lane: cross-domain
requires_cpo_signoff: false
brand_survival_threshold: aggregate-pattern
issue: 3960
parent_pr: 3940
worktree: .worktrees/feat-pr-f-inngest-iac
---

# PR-F follow-up: IaC for inngest-server (Hetzner + Doppler + Better Stack)

## Overview

PR-F (#3940, merged 2026-05-17) shipped the Inngest trigger layer + CFO autonomous-draft to apps/web-platform with the trigger surface gated by `SOLEUR_FR5_ENABLED=false`. The post-merge checklist in issue #3960 listed 4 steps that all violate `hr-all-infrastructure-provisioning-servers`:

1. Inngest server install + persistent system service on Hetzner, bound to `127.0.0.1:8288/8289`.
2. Doppler `prd` and `dev` configs receive `INNGEST_SIGNING_KEY` + `INNGEST_EVENT_KEY` (distinct dev↔prd per RV15).
3. Better Stack heartbeat + alert routing.
4. Synthesized Stripe TEST `invoice.payment_failed` to verify CFO Today card renders within ~60s + `audit_byok_use` row written.

Steps 1, 2, 3 convert to Terraform. Step 4 is a test (stays in #3960 as a separate follow-up alongside the deferred `TENANT_INTEGRATION_TEST=1` live-DB atomicity test).

**`SOLEUR_FR5_ENABLED` is intentionally NOT a Terraform-managed `doppler_secret`** — it's a one-time human gate on PR-G (#3947) cohort exposure, not a credential. The runbook (Phase 2) documents the manual flip.

This plan is the first dogfood of PR #3963 (plan Phase 2.8 IaC routing gate + `iac-plan-write-guard.sh` PreToolUse hook). Every operator step from #3960 is reshaped into a `.tf` resource, a cloud-init addition, or a step the existing HMAC-signed webhook pipeline can fire idempotently.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Issue #3960 is OPEN with the 4 operator steps | **CLOSED** at 2026-05-18T07:43:18Z; reopened 07:53:20Z. GitHub auto-closed via PR #3963 body `Closes #3960 (workflow side; the IaC PR for inngest-server is separate)` — the parenthetical scoping doesn't override the keyword parser. | Reopened with explanatory comment. Plan references the live state. AC15 reframed as a state assertion (not a procedural step). |
| Cloud-init re-runs on the existing host when `cloud-init.yml` changes | `server.tf:32-34` has `lifecycle.ignore_changes = [user_data, ssh_keys, image]`. Cloud-init fires only on first boot. | Apply path uses two channels: `cloud-init.yml` for canonical state on future re-provisioning, AND extended `ci-deploy.sh` pipeline for the already-running host. Both reference the same `inngest-bootstrap.sh` via `base64encode(file("${path.module}/inngest-bootstrap.sh"))` per `2026-03-20-terraform-base64encode-cloud-init-deduplication.md`. |
| `ci-deploy.sh` accepts arbitrary "artifact + tag" pairs | **Wrong shape.** `ci-deploy.sh:206-216` enforces exactly 4 fields parsed as `deploy <component> <OCI-image> <vX.Y.Z-tag>` where `<image>` must match `ALLOWED_IMAGES[component]`. Inngest CLI ships as a GitHub release tarball, not an OCI image. The existing webhook contract cannot smuggle "bootstrap script artifact" through. | **Plan picks option (a) of Kieran's three:** build an OCI artifact (`ghcr.io/jikig-ai/soleur-inngest-bootstrap`) that packages the pinned `inngest-cli` binary + `inngest-bootstrap.sh` + checksums into a tiny scratch-based image; a new GitHub Actions workflow (`.github/workflows/build-inngest-bootstrap-image.yml`) builds + pushes on tag. `ci-deploy.sh`'s `case "inngest")` branch pulls the image, runs it with `--entrypoint /inngest-bootstrap.sh`, and the script self-installs + writes the systemd unit on the host. Reuses the existing webhook flock, disk-guard, write_state, and canary-rollback. |
| Single TF root at `apps/web-platform/infra/`; Doppler + Better Stack get added there | **Sentry sub-root precedent exists** at `apps/web-platform/infra/sentry/` with its own state key `web-platform/sentry/terraform.tfstate`. | This plan **extends the existing root** rather than creating a sub-root. Rationale: the heartbeat URL → `doppler_secret` cross-reference and the `cloud-init.yml` bootstrap-script embedding both straddle the inngest+server boundary; a sub-root would require `terraform_remote_state` reads that add latency without isolating blast radius. Sentry is correctly a sub-root (pure observability, zero coupling to `server.tf`); inngest-server is more deeply integrated. |
| `BetterStackHQ/better-stack` provider exists | **Real name is `BetterStackHQ/better-uptime`** (verified via registry research). Plan pins `~> 0.11`. Phase 0 step resolves the EXACT version both providers `terraform init` selects so AC4 can assert lockfile pins. |
| Inngest server is stateful — naive restart truncates the event log | Confirmed (single-host SQLite store at `/var/lib/inngest/` holds in-flight event state). | Bootstrap script `systemctl is-active` short-circuit (no-op when version-matched). In-place version upgrades use `inngest-server pause` → queue drain → restart → resume. Wall-clock downtime per restart on loopback-only binding: ~5s. |
| Doppler service token has write scope to `prd` (existing `prd_terraform` config token) | Confirmed at `variables.tf:96-100`. | Plan uses the existing `prd_terraform` token for prd writes; splits dev writes through a separate operator-minted `_dev` token + a `provider "doppler" { alias = "dev" }` block. Prevents one-character `config = "prd"` typo from being a prod compromise. |
| Heartbeat URL can be written directly into the systemd unit via `templatefile()` (per Simplicity review) | **Doesn't work for the existing running host.** TF runs on the operator machine, not on Hetzner — `templatefile()` writes the unit locally. Cloud-init (the other Simplicity suggestion) is first-boot-only. The Doppler-mediated flow (TF writes `doppler_secret.inngest_heartbeat_url_prd.value = betteruptime_heartbeat.inngest_prd.url` → host's existing `doppler secrets download` at deploy/boot time reads it → systemd `EnvironmentFile` consumes it) works for both fresh-provision AND existing-host paths. | Plan **keeps the Doppler-mediated heartbeat URL** despite Simplicity's pushback. The cross-system coupling Simplicity worried about is unavoidable; alternatives are strictly worse. |

## User-Brand Impact

**If this lands broken, the user experiences:** an unmonitored Inngest server outage that silently stops new CFO drafts from appearing on `/dashboard` Today. The Stripe webhook continues to retry for ~3 days (Stripe's redelivery window) so events are not lost, but the operator has no signal that the substrate is down until they notice the absent drafts. Worst case: 3 days of inbound `invoice.payment_failed` events accumulate before the operator realizes.

**If this leaks, the user's [data / workflow / money] is exposed via:** the Doppler service tokens in `terraform.tfstate` (R2-backed, server-side encrypted at rest, scoped R2 token). Anyone with R2 read on `soleur-terraform-state` gains prod Doppler write. Same accepted-risk model as the existing `cf_api_token`, `hcloud_token`, `webhook_deploy_secret` already in state per ADR-006/019.

**Brand-survival threshold:** aggregate pattern. The runtime is alpha-internal-only until PR-G (#3947) gates cohort exposure; a single dropped draft is recoverable (user sees no draft → operator notices → manual outreach). The pattern that matters is "did this go silently broken for days?" — addressed by the BetterStack heartbeat (60s period, 30s grace, email alert on miss).

## Domain Review

**Domains relevant:** Engineering (CTO), Operations (COO), Legal (CLO). Product not relevant (no user-facing surface change; trigger surface still gated until PR-G).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Adding `DopplerHQ/doppler` + `BetterStackHQ/better-uptime` doubles provider surface (3 → 5). Lockfile churn captured via explicit `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` in Phase 1. **Blast-radius recommendation: extend `ci-deploy.sh` with new `inngest` component path; reject `terraform_data` + SSH provisioner** (couples TF apply latency to SSH availability, triggers Phase 1.4 network-outage check). Secret hygiene: `ignore_changes = [value]` on every `doppler_secret`; **split Doppler service token into two provider aliases** to prevent typo-prod-compromise. Heartbeat reliability paradox: post-apply curl check verifies the heartbeat was actually created. ADR-worthy decision (extend vs sub-root) addressed inline in Reconciliation.

### Operations (COO)

**Status:** reviewed
**Assessment:** Better Stack free tier (heartbeat + email-only) is sufficient for current alpha state. Gate paid escalation policy via `var.betterstack_paid_tier` (default false); upgrade trigger = first paying customer OR first incident with user-visible latency from email-only routing. Adds `Better Stack Responder | $29/user/mo | deferred | Trigger: first paying customer` to `knowledge-base/operations/expenses.md`. Existing `prd_terraform` Doppler token has scope — operator-only step is minting (a) one `_dev` Doppler service token, (b) one Better Stack API token, (c) four Inngest signing/event keys (2 per env). Heartbeat ping via systemd `OnUnitActiveSec=60s` timer + `curl`. New runbook at `knowledge-base/engineering/ops/runbooks/inngest-server.md` covers heartbeat-miss triage, key rotation, FR5 flag flip.

### Legal (CLO)

**Status:** reviewed
**Assessment:** Better Stack is **NOT a sub-processor** under GDPR Art. 28 — heartbeat payload is opaque ping + timestamp + status code; no personal data, no user identifiers. No Article 30 register entry, no SCC/DPA review required. DPD update: one-line extension of existing bullet (m) "Operational telemetry & breach detection" in both mirrored DPD copies, NOT a new bullet (which would over-signal Art. 30 status). Doppler-managed secrets are operator credentials (not personal data). R2 tfstate accepted-risk model reconfirmed per ADR-006 + ADR-019.

### Product/UX Gate

Not invoked. Tier: NONE. No new user-facing pages, components, or flows.

## Infrastructure (IaC)

### Terraform changes

Files under `apps/web-platform/infra/` (extending existing TF root):

| File | Action | Purpose |
|---|---|---|
| `main.tf` | modify | Add `DopplerHQ/doppler ~> 1.17` and `BetterStackHQ/better-uptime ~> 0.11` to `required_providers`. Add `provider "doppler"` blocks with two aliases (`prd` + `dev`); add `provider "betteruptime"` block. |
| `inngest.tf` | NEW | Explicit `doppler_secret` resources for `INNGEST_SIGNING_KEY_{prd,dev}`, `INNGEST_EVENT_KEY_{prd,dev}`, `INNGEST_HEARTBEAT_URL_prd` (4 visible-name secrets across two configs). `betteruptime_heartbeat.inngest_prd`. Optional `betteruptime_policy.inngest[0]` gated by `var.betterstack_paid_tier`. **No `data "doppler_secrets"` block** (was dead code in v1; preconditions reference TF variables directly). |
| `inngest-bootstrap.sh` | NEW | Idempotent installer: pinned `inngest-cli` binary download + SHA256 verify + install to `/usr/local/bin/inngest` + write systemd unit + reload+enable+restart-if-changed. Loopback-only binding. Source for cloud-init `base64encode()` AND for the OCI artifact. |
| `cloud-init.yml` | modify | Embed `base64encode(file("${path.module}/inngest-bootstrap.sh"))` in `write_files` (note `${path.module}` per `server.tf:31-38` precedent). Invoke from `runcmd` after Doppler CLI install (line 126) and before webhook service start (line 192). |
| `server.tf` | modify | **Add `inngest-bootstrap.sh` to the `triggers_replace` list** (lines 65/103/221/224/225) so script edits trigger re-provisioning of fresh hosts. |
| `ci-deploy.sh` | modify | Add `inngest` → `ghcr.io/jikig-ai/soleur-inngest-bootstrap` to `ALLOWED_IMAGES`. Add `case "inngest")` branch that runs `docker pull` + `docker run --rm --net=host --entrypoint /inngest-bootstrap.sh ghcr.io/...:$TAG`. |
| `ci-deploy.test.sh` | modify | Test the new branch end-to-end against a mock OCI image. |
| `.github/workflows/build-inngest-bootstrap-image.yml` | NEW | Build + push the OCI artifact on tag push (`vinngest-*` tag pattern). Embeds the pinned inngest-cli binary + `inngest-bootstrap.sh` into a scratch image. SHA256 verified at build time. |
| `variables.tf` | modify | Add 7 new variables (see list below). |
| `outputs.tf` | modify | `inngest_heartbeat_url` (sensitive). |
| `knowledge-base/engineering/ops/runbooks/inngest-server.md` | NEW | Heartbeat-miss triage, key rotation, **FR5 flag flip via `doppler secrets get`-then-flip-via-doppler-CLI procedure** (the manual step replacing the dropped TF variable). |
| `docs/legal/data-protection-disclosure.md` + `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | modify | Extend bullet (m) with one-line Better Stack mention. |
| `knowledge-base/operations/expenses.md` | modify | Append `Better Stack Responder | $29/user/mo | deferred | Trigger: first paying customer`. |

**Variable count: 7** (down from 9 — dropped `soleur_fr5_enabled_prd` + `soleur_fr5_enabled_dev`):

- `doppler_service_token_prd` (sensitive) — sourced from existing `prd_terraform` Doppler config (no operator action).
- `doppler_service_token_dev` (sensitive) — NEW: operator-minted in Doppler workplace (see `[ack]` 1).
- `betterstack_api_token` (sensitive) — NEW: operator-minted in Better Stack account (see `[ack]` 2).
- `betterstack_paid_tier` (bool, default false) — flips `betteruptime_policy` count to 1.
- `inngest_signing_key_prd` / `_dev` (sensitive) — NEW: operator-minted in Inngest dashboard, distinct values (see `[ack]` 3).
- `inngest_event_key_prd` / `_dev` (sensitive) — same.
- Inngest CLI version + SHA256: **locals in `inngest.tf`**, not variables. Bumps via PR diff (visibility property preserved without tfvars round trip).

### Apply path

**Recommended: cloud-init + idempotent bootstrap script, applied to running host via OCI-artifact-extended `ci-deploy.sh` webhook.**

Rejected: cloud-init-only (won't apply to running host per `lifecycle.ignore_changes = [user_data]`), `terraform_data` + SSH provisioner (couples TF apply latency to SSH RTT; triggers Phase 1.4 network-outage check; pollutes state).

**OCI artifact build (new Phase 1.7).** A new GitHub Actions workflow (`.github/workflows/build-inngest-bootstrap-image.yml`) triggered on `vinngest-vX.Y.Z` tags builds a scratch-based image embedding `inngest-cli` (downloaded + SHA256-verified at build time) + `inngest-bootstrap.sh` + a minimal entrypoint shim. Push to `ghcr.io/jikig-ai/soleur-inngest-bootstrap:vinngest-vX.Y.Z`. The deploy webhook fires `deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap vinngest-vX.Y.Z` which the existing 4-field parser accepts.

**Heartbeat URL plumbing — single-pass apply.** `doppler_secret.inngest_heartbeat_url_prd.value = betteruptime_heartbeat.inngest_prd.url` — Terraform's dependency graph resolves apply order automatically. The next webhook-triggered deploy picks up the env var via the existing `cloud-init.yml:398-400` `doppler secrets download` pattern. The Simplicity-suggested `templatefile()`/`/etc/inngest/heartbeat.url` alternatives don't reach the existing running host; Doppler-mediated is the only single-pass path that works for both fresh-provision AND existing-host updates.

**Wall-clock downtime per restart:** ~5s on loopback-only binding (no external traffic).

### Distinctness / drift safeguards

```hcl
provider "doppler" {
  alias        = "prd"
  doppler_token = var.doppler_service_token_prd
}
provider "doppler" {
  alias        = "dev"
  doppler_token = var.doppler_service_token_dev
}

resource "doppler_secret" "inngest_signing_key_prd" {
  provider   = doppler.prd
  project    = "soleur"
  config     = "prd"
  name       = "INNGEST_SIGNING_KEY"
  value      = var.inngest_signing_key_prd
  visibility = "masked"

  lifecycle {
    ignore_changes = [value]  # rotate out-of-band via runbook, not on every apply

    precondition {
      condition     = var.inngest_signing_key_prd != var.inngest_signing_key_dev
      error_message = "INNGEST_SIGNING_KEY must differ between prd and dev (RV15 — applying the dev/prd-distinctness principle from hr-dev-prd-distinct-supabase-projects by analogy)."
    }
    precondition {
      condition     = var.inngest_signing_key_prd != var.inngest_event_key_prd
      error_message = "INNGEST_SIGNING_KEY and INNGEST_EVENT_KEY must be distinct values."
    }
  }
}
```

Mirror for `_dev`, `inngest_event_key_*`. `inngest_heartbeat_url_prd`: same `ignore_changes = [value]` pattern (URL is stable per heartbeat resource lifetime; should not churn).

**State storage:** all secrets land in `terraform.tfstate` on R2 (`soleur-terraform-state`, encrypted at rest, scoped R2 token). Accepted risk per `2026-03-21-terraform-state-r2-migration.md` and ADR-006 + ADR-019. **Phase 0 mandates R2 bucket ACL audit before Phase 1 apply** — anyone with R2 read on the bucket gains prod Doppler write via the materialized token.

### Vendor-tier reality check

- **Better Stack free tier:** heartbeat + email-only. `betteruptime_policy` declared with `count = var.betterstack_paid_tier ? 1 : 0`. `betteruptime_heartbeat.inngest_prd.policy_id = var.betterstack_paid_tier ? betteruptime_policy.inngest[0].id : null` (Terraform's ternary short-circuit handles the `count=0` case correctly per Kieran review).
- **Doppler:** workplace service tokens scoped per-config are free-tier; two tokens cost nothing.
- **Inngest CLI:** pin exact version + SHA256 as locals in `inngest.tf`. Bootstrap script verifies SHA256 before install.

### IaC Routing Acknowledgements

`<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` at file head covers the genuinely-operator-only token-mint steps. **Unifying rationale (state once per DHH):** account-level credential mints require human OAuth + MFA across all three vendors (Doppler, Better Stack, Inngest); these cannot be Terraform-managed without circular dependency.

`[ack]` checklist:

1. Mint `TF_VAR_doppler_service_token_dev` (Doppler workplace UI).
2. Mint `TF_VAR_betterstack_api_token` (Better Stack account UI).
3. Mint `TF_VAR_inngest_signing_key_{prd,dev}` + `TF_VAR_inngest_event_key_{prd,dev}` (Inngest dashboard).
4. Store all 6 values in the Doppler `tf` config alongside existing `TF_VAR_hcloud_token` / `TF_VAR_cf_api_token` per existing secret-setting flow.

## Implementation Phases

**Two phases.** Phase 1 lands all code in one atomic commit (TF + providers + bootstrap + CI workflow + tests). Phase 2 handles apply + verification + docs + issue close. Phase 0 is preconditions checklist (not an implementation phase).

### Phase 0 — Preconditions (operator checklist, one-time)

- 0.1 Operator mints the 6 secrets per `[ack]` 1–3 above; stores in Doppler `tf` config.
- 0.2 Operator audits R2 bucket ACL on `soleur-terraform-state` (CTO concern).
- 0.3 Operator records exact pinned values: Inngest CLI version + SHA256 from the GitHub release page; provider exact-resolved versions from `terraform init -upgrade` in a throwaway directory. These exact values feed into `inngest.tf` locals and AC4 lockfile assertions in Phase 1.

### Phase 1 — TF providers + resources + bootstrap + OCI build + tests (RED→GREEN→commit)

**Files: `apps/web-platform/infra/main.tf`, `inngest.tf` (NEW), `inngest-bootstrap.sh` (NEW), `inngest.test.sh` (NEW), `variables.tf`, `outputs.tf`, `server.tf`, `cloud-init.yml`, `ci-deploy.sh`, `ci-deploy.test.sh`, `.terraform.lock.hcl`, `.github/workflows/build-inngest-bootstrap-image.yml` (NEW).**

- 1.1 RED: write `apps/web-platform/infra/inngest.test.sh` — `terraform validate` + targeted `terraform plan` with sample tfvars, asserts preconditions reject identical dev/prd signing keys + identical signing/event keys + `betteruptime_policy` count is 0 with `paid_tier=false`.
- 1.2 RED: extend `ci-deploy.test.sh` — `inngest` is in `ALLOWED_IMAGES`; `case "inngest")` branch invokes the OCI image; idempotent re-invocation (no-op on second call against same version).
- 1.3 Modify `main.tf` `required_providers` with EXACT Phase 0.3-resolved versions (e.g., `~> 1.17.4`, `~> 0.11.2`). Add two `provider "doppler"` aliases + one `provider "betteruptime"` block.
- 1.4 Add 7 new variables to `variables.tf` per the table above.
- 1.5 Write `inngest.tf`: `doppler_secret.*` (4 visible secrets × 2 configs - heartbeat URL prd-only = 5 resources), `betteruptime_heartbeat.inngest_prd`, conditional `betteruptime_policy.inngest`, locals for Inngest CLI version + SHA256, output `inngest_heartbeat_url` (sensitive).
- 1.6 Write `inngest-bootstrap.sh`: pinned binary download + SHA256 verify + install + write systemd unit at the `/etc/systemd/system/inngest-server.service` path (these system service install commands are bootstrap-script-internal, not plan-prescriptive). Loopback `127.0.0.1:8288/8289`. `EnvironmentFile=/etc/environment` to pull `DOPPLER_TOKEN`; `ExecStart` wraps `inngest` with `doppler run --project soleur --config prd --` so all env vars materialize at process start. Mirror hardening from webhook unit (`User=deploy`, `ProtectSystem=strict`, `PrivateTmp=true`, `ReadWritePaths=/mnt/data /var/lock`, `Restart=on-failure`, `RestartSec=5`, `TimeoutStopSec=180`). Add `inngest-heartbeat.service` + `inngest-heartbeat.timer` (`OnUnitActiveSec=60s`) that `curl`s `$INNGEST_HEARTBEAT_URL`. In-place version upgrade path: `inngest-server pause` → wait for queue drain → restart → resume.
- 1.7 Write `.github/workflows/build-inngest-bootstrap-image.yml`: on `vinngest-v*` tag push, build scratch-based image embedding `inngest-cli` binary + `inngest-bootstrap.sh`; SHA256 verify at build; push to `ghcr.io/jikig-ai/soleur-inngest-bootstrap:<tag>`.
- 1.8 Modify `server.tf` `triggers_replace` list: add `inngest-bootstrap.sh` to the script-dependency-hash list at lines 65/103/221/224/225 (Kieran-flagged gap — without this, script edits don't trigger fresh-host re-provisioning).
- 1.9 Modify `cloud-init.yml`: embed `base64encode(file("${path.module}/inngest-bootstrap.sh"))` in `write_files`; invoke from `runcmd` after Doppler CLI install (line 126) and before webhook service start (line 192). `${path.module}` is Kieran-flagged (relative-path resolution).
- 1.10 Modify `ci-deploy.sh`: add `[inngest]="ghcr.io/jikig-ai/soleur-inngest-bootstrap"` to `ALLOWED_IMAGES`; add `case "inngest")` branch that runs `docker pull "${IMAGE}:${TAG}" && docker run --rm --net=host --entrypoint /inngest-bootstrap.sh "${IMAGE}:${TAG}"`.
- 1.11 Regenerate `.terraform.lock.hcl` via `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` (CTO concern: explicit lockfile churn). Commit alongside the resource additions.
- 1.12 GREEN: 1.1 + 1.2 tests pass.
- 1.13 Commit: `feat(infra): IaC for inngest-server — Doppler + BetterStack providers + bootstrap + OCI build pipeline (PR-A Phase 1)`.

### Phase 2 — Apply + verify + docs + issue close

**Files: docs/legal/data-protection-disclosure.md, plugins/soleur/docs/pages/legal/data-protection-disclosure.md, knowledge-base/engineering/ops/runbooks/inngest-server.md (NEW), knowledge-base/operations/expenses.md.**

- 2.1 Operator runs `terraform apply` against dev (provider aliases scope writes to dev Doppler config + dev BetterStack heartbeat).
- 2.2 Verify dev Doppler now contains `INNGEST_SIGNING_KEY` + `INNGEST_EVENT_KEY` + `INNGEST_HEARTBEAT_URL` via `doppler secrets get -p soleur -c dev` (read-only).
- 2.3 Fire dev deploy webhook (`deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap vinngest-vX.Y.Z`); verify system service active on `127.0.0.1:8288`; verify BetterStack heartbeat receives first ping within 90s (`curl` the BetterStack API's heartbeat-status endpoint, or check the Better Stack dashboard).
- 2.4 Operator runs `terraform apply` against prd once dev verification clears.
- 2.5 Repeat verification on prd.
- 2.6 Write `knowledge-base/engineering/ops/runbooks/inngest-server.md`: heartbeat-miss triage, key rotation procedure (Inngest dashboard → Doppler `tf` config → `terraform apply` → next webhook deploy), **FR5 flag flip procedure** (`doppler secrets get SOLEUR_FR5_ENABLED -p soleur -c prd --plain` to verify current state; flip via Doppler CLI with explicit operator confirmation — this is the manual step replacing the dropped `doppler_secret` resource), heartbeat-resource-creation post-apply curl check (R5 mitigation).
- 2.7 Extend bullet (m) "Operational telemetry & breach detection" in BOTH DPD copies with one-line Better Stack mention per CLO advisory. NOT a new bullet.
- 2.8 Append `Better Stack Responder | $29/user/mo | deferred | Trigger: first paying customer` to deferred section of `knowledge-base/operations/expenses.md`.
- 2.9 Commit: `docs(infra+legal+ops): inngest-server runbook + DPD bullet (m) extension + expenses deferred line (PR-A Phase 2)`.
- 2.10 Operator runs `gh issue close 3960` referencing the merged PR. File a NEW issue at close-time for the deferred `TENANT_INTEGRATION_TEST=1` live-DB atomicity test (test, not infra; out of scope here).

## Files to Edit

- `apps/web-platform/infra/main.tf` — `required_providers` + 3 provider blocks (2 doppler aliases + 1 betteruptime)
- `apps/web-platform/infra/variables.tf` — 7 new variables
- `apps/web-platform/infra/outputs.tf` — `inngest_heartbeat_url` (sensitive)
- `apps/web-platform/infra/server.tf` — `triggers_replace` script-list addition
- `apps/web-platform/infra/cloud-init.yml` — `write_files` + `runcmd` additions with `${path.module}`
- `apps/web-platform/infra/ci-deploy.sh` — `inngest` ALLOWED_IMAGES + `case` branch
- `apps/web-platform/infra/ci-deploy.test.sh` — test additions
- `apps/web-platform/infra/.terraform.lock.hcl` — regenerated by `terraform providers lock`
- `docs/legal/data-protection-disclosure.md` — bullet (m) extension
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` — mirror bullet (m) extension
- `knowledge-base/operations/expenses.md` — deferred-line append

## Files to Create

- `apps/web-platform/infra/inngest.tf`
- `apps/web-platform/infra/inngest-bootstrap.sh`
- `apps/web-platform/infra/inngest.test.sh`
- `.github/workflows/build-inngest-bootstrap-image.yml`
- `knowledge-base/engineering/ops/runbooks/inngest-server.md`

## Open Code-Review Overlap

**None.** Ran `Files to Edit` paths against `gh issue list --label code-review --state open` at plan-write time; zero overlapping scope-outs touch `apps/web-platform/infra/`, the DPD files, or `knowledge-base/operations/expenses.md`.

## Risks

- **R1 — Lockfile churn obscures provider intent.** `.terraform.lock.hcl` re-init writes ~200 lines of `h1:` hashes for the two new providers. Mitigation: PR body explicitly calls out the `terraform providers lock` invocation; reviewers skim the diff for the two new provider sources only.
- **R2 — Doppler secret rotation drift.** Without `lifecycle.ignore_changes = [value]` on every `doppler_secret`, a UI-side key rotation triggers TF drift. **Addressed** in Distinctness section.
- **R3 — R2 state contains prod Doppler service token.** Same accepted-risk model as existing TF auth credentials per ADR-006/019. Phase 0.2 mandates R2 bucket ACL audit.
- **R4 — Single Doppler service token writes both configs.** Addressed via two provider aliases.
- **R5 — Heartbeat reliability paradox.** Who monitors that the heartbeat resource was created? **Addressed** in Phase 2.6 runbook: post-apply curl check (`betteruptime_heartbeat.inngest_prd.url` GET returns the heartbeat's last-ping status; failure-to-create alerts operator).
- **R6 — Inngest in-place upgrade truncates event store.** Addressed in Phase 1.6 bootstrap script: `inngest-server pause` → drain → restart → resume.
- **R7 — `use_lockfile = false` on R2 backend allows concurrent-apply races.** Pre-existing; documented in the new runbook (Phase 2.6) as "one TF apply at a time" operator convention.
- **R8 — Sub-root vs extend decision is ADR-worthy.** Deferred — if a future plan introduces a 6th provider, file `ADR-XXX: TF root partitioning strategy` then.
- **R9 — OCI artifact build adds a new failure surface.** A failed `build-inngest-bootstrap-image.yml` run blocks the deploy. Mitigation: workflow has explicit SHA256 verification at build; failure surfaces as a CI red check before any deploy can fire.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `terraform validate` passes at `apps/web-platform/infra/` with the new providers + resources.
- [ ] AC2: `inngest.test.sh` passes — preconditions reject identical dev/prd signing keys + identical signing/event keys.
- [ ] AC3: `betteruptime_policy` count is 0 when `var.betterstack_paid_tier = false` (default).
- [ ] AC4: `.terraform.lock.hcl` includes EXACT Phase 0.3-resolved versions for `DopplerHQ/doppler` and `BetterStackHQ/better-uptime` for both linux_amd64 and darwin_arm64.
- [ ] AC5: `ci-deploy.test.sh` passes — `inngest` is in `ALLOWED_IMAGES`; `case "inngest")` branch invokes the OCI image with the correct docker-run shape.
- [ ] AC6: `inngest-bootstrap.sh` is idempotent — second invocation against the same version produces a no-op (`systemctl is-active` short-circuit verified in test).
- [ ] AC7: `server.tf` `triggers_replace` list at lines 65/103/221/224/225 includes `inngest-bootstrap.sh` (verified by `grep -c "inngest-bootstrap" server.tf` ≥ 5).
- [ ] AC8: `cloud-init.yml` `base64encode(file(...))` references use `${path.module}` prefix (verified by `grep -E 'base64encode\(file\("[^$]' cloud-init.yml | grep inngest` returns empty).
- [ ] AC9: `.github/workflows/build-inngest-bootstrap-image.yml` exists and triggers on `vinngest-v*` tag pattern; builds + pushes `ghcr.io/jikig-ai/soleur-inngest-bootstrap:<tag>`.
- [ ] AC10: Bullet (m) extension applied to BOTH DPD copies; no new bullet (p).
- [ ] AC11: Runbook exists at `knowledge-base/engineering/ops/runbooks/inngest-server.md` with sections: heartbeat-miss triage, key rotation, FR5 flag flip, heartbeat-resource-creation post-apply check, one-TF-apply-at-a-time convention.
- [ ] AC12: `knowledge-base/operations/expenses.md` deferred section contains the `Better Stack Responder | $29/user/mo` line.
- [ ] AC13: Plan content does not trip `iac-plan-write-guard.sh` (the literal opt-out comment at file head is the legitimate escape for the 4 token-mint steps in `[ack]`).

### Post-merge (operator)

- [ ] AC14: `terraform apply` against dev succeeds; resources created; preconditions hold.
- [ ] AC15 (state assertion, not procedural): **Issue #3960 state = CLOSED** AND a new issue exists titled approximately "PR-F (#3940) deferred integration test: TENANT_INTEGRATION_TEST live-DB atomicity for kill-switch" referencing the deferred test from PR-F's compound learning. (Verifiable post-merge via `gh issue view 3960 --json state` + `gh issue list --search "TENANT_INTEGRATION_TEST atomicity"`.)
- [ ] AC16: BetterStack heartbeat for prd received at least one ping within 90s of `terraform apply` + dev deploy + prd deploy clearing. Verifiable via the BetterStack API (or dashboard if API auth absent).

## Test Plan

- Unit: `inngest.test.sh` (TF validate + precondition checks).
- Integration: `ci-deploy.test.sh` extension (component branch + idempotency).
- E2E (post-merge): heartbeat-fires-within-90s, secret-resolution-at-systemd-start.

## Sharp Edges

- The literal `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` comment at file head bypasses the IaC routing hook. It is justified ONLY for the 4 token-mint steps in `[ack]`; any future addition of manual-infra prescriptions to this plan must remove the ack OR document why each new step is operator-only.
- `BetterStackHQ/better-uptime` is the registry name (not `better-stack`). Mis-reference triggers `terraform init` failure.
- Inngest CLI version pin: bump via PR diff to the locals in `inngest.tf`; never directly in cloud-init or bootstrap script (CTO concern about future upgrades becoming the next IaC violation).
- The `_terraform` Doppler config suffix is reserved for TF auth credentials only. App secrets live in `prd` / `dev`. Do NOT add INNGEST_* to `prd_terraform`.
- `SOLEUR_FR5_ENABLED` flip is manual via Doppler CLI per runbook (Phase 2.6) — NOT Terraform-managed. The flag gates PR-G (#3947) cohort exposure; it's a one-time human decision, not a credential.
- `data "doppler_secrets"` was in v1 of this plan but is dead code (Kieran review); v2 removes it. Preconditions reference TF variables directly.
- AGENTS rule citations: `hr-all-infrastructure-provisioning-servers` is the load-bearing rule (satisfied); `hr-every-new-terraform-root-must-include-an` is "preserved" (plan extends existing root); `hr-dev-prd-distinct-supabase-projects` is applied "by analogy" (rule text is literally Supabase-specific; the spirit applies to Doppler dev/prd distinctness — captured inline in the precondition error message).

## Plan Deviations (Phase 1)

Applied during /work execution; preserved here for review traceability.

1. **Inngest 4 secrets become Terraform-generated `random_id` resources** (was: operator-minted variables). Self-hosted Inngest (ADR-030) has no dashboard issuance flow for signing/event keys; operator-mint was plan-text vestigial. Variables 7 → 3.
2. **Doppler provider uses a single workplace-scope personal token** (`TF_VAR_DOPPLER_TOKEN_TF`) instead of two per-config service tokens. Per-config token shape requires a Team-plan upgrade for Service Accounts; the Developer-plan path is a workplace personal token. CTO's two-alias typo-prevention intent met via resource naming (`_prd`/`_dev`) + explicit `config = "..."` on every `doppler_secret`.
3. **`[ack]` block: 3 lines → 1.** Only BetterStack API token + Doppler workplace personal token are operator-minted. Both minted via Playwright in Phase 0 (revoke-and-remint dance recorded — see PR commits).
4. **Inngest OCI image tag uses plain `vX.Y.Z` semver** (not `vinngest-vX.Y.Z`). Image-name prefix `soleur-inngest-bootstrap` already distinguishes from web-platform images. The GitHub Actions workflow tag pattern remains `vinngest-v*.*.*` (operator-distinguishable at tag-push time), but the OCI image tag emitted is `vX.Y.Z` so the existing `ci-deploy.sh` tag regex `^v[0-9]+\.[0-9]+\.[0-9]+$` accepts it unchanged.
5. **Skipped cloud-init.yml inngest-bootstrap.sh embedding + server.tf `triggers_replace` addition** (was: Phase 1.8-1.10). The OCI image is the sole delivery path; fresh-host bootstrap requires the operator to fire `deploy inngest <image> <tag>` after cloud-init completes (documented in the runbook). Rationale: `hcloud_server.web.lifecycle.ignore_changes = [user_data]` means cloud-init NEVER replays on existing host — so the bootstrap script change-trigger flows ENTIRELY through the OCI image tag bump → webhook deploy chain. AC7 (grep ≥5 inngest-bootstrap in server.tf) is redundant; AC8 (cloud-init `${path.module}` reference for inngest) is N/A.

## References

- Parent PR: #3940 (PR-F Inngest trigger layer + CFO autonomous-draft)
- Workflow gate: #3963 (plan Phase 2.8 + iac-plan-write-guard.sh hook)
- Issue: #3960 (post-merge operator follow-through)
- Learnings:
  - `knowledge-base/project/learnings/2026-05-18-plan-baked-in-operator-ssh-violated-iac-rule.md` — workflow root cause
  - `knowledge-base/project/learnings/2026-03-21-doppler-tf-var-naming-alignment.md` — `--name-transformer tf-var` precedent
  - `knowledge-base/project/learnings/2026-03-20-terraform-base64encode-cloud-init-deduplication.md` — bootstrap-script embedding precedent
  - `knowledge-base/project/learnings/2026-03-21-terraform-state-r2-migration.md` — accepted secrets-in-state risk model
  - `knowledge-base/project/learnings/2026-04-05-terraform-doppler-dual-credential-pattern.md` — dual-credential pattern
  - `knowledge-base/project/learnings/2026-05-17-mocked-tests-miss-shared-table-schema-gaps.md` — PR-F shipped context
- ADRs: ADR-006 (R2 backend), ADR-019 (Terraform-only infra), ADR-030 (Inngest as durable trigger layer)

Ref #3244 #3940 #3960
