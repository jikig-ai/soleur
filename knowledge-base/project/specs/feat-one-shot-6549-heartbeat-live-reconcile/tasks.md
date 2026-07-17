# Tasks — nightly source-vs-live heartbeat reconcile (#6549 item 2)

Plan: `knowledge-base/project/plans/2026-07-17-feat-heartbeat-live-reconcile-drift-workflow-plan.md`
Lane: cross-domain · Threshold: aggregate pattern

## Phase 0 — Preconditions
- [x] 0.1 Verify Better Stack API contract vs docs (`GET /api/v2/heartbeats`, `Authorization: Bearer`, `data[].attributes.{name,paused}`, `pagination.next`); pin `<!-- verified: 2026-07-17 source: -->` in the script.
- [x] 0.2 Confirm bun runs the script importing the pure manifest with no external deps; plan the `bun install --frozen-lockfile` step + `.bun-version` pin.
- [x] 0.3 Confirm `secrets.DOPPLER_TOKEN` is `prd_terraform`-scoped (reuse; no new secret).

## Phase 1 — Pure reconcile lib + RED tests (TDD)
- [x] 1.1 Write `plugins/soleur/test/heartbeat-live-reconcile.test.ts` FIRST (RED): condition (a), condition (b), count-gate carve-out, OK path, synthetic live-API fixture.
- [x] 1.2 Implement `plugins/soleur/lib/heartbeat-live-reconcile.ts` — `parseHeartbeatBlocks` (`{resourceName, liveName, sourcePaused, countGated}`, comment-stripped) + `reconcileHeartbeats(manifest, discovered, live) -> Violation[]`. GREEN.

## Phase 2 — CLI script
- [x] 2.1 `plugins/soleur/scripts/reconcile-live-heartbeats.ts`: env-token read, paginated `fetch`, 3-retry backoff + 10s timeout, 401/403→exit1, transient-exhausted→exit0 UNREACHABLE, mismatch→exit2, else exit0. Structured `SOLEUR_*` markers. Never echo the token.

## Phase 3 — Workflow job
- [x] 3.1 Add job `heartbeat-live-reconcile` to `scheduled-terraform-drift.yml`: checkout → setup-bun (SHA-pinned, `.bun-version`) → bun install → Doppler CLI → read+mask `BETTERSTACK_API_TOKEN` (`--plain`, `prd_terraform`) → run script (`set +e`, capture `rc=$?` to file) → branch on rc.
- [x] 3.2 Reporting: ensure `heartbeat-reconcile-mismatch` label, create/update deduped issue (sanitized output), `notify-ops-email` (creation-only), final `sentry-heartbeat` check-in to `scheduled-heartbeat-reconcile` (`if: always()`, `continue-on-error: true`). SHA-pin refs; strip CR/LF before annotations.

## Phase 4 — Sentry cron monitor (IaC)
- [x] 4.1 Add `sentry_cron_monitor.scheduled_heartbeat_reconcile` to `apps/web-platform/infra/sentry/cron-monitors.tf` — FULL attribute set (`organization`, `project = data.sentry_project.web_platform.slug`, `name = "scheduled-heartbeat-reconcile"`, `schedule = {crontab "0 6,18 * * *"}`, `checkin_margin_minutes 60`, `max_runtime_minutes 10`, `failure_issue_threshold 1`, `recovery_threshold 1`, `timezone "UTC"`). Provider `jianyuan/sentry 0.15.0-beta2`.
- [x] 4.2 VERIFY `sentry-monitor-iac-parity.test.ts` stays GREEN unmodified (one-way code→IaC; GHA-fired monitor with no Inngest slug is tolerated). Grep `apps/web-platform/test scripts/` only for a hardcoded monitor-count census / sentry scope-guard; edit only if one exists.

## Phase 5 — ADR + C4
- [x] 5.1 Amend ADR-117 (`executable-heartbeat-arming`) via `/soleur:architecture` — Decision + Alternatives Considered. (Fallback new ADR: ADR-122.)
- [x] 5.2 Read all three `.c4` files; add-or-cite the CI→betterstack heartbeat-read edge (+ `views.c4` include if new); run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 6 — Verify + ship prep
- [x] 6.1 `bun test` new + parity tests GREEN; typecheck new TS.
- [x] 6.2 Local read-only dry-run vs live Better Stack; capture `SOLEUR_*` output (git_data absent) for PR body.
- [ ] 6.3 #6549 item-2 box checked + PR ref, OPEN; #6548 commented, OPEN.
- [x] 6.4 File D1 read-only-token follow-up issue; PR body `Ref #6549`/`Ref #6548` (not Closes), `## Changelog`, `semver:minor`.
