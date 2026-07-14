# Tasks: Inngest watchdog functions-query corroboration + restart lock_contention (#6407)

Plan: `knowledge-base/project/plans/2026-07-14-fix-inngest-watchdog-functions-query-corroboration-and-restart-lock-contention-plan.md`
Lane: cross-domain · Threshold: aggregate pattern · Closes #6407

## Phase 0 — Preconditions
- [ ] 0.1 Verify cutover topology: liveness host runs `inngest-server.service` (runbook §Dedicated-host cutover + read-only `/hooks/deploy-status` `services.inngest_server`).
- [ ] 0.2 Re-read `scripts/inngest-liveness-classify.sh` + `.test.sh` and `inngest-inventory.sh:383-424`.
- [ ] 0.3 Confirm `INVENTORY_INNGEST_ACTIVE` seam is new (grep → zero); mirror `INVENTORY_REDIS_ACTIVE` (`inngest-inventory.sh:370`).
- [ ] 0.4 Confirm host-script delivery via `apply-deploy-pipeline-fix.yml` paths + `infra-config-apply.sh` FILE_MAP.

## Phase 1 — Defect A: co-located corroboration (host)
- [ ] 1.1 `inngest-inventory.sh` `fetch_functions()`: bounded retry (`FUNCTIONS_FETCH_RETRIES` default 2, short backoff, inside `PREFLIGHT_DEADLINE_S`).
- [ ] 1.2 `inngest-inventory.sh` `run_inventory()` FATAL guard (LIVENESS_ONLY only): corroborate `INVENTORY_INNGEST_ACTIVE`/`systemctl is-active inngest-server.service` before FATAL. active → `inngest-inventory: DEGRADED …` soft sentinel (exit 1, non-restart). inactive → keep FATAL (real down).
- [ ] 1.3 `inngest-inventory.test.sh`: active+failed-fetch → DEGRADED; inactive+failed-fetch → FATAL; retry seam test.

## Phase 2 — Defect A: classifier + watchdog routing
- [ ] 2.1 `scripts/inngest-liveness-classify.sh`: DEGRADED sentinel → new mode `functions_query_degraded` (match before FATAL); exclude from `is_restart_family`; document mode.
- [ ] 2.2 `scripts/inngest-liveness-classify.test.sh`: DEGRADED→functions_query_degraded; is_restart_family→no; keep FATAL→inngest_down regression.
- [ ] 2.3 `scheduled-inngest-health.yml`: add `functions_query_degraded)` case arm; ensure excluded from dispatch + age-gate `if:`; route to own soft issue class with evidence-based (non-claim) comment; heartbeat `ok` not `error`.

## Phase 3 — Defect C: observability markers
- [ ] 3.1 `inngest-inventory.sh`: `SOLEUR_INNGEST_LIVENESS_VERDICT mode= inngest_active= functions= durability= fetch_retries=` via `logger -t` (journald-only, scrubbed).
- [ ] 3.2 `ci-deploy.sh`: `SOLEUR_INNGEST_RESTART_LOCK_CONTENTION action= component= outcome=deferred_to_in_flight` at flock-contention (observability only; no stamp change).

## Phase 4 — Defect B: restart poll non-terminal lock_contention (ADR-079 #5960)
- [ ] 4.1 `restart-inngest-server.yml` verify poll: `component=inngest` + `reason=lock_contention` → `continue` (keep polling), NOT `::error::` exit 1.
- [ ] 4.2 Budget-expiry: only `lock_contention` seen → benign `::notice::` exit 0 + marker; other non-zero → exit 1. Track whether a non-lock_contention failure was seen.
- [ ] 4.3 Preserve ADR-100 restart purity (consumer-side change only; ci-deploy restart handler untouched).

## Phase 5 — ADR + runbook + postmortem
- [ ] 5.1 Amend `ADR-030` #6374 log with #6407 corroboration decision + ADR-079 #5960 cross-ref. No new ordinal. No C4 change.
- [ ] 5.2 Update `runbooks/inngest-server.md`: functions_query_degraded soft mode + lock_contention-benign (no-SSH).
- [ ] 5.3 Write `post-mortems/inngest-watchdog-functions-query-false-positive-6407-postmortem.md`.

## Phase 6 — Verify + ship
- [ ] 6.1 AC1–AC8 (classifier + inventory tests, greps, shellcheck, actionlint).
- [ ] 6.2 Follow-through enrollment: `scripts/followthroughs/inngest-watchdog-functions-query-6407.sh` + tracker directive + sweeper secrets.
- [ ] 6.3 PR body `Closes #6407`.
