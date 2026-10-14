---
title: "chore(infra): wire arm64 Vector journal→Better Stack shipper on the dedicated Inngest host"
issue: 6197
branch: feat-one-shot-6197-arm64-vector-shipper
type: chore
lane: single-domain
brand_survival_threshold: none
date: 2026-07-08
related: [6178, 6180, 4273, 5526]
adr: ADR-100 (amend — Phase-1 Vector caveat resolved)
---

# 🔧 chore(infra): arm64 Vector journal→Better Stack shipper on the dedicated Inngest host

## Enhancement Summary

**Deepened on:** 2026-07-08 | **Passes:** codebase verification (arm64 SHA live-probe, apply-path trace, parity-test) + architecture-strategist + security-sentinel review agents.

### Key improvements from deepen-plan
1. **Apply-path correction (P0, both agents).** The dedicated-inngest resources are NOT push-auto-applied — they ride `workflow_dispatch` jobs. The `doppler_secret` (pure create) is dispatch-applied via `apply_target=inngest-host`. The cloud-init force-replace is BLOCKED by that job's additive-only destroy-guard, so the plan now adds a NEW `inngest-host-replace` dispatch (web-2-recreate pattern, preserving the Redis AOF volume) — with a sequencing disambiguation (host-not-yet-provisioned rides the additive create; #6178 is OPEN). Post-merge is a `gh workflow run` dispatch, not "none required".
2. **IaC flipped A→B (P1, both agents).** Approach A (`data.doppler_secrets` mirror) would leak the entire ~116-secret `soleur/prd` map into SHARED tfstate — the inverse of the isolation thesis. Switched to Approach B (`var.betterstack_logs_token` from `prd_terraform`); only the one token enters state.
3. **Guard-suite sweep (P1).** The load-bearing parity registration is `OPERATOR_APPLIED_EXCLUSIONS` (the test's `stripDispatchJobs` strips the dispatch `-target`, so the workflow line alone doesn't satisfy coverage). Both entries + the new gate script added to Files-to-Edit + ACs + Sharp Edges.
4. **Isolation self-check** validated: floor 4→5, top-level-alternation regex (the P2-a grouping trap → boot-brick), admission-criterion comment (P2-b), delete-bricks-control-plane note (P2-c). **Live-verified arm64 SHA** `365bab73…8e6`; provider pin `DopplerHQ/doppler 1.21.2`.

### New considerations discovered
- No existing inngest-host replace path (the `inngest_host` dispatch is additive-only; `cutover-inngest.yml` is webhook-only, no terraform) — a new `-replace` dispatch + scoped gate must be built, mirroring `web-2-recreate`.
- Sink prose drift: issue title + ADR-100 say "Sentry"; the real sink is Better Stack Logs — reconciled in the ADR amendment.
- The floor-5 change couples control-plane liveness to the log token: deleting `BETTERSTACK_LOGS_TOKEN` post-cutover would FATAL the whole bootstrap (acceptable on a DARK host, documented in the isolation comment).

## Overview

The dedicated Inngest host (`cax11`, **arm64**, `10.0.1.40`) currently runs with the
Vector journald→Better Stack Logs shipper **deferred** (issue #6197, tracked under the
ADR-100 host-extraction / #6178). The single `inngest-bootstrap.sh` installs both the
Inngest CLI and Vector, but the **Inngest CLI install is already arch-parameterized**
(`INNGEST_CLI_ARCH`, `amd64|arm64`) while the **Vector install is hardcoded x86_64**.
The arm64 host therefore boots with empty `VECTOR_CLI_*` (skips the install) and does
not stage `/etc/vector/vector.toml`.

This plan mirrors the existing, proven Inngest-CLI arm64 pattern onto Vector so the arm64
host ships journald + host_metrics to Better Stack Logs before the Phase-2 cutover, closing
the observability gap ahead of the Phase-3 web-host-Inngest decommission.

**Five concrete pieces (all mirror an existing precedent — no novel mechanism):**

1. **Arch-parameterize the Vector install** in `inngest-bootstrap.sh` (mirror the Inngest CLI `INNGEST_CLI_ARCH` pattern): new `VECTOR_CLI_ARCH="${VECTOR_CLI_ARCH:-amd64}"` (default preserves the amd64 web host — cross-consumer edit, `hr-type-widening-cross-consumer-grep`), arch→target-triple mapping (`amd64`→`x86_64-unknown-linux-musl`, `arm64`→`aarch64-unknown-linux-musl` — note Vector's `aarch64` naming ≠ Inngest's `arm64`), applied to BOTH the download URL (`:477`) and the tarball extract path (`:498`).
2. **Pin the arm64 Vector SHA** as a `vector_sha256_arm64` local in `vector.tf` (mirror `inngest.tf:36 inngest_cli_sha256_arm64`). Verified value below.
3. **Stop deferring Vector on the arm64 host** in `cloud-init-inngest.yml`: stage `/tmp/vector.toml` (docker-cp from the OCI image, same as the web host), pass non-empty `VECTOR_CLI_VERSION` (from the image env, arch-independent) + `VECTOR_CLI_SHA256=${vector_sha256_arm64}` (override, mirror the Inngest-CLI SHA override at `:205`) + `VECTOR_CLI_ARCH=arm64`.
4. **Provision `BETTERSTACK_LOGS_TOKEN` into the isolated `soleur-inngest/prd` Doppler project** (it currently lives only in `soleur/prd`) — IaC via a `doppler_secret` mirror. See `## Infrastructure (IaC)`.
5. **Widen the boot isolation self-check** (`cloud-init-inngest.yml:156-157`) to admit `BETTERSTACK_LOGS_TOKEN` — **without this the host FATALs at boot** ("boot credential not isolated") the moment step 4 lands. This is the single highest-risk edit in the plan.

The Vector systemd unit's `@@DOPPLER_PROJECT@@` templating (`inngest-bootstrap.sh:535,558-560`) is **already in place** (landed under #6178 as load-bearing for this follow-up) — no unit change is needed.

**Verified arm64 Vector artifact (plan-time live probe, 2026-07-08):**
```
URL:  https://packages.timber.io/vector/0.43.1/vector-0.43.1-aarch64-unknown-linux-musl.tar.gz
SHA256: 365bab73244780083eb95b3e42161a9179f23a0811ffa6180f613c3af06ed8e6
size:   44087833 bytes
extract path: vector-aarch64-unknown-linux-musl/bin/vector
```

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #6197 / ADR-100 prose) | Reality (codebase, verified) | Plan response |
| --- | --- | --- |
| "journal→**Sentry** shipper" (issue title, ADR-100 L192/L198) | The actual Vector sink is **Better Stack Logs** (`vector.toml:377` `Bearer ${BETTERSTACK_LOGS_TOKEN}`, `:372` `s2457081.eu-fsn-3.betterstackdata.com`). Vector pivoted Sentry→Better Stack in #4273/#5526. | Use **Better Stack Logs** as the target throughout. Reconcile the stale "Sentry" prose in the ADR-100 amendment (`## Architecture Decision`). |
| "Vector systemd unit is already templated to `@@DOPPLER_PROJECT@@`, so no unit change is needed" | Confirmed — `inngest-bootstrap.sh:535` (ExecStart) + `:558-560` (bash param-expansion render). | No unit change. Only the binary/URL/SHA + `/tmp/vector.toml` + the Doppler secret. |
| "download URL is pinned x86_64; needs aarch64 build + pinned arm64 SHA + checksum override" | Confirmed `:477` (URL) **and** `:498` (extract path) both hardcode `x86_64-unknown-linux-musl`. | Both sites arch-parameterized via `VECTOR_CLI_ARCH`. |
| "`BETTERSTACK_LOGS_TOKEN` must be provisioned into `soleur-inngest`" | Confirmed — token lives only in `soleur/prd`; `soleur-inngest` is a distinct TF-managed project (`inngest-host.tf:80-123`). **Not mentioned in the issue:** the boot isolation self-check (`cloud-init-inngest.yml:156-157`) will FATAL unless its allowlist regex + cardinality floor are widened for the new token. | Widen the isolation check (step 5) — the load-bearing addition the issue omits. |
| Premise: blockers #6178 open, PR #6180 (Phase-1 IaC) tracked | #6178 OPEN (host extraction). ADR-100 exists and explicitly tracks this as the deferred Phase-1 caveat. | Premises hold; this plan is the tracked follow-up. |

## User-Brand Impact

**If this lands broken, the user experiences:** the dedicated Inngest host fails to boot
(the isolation self-check FATALs) at its next re-provision, OR Vector fails to install/start
and the arm64 host silently ships no logs — an observability blind spot on what becomes the
sole Inngest control plane at Phase-2 cutover. The host is **DARK/inert in Phase 1** (no prod
crons), so a broken bootstrap here does not take down a live control plane; it is caught by
`inngest-host.test.sh` at CI and by the deploy-status endpoint before cutover.

**If this leaks, the user's data is exposed via:** `BETTERSTACK_LOGS_TOKEN` is a **write-only
log-ingest token** (24 chars) to a Better Stack Logs source — it grants no read access to any
end-user data and no lateral movement. It is landed only into the isolated `soleur-inngest/prd`
project resolvable by a host-scoped read-only token. Shipped journald is already PII-scrubbed
by the Vector VRL (`vector.toml`, `vector-pii-scrub.test.sh`).

**Brand-survival threshold:** `none` — reason: operator-internal observability infrastructure on
a DARK/inert arm64 host with no end-user data surface; worst case (bootstrap FATAL or no-ship) is
caught pre-cutover by the arm64 host test suite + the deploy-status endpoint, and the shipped
logs are already PII-scrubbed. Diff touches a sensitive path (infra/secrets), so this explicit
`threshold: none` scope-out bullet is required by preflight Check 6.

## Implementation Phases

Phase order is load-bearing (`2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`):
the isolation-check widening (Phase 1) must land in the same PR as — and is read before — the
secret that would otherwise trip it (Phase 4). All changes ship in one atomic PR; the phases are
the TDD/read order, not separate merges.

### Phase 0 — Preconditions (verify at /work start)
- Confirm the arm64 SHA local is absent before adding it.
- Confirm the DopplerHQ/doppler provider version in `main.tf` exposes the mechanism chosen in `## Infrastructure (IaC)` (either a `doppler_secrets` data source or a `doppler_secret` value from a `prd_terraform` var) — see IaC section for the decision + fallback.
- Re-verify the arm64 SHA is still `365bab73…8e6` (Vector releases are immutable; a mismatch means the release was re-cut).

### Phase 1 — Widen the boot isolation self-check (highest-risk; do first)
`cloud-init-inngest.yml:156-157` + the explanatory comment `:143-146`:
- `:156` regex — add `BETTERSTACK_LOGS_TOKEN` to the allowlist alternation:
  - before: `grep -Ec '^INNGEST_(SIGNING_KEY|EVENT_KEY|REDIS_PASSWORD|POSTGRES_URI|HEARTBEAT_URL)$'`
  - after:  `grep -Ec '^(INNGEST_(SIGNING_KEY|EVENT_KEY|REDIS_PASSWORD|POSTGRES_URI|HEARTBEAT_URL)|BETTERSTACK_LOGS_TOKEN)$'`
- **Grouping trap (security-review P2-a — boot-brick risk):** `BETTERSTACK_LOGS_TOKEN` MUST be a TOP-LEVEL alternation member (`^(INNGEST_(…)|BETTERSTACK_LOGS_TOKEN)$`), NOT appended inside the `INNGEST_(…)` group. If nested, the anchored regex matches `INNGEST_BETTERSTACK_LOGS_TOKEN` and fails to match a bare `BETTERSTACK_LOGS_TOKEN` → `n_inngest=4, n_total=5` → identity clause FATALs → boot brick.
- `:157` cardinality floor — dark-boot count rises 4 → **5** (3 TF keys + `INNGEST_POSTGRES_URI` + `BETTERSTACK_LOGS_TOKEN`; `INNGEST_HEARTBEAT_URL` set only at cutover → 6 live). Change `-lt 4` → `-lt 5` (a floor accepts 6-live; correctly FATALs a 4-secret under-provisioned boot).
- Update the `:143-146` comment: dark 4→5, live 5→6; state the admission criterion is **"names this host's runtime consumes"** (not `INNGEST_`-prefixed — P2-b); note that DELETING `BETTERSTACK_LOGS_TOKEN` post-cutover now FATALs the whole control plane, not just Vector (P2-c — acceptable/desirable on a DARK host: loud fail beats a silent observability blind spot; safe across value rotation since the name persists).
- **INNGEST_-prefix alternative (P2-b) weighed & rejected:** naming the secret `INNGEST_BETTERSTACK_LOGS_TOKEN` would preserve the pure `^INNGEST_` regex with zero widening, BUT `vector.toml:377` reads `${BETTERSTACK_LOGS_TOKEN}` and `vector.toml` is SHARED with the amd64 web host (sources `soleur/prd.BETTERSTACK_LOGS_TOKEN`) — renaming would break the web host. So keep the name + widen the regex with the criterion-comment above.

### Phase 2 — Arch-parameterize the Vector install (`inngest-bootstrap.sh`)
- After `:467`, add `VECTOR_CLI_ARCH="${VECTOR_CLI_ARCH:-amd64}"` + a validate `case` (`amd64|arm64`) mirroring `:53-56`.
- Add an arch→triple map (bash `case`): `amd64) vec_triple=x86_64-unknown-linux-musl ;; arm64) vec_triple=aarch64-unknown-linux-musl ;;`.
- `:477` `VECTOR_DOWNLOAD_URL` — replace hardcoded `x86_64-unknown-linux-musl` with `${vec_triple}`.
- `:498` `install … "$tmp"/vector-x86_64-unknown-linux-musl/bin/vector` — replace with `"$tmp"/vector-${vec_triple}/bin/vector`.

### Phase 3 — Pin the arm64 SHA (`vector.tf`)
- Add `vector_sha256_arm64 = "365bab73244780083eb95b3e42161a9179f23a0811ffa6180f613c3af06ed8e6"` local with the verify-before-bump comment mirroring the amd64 pin (`:14-16`) and `inngest.tf:32-36`.

### Phase 4 — Un-defer Vector on the arm64 host (`cloud-init-inngest.yml`)
- `:191-197` comment block — rewrite from "DEFERRED" to "wired (arm64 build + isolated-project token)".
- Stage `/tmp/vector.toml`: add `docker cp soleur-inngest-bootstrap-extract:/vector.toml /tmp/vector.toml 2>/dev/null || true` (mirror `cloud-init.yml:659`).
- Read the image-env Vector version (arch-independent): `VECTOR_CLI_VERSION=$(printf '%s\n' "$image_env" | grep '^VECTOR_CLI_VERSION=' | head -1 | cut -d= -f2-)`.
- Replace `:212` `"VECTOR_CLI_VERSION=" "VECTOR_CLI_SHA256="` with `"VECTOR_CLI_VERSION=$VECTOR_CLI_VERSION" "VECTOR_CLI_SHA256=${vector_sha256_arm64}" "VECTOR_CLI_ARCH=arm64"` (SHA override mirrors the Inngest-CLI override at `:205`).
- `inngest-host.tf:189` templatefile render — add `vector_sha256_arm64 = local.vector_sha256_arm64` to the vars map (mirror `inngest_cli_sha256_arm64` at `:208`).

### Phase 5 — Provision the Doppler secret + replace-dispatch + sweep guard suites (Approach B)
- Add `variable "betterstack_logs_token"` (sensitive, no default) + the `doppler_secret.inngest_betterstack_logs_token` resource (`project="soleur-inngest", config="prd", value=var.betterstack_logs_token, ignore_changes=[value]`).
- Pre-provision gate: `BETTERSTACK_LOGS_TOKEN` copied into `soleur/prd_terraform` before merge (→ `TF_VAR_betterstack_logs_token`).
- **Sweep the guard suites (load-bearing):** register `doppler_secret.inngest_betterstack_logs_token` in `OPERATOR_APPLIED_EXCLUSIONS` (`terraform-target-parity.test.ts:454`, THE test-passing entry) AND in the `apply-web-platform-infra.yml` `inngest_host` `-target` list (`:1427`, for the apply).
- **Add the `inngest-host-replace` dispatch job** (mirror `web_2_recreate`) + `tests/scripts/lib/inngest-host-replace-gate.sh` (preserve `hcloud_volume.inngest_redis`).

### Phase 6 — Tests (write/adjust; see `## Test Scenarios`)
- Invert `inngest-host.test.sh:95-97` (test 7) from "Vector deferred" to "Vector wired (arm64)".
- Add bootstrap-level assertion for the arch→triple map + arm64 SHA local + isolation-check widening.

### Phase 7 — ADR-100 amendment + C4 (see `## Architecture Decision`)

## Files to Edit
- `apps/web-platform/infra/inngest-bootstrap.sh` — Phase 2 (`VECTOR_CLI_ARCH` + triple map + URL `:477` + extract `:498`).
- `apps/web-platform/infra/vector.tf` — Phase 3 (`vector_sha256_arm64` local).
- `apps/web-platform/infra/cloud-init-inngest.yml` — Phase 1 (isolation `:156-157` + comment) + Phase 4 (un-defer `:191-213`, stage `/tmp/vector.toml`, non-empty `VECTOR_CLI_*` + `VECTOR_CLI_ARCH`).
- `apps/web-platform/infra/inngest-host.tf` — Phase 4 (`:189` templatefile — pass `vector_sha256_arm64`).
- `apps/web-platform/infra/inngest-host.test.sh` — Phase 6 (invert test 7; add arm64-Vector assertions).
- `.github/workflows/build-inngest-bootstrap-image.yml` — validate `vector_sha256_arm64` is 64-hex alongside `vector_sha256` (`:120-129` parse block); the arm64 SHA is consumed via templatefile, not the image env, but the CI validator should still guard the new local from format drift.
- `.github/workflows/apply-web-platform-infra.yml` — (a) **add `-target='doppler_secret.inngest_betterstack_logs_token'` to the `inngest_host` dispatch job target list (`:1427`)** so the secret is applied by the dispatch. (b) **Add a NEW `inngest-host-replace` dispatch job** (mirror `web_2_recreate` `:887+`) doing `terraform apply -replace='hcloud_server.inngest'` behind an inngest-scoped gate — see Apply Path §2(b). (c) Add `inngest-host-replace` to the `apply_target` input options (`:96-100`).
- `tests/scripts/lib/inngest-host-replace-gate.sh` (**new**) — mirror `web2-recreate-gate.sh`: permit the intended `hcloud_server.inngest` + `hcloud_server_network.inngest` + `hcloud_volume_attachment.inngest_redis` replaces, forbid ALL other destroys, and specifically fail if `hcloud_volume.inngest_redis` is deleted (Redis AOF preservation).
- `plugins/soleur/test/terraform-target-parity.test.ts` — **add `doppler_secret.inngest_betterstack_logs_token` to `OPERATOR_APPLIED_EXCLUSIONS` (`:454`, next to the `inngest_*_dedicated` siblings ~`:589-591`).** This is the load-bearing registration: the parity test's `stripDispatchJobs` (`:418`) STRIPS the `inngest_host` job, so the dispatch `-target` line does NOT count as coverage — only the exclusions-set entry makes the coverage assertion (`:648-658`) pass. (The dispatch `-target` in (a) is still required for the secret to actually apply.) The "-target allowlist extension must sweep all guard suites" sharp edge.
- `apps/web-platform/infra/variables.tf` (or equivalent) — add `variable "betterstack_logs_token" { type = string; sensitive = true }` (no default; Approach B).
- `apps/web-platform/infra/inngest.tf` — reconcile the "Sentry" prose at `:331-353` if it misstates the sink (optional, low-priority; the ADR amendment is the canonical reconciliation).
- **Doppler-secret file** — one of `inngest-host.tf` (append) or a new `inngest-betterstack-token.tf` (Phase 5; see IaC section).

## Files to Create
- `apps/web-platform/infra/inngest-betterstack-token.tf` — **(conditional)** only if the IaC decision chooses a standalone file over appending to `inngest-host.tf`.

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

Phase 2.8 fires: this introduces a new secret into a Doppler project. Provisioning is routed
through IaC — a `doppler_secret` Terraform resource (below). No manual CLI secret write is used;
the boot isolation self-check remains the runtime guard on the resulting secret set.

### Terraform changes
- New `doppler_secret` writing `BETTERSTACK_LOGS_TOKEN` into `project = "soleur-inngest", config = "prd"`, `lifecycle { ignore_changes = [value] }` (mirror `ghcr-read-credential.tf:31-56` / `git-data-luks.tf:51`). Provider already manages the `soleur-inngest` project (`inngest-host.tf:80-123`), so it has write access.
- **Value-source decision — RESOLVED to Approach B (both deepen-plan review agents, decisive on the isolation axis):**
  - **Approach B (CHOSEN): new `var.betterstack_logs_token` (sensitive, no default) sourced from Doppler `prd_terraform`.** Exactly the established `ghcr_read_token` pattern. Only the one 24-char token enters `terraform.tfstate`. Pre-provision gate: add `BETTERSTACK_LOGS_TOKEN` to `soleur/prd_terraform` before merge (Doppler `--name-transformer tf-var` maps it → `TF_VAR_betterstack_logs_token` for all jobs; verify read-only via `doppler secrets get`). The no-default-var hazard (#5468) is real but small here — the token already exists in `soleur/prd`, so the Phase-0 gate is a copy into `prd_terraform`, verifiable read-only.
  - **Approach A (REJECTED — isolation regression):** `data "doppler_secrets" "soleur_prd"` was the original recommendation, but the DopplerHQ/doppler provider ships **only** the plural `doppler_secrets` data source (no singular `doppler_secret` data source), so `.map["BETTERSTACK_LOGS_TOKEN"]` necessarily materializes ALL ~116 `soleur/prd` secrets (Supabase service-role key, Stripe keys, etc.) into the SHARED web-platform `terraform.tfstate`, re-read on every push apply. That is the philosophical inverse of the ADR-100 isolation thesis this whole plan serves. Do NOT use Approach A. (Provider 1.21.2 does support the data source — it is feasible but wrong.)
- **Better Stack source:** NO new source needed — the existing source `soleur-inngest-vector-prd` (id 2457081, `inngest.tf:343-346`) is already named for and shared by inngest; the arm64 host reuses the same token. No `betterstackhq` provider change (the Logs product has no TF resource anyway — `inngest.tf:338-342`).

### Apply path
**Corrected after deepen-plan codebase verification — the dedicated-inngest resources are NOT
push-auto-applied.** Two distinct apply surfaces:

1. **The `doppler_secret` (BETTERSTACK_LOGS_TOKEN) — pure CREATE, dispatch-applied.** The dedicated-inngest resources live in the `apply-web-platform-infra.yml` `inngest_host` job (`:1339`, `if: workflow_dispatch && inputs.apply_target=='inngest-host'`) with an **additive-only destroy-guard** (`:1434-1448` — aborts if the plan shows ANY resource/nested delete). A net-new `doppler_secret` is a pure create → passes the guard. Apply via `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host -f reason=…` (a `gh` CLI dispatch — automatable, no operator SSH). Register the target in the job's `-target` list (`:1427`) **and** in `OPERATOR_APPLIED_EXCLUSIONS` (parity test).
2. **The cloud-init / bootstrap change — a REPLACE, path depends on whether the host already exists (deepen-plan finding — the ambiguity root).** Any `cloud-init-inngest.yml` change force-replaces `hcloud_server.inngest` (ADR-100, no `ignore_changes=[user_data]`).
   - **Sub-case (a) host NOT yet in tfstate at #6197 merge** (#6178 is OPEN — the host may not be provisioned yet): the cloud-init rides the **initial create** via the existing additive `inngest_host` dispatch (create-only → `resource_deletes==0` → guard passes). No new machinery needed.
   - **Sub-case (b) host ALREADY provisioned** (the plan's baseline assumption): the change is a force-**replace** (destroy+create) → the additive-only destroy-guard (`:1444`, aborts on any `["delete"]`-containing action) **ABORTS** it. There is NO existing replace path for the inngest host: `apply_target` options are only `manual-rerun|warm-standby|web-2-recreate|inngest-host`, and `cutover-inngest.yml` is **webhook-only (no terraform)**. **This plan must ADD a new `apply_target=inngest-host-replace` dispatch job**, mirroring the `web_2_recreate` job (`apply-web-platform-infra.yml:887+`): `terraform apply -replace='hcloud_server.inngest'` gated by a NEW inngest-scoped gate (mirror `tests/scripts/lib/web2-recreate-gate.sh`) whose allow-set is exactly the transitively-replaced resources — `hcloud_server.inngest` + `hcloud_server_network.inngest` + `hcloud_volume_attachment.inngest_redis` (all reference the new server id) — and which **must NOT permit deleting `hcloud_volume.inngest_redis`** (preserves the durable Redis AOF, exactly how web-2-recreate preserves `hcloud_volume.workspaces`).

The OCI image (bootstrap + `vector.toml`) rebuilds automatically on merge (`build-inngest-bootstrap-image.yml`); the cloud-init change is **latent** until the host is (re-)provisioned by the appropriate path above. The host is DARK/inert in Phase 1 (no live cron traffic, no reminders), so the replace has near-zero blast radius — but it is never a merge-time auto-apply.

**Net (operator/CI actions, all automatable — no SSH):** merge lands code + tests + the `doppler_secret` def + the new replace-dispatch job. Post-merge: (i) `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host` applies the additive `doppler_secret`; (ii) `gh workflow run … -f apply_target=inngest-host-replace` (sub-case b) OR the existing `inngest-host` create (sub-case a) provisions the host with the arm64 Vector bootstrap. This satisfies the re-eval trigger ("wired before the Phase-2 cutover") — the wiring is present + dispatch-applied ahead of the cutover.

### Distinctness / drift safeguards
`dev != prd`: the token lands only in `soleur-inngest/prd` (config pinned, `ignore_changes=[value]`).
State: the token value lands in `terraform.tfstate` (encrypted R2 backend — same as every other
`doppler_secret`). The isolation self-check (Phase 1) is the runtime drift guard: any *foreign*
secret leaking into `soleur-inngest/prd` still trips `n_total != n_inngest`.

### Vendor-tier reality check
N/A — reuses the existing Better Stack Logs source + token; no new paid resource, no tier gate.

## Observability

Phase 2.9 + 2.9.2 fire (infra change; the arm64 host is a **blind execution surface** — no SSH,
`hr-no-ssh-fallback-in-runbooks`). This feature *is* the observability wiring, so the discoverability
test is the shipped-log path itself.

```yaml
liveness_signal:
  what: vector.service active on the inngest host + journald/host_metrics arriving at Better Stack source 2457081
  cadence: continuous (Vector streams); confirm within ~2 min of host boot
  alert_target: Better Stack Logs "no logs from inngest host in N min" (post-cutover); pre-cutover the host is DARK and the heartbeat-absence P1 path (scheduled-inngest-health.yml) is the liveness proxy
  configured_in: apps/web-platform/infra/vector.toml (better_stack_logs sink) + inngest-bootstrap.sh (vector.service unit)
error_reporting:
  destination: inngest-bootstrap.sh stderr captured at the sudo boundary -> deploy-status endpoint (deploy.soleur.ai/hooks/deploy-status), same permanent diagnostic as the inngest install (:453-456). The bootstrap logs the installed vector config sha256 (:519) + restart status (:571-572).
  fail_loud: yes — SHA mismatch returns non-zero from install_vector_binary (:493-496) -> warn line in captured stderr; isolation FATAL (:158) aborts the whole bootstrap visibly.
failure_modes:
  - mode: arm64 SHA mismatch (wrong/re-cut release)
    detection: "vector sha256 mismatch: expected … actual …" in the captured bootstrap stderr (in-surface probe, visible via deploy-status — NO ssh)
    alert_route: deploy-status endpoint payload
  - mode: BETTERSTACK_LOGS_TOKEN missing/foreign in soleur-inngest/prd
    detection: isolation self-check FATAL "boot credential not isolated" (cloud-init-inngest.yml:158) — emitted FROM the host boot, surfaced in cloud-init/deploy-status output
    alert_route: deploy-status endpoint payload / cloud-init console
  - mode: vector.service restart loop (bad config / token invalid at ExecStart)
    detection: bootstrap logs "vector.service failed to (re)start" (:571); post-cutover, Better Stack "no logs from inngest host" absence alert
    alert_route: deploy-status endpoint (pre-cutover) + Better Stack absence alert (post-cutover)
logs:
  where: journald on the inngest host (bounded/persistent) -> Vector -> Better Stack Logs source 2457081 (EU cluster)
  retention: Better Stack Logs plan retention (existing); journald local bounded per journald-soleur.conf
discoverability_test:
  command: "curl -fsS https://deploy.soleur.ai/hooks/deploy-status  # shows the bootstrap vector install/config-sha/restart lines — NO ssh"
  expected_output: bootstrap stderr contains "vector config installed: sha256=…" and "vector observability shipper restarted"
```

**2.9.2 blind-surface note:** the `detection` for each mode is an **in-surface** signal (a line
the bootstrap emits FROM the host, reaching the deploy-status endpoint) — not a host-side-only
gate. The SHA/token/restart lines discriminate the three competing failure hypotheses (wrong
binary vs missing token vs bad config) in the same captured-stderr stream.

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-100** (`ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`), not a new
ADR — this is exactly ADR-100's tracked "Phase-1 caveat (deferred)" being resolved.
- `## Decision` / Phase-1-caveat section (L192-199): mark the Vector shipper **resolved** (arm64 build + isolated-project token wired in #6197).
- Correct the stale **"Vector journal->Sentry shipper"** prose to **Better Stack Logs** (the actual sink since #4273/#5526).
- Note the boot-isolation allowlist now admits `BETTERSTACK_LOGS_TOKEN` (dark-boot secret count 4->5, live 5->6).
- Record the new apply-path constraint: the additive-only `inngest_host` dispatch cannot force-replace the host; a scoped `inngest-host-replace` dispatch (web-2-recreate pattern, preserving the Redis AOF volume) is the escape hatch. This is an ADR-worthy infra-workflow addition worth capturing in the amendment.

### C4 views
Read all three model files — `model.c4`, `views.c4`, `spec.c4` — before concluding (C4 completeness
mandate; do NOT rely on a single `grep`). Both `inngest` and a Better Stack element already appear
in `model.c4`. The check: enumerate the feature's external system (Better Stack Logs) + the container
(dedicated Inngest host) + the access relationship (inngest-host -> Better Stack Logs *log-ship edge*).
If the dedicated Inngest host already has a `-> betterstack` observability edge modeled (or the
existing web-host->Better Stack edge is described generically enough to cover it), cite that and record
"no C4 impact — edge already modeled". If the dedicated host lacks the log-ship edge, add the element
relationship (`+ #external` tag on Better Stack if outside the boundary) + the `view … include` line
in `views.c4`, then run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing
Not soak-gated — the decision is true the moment the arm64 host re-provisions with the wired Vector.
The ADR amendment ships in this PR (status stays `accepted`; the caveat flips to resolved).

## Acceptance Criteria

### Pre-merge (PR)
- **AC1** `vector.tf` declares `vector_sha256_arm64 = "365bab73244780083eb95b3e42161a9179f23a0811ffa6180f613c3af06ed8e6"` — `grep -qE 'vector_sha256_arm64[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"' apps/web-platform/infra/vector.tf`.
- **AC2** `inngest-bootstrap.sh` builds the Vector download URL from an arch var — `grep -qF 'aarch64-unknown-linux-musl' apps/web-platform/infra/inngest-bootstrap.sh` AND the URL/extract no longer hardcode `x86_64` unconditionally (both derive from `${vec_triple}` / `${VECTOR_CLI_ARCH}`). Verify the extract path at `:498` no longer contains a literal `vector-x86_64-unknown-linux-musl/bin/vector`.
- **AC3** `VECTOR_CLI_ARCH` validates `amd64|arm64` and defaults `amd64` (web-host preserved) — `grep -qE 'VECTOR_CLI_ARCH="\$\{VECTOR_CLI_ARCH:-amd64\}"' apps/web-platform/infra/inngest-bootstrap.sh`.
- **AC4** `cloud-init-inngest.yml` passes non-empty arm64 Vector env — `grep -qF 'VECTOR_CLI_SHA256=${vector_sha256_arm64}'` AND `grep -qF 'VECTOR_CLI_ARCH=arm64'` AND stages `/tmp/vector.toml` (`grep -qF ':/vector.toml /tmp/vector.toml'`). The empty-`VECTOR_CLI_*` form is gone.
- **AC5** isolation self-check admits the new token — `grep -qF 'BETTERSTACK_LOGS_TOKEN' apps/web-platform/infra/cloud-init-inngest.yml` inside the allowlist regex AND the floor reads `-lt 5` (not `-lt 4`).
- **AC6** `inngest-host.tf:189` templatefile passes `vector_sha256_arm64` — `grep -qF 'vector_sha256_arm64 = local.vector_sha256_arm64' apps/web-platform/infra/inngest-host.tf`.
- **AC7** the `doppler_secret` for `BETTERSTACK_LOGS_TOKEN` targets `project = "soleur-inngest"`, `config = "prd"`, with `ignore_changes = [value]` — grep the chosen `.tf`.
- **AC8** `inngest-host.test.sh` test 7 now asserts Vector **wired** (arm64 SHA local + cloud-init override + `VECTOR_CLI_ARCH=arm64`), not deferred; the deferred-state grep is removed. Suite passes: `bash apps/web-platform/infra/inngest-host.test.sh` -> 0 failed.
- **AC9** `terraform validate` passes for `apps/web-platform/infra/` (init with the R2 backend + `--name-transformer tf-var` per the canonical triplet; `var.betterstack_logs_token` resolvable from `prd_terraform`). A scoped `terraform plan -target=doppler_secret.inngest_betterstack_logs_token` shows a pure CREATE (the additive-only inngest-host guard requires zero deletes). The new `inngest-host-replace` job's gate script permits exactly `hcloud_server.inngest`+`hcloud_server_network.inngest`+`hcloud_volume_attachment.inngest_redis` replaces and forbids `hcloud_volume.inngest_redis` deletion.
- **AC10** `-target`/parity sweep complete — `doppler_secret.inngest_betterstack_logs_token` is present in BOTH the `apply-web-platform-infra.yml` `inngest_host` job `-target` list AND `OPERATOR_APPLIED_EXCLUSIONS` in `terraform-target-parity.test.ts`. The parity suite passes: `bun test plugins/soleur/test/terraform-target-parity.test.ts` → 0 failures.
- **AC11** ADR-100 amended (caveat resolved + "Sentry"->"Better Stack Logs" reconciled); C4 completeness check recorded (edge added or cited as already-modeled).
- **AC12** No orphaned `x86_64` assumption remains in the Vector path — `grep -n 'x86_64' apps/web-platform/infra/inngest-bootstrap.sh` returns only the arch-map `amd64` arm (not the URL/extract literals).

### Post-merge (operator)
- **Dispatch the token apply (automatable, no SSH):** `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host -f reason="#6197 BETTERSTACK_LOGS_TOKEN"` — applies the additive `doppler_secret` via the additive-only guard. This is a `gh` CLI call, so `/ship` post-merge can run it; it is NOT an operator-manual step.
- **Host re-provision:** deferred to the **Phase-2 cutover** (ADR-100 operator-signed-off maintenance window) — the cloud-init/bootstrap change is latent until then. No separate operator step is added by #6197; the wiring is present + token-applied ahead of the cutover that consumes it. (If Approach B was used for the IaC, the only pre-merge gate is `TF_VAR_betterstack_logs_token` presence in `prd_terraform`, verified via a read-only `doppler secrets get`.)

## Open Code-Review Overlap

None — checked all 62 open `code-review` issues against the plan's Files-to-Edit
(`inngest-bootstrap.sh`, `vector.tf`, `cloud-init-inngest.yml`, `inngest-host.tf`,
`inngest-host.test.sh`, `build-inngest-bootstrap-image.yml`); no open scope-out names any.

## Domain Review

**Domains relevant:** none

Infrastructure/tooling change — arch-parameterizing a binary install + provisioning one write-only
log token into an isolated Doppler project. No user-facing surface (no `components/**`, no
`app/**/page.tsx`), no product/marketing/finance/legal/sales/support implication. The one
cross-cutting concern (the boot-isolation security boundary) is handled inline in Phase 1 + the
`## Observability` failure modes, and reviewed at deepen-plan by security-sentinel /
architecture-strategist (recommended at the isolation-boundary edit).

## Test Scenarios
- `inngest-host.test.sh` test 7 inverted: assert `vector_sha256_arm64` local exists in `vector.tf`, cloud-init overrides `VECTOR_CLI_SHA256="${vector_sha256_arm64}"`, passes `VECTOR_CLI_ARCH=arm64`, and stages `/tmp/vector.toml` — mirror the shape of test 5 (`:75-80`).
- New assertion: `inngest-bootstrap.sh` maps `arm64`->`aarch64-unknown-linux-musl` for BOTH the download URL and the extract path (grep both derive from the same triple var).
- New assertion: the isolation regex includes `BETTERSTACK_LOGS_TOKEN` and the floor is `-lt 5`.
- `build-inngest-bootstrap-image.yml` / `validate-vector-config.yml`: extend the 64-hex validator to cover `vector_sha256_arm64`.
- `terraform validate` + targeted `terraform plan` (dry, no apply) as an AC9 gate.

## Sharp Edges & Risks
- **Vector `aarch64` vs Inngest `arm64` naming.** Vector's release triple is `aarch64-unknown-linux-musl`; the Inngest CLI uses `linux_arm64`. Do NOT copy the Inngest URL shape — the arch->triple map must translate `arm64`->`aarch64` for Vector specifically.
- **Isolation self-check is the boot-brick trap.** Forgetting Phase 1 (or getting the `-lt N` floor wrong) makes the host FATAL at boot the instant the token lands in `soleur-inngest/prd`. The count is 5 dark / 6 live — re-derive it from the actual secret set, don't guess. This is the load-bearing edit the issue body omits.
- **Extract path is a second hardcoded x86_64 site.** `:498` hardcodes `vector-x86_64-unknown-linux-musl/bin/vector` in addition to the URL at `:477`. A URL-only fix installs nothing on arm64 (the `tar` extracts to `vector-aarch64-unknown-linux-musl/`). Both must move to `${vec_triple}`.
- **Additive-only guard rejects the host replace (deepen-plan finding).** The `inngest_host` dispatch job (`apply-web-platform-infra.yml:1339`) has an additive-only destroy-guard (`:1444` aborts on any delete). A cloud-init change force-replaces `hcloud_server.inngest` (destroy+create) → the guard ABORTS. So the cloud-init/bootstrap change is NOT applicable via this job; it lands at the Phase-2 cutover replace (Apply Path §2). Only the pure-create `doppler_secret` rides the dispatch. Do NOT frame the host change as merge-auto-applied.
- **Host force-replace is transitive — preserve the Redis volume (deepen-plan finding).** Replacing `hcloud_server.inngest` also replaces `hcloud_server_network.inngest` + `hcloud_volume_attachment.inngest_redis` (both reference the new server id). The `inngest-host-replace` gate's allow-set must include all three, and MUST forbid deleting `hcloud_volume.inngest_redis` (durable Redis AOF), mirroring how `web2-recreate-gate.sh` preserves `hcloud_volume.workspaces`.
- **`-target` allowlist extension MUST sweep all guard suites (deepen-plan finding).** Adding `doppler_secret.inngest_betterstack_logs_token` touches THREE artifacts: the `.tf` def, the `apply-web-platform-infra.yml` `inngest_host` `-target` list (`:1427`), AND `OPERATOR_APPLIED_EXCLUSIONS` in `plugins/soleur/test/terraform-target-parity.test.ts:454`. Missing the parity-test entry fails an orphan suite the plan's own tests don't exercise — run `bun test plugins/soleur/test/terraform-target-parity.test.ts` at /work.
- **Doppler provider data-source capability (Approach A).** Provider is pinned **`DopplerHQ/doppler` 1.21.2** (`.terraform.lock.hcl`); the `doppler_secrets` data source is available in this line, but confirm the exact `.map[...]` attribute shape at /work Phase 0 (context7 / provider docs). If unusable, use Approach B and pre-provision `TF_VAR_betterstack_logs_token` in `prd_terraform` before merge (auto-apply no-default-var hazard). Note: Approach A adds a TF-apply read-coupling to `soleur/prd`'s full secret set — see the security-review finding folded into the IaC section.
- **SHA immutability.** Vector 0.43.1 artifacts are immutable; the pinned `365bab73…8e6` is verified at plan time. If a future version bump is folded in, re-fetch BOTH the amd64 and arm64 SHAs.
- **Empty `## User-Brand Impact` fails deepen-plan Phase 4.6** — it is filled above (threshold `none` with reason); do not blank it.
