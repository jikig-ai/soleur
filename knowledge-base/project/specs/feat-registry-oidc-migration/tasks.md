---
feature: registry-oidc-migration
issue: "#6122"
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-06-feat-registry-oidc-migration-plan.md
---

# Tasks — Registry migration off GHCR to self-hosted zot (Hetzner registry host, volume-backed)

## Phase 0 — De-risking spikes (no production writes)
- [ ] 0.1 Local zot (docker, upstream digest-pinned image) + local-fs storage; push+pull both images; confirm read-only htpasswd ACL (pull ok / push denied) + gc/dedupe on singleton
- [ ] 0.2 cosign: sign a zot-stored digest; offline-verify; assert read-only user fetches `sha256-<digest>.sig`/`.att`; assert gc does not reap `.sig`; confirm `COSIGN_IDENTITY_REGEXP` unchanged
- [ ] 0.3 Confirm `crane copy` (or `skopeo copy`) mirrors a GHCR tag → zot (backfill mechanism)
- [ ] 0.4 Re-verify next ADR ordinal vs origin/main (provisional 093)

## Phase 1 — IaC foundations + backfill (additive; GHCR primary)
- [ ] 1.1 `apps/web-platform/infra/zot-registry.tf`: `hcloud_server.registry` (CAX11) + `hcloud_volume` (attached, `/var/lib/zot`) on the private network
- [ ] 1.2 cloud-init for the registry host: docker + zot systemd unit (Inngest pattern), local-fs storage, htpasswd, read-only/push ACLs
- [ ] 1.3 `random_password.zot_pull` + `random_password.zot_push`; `doppler_secret` ZOT_REGISTRY_URL/PULL_USER/PULL_TOKEN/PUSH_USER/PUSH_TOKEN (no `ignore_changes`)
- [ ] 1.4 `firewall.tf`: registry host reachable from web hosts on private network; keep GHCR egress through soak; any web_hosts `for_each` uses the `monitored` existence-flag gate
- [ ] 1.5 Volume snapshot cron
- [ ] 1.6 **Append every new zot resource address to `apply-web-platform-infra.yml` `-target=` list** (else silent no-apply)
- [ ] 1.7 `uptime-alerts.tf`: zot `/v2/` Better Stack monitor
- [ ] 1.8 Deploy; verify `/v2/` reachable on private network + monitor green
- [ ] 1.9 Backfill last N releases of BOTH images GHCR→zot + the pinned `v1.1.18` (inngest) + `:latest` (web)

## Phase 2 — Push side (dual-push)
- [ ] 2.1 `build-inngest-bootstrap-image.yml:131-194` → also push to zot (ZOT_PUSH_* via Doppler)
- [ ] 2.2 `reusable-release.yml:425-432,580-611` → also push to zot
- [ ] 2.3 `reusable-release.yml:626-640` → cosign-sign the zot digest
- [ ] 2.4 CI evidence: a tag build is pullable + signed from zot

## Phase 3 — Pull side (flip zot-primary + atomic GHCR fallback + per-site beacon)
- [ ] 3.1 `ci-deploy.sh`: web login/pull (`:535-569`,`:1025`) → zot-primary; atomic fallback (image+docker-config auth+sig target); beacon fields
- [ ] 3.2 `ci-deploy.sh`: inngest pull (`:1492`) → same
- [ ] 3.3 `ci-deploy.sh`: cosign verifier config mount (`:600-606`) → switch registry auth with the fallback
- [ ] 3.4 `soleur-host-bootstrap.sh:172-199` (corrected) → zot-primary + fallback + beacon (`:190`)
- [ ] 3.5 `cloud-init.yml`: web fresh-boot extract (`:440-452`,`:545`) → zot-primary + fallback + beacon
- [ ] 3.6 `cloud-init.yml`: **inngest fresh-boot extract `:591-606`** (missed site) → same
- [ ] 3.7 `apply-web-platform-infra.yml:1070` (imagetools digest-resolve + `docker login ghcr`) → point at zot
- [ ] 3.8 `plugins/soleur/skills/deploy/scripts/deploy.sh:17-25` → migrate or out-scope with rationale
- [ ] 3.9 Phase-3 entry-gate script: verify both images' deployed tags resolve in zot before flip

## Phase 4 — cosign continuity
- [ ] 4.1 Confirm offline verify passes on BOTH zot-primary and GHCR-fallback branches
- [ ] 4.2 Trust root + identity regexp unchanged; no cosign version bump

## Phase 5 — Cutover, soak, retirement (soak-gated)
- [ ] 5.1 `scripts/followthroughs/zot-soak-6122.sh` (zero ghcr-fallback across min-sample incl fresh-boot of each image; per-`image` count) + directive + `follow-through` label + sweeper `secrets=`
- [ ] 5.2 Revert runbook (Phase-3 → GHCR-primary) + fallback-rate alarm (`>X%`/`Yh` ⇒ page+revert), distinct from soak-close
- [ ] 5.3 (post-soak) remove fallback branch; stop GHCR push; remove GHCR egress allow
- [ ] 5.4 (post-soak) retire `cron-ghcr-token-minter.ts` + test + `ghcr-minter-doppler-token.tf` + `ghcr-read-credential.tf` + `GHCR_MINTER_DISABLED` gate
- [ ] 5.5 (post-soak, after fallback-removal deploy confirmed on all hosts) rotate + revoke the leaked classic PAT
- [ ] 5.6 Flip ADR-093 status adopting → accepted

## Phase 6 — ADR/C4 + docs
- [ ] 6.1 ADR-093 via `/soleur:architecture` (7-alt table + cold-boot-dependency statement; status: adopting)
- [ ] 6.2 Edit `model.c4`+`views.c4`+`spec.c4` (add `zotRegistry`, move host pull edge GHCR→zot, correct `ghcr` desc)
- [ ] 6.3 Run `c4-code-syntax.test.ts` + `c4-render.test.ts`
- [ ] 6.4 Update runbooks naming GHCR pull

## Cross-cutting (pre-PR-ready)
- [ ] X.1 Record recurring registry-host expense (~€4/mo) via ops-advisor
- [ ] X.2 Typecheck `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; run test suite via vitest
- [ ] X.3 File deferred HA/read-replica follow-up issue (done at plan time — see issue link)
