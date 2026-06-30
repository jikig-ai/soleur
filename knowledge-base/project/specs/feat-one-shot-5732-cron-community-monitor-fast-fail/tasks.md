---
issue: 5732
branch: feat-one-shot-5732-cron-community-monitor-fast-fail
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-30-fix-cron-community-monitor-fast-fail-plan.md
---

# Tasks — fix cron-community-monitor daily `error` fast-fail (#5732)

## Phase 0 — Evidence gate (BLOCKING — no code until verdict recorded)

- [ ] 0.1 Trigger a fresh post-top-up run (natural 08:00 UTC fire, or `cron/community-monitor.manual-trigger` if allowlisted in trigger-cron — verify first; no SSH fallback). Capture run_id/timestamp.
- [ ] 0.2 Pull `routine_runs` for `cron-community-monitor` 06-22→06-30 (Doppler `prd` `DATABASE_URL_POOLER`, transient node+pg verify script): status, error_summary, duration_ms, started_at, trigger_source.
- [ ] 0.3 Pull Sentry exception events for `feature:cron-community-monitor` (confirm/refute the no-exception-event finding; read any clone-stderr/spawn-tail title).
- [ ] 0.4 Pull Better Stack stdout tail of the freshest fire (`scripts/betterstack-query.sh` under `prd_terraform`): clone stderr, low-disk WARN, last heartbeat line.
- [ ] 0.5 Read `CRON_WORKSPACE_ROOT` free bytes + orphaned `soleur-cron-community-monitor-*` count from logged events (no SSH).
- [ ] 0.6 Record the Phase 0 verdict (executing path + branch A/B/C/D + citing datum) into the plan's Research Reconciliation. **Gate.**

## Phase 1 — Sentry monitor un-mute/re-enable (always)

- [ ] 1.1 `GET …/monitors/scheduled-community-monitor/` → `{status, isMuted}` (`SENTRY_IAC_AUTH_TOKEN`, `de.sentry.io`, org in path).
- [ ] 1.2 If disabled/muted → `PUT {"status":"active","isMuted":false}`. Dashboard fallback only on confirmed 403 (record `playwright-attempt:`).

## Phase 2 — Conditional fix (branch on Phase 0)

- [ ] 2.A (H-A ENOSPC) Automated orphan-workspace reclaim in `setupEphemeralWorkspace` (TTL sweep, never the live `spawnCwd`) + promote `warnIfCronWorkspaceLowOnDisk` to a loud pre-clone failure below a hard free-bytes floor.
- [ ] 2.B (H-B auth/egress) Correct `DEFAULT_CRON_TOKEN_PERMISSIONS` scope OR `cron-egress-allowlist.txt`; verify firewall/egress IP/DNS first. IaC, no host edit.
- [ ] 2.C (H-C credit, resolved) No code fix; recovery confirmation + Phase 1 un-mute is the close.

## Phase 3 — Observability hardening (unless Phase 0 proves already self-diagnosing)

- [ ] 3.1 Thread the redacted setup-failure reason into the handler's `{ok:false}` return so `run-log.ts` maps it to a non-generic `routine_runs.error_summary` (preserve ADR-033 I5 — extend handler return, not `SpawnResult`).
- [ ] 3.2 Confirm the `setup-ephemeral-workspace` Sentry event groups searchably.

## Phase 4 — Regression test (RED first)

- [ ] 4.1 `cron-community-monitor-heartbeat.test.ts`: setup-workspace throw → exactly one `?status=error` + `{ok:false}` carries the scrubbed reason (+ run-log mapping for AC4).
- [ ] 4.2 (H-A) `cron-claude-eval-substrate.test.ts`: orphan-reclaim sweep (only stale dirs) + hard low-disk floor (synthesized fixtures).
- [ ] 4.3 `tsc --noEmit` + `vitest run` green.

## Close-out

- [ ] 5.1 Soak follow-through probe `scripts/followthroughs/community-monitor-recovered-5732.sh` + tracker directive + sweeper `secrets=`.
- [ ] 5.2 PR body `Ref #5732` if post-merge close; post-merge `gh issue close` after AC8 recovery confirmed.
