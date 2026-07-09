# ADR-096: Migrate the container registry off GHCR to a self-hosted zot (Hetzner, volume-backed)

- **Status:** Adopting
- **Date:** 2026-07-07
- **Issue:** [#6122](https://github.com/jikig-ai/soleur/issues/6122)
- **Supersedes:** [ADR-088](./ADR-088-control-plane-installation-token-minter-for-private-ghcr-reads.md) (the GHCR App installation-token minter — GHCR refuses App tokens for `docker pull`, confirmed platform limitation)
- **Lineage:** [ADR-068](./ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md) (dedicated-host + private-network precedent this mirrors) · [ADR-087](./ADR-087-cosign-deploy-verify-host-net-ephemeral-verifier-over-private-ghcr.md) (cosign keyless sign + offline verify, preserved unchanged) · [ADR-052](./ADR-052-container-egress-firewall-docker-user-allowlist.md) (restricted-egress firewall the registry must live within)

## Status

**Adopting.** The IaC foundations (Phase 1), dual-push (Phase 2), and the dark-launch pull-site
flip (Phase 3) are merged. The flip is inert until the operator provisions (1.8) + backfills
(1.9) zot and the entry gate (`zot-entry-gate.sh`) passes. This ADR flips to **accepted** after
the Phase-5 soak (`zot-soak-6122.sh`: ≥7 days, zero ghcr-fallback, sufficient zot sample) and
GHCR-push retirement (5.3–5.5).

## Context

Hetzner hosts must `docker pull` the private platform images (`soleur-web-platform`,
`soleur-inngest-bootstrap`) at boot and on every rolling deploy, using a **zero-touch,
control-plane-minted credential** (no human PAT on the pull path). The chosen mechanism —
ADR-088's Inngest minter issuing a GitHub App installation token — is **infeasible**: GHCR does
not accept App installation tokens for `docker pull` (GitHub platform limitation, community
discussion #171423, no ETA; verified in #6073). The only GHCR credentials that pull are a user
**classic PAT** (browser-only creation → not machine-automatable) and the Actions
**`GITHUB_TOKEN`** (workflow-scoped, absent at host boot). GHCR therefore *structurally cannot*
deliver a zero-touch machine identity. The system currently runs on an interim classic PAT with
the minter disabled — the exact fragility this migration removes.

## Decision

Stand up **zot** (the CNCF OCI-native registry) on a **dedicated Hetzner host** (`cax11`, ARM64),
**volume-backed** local-fs storage, on the existing private network (`10.0.1.30:5000`), behind
the deny-all-public firewall — mirroring the **git-data** dedicated-host model (ADR-068), NOT a
managed registry. Then:

1. **Push (Phase 2):** CI dual-pushes both images GHCR → zot. The web image is `crane copy`d
   runner-side (digest-preserving) after the GHCR push; the inngest image is `docker tag`+push.
   The zot digest is cosign-signed (same digest, same keyless identity). CI reaches the
   private-net registry over a **Cloudflare Tunnel + Access** bridge on the existing web tunnel
   (no public port opens; no cloudflared on the registry host) — see the CTO's second ruling.
2. **Pull (Phase 3):** every pull site prefers zot, **dark-launch gated** — it attempts zot only
   when `ZOT_REGISTRY_URL` is configured AND a `/v2/` probe answers AND the pull login succeeds,
   else it falls straight through to the unchanged private-GHCR path. Image ref + docker auth +
   cosign `.sig` target move **atomically** (whichever registry serves the pull, verify and run
   follow it). zot is plain-HTTP on the private net, so a zot-pulled digest needs
   `insecure-registries` (Edge A) + cosign `--allow-insecure-registry` (Edge B); cosign
   digest-pinning is the integrity guard, not TLS.
3. **cosign (Phase 4):** unchanged trust anchor — same pinned cosign SHA, same offline
   `trusted_root.json`, same GitHub-Actions-OIDC identity regexp. Registry-agnostic (Phase-0
   proved a read-only user fetches a zot-stored `.sig` and gc does not reap it).
4. **Cutover (Phase 5):** dual-push → validate zot pull E2E → flip (dark) → soak → retire GHCR
   push + egress + the interim PAT. GHCR stays break-glass warm through the entire soak.

### Registry-choice alternatives (7)

| # | Option | Verdict | Why |
|---|--------|---------|-----|
| 1 | GHCR App installation-token minter (ADR-088) | **Rejected** | GHCR refuses App tokens for `docker pull` — the whole premise is impossible. |
| 2 | GHCR user classic PAT (make it permanent) | **Rejected** | Browser-only creation, no machine rotation → not zero-touch; this is the fragility we are escaping (TR5 exposed PAT). |
| 3 | GHCR Actions `GITHUB_TOKEN` | **Rejected** | Workflow-scoped only; unavailable at host boot/deploy, which is exactly the pull path that needs a credential. |
| 4 | **Self-hosted zot, dedicated Hetzner host, volume-backed (CHOSEN)** | **Chosen** | OCI-native single binary; control-plane-minted htpasswd/JWT cred; lives inside the restricted-egress private net (G4); mirrors git-data (ADR-068); Phase-0 proved read-only ACL + cosign gc-safety + `crane` backfill. |
| 5 | Self-hosted zot with Cloudflare R2 / S3 backend | **Deferred** | FR1's original intent; local-fs won for v1 — durability = CI-reproducibility (images rebuildable, backfill re-runnable), and an R2 spike + host-side S3 creds expand blast radius for no v1 benefit. Revisit at scale (NG3). |
| 6 | Managed registry (Docker Hub / ECR / GCP AR / Quay) | **Rejected** | Introduces a new external vendor + public egress dependency (violates ADR-052), still leaves a machine-credential-delivery problem, and adds recurring cost + a new outage surface on the boot path. |
| 7 | Harbor (or other heavyweight self-hosted registry) | **Rejected** | Multi-service (DB, Redis, job service) — far heavier to run + patch than zot's single binary for a 2-image fleet; zot is OCI-native and cosign-gc-safe as proven in Phase 0. |

### Cold-boot-dependency statement

zot becomes a **boot-path dependency**: a fresh host (or a rolling deploy) that must pull an
image now depends on zot being reachable. This is a deliberately-accepted SPOF, mitigated on four
independent axes so it never silently gates a host:

- **Automatic degrade:** the dark-launch gate falls through to the still-dual-pushed GHCR path on
  any zot miss (probe fail / login fail / pull fail) — a zot outage degrades latency, not
  availability, for the entire soak + break-glass period.
- **Loud, no-SSH signal:** every fallback emits a Sentry `registry:"ghcr-fallback"` /
  `stage:"inngest_ghcr_fallback"` event (the fallback-rate alarm pages at >3/1h); zot liveness is
  a `betteruptime_heartbeat.registry_prd` push beat that pages if zot stops beating — before it
  can gate a boot (TR3).
  - *CI push side (#6274):* the CI dual-push mirror step is **explicitly non-blocking**
    (`continue-on-error: true` + an `exit 0` inner shell + a bounded retry to self-heal a transient
    CF-tunnel reset) — a mirror failure degrades zot redundancy, never the release/build verdict
    (consistent with "latency, not availability" above). A persistent miss is loud via a CI-level
    degraded signal: `mirror_status=degraded` → `::warning::` + step summary (both workflows) + a
    ⚠️ line on the Slack release message (`reusable-release.yml` only). The *live* fallback-rate
    Sentry alarm the bullet above references is **design intent, not yet provisioned** — a separate
    IaC follow-up, load-bearing at the Phase-5 GHCR-push retirement. Two post-cutover boot-gating
    shapes the degraded signal must remain loud for: a **missing** copy (crane-copy failure) AND a
    **present-but-unsigned** copy (cosign-sign succeeded-copy-then-failed-sign) — the latter is NOT a
    clean miss, since the pull side would pull the present zot copy and *bypass* the atomic GHCR
    fallback, then hard-fail signature verify. During soak `ZOT_ACTIVE=0`, so both are latent and the
    pre-flip zot-entry-gate/soak-gate catch them; the mirror step's cosign-failure path emits a
    re-sign-specific remediation (a bare `crane copy` backfill does not re-sign).
- **Instant revert:** unset `ZOT_REGISTRY_URL` in Doppler `prd` → all sites revert to GHCR-primary
  with no deploy, no SSH (`zot-registry-revert.md`).
- **Durability = reproducibility:** zot's content is 100% rebuildable (CI re-pushes) + re-backfillable
  (`crane copy` GHCR→zot); a lost volume is a re-run, not data loss — which is why a host-side
  snapshot cron (1.5) was deferred rather than expanding the host's blast radius with an hcloud token.

<!-- lint-infra-ignore start -->
### Apply path (binding — see `apply-path-cto-ruling.md`)

The registry host follows the **ADR-068 git-data model**: all 24 new resources (18 host-stack + 6
CF-Tunnel ingress) are **operator-applied** via `OPERATOR_APPLIED_EXCLUSIONS` + the 12h drift
detector — **zero** added to the per-PR CI `-target=` list. An unattended per-PR apply must not
provision a production host / mint a push credential for a host that does not yet exist
(`hr-fresh-host-provisioning-reachable-from-terraform-apply`). Two load-bearing conditions: (1) the
registry host is **cloud-init-only** (an SSH-provisioned `terraform_data` would hit the first
parity guard); (2) no zot cred is a `github_actions_secret` (CI reads `ZOT_PUSH_*` from Doppler at
runtime). The **one** exception is `terraform_data.registry_insecure_config` — the running-host
`insecure-registries` SSH delivery — which, being SSH-provisioned, **must** be in the CI `-target`
list + the terraform-target-parity SSH set (condition #1 the other way).

<!-- lint-infra-ignore end -->

## Consequences

- **Positive:** a genuine zero-touch machine identity on the pull path (G1); the interim exposed
  PAT is retired (TR5, after soak); GHCR removed from the boot critical path once soak completes;
  cosign chain preserved end-to-end (G3); registry lives inside the restricted-egress net (G4);
  zero-downtime dark-launch cutover with no credential gap (G5).
- **Negative / residual:** a new dedicated host to run + patch (~€4/mo); a boot-path dependency
  (mitigated above); a plain-HTTP-on-private-net registry (integrity via cosign digest-pinning,
  not TLS); local-fs (single-datacenter) durability until an R2/snapshot revisit (NG3).
- **Retirement (post-soak):** remove the pull-site GHCR fallback branch (5.3), stop GHCR push +
  egress allow (5.3), retire `cron-ghcr-token-minter.ts` + `ghcr-*-credential.tf` + the
  `GHCR_MINTER_DISABLED` gate (5.4), then rotate + revoke the exposed classic PAT (5.5).

### Credential isolation (amendment 2026-07-07, #6122)

The registry host's boot credential is scoped to a **dedicated Doppler project `soleur-registry`**
whose own `prd` root config holds ONLY `ZOT_PULL_TOKEN` + `ZOT_PUSH_TOKEN` — **not** a `prd` branch
config. The original design placed the host token in a `prd_registry` **branch config under the
`prd` environment** and claimed it isolated the host. That claim was **structurally impossible**:
in Doppler, every config within an environment resolves that environment's ROOT config as its base,
so a token scoped to a `prd` branch config reads the full `prd` secret set — empirically verified to
return all 116 secrets including `SUPABASE_SERVICE_ROLE_KEY`. Provisioning as-designed would have
handed a new CF-tunnel-reachable private-net host read access to every production secret.

True isolation requires a boundary that does not share the `prd` root. A **separate project** was
chosen over a standalone `registry` **environment** because the `soleur` project is at the
4-environment tier cap (dev/prd/ci/cli) — a 5th environment needs a Doppler Team-plan upgrade,
whereas project creation is unrestricted at the current tier. `doppler_project.registry` is
TF-created in the operator's full apply (`var.doppler_token_tf` is workplace-scoped); fallback is a
one-time operator-created project. Verified by a boot-time self-assertion (cloud-init refuses to
launch unless its own shipped token resolves exactly 2 non-`DOPPLER_*` secrets, both `ZOT_*`) plus a
provisioning-gate scoped-token count/identity assert. The identical branch-config non-isolation
affects `prd_git_data`, `prd_kb_drift_walker`, and `prd_cla` (a **live** over-read) — audited
separately in **#6167**; status stays **Adopting**.

### Reprovisioning path + alert recipient (amendment 2026-07-08)

Two gaps surfaced when the 2026-07-08 zot capacity-management merge (`storage.retention` pruning +
10→30 GB volume grow + `betteruptime_heartbeat.registry_disk_prd`) created a disk-full heartbeat in
Better Stack but the registry **host was never redeployed** with the cloud-init that installs the
`zot-disk-heartbeat.sh` self-ping cron — so the heartbeat never pinged, Better Stack alerted on the
absence (`soleur-registry-disk-prd | Missed heartbeat`), and the same missing redeploy left the disk
mitigations un-live. Both are structural, not one-off:

- **Reprovisioning / apply-path.** The per-PR CI path bridges over SSH to the *existing* web host and
  cannot provision a fresh host; the registry resources stay `OPERATOR_APPLIED_EXCLUSIONS` (the
  binding apply-path ruling above is **unchanged**). The registry host now has a sanctioned
  **dispatch-only `registry-host-replace`** path (`apply_target=registry-host-replace` in
  `apply-web-platform-infra.yml`), mirroring ADR-100's `inngest-host-replace`: a scoped
  `terraform apply -replace='hcloud_server.registry'` over a **5-target** set (server +
  `hcloud_server_network.registry` + `hcloud_volume_attachment.registry` +
  `hcloud_firewall_attachment.registry` + `hcloud_volume.registry`) to re-run cloud-init + apply any
  pending storage-volume resize **without SSH**. *(Grew to a **6-target** set — the isolated
  `doppler_secret.registry_betterstack_logs_token` — under the #6240/#6244 amendment below.)* *(Grew to a **6-target** set — + `doppler_secret.registry_betterstack_logs_token` —
  in the #6240/#6244 amendment below.)* A sourced destroy-guard
  (`tests/scripts/lib/registry-host-replace-gate.sh`, no `[ack-destroy]` bypass —
  `hr-menu-option-ack-not-prod-write-auth`) PRESERVES the zot OCI store volume (size-update-only,
  never delete/forget/replace) and positively asserts the new host re-attaches to its private NIC +
  deny-all firewall. It is a **larger, stricter** gate than inngest's (5-member allow-set vs 3;
  positive NIC/firewall assertions; the storage volume in-scope so its size update rides in — the
  4-target scope would have aborted the very fix). The dispatch job is stripped from the per-merge
  parity coverage anchor (`stripDispatchJobs`).
- **Alert recipient (free-tier IaC path).** Recipients were not managed in Terraform at all, so only
  the account owner was emailed and the incident stayed unacknowledged.
  `betteruptime_team_member.ops` (email `ops@jikigai.com`, `role = "responder"`,
  `team_name = "Your team"`) is now the IaC-managed recipient in `uptime-alerts.tf`, auto-applied
  per-merge via `-target=betteruptime_team_member.ops`. It authenticates via the existing global
  `var.betterstack_api_token` (no new variable). Escalation `betteruptime_policy` stays paid-gated
  (`var.betterstack_paid_tier`, unchanged). The member is **inert until ops@ accepts the one-time
  invite** (its own inbox); if free-tier non-owner routing proves owner-only the documented fallback
  is a `betteruptime_outgoing_webhook` forward or a Responder-tier upgrade (expense-gated, out of
  scope). Status stays **Adopting**.

### Disk-full root cause + blind-host observability (amendment 2026-07-08, #6240/#6244)

The 2026-07-08 17:20 UTC `registry-host-replace` (fresh host, PRESERVED 30 GB volume) did **not**
fix the crane 500-on-blob-upload; the disk heartbeat still never pinged. A disk-full condition that
survives a fresh host on a preserved volume is a **filesystem**, not a host, fault: the on-boot
`resize2fs` was wrapped in `|| true`, so it **silently failed** and the ext4 fs on `/var/lib/zot`
never grew to fill the 30 GB block device — it filled, zot 500'd every push with `ENOSPC`, and the
absence-based heartbeat (pings only while `<85%`) never fired. The prior post-mortem read the Hetzner
volume API ("~30 GB") as "not full", but that API reports the **block-device** size, never the
**filesystem** size, and there was no `df` observability to tell them apart. Three coupled remedies:

- **Boot isolation-guard cardinality 2 → 3.** The `cloud-init-registry.yml` self-check now admits a
  third secret **`BETTERSTACK_LOGS_TOKEN`** by name (asserting `n_total == 3 && n_admitted == 3` over
  the exact set `{ZOT_PULL_TOKEN, ZOT_PUSH_TOKEN, BETTERSTACK_LOGS_TOKEN}`), mirroring the ADR-100
  `cloud-init-inngest.yml` precedent. Deleting the logs token post-cutover FATALs the bootstrap (loud
  fail > silent observability blind spot); the check keys on the NAME, so value rotation is safe. The
  token is provisioned by `doppler_secret.registry_betterstack_logs_token` (isolated `soleur-registry/prd`,
  exact mirror of `inngest-betterstack-token.tf`, value from the no-default `var.betterstack_logs_token`)
  and **MUST ride the SAME `registry-host-replace` dispatch** as the host replace — so the dispatch
  `-target` set + the destroy-guard allow-set both grew 5 → 6 to include it (a 2-secret config now
  FATALs the boot, a worse outage — the ordering is load-bearing).

- **Blind-host disk observability (#6244).** The deny-all-ingress, no-SSH registry host now
  self-reports its disk state as ONE structured **`SOLEUR_ZOT_DISK`** event
  (`pcent`, `fs_size_gb`, `block_size_gb`, `resize_ok`, `zot_restarts`, `ping_rc`) to the **existing**
  isolated Better Stack Logs source **2457081** (reused via the same token + region-bound ingest URL
  `s2457081.eu-fsn-3` that `vector.toml` ships to — no new source), queryable via
  `scripts/betterstack-query.sh --grep SOLEUR_ZOT_DISK` with NO SSH. The `#6244`-suggested
  journald-`logger` interim was rejected (journald needs SSH to read — `hr-no-ssh-fallback-in-runbooks`).
  The event's fields discriminate all three competing root causes in one line: fs-not-grown
  (`resize_ok=false` OR `fs_size_gb ≪ block_size_gb`), gc-too-slow (`resize_ok=true`, `fs≈28 GiB`,
  `pcent≥85`), and zot-mid-write-crash (`pcent<85`, `fs≈28 GiB`, `zot_restarts>0`). Delivered by folding
  the report into `zot-disk-heartbeat.sh` under a `doppler run --project soleur-registry --config prd`
  cron wrapper (token injected at run time, never baked into user_data). This adds the
  `zotRegistry → betterstack` edge in `model.c4`.

- **resize2fs fail-loud + gc/retention remediation (#6240).** The resize path drops `|| true`
  (silent-swallow), waits for the volume device node (attach race), re-ensures `e2fsprogs` (the
  cloud-init `packages:` stage is non-fatal), asserts the ext4-on-raw-device (no-partition) invariant,
  and captures `df` before/after + the resize2fs exit code into `/var/lib/zot/.resize-result` for the
  reporter to ship. A genuine resize failure is LOUD in telemetry (`resize_ok=false`) but does NOT
  wedge the boot — zot still launches on the existing fs so the host stays reachable to self-report
  (fail-loud, not fail-dark). `config.json` gc/retention tightened `gcInterval` 24h → 1h and
  `retention.delay` 24h → 2h (keep-set + `gcDelay` unchanged) so a filling store reclaims within ~1h;
  no on-boot gc trigger is issued (zot v2.1.2 exposes no sanctioned on-demand gc endpoint —
  `hr-verify-repo-capability-claim`). Status stays **Adopting**.

- **Capacity-vs-retention recurrence (2026-07-09, #6247).** The #6240 fix tightened gc/retention
  **timing** but deliberately left the keep-**set** unchanged. A recurrence followed: `SOLEUR_ZOT_DISK`
  showed the 30 GB ext4 fs **genuinely full** (`pcent=100`, `resize_ok=true`,
  `fs_size_gb=30=block_size_gb`, `zot_restarts` climbing) — NOT a resize regression, but the exact
  telemetry-gated *grow-the-volume* contingency #6244 pre-registered as #6247. Root cause: the
  `storage.retention` keep-set (`latest` + **unbounded** `sha256-.*` sig referrers + **10** `v*` + **10**
  commit-sha, **per repo across 2 platform-image repos**, each image ~1.5–2 GB) legitimately **exceeded
  30 GB**, and gc cannot reclaim a blob the policy says to KEEP. Resolution — **both levers, one PR, one
  `registry-host-replace` dispatch**: (1) grow `var.registry_volume_size` **30 → 60 GB** (Hetzner
  in-place volume resize preserving data; the fail-loud `resize2fs` grows the ext4 on the next boot);
  (2) tighten the keep-set — `mostRecentlyPushedCount` **10 → 5** for `v*` and commit-sha, and **bound
  the previously-absolute "ALWAYS keep every `sha256-*`" rule** at `mostRecentlyPushedCount` **50**.
  The `sha256-.*` bound revises the prior invariant and is coupled to deploy-time `cosign verify`
  (ADR-087): `mostRecentlyPushedCount` is push-ORDER heuristic and can evict out of order under the
  backfill/re-sign path above, and GHCR does NOT rescue a zot-pruned sig on a **kept** image (atomic-move
  fetches the `.sig` from whichever registry serves the pull). 50 sits far above the true keep
  requirement (~12–18 sig-tags/repo) so it never prunes a kept image's sig at current scale; blast
  radius today is WARN-mode (`ci-deploy.sh`), becoming blocking at the WARN→ENFORCE flip (#6129). No
  gate/workflow change: the `registry-host-replace` destroy-guard already permits a volume `["update"]`.
  Status stays **Adopting**.

## Alternatives Considered

The 7 registry-choice options are tabled above. The **apply-path** alternatives (per-PR `-target`
the whole stack; a `workflow_dispatch` warm-standby job; split-cred two-writer choreography) were
routed to the CTO agent and rejected in `apply-path-cto-ruling.md` §"Rejected alternatives"; the
**push-ingress** alternatives (public `/v2/` endpoint; cloudflared on the registry host) were
rejected in the CTO's second ruling in favour of the CF-Tunnel-on-the-web-tunnel bridge.
