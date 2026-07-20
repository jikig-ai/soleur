---
feature: registry-oidc-migration
issue: "#6122"
phase: 3
kind: pull-site-map-and-design
date: 2026-07-06
---

# Phase 3 — Pull-site map + fallback design (deploy-critical)

Verified site map (line numbers current as of 2026-07-06). Each site flips to **zot-primary with
atomic GHCR fallback** (image ref + docker auth + cosign sig-fetch move together) + a per-site
beacon (`registry`=zot|ghcr-fallback, `image`=web|inngest, `pull_rc`, `login_rc`).

## Dark-launch gate (SAFE to land before the host exists)
The registry host is provisioned by the operator's post-merge full apply (Phase 1.8) and images are
backfilled post-merge (Phase 1.9). So the flip MUST be gated: **attempt zot only when zot is
confirmed-configured** (`ZOT_REGISTRY_URL` present in Doppler AND a fast `/v2/` reachability probe
succeeds), else fall straight through to the unchanged GHCR path. This satisfies the plan AC ("tries
zot-primary with atomic GHCR fallback") while guaranteeing zero behaviour change until zot is live +
populated — the `wg-dark-launch-deploy-gates` pattern. The Phase-3 entry-gate script (below) is the
CI/deploy-time expression of the same check.

## Sites

| # | File:line | Kind | Action |
|---|---|---|---|
| 1 | `ci-deploy.sh` L1024 (pull), login via `ghcr_prelude_and_login` L547/L1002 | web rolling-deploy pull | zot-login+pull first (gated), else GHCR; beacon via `pull_failure_event`+`final_write_state`+logger |
| 2 | `ci-deploy.sh` L1491 | inngest rolling-deploy pull | same |
| 3 | `ci-deploy.sh` `verify_image_signature` L585-632 (cosign `docker run … verify --offline` L605-612) | cosign verify | sig-fetch registry = `RepoDigests[0]` of the pulled image → auto-follows the pull registry; ADD zot `auths` to the mounted `$GHCR_DOCKER_CONFIG` + `--allow-insecure-registry` when the pulled ref is zot |
| 4 | `soleur-host-bootstrap.sh` L172-199 (login only) | fresh-boot host login | add a zot `docker login 10.0.1.30:5000` (gated) beside the GHCR login; beacon via `_sentry_emit` |
| 5 | `cloud-init.yml` L449 (login) / L452,L545 (pull) | fresh-boot web seed + app pull | zot-first (gated) else GHCR; beacon via `soleur-boot-emit` (later blocks) / STAGE-trap (seed block) |
| 6 | `cloud-init.yml` L591/596/606 (hardcoded `ghcr.io/…/soleur-inngest-bootstrap:v1.1.18` ×3) | fresh-boot inngest extract (MISSED site) | zot-first (gated) else GHCR — swap all 3 refs consistently; beacon `soleur-boot-emit inngest_bootstrap` |
| 7 | `apply-web-platform-infra.yml` L1070/L1075 (imagetools digest-resolve, `docker login ghcr` w/ GITHUB_TOKEN) | CI runner digest resolve | **STAYS GHCR** — the GitHub runner cannot reach the private `10.0.1.30` net. It resolves the digest from GHCR; hosts pull that SAME digest from zot (crane-copy preserves digests). Documented, not migrated. |
| 8 | `plugins/soleur/skills/deploy/scripts/deploy.sh` L22 | tenant/user-facing deploy template | **OUT-SCOPE** — generic soleur:deploy skill (tenant registry/host, no Doppler/beacon/cosign/ZOT_* access). Migrating needs a separate tenant-zot story out of Phase-3 scope. |

## Two hard migration edges (plan under-specified)

### Edge A — `insecure-registries` has no running-host delivery
zot serves plain HTTP on `10.0.1.30:5000`; docker refuses a non-TLS registry unless
`daemon.json.insecure-registries` lists it. `daemon.json` is written in exactly ONE place —
`cloud-init.yml` L412 (fresh boot only), then `systemctl restart docker` L422. There is NO
running-host delivery (unlike host-scripts, which have `terraform_data.*` SSH mirrors). So:
- **Fresh hosts:** add `"insecure-registries": ["10.0.1.30:5000"]` to the cloud-init L413 daemon.json.
- **Running hosts (rolling ci-deploy):** need a NEW `terraform_data.registry_insecure_config` SSH
  push (mirror `journald`/`cosign-root` provisioner pattern) that writes daemon.json +
  `systemctl reload docker` — and it must be added to the SSH `-target` list + the parity test's
  SSH-provisioned set. (SSH-provisioned terraform_data → the FIRST parity guard, whose exclusion
  allowlist is only `root_authorized_keys` → it MUST be in the workflow SSH `-target` list, NOT
  OPERATOR_APPLIED_EXCLUSIONS. This is the one #6122 resource that is CI-`-target`ed.)
  NOTE: `127.0.0.1`/loopback is auto-insecure to docker; only the private IP `10.0.1.30:5000` needs
  the flag. `docker reload` (SIGHUP) picks up insecure-registries without a full restart.

### Edge B — cosign `.sig` fetch from zot (plain HTTP)
`verify_image_signature` (Site 3) fetches the `.sig` referrer for `RepoDigests[0]` — the registry the
image was pulled from. A zot-pulled image → cosign fetches from `10.0.1.30:5000` over HTTP → needs
`--allow-insecure-registry` on the `cosign verify` invocation (L608) AND a zot `auths` entry in the
`:ro`-mounted `$GHCR_DOCKER_CONFIG`. The atomic-switch requirement (plan P1-4) means: when the pull
falls back to GHCR, the cosign ref (RepoDigest) is GHCR and no insecure flag is used — the three move
together automatically because RepoDigest tracks the pull source. Phase-0 proved cosign verifies a
zot-stored `.sig` (registry-agnostic identity); the only new bits are the insecure flag + zot auths.

## Phase-3 entry-gate script (Pre-merge AC)
`scripts/followthroughs/` or `apps/web-platform/infra/` helper that, given both images' currently-
deployed tags, asserts each resolves in zot (`crane manifest 10.0.1.30:5000/<img>:<tag>` or a
`/v2/<img>/manifests/<tag>` HEAD with the pull cred) BEFORE any flip. Exit non-zero blocks the flip.
This is the runtime expression of the dark-launch gate; it can only PASS post-provisioning+backfill,
which is why the flip "trails dual-push by ≥1 release" (plan Phase 3).

## Staging note
The pull-site edits land in this PR **dark** (gated off until zot is confirmed live+populated), so the
deploy-critical flip is a no-op until the operator provisions the host (1.8) + backfills (1.9) + the
entry gate passes. This honours the plan's Pre-merge ACs (edits present, fallback + beacon wired)
without a degraded window between merge and provisioning.
