---
title: "fix: zot 500 blob-upload + blind-host disk observability (disk-full root cause) — Closes #6240 #6244"
date: 2026-07-08
type: bug
classification: ops-remediation
lane: cross-domain
brand_survival_threshold: aggregate pattern
issues: [6240, 6244]
adr: ADR-096 (amend)
---

# 🐛 fix: zot 500 on blob-upload + remotely-queryable registry-host disk observability

## Overview

The Web Platform Release **"Mirror image GHCR→zot (crane)"** step fails on every recent `main`
commit with `500 Internal Server Error` on blob-upload PATCH/PUT + `connection reset by peer`
mid-write (#6240). The still-open Better Stack incident `soleur-registry-disk-prd | Missed
heartbeat` (which pings **only** while `/var/lib/zot` is <85% used and has never pinged) shares a
single root cause with the 500s: **the zot store's ext4 filesystem is out of space.** Both surfaced
~13:xx UTC on 2026-07-08.

The 2026-07-08 17:20 UTC `registry-host-replace` redeploy (fresh Hetzner host id 149095542,
PRESERVED 30 GB volume) did **not** fix it — the 17:26 post-redeploy release still 500'd. A disk-full
condition that survives a fresh host on a preserved volume points at the **filesystem**, not the host:
either `resize2fs` is not effectively growing the ext4 fs to fill the 30 GB block device (the
cloud-init line swallows failure with `|| true`), or gc/retention has not reclaimed. The prior
post-mortem (PR #6238) read the Hetzner volume API ("~30 GB") as "disk not full" — but the volume
API reports the **block-device** size, never the **filesystem** size, and there was no `df`
observability to tell them apart. **That blind spot is the same gap #6244 asks us to close.**

This plan fixes both together, sequenced observability-first:

1. **Observability (#6244):** make the deny-all-ingress, no-SSH registry host self-report its disk
   state to a queryable surface — `df` % of `/var/lib/zot`, the on-boot `resize2fs` before/after
   result, the real filesystem size, and zot container health — as a single structured
   `SOLEUR_ZOT_DISK` event on Better Stack Logs, queryable via `scripts/betterstack-query.sh`. This
   is the in-surface probe that disambiguates ≥85%-full-vs-resize-broken-vs-zot-crash without a host
   login.
2. **Root-cause fix (#6240):** harden `resize2fs` to **fail loud** (not `|| true`), wait for the
   volume device node, verify the fs actually reaches ~30 GB, and tighten zot gc/retention +
   trigger an on-boot prune so a filling store is reclaimed inside the redeploy.
3. **Verify:** dispatch `registry-host-replace`, read the emitted telemetry to confirm the fix,
   probe a real crane push / release for zero 500s, confirm the heartbeat goes `up` and the
   incident auto-resolves — then close #6240 + #6244.

Serving is NOT at risk: ADR-096's GHCR dark-launch fallback covers image pulls independently of the
self-hosted registry. The urgency is that #6129 will flip the zot pull path WARN→ENFORCE, at which
point a broken mirror becomes deploy-blocking.

## Premise Validation

- **#6240 OPEN** (`gh issue view 6240`) — title + body match the framing (crane 500 on blob-upload,
  recurring on consecutive main commits, GHCR path healthy). Held.
- **#6244 OPEN** (`gh issue view 6244`) — the blind-host df%/ping-result gap. Held. (Its own "interim"
  suggestion — `logger` to journald — is rejected here: journald requires SSH to read, violating
  `hr-no-ssh-fallback-in-runbooks`. We ship the egress-POST-to-Better-Stack path instead.)
- **"Recurring since ~957350d8" is time-correlation, NOT causal.** `git show --stat 957350d8` touched
  only `cloud-init-inngest.yml` + inngest cutover files — zero zot/registry infra. So the 500s began
  because the store crossed the full threshold around 13:11 UTC, not because a zot config change
  regressed. **Plan response: do NOT hunt for a config regression at 957350d8; treat it as a
  disk-fill timeline marker.**
- **The prior post-mortem's "false positive / disk not full" conclusion is now falsified by newer
  evidence.** It predicted the post-merge redeploy would arm the heartbeat and auto-resolve; the
  ARGUMENTS confirm the 17:20 redeploy happened and the heartbeat still never pinged + the 17:26
  release still 500'd. Under the heartbeat's own logic (pings only while <85%), a never-ping after a
  successful redeploy is positive evidence the fs is ≥85%/full. The "~30 GB volume API" reading
  checked the block device, not the filesystem.
- **Correction on the "`last_event_at=None`" phrasing.** A Better Stack heartbeat has **no
  `last_event_at` field** (learning `2026-07-08-verify-disk-fullness-write-health-on-deny-all-host-without-ssh.md`).
  The queryable liveness signal is `attributes.status ∈ {paused, pending, up, down}` via the Uptime
  API. "Never pinged" = `status` never reached `up`. The post-merge verify uses `status==up`, not
  `last_event_at`. Same learning prescribes triangulating disk-full via THREE independent signals
  (Hetzner volume API size, disk-IO metrics, last CI write outcome) rather than heartbeat
  presence/absence alone — which is exactly why this plan ships an in-surface `df` probe.
- **All 6 cited reference files exist** (verified by `test -f`): `cloud-init-registry.yml`,
  `zot-registry.tf`, `reusable-release.yml`, `betterstack-query.sh`, the post-mortem, and
  `apply-web-platform-infra.yml`. `ADR-096` + the three `.c4` model files exist.
- **Mechanism vs ADR corpus:** the observability delivery mechanism (Better Stack Logs ingest token
  in an isolated Doppler project + boot-guard name-admission) is NOT a rejected alternative — it is
  the **established precedent** from `inngest-betterstack-token.tf` (#6197, ADR-100). We apply it, we
  don't re-invent it.

## Research Reconciliation — Spec vs. Codebase

| Claim (ARGUMENTS) | Codebase reality | Plan response |
|---|---|---|
| Host is cx23, 30 GB volume | `var.registry_server_type` default `cx23`; `var.registry_volume_size` default **30** (`variables.tf:116,126`) | Confirmed. Block device is 30 GB; the fs may not be. |
| resize2fs `\|\| true` swallows failure | `cloud-init-registry.yml:141,146` — `mount … \|\| true` AND `resize2fs … \|\| true` | Harden both: fail loud + emit result to telemetry. |
| gc/retention too slow (24h) | `config.json` `gcInterval:"24h"`, `retention.delay:"24h"` (`cloud-init-registry.yml:69-87`) | Tighten interval/delay + on-boot prune. |
| Adding a secret trips the boot isolation guard | Guard asserts `n_total==2 && n_zot==2` inside `doppler run` (`cloud-init-registry.yml:194-199`) | Amend to admit `BETTERSTACK_LOGS_TOKEN` by name (n=3), mirroring `cloud-init-inngest.yml` — the token is a Doppler secret read outside/inside `doppler run`, NOT baked into user_data. |
| `registry-host-replace` preserves the volume + applies pending resize | ADR-096 amendment: 5-target `-replace` set **includes `hcloud_volume.registry`** ("its size update rides in") | A volume-size bump WOULD apply on the dispatch. But the leading fix is resize2fs, not a bump. |
| `BETTERSTACK_LOGS_TOKEN` available to TF | `var.betterstack_logs_token` exists (no-default, from `prd_terraform`), already provisioned for inngest #6197 | Reuse it; verify present in `prd_terraform` at work-time. |
| Better Stack Logs SOURCE is a TF resource | It is NOT (`inngest.tf:339` — provider has no source resource; sources are API-provisioned; isolated Logs source id **2457081**) | Reuse the EXISTING source via the same token; no new source. Query with `--grep SOLEUR_ZOT_DISK`. |

## Hypotheses (L3→L7 — network-outage checklist, `hr-ssh-diagnosis-verify-firewall`)

The symptom string contains `500` + `connection reset`, firing the network-outage gate. Ordered
L3→L7; connectivity layers are **opt-out with artifacts** because a `500` is itself a lower-layer
success signal.

1. **L3 firewall allow-list — VERIFIED not-causal (opt-out, artifact).** The zot host firewall is
   deny-all **public ingress** only; CI reaches zot over the **CF-Tunnel private-net bridge** at
   `127.0.0.1:5000`, and in the failing run `docker login 127.0.0.1:5000` **succeeded** and the
   bridge step reported `outcome == success` (`reusable-release.yml` `zot_bridge`). A firewall drop
   cannot return an HTTP 500. Not-causal.
2. **L3 DNS / routing — VERIFIED not-causal (opt-out, artifact).** The push target is a literal
   loopback `127.0.0.1:5000` over the tunnel bridge — no DNS resolution, no external routing hop.
   Not-causal.
3. **L7 TLS/proxy — N/A (opt-out, artifact).** The bridged path is **plain-HTTP** loopback (crane
   auto-treats `127.0.0.1` as insecure); no TLS chain to fault. Not-causal.
4. **L7 application layer — THE ROOT CAUSE.** zot returns a genuine HTTP **500** on
   `PATCH/PUT …/blobs/uploads/*` and resets mid-write. A 500 proves the packet reached the service
   (the lower layers are healthy). zot returns 500 + closes the connection when a blob write hits
   **`ENOSPC` (no space left on device)** — the ext4 fs on `/var/lib/zot` is full. This is confirmed,
   not verified-by-hope, by the emitted `df` telemetry post-redeploy (the whole point of Phase 1).
   Competing L7 sub-hypotheses the telemetry discriminates in ONE event:
   - (a) **fs full because resize2fs never grew it to 30 GB** — `resize_ok=false` OR `fs_size_gb≈10`.
   - (b) **fs full because gc/retention didn't reclaim** — `resize_ok=true`, `fs_size_gb≈30`, `pcent≥85`.
   - (c) **zot mid-write crash / OOM on the 4 GB box (dedupe on large writes)** — `pcent<85`,
     `fs_size_gb≈30`, yet zot still 500s + `zot_health` shows restarts. (Least likely; contingent
     follow-up only if the telemetry shows a healthy fs.)

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — serving is GHCR-fallback-covered.
The failure surface is the **deploy pipeline**: the zot mirror keeps 500ing, and once #6129 flips the
zot pull path WARN→ENFORCE, deploys become blocked for the whole team (a shared capability), delaying
every subsequent user-facing fix.

**If this leaks, the user's data is exposed via:** no exposure vector. The emitted telemetry is
non-PII operational metrics (`df` %, fs size in GB, resize exit code, zot container health). The
`BETTERSTACK_LOGS_TOKEN` reused is a write-only append token to a single Logs source, held in the
isolated `soleur-registry` Doppler project (no `soleur/prd` inheritance).

**Brand-survival threshold:** aggregate pattern — the degraded surface is the deploy-pipeline
supply-chain/alerting layer (systemic), not one user's data or session. No CPO sign-off required.
(Threshold carried forward from the post-mortem's `aggregate pattern` classification.)

## Implementation Phases

> Contract-ordering note: the boot isolation-guard amendment (admit `BETTERSTACK_LOGS_TOKEN`) and the
> `doppler_secret.registry_betterstack_logs_token` that satisfies it are **coupled** — the secret
> MUST exist in `soleur-registry/prd` before/with the host boot, or the amended guard sees only 2
> secrets and FATALs (a worse outage: zot never launches). Phase 2 (TF secret) is authored before
> Phase 3 (guard amendment) and both ride the SAME `registry-host-replace` dispatch; the dispatch's
> `-target` set MUST include the new secret (Phase 4).

### Phase 0 — Preconditions (no writes)
- Confirm `TF_VAR_betterstack_logs_token` resolves in `prd_terraform`:
  `doppler secrets get BETTERSTACK_LOGS_TOKEN -p soleur -c prd_terraform --plain` (read-only). If
  absent, STOP — it must be copied from `soleur/prd` first (per `inngest-betterstack-token.tf`
  provisioning order).
- Better Stack Logs ingest tokens are **region/cluster-bound** (learning
  `2026-05-22-vector-vrl-config-gates-and-pii-redaction-pipeline.md`): confirm the ingest host/region
  the token authenticates against with a cheap authenticated POST probe before wiring the reporter's
  URL (do NOT assume the region).
- Determine the Logs source ↔ token mapping: confirm the reused `BETTERSTACK_LOGS_TOKEN` writes to
  source **2457081** (table `t520508_soleur_inngest_vector_prd_3_logs`, the `betterstack-query.sh`
  default). If it does, no `--table` override is needed for queries. Record the finding.
- Read the exact `registry-host-replace` `-target` list in `apply-web-platform-infra.yml` and
  confirm the 5 targets (`hcloud_server.registry`, `hcloud_server_network.registry`,
  `hcloud_volume_attachment.registry`, `hcloud_firewall_attachment.registry`, `hcloud_volume.registry`).

### Phase 1 — Observability (in-surface disk probe) [#6244]
> **Reuse + why-not-Vector (functional-discovery).** Two producer-side precedents exist:
> `apps/web-platform/infra/disk-monitor.sh` (df% reporter with WARN/CRIT thresholds + per-threshold
> cooldown + envfile — but monitors `/`, alerts via Resend email (NOT queryable), and deploys to
> web/soleur hosts, not the registry) and `vector.toml [sources.host_metrics]` (already ships
> `filesystem`/`disk` df% to Better Stack Logs, queryably — but co-located with inngest only). We
> **reuse `disk-monitor.sh`'s threshold/cooldown/envfile SHAPE** for the reporter, but do **NOT**
> stand up full Vector on the registry host: (1) the ARGUMENTS scope explicitly excludes the
> not-yet-built Phase-3 Vector shipper; (2) Vector `host_metrics` at a tight scrape interval dominated
> Better Stack quota in the past (`betterstack-quota-near-miss-postmortem.md` — ~99% of quota); (3)
> Vector `host_metrics` cannot capture the bespoke fields that discriminate the root cause here —
> `resize_ok`, the persisted resize before/after, and `zot_restarts`. A single 5-min (300s) curl-POST
> reporter is the minimal in-surface probe.
- Rewrite `/usr/local/bin/zot-disk-heartbeat.sh` → split responsibilities:
  - Keep the **absence-based liveness ping** (curl the `disk_heartbeat_url` only while `<85%`) —
    unchanged alerting semantics.
  - ADD a **structured self-report**: compute `pcent` (df of `/var/lib/zot`), `fs_size_gb`
    (`df -B1G --output=size` or `dumpe2fs` block-count), read the persisted on-boot resize result
    (`/var/lib/zot/.resize-result` written by Phase 2), and `zot_health` (docker inspect
    restart-count / `/v2/` reachability), then POST ONE line to Better Stack Logs:
    `SOLEUR_ZOT_DISK pcent=<n> fs_size_gb=<n> block_size_gb=<n> resize_ok=<bool> zot_restarts=<n> ping_rc=<n>`
    via `curl -fsS -H "Authorization: Bearer $BETTERSTACK_LOGS_TOKEN" <ingest-url> -d @-`.
  - The reporter reads `BETTERSTACK_LOGS_TOKEN` from the isolated Doppler config; the cron entry is
    wrapped: `*/5 * * * * root . /etc/default/registry-doppler && doppler run --project
    soleur-registry --config prd -- /usr/local/bin/zot-disk-report.sh` (or fold into a single
    `doppler run` wrapper). Fail-loud: on curl failure, retry once, then still exit 0 so the cron
    does not wedge — but emit the failure to journald AND include `ping_rc` in the NEXT successful
    post so an egress failure is itself observable.
- The ingest URL is terraform-interpolated into the script (non-secret host, like `disk_heartbeat_url`),
  OR read from the Doppler config alongside the token — choose the Doppler-read form to avoid baking
  any Better Stack routing into user_data (deepen-plan to finalize).

### Phase 2 — resize2fs hardening (fail-loud) [#6240 primary]
- In `cloud-init-registry.yml` `runcmd`, replace the silent mount+resize with a fail-loud block that:
  - **Waits for the device node** `/dev/disk/by-id/scsi-0HC_Volume_<id>` to appear (bounded loop,
    ~30 × 2s) before mount — handles the volume-attach race that a bare `mount || true` hides.
  - Ensures `e2fsprogs` present. cloud-init's `packages:` stage is **non-fatal** (failures logged,
    boot continues — learning `2026-04-19-cloud-init-packages-stage-silent-drop-audit.md`), so add
    `e2fsprogs` to `packages:` AND add a runcmd guard (`dpkg -s e2fsprogs >/dev/null 2>&1 || apt-get
    install -y e2fsprogs`) BEFORE the resize block. (zot-registry.tf has NO
    `lifecycle.ignore_changes=[user_data]` — line 236-237 — so this cloud-init change DOES re-apply
    on the `registry-host-replace`; contrast the once-only path.)
  - Detects a partition table on the device; the Hetzner `format=ext4` volume is ext4-on-raw-device
    (no partition), so `resize2fs <device>` is correct and `growpart` is NOT needed — assert the
    no-partition invariant and fail loud if a partition unexpectedly appears.
  - Captures `df` before + after resize2fs and the resize2fs exit code; **persists**
    `resize_ok=<bool> fs_size_gb=<n> df_before=<n> df_after=<n>` to `/var/lib/zot/.resize-result` for
    the Phase-1 reporter to ship.
  - Removes `|| true` from the resize path; on a genuine resize FAILURE, log a `SOLEUR_ZOT_DISK …
    resize_ok=false` line to journald AND proceed to launch zot (a resize failure must not wedge the
    whole boot — but it MUST be loud in telemetry, not silent).
  - Asserts the post-resize fs size ≈ the block-device size (within tolerance); a persistent
    `fs_size_gb≈10` on a 30 GB device is the smoking gun for hypothesis (a).

### Phase 3 — gc/retention tightening + on-boot prune + guard amendment [#6240 defense-in-depth]
- `config.json`: reduce `gcInterval` `24h`→`1h` (or `6h`) and `retention.delay` `24h`→a shorter
  window so a filling store is pruned within the day, not once per 24h. Keep the keep-set + `sha256-*`
  cosign-referrer retention exactly as-is (deleting `.sig` tags breaks deploy-time `cosign verify`).
- Trigger an on-boot gc/retention pass so the redeploy immediately reclaims (zot runs gc on interval;
  add a first-boot nudge if zot supports an admin gc trigger, else rely on the tightened interval).
- **Amend the boot isolation self-check** (`cloud-init-registry.yml:194-199`): expect exactly THREE
  non-DOPPLER secrets — `ZOT_PULL_TOKEN`, `ZOT_PUSH_TOKEN`, `BETTERSTACK_LOGS_TOKEN` — asserting
  cardinality (==3) AND identity (the exact set). Mirror the fail-loud wording. This is the sanctioned
  `cloud-init-inngest.yml` pattern: deleting the logs token post-cutover FATALs the bootstrap (loud
  fail > silent log blind spot).

### Phase 4 — Terraform wiring [#6244 + #6240]
- Add `doppler_secret.registry_betterstack_logs_token` in `zot-registry.tf` (project
  `doppler_project.registry`, config `doppler_environment.registry_prd`, name `BETTERSTACK_LOGS_TOKEN`,
  value `var.betterstack_logs_token`, `lifecycle.ignore_changes = [value]`) — exact mirror of
  `inngest-betterstack-token.tf`.
- Extend the `registry-host-replace` `-target` set in `apply-web-platform-infra.yml` to include
  `doppler_secret.registry_betterstack_logs_token` (and confirm `hcloud_volume.registry` is present for
  any future size bump). Without this, the new secret does not apply on the dispatch and the amended
  guard FATALs.
- Contingent (only if Phase-6 telemetry shows a genuinely-full 30 GB fs after resize+gc): bump
  `var.registry_volume_size` 30→larger. Not pre-committed — telemetry-driven.

### Phase 5 — Docs: ADR-096 amendment + C4 edge
- ADR-096: add an amendment recording (a) the isolation-guard cardinality 2→3 (admit
  `BETTERSTACK_LOGS_TOKEN`), (b) the registry-host disk-observability delivery, (c) the resize2fs
  fail-loud + gc/retention remediation as the disk-full root-cause fix.
- `model.c4`: add a `zotRegistry -> betterstack` edge ("Ships disk-state observability — df% of
  /var/lib/zot + resize2fs result + zot health — as SOLEUR_ZOT_DISK to the Logs source; token in
  soleur-registry/prd, #6244"). `views.c4` already includes both `zotRegistry` and `betterstack` in
  the relevant view include-lists, so the edge renders without a view edit. Run the C4 validation
  tests after editing.

### Phase 6 — Post-merge verify (agent-automated, NO operator) [both issues]
- Dispatch: `gh workflow run apply-web-platform-infra.yml -f apply_target=registry-host-replace -f
  reason='#6240/#6244 — resize2fs fail-loud + disk observability'`; wait for success.
- After the replace, **verify private-net reachability** — a fresh Hetzner host can boot with its
  private NIC down (the additive online-attach lands after cloud-init's network stage; a soft reboot
  brings it up — learning `2026-07-07-immutable-redeploy.md`). The crane push probe below (CI reaching
  zot over the private-net bridge) IS this reachability check; if it fails on connection (not 500),
  soft-reboot the host and re-probe before concluding.
- Read telemetry: `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30m
  --grep SOLEUR_ZOT_DISK` → confirm `resize_ok=true`, `fs_size_gb≈30`, `pcent<85`. This is the
  deterministic verdict (`hr-no-dashboard-eyeball-pull-data-yourself`), not a dashboard eyeball.
- Probe the mirror: trigger a fresh Web Platform Release OR a manual `crane` push probe → confirm the
  mirror step completes with zero `500` / zero `no space left on device`.
- Confirm `soleur-registry-disk-prd` heartbeat `status==up` (Better Stack Uptime API,
  `BETTERSTACK_API_TOKEN` in `prd_terraform`) and the missed-heartbeat incident auto-resolves.
- Close #6240 + #6244 ONLY after the heartbeat is `up` AND the mirror probe is green.

## Files to Edit

- `apps/web-platform/infra/cloud-init-registry.yml` — resize2fs fail-loud + device-wait (Phase 2);
  `zot-disk-heartbeat.sh` structured self-report + cron `doppler run` wrap (Phase 1); gc/retention
  tightening + on-boot prune (Phase 3); isolation-guard cardinality 2→3 (Phase 3); add `e2fsprogs` to
  `packages:`.
- `apps/web-platform/infra/zot-registry.tf` — `doppler_secret.registry_betterstack_logs_token`
  (Phase 4); optional `var.registry_volume_size` note (contingent).
- `.github/workflows/apply-web-platform-infra.yml` — extend `registry-host-replace` `-target` set with
  the new doppler secret (Phase 4).
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`
  — amendment (Phase 5).
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `zotRegistry -> betterstack` edge (Phase 5).

## Files to Create

- (Optional) `apps/web-platform/infra/zot-disk-report.sh` if the reporter is split from the heartbeat
  script rather than folded in — deepen-plan to decide (a single hardened `zot-disk-heartbeat.sh` is
  the more minimal option; prefer folding in).

## Observability

```yaml
liveness_signal:
  what: "soleur-registry-disk-prd Better Stack heartbeat — absence-based (pings only while /var/lib/zot <85%)"
  cadence: "every 5 min (cron); heartbeat period 900s / grace 600s"
  alert_target: "Better Stack incident (email, free-tier policy_id=null) → ops@ (betteruptime_team_member.ops)"
  configured_in: "apps/web-platform/infra/zot-registry.tf (betteruptime_heartbeat.registry_disk_prd) + cloud-init-registry.yml (cron)"
error_reporting:
  destination: "Better Stack Logs source 2457081 (SOLEUR_ZOT_DISK marker), queried via scripts/betterstack-query.sh; resize failures also to journald"
  fail_loud: "resize2fs failure emits resize_ok=false to the SOLEUR_ZOT_DISK event AND journald; boot isolation-guard FATALs (refuses to launch zot) on a wrong secret set"
failure_modes:
  - mode: "ext4 fs full because resize2fs never grew it to the 30 GB device"
    detection: "SOLEUR_ZOT_DISK event: resize_ok=false OR fs_size_gb≈10 while block_size_gb≈30"
    alert_route: "betterstack-query.sh --grep SOLEUR_ZOT_DISK; missed-heartbeat incident"
  - mode: "ext4 fs full because gc/retention did not reclaim in time"
    detection: "SOLEUR_ZOT_DISK event: resize_ok=true, fs_size_gb≈30, pcent≥85"
    alert_route: "same query + missed-heartbeat incident"
  - mode: "zot mid-write crash/OOM (dedupe on 4 GB box) with a healthy fs"
    detection: "SOLEUR_ZOT_DISK event: pcent<85, fs_size_gb≈30, zot_restarts>0"
    alert_route: "same query; crane push still 500s → release job failure"
  - mode: "egress to Better Stack Logs failed (host can't self-report)"
    detection: "ping_rc!=0 carried in the next successful SOLEUR_ZOT_DISK post; journald line"
    alert_route: "betterstack-query.sh --grep SOLEUR_ZOT_DISK (gap in event cadence)"
logs:
  where: "Better Stack Logs source 2457081 (table t520508_soleur_inngest_vector_prd_3_logs); resize breadcrumbs also journald on-host"
  retention: "Better Stack Logs plan default"
discoverability_test:
  command: "doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30m --grep SOLEUR_ZOT_DISK"
  expected_output: "≥1 SOLEUR_ZOT_DISK line with pcent, fs_size_gb, block_size_gb, resize_ok, zot_restarts — NO ssh"
```

Affected-surface note (Phase 2.9.2): the registry host is a **blind execution surface** (deny-all
public ingress, no SSH). The `SOLEUR_ZOT_DISK` event is the required **in-surface** probe — emitted
FROM the host — and its structured fields (`pcent` / `fs_size_gb` / `block_size_gb` / `resize_ok` /
`zot_restarts`) discriminate ALL competing root-cause hypotheses (fs-not-grown vs gc-too-slow vs
zot-crash) in ONE event, not a single boolean.

## Infrastructure (IaC)

### Terraform changes
- `zot-registry.tf`: new `doppler_secret.registry_betterstack_logs_token` (project
  `doppler_project.registry`, config `doppler_environment.registry_prd`). Value from
  `var.betterstack_logs_token` (no-default, sourced from Doppler `prd_terraform` —
  `hr-tf-variable-no-operator-mint-default`; already provisioned for #6197). `ignore_changes=[value]`.
- No new provider or version pin (hcloud/doppler/betteruptime already required).
- Sensitive var: `TF_VAR_betterstack_logs_token` — value from Doppler `soleur/prd_terraform`.

### Apply path
- **cloud-init + `registry-host-replace` dispatch** (option b: existing-infra reprovision). The zot
  host is `OPERATOR_APPLIED_EXCLUSION` (NOT in the per-PR `-target` set), so a merge does not
  auto-apply it. The agent dispatches `gh workflow run apply-web-platform-infra.yml -f
  apply_target=registry-host-replace` post-merge (scoped `-replace=hcloud_server.registry`,
  destroy-guard PRESERVES `hcloud_volume.registry`, re-runs cloud-init). No SSH. Blast radius: the
  registry host reboots (~1-2 min); serving unaffected (GHCR fallback). The new doppler secret + the
  guard amendment ride the same dispatch — the `-target` set MUST include the new secret.

### Distinctness / drift safeguards
- `dev != prd`: the registry host reads `--config prd` exclusively (no dev registry). No dev leg.
- `lifecycle.ignore_changes=[value]` on the logs-token secret (rotation managed at source, like
  `inngest-betterstack-token.tf`); `ignore_changes=[paused]` on the heartbeats (operator UI pause
  survives applies) — unchanged.
- Secret value lands in `terraform.tfstate` (R2-encrypted backend) — a single 24-char write-only
  logs token, not the 116-secret `soleur/prd` map.

### Vendor-tier reality check
- Better Stack free tier (`var.betterstack_paid_tier=false`): `policy_id=null` (email-only). No new
  paid resource created — reuses the existing heartbeat + an existing Logs source. No tier gate needed.

## Architecture Decision (ADR/C4)

### ADR
- **Amend ADR-096** (do NOT defer to a follow-up issue — `wg-architecture-decision-is-a-plan-deliverable`).
  New amendment: (1) boot isolation-guard cardinality 2→3 admitting `BETTERSTACK_LOGS_TOKEN` by name
  (mirrors the ADR-100 inngest precedent); (2) blind-host disk-observability delivery
  (registry → Better Stack Logs, `SOLEUR_ZOT_DISK`); (3) resize2fs fail-loud + gc/retention
  tightening as the disk-full root-cause remediation. Status stays `accepted` (amendment, not reversal).

### C4 views
Read all three model files. Enumeration:
- **External human actors:** none new (operational metrics, no human correspondent).
- **External systems:** `betterstack` (already modeled) gains a NEW inbound edge from `zotRegistry`
  (already modeled). No new system.
- **Containers/data stores:** none new.
- **Access relationships that change:** `zotRegistry → betterstack` (NEW edge — the registry host was
  previously a Better Stack *heartbeat pinger* only via the web-host probe; it now *ships Logs*
  directly). `doppler → zotRegistry` description gains the third admitted secret.
- **Edit:** add the `zotRegistry -> betterstack` edge to `model.c4`; `views.c4` already includes both
  endpoints in the `landscape` + relevant view include-lists (lines 14, 36), so the edge renders with
  no view edit. Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after.

### Sequencing
The ADR amendment + C4 edge ship in THIS PR (docs land with the change). The isolation-guard behavior
is true immediately on the `registry-host-replace` redeploy (not soak-gated).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `cloud-init-registry.yml`: `resize2fs` no longer has a trailing `|| true` on its own line;
      a device-wait loop precedes `mount`; `df` before/after + resize exit code persist to
      `/var/lib/zot/.resize-result`. (`grep -n 'resize2fs' cloud-init-registry.yml` shows no `|| true`
      on the resize line.)
- [ ] `zot-disk-heartbeat.sh` emits a `SOLEUR_ZOT_DISK` line with fields `pcent`, `fs_size_gb`,
      `block_size_gb`, `resize_ok`, `zot_restarts`, `ping_rc`; the cron entry wraps it in
      `doppler run --project soleur-registry --config prd`.
- [ ] Boot isolation self-check asserts exactly 3 non-DOPPLER secrets and the identity set
      `{ZOT_PULL_TOKEN, ZOT_PUSH_TOKEN, BETTERSTACK_LOGS_TOKEN}` (grep shows `-ne 3` and the
      `BETTERSTACK_LOGS_TOKEN` name in the guard).
- [ ] `config.json`: `gcInterval` < `24h` and `retention.delay` < `24h`; keep-set (`latest`,
      `sha256-.*`, `v.*` ×10, `[0-9a-f]{7,64}` ×10) UNCHANGED.
- [ ] `zot-registry.tf`: `doppler_secret.registry_betterstack_logs_token` present, value
      `var.betterstack_logs_token`, `ignore_changes=[value]`.
- [ ] `apply-web-platform-infra.yml`: `registry-host-replace` `-target` set includes
      `doppler_secret.registry_betterstack_logs_token`.
- [ ] ADR-096 amendment written; `model.c4` has the `zotRegistry -> betterstack` edge; C4 validation
      tests pass; `terraform validate` (or `fmt -check`) clean on the infra root.
- [ ] `TF_VAR_betterstack_logs_token` confirmed present in `prd_terraform` (read-only probe).

### Post-merge (operator = agent-automated; NO human step)
- [ ] `registry-host-replace` dispatched and succeeded (`gh run watch`).
- [ ] `betterstack-query.sh --since 30m --grep SOLEUR_ZOT_DISK` returns ≥1 event with `resize_ok=true`,
      `fs_size_gb≈30`, `pcent<85` (deterministic verdict; `hr-no-dashboard-eyeball-pull-data-yourself`).
- [ ] A fresh Web Platform Release (or manual `crane` push probe) mirror step completes with zero `500`
      / zero `no space left on device`.
- [ ] `soleur-registry-disk-prd` heartbeat `status==up` (Uptime API) and the missed-heartbeat incident
      auto-resolves.
- [ ] `#6240` + `#6244` closed via `gh issue close` AFTER the two green signals above (PR body uses
      `Closes #6240` `Closes #6244`; `Closes` is acceptable here because the fix takes effect on the
      redeploy the agent dispatches within the same session).

## Domain Review

**Domains relevant:** Engineering (CTO) only.

### Engineering (CTO)
**Status:** reviewed (carried via deep infra analysis in the planning session — this is a pure
infra/observability change on an already-provisioned surface).
**Assessment:** The fix follows established precedents 1:1 (`inngest-betterstack-token.tf` for the
logs-token isolation, ADR-096's `registry-host-replace` for the apply path). The load-bearing risks
are ordering (secret before guard) and the fail-loud/fail-open balance on resize2fs — both are called
out in Sharp Edges. No new vendor, no new host, no user-data surface.

### Product/UX Gate
Not applicable — mechanical UI-surface override did NOT fire (no `components/**`, `app/**/page.tsx`,
or `app/**/layout.tsx` in Files to Edit). NONE.

## Open Code-Review Overlap

None found. (`gh issue list --label code-review --state open` cross-referenced against the Files to
Edit paths — no open scope-out touches `cloud-init-registry.yml`, `zot-registry.tf`,
`apply-web-platform-infra.yml`, ADR-096, or `model.c4`.) Related open issues #6241 (ops@ accept the
Better Stack invite — operator-only, separate) and #6242 (git-data heartbeat audit — sibling class)
are NOT touched by this plan.

## Risks & Sharp Edges

- **Secret-before-guard ordering (P0).** The amended boot guard expects 3 secrets. If the
  `registry-host-replace` dispatch reprovisions the host BEFORE `doppler_secret.registry_betterstack_logs_token`
  is applied, the isolated project has only 2 secrets → guard FATALs → zot never launches → a WORSE
  outage than the 500s. Mitigation: the new secret is in the SAME dispatch `-target` set (Phase 4);
  Terraform creates the secret in the same apply that replaces the host, and cloud-init runs after the
  Doppler secret exists. Verify the `-target` extension is present before dispatch.
- **Fail-loud vs fail-open on resize2fs.** A resize FAILURE must be LOUD in telemetry
  (`resize_ok=false`) but must NOT wedge the whole boot (zot should still launch on the existing fs so
  the host is reachable to self-report). The `|| true` is removed from the *silent-swallow* sense (the
  result is captured + shipped), not replaced with a hard `set -e` abort that would dark the host.
- **Reused token → shared Logs source.** The registry ships to the SAME source (2457081) as
  inngest/web hosts. The `SOLEUR_ZOT_DISK` marker is the discriminator; queries MUST `--grep` it. If
  work-time finds the token maps to a DIFFERENT source, pass `--table` accordingly (Phase 0 resolves).
- **gc-trigger-on-boot capability.** zot may not expose an explicit admin gc trigger; if not, rely on
  the tightened `gcInterval`. Verify against zot v2.1.2 docs at work-time before asserting an on-boot
  prune step — do NOT prescribe a fabricated zot admin endpoint (`hr-verify-repo-capability-claim`).
- **`Closes #N` vs `Ref #N` for ops-remediation.** This is `classification: ops-remediation` but the
  remediation (the `registry-host-replace` dispatch) runs in the SAME session immediately post-merge,
  so `Closes #6240 #6244` in the PR body is acceptable — the issues are closed by the agent after the
  green verify, not auto-closed-before-remediation. (Contrast the ops-remediation `Ref #N` Sharp Edge,
  which applies when the apply is a separate operator step days later.)
- **`-replace` targets dependencies upstream, not dependents downstream** (learning
  `2026-07-07-immutable-redeploy.md`). The `registry-host-replace` set already includes
  `hcloud_server_network.registry` + `hcloud_volume_attachment.registry` +
  `hcloud_firewall_attachment.registry` (per ADR-096) — confirm they remain in the set when extending
  it for the new doppler secret; dropping one boots the host off the private net / firewall-exposed.
- **Fail-loud guard discipline in the reporter + resize block** (learning
  `2026-07-05-bounded-retry-off-host-verify-and-fail-loud-guard-detection-command-exit.md`). Commands
  whose nonzero exit is a valid outcome (`df`, `grep -c`, `curl` transport-fail) inside `VAR=$(…)`
  must be `|| true`/sentinel-neutralized so a guard message still prints — but the neutralization must
  ship the failure signal (`resize_ok=false`, `ping_rc=N`), never silently swallow it. Test the
  count=0 / transport-fail path explicitly (the current `|| true` bug is exactly the un-tested path).
- **No prior resize2fs-failure learning exists.** The one-shot `compound` phase MUST capture the
  resize-failed-silently signature + recovery once the telemetry confirms the root cause (the
  learnings search found the immutable-redeploy + disk-verify patterns but no resize2fs-specific one).
- **A plan whose `## User-Brand Impact` section is empty or `TODO` fails deepen-plan Phase 4.6.** This
  section is filled (threshold `aggregate pattern`).

## Test Scenarios

- **Static:** `grep` assertions per the Pre-merge ACs; `terraform validate` on the infra root; C4
  syntax + render tests; `actionlint` on `apply-web-platform-infra.yml` (workflow) — NOT `bash -n`.
- **Boot-guard shape:** a unit-shaped test (bash) that feeds the isolation-guard block a 2-secret and a
  3-secret name set and asserts FATAL vs pass (mirror any existing `*.test.sh` in `apps/web-platform/infra/`).
- **Telemetry parse:** assert the `SOLEUR_ZOT_DISK` line is valid `key=value` and every documented
  field is present (protects the `betterstack-query.sh --grep` consumer + the discoverability_test).
- **Post-merge (live):** the Phase-6 verify sequence IS the integration test — telemetry read + crane
  probe + heartbeat status. Read-only against prod; no synthetic writes (`hr-dev-prd-distinct`).
