---
title: "PR-F follow-up: IaC for inngest-server — tasks"
plan: knowledge-base/project/plans/2026-05-18-feat-pr-f-inngest-iac-plan.md
lane: cross-domain
issue: 3960
parent_pr: 3940
---

# Tasks — PR-F IaC for inngest-server

Derived from `2026-05-18-feat-pr-f-inngest-iac-plan.md`. Two phases (plan v2 collapsed Phase 4 docs into Phase 2). Phase 0 is operator checklist (one-time, no code).

## Phase 0 — Preconditions (operator, one-time)

- [ ] **0.1** Operator mints the 6 secrets per `[ack]` 1–3 in plan; stores in Doppler `tf` config: `TF_VAR_doppler_service_token_dev`, `TF_VAR_betterstack_api_token`, `TF_VAR_inngest_signing_key_{prd,dev}`, `TF_VAR_inngest_event_key_{prd,dev}`.
- [ ] **0.2** Operator audits R2 bucket ACL on `soleur-terraform-state` (CTO concern: state contains Doppler service token after Phase 1 apply).
- [ ] **0.3** Record exact pinned values:
  - Inngest CLI version + SHA256 from `https://github.com/inngest/inngest/releases` for the chosen `vX.Y.Z`.
  - Provider EXACT-resolved versions: in a throwaway dir, write a minimal `main.tf` with `DopplerHQ/doppler ~> 1.17` + `BetterStackHQ/better-uptime ~> 0.11`; run `terraform init`; capture the exact resolved version from `.terraform.lock.hcl`. These exact values feed Phase 1.3 (provider pins) and AC4 (lockfile assertion).

## Phase 1 — TF providers + resources + bootstrap + OCI build pipeline (RED → GREEN → commit)

### 1.A — RED tests

- [ ] **1.1** Write `apps/web-platform/infra/inngest.test.sh` — `terraform validate` + targeted `terraform plan` with sample tfvars. Asserts:
  - Precondition rejects `var.inngest_signing_key_prd == var.inngest_signing_key_dev` (RV15).
  - Precondition rejects `var.inngest_signing_key_prd == var.inngest_event_key_prd`.
  - `betteruptime_policy` count is 0 when `var.betterstack_paid_tier = false`.
- [ ] **1.2** Extend `apps/web-platform/infra/ci-deploy.test.sh` — `inngest` is in `ALLOWED_IMAGES`; `case "inngest")` branch invokes `docker pull` + `docker run --rm --net=host --entrypoint /inngest-bootstrap.sh ghcr.io/jikig-ai/soleur-inngest-bootstrap:$TAG`; idempotent re-invocation (`systemctl is-active` short-circuits second call).
- [ ] **1.3** Run tests → confirm RED.

### 1.B — Terraform additions

- [ ] **1.4** Modify `apps/web-platform/infra/main.tf` `required_providers` to add `DopplerHQ/doppler` and `BetterStackHQ/better-uptime` pinned to EXACT Phase 0.3-resolved versions (e.g., `~> 1.17.4`, `~> 0.11.2`). Add two `provider "doppler"` aliases (`prd` + `dev`) and one `provider "betteruptime"` block.
- [ ] **1.5** Add 7 new variables to `apps/web-platform/infra/variables.tf` (sensitive where applicable): `doppler_service_token_prd`, `doppler_service_token_dev`, `betterstack_api_token`, `betterstack_paid_tier` (bool, default false), `inngest_signing_key_prd`, `inngest_signing_key_dev`, `inngest_event_key_prd`, `inngest_event_key_dev`.
- [ ] **1.6** Write `apps/web-platform/infra/inngest.tf`:
  - 5 explicit `doppler_secret` resources (`inngest_signing_key_{prd,dev}`, `inngest_event_key_{prd,dev}`, `inngest_heartbeat_url_prd`). Each `lifecycle.ignore_changes = [value]`; preconditions per Distinctness section.
  - `betteruptime_heartbeat.inngest_prd` (period 60s, grace 30s, email=true).
  - `betteruptime_policy.inngest` with `count = var.betterstack_paid_tier ? 1 : 0`.
  - `betteruptime_heartbeat.inngest_prd.policy_id = var.betterstack_paid_tier ? betteruptime_policy.inngest[0].id : null`.
  - `locals { inngest_cli_version = "vX.Y.Z"; inngest_cli_sha256 = "<hash>" }` (NOT variables — bump via PR diff per DHH/Simplicity discussion).
- [ ] **1.7** Add `output "inngest_heartbeat_url"` (sensitive) in `apps/web-platform/infra/outputs.tf`.

### 1.C — Bootstrap script + cloud-init + server.tf triggers

- [ ] **1.8** Write `apps/web-platform/infra/inngest-bootstrap.sh`:
  - Pinned binary download from GitHub releases + SHA256 verify.
  - Install to `/usr/local/bin/inngest`; chmod +x.
  - Write `/etc/systemd/system/inngest-server.service` (system-service-install commands are bootstrap-script-internal). Mirror hardening from existing `webhook.service` at `cloud-init.yml:183-208`.
  - Loopback-only binding `127.0.0.1:8288/8289`.
  - `EnvironmentFile=/etc/environment`; `ExecStart` wraps `inngest` with `doppler run --project soleur --config prd --`.
  - Write `/etc/systemd/system/inngest-heartbeat.service` + `.timer` (`OnUnitActiveSec=60s`) that `curl`s `$INNGEST_HEARTBEAT_URL`.
  - In-place upgrade path: `inngest-server pause` → wait for queue drain → restart → resume.
  - Idempotency: `systemctl is-active inngest-server` + version check short-circuits no-op on second invocation against same version.
- [ ] **1.9** Modify `apps/web-platform/infra/server.tf` — add `inngest-bootstrap.sh` to the `triggers_replace` script-dependency hash at lines 65/103/221/224/225 (Kieran-flagged gap). Verify by `grep -c "inngest-bootstrap" server.tf` returns ≥ 5.
- [ ] **1.10** Modify `apps/web-platform/infra/cloud-init.yml`:
  - `write_files`: embed `base64encode(file("${path.module}/inngest-bootstrap.sh"))` (the `${path.module}` prefix is Kieran-flagged; matches `server.tf:31-38` precedent).
  - `runcmd`: invoke the embedded script after the Doppler CLI install (line 126) and before webhook service start (line 192).

### 1.D — ci-deploy.sh + OCI build workflow

- [ ] **1.11** Modify `apps/web-platform/infra/ci-deploy.sh`:
  - Add `[inngest]="ghcr.io/jikig-ai/soleur-inngest-bootstrap"` to `ALLOWED_IMAGES` map.
  - Add `case "inngest")` branch: `docker pull "${IMAGE}:${TAG}" && docker run --rm --net=host --entrypoint /inngest-bootstrap.sh "${IMAGE}:${TAG}"`. Reuses existing flock + disk-guard + write_state + canary-rollback.
- [ ] **1.12** Write `.github/workflows/build-inngest-bootstrap-image.yml`:
  - Trigger: `push` on `vinngest-v*` tag pattern.
  - Build scratch-based image embedding pinned `inngest-cli` binary + `inngest-bootstrap.sh`.
  - SHA256 verify the inngest-cli binary at build time (use Phase 0.3 recorded value).
  - Push to `ghcr.io/jikig-ai/soleur-inngest-bootstrap:<tag>`.

### 1.E — Lockfile + GREEN + commit

- [ ] **1.13** Regenerate `apps/web-platform/infra/.terraform.lock.hcl` via `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` (CTO concern: explicit lockfile churn).
- [ ] **1.14** Run 1.1 + 1.2 tests → confirm GREEN.
- [ ] **1.15** Commit Phase 1 atomically: `feat(infra): IaC for inngest-server — Doppler + BetterStack providers + bootstrap + OCI build pipeline (PR-A Phase 1)`.

## Phase 2 — Apply + verify + docs + close

### 2.A — Apply

- [ ] **2.1** Operator runs `terraform apply` against dev (apply targets dev Doppler config + dev BetterStack heartbeat via provider aliases).
- [ ] **2.2** Verify dev: `doppler secrets get INNGEST_SIGNING_KEY -p soleur -c dev --plain` returns the expected value (read-only check); same for `INNGEST_EVENT_KEY` and `INNGEST_HEARTBEAT_URL`.
- [ ] **2.3** Fire dev deploy webhook: `deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap vinngest-vX.Y.Z`. Verify system service active on `127.0.0.1:8288`; verify BetterStack heartbeat receives first ping within 90s.
- [ ] **2.4** Operator runs `terraform apply` against prd once dev verification clears.
- [ ] **2.5** Repeat 2.2 + 2.3 verification on prd.

### 2.B — Docs

- [ ] **2.6** Write `knowledge-base/engineering/ops/runbooks/inngest-server.md` covering:
  - Heartbeat-miss triage steps.
  - Key rotation: Inngest dashboard → Doppler `tf` config → `terraform apply` → next webhook deploy.
  - **FR5 flag flip procedure** (the manual step replacing the dropped `doppler_secret` resource): `doppler secrets get SOLEUR_FR5_ENABLED -p soleur -c prd --plain` to verify current; flip via Doppler CLI with explicit operator confirmation.
  - Post-apply heartbeat-resource-creation verification curl (R5 mitigation).
  - "One TF apply at a time" operator convention (R7 mitigation).
- [ ] **2.7** Extend bullet (m) "Operational telemetry & breach detection" in BOTH DPD copies (`docs/legal/data-protection-disclosure.md` + `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`) with one-line Better Stack mention per CLO advisory. NOT a new bullet.
- [ ] **2.8** Append `Better Stack Responder | $29/user/mo | deferred | Trigger: first paying customer` to deferred section of `knowledge-base/operations/expenses.md`.
- [ ] **2.9** Commit Phase 2 docs: `docs(infra+legal+ops): inngest-server runbook + DPD bullet (m) extension + expenses deferred line (PR-A Phase 2)`.

### 2.C — Issue close + deferred-test follow-up

- [ ] **2.10** Operator runs `gh issue close 3960` referencing the merged PR.
- [ ] **2.11** File a NEW issue at close-time titled "PR-F (#3940) deferred integration test: TENANT_INTEGRATION_TEST live-DB atomicity for kill-switch" — the deferred test is out of scope for this IaC PR.

## Acceptance Criteria Map

| AC | Task |
|---|---|
| AC1 | 1.14 |
| AC2 | 1.1 + 1.14 |
| AC3 | 1.1 + 1.14 |
| AC4 | 1.13 |
| AC5 | 1.2 + 1.14 |
| AC6 | 1.8 (idempotency) + 1.2 |
| AC7 | 1.9 |
| AC8 | 1.10 |
| AC9 | 1.12 |
| AC10 | 2.7 |
| AC11 | 2.6 |
| AC12 | 2.8 |
| AC13 | plan file head `<!-- iac-routing-ack ... -->` comment |
| AC14 | 2.1 + 2.4 |
| AC15 | 2.10 + 2.11 |
| AC16 | 2.3 + 2.5 |
