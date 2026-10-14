# Tasks: fix — reliable watchdog dispatch cadence (#8495)

Plan (deepened 2026-09-24): `knowledge-base/project/plans/2026-09-24-fix-external-watchdog-dispatch-cadence-plan.md`

## Phase 0: RED (tests first)

- [x] 0.1 Create `apps/web-platform/test/server/watchdog-dispatch-clock.test.ts`.
  - [x] 0.1.1 Harness. Inject `deps.table`, `now`, `random`, `mint`, `octokitFor`, `report`,
    `emit` and the timers. Save `realSetImmediate` before `vi.useFakeTimers()`, and advance with
    `advanceTimersByTimeAsync`. Add the `unhandledRejection` listener in `beforeEach` and remove it
    in `afterEach`. Count POSTs per workflow path.
  - [x] 0.1.2 Write scenarios C1–C16, including the C7 redaction fixture, where the token appears
    in the message, `request.headers.authorization` and `response.data`.
  - [x] 0.1.3 Run against a stub module and confirm every case fails.
- [x] 0.2 Add a `describe("Watchdog dispatch clock parity (#8495)")` block to
  `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts`.
  - [x] 0.2.1 Add helpers: `workflowOn(file)`, which parses the `on` keys and the top-level
    `concurrency` with the `yaml` dep, and `monitorFieldBySlug(tf, slug, field)`.
  - [x] 0.2.2 Assert per entry:
    - `eligibility` is non-empty;
    - the trigger set is exactly `{schedule, workflow_dispatch}`;
    - `cancel-in-progress: false`;
    - the crontab appears in the workflow's crons;
    - `monitor-slug` matches;
    - the margin is within `[ceil(3 + max_runtime), interval]`.
  - [x] 0.2.3 Assert the slug set equals the expected set, and `checked === table.length`.
  - [x] 0.2.4 Pin inngest `intervalMinutes <= 15`, with the assertion citing #8495.
  - [x] 0.2.5 Assert no `.github/workflows/*.yml` or `apps/web-platform/playwright*.config.ts`
    sets `SOLEUR_HOST_ID`.
  - [x] 0.2.6 Add a pure `marginWithinBudget` with rows H2 (must-PASS and must-RED).

## Phase 1: Clock module + boot wiring

- [x] 1.1 Create `apps/web-platform/server/watchdog-dispatch-table.ts`. It has no imports.
  - [x] 1.1.1 The table holds two entries: inngest-health (15) and zot (60).
  - [x] 1.1.2 Each entry has an `eligibility` string.
- [x] 1.2 Create `apps/web-platform/server/watchdog-dispatch-clock.ts`.
  - [x] 1.2.1 Add `slotStartAt`, `slotAlreadyHasRun` (`created_at >= S − 60 s`), and
    `shouldArmWatchdogClock` (production plus a trimmed `SOLEUR_HOST_ID`).
  - [x] 1.2.2 Add the poll:
    - `setInterval(poll, 30 s).unref()`;
    - one jitter draw per `(entry, slot)` in `[30 s, 150 s]`;
    - late cutoff at `S + interval − 2 min`;
    - `handledSlot` and `inFlight` flags.
  - [x] 1.2.3 Add `runTickSafely` with three fences: the inner try/catch/finally, the outer
    `.catch` → `tick_escaped`, and a try/catch around `report`. Wrap it in
    `withTimeout(90 s)` on the injected timers, with `clearTimeout` in `finally`.
  - [x] 1.2.4 Mint in-module:
    `createProbeOctokit` → `GET /repos/jikig-ai/soleur/installation` →
    `generateInstallationToken(id, { minRemainingMs: 5 min, permissions: { actions: "write" }, repositories: ["soleur"] })`.
    Do not import from `server/inngest/`.
  - [x] 1.2.5 Add a `per_page=1` read that fails open.
  - [x] 1.2.6 Inline the dispatch `POST {ref: "main"}`, passing an Octokit `request.signal`.
  - [x] 1.2.7 Report failures by building a new `Error(redactToken(msg, token))`, with `op` and
    `extra.{workflow, reason, status}`. Never forward the raw Octokit error.
  - [x] 1.2.8 On each tick, emit the marker with `{host_id, workflow, slot, outcome, op?, reason?, status?, run_id?, run_event?}`.
    Emit a boot `armed`/`disarmed` marker, plus a report with `op=arm` when disarmed in
    production.
- [x] 1.3 In `apps/web-platform/server/cron-liveness-marker.ts`, add `emitWatchdogDispatch`:
  a WARN marker, `SOLEUR_WATCHDOG_DISPATCH: true`, fail-open.
- [x] 1.4 In `apps/web-platform/.dependency-cruiser.cjs`, add the forbidden rule (DEVIATION: enforced by a transitive-import walker in watchdog-dispatch-clock.test.ts instead; .dependency-cruiser.cjs is generated + non-blocking — see session-state.md)
  `watchdog-clock-not-via-inngest` (`^server/watchdog-dispatch-` must not reach `^server/inngest/`).
- [x] 1.5 In `apps/web-platform/server/index.ts`, add
  `const watchdogClock = startWatchdogDispatchClock()` right after `startCcIdleReaper()`. In
  SIGTERM, call `watchdogClock.stop()` synchronously beside `clearInterval(ccIdleReaperTimer)`.
- [x] 1.6 Get the clock tests GREEN and the dep-cruiser gate passing. Leave
  `cron-main-health-monitor.ts` untouched.

## Phase 2: Sentry monitors + workflow headers

- [x] 2.1 In `cron-monitors.tf`, set zot `checkin_margin_minutes` from 120 to 30. Rewrite both
  rationale comments: the clock is primary, the GH schedule is the fallback, and include the
  margin-budget arithmetic. Leave the crontabs unchanged.
- [x] 2.2 Edit only the header comments of both workflows. Line 1 (the gate-override) must stay
  byte-identical.
- [x] 2.3 Get the parity block GREEN.
  - [x] 2.3.1 Apply Guard 1 rows 1, 3, 7 and 8, and Guard 2 row 6. Record each RED.
  - [x] 2.3.2 Run `terraform fmt -check` and `terraform validate` on `apps/web-platform/infra/sentry`.

## Phase 3: ADR + C4 + runbooks

- [x] 3.1 Write ADR-248 (provisional ordinal). It must cover:
  - the decision and the failure-domain table;
  - the eligibility rule, citing ADR-033;
  - the ADR-068 Bucket-B fleet rule and the ADR-078 non-participation rationale;
  - the alternatives;
  - the reversal triggers: #7230, Workers plus a narrow App, and a single `var.web_hosts` host;
  - a "Relates to" line: ADR-033, ADR-068, ADR-143 D2, ADR-241.

  Add a one-line cross-reference to ADR-033.
- [x] 3.2 Edit `model.c4`, locating each change by its anchor text.
  - [x] 3.2.1 Add a new `api -> github` watchdog edge.
  - [x] 3.2.2 In the `github -> sentry` edge, add the "fourth substrate" parenthetical. Keep its
    numbers and anchor phrases verbatim.
  - [x] 3.2.3 Update the tunnel census wording.
  - [x] 3.2.4 Fix the zot `*/30` comment.
  - [x] 3.2.5 Annotate web-2's "scheduler-less standby" text in the tunnel element and in the
    `hetzner -> tunnel` edge.
- [x] 3.3 Add an `inngest-server.md` subsection. It answers four questions, each with a command:
  - Is it running? (the marker query, plus the gh one-liner)
  - How do I stop it? (`gh workflow disable`, or a revert)
  - How do I change the table? (a checklist)
  - Which host sent a run? (the marker `host_name`/`run_id`; the canary is not shipped)

  It also carries the canary note.
- [x] 3.4 In `betterstack-log-query.md`, fix the stale zot "every 30 min" and add the
  `SOLEUR_WATCHDOG_DISPATCH` marker.
- [x] 3.5 Run the C4 checks: `c4-count-parity.test.sh`, `c4-code-syntax.test.ts` and
  `c4-render.test.ts`.

## Phase 4: Verification + ship prep

- [x] 4.1 Run the targeted vitest suites: clock, iac-parity, function-registry-count,
  cron-main-health-monitor and c4. Also run the dep-cruiser gate.
- [x] 4.2 Run `bash .claude/hooks/new-scheduled-cron-prefer-inngest.test.sh`.
- [x] 4.3 Run the AC5 comment-only diff check on both workflows.
- [x] 4.4 File the issues: (DONE differently — code-simplicity CONCUR gate DISSENTED on the Worker `deferred-scope-out` issue, so the re-evaluation hook went on #7230 as a comment (issuecomment-5810551088); the C4 overclaim was fixed inline; #8595 commented (issuecomment-5810547232))
  - the Cloudflare-Worker upgrade path (`deferred-scope-out`, re-evaluate at #7230);
  - the C4 `api -> supabase` "every GitHub App-token use" overclaim;
  - a comment on #8595.
- [ ] 4.5 Write the PR body:
  - the first line states that merging mutates production through `web-platform-release.yml`
    and `apply-sentry-infra.yml`;
  - `Closes #8495`;
  - render `decision-challenges.md`.
- [ ] 4.6 Postmerge checks:
  - AC9: the `betterstack-query.sh --grep SOLEUR_WATCHDOG_DISPATCH` query shows `armed` on
    `soleur-web-platform` and `soleur-web-2`;
  - AC10: the Sentry monitors are `ok`, the margin is 30, and there is no `op=mint` event;
  - AC11: the `gh run list` gap check passes.

  If any of them fails, reopen #8495.
