# Tasks — nightly source-vs-live heartbeat reconcile (#6549 item 2)

Plan: `knowledge-base/project/plans/2026-07-17-feat-heartbeat-live-reconcile-drift-workflow-plan.md`
Lane: cross-domain · Threshold: aggregate pattern

## Phase 0 — Preconditions
- [ ] 0.1 Verify Better Stack API contract vs docs (`GET /api/v2/heartbeats`, `Authorization: Bearer`, `data[].attributes.{name,paused}`, `pagination.next`); pin `<!-- verified: 2026-07-17 source: -->` in the script.
- [ ] 0.2 Confirm bun runs the script importing the pure manifest with no external deps; plan the `bun install --frozen-lockfile` step + `.bun-version` pin.
- [ ] 0.3 Confirm `secrets.DOPPLER_TOKEN` is `prd_terraform`-scoped (reuse; no new secret).

## Phase 1 — Pure reconcile lib + RED tests (TDD)
- [ ] 1.1 Write `plugins/soleur/test/heartbeat-live-reconcile.test.ts` FIRST (RED): condition (a), condition (b), count-gate carve-out, OK path, synthetic live-API fixture.
- [ ] 1.2 Implement `plugins/soleur/lib/heartbeat-live-reconcile.ts` — `parseHeartbeatBlocks` (`{resourceName, liveName, sourcePaused, countGated}`, comment-stripped) + `reconcileHeartbeats(manifest, discovered, live) -> Violation[]`. GREEN.

## Phase 2 — CLI script
- [ ] 2.1 `plugins/soleur/scripts/reconcile-live-heartbeats.ts`: env-token read, paginated `fetch`, 3-retry backoff + 10s timeout, 401/403→exit1, transient-exhausted→exit0 UNREACHABLE, mismatch→exit2, else exit0. Structured `SOLEUR_*` markers. Never echo the token.

## Phase 3 — Workflow job
- [ ] 3.1 Add job `heartbeat-live-reconcile` to `scheduled-terraform-drift.yml`: checkout → setup-bun (SHA-pinned, `.bun-version`) → bun install → Doppler CLI → read+mask `BETTERSTACK_API_TOKEN` (`--plain`, `prd_terraform`) → run script (`set +e`, capture `rc=$?` to file) → branch on rc.
- [ ] 3.2 Reporting: ensure `heartbeat-reconcile-mismatch` label, create/update deduped issue (sanitized output), `notify-ops-email` (creation-only), final `sentry-heartbeat` check-in to `scheduled-heartbeat-reconcile` (`if: always()`, `continue-on-error: true`). SHA-pin refs; strip CR/LF before annotations.

## Phase 4 — Sentry cron monitor (IaC)
- [ ] 4.1 Add `sentry_cron_monitor.scheduled_heartbeat_reconcile` to `apps/web-platform/infra/sentry/cron-monitors.tf` (`crontab "0 6,18 * * *"`, `checkin_margin_minutes 60`, `failure_issue_threshold 1`).
- [ ] 4.2 Update `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` (+ grep for any monitor census in `apps/web-platform/test scripts/`) to keep slug↔check-in parity GREEN.

## Phase 5 — ADR + C4
- [ ] 5.1 Amend ADR-117 (`executable-heartbeat-arming`) via `/soleur:architecture` — Decision + Alternatives Considered. (Fallback new ADR: ADR-122.)
- [ ] 5.2 Read all three `.c4` files; add-or-cite the CI→betterstack heartbeat-read edge (+ `views.c4` include if new); run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 6 — Verify + ship prep
- [ ] 6.1 `bun test` new + parity tests GREEN; typecheck new TS.
- [ ] 6.2 Local read-only dry-run vs live Better Stack; capture `SOLEUR_*` output (git_data absent) for PR body.
- [ ] 6.3 #6549 item-2 box checked + PR ref, OPEN; #6548 commented, OPEN.
- [ ] 6.4 File D1 read-only-token follow-up issue; PR body `Ref #6549`/`Ref #6548` (not Closes), `## Changelog`, `semver:minor`.
