# Tasks — cron-6109-defer-gate-eval (self-disarming defer-gate nudge)

Plan: `knowledge-base/project/plans/2026-07-06-feat-cron-6109-defer-gate-eval-plan.md`
Refs #6109 (NOT Closes — #6109 stays OPEN).

## Phase 1 — New cron function

- [ ] 1.1 Create `apps/web-platform/server/inngest/functions/cron-6109-defer-gate-eval.ts`.
- [ ] 1.2 Constants: `FUNCTION_NAME`/`SENTRY_MONITOR_SLUG = "cron-6109-defer-gate-eval"`,
  `TOKEN_MIN_LIFETIME_MS = 15*60*1000`, exported `ISSUE_NUMBER = 6109`,
  `DEFER_GATE_OPEN = "2026-08-31"`, `PRODUCER_MERGE_DATE = "2026-07-06"`,
  `DEFER_GATE_MARKER = "<!-- cron-6109-defer-gate-eval -->"`.
- [ ] 1.3 Handler `cron6109DeferGateEvalHandler`:
  - [ ] 1.3.1 Pure date guard (outside `step.run`): validate optional `data.date_override`
    (`/^\d{4}-\d{2}-\d{2}$/`); `today = date_override ?? new Date().toISOString().slice(0,10)`.
  - [ ] 1.3.2 `today < DEFER_GATE_OPEN` → `warnSilentFallback(op:"date-guard")`, post
    heartbeat `ok:true` (liveness), return `{ ok:false, reason:"date-guard" }`.
  - [ ] 1.3.3 `check-and-eval` step: mint token INSIDE step with
    `ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS`; new `Octokit`; GET issue → closed ⇒
    `{ok:true, reason:"already-handled", heartbeatOk:true}`; paginate comments
    (`per_page:100`) → marker found ⇒ same; else POST one comment with `NUDGE_BODY`
    (embeds marker + `/soleur:go 6109` + window/producer dates) ⇒
    `{ok:true, reason:"posted", heartbeatOk:true}`; catch ⇒ `redactToken` + preserve
    `Error.name` + `reportSilentFallback(op:"check-and-eval")` ⇒
    `{ok:false, reason:"api-error", heartbeatOk:false}`.
  - [ ] 1.3.4 `sentry-heartbeat` step: `postSentryHeartbeat({ ok: result.heartbeatOk, ... })`.
- [ ] 1.4 Registration `cron6109DeferGateEval` — id `"cron-6109-defer-gate-eval"`,
  concurrency `[{scope:"fn",limit:1},{scope:"account",key:'"cron-platform"',limit:1}]`,
  `retries:1`, triggers `[{cron:"0 9 1 * *"},{event:"cron/6109-defer-gate-eval.manual-trigger"}]`.

## Phase 2 — Route registration

- [ ] 2.1 `app/api/inngest/route.ts`: add import (after `cfoOnPaymentFailed`, line ~21) +
  `cron6109DeferGateEval,` in the `serve` functions array (first cron entry).

## Phase 3 — Watchdog manifest

- [ ] 3.1 `server/inngest/cron-manifest.ts`: add `"cron-6109-defer-gate-eval"` to
  `EXPECTED_CRON_FUNCTIONS` (alphabetically first). (Manual-trigger allowlist auto-derives.)

## Phase 4 — Sentry monitor Terraform (guard c+f)

- [ ] 4.1 `infra/sentry/cron-monitors.tf`: add `sentry_cron_monitor "cron_6109_defer_gate_eval"`
  (`name = "cron-6109-defer-gate-eval"`, `crontab = "0 9 1 * *"`, margin 30, runtime 5),
  mirroring `scheduled_nag_4216_readiness`.
- [ ] 4.2 `.github/workflows/apply-sentry-infra.yml`: add
  `-target=sentry_cron_monitor.cron_6109_defer_gate_eval \` to the target block.

## Phase 5 — Registry-count guard

- [ ] 5.1 `test/server/inngest/function-registry-count.test.ts`: bump guard (a) count
  `60 → 61`. Do NOT add slug to `KNOWN_UNMONITORED_SLUGS` (real monitor shipped).

## Phase 6 — Unit test

- [ ] 6.1 Create `test/server/inngest/cron-6109-defer-gate-eval.test.ts` (mirror
  `cron-nag-4216-readiness.test.ts` mock scaffold): date-guard no-op (heartbeat green),
  marker self-disarm, exactly-one-comment when open+no-marker, closed self-disarm,
  GET-throws api-error, source-shape anchors.

## Phase 7 — Verify

- [ ] 7.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 7.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-6109-defer-gate-eval.test.ts test/server/inngest/function-registry-count.test.ts`.
- [ ] 7.3 PR body `Refs #6109` (NOT `Closes`).
