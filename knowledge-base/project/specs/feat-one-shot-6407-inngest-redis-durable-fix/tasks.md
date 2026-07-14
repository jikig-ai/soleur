# Tasks: Inngest watchdog functions-query corroboration + restart lock_contention (#6407)

Plan: `knowledge-base/project/plans/2026-07-14-fix-inngest-watchdog-functions-query-corroboration-and-restart-lock-contention-plan.md`
Lane: cross-domain · Threshold: aggregate pattern · Closes #6407
(Deepened 2026-07-14: corroboration signal is loopback `/health` — NOT `systemctl is-active`; fetch-retry cut; +persistence escalation, +auto-close, +final-state re-read.)

## Phase 0 — Preconditions
- [ ] 0.1 Confirm liveness host runs inngest-server + answers loopback `/health` (runbook §Dedicated-host cutover + `/hooks/deploy-status` GET).
- [ ] 0.2 Re-read classifier + `.test.sh`, `inngest-inventory.sh:383-424`; confirm `verify_inngest_health` `/health` form (`ci-deploy.sh ~:1019`).
- [ ] 0.3 Confirm seam `INVENTORY_INNGEST_HEALTH_CODE` is new (mirror `INVENTORY_REDIS_ACTIVE:370`).
- [ ] 0.4 Confirm delivery: `apply-deploy-pipeline-fix.yml` paths + `infra-config-apply.sh` FILE_MAP.

## Phase 1 — Defect A: /health corroboration (host)
- [ ] 1.1 `inngest-inventory.sh` FATAL guard (`:398-408`, LIVENESS_ONLY only): probe loopback `/health` via `INVENTORY_INNGEST_HEALTH_CODE`/`curl 127.0.0.1:8288/health` BEFORE FATAL. 200 → `inngest-inventory: DEGRADED …` soft sentinel (exit 1). !=200 → keep FATAL (real down/wedged). Do NOT use is-active/ExecStart.
- [ ] 1.2 `inngest-inventory.test.sh`: `HEALTH_CODE=200`+failed-fetch → DEGRADED.
- [ ] 1.3 `inngest-inventory.test.sh`: `HEALTH_CODE=000` and `503`+failed-fetch → FATAL (real-down preserved).

## Phase 2 — Defect A: classifier + watchdog routing (union-widening, all MANDATORY)
- [ ] 2.1 `inngest-liveness-classify.sh`: DEGRADED → `functions_query_degraded` (match before FATAL); exclude from `is_restart_family`; document.
- [ ] 2.2 `inngest-liveness-classify.test.sh`: DEGRADED→mode; is_restart_family→no; keep FATAL→inngest_down regression.
- [ ] 2.3 `scheduled-inngest-health.yml` probe `case "$MODE"` (`:115-129`): add `functions_query_degraded)` arm.
- [ ] 2.4 MANDATORY — `ISSUE_CLASS case` (`:359-364`): add `functions_query_degraded)` arm BEFORE `*) → down`; own soft class `[ci/inngest-functions-degraded]` + accurate body (`/health=200; NO restart`).
- [ ] 2.5 MANDATORY — heartbeat `status:` (`:597`): add `functions_query_degraded` to the `ok` allowlist (else it pages).
- [ ] 2.6 Auto-close (`:481-515`): add close block for `[ci/inngest-functions-degraded]` title (mirror `:511-515`).
- [ ] 2.7 Down-branch `else` (`:472-474`): no-claim-on-empty per 2026-07-13 learning.
- [ ] 2.8 Persistence escalation: reuse `inngest-restart-age-gate.sh` against the new title; age ≥ ~45min → reclassify to inngest_down (restart + page).

## Phase 3 — Defect C: observability markers
- [ ] 3.1 `inngest-inventory.sh`: `SOLEUR_INNGEST_LIVENESS_VERDICT mode= health_code= functions= durability=` (logger -t, journald-only, scrubbed).
- [ ] 3.2 `ci-deploy.sh`: `SOLEUR_INNGEST_RESTART_LOCK_CONTENTION action= component= outcome=deferred_to_in_flight` at flock-contention (`:1263-1268`; no stamp change).

## Phase 4 — Defect B: restart poll non-terminal lock_contention + final state re-read (ADR-079 #5960)
- [ ] 4.1 `restart-inngest-server.yml` verify poll (`:143-153`): `reason=lock_contention` + component=inngest → `continue` (not `::error` exit 1); track "only lock_contention seen".
- [ ] 4.2 Budget expiry (`:158-159`): only-lock_contention → final STATE re-read (`/hooks/deploy-status` fresh inngest success OR `/hooks/inngest-liveness` healthy) → benign exit 0 + marker; unconfirmed → `::error` UNVERIFIED exit 1; other failure → exit 1.
- [ ] 4.3 Preserve ADR-100 restart purity (consumer-side only).

## Phase 5 — ADR + runbook + postmortem
- [ ] 5.1 Amend `ADR-030` #6374 log with #6407 (/health corroboration + soft mode + escalation); cross-ref ADR-079 #5960. No new ordinal. No C4 change.
- [ ] 5.2 Update `runbooks/inngest-server.md`: functions_query_degraded soft mode + escalation ceiling + lock_contention-benign (no-SSH).
- [ ] 5.3 Amend existing `post-mortems/inngest-watchdog-false-positive-unseen-6374-postmortem.md` with `## Residual vector — #6407` (fold in, not a new file).

## Phase 6 — Verify + ship
- [ ] 6.1 AC1–AC8 (classifier + inventory tests, union-widening sweep incl. ISSUE_CLASS arm + heartbeat ok + auto-close + escalation, no-claim else, markers, restart poll, shellcheck, actionlint).
- [ ] 6.2 Follow-through: `scripts/followthroughs/inngest-watchdog-functions-query-6407.sh` + tracker directive + sweeper secrets.
- [ ] 6.3 PR body `Closes #6407`.
