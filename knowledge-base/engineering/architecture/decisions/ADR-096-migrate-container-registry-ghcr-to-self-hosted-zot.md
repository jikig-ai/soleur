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

## Alternatives Considered

The 7 registry-choice options are tabled above. The **apply-path** alternatives (per-PR `-target`
the whole stack; a `workflow_dispatch` warm-standby job; split-cred two-writer choreography) were
routed to the CTO agent and rejected in `apply-path-cto-ruling.md` §"Rejected alternatives"; the
**push-ingress** alternatives (public `/v2/` endpoint; cloudflared on the registry host) were
rejected in the CTO's second ruling in favour of the CF-Tunnel-on-the-web-tunnel bridge.
