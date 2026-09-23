---
feature: feat-anthropic-spend-reduction
plan: knowledge-base/project/plans/2026-09-23-fix-anthropic-spend-cron-524-double-run-plan.md
lane: cross-domain
---

# Tasks: stop Cloudflare-524 double-runs and cut operator Anthropic spend

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Phase 0 — Streaming spike (decides Fix 1A vs 1B)

- [x] 0.1 Download `inngest` v1.19.4 and `cloudflared` release binaries into the scratchpad.
- [x] 0.2 Safety first: throwaway keys (`openssl rand -hex 32`), `env -i` with `INNGEST_DEV=0`, no Doppler, bind to 127.0.0.1, `trap` tunnel teardown, spike functions import nothing that reads production secrets.
- [x] 0.3 (deviation: a transport-mirroring server; S7 re-ran with the production crash handlers — streaming-spike.md) Run the app's own `server/index.ts` with `serve({ streaming: "force" })` and the spike function set (S1 2s, S2 3 min, S3 70 min, S4 throw-then-succeed, S5 NonRetriableError, S6 two steps + `step.sleep`, S7 stream cut mid-way at `retries: 1` and `retries: 3`, S8 real leader-loop chain with step 3 failing once, plus one throttled function).
- [x] 0.4 Expose it through a Cloudflare quick tunnel with `Accept-Encoding: gzip`, send one unsigned POST (expect a 401 envelope, no function run), then run S1–S6 and S8 three times each and S7 at both retry settings.
- [x] 0.5 (gzip not recorded) Record attempts, any 524, the S7 server error text, whether `"allow"` streams, the heartbeat interval, gzip behavior, body-signature acceptance, and throttle support.
- [x] 0.6 Write and commit `streaming-spike.md` with no tunnel hostname or keys; name the branch (A or B).

## Phase 1 — Fix 1 (single session per run)

- [x] 1.1 Write `apps/web-platform/test/server/inngest/claude-eval-single-flight.test.ts` (Guard 1 rows 1–6, H1, H2), RED.
- [x] 1.2 Branch A: add `streaming: "force"` to `serve()` in `app/api/inngest/route.ts`, with a comment citing the spike and ADR-243; rewrite the four 401 assertions in `signature-verify.test.ts` to read the streamed envelope.
- [x] 1.3 (revised: a fulfilled result is kept 15 min, a rejection cleared at once — ADR-243) Add the `globalThis` in-flight map to `spawnClaudeEval`: set before the first `await`, clear in `finally`, join on hit (`op=claude-eval-singleflight-join`); skip plus report when `runId` is not ULID-shaped (`op=claude-eval-singleflight-no-runid`).
- [x] 1.4 Move `cron-daily-triage` and `cron-follow-through-monitor` onto `spawnClaudeEval`: destructure `runId`/`attempt`, pass the current cwd as `spawnCwd`, drop the duplicate `--strict-mcp-config`, and update their tests, naming each changed assertion.
- [x] 1.5 Go green; run the full `test/server/inngest` suite.
- [x] 1.6 N/A — Branch A (A-wrap) chosen; see ADR-243. Branch B only: implement Fix 1B exactly as the plan specifies (step id `claude-eval` kept, dedup for the same cron, slot-based poll counting, envelope file in the run's workspace, GC skip, monitor margins, state logs).

## Phase 2 — Fix 4 telemetry

- [x] 2.1 Add `is_error`, `subtype` and `num_turns` to the cost marker (additive; no `CaptureStatus` widening; no result or error text); unit test on a synthesized result line.
- [x] 2.2 Fix the ranked-spend SQL in `runbooks/betterstack-log-query.md` to `JSONExtractFloat(raw,'message','cost_usd')` (`cost_usd` is populated; the old path read the wrong JSON level).

## Phase 3 — Fix 3 budget cap

- [x] 3.1 Verify `--max-budget-usd` and its budget-stop `subtype` on `@anthropic-ai/claude-code@2.1.219`; bump the pin in `package.json` and `Dockerfile` together if needed.
- [x] 3.2 Derive each of the 18 sites' cap from the markers' `cost_usd` (`max(3 × median, re-priced for Opus 5.5, $2)`), plus the worst-case-daily column and the manual-trigger row.
- [x] 3.3 Add `--max-budget-usd` to all 18 spawn sites and a `throttle` (2/hour per function) to each claude-eval function, or record in the ADR that the server ignores `throttle`.

## Phase 4 — Fix 2 model re-pin (subsumed: #8601 made the same change on main; this branch took main's version at merge)

- [x] 4.1 Verify `claude-opus-5-5` with `GET /v1/models/claude-opus-5-5`.
- [x] 4.2 Set `AUDIT_MODEL = "claude-opus-5-5"`; update `model-tiers.test.ts` and the header comments.
- [x] 4.3 `git grep -nE 'claude-opus-5([^-.]|$)' -- apps/web-platform` returns nothing.

## Phase 5 — Alerts, ADR, C4, ledger

- [x] 5.1 Add the 524 (plus the S7 literal), burn ($15/day, nested path, `"SOLEUR_CLAUDE_COST":true` key match, `cron:` sources) and stuck-at-zero explorations and alerts to `betterstack-logs-alerts.tf`. Aggregates only; no `PRIORITY` filter; confirm the 86400 `query_period`.
- [x] 5.2 (no edge rule added; ADR-243 Consequences records the accepted exposure) Add `-target=` lines for every new resource to `apply-web-platform-infra.yml`; reconcile every other `logtail_exploration` consumer; add the Cloudflare edge rule only if the custom-rule quota allows.
- [x] 5.3 Write `test/infra/inngest-step-524-alert.test.sh` (Guard 2 rows 1–6); register it in `infra-validation.yml`; `terraform validate`; add `scripts/probe-inngest-524-count.sh` (prints `count=<n>`).
- [x] 5.4 Write ADR-243 (re-verify the ordinal across all `origin/*` refs) and amend ADR-033, covering the spike result, alternatives, streaming contract, single-flight (AP-013), cap table, throttle and alert thresholds.
- [x] 5.5 Fix the C4 edge in `model.c4`, regenerate `model.likec4.json`, and run the five C4 tests.
- [x] 5.6 Update `knowledge-base/operations/expenses.md` and `knowledge-base/finance/cost-model.md` with the `cost_usd`-derived funded-day figure (~$17/day, ~$516/month pre-fix).
- [ ] 5.7 CPO sign-off recorded (approved with conditions); confirm S7/S8 results satisfy it.

## Phase 6 — Post-merge check (in `soleur:ship`, once credit is present)

- [ ] 6.1 Fire cron-seo-aeo-audit, cron-community-monitor, cron-architecture-diagram-sync and cron-compound-promote via `soleur:trigger-cron`; run one BYOK leader-loop turn with a tool call on the operator's own founder account (one `leader-loop` marker per turn, sum = `cumulativeCents`); watch one email-triage run.
- [ ] 6.3 Arm the 72h rollback trigger: a duplicate leader-loop marker, `persist-failure anthropic_timeout`, or a `turn-*-claude` attempt > 0 means revert `streaming`, plus a notice and refund to the affected founder.
- [ ] 6.2 From Better Stack: one cost marker per run id, zero 524s, one attempt per run, and a committed PR/issue per cron.
