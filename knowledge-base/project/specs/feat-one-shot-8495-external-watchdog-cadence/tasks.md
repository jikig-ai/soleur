# Tasks: fix — reliable watchdog dispatch cadence (#8495)

Plan: `knowledge-base/project/plans/2026-09-24-fix-external-watchdog-dispatch-cadence-plan.md`

## Phase 0: RED (tests first)

- [ ] 0.1 Create `apps/web-platform/test/server/watchdog-dispatch-clock.test.ts`.
  - [ ] 0.1.1 Write scenarios C1–C13, using vitest fake timers and injected deps (`now`, `random`,
    `mint`, `octokitFor`, `report`, `log` and the timer functions).
  - [ ] 0.1.2 Add an `unhandledRejection` spy for the Guard 2 rows.
  - [ ] 0.1.3 Run the file against a stub module and confirm every case is RED.
- [ ] 0.2 Add a `describe("Watchdog dispatch clock parity (#8495)")` block to
  `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts`.
  - [ ] 0.2.1 Import `WATCHDOG_DISPATCH_TABLE`. Assert the slug set, and that
    `checked === table.length`.
  - [ ] 0.2.2 Assert, per entry: `workflow_dispatch` is present, `concurrency` has
    `cancel-in-progress: false`, the crontab appears in the workflow crons, `monitor-slug`
    matches, margin is in `[12, interval]`, and `eligibility` is non-empty.
  - [ ] 0.2.3 Assert the #8495 pin: inngest `intervalMinutes <= 15`.
  - [ ] 0.2.4 Add a pure `marginWithinBudget` in the test file, with the must-PASS and must-RED
    cases.

## Phase 1: Clock module + boot wiring

- [ ] 1.1 Create `apps/web-platform/server/watchdog-dispatch-clock.ts`.
  - [ ] 1.1.1 `WATCHDOG_DISPATCH_TABLE` with `{ workflowFile, monitorSlug, intervalMinutes, eligibility }`
    for inngest-health (15) and zot (60).
  - [ ] 1.1.2 `slotStartAt`, `slotAlreadyHasRun` (`created_at >= S − 60 s`), and
    `shouldArmWatchdogClock` (`NODE_ENV=production` and a trimmed `SOLEUR_HOST_ID`).
  - [ ] 1.1.3 `startWatchdogDispatchClock(deps?)`:
    - `setInterval(poll, 30 s).unref()`;
    - per-slot jitter of 30–150 s;
    - a late cutoff at `S + interval − 2 min`;
    - `handledSlot` / `inFlight`.
  - [ ] 1.1.4 `runTickSafely`:
    - `withTimeout(90 s)` on the injected timers, with `clearTimeout` in `finally`;
    - mint scoped `{ actions: "write" }` and `repositories: [REPO_NAME]`;
    - a `per_page=1` read that fails open;
    - an inlined dispatch POST with `ref: main` and an Octokit `request.signal`;
    - `reportSilentFallback` (`op` ∈ mint/dedup-read/dispatch, `extra.reason`), itself inside a
      try/catch, with `redactToken` applied;
    - an info log line `{ host, slot, workflow, outcome }` on every tick.
  - [ ] 1.1.5 Emit a `disarmed` boot line, plus an `op=arm` report when running in production.
- [ ] 1.2 In `apps/web-platform/server/index.ts`, arm after `server.listen`, and call `stop()` in
  SIGTERM next to `clearInterval(ccIdleReaperTimer)`.
- [ ] 1.3 Get the clock tests GREEN. `cron-main-health-monitor.ts` stays untouched.

## Phase 2: Sentry monitors + workflow headers

- [ ] 2.1 `cron-monitors.tf`:
  - [ ] 2.1.1 Change `zot_restart_loop_alarm.checkin_margin_minutes` from 120 to 30.
  - [ ] 2.1.2 Rewrite both rationale comments: the clock is primary, the GH schedule is the
    fallback, and include the margin-budget arithmetic.
  - [ ] 2.1.3 Leave crontabs unchanged.
- [ ] 2.2 Edit the header comments only in `scheduled-inngest-health.yml` and
  `scheduled-zot-restart-loop.yml`. Line 1, the gate-override, stays byte-identical.
- [ ] 2.3 Get the parity block GREEN, then:
  - [ ] 2.3.1 Apply Guard 1 rows 1, 2, 3 and 7 once and record each RED.
  - [ ] 2.3.2 Run `terraform fmt -check` and `terraform validate` on `apps/web-platform/infra/sentry`.

## Phase 3: ADR + C4 + runbooks

- [ ] 3.1 Create the short ADR-246 (provisional ordinal).
  - [ ] 3.1.1 Cover the decision, the failure domains, the eligibility rule, the fleet-uniqueness
    sentence, the alternatives, and the reversal triggers.
  - [ ] 3.1.2 Add a one-line cross-reference in ADR-033.
- [ ] 3.2 Make the `model.c4` edits, located by anchor text:
  - [ ] 3.2.1 Add the new `api -> github` watchdog edge.
  - [ ] 3.2.2 Add the `github -> sentry` parenthetical. Keep the numbers and anchor phrases
    verbatim.
  - [ ] 3.2.3 Fix the tunnel census wording.
  - [ ] 3.2.4 Fix the zot `*/30` comment.
- [ ] 3.3 In `inngest-server.md`, add a "How the external watchdogs are triggered" subsection
  answering: is it running, how to stop it, how to change the table (checklist), and which host
  sent a run. Include the canary note.
- [ ] 3.4 In `betterstack-log-query.md`, fix the stale zot "every 30 min" and add a pointer.
- [ ] 3.5 Run the C4 checks: `c4-count-parity.test.sh`, `c4-code-syntax.test.ts` and
  `c4-render.test.ts`.

## Phase 4: Verification + ship prep

- [ ] 4.1 Run the targeted vitest: clock, iac-parity, function-registry-count,
  cron-main-health-monitor, and the c4 tests.
- [ ] 4.2 Run `bash .claude/hooks/new-scheduled-cron-prefer-inngest.test.sh`.
- [ ] 4.3 Run the AC5 comment-only diff check on both workflows.
- [ ] 4.4 File the issues:
  - the Cloudflare Worker upgrade-path issue, labelled `deferred-scope-out` and re-evaluated at
    #7230;
  - the C4 `api -> supabase` "every GitHub App-token use" overclaim;
  - a comment on #8595.
- [ ] 4.5 In the PR body:
  - the first line states that merging mutates production through `web-platform-release.yml` and
    `apply-sentry-infra.yml`;
  - `Closes #8495`;
  - render `decision-challenges.md`.
- [ ] 4.6 Postmerge: AC9 (Better Stack `armed` on web-1 and web-2), AC10 (Sentry monitors `ok`,
  zot margin 30), and AC11 (the `gh run list` gap check). Reopen #8495 if any of them fails.
