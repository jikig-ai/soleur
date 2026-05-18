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

- [x] **0.1** (deviated) Mint 2 secrets via Playwright (down from 6): `TF_VAR_DOPPLER_TOKEN_TF` (workplace personal token at dashboard.doppler.com/workplace/.../tokens/personal) + `TF_VAR_BETTERSTACK_API_TOKEN` (global API token at betterstack.com/settings/global-api-tokens). Stored in Doppler `prd_terraform`. The 4 Inngest keys are now Terraform-generated via `random_id` (plan deviation #1).
- [ ] **0.2** Operator audits R2 bucket ACL on `soleur-terraform-state` (CTO concern: state contains Doppler personal token after Phase 1 apply). Deferred to operator pre-Phase-2.
- [x] **0.3** Recorded pinned values:
  - Inngest CLI: `v1.19.4` / SHA256 `d023b26659275fdbe9348b6518077ce1ea9906a449898e49ddced91bfc6fd757`.
  - Doppler provider: resolved `1.21.2` under `~> 1.21` constraint.
  - BetterStack provider: resolved `0.20.17` under `~> 0.20` constraint.

## Phase 1 — TF providers + resources + bootstrap + OCI build pipeline (RED → GREEN → commit)

### 1.A — RED tests

- [x] **1.1** Wrote `apps/web-platform/infra/inngest.test.sh` — grep + `terraform fmt -check` based assertions (lightweight; full `terraform validate` against live providers happens in Phase 2). Asserts 4 random_id, 5 doppler_secret, `betteruptime_heartbeat`, conditional `betteruptime_policy`, `signkey-prod-`/`signkey-test-` prefix distinctness, `lifecycle ignore_changes` on every secret, sensitive output.
- [x] **1.2** Extended `apps/web-platform/infra/ci-deploy.test.sh` — `inngest` is in `ALLOWED_IMAGES`; branch-routing test (happy path + image mismatch rejection). Idempotency is enforced inside `inngest-bootstrap.sh` via systemctl is-active + version-file match (verified inline by reading the script; full end-to-end idempotency test deferred — would require a docker-in-test harness).
- [x] **1.3** Tests confirmed GREEN: 29/29 inngest.test.sh + 71/71 ci-deploy.test.sh.

### 1.B — Terraform additions

- [x] **1.4** Modified `apps/web-platform/infra/main.tf` `required_providers` (added `DopplerHQ/doppler ~> 1.21`, `BetterStackHQ/better-uptime ~> 0.20` — Phase 0.3-resolved). Added ONE `provider "doppler"` block + one `provider "betteruptime"` block (plan deviation #2: single workplace-scope token instead of two per-config aliases).
- [x] **1.5** Added 3 new variables to `apps/web-platform/infra/variables.tf` (down from 7 per plan deviation #1): `doppler_token_tf` (sensitive), `betterstack_api_token` (sensitive), `betterstack_paid_tier` (bool, default false).
- [x] **1.6** Wrote `apps/web-platform/infra/inngest.tf`:
  - 4 `random_id` resources (Inngest signing/event × prd/dev, `byte_length = 32`) — plan deviation #1.
  - 5 explicit `doppler_secret` resources with `lifecycle.ignore_changes = [value]`.
  - `betteruptime_heartbeat.inngest_prd` (period 60s, grace 30s, email=true).
  - `betteruptime_policy.inngest` with `count = var.betterstack_paid_tier ? 1 : 0`.
  - `locals { inngest_cli_version = "v1.19.4"; inngest_cli_sha256 = "d023b26659275fdbe9348b6518077ce1ea9906a449898e49ddced91bfc6fd757" }`.
- [x] **1.7** Added `output "inngest_heartbeat_url"` (sensitive=true) to `apps/web-platform/infra/outputs.tf`.

### 1.C — Bootstrap script + cloud-init + server.tf triggers

- [x] **1.8** Wrote `apps/web-platform/infra/inngest-bootstrap.sh`:
  - Pinned binary download + SHA256 verify (versions injected via `INNGEST_CLI_VERSION` / `INNGEST_CLI_SHA256` env at OCI build OR cloud-init substitution).
  - Writes `/etc/systemd/system/inngest-server.service` (mirrors webhook.service hardening: User=deploy, ProtectSystem=strict, PrivateTmp, ReadWritePaths).
  - Loopback `127.0.0.1:8288/8289`. ExecStart wraps `inngest start` with `doppler run --project soleur --config prd --`.
  - `inngest-heartbeat.service` + `.timer` (OnUnitActiveSec=60s).
  - In-place upgrade path: pause → drain (2s) → restart → resume.
  - Idempotency: `systemctl is-active inngest-server.service` + version-file match short-circuits.
- [~] **1.9** **Skipped per plan deviation #5** — OCI image is the sole delivery path. `triggers_replace` would be no-op since the script doesn't get provisioned to the host filesystem.
- [~] **1.10** **Skipped per plan deviation #5** — same rationale. Fresh-host bootstrap requires `deploy inngest <image> <tag>` after cloud-init completes (documented in Phase 2.6 runbook).

### 1.D — ci-deploy.sh + OCI build workflow

- [x] **1.11** Modified `apps/web-platform/infra/ci-deploy.sh`:
  - Added `[inngest]="ghcr.io/jikig-ai/soleur-inngest-bootstrap"` to `ALLOWED_IMAGES`.
  - Added `case "inngest")` branch: `docker pull "$IMAGE:$TAG"` + `docker run --rm --net=host --pid=host -v /etc/systemd/system -v /usr/local/bin -v /var/lib/inngest -v /var/run/dbus -v /etc/default --entrypoint /inngest-bootstrap.sh "$IMAGE:$TAG"`. Reuses existing flock + disk-guard + write_state.
- [x] **1.12** Wrote `.github/workflows/build-inngest-bootstrap-image.yml`:
  - Trigger: `push` on `vinngest-v*.*.*` tag pattern + `workflow_dispatch`.
  - Hardened against workflow-injection (untrusted inputs through `env:` vars, validated with regex).
  - Build-time SHA256 verify of the inngest-cli binary against `inngest.tf` locals (source of truth).
  - Push to `ghcr.io/jikig-ai/soleur-inngest-bootstrap:vX.Y.Z` (plan deviation #4: image tag is plain semver, accepted by existing ci-deploy.sh tag regex).

### 1.E — Lockfile + GREEN + commit

- [x] **1.13** Regenerated `apps/web-platform/infra/.terraform.lock.hcl` via `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`.
- [x] **1.14** Tests GREEN: 29/29 inngest.test.sh + 71/71 ci-deploy.test.sh + `terraform validate` success.
- [x] **1.15** Commit Phase 1 atomically: `feat(infra): IaC for inngest-server — Doppler + BetterStack providers + bootstrap + OCI build pipeline (PR-A Phase 1)`.

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
