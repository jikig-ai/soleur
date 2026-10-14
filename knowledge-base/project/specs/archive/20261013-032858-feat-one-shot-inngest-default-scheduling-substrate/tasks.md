---
title: "Tasks — feat-inngest-default-scheduling-substrate"
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-16-feat-inngest-default-scheduling-substrate-plan.md
date: 2026-06-16
---

# Tasks — Inngest default scheduling substrate

Derived from the deepened plan. NEW feature — no work-target issue. `Ref #5417` (first consumer), never `Closes #5417`.

## Phase 0 — Preconditions (/work)
- 0.1 Confirm runner + globs: `apps/web-platform/package.json scripts.test` + `vitest.config.ts include:` cover `test/server/inngest/*.test.ts` and `test/server/internal/*.test.ts`.
- 0.2 Read `event-scheduled-reminder.ts` (handler, `CHECK_REGISTRY` :58, `CheckResult` :46, comment POST :182-190), `scheduled-reminder-action.ts`, `route.ts`, `observability.ts:220` (captureException raw err).
- 0.3 Confirm `function-registry-count.test.ts:135` asserts 56 (no bump expected).

## Phase 1 — Contract widening (RED first)
- 1.1 `lib/inngest/scheduled-reminder-action.ts`: confirm `named-check` already carries `params?` — NO `ReminderAction` union widening. Add NO typed `sentry-issue-rate` variant.
- 1.2 `event-scheduled-reminder.ts`: widen `CheckResult` to `{ verdict; body; close?: boolean }` (boolean intent, NOT `close_issue?: number`).
- 1.3 `tsc --noEmit` — walk every TS2322 rail (only the seeded demonstrator + new check produce CheckResult).

## Phase 2 — sentry-issue-rate check + handler close
- 2.1 Add `"sentry-issue-rate"` to `CHECK_REGISTRY`. Fire-time param validation: `tag` regex `^[A-Za-z0-9_.-]+:[A-Za-z0-9_.\-/]+$` (reject `&`/`?`/`#`/ws/`..`), `max_per_day` finite `>0`, `window_hours ∈ [1,168]`, optional `close_on_pass`. Env guard (`SENTRY_AUTH_TOKEN`/`SENTRY_ORG`/`SENTRY_PROJECT`/`SENTRY_API_HOST`) → `info` + `sentry-issue-rate-misconfig`.
- 2.2 Tag→issue-id: `GET https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/issues/?query=<tag>&project=${SENTRY_PROJECT}&statsPeriod=<window>` via `new URL`+`URLSearchParams`. Slug for `project=` (NOT empty `SENTRY_PROJECT_ID`). Bounded `fetch` (AbortController ~10s). Fail-closed `info` on 0/>1 matches.
- 2.3 **Live-probe** the stats endpoint (issue-detail `?statsPeriod=` `stats` object vs project-stats `?resolution=1d` `[ts,count]` tuples); pick the sum-able shape, document inline. Compute `events_per_day = total / (window_hours/24)`.
- 2.4 Verdict: `<= max_per_day` → `pass` (+ `close:true` iff `close_on_pass`); else `fail`. Token-free error construction (never forward raw Sentry err/body/header to `reportSilentFallback`).
- 2.5 Handler: after comment POST, if `result.close === true` → `PATCH .../issues/{action.report_to_issue}` (state=closed, state_reason=completed), try/catch → `named-check-close-failed`. PATCH target is `action.report_to_issue` only. Update header comment + invariant ("one self-scoped close; new channels require ADR").

## Phase 3 — Tests
- 3.1 `event-scheduled-reminder.test.ts`: pass+close, pass+no-close, fail-no-close, 0/>1 match `info`, env-missing `info`, invalid/out-of-bounds params `info`, `tag`-injection rejected (no/safe fetch), token-non-leak (no `Bearer`/token in reported msg), host=`jikigai-eu.sentry.io` + slug `project=`, seeded demonstrator still green. NO scope-violation test (boolean = unrepresentable).
- 3.2 `schedule-reminder-route.test.ts`: one case — `named-check check:"sentry-issue-rate"` + params → 202.
- 3.3 `function-registry-count.test.ts` — confirm UNCHANGED at 56.

## Phase 4 — Step 0 routing gate (BODY only)
- 4.1 `plugins/soleur/skills/schedule/SKILL.md`: insert "## Step 0: Execution-substrate routing gate" before Step 0a. Route (a) fire-time-prd-secret/server-side → reminder primitive (sentry-issue-rate worked example) or oneshot, STOP no GHA; (b) periodic + sweeper-allowlisted secret → follow-through sweeper; (c) pure-GH → GHA-cron. Cite the runbook + followthrough-convention.
- 4.2 Update preamble: gate = primary, hook = backstop, add follow-through sweeper. **Do NOT edit `description:` frontmatter** (budget 2250/2250).
- 4.3 `bun test plugins/soleur/test/components.test.ts` green.

## Phase 5 — (Optional) hook override tighten
- 5.1 `.claude/hooks/new-scheduled-cron-prefer-inngest.sh`: require `reason:` clause in override marker; `.test.sh` case (c) updated + (c2) bare-marker → deny; keep fail-open/exit-0. Scope out with tracking issue if it risks scope.

## Phase 6 — Docs
- 6.1 Amend `inngest-oneshot-and-reminder-patterns.md`: sentry-issue-rate parametric check, slug-friendly endpoint, host trap, v1.1 close invariant, "## Step 0: which substrate?".
- 6.2 Create terse ADR (`/soleur:architecture create`): v1→v1.1 boundary + substrate-default decision.

## Post-merge (operator, NOT this PR)
- AC12 arm POST for #5417 after deploy (operator-held `INNGEST_MANUAL_TRIGGER_SECRET`); exact curl in PR body. Verify trigger-cron cannot cover it (AP-007).
