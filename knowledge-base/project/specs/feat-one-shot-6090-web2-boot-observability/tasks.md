---
feature: feat-one-shot-6090-web2-boot-observability
plan: knowledge-base/project/plans/2026-07-06-fix-web2-fresh-boot-observability-plan.md
tracker: "#6090"
lane: single-domain
brand_survival_threshold: none
---

# Tasks — web-2 fresh-boot observability (#6090)

> This PR is a structured off-host observability **probe**, not the boot fix. It makes the last-reached fresh-boot stage visible in Sentry so a single post-merge recreate names the failing stage. Uses `Ref #6090` (not `Closes`).

## Phase 0 — Preconditions (no host writes)

- [ ] 0.1 (B) Confirm cosign ENFORCE is NOT the cause (code-read only): #6023 unmerged, `IMAGE_VERIFY_MODE:-warn`, no `enforce` setter, cosign absent from cloud-init, trusted root installed pre-sentinel (`soleur-host-bootstrap.sh:81`). Write conclusion into PR body. No code change.
- [ ] 0.2 user_data byte-budget gate: render `templatefile("cloud-init.yml", …)` + `wc -c` with/without the added trap text; decide Option A (inline, if `< 32,768`) vs Option B (baked helper). Pin before/after byte counts in PR body.
- [ ] 0.3 Confirm `${sentry_dsn}` already wired into the cloud-init templatefile (`server.tf:138`).

## Phase 1 — soleur-host-bootstrap.sh (baked)

- [ ] 1.1 Factor a single `_sentry_emit <level> <json-tags>` helper; resolve DSN preferring `${SOLEUR_SENTRY_DSN:-<doppler fetch>}`. Migrate `emit_fail` (34-52) + `ghcr_login_warn` (168-180) to it.
- [ ] 1.2 Add `_breadcrumb()` emitting `{stage, host_id, region:"bootstrap"}` at each stage (`install/hooks/assert/reload/journald/ghcr_login`) + a `bootstrap_complete` breadcrumb immediately before `/run/soleur-hostscripts.ok` (line 199).
- [ ] 1.3 Fail-open: every emit/breadcrumb call site wrapped `( set +e; … ) || true`. `emit_fail` keeps `trap - EXIT` first.
- [ ] 1.4 Keep emit bodies classification/enum only (no raw stderr/creds).

## Phase 2 — cloud-init.yml downstream region

- [ ] 2.1 Line 412: add `SOLEUR_SENTRY_DSN='${sentry_dsn}'` to the bootstrap invocation env.
- [ ] 2.2 Instrument mount(417)→cloudflared(433-441)→webhook(444-453)→plugin-seed(492)→inngest(523)→app-run(555) with baked-`${sentry_dsn}` on_err trap + per-`STAGE` breadcrumbs (Option A inline OR Option B baked helper per 0.2). Region tag `cloud-init`.
- [ ] 2.3 Preserve every existing `|| true`/`2>/dev/null || true` tolerance when consolidating bare `- command` lines into `set -e` blocks (behavioral parity).
- [ ] 2.4 (Option B only) early `printf '%s' '${sentry_dsn}' > /run/soleur-boot-dsn`; add `soleur-boot-emit` to the baked host-scripts set + `local.host_scripts_content_hash` + Dockerfile COPY (lockstep).

## Phase 3 — apply-web-platform-infra.yml

- [ ] 3.1 Extend the failure Sentry QUERY (1207) to match the new downstream fatal + last breadcrumb (lockstep with emit `message` strings); show most-recent stage.
- [ ] 3.2 Update summary prose (1198-1201) to say it surfaces the named boot stage.

## Phase 4 — Tests (write first)

- [ ] 4.1 Create `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` asserting: AC2 (DSN pass), AC3 (DSN preference at both sites), AC4 (breadcrumb ordering), AC5 (fail-open guards), AC6 (downstream trap + parity), AC8 (workflow query).
- [ ] 4.2 Wire the new test into `.github/workflows/infra-validation.yml` (mirror line 160).
- [ ] 4.3 Run all existing `apps/web-platform/infra/*.test.sh`; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (unaffected).

## Phase 5 — Ship (pre-merge)

- [ ] 5.1 PR body: Pre-merge/Post-merge AC split; `Ref #6090`; cosign-B conclusion; user_data byte counts; Option A/B choice.
- [ ] 5.2 Review + merge (do NOT `Closes #6090`).

## Post-merge (operator + verification — NOT in the code PR)

- [ ] P1 [automatable] Confirm `web-platform-release.yml` rebuilt `${image_name}` with the new baked script before any recreate (AC11).
- [ ] P2 [automatable] Quiet-window go/no-go: 0 in-progress `web-platform-release` + web-1 deploy-status `exit_code=0` + `app.soleur.ai/health`=200 (AC12).
- [ ] P3 [operator-ack] `gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate -f reason='#6090 …'` — menu-ack gated; NEVER web-1 (AC13).
- [ ] P4 [automated + fallback] Read the named stage from the recreate run summary (Phase 3) or the `de.sentry.io` curl (AC14).
- [ ] P5 [verification] Sentry event names the stage/region; `app.soleur.ai/health`=200 unchanged (AC15).
- [ ] P6 [follow-up] File the stage-fix issue; keep #6090 open until web-2 binds `:9000` + fan-out reports `ok` (AC16).
