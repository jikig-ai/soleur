---
feature: inngest-host-inplace-redelivery
issue: 6780
lane: single-domain
brand_survival_threshold: single-user incident
status: draft
created: 2026-07-22
branch: feat-6780-inngest-inplace-redelivery
pr: 6839
brainstorm: knowledge-base/project/brainstorms/2026-07-22-inngest-host-inplace-redelivery-brainstorm.md
---

# Spec: in-place signed redelivery channel for the dedicated Inngest host

## Problem Statement

The dedicated Inngest host `soleur-inngest-prd` (private `10.0.1.40`, deny-all-public, no inbound)
has no in-place channel to receive updated host-executed `apps/web-platform/infra/*.sh` scripts.
Today the only delivery path is baking a new bootstrap image and force-replacing the **sole
production Inngest scheduler** via `apply-web-platform-infra.yml -f apply_target=inngest-host-replace`
— which must preserve/re-attach `hcloud_volume.inngest_redis` (Redis AOF) and move four image-pin
sites together, reddening `main` until all four land. The cost is structurally disproportionate to
the change size, so observability improvements to this host are priced out (the #6617 `sdk_url`
discriminator remains unobtained specifically because shipping it costs a host replace). The web
hosts have an in-place channel (`push-infra-config.sh` → `/hooks/infra-config`); the dedicated host
does not, and that channel is **inbound**, so it cannot be reused on a deny-all-public host.

## Goals

- G1: A change to a host-executed `apps/web-platform/infra/*.sh` script reaches `10.0.1.40`
  **without** `apply_target=inngest-host-replace`.
- G2: The channel is **no-SSH** (`hr-no-ssh-fallback-in-runbooks`) and adds **no new inbound**
  (preserves deny-all-public).
- G3: Delivery is **verifiable off-box** — a marker reaching Better Stack proves a specific bundle
  version/digest is live, never inferred from an exit code.
- G4: The channel cannot become an RCE or config-rollback vector into the sole scheduler
  (asymmetric signing, fail-closed verify, monotonic version gate, hardcoded dest allowlist).
- G5: The channel is installed by the #6178 cutover provision cloud-init (no separate host replace
  to add it) and coexists with the image-baked baseline (image = floor, pull = delta).

## Non-Goals

- NOT changing the four bootstrap-**image** pin sites or the server-binary delivery path — the
  config bundle is a distinct artifact; server-image bumps still ride an image bake/replace.
- NOT the #6178 cutover itself (topology move to 10.0.1.40); this rides it but does not perform it.
- NOT reopening the accept-the-constraint or extend-the-push directions (operator chose pull-based).
- NOT customer-facing / multi-tenant — internal operator infra only.

## Functional Requirements

- FR1: **CI build+sign+publish.** A CI workflow packages the host-executed `*.sh` refresh-set +
  a per-file sha256 manifest + a monotonic version into a bundle, **cosign-signs it with a static
  key** (private key from Doppler prd, never on any host), and publishes the OCI artifact to
  **Zot (10.0.1.30) first, GHCR as fallback**.
- FR2: **Promoted digest pointer.** The bundle's digest is published to Doppler
  `soleur-inngest/prd` as `INNGEST_CONFIG_DIGEST` **only on promotion** (CI gate / soak after main),
  never raw main-latest. Admit the key in the boot-isolation self-check (`cloud-init-inngest.yml:321`,
  cardinality 5→6).
- FR3: **On-host systemd timer + service.** Baked into the cutover provision cloud-init. On each
  tick: resolve `INNGEST_CONFIG_DIGEST` from Doppler → pull the artifact by `@sha256` (Zot-first →
  GHCR fallback) → **cosign verify** against the baked public verify key → verify each file's sha256
  against the signed manifest → **monotonic version gate** (reject version ≤ last-applied).
- FR4: **Atomic fail-closed apply.** Stage to a temp dir, apply via the `infra-config-install.sh`
  STDIN root helper (hardcoded dest+mode+owner allowlist, `rc=3` on dest-guard rejection,
  TOCTOU/symlink-safe), atomic swap. On ANY verify/version/fetch failure: keep last-known-good, do
  not touch live scripts, emit the off-box fail marker.
- FR5: **Off-box reporting.** Emit `SOLEUR_INFRA_PULL_APPLIED version=… sha256=… verify=ok` on every
  run and `SOLEUR_INFRA_PULL_VERIFY_FAIL …` on failure via `inngest-boot-phone-home.sh` → Better
  Stack; add a Better Stack **absence-heartbeat** monitor (alerts on a missing refresh) and an
  `OnFailure=` Sentry-Crons/Resend alarm.
- FR6: **Off-box audit.** A host state file (`{applied_version, bundle_sha256, signer_keyid,
  per_file_sha256[], applied_ts, verify_result}`) readable via a `cat-infra-config-state.sh`-style
  reader; the applied digest is cross-checkable off-box against the CI-logged signed-artifact digest.

## Technical Requirements

- TR1: **Zot pull path for the dedicated host is net-new** — the host pulls its image from
  GHCR-direct today with no zot branch. Wire + verify Zot (`10.0.1.30:5000`, private subnet) egress
  and pull for this host; GHCR digest-pinned fallback. *(open question OQ1)*
- TR2: **cosign signing custody + rotation.** *As-implemented: KEYLESS* (ADR-134 Option A / plan
  DEEPEN-CORRECTION-1) — no key custody: CI keyless-signs (OIDC id-token), the host verifies offline
  against the already-committed `cosign-trusted-root.json` + a config-workflow identity regexp;
  rotation = edit the regexp / re-capture the trusted root (ADR-087), no overlap dance. *Fallback
  (static key):* public verify key baked in cloud-init (non-secret, committed, reachable from
  `terraform apply` per `hr-fresh-host-provisioning-reachable`); private key CI/Doppler prd only;
  rotation mirrors the ADR-087 re-capture (accept both keys during overlap → cut CI → drop old).
- TR3: **ADR** capturing the new trust boundary + pull control channel (carves the `*.sh`-only
  exception to the image-replace-only rule; extends ADR-087 verify + ADR-128 digest coherence).
- TR4: Reuse existing patterns verbatim where they exist: `infra-config-install.sh` (apply),
  `infra-config-gate.sh` (per-file sha256 assert), `cat-infra-config-state.sh` (state reader),
  `inngest-boot-phone-home.sh` (off-box marker), `cron-egress-alarm.sh` (`OnFailure=` alarm).
- TR5: Coexistence — cloud-init bakes the baseline refresh-set (floor); the timer converges to the
  promoted head (delta). Guard the latched-stale-floor hazard (#6594) via the monotonic gate +
  off-box applied-digest report.

## Acceptance Criteria (from #6780)

- [ ] AC1: A change to an `apps/web-platform/infra/` host script reaches `10.0.1.40` without
  `apply_target=inngest-host-replace`.
- [ ] AC2: The channel is no-SSH.
- [ ] AC3: Delivery is verifiable off-box (a marker reaching Better Stack), not inferred from an
  exit code.
- [ ] AC4: No new inbound is opened; deny-all-public preserved.
- [ ] AC5: Verify is fail-closed and asymmetric; a monotonic version gate blocks rollback/replay.

## Open Questions (carry to plan)

1. OQ1 — wire + verify the Zot pull path for the dedicated host (net-new; TR1).
2. OQ2 — enumerate the exact host-executed `*.sh` refresh-set boundary.
3. OQ3 — timer cadence + promotion mechanism (CI gate vs soak window).
4. OQ4 — cosign custody + rotation recipe details. **Resolved: keyless (no key custody)** per DEEPEN-CORRECTION-1; static-key custody applies only to the documented fallback.
