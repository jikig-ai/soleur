---
title: "fix: stop Cloudflare-524 double-runs of claude-eval crons and cut operator Anthropic spend"
type: fix
date: 2026-09-23
slug: fix-anthropic-spend-cron-524-double-run
branch: feat-anthropic-spend-reduction
pr: 8611
lane: cross-domain
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: stop Cloudflare-524 double-runs of claude-eval crons and cut operator Anthropic spend

## Enhancement Summary

**Deepened on:** 2026-09-23. **Lenses:** architecture-strategist, observability-coverage-reviewer,
security-sentinel, a verify-the-negative claims sweep, and mechanical gates 4.5–4.11. The broad
40-agent sweep was scaled down: the plan had already passed seven reviewers (CTO, CFO, DHH, Kieran,
code-simplicity, CTO-devex, a strong-model consult), and further lenses would mostly repeat them.

1. **Cost numbers corrected from the CLI's own `cost_usd`.** It is $159.81 over 30 days, not $107.85.
   Duplicates are 51%. The run-rate is ~$516/month, falling to ~$208/month after the fix. An earlier
   claim that `cost_usd` was null was a query-path error.
2. **The spike now proves failure semantics, not just success**: retry-after-error, non-retriable,
   multi-step with sleep, a cut stream, and a 70-minute step. It runs on the real custom server with
   gzip, under a mandatory key-hygiene Safety list.
3. **Brand-survival threshold raised to `single-user incident`.** Fix 1A also changes transport for the
   Concierge BYOK leader loop, where a misread streamed error could double-bill a founder's key.
4. **Streaming answers unsigned POSTs with 201 before verifying.** The signature tests are rewritten
   around the envelope, and an edge rule is added if the quota allows.
5. **Alerts corrected**: nested JSON path, `_DAILY` rows excluded, a separate stuck-at-zero alert,
   aggregate-only selects, and no `PRIORITY` filter. The throttle and the manual-trigger row close the
   gap per-run caps leave.
6. ADR ordinal is **241**: 238–240 are claimed on pushed branches.

## Overview

The operator Anthropic key's credit runs out far faster than the work it buys. A $50 top-up at
about 2026-09-19 20:00 UTC was gone by 2026-09-21 11:05 UTC, roughly 39 hours. The key has been
exhausted since then, so every claude-eval cron is currently failing.

The measured root cause is not prompt caching. It is a transport defect. The Inngest server runs
each function step by calling the registered serve URL `https://app.soleur.ai/api/inngest`, which
is Cloudflare-proxied. Cloudflare closes any origin request that has not answered within about 100
seconds, with HTTP 524. The claude-eval step holds its request open for 5 to 25 minutes, so:

1. The first attempt gets a 524 about 2 minutes in, while the Claude session is still running.
2. Inngest retries the step (`retries: 1`), which starts a **second, concurrent, paid Claude
   session**, because the first attempt's result was never memoized.
3. The retry also gets a 524, and Inngest marks the run failed (`inngest/function.failed`).
4. The later steps (`verify-output`, `safe-commit-pr`) never run, so neither session's output is
   committed.

This plan fixes that, re-pins the audit model tier from Opus 5 to the cheaper Opus 5.5, adds a
per-run dollar ceiling and a manual-trigger throttle, and adds the alerts that would have caught
the drain. It deliberately does
**not** add prompt caching to the direct Messages API callers. The measurement below shows it would
cost more than it saves (see Research Reconciliation).

## Research Reconciliation — Spec vs. Codebase

| Claim in the request | Reality (measured) | Plan response |
|---|---|---|
| "Duplicate sessions, hypothesis: HTTP request timeout" | Confirmed. inngest-server logged `error handling queue item … invalid status code: 524` (2026-09-18 08:02:38), then `inngest/function.failed` for run `01M2SRF3AT19V9WZZHNC9MY5YP` at 08:05:10 while both children were still running (they ended 08:07:36 and 08:09:23). | Fix 1 moves the long work out of the step request. |
| "~40% of spend is duplicate" | 51% of metered claude-eval spend over 30 days ($82.04 of $159.81, from the markers' own `cost_usd`). And 24 of 33 spending runs were marked failed, so most of the other half produced no committed output either. | Fix 1 is the priority. |
| "Add cache_control to compound-promote (537k uncached tokens)" | It runs once a week, one call per run. The extra runs on 2026-09-19/20 were **manual** triggers (outcome markers: `trigger=manual`), hours apart, beyond even the 1h cache TTL. A single call with a cache write pays 1.25x on input and gets no read back. | **Cut** (see Cut List). |
| "domain-router / email-triage likely below minimum cacheable length" | Confirmed. Their stable prefixes are about 611 and 624 chars (~150–160 tokens) against Haiku 4.5's 4,096-token minimum. | **Cut.** |
| "Cost markers report ok with 0 tokens on exhausted credit" | Half right. `resolveEvalCaptureStatus` returns `"ok"` for any parsed result event, including an `is_error` one. But `cost_usd` **is** populated on every claude-eval marker (118/118); an earlier draft claimed it was null because it read the wrong JSON path (fields nest under `raw.message` since #8344). | Fix 4: add `is_error`/`subtype`/`num_turns`; fix the runbook query path. |
| C4 edge `api -> inngest "Sends events; serves functions" (HTTP private-net :8288)` | Execution is the reverse direction and goes through Cloudflare: inngest -> `https://app.soleur.ai/api/inngest` (serveHost, route.ts #5159), `app` DNS record `proxied = true` (dns.tf). | C4 correction is in scope. |

## Research Insights

**Premise Validation.** No `#N` refs cited. Every mechanism claim was checked against live data or
`origin/main`. Cost/time series: Better Stack `SOLEUR_CLAUDE_COST` + `SOLEUR_CRON_FILING_DENY`
markers (ClickHouse via `scripts/betterstack-query.sh`, Doppler `prd_terraform`), 30-day window,
350 deduplicated markers. Credit exhaustion windows: `credit balance is too low` rows per day
(exhausted 2026-08-24 → 09-10 15:47, again 09-18 09:03 → 09-19 20:02, and since 09-21 11:05). The
524 series starts in the week of 2026-09-06, which is when credit returned. Before that, runs failed
in seconds on the credit error and never reached 100s. The run IDs of paired sessions match, and the
`spawn_started_at` pairs are 2.5–4.7 minutes apart with overlapping lifetimes (e.g. growth-audit
2026-09-21: 07:00:37→07:18:50 and 07:03:07→07:20:13).

**Property List (Phase 0.6b).**

- P1. A cron run starts at most one Claude session per logical eval step.
- P2. A cron run whose Claude session succeeds reaches its later steps (verify, commit/PR).
- P3. No Inngest step request runs longer than Cloudflare's origin timeout.
- P4. Cron sessions on the audit tier bill at the cheapest model in that tier.
- P5. A single runaway session cannot spend more than a bounded amount.
- P6. A run that failed on an API error is visible as a failure in cost telemetry, and per-run cost
  is recorded.
- P7. A future step that exceeds the proxy timeout pages instead of silently double-spending.

**Cut List.**

- `cache_control` on `postAnthropicMessage` (compound-promote, weekly-release-digest) → buys P-none:
  single call per run, no reuse inside the TTL; it adds a 1.25x cache-write surcharge. Cut.
- `cache_control` on domain-router / email-triage → prefixes ~150 tokens, below Haiku's 4,096 minimum;
  the API would ignore it. Cut.
- Inngest SDK `streaming: "force"` → buys P3 with no new mechanism. v1 rejected it untested; plan review
  moved it to a Phase 0 spike that decides between Fix 1A (streaming) and Fix 1B (detach-and-poll).
- Re-pointing `serveHost` at the private network → buys P3, but changes the app's registered URL
  identity on the Inngest server (risk of a lingering public-URL app still planning crons = real
  double-fire), and would need TLS/origin work. Rejected (Alternatives).
- A separate single-flight table in Postgres → P1 is buyable in-process, because all steps reach the
  single active web host (web-2 is weight 0, ADR-143). This is recorded as a constraint in the ADR instead.

**Value measurement (Phase 0.6c).** Command: the `jq` aggregation over the 30-day marker export
(pricing from platform.claude.com/docs/en/about-claude/pricing, fetched 2026-09-23: Opus 5 $5/$6.25/
$0.50/$25, Opus 5.5 $4/$5/$0.20/$20, Sonnet 5 $2/$2.50/$0.20/$10 per MTok in/5m-write/read/out).
Authoritative figures come from the markers' own `cost_usd`, which is the CLI's `total_cost_usd`
and includes sub-agent spend. An earlier token-derived estimate ($107.85) undercounted by about a third.

- Metered claude-eval spend was **$159.81** over the 30-day window, of which duplicate sessions were
  **$82.04 (51%)**.
- Keeping one session per run and re-pricing audit-tier runs at Opus 5.5 gives about **$64.47
  (−60%)** for the same window. The re-pricing scales each Opus 5 run's `cost_usd` by the
  Opus 5.5 / Opus 5 token-price ratio of that run.
- The key had credit for only ~9.3 of those 30 days (2026-09-10 16:00 → 09-18 09:03 and 09-19 20:00
  → 09-21 11:05). The real run-rate is therefore **~$17/day, about $516/month**, falling to
  **~$7/day, about $208/month**, after Fixes 1–2.
- Value per dollar matters more: today ~73% of paid runs (24/33) commit nothing.
- The exhausted $50 window (2026-09-19 20:00 → 09-21 11:05) shows **$42.56** of metered spend. The rest
  went to `cron-daily-triage` and `cron-follow-through-monitor`, which spawn Claude inline and emit no
  cost marker, and to small direct-API calls.
- Caveats: re-measure the Opus 5.5 token use over the first 7 funded days. The two newly metered crons
  are new visibility, not a regression, so report them as their own line.

**Relevant files.**

- `apps/web-platform/app/api/inngest/route.ts` — `serve()`, `serveHost` pin (#5159 rationale), no `streaming`.
- `apps/web-platform/infra/dns.tf` — `cloudflare_record.app`, `proxied = true`.
- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — `spawnClaudeEval`,
  `SpawnResult`, `resolveEvalCaptureStatus`, `parseClaudeResultLine`, cost marker emit.
- 16 `spawnClaudeEval` call sites, each `step.run("claude-eval", …)`: cron-agent-native-audit,
  -architecture-diagram-sync, -bug-fixer, -campaign-calendar, -community-monitor,
  -competitive-analysis, -content-generator, -growth-audit, -growth-execution, -legal-audit,
  -roadmap-review, -seo-aeo-audit, -ux-audit, event-ship-merge, oneshot-f2-defer-gate-review,
  oneshot-recheck-4217-calibration. Plus 2 inline spawns: cron-daily-triage (`--max-turns 80`),
  cron-follow-through-monitor (`--max-turns 30`).
- `apps/web-platform/server/inngest/model-tiers.ts:46` — `AUDIT_MODEL = "claude-opus-5"`; comment:
  "Same-tier re-pins land here since"; re-tiering across tiers is ADR-053 clo-attestation class.
- `apps/web-platform/test/server/inngest/model-tiers.test.ts:157` — pins the literal.
- `apps/web-platform/infra/betterstack-logs-alerts.tf` — `logtail_exploration(_alert)` precedent (ADR-218).
- `apps/web-platform/infra/inngest-host.tf` ~L348 — `sdk_url = http://10.0.1.10:3000/api/inngest` (sync only).

**Institutional learnings.**

- `2026-03-21-async-webhook-deploy-cloudflare-timeout.md` — the same Cloudflare ceiling on a deploy
  webhook, fixed by start-then-poll. This plan applies that pattern to Inngest steps.
- `2026-06-11-restart-recovery-push-driven-not-poll-driven.md` and the #5159 route.ts comments — why
  `serveHost` is the public origin; do not touch it here.
- `2026-03-20-claude-code-action-max-turns-budget.md` — turn budgets carry ~10 turns of plugin overhead;
  do not cut `--max-turns` blind (deferred to measured data, see Deferrals).
- `2026-02-22-model-id-update-patterns.md` — grep every literal, verify the ID live, re-grep after edit.

**External.** Inngest SDK 3.54.2 `streaming` option: `"allow"` is a no-op on a non-Vercel Node host,
and `"force"` is honored by the Next.js adapter (`node_modules/inngest/types.d.ts` ~L905–926,
`helpers/stream.js` whitespace heartbeat). Self-hosted server support for streamed responses is
undocumented. Cloudflare 524 docs: origin must answer within the proxy timeout. Anthropic caching
minimums: 512 tokens (Sonnet 5, Opus 5.5), 4,096 (Haiku 4.5). `claude --help` 2.1.280 lists
`--max-budget-usd`; the container pins `@anthropic-ai/claude-code@2.1.219`, so the flag must be
re-verified against that version (Phase 3 task).

**Functional overlap.** No community artifact covers the Inngest/Cloudflare fix; caching/pricing
guidance is already covered by the built-in `claude-api` skill. Nothing installed.

## Proposed Solution

### Fix 1 — Keep one Claude session per run and let it reach its commit step (P1, P2, P3)

**Phase 0 is a spike, and its result picks the branch.** Plan review found that the detach-and-poll
design (v1 of this plan) carried at least nine correctness defects once sleeping runs replaced
running ones. Among them: workspace GC deleting live workspaces, queued runs exhausting their poll
budget, a lost run reported to Sentry on every replay, false Sentry cron-monitor misses, lost Inngest
concurrency limits, and three existing tests that assert step ids. Every one of these exists
only because the run sleeps. The streaming alternative keeps the step a single request, and v1
rejected it on an untested guess. Test it first.

#### Phase 0 — streaming spike (local, about half a day)

Reproduce the production path on a workstation as closely as possible:

- the pinned server, `inngest start` **v1.19.4** (release binary, same flags as `inngest-host.tf`
  **except the keys**, see Safety below);
- the app's **own** `apps/web-platform/server/index.ts` custom server and Next 16 router server (not a
  toy app), with `serve({ …, streaming: "force" })` and a spike-only function set registered in place
  of the production list. Requests carry `Accept-Encoding: gzip`, and the spike records whether the
  streamed response is compressed and whether the heartbeat bytes still arrive in time;
- a **Cloudflare quick tunnel** (`cloudflared tunnel --url http://127.0.0.1:3000`) as the serve URL, so
  requests cross a real Cloudflare proxy. Production uses a proxied A record rather than a tunnel;
  the ADR records that difference and Phase 6 closes it on the real edge.

**Safety (mandatory, from the security review).**

- Throwaway keys only: `signkey-test-$(openssl rand -hex 32)` and a random event key. Never
  `doppler run`; start both processes under `env -i` with an explicit minimal env and `INNGEST_DEV=0`.
- Bind the app and `inngest start` to 127.0.0.1. Stop the tunnel with `trap 'kill $CF_PID' EXIT`.
- The spike function set imports nothing that reads production secrets.
- Before recording results, send one unsigned POST through the tunnel and confirm the streamed
  envelope reports 401 and that no function ran.
- `streaming-spike.md` must not contain the tunnel hostname or either key.

Rows. Run each three times:

| # | Function | Pass condition |
|---|---|---|
| S1 | one 2s step | completes, one attempt |
| S2 | one 3-minute step | completes, one attempt, no `invalid status code: 524` |
| S3 | one 70-minute step (the largest `MAX_TURN_DURATION_MS`, cron-growth-audit) | completes, one attempt, no 524 |
| S4 | step throws a plain `Error` on attempt 1, succeeds on attempt 2 (`retries: 1`) | the server schedules attempt 2 (a streamed error is read as an error, not as success) |
| S5 | step throws `NonRetriableError` | the run fails with no retry |
| S6 | two steps with a `step.sleep("1m")` between (the shape of event-scheduled-reminder) | both steps run, in order, once |
| S7 | a 3-minute step whose stream is cut mid-way (kill the app process), run with `retries: 1` and again with `retries: 3` | record the exact inngest-server error text (it becomes a second alert literal, Fix 4) and **how many times the cut step re-runs** (the ADR records that as the BYOK exposure to a deploy or network drop mid-turn) |
| S8 | the real leader-loop shape (`agent-on-spawn-requested.ts`): ≥ 3 sequential `step.run`s (`cap-check` → `claude` → `tool-0`), `retries: 3`, `timeouts.finish: "10m"`; step 3 throws on attempt 1 | steps 1–2 are **not** re-executed on the retry (memoized), step 3 runs twice, and the run completes. A re-executed `claude` step means a founder is billed twice → Branch B for streaming |

Also record: whether `"allow"` streams on this host (expected: no), the heartbeat interval, whether the
server accepts the response signature carried in the streamed body, and the server's log lines for
each row. Write it all to `knowledge-base/project/specs/feat-anthropic-spend-reduction/streaming-spike.md`
and commit it before Phase 1. The ADR cites it.

- **Branch A: S1–S6 and S8 pass in all three runs.** Implement Fix 1A.
- **Branch B: any of S1–S6 or S8 fails.** Implement Fix 1B. If only S3 fails and S2 passes, record the
  longest passing duration. Branch A remains possible with every `MAX_TURN_DURATION_MS` capped below it;
  decide by comparing that cap with the measured session durations.

#### Fix 1A — SDK streaming plus an in-process single-flight guard

1. `apps/web-platform/app/api/inngest/route.ts`: add `streaming: "force"` to `serve()`, with a
   comment citing the spike file and ADR-243. `serveHost` is unchanged.
   - Streaming answers every POST with HTTP 201 and the SDK headers before signature verification;
     the 401 moves into the streamed body (`InngestCommHandler.js`, `createStream` branch). Signing
     is still enforced.
   - Update the four `res.status === 401` assertions in `test/server/inngest/signature-verify.test.ts`
     to read the stream, parse the final envelope, assert `status === 401`, and assert no function ran.
     Never turn streaming off in the test to keep it green.
2. **Single-flight inside `spawnClaudeEval`**, so every caller is covered without touching its call
   site. Streaming removes the systematic retry, but a genuine mid-stream failure can still trigger
   one while the first child lives. The guard is a process-wide map keyed `${cronName}:${runId}`, on
   `globalThis[Symbol.for("soleur.claudeEvalInFlight")]`. The app ships two bundles, so a module-level
   `Map` is not guaranteed to be a single instance. This is process-local state (AP-013); the ADR
   records why that is acceptable here.
   - The entry is set synchronously before the first `await`. A retry that finds an entry **awaits
     the existing child's promise** instead of spawning.
   - The entry is removed in a `finally`, so spawn failures (ENOENT), timeout aborts and rejections
     all clear it.
   - `runId` must match the Inngest ULID shape `^01[0-9A-HJKMNP-TV-Z]{24}$`. Otherwise the guard is
     skipped, not keyed on `undefined`, and `reportSilentFallback(op="claude-eval-singleflight-no-runid")`
     fires.
   - A hit reports `reportSilentFallback(op="claude-eval-singleflight-join")`.
   - No TTL, no file, no queue: Inngest concurrency still holds, because the step is still running.
3. **Route the two inline spawners through `spawnClaudeEval`.** This is not a drop-in change (architecture review):
   - Destructure `runId` and `attempt` from the handler args in `cronDailyTriageHandler` and
     `cronFollowThroughMonitorHandler`. They do not today, which would key both on `undefined`.
   - They run without an ephemeral workspace. Pass their current process cwd explicitly as
     `spawnCwd`, which preserves behavior.
   - Drop their own `--strict-mcp-config`, which the substrate already adds.
   - Accept the substrate's `--output-format json` and piped stdio (they use `stdio: "inherit"` today).
     Update `cron-daily-triage.test.ts` and `cron-follow-through-monitor.test.ts` to the new spawn
     args, and name each changed assertion in the PR.
   - This gives them the guard and the cost marker.
4. **Canary.** Streaming changes the transport for every function (~70), including
   `agent-on-spawn-requested` (the BYOK leader loop, `retries: 3`, user keys) and `email-on-received`.
   Phase 6 covers both.

#### Fix 1B — fallback, only if the spike fails

The detach-and-poll helper from plan v1, corrected by the review panel:

- `runDetachedEval(step, opts)` takes the spawn args, not a closure, and builds its key from function
  id + run id internally. `spawnClaudeEval` stops being exported, so the compiler enforces routing.
- Keep the start step id exactly `"claude-eval"` (`cron-cohort-dedup.test.ts:487`,
  `cron-daily-triage.test.ts:170` and `cron-follow-through-monitor.test.ts:245` pin it). Polls are
  `claude-eval-wait-i` / `claude-eval-poll-i`. No inline wait: the start step returns `pending`
  and the first sleep is about 20s.
- The registry lives on `globalThis` and has one per-process slot (preserving `cron-platform`
  limit:1). A same-cron second run returns `deduped` and exits through the cron's existing dedup
  early-return; only a different cron queues. The poll count starts when the slot is acquired, and a
  separate queue-wait ceiling ends in a `queued-timeout` envelope. The entry carries an
  AbortController, so a terminal `timeout` aborts the child. Total steps stay well under 1000.
- The poll never throws. Envelopes are `ok | error | pending | queued | lost | deduped | timeout`, and
  settled entries are never deleted on read. The settled envelope is also written atomically inside
  the run's own mkdtemp workspace (on the host-mounted `/workspaces`, `CRON_WORKSPACE_ROOT`), so it
  survives the deploy drain's container swap. The existing workspace GC sweeps it.
- `cron-workspace-gc` must skip workspaces whose run has a live registry entry, and its max age must
  exceed the longest `MAX_TURN_DURATION_MS` plus queue and poll slack. Today the shared
  `cron-platform` limit stops GC running during a claude-eval step; sleeping runs lose that.
- `lost` is reported to Sentry from inside the poll step that first observes it (memoized, so it
  reports once). The function body rethrows `error` envelopes as a plain `Error` with the original
  `name`/`message`; `DeployInProgressError` originates at setup-workspace and is untouched.
- Operator visibility: one log line per state change (`start / queued / slot-acquired / settled /
  lost / timeout`) keyed by run id, a Sentry `reason` tag, and `cron-monitors.tf` check-in margins
  widened (or an `in_progress` check-in on slot acquisition) so queued runs do not page.

Fix 1B stays in this plan as a contingency. Its full test battery is written only if Branch B is taken.

### Fix 2 — Same-tier re-pin of the audit model (P4)

`AUDIT_MODEL`: `"claude-opus-5"` → `"claude-opus-5-5"`. This is a same-tier re-pin, which
`model-tiers.ts` permits; cross-tier moves stay out of scope per ADR-053. It covers the six audit
crons. Before editing, verify the ID with `GET /v1/models/claude-opus-5-5`. Update
`model-tiers.test.ts:157` and every unquoted mention: the `--model claude-opus-5` header comments in
agent-native-audit, legal-audit, competitive-analysis and growth-audit, plus the `model-tiers.ts`
comments.

### Fix 3 — Per-run dollar ceiling and a manual-trigger throttle (P5)

- Add `--max-budget-usd <cap>` to all **18** Claude spawn sites' flags, named individually in the ADR
  table. That is the 13 cron-* functions, the 2 migrated inline spawners, event-ship-merge and the 2
  oneshot functions.
  - First confirm `@anthropic-ai/claude-code@2.1.219` supports the flag
    (`npx -y @anthropic-ai/claude-code@2.1.219 --help`), and take the exact budget-stop `subtype`
    string from that version. If the flag is missing, bump the pin in `package.json` and the
    `Dockerfile` together (KEEP IN SYNC).
  - Cap per site: `max(3 × 30-day median cost_usd per session, re-priced for Opus 5.5 where
    applicable, $2)`, taken from the markers' own `cost_usd`.
- The ADR table carries a worst-case-daily column (cap × scheduled runs per day, summed). It also
  carries a **manual-trigger row**: each `soleur:trigger-cron` fire is a new run with a fresh cap, which
  is how the 2026-09-19/20 extra runs happened.
- Bound manual fires with an Inngest `throttle` on every claude-eval function (limit 2 per hour, key per
  function). Verify the pinned server honors `throttle` by registering a throttled spike function in
  Phase 0. If it does not, record that in the ADR and rely on the burn alert.

### Fix 4 — Telemetry, query paths and alerts (P6, P7)

- **The cost figure is already captured.** Deepen-pass correction: `cost_usd` is populated on every
  claude-eval marker (118/118 in the 30-day export; nulls are only the credit-probe and compound-promote
  HTTP markers). What is broken is the **query path**. Since #8344 pino fields sit under `raw.message`,
  so a top-level `JSONExtractFloat(raw,'cost_usd')` reads 0. Fix the ranked-spend SQL in
  `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` to the nested path
  `JSONExtractFloat(raw,'message','cost_usd')`.
- Cost marker: add `is_error`, `subtype` and `num_turns` from the CLI result event. They are additive,
  so `CaptureStatus` does not widen, and they carry no result or error text.
- **524 alert** (ADR-218 pattern): an exploration counting inngest-server rows containing
  `invalid status code: 524`, alerting at > 0 per 15 min. The query must not filter on `PRIORITY`:
  the live lines are `PRIORITY 6`, and they ship because the `inngest_journald` source forwards all
  priorities for that unit (observed). The spike's S7 stream-cut error text becomes a second literal
  in the same exploration.
- **Daily burn alert** (operator decision 2026-09-23; addresses open #5692):
  - An exploration computing `sum(JSONExtractFloat(raw,'message','cost_usd'))` over rows with
    `raw LIKE '%"SOLEUR_CLAUDE_COST":true%'` and `JSONExtractString(raw,'message','source') LIKE 'cron:%'`,
    per 24h bucket. The explicit `:true` key match keeps the `SOLEUR_CLAUDE_COST_DAILY` org-total rows
    out of the sum.
  - The alert pages above **$15/day**, about 2× the post-fix funded-day rate of ≈$7. Recalibrate after
    14 funded days.
  - A **separate** stuck-at-zero exploration and alert fires when the 24h count of cron markers with a
    non-null `cost_usd` is 0. Its sibling alerts use `on_missing_data = "treat_as_zero"`, so a single
    `higher_than` rule could never fire on silence. Suppress it while the credit probe is RED: a
    zero-spend day with no credit is legitimate. If the logtail provider cannot express that
    condition, the ADR records that the page is expected during exhaustion.
  - Confirm the provider accepts a `query_period` of 86400; the sibling alerts go up to 5400 at most.
    If it does not, use the largest accepted window and scale the threshold to it.
  - Every exploration selects **aggregates only** (`countIf`, `sum`), with no raw message column and
    no grouping on free text. The inngest-server line can carry queue-item payloads (email data), and
    the Cloudflare 524 page carries an IP.
  - At ship, `Closes #5692` only if its acceptance criteria are met; otherwise `Ref #5692`.
- **Edge rule (conditional).** If the zone's custom-rule quota allows, add a Cloudflare custom rule
  (Terraform) that blocks POST `/api/inngest` without an `x-inngest-signature` header. Streaming
  otherwise returns 201 and the SDK version headers to unsigned callers. If there is no quota, the ADR
  records the accepted exposure (a version string, no function execution).
- **Expense ledger.** `knowledge-base/operations/expenses.md` "Anthropic API (claude-eval cron fleet)"
  row: replace `0.00 unmetered` with the measured funded-day run-rate from `cost_usd` (~$17/day,
  ~$516/month pre-fix), model `claude-opus-5-5`, 18 spawn sites, a fresh `verify_by`. Mirror it in
  `knowledge-base/finance/cost-model.md` and re-derive the cron-ux-audit $15 row from markers.

**Cut by review:** routing compound-promote's `anthropic-cluster` through a helper (no measured 524;
under 1A streaming covers it anyway, and the alert watches it), and the 7-day soak probe (replaced by
the Phase 6 check plus the permanent 524 alert). **Cut by operator decision (2026-09-23):** prompt
caching on the direct Messages API callers (see Research Reconciliation).

### Architecture record

- **ADR-243** (ordinal provisional; ADR-238–242 are already claimed on pushed branches). Re-verify
  across all `origin/*` refs before merge. Title: "Inngest step requests cross the Cloudflare proxy;
  long steps must stream or detach". Contents:
  - the evidence, the spike result and the chosen branch;
  - the rejected alternatives: private `serveHost`, `waitForEvent`, Inngest Connect (switches every
    function's transport; self-hosted support unverified), and a Cloudflare timeout increase
    (Enterprise only);
  - the streaming contract: 201 + body envelope, the signature in the body, the test rewrite, the
    edge rule or the accepted exposure;
  - the single-flight contract, and why process-local state (AP-013) is acceptable while a single
    host executes steps;
  - the budget-cap table (18 sites, the worst-case-daily column, the manual-trigger row), the
    throttle, and the burn-alert thresholds;
  - amendments to **ADR-033**, which assumes the child lives inside one `step.run` request, and a
    note on **ADR-030**'s signing assumptions under streaming.
  - Under 1B it also records the per-host constraint, the in-process concurrency contract, and the
    fact that non-Claude `cron-platform` functions can now run beside a live child.
- **C4:** in `model.c4`, narrow the `api -> inngest` edge to event sending and add
  `inngest -> api "Invokes function steps at the registered serve URL (Cloudflare-proxied, ~100s origin timeout)"`.
  Regenerate `model.likec4.json`, which mirrors the edge title.

### Network-Outage Deep-Dive (deepen-plan 4.5)

The 4.5 gate fires on "timeout" and 524. Layer-by-layer status, with the evidence that settles each:

| Layer | Status | Evidence |
|---|---|---|
| L3 firewall allow-list | Not implicated. A 524 means Cloudflare **connected** to the origin and waited; a firewall drop surfaces as 521/522. | inngest-server log `invalid status code: 524` (2026-09-18 08:02:38, source 2457081); the same runs' first attempts reached the SDK and spawned children (paired `spawn_started_at`). |
| L3 DNS/routing | Not implicated. `app` resolves to the Cloudflare-proxied record, as designed. | `apps/web-platform/infra/dns.tf` `cloudflare_record.app` `proxied = true`. |
| L7 TLS/proxy | **Root cause.** Cloudflare's origin timeout on a proxied record (~100s, non-Enterprise) ends step requests that hold for minutes. | The 524 series starts only once credit returned (week of 2026-09-06), when sessions first ran longer than 100s; 37 of the 55 weekly 524s fell in the week of 09-13, which had the most funded runs. |
| L7 application | Correct behavior under a broken transport: `retries: 1` re-invokes the unmemoized step. | `inngest/function.failed` for run `01M2SRF3AT19V9WZZHNC9MY5YP` at 08:05:10 while both children still ran. |

No SSH or firewall hypothesis is in play, so `hr-ssh-diagnosis-verify-firewall` has nothing to order.

## Alternative Approaches Considered

| Approach | Disposition |
|---|---|
| Detach-and-poll helper | Kept as Fix 1B, the fallback. Plan review found it expensive and defect-prone because runs sleep. |
| Pin `serveHost` to the private IP | Rejected. It changes the app's registered identity on the Inngest server, so a stale public-URL registration could keep planning crons (a real double-fire). It also conflicts with the #5159 recovery design. |
| `step.waitForEvent` on completion | Rejected. Events that arrive before the wait registers are not matched. |
| Inngest Connect (WebSocket worker) | Rejected. It switches every function's transport, and self-hosted v1.19.4 support is unverified. |
| Cloudflare timeout increase | Needs an Enterprise plan. |
| Prompt caching on direct API callers | Rejected with measurement: no reuse inside the TTL, and a 25% cache-write surcharge. |
| Audit crons to Sonnet 5 | A cross-tier change is ADR-053 clo-attestation class. Out of scope; Opus 5.5 captures most of the saving. |

## User-Brand Impact

- **If this lands broken, the user experiences:** the Concierge agent loop
  (`agent-on-spawn-requested`, `turn-${n}-claude` steps, `retries: 3`) is served by the same
  `/api/inngest` handler whose transport Fix 1A changes. If the pinned server misread a streamed error
  as success, a founder's agent turn would silently stop. If it misread success as an error, the turn
  would re-run and bill the founder's **own** API key (BYOK) twice. Email triage (`email-on-received`)
  and scheduled reminders share the risk. On the operator side, crons stop producing PRs/issues or
  keep double-spending.
- **If this leaks, the user's money is exposed via:** duplicate Claude turns billed to the founder's
  BYOK key through a misread retry. No data is exposed: step results keep today's shape, and under 1B
  the persisted envelope is the same bounded, redacted `SpawnResult` inside the run's own ephemeral
  workspace.
- **Brand-survival threshold:** `single-user incident`

Named, scoped side effects (review panel):

- **Email ingress probe delay (operator-facing):** the account-wide `cron-platform` concurrency slot
  is now held for a whole claude-eval run instead of released at the ~100 s 524, so the 06:00
  `cron-email-ingress-probe` can wait behind `cron-bug-fixer` for up to ~50 min. Delayed, never
  dropped or duplicated; statutory deadline reminders keep their schedule, a little later.
- **Routines UI (every signed-in founder):** live rows for `cron-daily-triage` and
  `cron-follow-through-monitor` now appear, because both write `routine_run_progress` through
  `spawnClaudeEval`. The table's SELECT is any-authenticated (ADR-077 single-operator assumption);
  the rows carry system ids only. Scoped out under ADR-077.
- **Email-triage notify duplicate (operator only):** a stream dropped after `notifyOfflineUser`
  returns re-runs that step once (`retries: 1`) and can send a second non-statutory ping. The owner
  is one fixed operator account, so no founder receives it. Scoped out.

Controls: spike rows S4–S6 prove retry, non-retry and multi-step semantics on the pinned server
before 1A can be chosen. Phase 6 exercises one BYOK leader-loop turn on the operator's own founder
account and one email-triage run. The rollback is one line (remove `streaming`). `requires_cpo_signoff: true`;
`soleur:engineering:review:user-impact-reviewer` runs at review.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_CLAUDE_COST marker per claude-eval run (cost_usd already populated; adds is_error/subtype/num_turns) plus the existing per-cron Sentry cron monitors"
  cadence: "per cron run"
  alert_target: "Sentry cron monitor miss -> operator email (existing)"
  configured_in: "apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts; apps/web-platform/infra/sentry/cron-monitors.tf"
error_reporting:
  destination: "Sentry web-platform project (SENTRY_DSN) via reportSilentFallback (layer: sentry-correlation); pino WARN+ to Better Stack source 2457081 via the app_container_warn_filter (layer: pino)"
  fail_loud: "inngest-server 'invalid status code: 524' or a dropped-stream literal -> Better Stack alert; missing runId or a key collision -> reportSilentFallback (error); a join -> warnSilentFallback"
failure_modes:
  - mode: "any step request exceeds the Cloudflare origin timeout"
    detection: "logtail_exploration_alert inngest_step_524 counting inngest-server rows whose message.error is 'invalid status code: 524' (layer: vector — Source 1 inngest_journald; PRIORITY 6 rows ship as observed, #6551, pinned by Guard 2)"
    alert_route: "Better Stack alert -> operator email"
  - mode: "a streamed response is cut or misparsed (streaming-specific)"
    detection: "the same exploration's two dropped-stream needles: S7 'error parsing stream: error reading response body' and S3 'Your server reset the connection while we were reading the reply' (layer: vector — Source 1)"
    alert_route: "Better Stack alert -> operator email"
  - mode: "a step stream's consumer disconnects (drop, deploy kill, unsigned caller abort)"
    detection: "warnSilentFallback op=inngest-stream-consumer-cancel, tags signed/fn (layer: pino, mirrored to Sentry at warning); drain errors op=inngest-stream-drain-error"
    alert_route: "Sentry, queryable (warning level, no page); the rate of signed:true events is the production drop rate"
  - mode: "stream-detach wrapper fails, so a dropped stream's leaked SDK heartbeat throws"
    detection: "server/crash-handlers.ts uncaughtException -> Sentry fatal + process exit (layer: sentry-correlation); the container restart is visible in the deploy/uptime monitors"
    alert_route: "Sentry fatal issue -> operator email"
  - mode: "a retry arrives while the first Claude child is live, or runId is missing, or two different spawns collide in one run"
    detection: "op=claude-eval-singleflight-join (warning) / op=claude-eval-singleflight-no-runid (error) / op=claude-eval-singleflight-key-collision (error) (layer: sentry-correlation)"
    alert_route: "join: Sentry, queryable; no-runid and key-collision: Sentry issue -> operator email on first seen"
  - mode: "per-run budget cap hit"
    detection: "cost marker is_error=true, subtype error_max_budget_usd (layer: vector — Source 3 SOLEUR_CLAUDE_COST); classifyEvalFatal budget-capped class turns the cron's Sentry monitor red with the reason (layer: Sentry monitor)"
    alert_route: "Sentry monitor miss/error -> operator email; per-cron cap_hits query in the runbook"
  - mode: "daily spend above threshold, or the cost stream goes silent"
    detection: "burn exploration sum(JSONExtractFloat(raw,'message','cost_usd')) > local.claude_cost_daily_burn_usd (25) per trailing 24h — a floor, null-cost markers count $0; separate capture-dark exploration on the count of non-null cost markers (layer: vector — Source 3)"
    alert_route: "Better Stack alert -> operator email"
  - mode: "credit exhausted"
    detection: "cron-anthropic-credit-probe (hourly, existing) + cost marker is_error=true (layer: Sentry monitor)"
    alert_route: "credit-probe Sentry monitor RED -> operator email (existing)"
  - mode: "a founder BYOK leader turn re-runs after billing (double bill)"
    detection: "leader-loop SOLEUR_CLAUDE_COST marker with attempt > 0, or two markers for one (id, turn) (layer: vector — Source 3)"
    alert_route: "72h rollback trigger (below) -> revert + founder notice/refund"
logs:
  where: "Better Stack Logs source 2457081 (soleur-inngest-vector-prd): app container pino WARN+ (markers nested under raw.message since #8344) and inngest-server journald"
  retention: "Better Stack source retention (hot + S3 archive via s3Cluster union)"
discoverability_test:
  command: "bash scripts/probe-inngest-524-count.sh"
  expected_output: "count=0"
  credentials_required: "Better Stack ClickHouse read connection (Doppler soleur/prd_terraform BETTERSTACK_QUERY_*) — the 524 line and the cost markers exist only in the log warehouse; no unauthenticated endpoint exposes inngest-server logs"
```

## Encryption Posture

```yaml
at_rest: []   # 1A adds no store. 1B's envelope file lives inside the run's existing ephemeral workspace on the existing /workspaces volume (already in the ledger); no new store
in_transit:
  - connection: "inngest server -> https://app.soleur.ai/api/inngest (existing, unchanged path; now streamed under 1A; documented in C4)"
    enforced_at: "apps/web-platform/app/api/inngest/route.ts serveHost (https scheme)"
    tls: "HTTPS to the Cloudflare edge (TLS 1.2+ per zone setting); Cloudflare -> origin per existing zone SSL mode"
    cert_verification: on
    does_not_defend: "Cloudflare itself (terminates TLS and sees step payloads); a compromised signing key (SDK HMAC is the auth)"
    disclosed_as: not-publicly-claimed
```

## Guard Contract

### Guard 1 — at most one live Claude child per (cron, run)

**Property.** For any `(cronName, runId)` with a well-formed `runId`, at most one Claude child process
is alive in the process, however many times Inngest re-invokes the step. A run without a well-formed
`runId` never joins another run's child.

**Assembly.** The single chokepoint is `spawnClaudeEval` in `_cron-claude-eval-substrate.ts`: the
`globalThis` in-flight map is checked, and its entry set, before the first `await`, and the entry is
cleared in a `finally`. Every Claude spawn flows through it once the two inline spawners are migrated.
What enforces that is a test asserting `resolveClaudeBin()` is called nowhere outside the substrate
file, not a hand-kept list.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Invoke `spawnClaudeEval` twice concurrently with the same key (the second arrives while the first child is live) | RED if the spawn spy counts 2; GREEN requires 1 spawn and both callers receiving the same result |
| 2 | REORDER: move the map `set` after the first `await` | RED (row 1 observes inside the window) |
| 3 | Add a new `resolveClaudeBin()` call in any `functions/*.ts` other than the substrate, as a second member after the compliant one | RED (the scan counts call sites across all files) |
| 4 | Guard dispatch: point the scan at a directory with zero `.ts` files | RED (the scan asserts it read ≥ 1 file and found the substrate's own call) |
| 5 | Same `runId`, different `cronName` | 2 spawns (distinct keys), GREEN |
| 6 | The first child rejects; then the same key is invoked again | 1 new spawn (entry cleared in `finally`), GREEN |
| 7 | `runId` is `undefined`, or not ULID-shaped, for two concurrent calls of the same cron | 2 spawns and 2 `singleflight-no-runid` reports, never a join (move the check after keying → RED) |
| 8 | The spawn throws ENOENT (missing binary), or the abort timer fires | entry cleared; a following call spawns (move the clear out of `finally` → RED) |

**Harness rows:** (H1) row 4 is the harness row: an empty scan must fail loudly, not pass on "0
checked". (H2) must-PASS: a fixture file that imports `spawnClaudeEval` and calls it (no raw
`resolveClaudeBin`) passes the scan.

**Anchor.** The scan derives its population from the directory at test time, and its only stored
expectation is "exactly one file, the substrate". A PR adding a raw spawn changes the tree and
reddens.

**Implementation revision (2026-09-23, CTO review of the spike; ADR-243).** The entry is no longer
cleared on settle. A **fulfilled** result stays for `SETTLED_TTL_MS` (15 min) so a retry whose stream
dropped after the child finished gets that result instead of a new session; a **rejection** is removed
at once. Row 6 therefore now expects **1** spawn (the retry receives the first result), and a new row 9
asserts a fresh spawn once the TTL has passed. Rows 1, 5, 7 and 8 are unchanged. Removing the retention
reds rows 6 and 9 (mutation run).

**Second implementation revision (2026-09-23, review panel; ADR-243 §2).** `SETTLED_TTL_MS` is now
**2 hours**: a dropped step's retry can queue behind another claude-eval cron on the account-wide
`cron-platform` concurrency slot for longer than 15 minutes. Row 10 pins the minimum. Rows 6 and 9
now cross a real macrotask / an async timer advance, so a retention dropped on a microtask reds them
(the earlier rows passed by timing). A second spawn in one run with a **different** prompt is refused
(row 11, op `claude-eval-singleflight-key-collision`). Rows 1 and 6 assert exactly one cost marker and
one `routine_run_progress` upsert per joined run. The join is reported at warning level.

### Guard 2 — every alert queries what its emitter writes, and nothing more

**Property.** Each of this plan's Better Stack explorations queries the literal or field path its
emitter actually writes, on the source that carries it, selects only aggregates, and is in the
auto-apply target list.

**Assembly.** Every `logtail_exploration` and `logtail_exploration_alert` added by this plan in
`betterstack-logs-alerts.tf` (discovered by iterating the file for this plan's names, not a fixed
count), the apply workflow's `-target=` list, and the observed emitter shapes:
`invalid status code: 524` (inngest-server, PRIORITY 6, source 2457081), the S7 literal, and the
`SOLEUR_CLAUDE_COST` marker nested under `raw.message`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change the 524 query literal | RED (pinned against a synthesized fixture of the observed log shape) |
| 2 | Point any exploration at a different source | RED |
| 3 | Remove any of the `-target=` lines for these resources from the apply workflow | RED (asserts every address is in the target list; otherwise the alert is never created) |
| 4 | Burn query reads top-level `cost_usd` instead of `raw.message.cost_usd`, or drops the `"SOLEUR_CLAUDE_COST":true` key match (would sum `_DAILY` rows) | RED (the test iterates every exploration, not just the first) |
| 5 | Add a raw message column or a free-text GROUP BY to any exploration's select list | RED (asserts aggregates only) |
| 6 | Add a `PRIORITY` filter to the 524 query | RED (the live 524 lines are PRIORITY 6) |

## Files to Edit

- `apps/web-platform/app/api/inngest/route.ts` (1A).
- `apps/web-platform/test/server/inngest/signature-verify.test.ts` (1A: 201 + envelope assertions).
- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — single-flight guard,
  marker fields, result-line parse.
- `apps/web-platform/server/inngest/functions/cron-daily-triage.ts` and
  `cron-follow-through-monitor.ts` — move onto `spawnClaudeEval`, destructure `runId`/`attempt`;
  their tests `test/server/inngest/cron-daily-triage.test.ts` and `cron-follow-through-monitor.test.ts`.
- `apps/web-platform/server/claude-cost-marker.ts` — additive fields.
- `apps/web-platform/server/inngest/model-tiers.ts` and its test; the four audit crons' header comments.
- All 18 spawn sites' flag arrays (`--max-budget-usd`) and function configs (`throttle`);
  `package.json` + `Dockerfile` only if the CLI pin must move.
- `apps/web-platform/infra/betterstack-logs-alerts.tf` (524, burn and stuck-at-zero explorations and
  alerts); the Cloudflare ruleset file only if the edge rule fits the quota.
- `.github/workflows/apply-web-platform-infra.yml` (`-target=` lines for every new resource).
- `.github/workflows/infra-validation.yml` (register the new infra test; CI lists suites by name).
- Every other logtail consumer from `git grep -ln logtail_exploration`, each reconciled:
  `scheduled-terraform-drift.yml`, `infra/main.tf`, `infra/variables.tf`,
  `plugins/soleur/lib/heartbeat-live-reconcile.ts`.
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (nested `cost_usd` path).
- `knowledge-base/engineering/architecture/decisions/ADR-243-*.md` (new), ADR-033 (amendment),
  `knowledge-base/engineering/architecture/diagrams/model.c4`, `model.likec4.json`.
- `knowledge-base/operations/expenses.md`, `knowledge-base/finance/cost-model.md`.
- Branch B only: `cron-workspace-gc.ts`, `sentry/cron-monitors.tf`, `test/server/inngest/cron-cohort-dedup.test.ts`,
  plus the 16 caller files.

## Files to Create

- `knowledge-base/project/specs/feat-anthropic-spend-reduction/streaming-spike.md` (Phase 0 evidence,
  with no tunnel hostname and no keys).
- `apps/web-platform/test/server/inngest/claude-eval-single-flight.test.ts` — Guard 1.
- `apps/web-platform/test/infra/inngest-step-524-alert.test.sh` — Guard 2 (precedent:
  `inngest-luks-wrong-volume-alert.test.sh`).
- `scripts/probe-inngest-524-count.sh` — wraps `betterstack-query.sh` and prints `count=<n>` for the
  last 24h, so the discoverability test needs no shell pipe.

## Implementation Phases

0. **Spike** (above, with its Safety list). Commit `streaming-spike.md`; pick the branch.
1. **Fix 1A** (or 1B): Guard 1 tests first (RED), then the guard, the `serve()` flag, the
   signature-verify test rewrite, and the two inline spawners moved over; go green. Run the full
   `test/server/inngest` suite.
2. **Fix 4 telemetry and query paths**: marker fields; runbook SQL to the nested path.
3. **Fix 3 budget cap and throttle**: verify the flag and its subtype on 2.1.219, derive the caps from
   `cost_usd`, add flags and throttles.
4. **Fix 2 model re-pin**: verify the ID live, edit, re-grep with the unquoted pattern.
5. **Alerts, ADR, C4, ledger**: Terraform explorations and alerts, `-target` lines and CI registration
   (Guard 2), the edge rule if it fits the quota, `probe-inngest-524-count.sh`, ADR-243 and the ADR-033
   amendment, C4 and its JSON mirror, expenses and cost model.
6. **Post-merge check (`soleur:ship`, once credit is present).** Via `soleur:trigger-cron`, fire:
   - cron-seo-aeo-audit (short);
   - cron-community-monitor (long);
   - cron-architecture-diagram-sync (audit tier: exercises the Opus 5.5 re-pin and the cap);
   - cron-compound-promote.

   Also run one BYOK leader-loop turn **that includes a tool call** on the operator's own founder
   account, and let one email-triage run happen naturally. For the leader turn, check the bill as
   well as the attempts: the `leader-loop` `SOLEUR_CLAUDE_COST` markers for that conversation must
   number exactly the turns the run executed (one per `turn`, every `attempt` 0). Comparing their sum
   to `cumulativeCents` proves nothing: both are written in the same step, so a re-run doubles them
   together. A duplicate turn marker, or `attempt > 0`, is a double bill. Then read Better Stack: exactly one cost marker per run id,
   zero 524s, one attempt per run (the leader turn included), and a committed PR or issue per cron.

**Rollback trigger (CPO condition, 72h after deploy, automated in `soleur:ship`'s follow-through).**
Any of the following means reverting the `streaming` line immediately, without waiting for triage.
Both read the fields #8611 added to the leader-loop `SOLEUR_CLAUDE_COST` marker (`turn`, `attempt`);
before them the marker's only correlation field was the conversation id, so a double bill looked
exactly like a real second turn:

- a `leader-loop` marker with `attempt > 0`;
- more than one `leader-loop` marker for the same (`id`, `turn`).

A web deploy that kills an in-flight leader turn also produces `attempt > 0`, and no pre-merge
baseline of leader-turn retries exists. So each hit is checked against the deploy log for that
minute: a hit that coincides with a deploy is recorded, not reverted. `persist-failure` with reason
`anthropic_timeout` is **not** a detector: a dropped stream completes the step (no persist failure),
and the classifier labels every unknown error `anthropic_timeout`. It stays a liveness signal only.

If it fires, the founder whose key was hit gets a direct notice and a refund of the duplicate spend.
Founders are not notified in advance, because no change is intended for them.

**Does merging this alone change production?** Yes, on two paths, and the PR body's first line must
say so. (a) `web-platform-release.yml` redeploys on any `apps/web-platform/**` change. Under 1A every
Inngest function streams from the next request, and every cron runs the new guard, model, caps and
throttle. (b) `apply-web-platform-infra.yml` fires on `apps/web-platform/infra/**` and creates the
Better Stack explorations and alerts (and the edge rule, if added) for the addresses in its `-target=`
list. No Terraform variable is added.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `streaming-spike.md` is committed with rows S1–S7 (three runs each for S1–S6), the Safety
      checklist ticked (including the unsigned-POST 401 check), and the chosen branch named. It contains
      no tunnel hostname or key. The implementation matches the branch.
- [ ] AC2: Guard 1 rows 1–8 plus H1 and H2 pass:
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/claude-eval-single-flight.test.ts`.
- [ ] AC3: `resolveClaudeBin()` is called only in `_cron-claude-eval-substrate.ts`.
      `cron-daily-triage` and `cron-follow-through-monitor` pass a ULID `runId` and emit the cost marker.
- [ ] AC4 (1A): `signature-verify.test.ts` asserts the 401 from the streamed envelope, and that no
      function ran, with streaming on.
- [ ] AC5: `AUDIT_MODEL === "claude-opus-5-5"`, the ID verified by `GET /v1/models/claude-opus-5-5`,
      and `git grep -nE 'claude-opus-5([^-.]|$)' -- apps/web-platform` returns nothing.
- [ ] AC6: all 18 spawn sites carry `--max-budget-usd` and a `throttle` matching the ADR table (or the
      ADR records that the server ignores `throttle`). The flag was verified on the pinned CLI, or the
      pin was bumped in both `package.json` and `Dockerfile`.
- [ ] AC7: the cost marker carries `is_error`, `subtype` and `num_turns` (unit test on a synthesized
      result line using the verified budget-stop subtype). The runbook's ranked-spend SQL uses
      `JSONExtractFloat(raw,'message','cost_usd')`.
- [ ] AC8: the 524, burn and stuck-at-zero explorations and alerts exist, every new address is in the
      apply workflow's `-target=` list, `inngest-step-524-alert.test.sh` (Guard 2 rows 1–6) is
      registered in `infra-validation.yml` and green, and `terraform validate` is green.
- [ ] AC9: ADR-243 (or the re-verified ordinal) and the ADR-033 amendment are committed. The C4 edge
      and `model.likec4.json` are updated. `c4-code-syntax.test.ts`, `c4-render.test.ts`,
      `c4-canonical-mirror.test.ts`, `plugins/soleur/test/c4-canonical.test.ts` and
      `plugins/soleur/test/c4-count-parity.test.sh` are green.
- [ ] AC10: `expenses.md` no longer reads `unmetered` for the claude-eval fleet. It carries the
      `cost_usd`-derived figure, names `claude-opus-5-5` and 18 spawn sites, and cites the query.
      `cost-model.md` matches.
- [ ] AC11: the plan and `tasks.md` pass `npx markdownlint-cli2`.
- [ ] AC12: CPO sign-off (approved with conditions) is recorded, and spike rows S7 (`retries: 3`) and S8 are in `streaming-spike.md`.

### Post-merge (automated in `soleur:ship`)

- [ ] AC13: the 72h rollback trigger has not fired, and the Phase 6 check shows, for each fired function (the BYOK leader turn and an
      email-triage run included), exactly one cost marker per run id for Claude spawns, zero
      `invalid status code: 524` lines, one attempt, and a committed PR or issue where the cron
      produces one.

## Test Scenarios

- Given two concurrent `spawnClaudeEval` calls with the same `(cronName, runId)`, then one child spawns
  and both calls receive its result (Guard 1 row 1).
- Given `runId` undefined for two concurrent calls, then two children spawn and neither joins the
  other (row 7).
- Given a spawn that throws ENOENT, when the same key is invoked again, then a fresh child spawns
  (row 8).
- Given a streamed unsigned POST to the handler, then the envelope reports 401 and no function runs
  (AC4).
- Given a CLI result line with `is_error:true` and the verified budget-stop subtype (synthesized),
  when parsed, then the marker carries both.
- Given a raw `resolveClaudeBin()` call added to a fixture cron file, the scan reports it (row 3).
- Spike (Phase 0, recorded in `streaming-spike.md`): rows S1–S7 through a Cloudflare quick tunnel,
  covering success, a 70-minute step, retry-after-error, non-retriable, multi-step with sleep, and a
  cut stream.

## Deferrals (tracking issues to file)

- **Tune `--max-turns` from measured `num_turns`** (#8613). Re-evaluate after 14 funded days of marker data;
  set each cap at p95 plus ~10 turns.
- **Burn alert threshold recalibration.** Re-evaluate $15/day after 14 funded days of non-null
  `cost_usd` (tracked on #5692 if it stays open, otherwise on a new issue).
- **Separate Console workspace with a monthly limit for the cron key** (CFO, #8614). `automation-status:
  UNVERIFIED — /work must attempt the Console step with Playwright before any operator handoff`.
  Re-evaluate after the burn alert exists.

## Open Code-Review Overlap

1 open scope-out touches these files: #8593 (the #6793 probe gate window in
`cron-follow-through-monitor.ts`). **Acknowledge.** It is about the probe window; this plan only moves
that file's spawn onto `spawnClaudeEval`. The other hits named unrelated files that share the
`route.ts` basename.

## Dependencies & Risks

- **Credits are exhausted now.** Top up after this merges. A top-up before it drains the same way,
  with each long run paying twice and committing nothing. Phase 6 needs credit.
- **1A changes transport for all ~70 functions.** The spike, the 524 alert and the Phase 6 non-cron
  canary are the controls. To revert, remove one line.
- **Long streamed requests across a deploy.** The deploy drain (`cron_in_flight`) waits for the Claude
  child to exit before swapping, and the stream completes with it. That is unchanged from today's
  behavior, minus the 524.
- **`--max-budget-usd` on 2.1.219** is unverified; Phase 3 gates on it.
- **The Opus 5.5 token-use assumption**: re-measure over 7 funded days (Finance).

## Domain Review

**Domains relevant:** Engineering, Finance

### Engineering

**Status:** reviewed
**Assessment:** Approve with changes: settled entries kept until TTL, errors returned as data, the
concurrency limits sleeping runs lose, results lost at the deploy swap, and compound-promote. Those
findings apply to Fix 1B and are folded into it. Plan review then moved the primary path to a
streaming spike (Fix 1A), which does not have those defects at all. The devex-lens review added poll
counting from slot acquisition, Sentry monitor margins, state-change logs, key construction inside the
helper, and Inngest Connect in the alternatives (all folded into 1B or the ADR). It also added the
audit-tier and compound-promote runs to the Phase 6 check.

### Finance

**Status:** reviewed
**Assessment:** Approve with changes: express the saving per funded day (~$516/month → ~$208/month, as corrected by the deepen pass from `cost_usd`),
report newly metered crons separately, re-measure the Opus 5.5 token assumption, add a
worst-case-daily cap column, and update the ledger and cost model (all folded in). The
pre-exhaustion burn alert is in scope (operator decision). The Console workspace limit is deferred.

### Product (CPO sign-off, threshold `single-user incident`)

**Status:** reviewed — **approved with conditions** (2026-09-23). All four conditions are applied:
(1) spike row S8 reproduces the real leader-loop chain and fails the branch if a memoized step
re-runs; (2) S7 re-runs with `retries: 3` and records the re-run count as the BYOK exposure;
(3) Phase 6 checks the leader turn's bill (one cost marker per turn, every `attempt` 0 — see the
Phase 6 wording; the `cumulativeCents` comparison was dropped at review because it doubles with the
markers),
using a turn with a tool call; (4) a 72h rollback trigger, with a direct notice and refund to any
affected founder. The CPO also floated excluding BYOK functions from streaming, since leader turns
are capped at 60s and gain nothing. Decided (CTO call, recorded): no. A second serve handler is a
second app registration on the Inngest server, which is the registration-identity risk that
rejected the private `serveHost`. Conditions 1–4 cover the BYOK risk instead.

### Product/UX Gate

Not applicable: there is no UI surface in Files to Edit/Create, and the mechanical override did not fire.

## Architecture Decision (ADR/C4)

### ADR

Create ADR-243 (provisional). Its contents are in "Architecture record" above.

### C4 views

All three model files (`model.c4`, `views.c4`, `spec.c4`) were read against this change. The actors
and systems involved (Inngest Server, `api`, Cloudflare, Anthropic API) are already modeled. The
defect is the relationship: `api -> inngest "Sends events; serves functions" (HTTP private-net :8288)`
omits that step execution runs inngest → `https://app.soleur.ai/api/inngest` through the Cloudflare
proxy. Add the edge, narrow the old one, and regenerate `model.likec4.json`. If the edge crosses a
view boundary, add its `views.c4` include line. The tests are listed in AC8.

### Sequencing

The ADR describes the state this PR ships. Nothing waits on a later slice.

## Plan Review Revisions

| Source | Finding | Disposition |
|---|---|---|
| DHH P0 | Streaming was rejected untested | **Applied.** Phase 0 spike; 1A is primary, 1B is the fallback. |
| Kieran P0 | Workspace GC deletes live workspaces once runs sleep | Applied to 1B; not applicable to 1A. |
| Kieran P1 | A same-cron second run still pays twice; the loop end is undefined; the lost report repeats; step renames break 3 tests; the infra test is not in CI | 1B: dedup, slot-based poll counting, report inside the step, step id kept. CI registration applied. |
| Kieran P2 | AC grep misses unquoted IDs; C4 JSON mirror; DeployInProgressError contradiction; `globalThis` registry; ADR side-effect note | All applied. |
| Simplicity | Cut the inline wait, per-cron slot, TTL code, generic `<T>` + compound-promote, burn alert, soak probe, population regex scan, Guard 2 rows 2–3 | Applied, except: (a) Guard 2 keeps a `-target` row, because an alert missing from the target list is never created; (b) `num_turns`, the ledger update and the worst-case-daily column are kept, since Finance asked for them and each is small. |
| DHH P1 | Use `routine_run_progress` instead of a file | Not applied: it is 1B-only, would need a migration, and the workspace-dir file needs no new store. It is recorded as the 1B upgrade path if web-2 enters the step path. |
| DHH P1 | Split the PR | **Surfaced to the operator** (taste). |
| CTO devex | Poll counting, monitor margins, state logs, key inside the helper, Inngest Connect, Phase 6 coverage | Applied (1B + ADR + Phase 6). |
| Deepen: security | Streaming returns 201 before verifying; spike key hygiene; ULID `runId` check; manual-trigger budget; alerts leaking payloads; zero read as healthy | Applied: signature test rewrite plus conditional edge rule, the spike Safety list, Guard rows 7–8, throttle plus manual-trigger row, aggregate-only selects, stuck-at-zero alert. |
| Deepen: observability | `cost_usd` is populated (wrong JSON path); burn query double-counts `_DAILY`; silence never pages; the "WARN+" citation is false; stream failure might not be a 524; empty-output probe | Applied: diagnosis corrected, nested path plus `:true` key match, a separate stuck-at-zero alert, citation corrected, S7 literal, probe script printing `count=`. |
| Deepen: architecture | The spike tested only success; toy app ≠ prod stack; 25 min < the 70-min cap; BYOK loop affected; inline spawners lack `runId` and are not drop-in; the budget table misses the event/oneshot sites; ADR-033/030 | Applied: S4–S7, the real custom server with gzip, S3 at 70 min, **threshold raised to single-user incident**, the migration detail, 18 named sites, the ADR amendments. |
| Deepen: claims sweep | web-2 flagged as retired | Not changed: the cattle web-2 born 2026-07-27 is a weight-0 standby (C4 `model.c4`, ADR-143). |
| Finance | Burn alert in scope | Surfaced to the operator, who chose **build it now**. It lands after the `cost_usd` fix and pages on a stuck-at-zero stream as well. |
| Operator (User-Challenge) | Prompt caching on direct API callers | Operator agreed to **drop** it (measured: no reuse within the TTL). |
| DHH P1 / operator | Split the PR | Operator chose **one PR**. |
