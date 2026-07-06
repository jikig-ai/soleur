---
feature: feat-one-shot-6090-web2-boot-observability
plan: knowledge-base/project/plans/2026-07-06-fix-web2-fresh-boot-observability-plan.md
tracker: "#6090"
lane: single-domain
brand_survival_threshold: none
deepened: 2026-07-06
---

# Tasks — web-2 fresh-boot observability (#6090)

> Off-host observability **probe** (not the boot fix). Makes the last-reached fresh-boot stage visible in Sentry so one post-merge recreate names the failing stage. `Ref #6090` (not `Closes`). Deepened by 4 reviewers — load-bearing additions: **readiness gates** (async-service death detector) and **EU Sentry endpoint** fix.

## Phase 0 — Preconditions (no host writes)

- [ ] 0.1 (B) Confirm cosign ENFORCE is NOT the cause (code-read): #6023 unmerged, `IMAGE_VERIFY_MODE:-warn`, no `enforce` setter, cosign absent from cloud-init, trusted root installed pre-sentinel (`soleur-host-bootstrap.sh:81`). PR-body conclusion. No code change.
- [ ] 0.2 user_data byte budget: render `templatefile("cloud-init.yml", …)` + `wc -c` (baseline ~29.6 KB / ~3 KB headroom, `server.tf:56`). Default = **single shared `soleur-boot-emit` helper written once** (inline `cat >`), NOT per-block `on_err` duplication. Bake only if still over 32,768. Pin bytes + shape in PR body.
- [ ] 0.3 Confirm `${sentry_dsn}` wired into the cloud-init templatefile (`server.tf:138`).
- [ ] 0.4 **(H3) Empirically pin cloud-init errexit scoping** — render `/var/lib/cloud/instance/scripts/runcmd`; does `set -e` from the extraction block (354) leak to the bare cloudflared `apt` (437)? If yes with no active trap, that is a candidate root cause → scope-fix it in this PR. Pin finding (leaks/does-not) in PR body.
- [ ] 0.5 Read `apps/web-platform/infra/scripts/web2-recreate-preflight.sh` — confirm it fail-closes a stale-image recreate (hash mismatch → abort). Cite in IaC section.

## Phase 1 — soleur-host-bootstrap.sh (baked)

- [ ] 1.1 One `_sentry_emit <level> <json-tags>` helper; DSN preference `${SOLEUR_SENTRY_DSN:-<doppler>}` in one place. Migrate `emit_fail` (34-52) + `ghcr_login_warn` (168-180).
- [ ] 1.2 Single `bootstrap_complete` breadcrumb (region:bootstrap) immediately before `/run/soleur-hostscripts.ok` (199). Drop the 6 per-stage breadcrumbs (emit_fail already tags stage) + the `_breadcrumb` wrapper.
- [ ] 1.3 Fail-open: emit call in `( set +e; … ) || true` subshell.
- [ ] 1.4 Emit body classification/enum only.

## Phase 2 — cloud-init.yml post-bootstrap region

- [ ] 2.1 Line 412: add `SOLEUR_SENTRY_DSN='${sentry_dsn}'` to the bootstrap invocation.
- [ ] 2.2 Shared `soleur-boot-emit <stage> <level>` written once (Phase 0.2 shape); tags `{stage, host_id, region:cloud-init}`; all calls `|| true`.
- [ ] 2.3 Entry breadcrumbs as separate runcmd items; bare tolerant commands use `cmd || soleur-boot-emit <stage> warning` (NO new `set -e`+`exit 1`). Stages: volume_mount(417-431), cloudflared(433-441), webhook(444-453), host_timers(455-477), app_image_pull(480, own stage), plugin_seed(492), inngest_bootstrap(523).
- [ ] 2.4 **Readiness gates (load-bearing):** after cloudflared enable → `cloudflared_ready` (poll `systemctl is-active --quiet cloudflared`); after webhook enable → `webhook_bound` (poll `:9000` bind via `curl -sf localhost:9000` / `ss -ltn 'sport = :9000'`). Bounded timeout; on timeout `soleur-boot-emit <stage> fatal` + `exit 1`. These NEW blocks are legitimately `set -e`.
- [ ] 2.5 Composite-trap merge on plugin_seed(496)/inngest(528): `trap 'rc=$?; cleanup; [ "$rc" = 0 ] || soleur-boot-emit <stage> fatal' EXIT` — never a second trap.
- [ ] 2.6 Terminal block (555-600): sub-stage `doppler_download`(568) vs `docker_run`(580); `cloud_init_complete` breadcrumb after the egress probe (597). Document poweroff paths (563/599) rely on Better Stack absence, not the emit.

## Phase 3 — apply-web-platform-infra.yml

- [ ] 3.1 **Fix the Sentry endpoint host to EU** (`de.sentry.io`, derive from DSN residency) at line 1212 — load-bearing; add a test asserting host↔DSN parity.
- [ ] 3.2 Extend the QUERY (1207) to the new downstream fatal + `bootstrap_complete`/`webhook_bound` breadcrumb literals (byte-lockstep with the emit sites); most-recent sort.
- [ ] 3.3 Surface the breadcrumb trail `if: always()` (not only failure()) so a green boot shows the probe fired.
- [ ] 3.4 Verify `fresh-host Sentry pointer` literal lands in `gh run view --log`; else point discoverability at the summary artifact.

## Phase 4 — Tests (write first) + wire

- [ ] 4.1 `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh`: AC2 (DSN pass), AC3 (DSN preference), AC4 (bootstrap_complete order), AC5 (enclosure shape, not per-line), AC6 (readiness gates + `:9000`), AC6b (no inversion + composite trap), AC8 (byte-equality lockstep), AC8b (EU endpoint parity).
- [ ] 4.2 Wire into `.github/workflows/infra-validation.yml` (mirror line 160).
- [ ] 4.3 Run all existing `apps/web-platform/infra/*.test.sh`. (No `tsc` — no TS touched.)

## Phase 5 — Ship (pre-merge)

- [ ] 5.1 PR body: Pre-merge/Post-merge AC split; `Ref #6090`; cosign-B + H3 findings; user_data bytes; helper shape.
- [ ] 5.2 Review + merge (do NOT `Closes #6090`).

## Post-merge (operator + verification — NOT in the code PR)

- [ ] P1 [automatable] Confirm `web-platform-release.yml` rebuilt `${image_name}` before recreate; `web2-recreate-preflight.sh` is the real fail-closed gate (AC11).
- [ ] P2 [automatable] Quiet-window go/no-go: 0 in-progress release + web-1 `exit_code=0` + `app.soleur.ai/health`=200 (AC12).
- [ ] P3 [operator-ack] `gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate -f reason='#6090 …'` — menu-ack gated; NEVER web-1 (AC13).
- [ ] P4 [automated + fallback] Read named stage from the recreate run summary (EU endpoint) or the `de.sentry.io` curl (AC14).
- [ ] P5 [verification] Sentry event names the stage/region (or webhook_bound fatal); (AC15).
- [ ] P6 [branch] Died → file stage-fix issue, keep #6090 open. Booted green (`:9000` binds + fan-out `ok` + `if:always()` breadcrumb confirms probe fired) → close #6090 (AC16).
