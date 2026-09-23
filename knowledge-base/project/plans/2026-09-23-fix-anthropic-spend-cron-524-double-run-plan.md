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
brand_survival_threshold: none
---

# fix: stop Cloudflare-524 double-runs of claude-eval crons and cut operator Anthropic spend

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
per-run dollar ceiling, and fixes the cost telemetry that hid the failure. It deliberately does
**not** add prompt caching to the direct Messages API callers. The measurement below shows it would
cost more than it saves (see Research Reconciliation).

## Research Reconciliation — Spec vs. Codebase

| Claim in the request | Reality (measured) | Plan response |
|---|---|---|
| "Duplicate sessions, hypothesis: HTTP request timeout" | Confirmed. inngest-server logged `error handling queue item … invalid status code: 524` (2026-09-18 08:02:38), then `inngest/function.failed` for run `01M2SRF3AT19V9WZZHNC9MY5YP` at 08:05:10 while both children were still running (they ended 08:07:36 and 08:09:23). | Fix 1 moves the long work out of the step request. |
| "~40% of spend is duplicate" | 49% of metered claude-eval spend over 30 days ($53.37 of $107.85). And 24 of 33 spending runs were marked failed, so most of the other half produced no committed output either. | Fix 1 is the priority. |
| "Add cache_control to compound-promote (537k uncached tokens)" | It runs once a week, one call per run. The extra runs on 2026-09-19/20 were **manual** triggers (outcome markers: `trigger=manual`), hours apart, beyond even the 1h cache TTL. A single call with a cache write pays 1.25x on input and gets no read back. | **Cut** (see Cut List). |
| "domain-router / email-triage likely below minimum cacheable length" | Confirmed. Their stable prefixes are about 611 and 624 chars (~150–160 tokens) against Haiku 4.5's 4,096-token minimum. | **Cut.** |
| "Cost markers report ok with 0 tokens on exhausted credit" | Confirmed at `_cron-claude-eval-substrate.ts` `resolveEvalCaptureStatus`: any parsed result event returns `"ok"`, including an `is_error` result. `cost_usd` is `null` on all 350 markers in 30 days. | Fix 4 (telemetry). |
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
Metered claude-eval spend $107.85 over the 30-day window, of which duplicate sessions were $53.37.
Keeping one session per run and re-pricing audit-tier runs at Opus 5.5 gives **$41.18 (−62%)** for
the same window. **Read this per funded day, not per month:** the key had credit for only ~9.3 of those
30 days (2026-09-10 16:00 → 09-18 09:03 and 09-19 20:00 → 09-21 11:05), so the real run-rate is about
$11.60/day, roughly $350/month, falling to about $4.40/day, roughly $133/month, after Fixes 1–2. The
bigger gain is in value per dollar: today ~73% of paid runs (24/33) commit nothing. Two caveats. The
Opus 5.5 re-pricing assumes the same tokens per run as Opus 5, so re-measure over the first 7 funded
days. And `cron-daily-triage` and `cron-follow-through-monitor` become metered for the first time, so
their spend is new visibility, not a regression. Report them as their own line. The exhausted $50 window
(2026-09-19 20:00 → 09-21 11:05) measured $40.57–44.89 of metered spend. The rest is unmetered:
`cron-daily-triage` and `cron-follow-through-monitor` spawn Claude inline and emit no cost marker.

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

#### Phase 0 — streaming spike (local, about an hour)

Reproduce the production path on a workstation:

- the pinned server, `inngest start` **v1.19.4** (release binary, same flags as `inngest-host.tf`);
- a minimal Next.js App Router app on `inngest@3.54.2` with `serve({ …, streaming: "force" })`;
- a **Cloudflare quick tunnel** (`cloudflared tunnel --url http://localhost:3000`) as the serve URL, so
  requests cross a real Cloudflare proxy with the same origin timeout.

Register three functions and run each three times:

| Function | Step duration | Pass condition |
|---|---|---|
| short | 2s | completes, one attempt |
| long | 3 min | completes, one attempt, no `invalid status code: 524` in server logs |
| very long | 25 min (the longest real cron session) | completes, one attempt, no 524 |

Also record: whether `"allow"` (not `"force"`) streams on this host, the SDK's heartbeat interval, and
whether the server logs anything new for streamed responses. Write the findings to
`knowledge-base/project/specs/feat-anthropic-spend-reduction/streaming-spike.md` and commit it before
Phase 1. It is the evidence the ADR cites.

- **Branch A: the spike passes on all three rows, all three runs.** Implement Fix 1A.
- **Branch B: any row fails.** Implement Fix 1B.

#### Fix 1A — SDK streaming plus an in-process single-flight guard

1. `apps/web-platform/app/api/inngest/route.ts`: add `streaming: "force"` to `serve()`, with a
   comment citing the spike file and ADR-238. `serveHost` is unchanged.
2. **Single-flight inside `spawnClaudeEval`**, so every caller is covered without touching its call
   site. Streaming removes the systematic retry, but a genuine mid-stream failure can still trigger
   one while the first child lives. Keep a process-wide map keyed `${cronName}:${runId}`, on
   `globalThis[Symbol.for("soleur.claudeEvalInFlight")]`. The app ships two bundles, so a
   module-level `Map` is not guaranteed to be a single instance. If an entry exists, the retry
   **awaits the existing child's promise** instead of spawning. The entry is set synchronously before
   the first `await` and deleted when the child settles. No TTL, no file, no queue: Inngest
   concurrency still holds because the step is still running.
3. **Route the two inline spawners through `spawnClaudeEval`.** `cron-daily-triage` and
   `cron-follow-through-monitor` build their own `SpawnResult` today and emit no cost marker. Moving
   them onto the shared function gives them the guard and the marker.
4. **Canary.** Streaming changes the transport for every function (~70). Phase 6 (post-merge) fires
   one short non-Claude function (`cron-anthropic-credit-probe`, once credit is present) plus the
   crons listed there, and checks that each completes in one attempt.

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

### Fix 3 — Per-run dollar ceiling (P5)

Add `--max-budget-usd <cap>` to each claude-eval cron's `CLAUDE_CODE_FLAGS`, first confirming that
`@anthropic-ai/claude-code@2.1.219` supports the flag (`npx -y @anthropic-ai/claude-code@2.1.219
--help`) and taking the exact budget-stop `subtype` string from that version. If it does not support
the flag, bump the pin in `package.json` and the `Dockerfile` together (KEEP IN SYNC). The cap for
each cron is `max(3 × 30-day median single-session cost at post-Fix-2 prices, $2)`, derived from the
marker export. The ADR records each cap, plus a worst-case-daily column (cap × scheduled runs per
day, summed), because per-run caps do not bound the daily total.

### Fix 4 — Telemetry and the 524 alert (P6, P7)

- Cost marker: add `is_error`, `subtype` and `num_turns` from the CLI result event, and root-cause why
  `total_cost_usd` never reaches `cost_usd` (null on 350/350 markers). The fields are additive, so
  `CaptureStatus` does not widen.
- Better Stack Logs alert (ADR-218 pattern) on inngest-server `invalid status code: 524` > 0 per 15
  min. Under Fix 1A this is also the canary for any function streaming fails to protect.
- **Daily burn alert (operator decision 2026-09-23: in scope; addresses open #5692).** A second
  Logs exploration sums `cost_usd` over `SOLEUR_CLAUDE_COST` markers per 24h bucket, and its alert
  pages above **$9/day**. That is about 2× the post-fix funded-day run-rate, and the ADR records it
  with a recalibration trigger: 14 funded days of non-null `cost_usd`. It is a per-bucket aggregate
  with no cross-bucket state, the class ADR-218 admits. Confirm the exploration SQL accepts `sum()`
  the way the existing ones accept `count()`. It depends on the `cost_usd` fix in the bullet above, so
  land that first. The alert also pages on a stuck-at-zero stream: zero markers over a 24h bucket
  that should contain scheduled runs. Otherwise a broken `cost_usd` would read as zero spend. At
  ship, `Closes #5692` only if its acceptance criteria are met; otherwise `Ref #5692`.
- Expense ledger: `knowledge-base/operations/expenses.md` "Anthropic API (claude-eval cron fleet)"
  row gets the measured funded-day run-rate instead of `0.00 unmetered`, model `claude-opus-5-5`, 18
  spawn sites and a fresh `verify_by`. Mirror the figure in `knowledge-base/finance/cost-model.md`.
  The cron-ux-audit $15 row is re-derived from markers.

**Cut by review:** routing compound-promote's `anthropic-cluster` through a helper (no measured 524;
under 1A streaming covers it anyway, and the alert watches it), and the 7-day soak probe (replaced by
the Phase 6 check plus the permanent 524 alert). **Cut by operator decision (2026-09-23):** prompt
caching on the direct Messages API callers (see Research Reconciliation).

### Architecture record

- **ADR-238** (ordinal provisional; re-verify across all `origin/*` refs before merge): "Inngest step
  requests cross the Cloudflare proxy; long steps must stream or detach". It records the evidence,
  the spike result and chosen branch, the rejected alternatives (private `serveHost`, `waitForEvent`,
  and Inngest Connect, which would switch every function's transport and whose self-hosted support is
  unverified), the single-flight contract, and the budget-cap table.
  - Under 1B it also records the per-host constraint, the in-process concurrency contract, and the fact
    that non-Claude `cron-platform` functions (GC, watchdogs) can now run beside a live child.
- **C4:** in `model.c4`, narrow the `api -> inngest` edge to event sending and add
  `inngest -> api "Invokes function steps at the registered serve URL (Cloudflare-proxied, ~100s origin timeout)"`.
  Regenerate `model.likec4.json`, which mirrors the edge title.

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

- **If this lands broken, the user experiences:** operator-facing only. Scheduled crons stop producing
  their PRs/issues, or keep double-spending. Under 1A a transport regression could also affect
  event-driven functions (email triage, GitHub webhooks, reminders), which is why Phase 6 includes a
  non-cron canary. No founder data or credentials are involved.
- **If this leaks, the user's data is exposed via:** no new vector. Step results keep today's shape;
  under 1B the persisted envelope is the same bounded, redacted `SpawnResult`, stored in the run's own
  ephemeral workspace.
- **Brand-survival threshold:** `none`

`threshold: none, reason: the touched paths (Inngest serve config, cron substrate, model tiers, one Better Stack alert) run operator-keyed scheduled jobs and existing event functions against the operator's own repository; no end-user data or credential surface changes.`

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_CLAUDE_COST marker per claude-eval run (now with is_error/subtype/num_turns/cost_usd) plus the existing per-cron Sentry cron monitors"
  cadence: "per cron run"
  alert_target: "Sentry cron monitor miss -> operator email (existing)"
  configured_in: "apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts; apps/web-platform/infra/sentry/cron-monitors.tf"
error_reporting:
  destination: "Sentry web-platform project (SENTRY_DSN) via reportSilentFallback; Better Stack Logs source 2457081"
  fail_loud: "inngest-server 'invalid status code: 524' -> Better Stack alert; single-flight hit -> reportSilentFallback op=claude-eval-singleflight-join"
failure_modes:
  - mode: "any step request exceeds the Cloudflare origin timeout (streaming failed to protect it, or a non-streamed path)"
    detection: "logtail_exploration_alert on inngest-server 'invalid status code: 524' (count > 0 per 15 min)"
    alert_route: "Better Stack alert -> operator email"
  - mode: "a retry arrives while the first Claude child is still live"
    detection: "single-flight join -> reportSilentFallback op=claude-eval-singleflight-join (Sentry), no second cost marker"
    alert_route: "Sentry issue -> operator email"
  - mode: "per-run budget cap hit"
    detection: "cost marker is_error=true with the budget-stop subtype; existing scheduled-output-missing Sentry event"
    alert_route: "Sentry -> operator email"
  - mode: "credit exhausted"
    detection: "cron-anthropic-credit-probe (hourly, existing) + cost marker is_error=true"
    alert_route: "credit-probe heartbeat RED -> operator email (existing)"
logs:
  where: "Better Stack Logs source 2457081 (soleur-inngest-vector-prd): app container WARN+ markers and inngest-server journald"
  retention: "Better Stack source retention (hot + S3 archive via s3Cluster union)"
discoverability_test:
  command: "bash scripts/betterstack-query.sh --since 24h --grep 'invalid status code: 524'"
  expected_output: "0"
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

**Property.** For any `(cronName, runId)`, at most one Claude child process is alive in the process,
however many times Inngest re-invokes the step.

**Assembly.** The single chokepoint is `spawnClaudeEval` in `_cron-claude-eval-substrate.ts`: the
`globalThis` in-flight map is checked, and its entry set, before the first `await`. Every Claude spawn
flows through it once the two inline spawners are migrated. What enforces that is a test asserting
`resolveClaudeBin()` is called nowhere outside the substrate file, not a hand-kept list.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Invoke `spawnClaudeEval` twice concurrently with the same key (the second arrives while the first child is live) | RED if the spawn spy counts 2; GREEN requires 1 spawn and both callers receiving the same result |
| 2 | REORDER: move the map `set` after the first `await` | RED (row 1 observes inside the window) |
| 3 | Add a new `resolveClaudeBin()` call in any `functions/*.ts` other than the substrate, as a second member after the compliant one | RED (the scan counts call sites across all files) |
| 4 | Guard dispatch: point the scan at a directory with zero `.ts` files | RED (the scan asserts it read ≥ 1 file and found the substrate's own call) |
| 5 | Same `runId`, different `cronName` | 2 spawns (distinct keys), GREEN |
| 6 | The first child rejects; then the same key is invoked again | 1 new spawn (the entry was cleared on settle), GREEN |

**Harness rows:** (H1) row 4 is the harness row: an empty scan must fail loudly, not pass on "0
checked". (H2) must-PASS: a fixture file that imports `spawnClaudeEval` and calls it (no raw
`resolveClaudeBin`) passes the scan.

**Anchor.** The scan derives its population from the directory at test time, and its only stored
expectation is "exactly one file, the substrate". A PR adding a raw spawn changes the tree and
reddens.

### Guard 2 — the 524 and burn alerts match what their emitters log

**Property.** Each of this plan's Better Stack explorations queries the literal its emitter actually
writes, on the source that carries it, and every one of them is in the auto-apply target list.

**Assembly.** `logtail_exploration.inngest_step_524` and `logtail_exploration.claude_daily_burn` in
`betterstack-logs-alerts.tf`, their two alerts, and the apply workflow's `-target=` list. Literals
observed in production: `invalid status code: 524` (2026-09-18 08:02:38, source 2457081) and the
`SOLEUR_CLAUDE_COST` marker key.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change the query literal | RED (the test pins the query against a synthesized fixture of the observed log shape) |
| 2 | Point the exploration at a different source | RED |
| 3 | Remove any of the four `-target=` lines from the apply workflow | RED (the test asserts every exploration and alert address in the file is in the workflow's target list; without them the alert is never created) |
| 4 | A second exploration: change the burn query from `sum(cost_usd)` to `count()`, or drop its `SOLEUR_CLAUDE_COST` filter | RED (the test iterates every exploration in the file, not just the first) |

## Files to Edit

- `apps/web-platform/app/api/inngest/route.ts` (1A).
- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — single-flight guard,
  marker fields, result-line parse.
- `apps/web-platform/server/inngest/functions/cron-daily-triage.ts` and
  `cron-follow-through-monitor.ts` — move onto `spawnClaudeEval`; update their tests
  (`test/server/inngest/cron-daily-triage.test.ts`, `cron-follow-through-monitor.test.ts`).
- `apps/web-platform/server/claude-cost-marker.ts` — additive fields.
- `apps/web-platform/server/inngest/model-tiers.ts` and its test; the four audit crons' header comments.
- Each claude-eval cron's `CLAUDE_CODE_FLAGS` (`--max-budget-usd`); `package.json` + `Dockerfile` only
  if the CLI pin must move.
- `apps/web-platform/infra/betterstack-logs-alerts.tf` (two explorations and two alerts),
  `.github/workflows/apply-web-platform-infra.yml` (four `-target=` lines), `.github/workflows/infra-validation.yml` (register the new infra test, since
  CI lists suites by name), and every other logtail consumer from `git grep -ln logtail_exploration`
  (`scheduled-terraform-drift.yml`, `infra/main.tf`, `infra/variables.tf`,
  `plugins/soleur/lib/heartbeat-live-reconcile.ts`), each reconciled.
- `knowledge-base/engineering/architecture/decisions/ADR-238-*.md` (new),
  `knowledge-base/engineering/architecture/diagrams/model.c4`, `model.likec4.json`.
- `knowledge-base/operations/expenses.md`, `knowledge-base/finance/cost-model.md`.
- Branch B only: `cron-workspace-gc.ts`, `sentry/cron-monitors.tf`, `test/server/inngest/cron-cohort-dedup.test.ts`,
  plus the 16 caller files.

## Files to Create

- `knowledge-base/project/specs/feat-anthropic-spend-reduction/streaming-spike.md` (Phase 0 evidence).
- `apps/web-platform/test/server/inngest/claude-eval-single-flight.test.ts` — Guard 1.
- `apps/web-platform/test/infra/inngest-step-524-alert.test.sh` — Guard 2 (precedent:
  `inngest-luks-wrong-volume-alert.test.sh`).

## Implementation Phases

0. **Spike** (above). Commit `streaming-spike.md`; pick the branch.
1. **Fix 1A** (or 1B): Guard 1 tests first (RED), then the guard, the `serve()` flag, and the two
   inline spawners moved over; go green. Run the per-cron tests.
2. **Fix 4 telemetry**: marker fields; root-cause `cost_usd: null`.
3. **Fix 3 budget cap**: verify the flag and its subtype on 2.1.219, derive the caps, add the flag.
4. **Fix 2 model re-pin**: verify the ID live, edit, re-grep with the unquoted pattern.
5. **Alert, ADR, C4, ledger**: Terraform plus `-target` plus CI registration (Guard 2), ADR-238, C4
   and its JSON mirror, expenses and cost model.
6. **Post-merge check (`soleur:ship`, once credit is present).** Via `soleur:trigger-cron`, fire one
   short execution cron (cron-seo-aeo-audit), one long execution cron (cron-community-monitor), one
   audit-tier cron (cron-architecture-diagram-sync, to exercise the Opus 5.5 re-pin and the cap),
   and cron-compound-promote. Also watch one event function's next natural run. Then read Better
   Stack: exactly one cost marker per run id, zero 524s, one attempt per run, and a committed PR or
   issue per cron.

**Does merging this alone change production?** Yes, on two paths, and the PR body's first line must
say so. (a) `web-platform-release.yml` redeploys on any `apps/web-platform/**` change. Under 1A every
Inngest function streams from the next request, and every cron runs the new guard, model and caps.
(b) `apply-web-platform-infra.yml` fires on `apps/web-platform/infra/**` and creates the Better Stack
exploration and alert for the addresses in its `-target=` list. No Terraform variable is added.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `streaming-spike.md` is committed with the three-row result table (three runs each) and
      names the chosen branch. The implementation matches that branch.
- [ ] AC2: Guard 1 rows 1–6 plus H1 and H2 pass:
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/claude-eval-single-flight.test.ts`.
- [ ] AC3: `resolveClaudeBin()` is called only in `_cron-claude-eval-substrate.ts` (Guard 1 row 3 green
      on the final tree). `cron-daily-triage` and `cron-follow-through-monitor` emit the cost marker.
- [ ] AC4: `AUDIT_MODEL === "claude-opus-5-5"`, the ID verified by `GET /v1/models/claude-opus-5-5`,
      and `git grep -nE 'claude-opus-5([^-.]|$)' -- apps/web-platform` returns nothing.
- [ ] AC5: every claude-eval cron's flags carry `--max-budget-usd` matching the ADR table. The flag was
      verified on the pinned CLI, or the pin was bumped in both `package.json` and `Dockerfile`.
- [ ] AC6: the cost marker carries `is_error`, `subtype`, `num_turns`, and a non-null `cost_usd` when
      the CLI reports `total_cost_usd` (unit test on a synthesized result line using the verified
      budget-stop subtype).
- [ ] AC7: both explorations and both alerts (the 524 alert and the daily burn alert) exist, all four
      addresses are in the apply workflow's `-target=` list, `inngest-step-524-alert.test.sh` (it covers
      both) is registered in `infra-validation.yml` and green, and `terraform validate` is green.
- [ ] AC8: ADR-238 (or the re-verified ordinal) is committed. The C4 edge and `model.likec4.json` are
      updated. `c4-code-syntax.test.ts`, `c4-render.test.ts`, `c4-canonical-mirror.test.ts`,
      `plugins/soleur/test/c4-canonical.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh`
      are green.
- [ ] AC9: `expenses.md` no longer reads `unmetered` for the claude-eval fleet; it names
      `claude-opus-5-5` and 18 spawn sites. `cost-model.md` carries the same figure, and both cite the
      marker query that produced it.
- [ ] AC10: the plan and `tasks.md` pass `npx markdownlint-cli2`.

### Post-merge (automated in `soleur:ship`)

- [ ] AC11: the Phase 6 check shows, for each fired function, exactly one cost marker per run id (for
      Claude crons), zero `invalid status code: 524` lines, one attempt, and a committed PR or issue
      where the cron produces one.

## Test Scenarios

- Given two concurrent `spawnClaudeEval` calls with the same `(cronName, runId)`, then one child spawns
  and both calls receive its result (Guard 1 row 1).
- Given a child that rejected, when the same key is invoked again, then a fresh child spawns (row 6).
- Given a CLI result line with `is_error:true` and the verified budget-stop subtype (synthesized),
  when parsed, then the marker carries both, and `cost_usd` equals the line's `total_cost_usd`.
- Given a raw `resolveClaudeBin()` call added to a fixture cron file, the scan reports it (row 3).
- Spike (manual, Phase 0, recorded in `streaming-spike.md`): a 3-minute and a 25-minute step through a
  Cloudflare quick tunnel complete in one attempt with `streaming: "force"`.

## Deferrals (tracking issues to file)

- **Tune `--max-turns` from measured `num_turns`** (#8613). Re-evaluate after 14 funded days of marker data;
  set each cap at p95 plus ~10 turns.
- **Burn alert threshold recalibration.** Re-evaluate $9/day after 14 funded days of non-null
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
**Assessment:** Approve with changes: express the saving per funded day (~$350/month → ~$133/month),
report newly metered crons separately, re-measure the Opus 5.5 token assumption, add a
worst-case-daily cap column, and update the ledger and cost model (all folded in). The
pre-exhaustion burn alert is in scope (operator decision). The Console workspace limit is deferred.

### Product/UX Gate

Not applicable: there is no UI surface in Files to Edit/Create, and the mechanical override did not fire.

## Architecture Decision (ADR/C4)

### ADR

Create ADR-238 (provisional). Its contents are in "Architecture record" above.

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
| Finance | Burn alert in scope | Surfaced to the operator, who chose **build it now**. It lands after the `cost_usd` fix and pages on a stuck-at-zero stream as well. |
| Operator (User-Challenge) | Prompt caching on direct API callers | Operator agreed to **drop** it (measured: no reuse within the TTL). |
| DHH P1 / operator | Split the PR | Operator chose **one PR**. |
