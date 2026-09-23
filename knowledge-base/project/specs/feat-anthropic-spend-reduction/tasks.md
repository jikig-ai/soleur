---
feature: feat-anthropic-spend-reduction
plan: knowledge-base/project/plans/2026-09-23-fix-anthropic-spend-cron-524-double-run-plan.md
lane: cross-domain
---

# Tasks: stop Cloudflare-524 double-runs and cut operator Anthropic spend

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Phase 0 — Streaming spike (decides Fix 1A vs 1B)

- [ ] 0.1 Download `inngest` v1.19.4 and `cloudflared` release binaries into the scratchpad.
- [ ] 0.2 Build a minimal Next.js App Router app on `inngest@3.54.2` with `serve({ streaming: "force" })` and three functions (2s, 3 min, 25 min steps).
- [ ] 0.3 Expose it through a Cloudflare quick tunnel, register it with a local `inngest start`, and run each function 3 times.
- [ ] 0.4 Record: attempts per run, any `invalid status code: 524`, whether `"allow"` streams, the heartbeat interval.
- [ ] 0.5 Write and commit `knowledge-base/project/specs/feat-anthropic-spend-reduction/streaming-spike.md`; name the branch (A or B).

## Phase 1 — Fix 1 (single session per run)

- [ ] 1.1 Write `apps/web-platform/test/server/inngest/claude-eval-single-flight.test.ts` (Guard 1 rows 1–6, H1, H2), RED.
- [ ] 1.2 Branch A: add `streaming: "force"` to `serve()` in `app/api/inngest/route.ts`, with a comment citing the spike and ADR-238.
- [ ] 1.3 Add the `globalThis` in-flight map to `spawnClaudeEval` (set before the first `await`, delete on settle, join on hit, `reportSilentFallback op=claude-eval-singleflight-join`).
- [ ] 1.4 Move `cron-daily-triage` and `cron-follow-through-monitor` onto `spawnClaudeEval`; update their tests.
- [ ] 1.5 Go green; run the full `test/server/inngest` suite.
- [ ] 1.6 Branch B only: implement Fix 1B exactly as the plan specifies (step id `claude-eval` kept, dedup for the same cron, slot-based poll counting, envelope file in the run's workspace, GC skip, monitor margins, state logs).

## Phase 2 — Fix 4 telemetry

- [ ] 2.1 Add `is_error`, `subtype` and `num_turns` to the cost marker (additive; no `CaptureStatus` widening).
- [ ] 2.2 Root-cause why `cost_usd` is null on every marker; fix it; add a unit test on a synthesized result line.

## Phase 3 — Fix 3 budget cap

- [ ] 3.1 Verify `--max-budget-usd` and its budget-stop `subtype` on `@anthropic-ai/claude-code@2.1.219`; bump the pin in `package.json` and `Dockerfile` together if needed.
- [ ] 3.2 Derive each cron's cap (`max(3 × median session cost at post-Fix-2 prices, $2)`) and the worst-case-daily column from the marker export.
- [ ] 3.3 Add the flag to each claude-eval cron's `CLAUDE_CODE_FLAGS`.

## Phase 4 — Fix 2 model re-pin

- [ ] 4.1 Verify `claude-opus-5-5` with `GET /v1/models/claude-opus-5-5`.
- [ ] 4.2 Set `AUDIT_MODEL = "claude-opus-5-5"`; update `model-tiers.test.ts` and the header comments.
- [ ] 4.3 `git grep -nE 'claude-opus-5([^-.]|$)' -- apps/web-platform` returns nothing.

## Phase 5 — Alerts, ADR, C4, ledger

- [ ] 5.1 Add the `inngest_step_524` and `claude_daily_burn` explorations and alerts to `betterstack-logs-alerts.tf` ($9/day; also page on a stuck-at-zero stream).
- [ ] 5.2 Add the four `-target=` lines to `apply-web-platform-infra.yml`; reconcile every other `logtail_exploration` consumer.
- [ ] 5.3 Write `test/infra/inngest-step-524-alert.test.sh` (Guard 2 rows 1–4); register it in `infra-validation.yml`; `terraform validate`.
- [ ] 5.4 Write ADR-238 (re-verify the ordinal across all `origin/*` refs), including the spike result, alternatives, single-flight contract, cap table and burn threshold.
- [ ] 5.5 Fix the C4 edge in `model.c4`, regenerate `model.likec4.json`, and run the five C4 tests.
- [ ] 5.6 Update `knowledge-base/operations/expenses.md` and `knowledge-base/finance/cost-model.md` with the measured funded-day figure.

## Phase 6 — Post-merge check (in `soleur:ship`, once credit is present)

- [ ] 6.1 Fire cron-seo-aeo-audit, cron-community-monitor, cron-architecture-diagram-sync and cron-compound-promote via `soleur:trigger-cron`; watch one event function's next natural run.
- [ ] 6.2 From Better Stack: one cost marker per run id, zero 524s, one attempt per run, and a committed PR/issue per cron.
