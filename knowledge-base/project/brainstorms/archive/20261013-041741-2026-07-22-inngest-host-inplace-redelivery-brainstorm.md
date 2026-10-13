# Brainstorm: in-place signed redelivery channel for the dedicated Inngest host

- **Date:** 2026-07-22
- **Issue:** #6780 (P2 chore, domain/engineering) — deferred C5.8 of #6617
- **Branch:** feat-6780-inngest-inplace-redelivery
- **Draft PR:** #6839
- **Related live work:** #6178 (extract Inngest to its own HA host — mid-cutover; PR #6348 held for the flip). PR C of #6617 is **cancelled** (recorded by merged #6784), which does not affect this debt.

## What We're Building

An in-place, **pull-based signed config-refresh channel** for the dedicated Inngest host
`soleur-inngest-prd` (private `10.0.1.40`, deny-all-public, no inbound). A systemd timer on the
host periodically resolves a promoted **digest pointer**, pulls a **signed OCI bundle** of the
host-executed `apps/web-platform/infra/*.sh` scripts, **verifies** it (cosign static key +
per-file sha256 manifest), applies it **atomically and fail-closed**, and reports the applied
version **off-box** to Better Stack. This removes the current constraint where *any* host-script
change — even a one-line log marker — can only be delivered by baking a new image and
force-replacing the **sole production Inngest scheduler** via
`apply-web-platform-infra.yml -f apply_target=inngest-host-replace`.

## Why This Approach

The host is deny-all-public, so the web-host in-place channel (`push-infra-config.sh` →
`/hooks/infra-config`, **inbound** HMAC webhook) cannot be reused without opening a new inbound
listener — rejected on the no-new-inbound acceptance criterion. **Pull** is the only shape that
preserves the posture. The host is already an outbound puller (GHCR-by-digest for its bootstrap
image, `api.doppler.com`, `github.com`, Better Stack all egress-reachable), so a signed-artifact
pull reuses proven egress + auth with **zero new inbound and zero new credentials**. Publishing a
**Doppler-held digest** the host resolves then pulls `IMAGE@sha256` extends the repo's existing
digest-pinned coherence primitive (ADR-128) instead of introducing the mutable-tag anti-pattern
the codebase explicitly warns against. Signing must be **asymmetric** (not the existing shared
HMAC): a shared secret would let a compromised sole scheduler forge its own updates. **cosign
keyless is ruled out** — Fulcio/Rekor egress is blocked by ADR-052/#5046 — so a **static cosign
key** (baked public verify key; private key CI/Doppler-only) extends the air-gapped trusted-root
model already in the repo (ADR-087).

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Pull, not push** — systemd timer on-host | Deny-all-public host has no inbound; the web-host push channel is inbound HMAC. Preserves no-new-inbound (AC-d). |
| D2 | **Substrate: signed OCI artifact, Zot-first (10.0.1.30) → GHCR fallback** | Operator call. Prefer the private-net registry (same subnet, no external egress); GHCR digest-pinned as fallback. Mirrors the bootstrap-image pull pattern. Signature is registry-independent. |
| D3 | **Pointer: Doppler `soleur-inngest/prd` `INNGEST_CONFIG_DIGEST`** | Host resolves digest (Doppler already reachable), pulls `@sha256`. Extends ADR-128 digest-pinned coherence; avoids mutable-tag drift. Must be admitted in the boot-isolation self-check (`cloud-init-inngest.yml:321`, cardinality 5→6) — precedented by `inngest-betterstack-token.tf`. |
| D4 | **Signing: cosign static key** (baked public verify key; private key CI/Doppler prd only) | Asymmetric prevents host-compromise self-forgery. Keyless ruled out (ADR-052 blocks Fulcio/Rekor egress). Extends ADR-087 air-gapped trusted-root. |
| D5 | **Apply: fail-closed** — verify sig → verify per-file sha256 manifest → atomic staging+swap → hardcoded dest allowlist | Reuse `infra-config-install.sh` STDIN root helper verbatim (dest+mode+owner table, `rc=3` on reject, TOCTOU/symlink-safe #4827). Never apply unsigned; a forged bundle can't reach the Redis AOF volume or sudoers. |
| D6 | **Monotonic version gate** (never apply version ≤ last-applied) | Blocks rollback/replay of an older validly-signed bundle. The current `infra-config-apply.sh` has no such guard. |
| D7 | **Head selection: promoted/soak-gated pointer, not main-latest** | Operator call. The digest advances only on explicit promotion (CI gate / short soak after landing on main) — a bad/mid-merge build can't auto-ship to the sole scheduler. |
| D8 | **Off-box verify + absence-heartbeat** | Emit `SOLEUR_INFRA_PULL_APPLIED version=… sha256= verify=ok` (and `…VERIFY_FAIL` on failure) via `inngest-boot-phone-home.sh` → Better Stack every run; pair with a Better Stack **absence-heartbeat** monitor (#6536 — a dead timer is silent+exit-0, indistinguishable from healthy). Satisfies AC-c + hr-no-ssh-fallback + hr-no-dashboard-eyeball. |
| D9 | **Coexistence: image = floor, pull = delta** | cloud-init bakes a baseline script set (fresh host never broken even if registries unreachable at boot); the timer converges to the promoted head. The four bootstrap-**image** pin sites (`cloud-init.yml:699/705`, `cloud-init-inngest.yml:390`, `inngest-bootstrap.sh:492`) are untouched — the config bundle is a different artifact from the server image. |
| D10 | **Sequencing: channel rides the #6178 cutover provision cloud-init** | Bootstrap paradox — the timer + verify script + baked cosign public key + Doppler-digest wiring install only through the replace they eliminate, so they must be baked into the cutover provision. Manifest/bundle edits + the CI build-sign-promote workflow follow via the channel itself. |
| D11 | **Capture as an ADR** | New trust boundary + pull control channel on the sole prod scheduler. Carves the `*.sh`-only exception to the image-replace-only rule; extends ADR-087 (verify) + ADR-128 (digest coherence). |

## Open Questions

1. **Zot pull path on the dedicated host must be wired + verified.** The dedicated host pulls its
   bootstrap image from GHCR-direct today; it has **no existing zot branch** in
   `cloud-init-inngest.yml`. Zot (`10.0.1.30:5000`, plain HTTP) is same-subnet so private-net
   reachable and web-host-proven, but the pull path + egress for *this* host is net-new and must
   be established and tested (Zot-first → GHCR fallback per D2). *(evidence: platform-strategist
   read of `cloud-init-inngest.yml` — no zot branch; `10.0.1.x` shared subnet.)*
2. **Refresh-set boundary** — exactly which `apps/web-platform/infra/*.sh` scripts are host-executed
   on `10.0.1.40` and belong in the bundle (vs web-host-only scripts). Enumerate at plan time.
3. **Timer cadence + promotion mechanism** — timer interval, and how the Doppler digest is
   promoted (CI gate vs a fixed soak window after main).
4. **cosign static-key custody + rotation recipe** — mirror the ADR-087 trusted-root re-capture
   recipe (accept both public keys during overlap, cut CI to the new private key, drop the old).

## User-Brand Impact

- **Artifact:** the pull-based signed config-refresh channel on the sole production Inngest scheduler (`soleur-inngest-prd`, 10.0.1.40).
- **Vector:** an unsigned/forged/rolled-back bundle executing on the sole scheduler → remote code execution or silent stale-config on the host that runs every statutory-deadline / notification cron; or a silent dead timer masking undelivered fixes.
- **Threshold:** `single-user incident`.

Tagged **user-brand-critical** (auto, per #5175). The plan inherits `Brand-survival threshold: single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support
*(Relevant: Engineering only — pure internal infra/CI; no user-facing surface, marketing, legal, or revenue implications.)*

### Engineering

**Summary (CTO):** The pull-based signed refresh is the minimal delta over machinery the host already runs (OCI puller + baked creds + off-box phone-home). Config bundle is a distinct artifact from the four image pin sites, so scope matches the issue exactly. Load-bearing hazards: RCE via weak verify or arbitrary dest paths (→ cosign verify + hardcoded dest allowlist), and the #6594/#6536 latched-false-green class (→ monotonic version gate + off-box applied-digest report + absence-heartbeat). Must ride the cutover provision (bootstrap paradox).

**Summary (platform-strategist):** Confirmed the dedicated host self-reports via `inngest-boot-phone-home.sh` → Better Stack (not the web host's Sentry emitter), pulls IREF from GHCR-direct (no zot branch — zot is web-host-only today), and egresses freely (the `cron-egress-allowlist` cage is the web container's, not this host's). The Doppler-published-digest model aligns with ADR-128/#6730 (digest-pinned coherence) and is the right anti-mutable-tag choice. Adding `INNGEST_CONFIG_DIGEST` to `soleur-inngest/prd` needs the boot-isolation self-check bumped 5→6 (precedented).

**Summary (infra-security):** The current channel is push + shared-HMAC and cannot be reused for a dark host. Recommend **asymmetric** signing (host holds only the public verify key, baked in cloud-init; private key CI/Doppler-only) — a shared secret makes verify-key == sign-key, a self-update forgery path on the sole scheduler. cosign keyless is out (ADR-052 blocks Fulcio/Rekor egress); use a static key extending ADR-087. Top risks: rollback/replay (→ signed monotonic version), host-compromise self-forgery (→ asymmetric), partial/unsigned apply (→ verify-before-activate, atomic swap, dest allowlist, hard-reject unsigned). Fail-closed = keep last-known-good + off-box `SOLEUR_INFRA_PULL_VERIFY_FAIL` marker + `OnFailure=` Sentry-Crons/Resend; never SSH.
