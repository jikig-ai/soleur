---
feature: registry-oidc-migration
issue: "#6122"
phase: 0
kind: de-risking-spike-evidence
date: 2026-07-06
env: local docker (no production writes)
---

# Phase 0 — De-risking Spike Evidence

All spikes run locally against a throwaway zot container (`ghcr.io/project-zot/zot-linux-amd64@sha256:073f30d99fbdbcd8869334231c9ca45c75e535e4bdc6e28cc8a1541abe7a3f71`, i.e. `v2.1.2`, **digest-pinned** — this is the upstream-image pinning the registry-host cloud-init will use). Storage = local filesystem (`/var/lib/zot`), the volume-backed model the plan adopts. **No production writes.** Tooling pinned: `cosign v2.4.1`, `crane v0.20.2`.

## 0.1 — Local zot, local-fs storage, push/pull both images, read-only htpasswd ACL, gc/dedupe

- **Config:** local-fs `rootDirectory`, `dedupe: true`, `gc: true`, htpasswd auth (bcrypt via `htpasswd -Bbn`), `accessControl` — `zot-pull` user `["read"]`, `zot-push` user `["read","create","update"]`, `defaultPolicy: []` (deny-by-default). This is exactly the shape Terraform's `random_password.zot_pull`/`zot_push` + zot config will generate.
- **Reachability:** unauth `GET /v2/` → **401**; `zot-pull` authed `GET /v2/` → **200**.
- **Push (as `zot-push`):** `crane copy` mirrored two stand-in images →
  - `soleur-web-platform:latest` (alpine stand-in) → pushed, digest `sha256:d9e853…4b6bc`
  - `soleur-inngest-bootstrap:v1.1.18` (busybox stand-in) → pushed
  - (real images are GHCR-private; stand-ins exercise the identical push/ACL/storage path)
- **Pull (as `zot-pull`, read-only):** manifest read OK, `crane pull` tarball OK.
- **ACL enforcement (the load-bearing assertion):** `zot-pull` attempting `crane copy … soleur-web-platform:evil` → **DENIED, HTTP 403.** Read-only credential cannot push. ✅
- **dedupe/gc on singleton:** dedupe task ran clean on startup; gc completed per-repo without error (see 0.2).

## 0.2 — cosign: sign a zot-stored digest, offline verify, `.sig` ACL, gc-not-reaping, identity regexp

- **Signing scope note:** true *keyless* signing (Fulcio + Rekor + GitHub-Actions OIDC) is not locally reproducible without an OIDC provider. The **registry-specific** risk this spike must de-risk is whether **zot stores/serves the `.sig` and gc retains it** — that is fully exercised with key-based signing (`cosign generate-key-pair` + `cosign sign --key`). The keyless identity is registry-agnostic (below).
- **Sign:** `cosign sign --key cosign.key --tlog-upload=false localhost:5000/soleur-web-platform@sha256:d9e853…` → signature pushed to zot.
- **`.sig` tag scheme:** cosign wrote the **legacy `sha256-<digest>.sig` tag** (`sha256-d9e853…4b6bc.sig`) — the scheme the plan/AC references. `cosign triangulate` resolves it.
- **Read-only `.sig` ACL:** `zot-pull` (read-only) **can fetch** the `.sig` tag manifest. ✅ (verify path only needs read.)
- **Offline verify:** `cosign verify --key cosign.pub --insecure-ignore-tlog=true …@<digest>` → "signatures were verified against the specified public key". ✅
- **gc does NOT reap the `.sig` (referrers handling):** restarted zot with aggressive gc (`gcDelay=2s`, `gcInterval=3s`), waited through ≥2 gc cycles (logs show "executing gc … / gc successfully completed"), then re-checked:
  - subject digest → **survives** ✅
  - `sha256-<digest>.sig` tag → **survives** ✅ (it is itself a *tagged* manifest, so the untagged-manifest sweep never touches it)
  - offline verify after gc → **still passes** ✅
- **`COSIGN_IDENTITY_REGEXP` unchanged / registry-agnostic:** confirmed in `apps/web-platform/infra/ci-deploy.sh:52` — the regexp matches the **GitHub Actions workflow identity** (`^https://github.com/jikig-ai/soleur/.github/workflows/reusable-release.yml@…$`), i.e. the Fulcio cert SAN. It is independent of the registry host; only the image-reference argument to `cosign verify` (ci-deploy.sh:600-611) changes in the zot/GHCR-fallback branches. No change needed. ✅

## 0.3 — crane copy GHCR → zot (backfill mechanism)

- `crane copy ghcr.io/project-zot/zot-linux-amd64:v2.1.2  localhost:5000/backfill-zot:v2.1.2` (public GHCR source).
- **Digest identity:** source `sha256:073f30d…a3f71` == zot dest `sha256:073f30d…a3f71`. `crane copy` is content-addressable/preserving → backfill mirrors tags without re-digesting. ✅ (real backfill copies GHCR-private tags under the interim classic PAT; mechanism identical.)

## 0.4 — ADR ordinal re-verified vs origin/main

- Latest committed ADR on this branch = **ADR-092**. Next free = **ADR-093** — the plan's provisional ordinal holds. (Ship's collision gate re-verifies; on renumber sweep plan+spec+tasks per Sharp Edges.)

## Carry-forward to Phase 1+

1. zot config shape (deny-by-default `accessControl`, `read` vs `read,create,update`, `dedupe`+`gc`) is validated — reuse verbatim in the registry-host cloud-init.
2. Use the **legacy `sha256-<digest>.sig` tag** expectation in any Phase-3 entry-gate / sig-fetch assertions.
3. gc is safe on the singleton with signatures present — no `gcReferrers`-specific tuning needed beyond `gc: true`.
4. Backfill = `crane copy` per tag; digests preserved so cosign sigs (also copied by tag) stay valid.
