---
feature: feat-one-shot-6353-deploy-fanout-tag-malformed
plan: knowledge-base/project/plans/2026-07-11-fix-deploy-fanout-tag-resolution-health-plan.md
issue: 6353
lane: single-domain
brand_survival_threshold: aggregate pattern
---

# Tasks — deploy fan-out verify resolves web-1's re-swap tag from /health (#6353)

## Phase 0 — Preconditions
- [x] 0.1 Read `apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh` — seed at `:170-197`, `latest` band-aid `:184-194`, `_trigger_fanout` `:142-166`, poll `.tag` reads `:219`/`:228`.
- [x] 0.2 Read `apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh` (pure, `$1`-or-stdin, strict `^v[0-9]+\.[0-9]+\.[0-9]+$`) — reuse as-is, no change.
- [x] 0.3 Confirm test seams + SEQ position contract in `apps/web-platform/infra/deploy-status-fanout-verify.test.sh` and the fixture format under `apps/web-platform/infra/fixtures/deploy-status/`.
- [x] 0.4 Confirm `pin` step (`apply-web-platform-infra.yml:1021`) does not feed the verify, and `warm_standby` verify step has no Doppler/`APP_DOMAIN_BASE` context.

## Phase 1 — RED fixtures + harness capture first (cq-write-failing-tests-before)
- [x] 1.0 **[spec-flow P0] Capture the POST-sink contents into a global** (`POSTBODIES=$(cat "$sink")`) in `run_verify` BEFORE its `rm -rf "$tmp"` (test `:111-113`), mirroring the existing `GHOUT` capture. Assertions read `$POSTBODIES`, not the deleted file. Avoid the vacuous-pass trap: use a POSITIVE anchor (`grep -q 'v1.2.3' <<<"$POSTBODIES"`), never `! grep -q latest <missing-file>`.
- [x] 1.1 `/health` fixtures are stdout strings via `HEALTH_SOURCE_CMD` (no JSON body for the light seam); reuse `latest-tag.json` for T-A's deploy-status side.
- [x] 1.2 T-A: deploy-status `.tag=latest` + `/health=1.2.3` → `$POSTBODIES` contains `v1.2.3` AND not `latest`; verify exits 0.
- [x] 1.3 T-B: `/health` unreachable (`HEALTH_SOURCE_CMD='echo ""'`) → terminal `exit 1` + named `::error::`; `$POSTBODIES` has no `latest`/`.tag`. Run under `OP_CONTEXT=recreate` AND `=warm-standby`.
- [x] 1.4 T-C: `/health=dev` → terminal `exit 1` + remediation `::error::` (minimal string-shape echo; resolver suite covers the rest).
- [x] 1.5 T-D (replaces AC4-latest-resolve): `/health=v1.2.3` baseline, degraded → after window, retrigger re-resolves `/health` now `1.3.0` → second POST carries `v1.3.0` (never `.tag`).
- [x] 1.6 Non-vacuity: confirm 1.2–1.5 FAIL against the current unmodified script.

## Phase 2 — /health seam + resolve
- [x] 2.1 Add a **distinct** LIGHT stdout-echo seam: `HEALTH_URL` + `HEALTH_SOURCE_CMD` — separate from `DEPLOY_STATUS_URL`/`DEPLOY_STATUS_SOURCE_CMD` (independently drivable). NOT a `_get_status` clone.
- [x] 2.2 Add `_resolve_known_good_tag()`: `version=$([[ -n "$HEALTH_SOURCE_CMD" ]] && bash -c "$HEALTH_SOURCE_CMD" || curl -sf --max-time 15 --retry 3 --retry-connrefused "$HEALTH_URL" | jq -r '.version // ""')` → `resolve-web1-known-good-tag.sh "$version"`. `curl --retry 3`, NOT a 12× loop. `|| true` on the curl (set -e leak).
- [x] 2.3 **stdout = tag only; ALL diagnostics `>&2`** (else stdout pollutes `DEPLOY_TAG`). On failure/non-semver: loud `::error::` (mirror `resolve-web1-known-good-tag.sh:56` + `_recovery_msg`) + `exit 1`. NEVER fall back to `.tag`.
- [x] 2.4 **[P1-B]** Carry the pin step's HOST-TARGETING INVARIANT comment (`apply-web-platform-infra.yml:1058-1066`) into `_resolve_known_good_tag` (`app/health` must hit web-1; revisit on #5274/#6178).

## Phase 3 — Seed AND retrigger from /health + delete band-aid
- [x] 3.1 Replace `DEPLOY_TAG=CURRENT_TAG` seed (`:197`) with `DEPLOY_TAG="$(_resolve_known_good_tag)"`. Keep the baseline read only for `exit_code` (`-1` skip) + `PRE_START_TS`.
- [x] 3.2 Delete the `latest`-widened baseline guard (`:191-194`) + `:184-190` justification; remove dead `CURRENT_TAG` (`:170/:180/:196`).
- [x] 3.3 **[P1-A load-bearing] Route the `_trigger_fanout` retrigger (`:143-156`) through `/health` too:** replace the `.tag` re-read + looser `:152` guard + `DEPLOY_TAG=$fresh_tag` with `DEPLOY_TAG="$(_resolve_known_good_tag)"`. Trim the orphaned `:148` comment.
- [x] 3.4 Leave the poll acceptance-match `.tag` reads (`:219`/`:228`) as acceptance proof (P2-A residual documented — do not claim full immunity).

## Phase 4 — Harness default + test re-homing + ADR + green suite
- [x] 4.0 **[spec-flow P1] Inject a DEFAULT `/health` seam into `run_verify`** for EVERY existing case (resolving to each family's fixture version — `1.0.0` for settled-v1/ok-v1) so no real `app.soleur.ai/health` curl fires in CI.
- [x] 4.1 Re-home AC4-tag / AC4-tag-empty to `/health`-garbage/-empty (they pin the DELETED `.tag` guard — do NOT leave them asserting it). Replace AC4-latest + AC4-latest-resolve (T-A + T-D). Delete orphaned `fixtures/deploy-status/ok-latest-s300.json`.
- [x] 4.2 Add the dated #6353 third-reader line to ADR-079's `#6147` reader-inventory paragraph (~`:356`) — note BOTH seed + retrigger resolve from `/health`; record the host-targeting invariant.
- [x] 4.3 `bash apps/web-platform/infra/deploy-status-fanout-verify.test.sh` all green (T-A/B/C/D pass; re-homed + replaced cases; others green WITH the default `/health` seam).
- [x] 4.4 `bash apps/web-platform/infra/resolve-web1-known-good-tag.test.sh` green (unchanged).
- [x] 4.5 `bash apps/web-platform/infra/web-hosts-fanout-parity.test.sh` + `bash apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` green.
- [x] 4.6 Confirm the exact `.sh` test invocations against `.github/workflows/infra-validation.yml` (do not assume a JS runner).

## Acceptance verification (pre-merge — see plan)
- [x] AV.1 BOTH `.tag` tag-sources gone (`git grep -E 'DEPLOY_TAG=.*CURRENT_TAG|DEPLOY_TAG="\$fresh_tag"'` → 0).
- [x] AV.2 `latest` band-aid + dead `CURRENT_TAG` gone (`git grep -E '\^\(v\[0-9\].*\|latest\)\$|CURRENT_TAG'` → 0).
- [x] AV.3 `/health` seam distinct from deploy-status seam (`HEALTH_URL`/`HEALTH_SOURCE_CMD` ≠ `DEPLOY_STATUS_*`); host-targeting-invariant comment present.
- [x] AV.4 Sink contents captured before `rm`; T-A/T-B assert with a positive anchor (no vacuous `! grep <missing-file>`).
- [x] AV.5 Default `/health` seam injected in `run_verify`; AC4-tag/-empty re-homed; `ok-latest-s300.json` deleted.
- [x] AV.6 ADR-079 carries `#6353` third-reader line (`grep -c '#6353' ADR-079-*.md` ≥ 1).
- [ ] AV.7 PR body uses `Closes #6353` (ship-time).

## Post-merge (operator)
- [x] None. web-1 `.tag` live-state self-heals on the release triggered by this PR + the next `/health`-resolved fan-out. A web-2 recreate re-verification is the natural next dispatch (unblocks #6178).
