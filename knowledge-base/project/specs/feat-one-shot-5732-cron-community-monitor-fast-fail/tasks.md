---
issue: 5732
branch: feat-one-shot-5732-cron-community-monitor-fast-fail
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-30-fix-cron-community-monitor-fast-fail-plan.md
---

# Tasks — fix cron-community-monitor daily `error` fast-fail (#5732)

## Phase 0 — Evidence gate (BLOCKING — no code until verdict recorded)

Decision tree: 0.2 `duration_ms` forks credit-ran (H-C) vs pre-eval; 0.3/0.4 clone-stderr + 0.7 GC health fork H-B (codeload egress) vs H-A (disk).

- [ ] 0.1 Trigger a fresh post-top-up run (natural 08:00 UTC fire, or `cron/community-monitor.manual-trigger` if allowlisted in trigger-cron — verify first; no SSH fallback). Capture run_id/timestamp.
- [ ] 0.2 Pull `routine_runs` for `cron-community-monitor` 06-22→06-30 (Doppler `prd` `DATABASE_URL_POOLER`, transient node+pg verify script): status, error_summary, duration_ms, started_at, trigger_source. **duration_ms is the primary fork.**
- [ ] 0.3 Pull Sentry exception events **by `op:` TAG** (`op:setup-ephemeral-workspace`, `handler-body-threw`, `scheduled-output-missing`, `ensure-audit-issue-failed`) — NOT free text (title = clone stderr). Read the title: `Connection refused`/`resolve host` ⇒ H-B (codeload); `No space left on device` ⇒ H-A. Also pull `feature:cron-sentry-heartbeat op:fetch`.
- [ ] 0.4 Pull Better Stack stdout tail of the freshest fire (`scripts/betterstack-query.sh` under `prd_terraform`): clone stderr, low-disk WARN, last heartbeat line.
- [ ] 0.5 Read `CRON_WORKSPACE_ROOT` free bytes + orphan `soleur-*` count from logged events (no SSH). Chicken-and-egg: absence of disk logs ≠ refutation of H-A.
- [ ] 0.7 Pull `cron-workspace-gc` health 06-13→22 (`scheduled-workspace-gc` checkins + `routine_runs` + `workspace-gc-low-after-sweep` events). GC healthy ⇒ H-A refuted; GC down ⇒ GC outage is the root cause.
- [ ] 0.6 Record the Phase 0 verdict (executing path + H-A/H-B/H-C + whether the setup catch is the executing path + citing datum). **Gate.**

## Phase 1 — Sentry monitor un-mute/re-enable (always)

- [ ] 1.1 `GET …/monitors/scheduled-community-monitor/` → `{status, isMuted}` (`SENTRY_IAC_AUTH_TOKEN`, `de.sentry.io`, org in path).
- [ ] 1.2 If disabled/muted → `PUT {"status":"active","isMuted":false}`. Dashboard fallback only on confirmed 403 (record `playwright-attempt:`).

## Phase 2 — Conditional fix (branch on Phase 0)

- [ ] 2.B (H-B codeload egress — leading) Add `codeload.github.com` to `cron-egress-allowlist.txt` + `cron-egress-resolve.sh` CIDR set; amend ADR-052 (two→three-host). Verify firewall/egress-IP/DNS first; IaC, no host edit. (403/auth stderr instead ⇒ fix `DEFAULT_CRON_TOKEN_PERMISSIONS`.)
- [ ] 2.A (H-A ENOSPC) Fix/tune the EXISTING `cron-workspace-gc.ts` (Phase 0.7 names the GC outage as root cause). If a synchronous pre-clone guard is required, reuse `isSweepable` (shared helper, never fork policy) + a separate `assertCronWorkspaceFloor` fn. Do NOT add a sweep to `setupEphemeralWorkspace`; do NOT mutate `warnIfCronWorkspaceLowOnDisk`. Defer build until ENOSPC + GC-down reproduced.
- [ ] 2.C (H-C credit, resolved) No code fix; recovery confirmation + Phase 1 un-mute is the close.

## Phase 3 — Observability hardening (gated on Phase 0 confirming the catch executes)

- [ ] 3.1 Thread the scrubbed reason into BOTH `{ok:false}` returns — `:356` (setup catch) AND `:524` (output-missing/body-threw, from `spawnResult.stderrTail`/`threw`) — so `run-log.ts:158-189` maps it to `routine_runs.error_summary`. Widen handler return `{ok}`→`{ok, errorSummary?}` (ADR-033 I5: handler return, not `SpawnResult`; zero middleware change).

## Phase 4 — Regression test (RED first)

- [ ] 4.1 `cron-community-monitor-heartbeat.test.ts`: setup throw → exactly one `?status=error` + literal `errorSummary` field, `routine_runs.error_summary` string-equals the scrubbed reason (both `:356` and `:524`).
- [ ] 4.2 Non-final-attempt suppression (heartbeat skipped + rethrow, no interim row).
- [ ] 4.3 (H-A only) `cron-claude-eval-substrate.test.ts`: `isSweepable` removes only stale dirs (synthesized fixtures).
- [ ] 4.4 `tsc --noEmit` + `vitest run` green.

## Close-out

- [ ] 5.1 Reuse `scripts/followthroughs/community-monitor-checkin-soak-5728.sh` — re-point its tracker directive at #5732 (`earliest=<deploy+Nd>`). Build a new probe only if an H-A/H-B close needs a routine_runs-duration assertion.
- [ ] 5.2 PR body `Ref #5732` if post-merge close; post-merge `gh issue close` after AC8 recovery confirmed.
