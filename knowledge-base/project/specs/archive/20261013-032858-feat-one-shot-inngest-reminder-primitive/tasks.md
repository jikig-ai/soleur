# Tasks — feat: Inngest oneshot pattern + generic reminder primitive

lane: cross-domain
Plan: `knowledge-base/project/plans/2026-06-03-feat-inngest-oneshot-pattern-and-reminder-primitive-plan.md`

Additive only — do NOT modify the 5 existing oneshots or any `cron-*.ts`.

## Phase 0 — Preconditions (verify, no code)

- [ ] 0.1 Confirm `app/api/inngest/route.ts` array length is 49 (`grep -cE '^\s+\w+,$'`).
- [ ] 0.2 Confirm `trigger-cron/route.ts` reads `INNGEST_MANUAL_TRIGGER_SECRET`.
- [ ] 0.3 Confirm `EXEMPT_ROUTES` is in `lib/auth/csrf-coverage.test.ts:14` and keys on relative route-file path.
- [ ] 0.4 Re-read `oneshot-4650-monitor-close.ts` + `.test.ts` as the structural template.

## Phase 1 — Part B: shared action module + RED tests (TDD)

- [ ] 1.1 Create `apps/web-platform/lib/inngest/scheduled-reminder-action.ts`: `ReminderAction` union,
      `MAX_COMMENT_BODY = 65000`, `validateReminderAction(raw)` (exhaustive switch, default arm rejects),
      `ReminderEventData` type. Rules: issue-comment (positive int issue, non-empty body ≤ 65000); named-check
      (non-empty check string, positive int report_to_issue, plain-object params); any other type → reject.
- [ ] 1.2 Create RED `test/server/inngest/event-scheduled-reminder.test.ts` (mirror oneshot-4650 mocks:
      `vi.hoisted` spies, `function`-keyword Octokit constructor mock, hand-rolled `makeStep()`).
- [ ] 1.3 Create RED `test/server/internal/schedule-reminder-route.test.ts` (mirror trigger-cron-route:
      `ORIG_SECRET` capture/restore, `makeRequest` helper, mock send-with-retry/observability/client).
- [ ] 1.4 Add RED assertions to `test/middleware.test.ts` and `test/server/inngest/function-registry-count.test.ts`.

## Phase 2 — Part B: the Inngest function (GREEN)

- [ ] 2.1 Create `server/inngest/functions/event-scheduled-reminder.ts`: header (ADR-046 endpoint-armed
      note + ADR-033 I1/I2/I5/I6 + NO Sentry monitor), `isValidIsoInstant`, `CHECK_REGISTRY` seeded with
      `open-silence-issue-count` (read-only), handler (guards FIRST → issue-comment step → named-check step
      with registry-membership reject + verdict==="fail" → reportSilentFallback error-level), exported
      `eventScheduledReminder` createFunction (`reminder.scheduled`, cron-platform concurrency, retries:1).
- [ ] 2.2 Register `eventScheduledReminder` in `app/api/inngest/route.ts` (import + array entry near `event*`).
- [ ] 2.3 Bump `function-registry-count.test.ts` `(a)` 49 → 50.
- [ ] 2.4 GREEN: handler tests pass.

## Phase 3 — Part B: internal emit endpoint (GREEN)

- [ ] 3.1 Create `app/api/internal/schedule-reminder/route.ts` — mirror `trigger-cron` auth verbatim
      (503 unset / 401 mismatch / 413 / 400, dynamic client import), validate body
      (`reminder_id` non-empty, `fire_at` real ISO, `actor === "platform"`, `validateReminderAction(action).ok`),
      `sendInngestWithRetry(() => inngest.send({ name:"reminder.scheduled", id:reminder_id,
      ts:Date.parse(fire_at), data }), { feature:"schedule-reminder" })` → 202 / 502. POST export only.
- [ ] 3.2 Add `/api/internal/schedule-reminder` to `PUBLIC_PATHS` in `lib/routes.ts` (narrow exact + comment).
- [ ] 3.3 Add `"app/api/internal/schedule-reminder/route.ts"` to `EXEMPT_ROUTES` in `csrf-coverage.test.ts`.
- [ ] 3.4 Add `middleware.test.ts` membership + prefix-collision assertions; GREEN endpoint + middleware tests.

## Phase 4 — Part A: docs + scaffold + skill pointers

- [ ] 4.1 Create `knowledge-base/engineering/ops/runbooks/inngest-oneshot-and-reminder-patterns.md`
      (decision matrix 4 rows; 3 integration points + count bump; 4 gotchas).
- [ ] 4.2 Create `server/inngest/functions/oneshot-TEMPLATE.ts.template` (copy-fill, `.ts.template` ext,
      3-integration-point trailer).
- [ ] 4.3 Wire `/ship` Step 3.5.B (`plugins/soleur/skills/ship/SKILL.md` ~1624) — 2 autonomous pattern
      bullets (body only, no description edit).
- [ ] 4.4 Wire `/soleur:schedule` (`plugins/soleur/skills/schedule/SKILL.md`) — GH-Actions-cron-only note +
      Inngest/reminder pointer (body only).

## Phase 5 — Verify

- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/vitest run` the 4 new/changed test paths IN ISOLATION
      (NOT the whole `test/server/inngest/` dir — avoid the `signature-verify` env-leak flake).
- [ ] 5.2 `./node_modules/.bin/tsc --noEmit` clean.
- [ ] 5.3 `git diff --stat` shows the 5 oneshots + every `cron-*.ts` are unmodified.
- [ ] 5.4 Confirm `.ts.template` did not change the registry count (`(a)` still 50) or trip tsc/vitest.

## Review gate

- [ ] R1 security-sentinel scrutinizes endpoint → installation-token GitHub-write boundary + action
      allowlist completeness (AC-S1/AC-S2/AC-S3).
