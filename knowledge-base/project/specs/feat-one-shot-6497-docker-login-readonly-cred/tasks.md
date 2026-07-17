---
feature: feat-one-shot-6497-docker-login-readonly-cred
plan: knowledge-base/project/plans/2026-07-17-fix-web-platform-docker-login-erofs-cred-path-plan.md
issue: 6565
refs: [6497]
lane: single-domain
brand_survival_threshold: aggregate pattern
---

# Tasks — fix web-platform docker-login EROFS (relocate DOCKER_CONFIG off ProtectHome)

Recommended fix: **Option 2** — relocate the deploy-user docker config onto `/mnt/data` (already a `ReadWritePath`) via one exported `DOCKER_CONFIG` in `ci-deploy.sh`. Single-file fix + test + repair soak. Reaches web-1 hot (no power-off), web-2 via the sanctioned recreate dispatch.

## Phase 0 — Prove the one unmeasured link

- [ ] 0.1 Cite prod evidence (no synthetic re-run): EROFS on `/home/deploy/.docker` (telemetry `kw=errsaving,erofs`, 55 lines); `/mnt/data` writable under `webhook.service` (existing `/mnt/data/workspaces/.deploy-lease` writes, `ci-deploy.sh:241`).
- [ ] 0.2 MEASURED check: `tmp=$(mktemp -d); DOCKER_CONFIG="$tmp" docker login <reg> -u <u> --password-stdin <<<"<tok>" && test -f "$tmp/config.json"` — proves `docker login` honors `DOCKER_CONFIG` as the config dir. Pin output into PR body.

## Phase 1 — Relocate DOCKER_CONFIG in ci-deploy.sh

- [ ] 1.1 At `ci-deploy.sh:~69`: add `readonly DEPLOY_DOCKER_CONFIG_DIR="${DEPLOY_DOCKER_CONFIG_DIR:-/mnt/data/deploy-docker}"`, `export DOCKER_CONFIG="$DEPLOY_DOCKER_CONFIG_DIR"`, fail-soft `mkdir -p`/`chmod 700`.
- [ ] 1.2 Derive `readonly GHCR_DOCKER_CONFIG="${DOCKER_CONFIG}/config.json"` from the exported `DOCKER_CONFIG` (single source of truth — NOT `${GHCR_DOCKER_CONFIG:-...}`; arch-strategist Finding 1).
- [ ] 1.3 Do NOT touch the boot-bake `runcmd` (`cloud-init.yml:487/495/508`) — root/`/root/.docker`, separate lifecycle.
- [ ] 1.4 (optional hardening) `mountpoint -q /mnt/data` warning breadcrumb; skip cosign `-v` config mount arg when the config file is absent.

## Phase 2 — Extend ci-deploy.test.sh

- [ ] 2.1 Assert `GHCR_DOCKER_CONFIG` assignment resolves under `/mnt/data`, no assignment default under `/home/deploy` — anchor to the assignment line, strip comments (`cq-assert-anchor-not-bare-token`); if asserting no `docker --config`, match `docker[[:space:]].*--config` not bare `--config`.
- [ ] 2.2 Assert `$GHCR_DOCKER_CONFIG == ${DOCKER_CONFIG}/config.json` by construction (login-write == cosign-mount source).
- [ ] 2.3 Harness sets `DEPLOY_DOCKER_CONFIG_DIR="$(mktemp -d)"` before sourcing `ci-deploy.sh` (source-time export/mkdir runs on the GH runner where `/mnt/data` is absent).
- [ ] 2.4 Confirm existing cosign-mount (`:1472`) + recovery-relogin (`:3456-3466`) tests still pass; add a note that T16/T20/T21 `/home/deploy/.docker` fixtures are pre-fix, path-agnostic, intentionally retained.
- [ ] 2.5 `bash apps/web-platform/infra/ci-deploy.test.sh` green.

## Phase 3 — Repair follow-through soak (on #6565)

- [ ] 3.1 Create `scripts/followthroughs/zot-login-gate-erofs-repaired-6565.sh` (thin wrapper reusing the instrument soak's Better Stack query helper).
- [ ] 3.2 PASS = ≥2 distinct `host_id`s, EACH with ≥1 `ZOT_GATE: active … ok`/`PRELUDE: … ok` line AND zero `class=cred_store`/`kw=erofs` FAILED; TRANSIENT if <2 host_ids or any host silent; FAIL on any cred_store/erofs line. Discover host_ids from the window (do not hardcode — web-2 recreate mints a new one).
- [ ] 3.3 Enroll on **#6565** (repair issue) with `follow-through` label + `<!-- soleur:followthrough script=… earliest=<max both hosts' first post-fix deploy> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->`. Do NOT enroll on #6497 (instrument soak would auto-close it).

## Phase 4 — Delivery + verification (ship-driven, operator ACK only)

- [ ] 4.1 Merge → `apply-deploy-pipeline-fix.yml` hot-pushes ci-deploy.sh to web-1; force a web-1 deploy (re-deploy pinned version) so the deploy-user login runs the relocated path.
- [ ] 4.2 Build-green gate: confirm `web-platform-release.yml` for the merge SHA is green + image pinned BEFORE web-2 recreate.
- [ ] 4.3 Operator ACK: `gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate` (passes `web2-recreate-preflight.sh`); force a web-2 deploy to exercise its deploy-user login.
- [ ] 4.4 Resolve `earliest=` to max(both forced-deploy timestamps); repair soak PASS across ≥2 host_ids → `gh issue close 6565`.

## Phase 5 — PR / ship

- [ ] 5.1 PR body: `Ref #6565` + `Ref #6497` (NOT Closes); pin Phase 0 MEASURED output; split pre-merge / post-redeploy ACs.
- [ ] 5.2 Ship renders `decision-challenges.md` (DC-1: Option 2 over presumptive Option 1) into PR body + files action-required issue.
- [ ] 5.3 `/compound` learning at ship: ProtectHome-relocate applied to `~/.docker` (extends `2026-04-06-doppler-protecthome-readonly-config-dir-fix.md`).
