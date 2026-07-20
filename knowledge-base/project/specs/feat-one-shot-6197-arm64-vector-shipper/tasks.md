---
title: "Tasks — arm64 Vector shipper on the dedicated Inngest host"
issue: 6197
branch: feat-one-shot-6197-arm64-vector-shipper
lane: single-domain
plan: knowledge-base/project/plans/2026-07-08-chore-arm64-vector-shipper-inngest-host-plan.md
---

# Tasks — arm64 Vector journal→Better Stack shipper (#6197)

Derived from `2026-07-08-chore-arm64-vector-shipper-inngest-host-plan.md`. Phase order is
load-bearing: the isolation-check widening (1.x) must land in the same PR as the secret that
would otherwise trip it. All tasks ship in ONE atomic PR.

## Phase 0 — Preconditions
- [ ] 0.1 Re-verify the arm64 Vector SHA is still `365bab73244780083eb95b3e42161a9179f23a0811ffa6180f613c3af06ed8e6` (immutable release; mismatch = re-cut). `curl -fsSL https://packages.timber.io/vector/0.43.1/vector-0.43.1-aarch64-unknown-linux-musl.tar.gz | sha256sum`.
- [ ] 0.2 Confirm `vector_sha256_arm64` local does not yet exist in `vector.tf`.
- [ ] 0.3 IaC = **Approach B** (resolved at deepen-plan; Approach A leaks the full soleur/prd map into shared tfstate). Pre-provision gate: copy `BETTERSTACK_LOGS_TOKEN` into `soleur/prd_terraform` BEFORE merge (→ `TF_VAR_betterstack_logs_token`); verify read-only via `doppler secrets get`.

## Phase 1 — Boot isolation self-check widening (highest-risk; do first)
- [ ] 1.1 `cloud-init-inngest.yml:156` — add `BETTERSTACK_LOGS_TOKEN` as a TOP-LEVEL alternation member: `^(INNGEST_(SIGNING_KEY|EVENT_KEY|REDIS_PASSWORD|POSTGRES_URI|HEARTBEAT_URL)|BETTERSTACK_LOGS_TOKEN)$`. NOT nested inside `INNGEST_(…)` (P2-a boot-brick trap).
- [ ] 1.2 `cloud-init-inngest.yml:157` — raise the cardinality floor `-lt 4` → `-lt 5` (dark boot now: 3 TF keys + INNGEST_POSTGRES_URI + BETTERSTACK_LOGS_TOKEN).
- [ ] 1.3 Update the `:143-146` comment: dark 4→5, live 5→6; admission criterion = "names this host's runtime consumes" (P2-b); note deleting BETTERSTACK_LOGS_TOKEN post-cutover FATALs the whole control plane (P2-c).

## Phase 2 — Arch-parameterize the Vector install (`inngest-bootstrap.sh`)
- [ ] 2.1 Add `VECTOR_CLI_ARCH="${VECTOR_CLI_ARCH:-amd64}"` + `case amd64|arm64` validate (mirror `:53-56`).
- [ ] 2.2 Add arch→triple map: `amd64`→`x86_64-unknown-linux-musl`, `arm64`→`aarch64-unknown-linux-musl`.
- [ ] 2.3 `:477` — build `VECTOR_DOWNLOAD_URL` from `${vec_triple}` (drop hardcoded `x86_64`).
- [ ] 2.4 `:498` — extract path `"$tmp"/vector-${vec_triple}/bin/vector` (drop hardcoded `x86_64`).

## Phase 3 — Pin the arm64 SHA (`vector.tf`)
- [ ] 3.1 Add `vector_sha256_arm64 = "365bab73244780083eb95b3e42161a9179f23a0811ffa6180f613c3af06ed8e6"` local with verify-before-bump comment.

## Phase 4 — Un-defer Vector on the arm64 host
- [ ] 4.1 `cloud-init-inngest.yml:191-197` — rewrite the DEFERRED comment block to "wired (arm64 + isolated token)".
- [ ] 4.2 `cloud-init-inngest.yml` — stage `/tmp/vector.toml`: `docker cp soleur-inngest-bootstrap-extract:/vector.toml /tmp/vector.toml 2>/dev/null || true` (mirror `cloud-init.yml:659`).
- [ ] 4.3 `cloud-init-inngest.yml` — read image-env version: `VECTOR_CLI_VERSION=$(printf '%s\n' "$image_env" | grep '^VECTOR_CLI_VERSION=' | head -1 | cut -d= -f2-)`.
- [ ] 4.4 `cloud-init-inngest.yml:212` — replace empty `VECTOR_CLI_*` with `"VECTOR_CLI_VERSION=$VECTOR_CLI_VERSION" "VECTOR_CLI_SHA256=${vector_sha256_arm64}" "VECTOR_CLI_ARCH=arm64"`.
- [ ] 4.5 `inngest-host.tf:189` — pass `vector_sha256_arm64 = local.vector_sha256_arm64` into the templatefile vars.

## Phase 5 — Provision the Doppler secret (Approach B) + replace-dispatch + sweep guard suites
- [ ] 5.1 Add `variable "betterstack_logs_token" { type=string; sensitive=true }` (no default) + `doppler_secret.inngest_betterstack_logs_token` (`project="soleur-inngest"`, `config="prd"`, `value=var.betterstack_logs_token`, `ignore_changes=[value]`). File: append to `inngest-host.tf` or new `inngest-betterstack-token.tf`.
- [ ] 5.2 `plugins/soleur/test/terraform-target-parity.test.ts:454` — add `doppler_secret.inngest_betterstack_logs_token` to `OPERATOR_APPLIED_EXCLUSIONS` (THE test-passing entry; `stripDispatchJobs` strips the dispatch `-target`).
- [ ] 5.3 `apply-web-platform-infra.yml:1427` — add `-target='doppler_secret.inngest_betterstack_logs_token'` to the `inngest_host` job (for the apply).
- [ ] 5.4 `apply-web-platform-infra.yml` — add a NEW `inngest-host-replace` dispatch job (mirror `web_2_recreate` `:887+`, `terraform apply -replace='hcloud_server.inngest'`) + add `inngest-host-replace` to the `apply_target` options (`:96-100`).
- [ ] 5.5 New `tests/scripts/lib/inngest-host-replace-gate.sh` (mirror `web2-recreate-gate.sh`): permit `hcloud_server.inngest`+`hcloud_server_network.inngest`+`hcloud_volume_attachment.inngest_redis` replaces; FORBID `hcloud_volume.inngest_redis` deletion (Redis AOF).

## Phase 6 — Tests
- [ ] 6.1 `inngest-host.test.sh:95-97` — invert test 7 from "Vector deferred" to "Vector wired (arm64)": assert `vector_sha256_arm64` local + cloud-init `VECTOR_CLI_SHA256="${vector_sha256_arm64}"` + `VECTOR_CLI_ARCH=arm64` + `/tmp/vector.toml` staging (mirror test 5 shape).
- [ ] 6.2 Add assertion: `inngest-bootstrap.sh` maps `arm64`→`aarch64` for BOTH URL and extract path.
- [ ] 6.3 Add assertion: isolation regex includes `BETTERSTACK_LOGS_TOKEN` and floor is `-lt 5`.
- [ ] 6.4 `build-inngest-bootstrap-image.yml` / `validate-vector-config.yml` — extend the 64-hex validator to cover `vector_sha256_arm64`.
- [ ] 6.5 `bash apps/web-platform/infra/inngest-host.test.sh` → 0 failed.
- [ ] 6.6 `bun test plugins/soleur/test/terraform-target-parity.test.ts` → 0 failed.
- [ ] 6.7 `terraform validate` (init with R2 backend + `--name-transformer tf-var`); scoped `terraform plan -target=doppler_secret.inngest_betterstack_logs_token` shows pure CREATE.

## Phase 7 — ADR-100 amendment + C4
- [ ] 7.1 Amend `ADR-100-*.md` Phase-1 caveat (L192-199): mark Vector shipper resolved; reconcile "Sentry"→"Better Stack Logs"; note isolation allowlist now admits BETTERSTACK_LOGS_TOKEN (dark 4→5).
- [ ] 7.2 Read `model.c4` + `views.c4` + `spec.c4`; enumerate Better Stack Logs (external system) + dedicated Inngest host (container) + log-ship edge. Add the edge + `view include` if absent, else record "already modeled" with the checked actors/systems; run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Verification (pre-merge, per plan AC1-AC12)
- [ ] All 12 ACs green (see plan `## Acceptance Criteria`).

## Post-merge (all automatable via `gh` — no SSH)
- [ ] Dispatch token apply: `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host -f reason="#6197 BETTERSTACK_LOGS_TOKEN"` (pure-create, additive-guard-safe).
- [ ] Host provision/replace: if host not yet in tfstate (#6178 pending) it rides the additive `inngest-host` create; if already provisioned, dispatch `apply_target=inngest-host-replace`. Either way latent until fired; consumed by the Phase-2 cutover.
