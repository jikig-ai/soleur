---
feature: feat-one-shot-6353-deploy-fanout-tag-malformed
plan: knowledge-base/project/plans/2026-07-11-fix-deploy-fanout-tag-resolution-health-plan.md
issue: 6353
lane: single-domain
brand_survival_threshold: aggregate pattern
---

# Tasks — deploy fan-out verify resolves web-1's re-swap tag from /health (#6353)

## Phase 0 — Preconditions
- [ ] 0.1 Read `apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh` — seed at `:170-197`, `latest` band-aid `:184-194`, `_trigger_fanout` `:142-166`, poll `.tag` reads `:219`/`:228`.
- [ ] 0.2 Read `apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh` (pure, `$1`-or-stdin, strict `^v[0-9]+\.[0-9]+\.[0-9]+$`) — reuse as-is, no change.
- [ ] 0.3 Confirm test seams + SEQ position contract in `apps/web-platform/infra/deploy-status-fanout-verify.test.sh` and the fixture format under `apps/web-platform/infra/fixtures/deploy-status/`.
- [ ] 0.4 Confirm `pin` step (`apply-web-platform-infra.yml:1021`) does not feed the verify, and `warm_standby` verify step has no Doppler/`APP_DOMAIN_BASE` context.

## Phase 1 — RED fixtures first (cq-write-failing-tests-before)
- [ ] 1.1 Add fixtures (synthesized only): a `/health` semver body + a `/health` non-semver (`dev`) body, reusing/adding a `latest`-tag deploy-status body.
- [ ] 1.2 T-A: deploy-status `.tag=latest` + `/health=1.2.3` → POST payload carries `v1.2.3`, never `latest`; verify exits 0. Assert `DEPLOY_POST_SINK` **contents** (grep the sink), not just line count.
- [ ] 1.3 T-B: `/health` unreachable → terminal `exit 1` + named `::error::`; zero `latest`/`.tag` POSTs.
- [ ] 1.4 T-C: `/health` non-semver → terminal `exit 1` + remediation `::error::`.
- [ ] 1.5 Non-vacuity: confirm 1.2–1.4 FAIL against the current unmodified script.

## Phase 2 — /health seam + resolve
- [ ] 2.1 Add a **distinct** `/health` test seam: `HEALTH_URL` override + a separate `HEALTH_STATUS_SOURCE_CMD` (or equivalent) — different URL + fixture from `DEPLOY_STATUS_SOURCE_CMD`. (Highest-risk detail — must be independently drivable.)
- [ ] 2.2 Add `_resolve_known_good_tag()`: bounded `/health` curl (mirror pin's 12× retry, `--max-time 15`, public — no CF-Access) → `jq -r '.version // ""'` → pipe through `resolve-web1-known-good-tag.sh`.
- [ ] 2.3 On `/health` failure / non-semver: loud `::error::` (mirror `resolve-web1-known-good-tag.sh:56` + `_recovery_msg`) + `exit 1`. NEVER fall back to the `.tag` seed.

## Phase 3 — Seed from /health + delete band-aid
- [ ] 3.1 Replace `DEPLOY_TAG=CURRENT_TAG` seed (`:197`) with `DEPLOY_TAG="$(_resolve_known_good_tag)"`. Keep the baseline read for `exit_code` (`-1` skip) + `PRE_START_TS`.
- [ ] 3.2 Delete the `latest`-widened baseline guard alternation + `:184-190` justification (the `.tag` tolerance is now dead).
- [ ] 3.3 Leave poll `.tag` reads (`:219`/`:228`) and the `_trigger_fanout` downgrade guard (`:147-155`) untouched.

## Phase 4 — ADR amendment + green suite
- [ ] 4.1 Add the dated #6353 third-reader line to ADR-079's `#6147` reader-inventory paragraph (~`:356`).
- [ ] 4.2 `bash apps/web-platform/infra/deploy-status-fanout-verify.test.sh` all green (T-A/B/C pass; AC4-latest / AC4-latest-resolve replaced; other AC4/staleness/degraded-retry cases stay green).
- [ ] 4.3 `bash apps/web-platform/infra/resolve-web1-known-good-tag.test.sh` green (unchanged).
- [ ] 4.4 `bash apps/web-platform/infra/web-hosts-fanout-parity.test.sh` + `bash apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` green.
- [ ] 4.5 Confirm the exact `.sh` test invocations against `.github/workflows/infra-validation.yml` (do not assume a JS runner).

## Acceptance verification (pre-merge — see plan)
- [ ] AV.1 `.tag` seed gone (`git grep 'DEPLOY_TAG=.*CURRENT_TAG'` → 0).
- [ ] AV.2 `latest` band-aid gone (`git grep -E '\^\(v\[0-9\].*\|latest\)\$'` → 0).
- [ ] AV.3 `/health` seam distinct from deploy-status seam (`HEALTH_URL` ≠ `DEPLOY_STATUS_URL`).
- [ ] AV.4 ADR-079 carries `#6353` third-reader line (`grep -c '#6353' ADR-079-*.md` ≥ 1).
- [ ] AV.5 PR body uses `Closes #6353`.

## Post-merge (operator)
- [ ] None. web-1 `.tag` live-state self-heals on the release triggered by this PR + the next `/health`-resolved fan-out. A web-2 recreate re-verification is the natural next dispatch (unblocks #6178).
