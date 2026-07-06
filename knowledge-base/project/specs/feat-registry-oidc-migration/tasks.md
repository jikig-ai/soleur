---
feature: registry-oidc-migration
issue: "#6122"
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-06-feat-registry-oidc-migration-plan.md
---

# Tasks — Registry migration off GHCR to self-hosted zot (Hetzner registry host, volume-backed)

## Phase 0 — De-risking spikes (no production writes)
- [x] 0.1 Local zot (docker, upstream digest-pinned image) + local-fs storage; push+pull both images; confirm read-only htpasswd ACL (pull ok / push denied) + gc/dedupe on singleton — evidence: `phase-0-spike-evidence.md` (ACL push→403; dedupe+gc clean)
- [x] 0.2 cosign: sign a zot-stored digest; offline-verify; assert read-only user fetches `sha256-<digest>.sig`/`.att`; assert gc does not reap `.sig`; confirm `COSIGN_IDENTITY_REGEXP` unchanged — evidence: legacy `.sig` tag fetched by read-only user; survives aggressive-gc; regexp registry-agnostic (ci-deploy.sh:52)
- [x] 0.3 Confirm `crane copy` (or `skopeo copy`) mirrors a GHCR tag → zot (backfill mechanism) — evidence: GHCR→zot digest-identical copy
- [x] 0.4 Re-verify next ADR ordinal vs origin/main (provisional 093) — latest committed = ADR-092; 093 free

## Phase 1 — IaC foundations + backfill (additive; GHCR primary)
- [x] 1.1 `apps/web-platform/infra/zot-registry.tf`: `hcloud_server.registry` (cax11) + `hcloud_volume.registry` (attached, `/var/lib/zot`) + `hcloud_server_network.registry` (10.0.1.30) on the private network — mirrors `git-data.tf` (NOT inngest.tf). fmt+validate green
- [x] 1.2 `cloud-init-registry.yml`: docker.io + digest-pinned zot **container** (`--restart unless-stopped`; upstream image was the Phase-0 precedent, not a systemd unit — matches web-host runcmd docker-run), local-fs storage, htpasswd (on-host `htpasswd -Bbn` from Doppler tokens), deny-by-default read-only/push ACLs. Rendered + `cloud-init schema` valid (6648B raw); zot boots + serves the authored config.json (401 unauth / 200 authed, no config errors)
- [x] 1.3 `random_password.zot_pull` + `random_password.zot_push`; `doppler_secret` ZOT_REGISTRY_URL/PULL_USER/PULL_TOKEN/PUSH_USER/PUSH_TOKEN in `prd` (no `ignore_changes`) + host-scoped ZOT_PULL_TOKEN/ZOT_PUSH_TOKEN in operator-created `prd_registry` config (least-privilege, mirrors git-data-luks `prd_git_data`)
- [x] 1.4 Deny-all-public `hcloud_firewall.registry` + attachment (private-net reachability is automatic via network membership — no allow rule, mirrors `git_data`); GHCR egress stays (no explicit egress rule needed — firewall denies only public *ingress*). Registry is a singleton (no `for_each var.web_hosts`) → no `monitored`-flag gate needed
- [~] 1.5 Volume snapshot cron — **DEFERRED (inline-triaged): durability = CI-reproducibility (plan's stated primary; images rebuildable + backfill re-runnable). A host-side hcloud token would expand the registry host's blast radius; if added it belongs as a GHA-side scheduled snapshot job, filed as a fast-follow (not merge-blocking for a CI-reproducible registry).** See plan Sharp Edges.
- [x] 1.6 **(CTO-REVISED)** added all 18 zot resources to `OPERATOR_APPLIED_EXCLUSIONS` (+ `doppler_service_token.registry` to `OPERATOR_APPLIED_TOKEN_EXCLUSIONS`) in `terraform-target-parity.test.ts` (40 tests green); added NONE to the workflow `-target=` list (git-data model). See `apply-path-cto-ruling.md`
- [x] 1.7 Liveness = `betteruptime_heartbeat.registry_prd` push heartbeat in `zot-registry.tf` (no public ingress → no pull monitor; paused=true+ignore_changes until probe cron ships); reuses the inngest escalation policy; mirrors `git_data_prd`
- [ ] 1.8 Deploy; verify `/v2/` reachable on private network + heartbeat green — **operator full apply (post-merge; requires `prd_registry` Doppler config precondition + live Hetzner provisioning)**
- [ ] 1.9 Backfill last N releases of BOTH images GHCR→zot + the pinned `v1.1.18` (inngest) + `:latest` (web) — **post-provisioning (crane copy; needs the live zot host)**

## Phase 2 — Push side (dual-push)
- [x] 2.0 NEW `cf-tunnel-registry-bridge` composite action (CI→private-net zot push via the existing web CF Tunnel; CTO ruling 2). `cloudflared access tcp … 127.0.0.1:5000` + `docker login` (CF Access registry_push token + zot-push htpasswd from Doppler)
- [x] 2.1 `build-inngest-bootstrap-image.yml` → dual-push (docker tag+push 127.0.0.1:5000; plain build → local docker, no crane). Not cosign-signed (no id-token perm — GHCR parity)
- [x] 2.2 `reusable-release.yml` → dual-push web image via `crane copy` GHCR→zot RUNNER-SIDE (buildx container driver can't reach the runner bridge; digest preserved). Bridge continue-on-error + if:always() teardown (additive — zot failure never fails GHCR)
- [x] 2.3 `reusable-release.yml` → cosign-sign the zot digest (same digest; host offline-verify passes, COSIGN_IDENTITY_REGEXP unchanged)
- [ ] 2.4 CI evidence: a tag build is pullable + signed from zot — **post-provisioning (needs live zot + a tag build)**

## Phase 3 — Pull side (flip zot-primary + atomic GHCR fallback + per-site beacon)
**Design + verified site map: `phase-3-pull-site-design.md`. Dark-launch gated (attempt zot only when confirmed-configured, else unchanged GHCR) → SAFE to land before the host is provisioned (1.8) + backfilled (1.9); honours the plan's "flip trails dual-push by ≥1 release".**
- [x] 3.0a **(Edge A, fresh hosts — DONE)** `cloud-init.yml:412` daemon.json → added `"insecure-registries": ["10.0.1.30:5000"]`. Safe/additive (nothing pulls from zot until the flip). Valid JSON, quoted heredoc (no interpolation).
- [x] 3.0b **(Edge A, running hosts — HIGH-RISK, defer to flip-activation)** NEW SSH-provisioned `terraform_data.registry_insecure_config` (web hosts; CI-`-target`ed + SSH parity set) → writes daemon.json + `docker RELOAD` (SIGHUP, not restart). Mutates the prod docker daemon → author with fresh context + a malformed-JSON guard; only needed when zot-primary activates on running hosts (post-provisioning). Mirror `terraform_data.journald_persistent` (server.tf).
- [x] 3.1 `ci-deploy.sh`: web login/pull (`ghcr_prelude_and_login` L547/L1002, pull L1024) → zot-primary (gated); atomic fallback (image+docker-config auth+sig target); beacon via `pull_failure_event`+`final_write_state`
- [x] 3.2 `ci-deploy.sh`: inngest pull (L1491) → same
- [x] 3.3 `ci-deploy.sh`: cosign `verify_image_signature` (L585-632) → sig-fetch auto-follows RepoDigest; add zot `auths` + `--allow-insecure-registry` on the zot branch (Edge B)
- [x] 3.4 `soleur-host-bootstrap.sh` L172-199 → add gated zot `docker login` beside GHCR; beacon via `_sentry_emit`
- [x] 3.5 `cloud-init.yml`: web fresh-boot seed+app (L449 login, L452/L545 pull) → zot-primary (gated) + fallback + beacon (`soleur-boot-emit`)
- [x] 3.6 `cloud-init.yml`: **inngest fresh-boot extract L591/596/606** (missed site; hardcoded `v1.1.18` ×3) → same
- [x] 3.7 `apply-web-platform-infra.yml:1070` → **STAYS GHCR** (runner can't reach the private net; resolves the digest from GHCR, hosts pull the same digest from zot). Documented in `phase-3-pull-site-design.md` §Site 7
- [x] 3.8 `plugins/soleur/skills/deploy/scripts/deploy.sh` → **OUT-SCOPE** (tenant-facing template; no Doppler/beacon/cosign/ZOT_* access). Documented in `phase-3-pull-site-design.md` §Site 8
- [x] 3.9 Phase-3 entry-gate script: verify both images' deployed tags resolve in zot before flip (runtime expression of the dark-launch gate)

## Phase 4 — cosign continuity
- [x] 4.1 Confirm offline verify passes on BOTH zot-primary and GHCR-fallback branches
- [x] 4.2 Trust root + identity regexp unchanged; no cosign version bump

## Phase 5 — Cutover, soak, retirement (soak-gated)
- [x] 5.1 `scripts/followthroughs/zot-soak-6122.sh` (zero ghcr-fallback across min-sample incl fresh-boot of each image; per-`image` count) + directive + `follow-through` label + sweeper `secrets=`
- [x] 5.2 Revert runbook (Phase-3 → GHCR-primary) + fallback-rate alarm (`>X%`/`Yh` ⇒ page+revert), distinct from soak-close
- [ ] 5.3 (post-soak) remove fallback branch; stop GHCR push; remove GHCR egress allow
- [ ] 5.4 (post-soak) retire `cron-ghcr-token-minter.ts` + test + `ghcr-minter-doppler-token.tf` + `ghcr-read-credential.tf` + `GHCR_MINTER_DISABLED` gate
- [ ] 5.5 (post-soak, after fallback-removal deploy confirmed on all hosts) rotate + revoke the leaked classic PAT
- [ ] 5.6 Flip ADR-096 status adopting → accepted

## Phase 6 — ADR/C4 + docs
- [x] 6.1 ADR-096 via `/soleur:architecture` (7-alt table + cold-boot-dependency statement; status: adopting)
- [x] 6.2 Edit `model.c4`+`views.c4`+`spec.c4` (add `zotRegistry`, move host pull edge GHCR→zot, correct `ghcr` desc)
- [x] 6.3 Run `c4-code-syntax.test.ts` + `c4-render.test.ts`
- [x] 6.4 Update runbooks naming GHCR pull

## Cross-cutting (pre-PR-ready)
- [x] X.1 Record recurring registry-host expense (~€4/mo) via ops-advisor
- [x] X.2 Typecheck `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; run test suite via vitest
- [x] X.3 File deferred HA/read-replica follow-up issue (done at plan time — see issue link)
