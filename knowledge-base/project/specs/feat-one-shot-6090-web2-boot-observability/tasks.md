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

- [x] 0.1 (B) Confirm cosign ENFORCE is NOT the cause (code-read): #6023 unmerged, `IMAGE_VERIFY_MODE:-warn`, no `enforce` setter, cosign absent from cloud-init, trusted root installed pre-sentinel (`soleur-host-bootstrap.sh:81`). PR-body conclusion. No code change.
- [x] 0.2 user_data byte budget: render `templatefile("cloud-init.yml", …)` + `wc -c` (baseline ~29.6 KB / ~3 KB headroom, `server.tf:56`). Default = **single shared `soleur-boot-emit` helper written once** (inline `cat >`), NOT per-block `on_err` duplication. Bake only if still over 32,768. Pin bytes + shape in PR body.
- [x] 0.3 Confirm `${sentry_dsn}` wired into the cloud-init templatefile (`server.tf:138`).
- [x] 0.4 **(H3) Empirically pin cloud-init errexit scoping** — render `/var/lib/cloud/instance/scripts/runcmd`; does `set -e` from the extraction block (354) leak to the bare cloudflared `apt` (437)? If yes with no active trap, that is a candidate root cause → scope-fix it in this PR. Pin finding (leaks/does-not) in PR body.
- [x] 0.5 Read `apps/web-platform/infra/scripts/web2-recreate-preflight.sh` — confirm it fail-closes a stale-image recreate (hash mismatch → abort). Cite in IaC section.

## Phase 1 — soleur-host-bootstrap.sh (baked)

- [x] 1.1 One `_sentry_emit <level> <json-tags>` helper; DSN preference `${SOLEUR_SENTRY_DSN:-<doppler>}` in one place. Migrate `emit_fail` (34-52) + `ghcr_login_warn` (168-180).
- [x] 1.2 Single `bootstrap_complete` breadcrumb (region:bootstrap) immediately before `/run/soleur-hostscripts.ok` (199). Drop the 6 per-stage breadcrumbs (emit_fail already tags stage) + the `_breadcrumb` wrapper.
- [x] 1.3 Fail-open: emit call in `( set +e; … ) || true` subshell.
- [x] 1.4 Emit body classification/enum only.

## Phase 2 — cloud-init.yml post-bootstrap region

- [x] 2.1 Line 412: add `SOLEUR_SENTRY_DSN='${sentry_dsn}'` to the bootstrap invocation.
- [x] 2.2 Shared `soleur-boot-emit <stage> <level>` written once (Phase 0.2 shape); tags `{stage, host_id, region:cloud-init}`; all calls `|| true`.
- [x] 2.3 Entry breadcrumbs as separate runcmd items; bare tolerant commands use `cmd || soleur-boot-emit <stage> warning` (NO new `set -e`+`exit 1`). Stages: volume_mount(417-431), cloudflared(433-441), webhook(444-453), host_timers(455-477), app_image_pull(480, own stage), plugin_seed(492), inngest_bootstrap(523).
- [x] 2.4 **Readiness gates (load-bearing):** after cloudflared enable → `cloudflared_ready` (poll `systemctl is-active --quiet cloudflared`); after webhook enable → `webhook_bound` (poll `:9000` bind via `curl -sf localhost:9000` / `ss -ltn 'sport = :9000'`). Bounded timeout; on timeout `soleur-boot-emit <stage> fatal` + `exit 1`. These NEW blocks are legitimately `set -e`.
- [x] 2.5 Composite-trap merge on plugin_seed(496)/inngest(528): `trap 'rc=$?; cleanup; [ "$rc" = 0 ] || soleur-boot-emit <stage> fatal' EXIT` — never a second trap.
- [x] 2.6 Terminal block (555-600): sub-stage `doppler_download`(568) vs `docker_run`(580); `cloud_init_complete` breadcrumb after the egress probe (597). Document poweroff paths (563/599) rely on Better Stack absence, not the emit.

## Phase 3 — apply-web-platform-infra.yml

- [x] 3.1 **Fix the Sentry endpoint host to EU** (`de.sentry.io`, derive from DSN residency) at line 1212 — load-bearing; add a test asserting host↔DSN parity.
- [x] 3.2 Extend the QUERY (1207) to the new downstream fatal + `bootstrap_complete`/`webhook_bound` breadcrumb literals (byte-lockstep with the emit sites); most-recent sort.
- [x] 3.3 Surface the breadcrumb trail `if: always()` (not only failure()) so a green boot shows the probe fired.
- [x] 3.4 Verify `fresh-host Sentry pointer` literal lands in `gh run view --log`; else point discoverability at the summary artifact.

## Phase 4 — Tests (write first) + wire

- [x] 4.1 `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh`: AC2 (DSN pass), AC3 (DSN preference), AC4 (bootstrap_complete order), AC5 (enclosure shape, not per-line), AC6 (readiness gates + `:9000`), AC6b (no inversion + composite trap), AC8 (byte-equality lockstep), AC8b (EU endpoint parity).
- [x] 4.2 Wire into `.github/workflows/infra-validation.yml` (mirror line 160).
- [x] 4.3 Run all existing `apps/web-platform/infra/*.test.sh`. (No `tsc` — no TS touched.)

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

## Implementation Notes (for PR body)

- **(B) cosign ENFORCE — confirmed dead end, NO code change.** `IMAGE_VERIFY_MODE:-warn` (ci-deploy.sh:54); the only `enforce` setter in the repo is a test (`ci-deploy.test.sh:1243`); cosign verify runs only on the deploy-webhook path, never in the fresh-boot cloud-init sequence; trusted root is installed pre-sentinel. (AC1)
- **(H3) errexit leak CONFIRMED by code-read → scope-fix included (likely the actual boot fix).** cloud-init joins ALL runcmd items into ONE `/bin/sh` (the file's own line-349/559 comments state this). The extraction block's `set -e` (354) was never restored, so it leaked into the bare downstream `apt-get`/cloudflared region with the `on_err` trap already disarmed — a transient non-zero there aborts the whole runcmd SILENTLY (no trap, no emit): exactly "cloudflared never comes up, :9000 never binds". Fix = `set +e` after the extraction block, restoring the "runcmd is NOT under a top-level set -e" invariant the terminal fail-closed gate already assumes. The probe still lands (proves the fix on the next recreate); `Ref #6090`, not `Closes`. (AC1b)
- **Emitters BAKED, not inline (byte cap).** Rendered user_data delta measured at **+892 bytes** (est. total ~32.2 KB vs the 32,768 cap). An inline emit body would blow it, so `soleur-boot-emit` (the Sentry emitter) and `soleur-wait-ready` (the bounded readiness poll) are authored by `soleur-host-bootstrap.sh` via heredoc → 0 user_data; cloud-init carries only call-sites. No new Dockerfile/server.tf lockstep (only bootstrap.sh changed, already in `host_scripts_content_hash`). Hetzner enforces the cap at apply — an over-cap fails the recreate *apply* loudly (never a silent bad boot, never web-1). (AC7)
- **Readiness gates (AC6, load-bearing).** `soleur-wait-ready service cloudflared cloudflared_ready || exit 1` and `soleur-wait-ready port 9000 webhook_bound || exit 1` — bounded polls of the REAL invariant (unit active / :9000 bind); on timeout emit a named fatal + abort the boot. These convert the async-service death a command-level trap cannot see into a named Sentry event.
- **Dropped `post_seed` + `app_image_pull` breadcrumbs for the byte cap** — covered transitively by `bootstrap_complete`/`cloudflared_ready` and the `plugin_seed` composite trap respectively.
- **AC5 fail-open** consolidated into the single `_sentry_emit` boundary (+ the baked helpers' own `( set +e ) || true`) rather than per-call-site subshells — the safety invariant lives in one place.
- **Cross-file drift guard preserved:** `cron-egress-enforce-probe.test.sh`'s "Sentry TRANSPORT parity" gate requires `_sentry_emit`'s transport lines byte-identical (incl. 6/8-space indent) to the probe's copy — kept via the `if [ -n "$DSN" ]` form.
- **(Phase 3) EU data plane:** the recreate workflow auto-read now queries `de.sentry.io` (was US `sentry.io` → empty for the EU-resident `jikigai-eu` project), extends the QUERY to the new message literals (byte-lockstep, AC8), and runs `if: always()` so a green boot also shows the probe fired (AC8b).
