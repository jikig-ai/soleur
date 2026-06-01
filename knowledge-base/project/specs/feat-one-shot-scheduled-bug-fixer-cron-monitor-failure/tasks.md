---
title: Tasks — Fix scheduled-bug-fixer Sentry cron error check-in
plan: knowledge-base/project/plans/2026-06-01-fix-scheduled-bug-fixer-cron-error-checkin-plan.md
lane: cross-domain
date: 2026-06-01
---

# Tasks — Fix `scheduled-bug-fixer` cron error check-in

Spec lacks a `spec.md` — defaulted to `lane: cross-domain` (TR2 fail-closed).

## Phase 0 — Preconditions

- [x] 0.1 Baseline: 30 tests green on this branch's base.
- [x] 0.2 Confirmed `SpawnResult.ok = exitCode === 0` (`_cron-claude-eval-substrate.ts:231`).
- [x] 0.3 Confirmed `!detectedPr` early-return (`cron-bug-fixer.ts:756`) was `ok: spawnResult.ok` and `:792` `&& !!detectedPr` was dead (early-return guarantees `detectedPr` truthy at `:792`).
- [x] 0.4 Enumerated every heartbeat-status test: status sites `:489`, `:577`, `:803`, `:828`; `result.ok` sites `:482`, `:566`, `:822`, `:888`.

## Phase 1 — Confirm root cause from Sentry (data-pull, no SSH)

- [x] 1.1 Pulled monitor check-ins (05-30 `ok` → 05-31 `error` → 06-01 `error`) + event `c05485aca66b4696844fd815e4ec4600` (the monitor's own auto-generated "Cron failure" marker, no `op`/extras) via Sentry API (token from Doppler `prd`).
- [x] 1.2 **Verdict: H1.** `reportSilentFallback` → `Sentry.captureException` (observability.ts:206) creates searchable project issues; a 14-day project search for `cron-bug-fixer` returned ZERO issues, so no infra-fault path (setup-workspace `:684`, claude-eval-timeout `:727`, parse-event `:601`, child_process.spawn) fired. Yet `status=error` was posted — the only remaining `status=error` sites (`:756`/`:794`) are both gated on `spawnResult.ok === false`. ⟹ claude exited non-zero with no infra fault (the normal "no fix today" outcome). H2/H3/H4 ruled out.
- [x] 1.3 Hypothesis + evidence recorded (for PR body). `auth-callback-no-code-burst` confirmed coincidental (unrelated project-wide issue alert sharing only the email channel; precedent 2026-05-27); no callback edits.

## Phase 2 — Fix (branch by hypothesis)

- [x] 2.A (H1 confirmed — primary) Decoupled heartbeat `ok` from `spawnResult.ok` in `cron-bug-fixer.ts`: both post-spawn heartbeats (`!detectedPr` branch + final) now post `ok:true`; added a structured `logger.warn` ("claude-eval exited non-zero (no fix landed); not paging the cron monitor") on `!spawnResult.ok`; kept the chronic-timeout `reportSilentFallback` (op=claude-eval-timeout) as a non-paging breadcrumb; kept infra-fault early-returns (`:691` setup-workspace, `:613` parse-event) at `status=error`. Handler return `ok` updated in lockstep; dead `overallOk = ... && !!detectedPr` removed.
- [~] 2.B (H3) N/A — H1 confirmed, not an infra fault. Monitor would have been correct to page on H3; left strict.
- [~] 2.C (H4) N/A — daily cron sends no `data`; parse-event path never fired.

## Phase 3 — Tests (RED→GREEN)

- [x] 3.1 Rewrote group (e) non-zero-exit test: `wireSpawn(1)` + no PR → asserts `status=ok` AND `result.ok === true` AND no infra-fault breadcrumb. (RED verified against pre-fix code: `expected false to be true`.)
- [x] 3.2 Added timeout-abort → `status=ok` test (real `AbortController` driven via fake timers; asserts monitor green + `claude-eval-timeout` breadcrumb still present). RED verified.
- [x] 3.3 Kept `status=error` tests: sentinel-missing, bad manual trigger; kept `status=ok` happy-path + no-issue. All unchanged + still green.
- [x] 3.4 `./node_modules/.bin/vitest run test/server/inngest/cron-bug-fixer.test.ts` → 31 passed.
- [x] 3.5 `function-registry-count.test.ts` → 7 passed; `./node_modules/.bin/tsc --noEmit` → clean.

## Phase 4 — Recover live monitor + close incident

- [ ] 4.1 After deploy, next `0 6 * * *` fire posts `status=ok`; `recovery_threshold=1` flips monitor green (optional faster: Inngest manual-trigger).
- [ ] 4.2 Confirm via Sentry Crons API the monitor reads `ok`; close incident `5127648` + any auto-filed issue (`gh issue close` post-recovery; `Ref #N` not `Closes #N` in PR body).

## Follow-up

- [ ] F.1 If H1 confirmed, file a follow-up issue to assess the same over-tight semantic in `cron-roadmap-review.ts:277` + `cron-legal-audit.ts:263` (do NOT widen this PR to all five claude-eval crons silently).
