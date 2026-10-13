# Tasks — Durable zot restart-loop recurrence alarm (#6291)

Plan: `knowledge-base/project/plans/2026-07-10-feat-zot-restart-loop-recurrence-alarm-plan.md`
Lane: cross-domain (no spec.md — fail-closed default). Brand-survival threshold: aggregate pattern.

## Phase 0 — Preconditions (verify, no code)
- [ ] 0.1 Confirm `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` exist as GH Actions secrets (`gh secret list`).
- [ ] 0.2 Confirm live telemetry: `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 3h --grep SOLEUR_ZOT_DISK --limit 20` returns rows with `boot_id=`/`zot_restarts=`/`exit_code=`/`oom_kills_5m=`.
- [ ] 0.3 Confirm `.github/actions/sentry-heartbeat` exists + `apply-sentry-infra.yml` auto-applies the sentry subroot on push; check whether that apply is `-target=`-scoped (drives Files-to-Edit 2).

## Phase 1 — Shared helper + checker script + tests (RED → GREEN)
- [ ] 1.0 Create `scripts/lib/zot-telemetry-parse.sh` (sort → strip `zot_last_err` tail → newest-boot scope → `-1` sentinel filter); refactor `scripts/followthroughs/zot-restart-plateau-6288.sh` to `source` it (existing soak test = safety net).
- [ ] 1.1 Write `scripts/zot-restart-loop-alarm.test.sh` first (RED) — synthesized `ZOT_BQ_OVERRIDE` fixtures; one case per Test Scenario 1-12 in the plan (incl. producer-silent(3) + fresh-host→transient(2)).
- [ ] 1.2 Create `scripts/zot-restart-loop-alarm.sh` sourcing the helper: named consts `WINDOW=3h`,`CLIMB_N=3`. Exit contract 0=GREEN / 1=FIRE (137 | ≥CLIMB_N consecutive climb | oom_kills_5m>0) / 2=TRANSIENT probe-fault (query fail OR control-marker also empty) / 3=PRODUCER-SILENT (control present + 24h-had-rows + 3h-empty). Never FIRE on all-`-1` sentinel. Document the non-OOM/all-sentinel→TRANSIENT coverage seam in the header.
- [ ] 1.3 `bash scripts/zot-restart-loop-alarm.test.sh` GREEN; confirm the refactored soak test still GREEN.

## Phase 2 — Standing alarm workflow
- [ ] 2.1 Create `.github/workflows/scheduled-zot-restart-loop.yml`: `gate-override` header + justification anchored on ADR-033 I7 + scope-note; `on.schedule '*/30 * * * *'` + `workflow_dispatch`; concurrency group; `permissions: contents:read, issues:write`; `BETTERSTACK_QUERY_*` env.
- [ ] 2.2 Checker step captures verdict+exit to `$GITHUB_OUTPUT` (does NOT `exit 1` the step); `strip_log_injection` all telemetry before echo.
- [ ] 2.3 FIRE(1): open-or-comment `[ci/zot-restart-loop]` (own-title), labels `action-required,observability,domain/engineering`, body = decoded cause + run URL + reproduce command.
- [ ] 2.4 PRODUCER-SILENT(3): open-or-comment `[ci/zot-telemetry-silent]` (own-title, action-required).
- [ ] 2.5 GREEN(0): own-title auto-close BOTH issue classes (no union search — #5562).
- [ ] 2.6 TRANSIENT(2): no issue; loud Actions log; errored Sentry check-in only.
- [ ] 2.7 Final `./.github/actions/sentry-heartbeat` with `if: always()` (`MONITOR_SLUG=scheduled-zot-restart-loop`, errored on TRANSIENT).
- [ ] 2.8 `actionlint` clean; embedded `run:` snippets `bash -n` on extraction.

## Phase 3 — Self-liveness monitor + ADR/C4/docs
- [ ] 3.1 Add `sentry_cron_monitor.zot_restart_loop_alarm` to `apps/web-platform/infra/sentry/cron-monitors.tf` (slug `scheduled-zot-restart-loop`, `*/30 * * * *`, UTC, **pinned `checkin_margin_minutes=30`** for GHA jitter — cite the 2026-06-15 agent-native-audit incident); add `-target=` entry if the sentry auto-apply is target-scoped (verify via `git grep -ln 'sentry_cron_monitor\|-target=' apps/web-platform/infra/sentry/ .github/workflows/apply-sentry-infra.yml tests/ scripts/`). `terraform validate` clean.
- [ ] 3.2 Amend `ADR-096` §Consequences + §Alternatives with the recurrence-alarm mechanism decision (GH-cron poller; BS-v2-API considered-rejected with endpoints).
- [ ] 3.3 C4: add `github -> betterstack` Logs-read edge to `model.c4` + enrich `betterstack` description; add `views.c4` include if it does not render; run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] 3.4 `betterstack-log-query.md` runbook: standing-alarm note.

## Phase 4 — Verify + ship
- [ ] 4.1 Live dry-run: `doppler run -p soleur -c prd_terraform -- bash scripts/zot-restart-loop-alarm.sh` → paste verdict block into PR.
- [ ] 4.2 All Pre-merge ACs green (plan §Acceptance Criteria).
- [ ] 4.3 PR body uses `Closes #6291`; no operator-checklist (post-merge steps are fully automated: apply-sentry-infra + workflow schedule).
