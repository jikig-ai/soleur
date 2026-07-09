---
title: "feat: End-to-end Anthropic API cost attribution for the production Claude fleet"
date: 2026-07-09
type: feat
branch: feat-one-shot-anthropic-cost-attribution
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
status: draft
---

# feat: End-to-end Anthropic API cost attribution for the production Claude fleet ✨

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: the ANTHROPIC_ADMIN_KEY secret is written by a
     doppler_secret Terraform resource (mirrors inngest-betterstack-token.tf); the
     only non-Terraform residual is the vendor-console key mint, gated by the
     automation-feasibility rule (Playwright attempt first, UNVERIFIED until a
     human gate is reached). No secret write is done by hand. -->

## Enhancement Summary

**Deepened on:** 2026-07-09
**Review panel:** architecture-strategist, code-simplicity-reviewer,
observability-coverage-reviewer, security-sentinel, git-history-analyzer (premise
verification). All 7 cited premises CONFIRMED against the codebase.

### Key corrections folded in (load-bearing)
1. **P1-A — the cron output-format switch is NOT wholly fail-open (ADR-033 I8 collision).**
   `classifyEvalFatal` (`_cron-shared.ts:1088-1132`) classifies credit/auth/spawn-fault
   by substring-regex over `stdoutTail + stderrTail` — the #5674 fix for the
   2026-06-29 fleet-wide credit-exhaustion incident. Changing claude's stdout shape
   can change what those regexes see. Phase 0 now HARD-verifies I8 classification +
   `stdoutTail`/`stderrTail` readability survive the format change; the ADR-033
   amendment must reconcile I8 + I5 explicitly.
2. **P1-B — "single substrate edit covers ~40 crons" was false.** Only **15 of 47**
   crons route through `spawnClaudeEval`. There is a **third** Anthropic-spend choke
   point — `postAnthropicMessage` (`_cron-shared.ts:547`) — used by
   `cron-compound-promote.ts:438` (real spend) + credit-probe. Phase 2 now names all
   THREE choke points and adds a marker to `postAnthropicMessage`.
3. **Default the substrate flag to `--output-format json`** (not `stream-json --verbose`)
   — lowest log-volume + smallest change to the existing `stdoutTail`→Sentry signal;
   preserve tail readability by extracting the result text into `stdoutTail`.
4. **Positive `capture_status` marker on every substrate exit** (obs P1) — row-absence
   is not a probe; emit `cost_usd: null` + `capture_status ∈ {ok,no-result-event,parse-error,timeout}`
   so a capture failure is a shipped event, not silence.
5. **Marker helper bypasses the Sentry breadcrumb mirror** (`logger.ts:123-125`
   auto-mirrors every WARN+ line) to avoid evicting genuine diagnostics from the
   ring buffer.
6. **Field-allowlist (not object-spread) the daily marker rows** (security F2) so
   `api_key_id`/`workspace_id` never reach Better Stack; add an admin-transport
   redaction AC (security F1); correct R-E — the admin key is process-wide readable,
   the real control is its read-only scope (security F3).

### Deferred / recorded (see `decision-challenges.md`)
- **Simplicity challenge:** Phase 3 (Admin API) serves NONE of the four optimizations
  directly (they are all measurable from Phase 1+2 markers) — it is authoritative
  reconciliation, which the caller nonetheless explicitly scoped (Scope item 2).
  Kept per stated scope; challenge persisted for the operator.

## Overview

Today Anthropic spend (~$430/mo on the shared `github-claude-code-key`) **cannot be
attributed** per-cron or per-model. The key is byte-identical across Doppler
`soleur/ci`, `soleur/prd`, `soleur/prd_cla` and powers the production web-platform
Inngest cron fleet + the agent-runner / leader-loop web sessions (NOT CI —
`claude-code-review` is dormant since 2026-02-12). No structured cost marker is
logged anywhere it can be self-served.

This PR adds **attribution only** — three surfaces, all emitting one queryable
Better Stack marker family, plus one daily reconciliation cron:

1. **Session markers** — a `SOLEUR_CLAUDE_COST` structured marker at every
   agent-runner / cc-soleur-go / leader-loop **turn**, emitted from the single
   `cost-writer.ts` choke point (all three session paths already funnel through
   it). Surfaces the already-accumulated per-turn `total_cost_usd` + 4 token
   fields — no recompute.
2. **Cron markers** — the same marker at every `claude-eval` cron run. This
   half is **new capture, not surfacing** (see Research Reconciliation R1): the
   eval substrate spawns the `claude` CLI and today captures only text tails, so
   there is no accumulated cost to surface. We add a JSON output format to the
   substrate spawn and parse the final `result` event's `total_cost_usd` /
   `usage` / model.
3. **Daily Admin cost-report cron** — a new low-frequency `cron-anthropic-cost-report`
   that pulls the Anthropic **Admin Cost & Usage API** (the `Ref #5674` deferred
   follow-up noted in `cron-anthropic-credit-probe.ts`) and emits a daily marker
   with authoritative per-model / per-key org spend — self-servable from Better
   Stack without the Anthropic Console.

All cost capture is **fail-open**: a logging or parse failure must never red a
cron or fail a session. The markers ride the **existing** app-container →
journald → Vector → Better Stack path and are queryable via the **existing**
`scripts/betterstack-query.sh --grep SOLEUR_CLAUDE_COST` (no script change
required); Scope 3 is satisfied by documenting the query patterns in the runbook.

**Goal:** make the four downstream optimizations measurable — Opus→Sonnet tier
audit (per-model), prompt caching (cache-token visibility), spawn-only-when-work-exists
(per-cron), per-surface key split (session-vs-cron). **Non-goal:** this PR does
NOT change any model tier, cadence, or key assignment, and does NOT add
spend-vs-budget alerting (that remains the other half of `Ref #5674`).

## Research Reconciliation — Spec vs. Codebase

| # | Premise (from the task) | Codebase reality (verified) | Plan response |
|---|---|---|---|
| R1 | The eval substrate `_cron-claude-eval-substrate.ts` "accumulates `accumulatedUsage.cost_usd` (~lines 1012, 2325-2365)". | **False for the substrate.** That file (927 lines) spawns the `claude` CLI via `child_process` and captures only bounded stdout/stderr **tails** — it accumulates NO cost. The `accumulatedUsage` object (`:1012`) and the `message.total_cost_usd` delta extraction (`:2325-2365`) are in **`agent-runner.ts`** — the *session* path. The premise conflated the two files. | Split Scope 1 into two architecturally-distinct halves: **sessions** (surface accumulated cost at the `cost-writer.ts` choke point — Phase 1) and **crons** (NEW capture via a JSON output format — Phase 2, higher blast radius). |
| R2 | "agent-runner.ts / soleur-go-runner.ts serve web sessions with the same key." | Confirmed. Cost flows to `cost-writer.persistTurnCost` / `persistTurnCostAwaitable` from **three** call sites: `agent-runner.ts:2359`, `cc-dispatcher.ts:4002`, `agent-on-spawn-requested.ts:583` (the PR-B leader loop, #4379). | `cost-writer.ts` is the single choke point — emit the session marker there once, threading `source`+`model` from the 3 callers (type widening, R6). |
| R3 | "the Admin cost_report is flagged as a deferred follow-up in cron-anthropic-credit-probe.ts." | Confirmed verbatim (`cron-anthropic-credit-probe.ts:15-20`): "NO BALANCE ENDPOINT EXISTS … the only signals are the canary 400/401 and the Admin cost_report spend trend (a deferred follow-up needing a new sk-ant-admin secret …). The pre-exhaustion spend-vs-budget alert is tracked as a `Ref #5674` follow-up." | Phase 3 wires the cost-report pull (attribution). The **spend-vs-budget alert** stays deferred (explicit non-goal). |
| R4 | "emit a monitored SOLEUR_CLAUDE_COST **structured stdout** marker … queryable via scripts/betterstack-query.sh." | Better Stack ingests the app container's pino stdout via Vector Source 3 (`app_container_journald`) but **filtered to pino WARN+ (level ≥ 40)** (`vector.toml` `app_container_warn_filter`; runbook `betterstack-log-query.md:85-111`). An `info`-level marker will **not** ship. | Emit the marker at pino **`warn`** level (level 40). `betterstack-query.sh --grep SOLEUR_CLAUDE_COST` already does `raw LIKE '%…%'` — **no script edit**; document the query in the runbook. |
| R5 | "surface the already-accumulated cost_usd — do not recompute." | True for sessions (R1). For **crons**, nothing is accumulated. For the **leader loop** (`agent-on-spawn-requested.ts:568-582`), cost is already computed from `MODEL_PRICING × usage` — surface it, don't re-derive. | Sessions/leader-loop: surface. Crons: parse the CLI's own `total_cost_usd` (the CLI's authoritative number, not a re-derivation). Admin cron: use the Admin API's authoritative `amount`. |
| R6 | (implicit) cost-writer already carries model/source. | `TurnCostInput` = `{ totalCostUsd, usage:{4 tokens} }` — **no `model`, no `source`**. | Widen the `persistTurnCost` / `persistTurnCostAwaitable` signatures with a `marker: { source, model }` arg (`hr-type-widening-cross-consumer-grep` — 3 callers enumerated in R2). |
| R7 | (implicit) the claude CLI result field names are known. | `total_cost_usd` is doc-confirmed in the `--print` json result; the exact `usage` token field names + model id are **NOT** doc-confirmed (per live docs check). | Phase 0 runs `claude -p --output-format json` **live** and pins the actual shape before coding (CLI-verification gate #2566). |
| R8 | (implicit) the Admin cost_report gives per-model $ directly. | `cost_report` groups by `description`/`workspace_id` only (`bucket_width="1d"`); per-**model**/per-**key** breakdown lives in the **usage_report** (tokens, `group_by[]` supports `model`,`api_key_id`). `amount` unit (dollars vs cents) is ambiguous in docs. | Phase 3 pulls **both**: `cost_report` (authoritative daily $) + `usage_report group_by=model,api_key_id` (per-model tokens). Phase 0 pins the `amount` unit live. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this is an
internal observability/cost surface. The only failure mode that could reach a
user is a cost-capture path that throws and fails a cron or session; every
capture site is therefore **fail-open** (wrapped, never rethrows), so a broken
marker degrades to "no marker" (an observability gap), never a failed run.

**If this leaks, the user's data is exposed via:** not user data. The new
`ANTHROPIC_ADMIN_KEY` is a **read-only** org-billing key (`sk-ant-admin01-…`) —
it can read org usage/cost metadata but cannot spend or read conversations. A
leak exposes aggregate org spend metadata (competitive/reputational), not any
single user's data, money, or workflow. Markers carry `conversationId`/`runId`
(already present in existing WARN logs), token counts, cost, and model — no PII.

**Brand-survival threshold:** none.

> **threshold: none, reason:** the diff touches a sensitive path (a new Doppler
> secret + infra) but introduces no user-facing surface, no user-data exposure
> vector, and no single-user failure mode — all cost capture is fail-open and
> the new secret is read-only org-billing metadata.

## Implementation Phases

### Phase 0 — Live contract verification (no code) 🔬

Pin the two under-documented external contracts BEFORE coding (CLI-verification
gate #2566; R7/R8). Record outputs in `## Research Insights` at the bottom.

- [x] **Claude CLI result shape.** Run a throwaway 1-turn probe and capture the
  final `result` object:
  ```bash
  claude -p --output-format json "reply with the single word ok" | jq '{type, total_cost_usd, usage, model, modelUsage, session_id}'
  ```
  Pin the EXACT key names for token usage (`input_tokens` vs `uncached_input_tokens`?),
  the cache fields, and where the model id lives. Repeat with
  `--output-format stream-json --verbose` and confirm the final newline-delimited
  event is `{"type":"result", … total_cost_usd …}`. **Decide** the substrate flag
  — **default `--output-format json`** (single final object: lowest log volume,
  smallest change to the existing `stdoutTail` diagnostic; the `routine_run_progress`
  heartbeat (#5766) already covers liveness). `stream-json --verbose` is the
  fallback only if a live per-event stream proves necessary.
- [x] **HARD GATE — ADR-033 I8 classification survives the format change (arch P1-A).**
  The credit/auth/spawn-fault classifier `classifyEvalFatal` (`_cron-shared.ts:1088-1132`)
  substring-matches `ANTHROPIC_CREDIT_EXHAUSTED_RE`/`ANTHROPIC_AUTH_FAILURE_RE`/
  `SPAWN_FAULT_RE` over `stdoutTail + stderrTail` — the #5674 fix for the 2026-06-29
  fleet-wide credit-exhaustion incident. Under the chosen output format, verify LIVE
  that (a) a credit-exhausted / auth-failed / spawn-fault run STILL classifies fatal
  (the error text still reaches `stdoutTail` OR `stderrTail` — Anthropic API errors
  typically print to stderr, which is unchanged, but CONFIRM), and (b) a benign
  max-turns run still classifies benign. If the format moves the error text out of
  the captured tails, Phase 2 MUST extract the `result` event's error field into the
  tail. **Do not proceed to Phase 2 until this is pinned** — I8 loss re-opens the
  exact P0 the credit-probe/#5674 work closed.
- [ ] **Session-marker volume baseline (obs P3).** Cost markers ride the SAME
  Better Stack 3 GB/mo quota AND the SAME WARN+ Vector lane that preserves the
  cron-FAILURE reason. Session markers are per-turn. Measure actual volume before
  merge — do NOT estimate: count `persistTurnCost`/`persistTurnCostAwaitable` calls
  over a representative window (or app-container WARN lines/day via
  `betterstack-query.sh`). If non-trivial, gate session markers behind sampling/debounce.
- [ ] **Admin API `amount` unit.** With a scratch admin key (or the org key,
  post-mint — see Phase 3), run:
  ```bash
  curl -s https://api.anthropic.com/v1/organizations/cost_report \
    -H "x-api-key: $ANTHROPIC_ADMIN_KEY" -H "anthropic-version: 2023-06-01" \
    --url-query starting_at=<yesterdayZ> --url-query bucket_width=1d | jq '.data[0].results[0]'
  ```
  Pin whether `amount` is **dollars or cents** and its type (decimal string).
  Confirm `group_by[]=model,api_key_id` on `/usage_report/messages` returns the
  per-model split. Do NOT assume — the doc wording is contradictory.
- [x] Confirm the marker is queryable end-to-end shape: a `logger.warn({...}, "msg")`
  JSON line with a top-level `SOLEUR_CLAUDE_COST` discriminator is matched by
  `betterstack-query.sh --grep SOLEUR_CLAUDE_COST`.

### Phase 1 — Session cost markers (low risk) 💰

Emit the marker as **side-effect #5** in `cost-writer.ts`, the choke point all
three session paths funnel through (R2). Fail-open.

- [x] **New marker helper** `apps/web-platform/server/claude-cost-marker.ts`
  (small, single-purpose):
  ```ts
  // Structured, WARN-level (Vector ships pino level >= 40 — R4), fail-open cost
  // marker. `SOLEUR_CLAUDE_COST` is the top-level discriminator so
  // betterstack-query.sh --grep matches it. NEVER throws.
  //
  // Uses a DEDICATED pino instance that does NOT install the mirrorToSentry
  // logMethod hook (logger.ts:123-125 auto-mirrors every WARN+ line to a Sentry
  // breadcrumb — a steady cost-marker stream would evict genuine diagnostics from
  // the shared-scope ring buffer; arch P2-Q4). Level WARN is still required so the
  // Vector app_container_warn_filter ships it. This silent catch is the sanctioned
  // observability-of-observability exemption to cq-silent-fallback-must-mirror-to-sentry
  // (documented in ADR-103).
  import pino from "pino";
  const log = pino({ base: { component: "claude-cost" } }); // no Sentry logMethod hook
  export type ClaudeCostSource =
    | "agent-runner" | "cc-soleur-go" | "leader-loop" | `cron:${string}`;
  export type CaptureStatus = "ok" | "no-result-event" | "parse-error" | "timeout";
  export interface ClaudeCostMarker {
    source: ClaudeCostSource; model: string | null;
    input_tokens: number | null; output_tokens: number | null;
    cache_read_input_tokens: number | null; cache_creation_input_tokens: number | null;
    cost_usd: number | null; id: string; capture_status: CaptureStatus;
  }
  export function emitClaudeCostMarker(m: ClaudeCostMarker): void {
    try {
      log.warn({ SOLEUR_CLAUDE_COST: true, ...m }, "claude cost");
    } catch { /* fail-open: observability must never break a run */ }
  }
  ```
  (Session sites always pass `capture_status: "ok"` with concrete values; the
  substrate uses the other statuses — Phase 2. Confirm the dedicated pino instance
  reuses the project's `formatters.log` PII-rename + does not double-register the
  Sentry hook; if a shared base logger is easier, gate the hook off for this
  `component`.)
- [x] **Widen `persistTurnCost` + `persistTurnCostAwaitable`** (`cost-writer.ts`)
  with a new `marker: { source: ClaudeCostSource; model: string }` param; call
  `emitClaudeCostMarker` at the top of each (synchronous, before the fire-and-forget
  RPCs — does not change timing). `id` = `conversationId`.
- [x] Thread `marker` from the **3 call sites** (`hr-type-widening-cross-consumer-grep`
  — verify via `git grep -n 'persistTurnCost' apps/web-platform/server`):
  - `agent-runner.ts:2359` → `{ source: "agent-runner", model: <leader model in scope> }`
  - `cc-dispatcher.ts:4002` → `{ source: "cc-soleur-go", model: <result/query model> }`
  - `agent-on-spawn-requested.ts:583` → `{ source: "leader-loop", model: leaderModule.model }`
  - For each, grep the local scope for the model variable; if a site lacks a
    model in scope, thread it from the leader config / SDK result (name the exact
    variable in tasks.md at /work time, do not guess here).

### Phase 2 — Cron per-run cost markers (higher blast radius) ⚙️

**Riskiest phase.** There are **THREE** Anthropic-spend choke points (arch P1-B —
NOT "one substrate edit covers ~40 crons"): (1) `cost-writer.persistTurnCost` —
sessions (Phase 1); (2) `spawnClaudeEval` — the **15 of 47** spawn-based eval crons;
(3) `postAnthropicMessage` (`_cron-shared.ts:547`) — the HTTP-transport crons
(`cron-compound-promote.ts:438` = real spend; credit-probe = canary). Phase 2
instruments (2) and (3). Fail-open + ADR-033 amend (reconcile I8 + I5).

**(2) `spawnClaudeEval` substrate:**
- [x] `_cron-claude-eval-substrate.ts` `spawnClaudeEval` (`:818`): inject the
  Phase-0-chosen flag (**default `--output-format json`**) into the argv **only if
  the caller's `flags` do not already set `--output-format`** (today none do — text
  `--print`). Mirror the existing `--strict-mcp-config` prepend.
- [x] In the `rlOut.on("line")` handler (`:830`): try-`JSON.parse` each line
  fail-open; if `parsed.type === "result"`, capture `total_cost_usd` + `usage` +
  model into a local `evalCost`. **Preserve the `stdoutTail` diagnostic (obs P2 /
  arch P1-A):** extract the result event's human-readable text (`.result`) — and any
  error field — INTO `stdoutTail` rather than letting raw JSON events crowd the
  bounded tail out (the tail feeds `scheduled-output-missing`'s Sentry extra
  `:1016` AND the I8 classifier reads it).
- [x] Extend `SpawnResult` (`:22`) with optional `costUsd?`, `usage?`, `model?`
  (optional — inline-spawn siblings that build their own `SpawnResult` literals stay
  compiling, mirroring `stdoutTail?`).
- [x] **Emit a POSITIVE marker on EVERY substrate exit (obs P1) — never rely on
  row-absence.** After the child exits: `emitClaudeCostMarker({ source: \`cron:${cronName}\`,
  id: runId ?? cronName, ...(evalCost ? {capture_status:"ok", model, cost_usd, ...usage}
  : {capture_status: <no-result-event|parse-error|timeout>, model:null, cost_usd:null, ...nulls}) })`.
  A parse failure / old format / timeout emits `capture_status != "ok"` — a shipped
  event that disambiguates "capture broke" from "genuinely $0" from "cron never ran",
  none of which a missing row can distinguish. Wrapped fail-open (never fatal).
- [x] Confirm no cron's semantic behavior depends on claude's stdout **text** format
  (`git grep` the substrate + handlers: output is verified independently via the
  GitHub API in `verifyScheduledIssueCreated`, not by parsing claude's stdout — note
  in tasks.md).

**(3) `postAnthropicMessage` HTTP transport:**
- [x] `_cron-shared.ts` `postAnthropicMessage` (`:547-603`): it currently returns
  `{text, stopReason}` and DISCARDS the response `usage`. Surface it — read
  `data.usage` + `data.model` from the parsed response and emit
  `emitClaudeCostMarker({ source: \`cron:${callerCronName}\`, capture_status:"ok", ... })`.
  Thread the caller's cron name in (compound-promote, credit-probe pass their
  `CRON_NAME`). This closes per-cron attribution for the HTTP-transport crons that
  `spawnClaudeEval` misses. Note: Anthropic's `/v1/messages` does NOT return
  `total_cost_usd` — derive cost from `usage × MODEL_PRICING` (the ONE place a
  recompute is unavoidable; the leader-loop already does exactly this at
  `agent-on-spawn-requested.ts:568`), or emit tokens-only with `cost_usd:null` and
  let Phase 3's Admin totals reconcile. Decide in tasks.md; tokens-only is acceptable
  for the canary.

### Phase 3 — Daily Admin cost-report cron (Scope 2) 📊

New low-frequency cron mirroring `cron-anthropic-credit-probe.ts`'s shape.

- [x] `apps/web-platform/server/inngest/functions/cron-anthropic-cost-report.ts`:
  - Reads `process.env.ANTHROPIC_ADMIN_KEY`; if unset → `reportSilentFallback`
    (`op: "anthropic-admin-key-missing"`) + benign heartbeat (do not page a
    missing-optional-key the same as fleet-down; mirror credit-probe's key-missing
    branch semantics) **AND emit a positive `SOLEUR_CLAUDE_COST_DAILY {status:"key-missing"}`
    WARN marker** (obs P4) so the daily Better Stack surface is positively-dark, not
    absent — an absent row is otherwise mis-triageable as a regression during the
    code-merges-first → mint window (Apply path §).
  - **Single consolidated `step.run`** (learning 2026-06-14 — Inngest memoizes
    return values not side effects): fetch `GET /v1/organizations/cost_report`
    (`bucket_width=1d`, prior UTC day) for authoritative daily $ grouped by
    `description` (Phase 0 confirms whether `description` grouping already yields the
    per-model $ split). Pull `GET /v1/organizations/usage_report/messages`
    (`group_by[]=model`, `group_by[]=api_key_id`, `bucket_width=1d`) for per-model
    **tokens** ONLY if Phase 0 shows `cost_report`'s `description` grouping does not
    already carry per-model detail (simplicity #2 — avoid the redundant second call).
    Auth `x-api-key: <admin key>` + `anthropic-version: 2023-06-01`. Add
    `getAnthropicAdminReport` to `_cron-shared.ts` (GET; typed non-ok error;
    **MUST mirror `postAnthropicMessage`'s two redaction properties** — the
    network-catch rethrow carries neither key nor request context, and the non-ok
    body excerpt routes through `formatTailForSentry`; security F1).
  - Emit one `SOLEUR_CLAUDE_COST_DAILY` WARN marker carrying: date, org total
    `cost_usd`, and a per-model array. **Field-allowlist (explicit picks), NEVER
    object-spread the Admin rows (security F2)** — the API rows carry `api_key_id` /
    `workspace_id`; a `...row` spread would ship those to Better Stack. Build the
    per-model entry as `{model, input_tokens, output_tokens, cache_read,
    cache_creation, cost_usd?}` with named picks only. Distinct discriminator from
    the per-run `SOLEUR_CLAUDE_COST` so the runbook can rank either.
  - **Fail-open + output-aware heartbeat** (learnings 2026-06-01/06-12): gate the
    Sentry heartbeat on a successful API pull; classify 401/403 (bad admin key)
    as fatal-RED, transient (429/5xx/net) → rethrow for Inngest retry; gate the
    error heartbeat on the **final attempt** (`ctx.attempt`/`maxAttempts`).
  - Cadence: daily, off-peak (e.g. `17 6 * * *`). `retries: 1`,
    `concurrency: [{scope:"fn",limit:1},{scope:"account",key:'"cron-platform"',limit:1}]`.
    Manual-trigger event `cron/anthropic-cost-report.manual-trigger`.
- [x] **Register** (the new-cron checklist, all code — verified):
  - `app/api/inngest/route.ts` — import + add `cronAnthropicCostReport` to `functions:`.
  - `cron-manifest.ts` `EXPECTED_CRON_FUNCTIONS` — add `"cron-anthropic-cost-report"`
    (this auto-updates the manual-trigger allowlist AND `function-registry-count.test.ts`).
  - `routine-metadata.ts` — add the entry (`description`, `domain: "Engineering"`,
    `ownerRole: "CTO"`, `scheduleLabel: "Daily (06:17 UTC)"`, `manualTrigger: "allowed"`).
- [x] Import convention: `from "./_cron-shared"` **relative** (not alias) —
  `cron-substrate-imports.test.ts` enforces it.
- [x] `ANTHROPIC_ADMIN_KEY` provisioning: Terraform-routed (see Infrastructure §);
  the cron reads it at runtime and self-reports benignly while the secret is
  absent, so the code merges independently of the mint.

### Phase 4 — Observability, ADR/C4, docs 📚

- [x] **Runbook** `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`:
  add a "Querying Anthropic cost markers" section with ranked SQL — per-cron
  (`GROUP BY source`), per-model (`JSONExtractString(raw,'model')`), and the daily
  total (`SOLEUR_CLAUDE_COST_DAILY`). Include the `--grep SOLEUR_CLAUDE_COST` form.
- [x] **ADR-033 amend + ADR-103 create** — see the `## Architecture Decision (ADR/C4)`
  section for the full contract (ADR-033 must reconcile I8 + I5; ADR-103 records the
  WARN + Sentry-mirror-bypass decision and the three rejected alternatives incl. the
  dispatch-hybrid rebuttal). Re-verify the next-free ordinal at `/ship` (collision
  gate); sweep the whole feature's artifacts on any renumber.
- [x] **C4**: `model.c4` — add a relationship edge `api -> anthropic "Daily org
  cost/usage report (Admin API, cost-report cron)"` (the `anthropic` system
  `:222` and `betterstack` `:262` already exist; the markers ride the existing
  `inngest -> betterstack` Vector edge `:369` — no new element). Add the edge to
  the relevant `views.c4` include if needed; run `c4-code-syntax.test.ts` +
  `c4-render.test.ts`.
- [x] Tests (`cq-write-failing-tests-before` — RED first): marker helper
  fail-open (throws in log → no throw out); cost-writer threads `source`/`model`;
  substrate `result`-event parse (fixture) + fail-open on non-JSON; cost-report
  cron classify-fatal + fail-open + registry-count; the sentry `-target` scope
  guard.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** `git grep -n 'SOLEUR_CLAUDE_COST' apps/web-platform/server/claude-cost-marker.ts`
  returns the helper, and it emits at pino **`warn`** (level 40) — `grep -c 'log.warn' apps/web-platform/server/claude-cost-marker.ts >= 1`.
- [x] **AC2** `persistTurnCost` and `persistTurnCostAwaitable` both take a
  `marker` arg; `git grep -n 'source:' ` at the **3** call sites
  (`agent-runner.ts`, `cc-dispatcher.ts`, `agent-on-spawn-requested.ts`) each
  pass a distinct `source` (`agent-runner`/`cc-soleur-go`/`leader-loop`). Count == 3.
- [x] **AC3** Marker helper is fail-open: a unit test that makes the underlying
  `log.warn` throw asserts `emitClaudeCostMarker` does **not** throw.
- [x] **AC4** Substrate emits a POSITIVE marker on EVERY exit: a `{"type":"result",…}`
  fixture yields `capture_status:"ok"` + parsed cost; a non-JSON / no-result fixture
  yields a marker with `capture_status ∈ {no-result-event,parse-error,timeout}` +
  `cost_usd:null` and **no throw** (obs P1 — never row-absence). `SpawnResult.costUsd`
  is `undefined` on the failure fixtures.
- [x] **AC4b** I8 preserved (arch P1-A): a substrate test feeds a fixture carrying a
  credit-exhaustion / auth-failure / spawn-fault marker under the new output format
  and asserts `classifyEvalFatal` still returns fatal, and the error text is present
  in `stdoutTail`/`stderrTail`; a benign max-turns fixture classifies benign. Phase-0
  live confirmation is cited in `## Research Insights`.
- [x] **AC4c** `postAnthropicMessage` emits a `cron:<name>` marker (arch P1-B): a unit
  test asserts a marker with the caller's cron source + the response `usage`/`model`
  is emitted (covers `cron-compound-promote` + credit-probe — the HTTP-transport crons
  `spawnClaudeEval` misses).
- [x] **AC5** `cron-anthropic-cost-report` is registered: it appears in
  `EXPECTED_CRON_FUNCTIONS`, in `route.ts` `functions:`, and in `routine-metadata.ts`;
  `function-registry-count.test.ts` + `routine-metadata-parity.test.ts` pass (the
  file / manifest / metadata sets are all equal).
- [x] **AC6** Cost-report cron is fail-open + classify-fatal: unit tests assert a
  401/403 → RED heartbeat, a 429/5xx → rethrow (Inngest retry), a missing
  `ANTHROPIC_ADMIN_KEY` → benign self-report (no fleet-down page) + a positive
  `SOLEUR_CLAUDE_COST_DAILY {status:"key-missing"}` marker. **AND (security F1):** a
  test asserts `getAnthropicAdminReport`'s network-catch rethrow contains neither the
  key nor request context, and its non-ok body excerpt routes through `formatTailForSentry`.
- [x] **AC6b** Daily marker curated-keys-only (security F2): a test asserts the emitted
  `SOLEUR_CLAUDE_COST_DAILY` object contains ONLY the allowlisted keys and NO
  `api_key_id` / `workspace_id` (guards against a `...row` spread regression).
- [x] **AC7** A new `sentry_cron_monitor "scheduled_anthropic_cost_report"` block
  exists in `infra/sentry/cron-monitors.tf` AND a matching `-target=` line is added to
  `apply-sentry-infra.yml` (the ~L197-219 set) AND **both** sentry scope-guard suites
  pass — `sentry-monitor-iac-parity.test.ts` (every code `SENTRY_MONITOR_SLUG` has an
  IaC monitor) AND `terraform-target-parity.test.ts` (every sentry resource is in the
  workflow `-target=` allowlist; the "#5884" section). Sweep both, not just the YAML.
- [x] **AC8** Typecheck clean: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [x] **AC9** `betterstack-query.sh` is **unchanged** (Scope 3 satisfied by
  `--grep`) and the runbook contains a "Querying Anthropic cost markers" section
  (`grep -c 'SOLEUR_CLAUDE_COST' knowledge-base/engineering/operations/runbooks/betterstack-log-query.md >= 1`).
- [x] **AC10** ADR-033 amended + ADR-103 created; C4 `model.c4` has the new
  `api -> anthropic … Admin API …` edge; `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- [x] **AC11** Phase-0 findings (CLI result shape + Admin `amount` unit) are
  pinned in `## Research Insights` with the probe output or a dated doc citation.
- [x] **AC12** `anthropic-admin-key.tf` adds a `doppler_secret` writing
  `ANTHROPIC_ADMIN_KEY` to `soleur/prd` from no-default `var.anthropic_admin_key`
  (mirrors `inngest-betterstack-token.tf`); `terraform validate` on the
  web-platform root passes.

### Post-merge (automated / verification)

- [ ] **AC13** The sentry monitor applies on merge via `apply-sentry-infra.yml`
  (`-target=sentry_cron_monitor.scheduled_anthropic_cost_report`).
- [ ] **AC14** Within 48h of deploy (after crons fire), the per-run marker is
  queryable: `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 48h --grep SOLEUR_CLAUDE_COST --limit 5`
  returns ≥1 `SOLEUR_CLAUDE_COST` row. The `SOLEUR_CLAUDE_COST_DAILY` row is expected
  only **after `anthropic-admin-key.tf` merges + the key is provisioned** (before that,
  a `{status:"key-missing"}` daily row is the correct dark signal — obs P4); do NOT
  triage its absence as a regression during the mint window.
- [ ] **AC15 (hard, obs P3)** Post-deploy Better Stack quota re-check: after the
  session markers have run for a representative window, confirm the app-container WARN
  ingest volume has NOT displaced the cron-failure lane (`betterstack-query.sh` count
  of WARN lines/day within the quota headroom). If the Phase-0 baseline underestimated
  per-turn volume, gate session markers behind sampling before this passes.

## Risks & Mitigations

- **R-A (Phase 2 blast radius + ADR-033 I8):** the output-format change affects the
  **15** `spawnClaudeEval` crons' local journald log format (JSON vs text). *The
  load-bearing risk is NOT journald readability but the I8 classifier* (`classifyEvalFatal`
  reads `stdoutTail`/`stderrTail` for credit/auth/spawn-fault — the #5674 fix). *Mitigation:*
  Phase 0 hard-gates that I8 classification survives + the substrate extracts the
  result text into `stdoutTail` so the Sentry diagnostic + I8 tail stay readable;
  capture is fail-open with a POSITIVE `capture_status` marker on every exit (not
  silence). Reconciled in the ADR-033 amendment. **Scoped-advisor-consult +
  plan-review focus this phase.**
- **R-B (output-format volume):** *default `--output-format json`* (single final
  object) is the low-volume choice; `stream-json --verbose` (high event volume, bounded
  tail can evict the terminal error) is the fallback only if a live stream proves
  necessary — the `routine_run_progress` heartbeat already covers liveness.
- **R-C (WARN-lane + quota coupling — obs P3):** cost markers ride the SAME 3 GB/mo
  Better Stack quota AND the SAME WARN+ Vector lane whose purpose is preserving the
  cron-FAILURE reason — so a session-marker volume UNDER-estimate could evict
  cron-failure diagnostics, not just cost data. Session markers are per-turn; "low
  volume" is a hypothesis, NOT a mitigation. *Mitigation (hardened):* Phase 0
  MEASURES actual per-turn volume before merge; AC15 is a HARD post-deploy quota
  re-check (not advisory); gate session markers behind sampling/debounce if the
  measured volume is non-trivial. Baseline context: host metrics dominate the quota
  today (2026-06-10 quota-diagnosis learning), leaving headroom, but that is to be
  confirmed by measurement, not assumed.
- **R-D (`amount` unit misread):** treating cents as dollars (or vice-versa) in
  the daily marker mis-reports spend 100×. *Mitigation:* Phase 0 pins the unit
  live before coding; a unit test asserts the parse against the pinned fixture.
- **R-E (Admin key privilege):** the admin key is org-wide **read-only** billing
  metadata. *Correction (security F3):* it is NOT cron-isolated — `ANTHROPIC_ADMIN_KEY`
  in `soleur/prd` is `process.env`-readable by the ENTIRE web-platform process (same
  surface as `ANTHROPIC_API_KEY` + ~116 other secrets; `inngest-host.tf:79-85`). The
  real blast-radius control is the key's **read-only scope** (cannot spend, cannot
  read conversations), not env isolation. *Mitigation:* never logged (the new
  `getAnthropicAdminReport` transport MUST redact like `postAnthropicMessage` —
  security F1); `sk-ant-admin01-…` is already covered by `API_KEY_RE`
  (`lib/safety/redaction-allowlist.ts:71`).
- **R-G (tfstate cleartext — security F4, inherited):** `doppler_secret` +
  no-default-var writes the org-wide admin key into `terraform.tfstate` in cleartext
  (Approach B, mirrors `inngest-betterstack-token.tf`). Confirm the state backend is
  encrypted + access-restricted (pre-existing R2 control); treat any state exposure
  as an admin-key-rotation trigger; `ignore_changes=[value]` leaves the prior value
  in state after a Doppler-side rotation until the next create/replace.
- **R-H (Sentry breadcrumb pollution — arch P2-Q4):** WARN+ pino lines auto-mirror
  to Sentry breadcrumbs (`logger.ts:123-125`). *Mitigation:* `emitClaudeCostMarker`
  uses a dedicated pino instance WITHOUT the `mirrorToSentry` logMethod hook, so cost
  markers do not evict genuine diagnostics from the shared-scope ring buffer.
- **R-F (leader-loop `MODEL_PRICING` gap):** the leader loop derives cost from
  `MODEL_PRICING[leaderModule.model] ?? {all-zeros}`; an unpriced model yields
  cost 0 in the marker. *Mitigation:* surface the same value the DB already
  stores (parity, not a new bug); note the zero-fallback in the marker's model
  field so a 0-cost sonnet/haiku is distinguishable from an unpriced model.

## Domain Review

**Domains relevant:** Engineering (CTO), Finance (advisory).

### Engineering (CTO)
**Status:** to-review (plan-review panel + scoped-advisor consult cover the
architecture; Phase 2 substrate change + ADR-033 amendment are the load-bearing
CTO concerns). **Assessment:** the substrate output-format change is the only
non-trivial architectural decision (blast radius across the cron fleet); it is
fail-open and ADR-recorded. New-cron + new-secret follow established patterns
(credit-probe, inngest-betterstack-token).

### Finance (advisory)
**Status:** advisory-only. **Assessment:** this feature *enables* future
budget-analyst / cfo work (per-model, per-surface spend) but creates no new
finance obligation or recurring vendor expense in THIS PR (the Anthropic key
already exists and is already billed). No `wg-record-recurring-vendor-expense`
trigger — no new vendor, no new spend.

### Product/UX Gate
**Not applicable.** No `## Files to Create` / `## Files to Edit` path matches a
UI-surface term (`components/**`, `app/**/page.tsx`, `app/**/layout.tsx`). The
one `app/api/inngest/route.ts` edit is an HTTP registration list, not a UI
surface. Tier: **NONE**.

## Infrastructure (IaC)

### Terraform changes
- **New** `apps/web-platform/infra/anthropic-admin-key.tf` — a `doppler_secret`
  resource writing `ANTHROPIC_ADMIN_KEY` into `soleur/prd`, value from a **no-default**
  `var.anthropic_admin_key` sourced from Doppler `prd_terraform` (Approach B —
  only the one admin key enters `terraform.tfstate`). **Direct mirror of the
  existing `inngest-betterstack-token.tf`** (same `ignore_changes=[value]`,
  `visibility="masked"`, no-default `TF_VAR` pattern) — the secret write is the
  Terraform resource itself.
- `apps/web-platform/infra/sentry/cron-monitors.tf` — new
  `resource "sentry_cron_monitor" "scheduled_anthropic_cost_report"` (name
  `scheduled-anthropic-cost-report`, `schedule={crontab="17 6 * * *"}`,
  `checkin_margin_minutes=60`, `max_runtime_minutes=15`, `failure_issue_threshold=1`,
  `recovery_threshold=1`, `timezone="UTC"`) — mirrors `scheduled_domain_model_drift`.
- `.github/workflows/apply-sentry-infra.yml` — add `-target=sentry_cron_monitor.scheduled_anthropic_cost_report`
  to the `-target=` set (~L197-201); sweep the sentry `-target` scope-guard test.
- **Sensitive variable:** `TF_VAR_anthropic_admin_key` — no default
  (`hr-tf-variable-no-operator-mint-default`); value lives in Doppler
  `prd_terraform` (the TF runner's var source), populated from the console-minted
  admin key.

### Apply path
- **Sentry monitor:** auto-applies on merge via `apply-sentry-infra.yml`
  (`-target`-scoped).
- **`anthropic-admin-key.tf`:** `apply-web-platform-infra.yml` auto-applies on
  `infra/*.tf` merge and resolves **all** root vars before `-target` pruning — a
  no-default `var.anthropic_admin_key` absent from `prd_terraform` would fail the
  WHOLE merge-apply (Sharp Edge: operator-mint-tf-var-must-sequence-before-auto-applied-iac).
  **Sequencing:** the KEY MINT is `automation-status: UNVERIFIED — /work MUST run
  a Playwright attempt at console.anthropic.com before any handoff` (a vendor
  dashboard mint under an authenticated session is presumptively Playwright-automatable).
  Therefore **split**: the code (Phases 1–4, no `*.tf` for the admin key) merges
  first — the cost-report cron self-reports `anthropic-admin-key-missing` benignly
  until the key lands; `anthropic-admin-key.tf` + the `TF_VAR_anthropic_admin_key`
  provisioning into `prd_terraform` land in a follow-up that merges **after** the
  mint. The sentry monitor `.tf` is unaffected (it has no new var) and can ship
  with the code PR.

### Distinctness / drift safeguards
`dev != prd`: the admin key + cost-report cron are prd-only; `dev` is not
provisioned with an admin key (the dark path self-reports key-missing benignly).
`ignore_changes=[value]` on the `doppler_secret` (rotation managed at Doppler,
not this file — mirrors `inngest-betterstack-token.tf`).

### Vendor-tier reality check
Better Stack free tier (3 GB/mo logs): the WARN markers are low-volume (R-C).
Anthropic Admin API: no documented rate limit; `cost_report` is daily-bucket
only (`bucket_width="1d"`) — the cron respects that granularity.

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor "scheduled-anthropic-cost-report" (daily check-in) +
        the SOLEUR_CLAUDE_COST_DAILY marker appearing in Better Stack once/day.
  cadence: daily (06:17 UTC); check-in margin 60 min.
  alert_target: Sentry (RED on missed check-in or classified-fatal 401/403).
  configured_in: infra/sentry/cron-monitors.tf + the cron's postSentryHeartbeat.
error_reporting:
  destination: Sentry via reportSilentFallback / mirrorWarnWithDebounce (existing
               observability helpers); pino WARN mirrored per logger.ts.
  fail_loud: a fatal admin-key auth failure (401/403) flips the monitor RED; a
             missing key self-reports (op=anthropic-admin-key-missing) without a
             false fleet-down page.
failure_modes:
  - mode: session/cron marker emit throws
    detection: cannot — emitClaudeCostMarker is try/caught (fail-open by design)
    alert_route: none (intentional; observability must never break a run)
  - mode: substrate result-event parse fails / old text format
    detection: SpawnResult.costUsd is undefined so the marker is skipped; the
               ABSENCE of a cron's SOLEUR_CLAUDE_COST row in Better Stack is
               itself the in-surface signal, queryable per-cron
    alert_route: none inline; surfaced by a per-cron marker-presence query
  - mode: Admin API auth failure (bad/revoked admin key)
    detection: 401/403 classified fatal in the cost-report cron
    alert_route: Sentry monitor RED (scheduled-anthropic-cost-report)
  - mode: Admin API transient (429/5xx/net)
    detection: rethrow gives an Inngest retry; error heartbeat gated on final attempt
    alert_route: Sentry RED only after retries exhaust on the final attempt
logs:
  where: Better Stack (app_container source, WARN+) via existing Vector path;
         query with scripts/betterstack-query.sh --grep SOLEUR_CLAUDE_COST.
  retention: 3-day hot window (Better Stack source config); the daily marker + the
             Admin API remain the durable reconciliation ground-truth.
discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 48h --grep SOLEUR_CLAUDE_COST --limit 5
  expected_output: >=1 JSONEachRow line carrying source/model/cost_usd (per-run)
                   and >=1 SOLEUR_CLAUDE_COST_DAILY row after the daily cron fires.
```

Affected-surface note (2.9.2): the cron worker + the claude subprocess are blind
surfaces; the marker itself IS the in-surface probe (emitted from the substrate
after the child exits, carrying `source`/`model`/`cost_usd` — the fields that
discriminate per-cron/per-model attribution in one event).

## Architecture Decision (ADR/C4)

### ADR
- **Amend ADR-033** (`…-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`
  — the colliding-ordinal file; target by full filename, arch P3): the substrate now
  requests a structured output format (`json`, default) and parses the `result` event
  for `total_cost_usd`/`usage`/model. `## Decision` MUST explicitly reconcile **I8**
  (`classifyEvalFatal` still classifies credit/auth/spawn-fault + benign max-turns
  under the new format — Phase 0 hard-gate) and **I5** (deterministic capture —
  `SpawnResult` gains `costUsd`/`usage`/`model`; the FR10 memoized-step test stays
  green). `## Consequences`: the local-journald readability trade-off.
- **Create ADR-103** (provisional ordinal; ADR-102 is highest, git-history-verified):
  the `SOLEUR_CLAUDE_COST` marker convention (pino WARN via a Sentry-mirror-bypassing
  logger so the existing Vector `app_container_warn_filter` ships it without polluting
  breadcrumbs) + the Admin Cost/Usage API integration. **Rejected alternatives to
  record:** (a) *relax the global Vector INFO filter* — rejected (quota); (b) *a
  targeted Vector transform matching `SOLEUR_CLAUDE_COST` at INFO* — rejected (still a
  `vector.toml` deploy for no gain over WARN); (c) *Inngest→GHA dispatch-hybrid for
  the Admin key* (per the 2026-06-02 credential-heavy-cron learning) — rejected: the
  admin key is read-only, execution is two trivial HTTP GETs, and the credit-probe
  precedent already calls Anthropic direct from the app container (the dispatch-hybrid
  learning's own scope-note warns against mis-citing it for this inverse workload).
  Note the sanctioned silent-`catch` exemption for `emitClaudeCostMarker`. Re-verify
  next-free ordinal at `/ship`; sweep all feature artifacts on any renumber.

### C4 views
- `model.c4`: add edge `api -> anthropic "Daily org cost/usage report (Admin API,
  cost-report cron)" { technology "HTTPS" }`. **Enumeration checked against all
  three .c4 files:** external human actors — none new; external systems —
  `anthropic` (`model.c4:222`) and `betterstack` (`:262`) both already modeled;
  data stores — none new; access relationships — the cost markers ride the
  existing `inngest -> betterstack` Vector edge (`:369`), so the ONLY new edge is
  the platform→Anthropic Admin read. Add to the Container view include in
  `views.c4` if the edge does not render.

### Sequencing
No soak-gated status flip; the ADRs describe the target state shipped in this PR.

## Open Code-Review Overlap

2 open code-review issues touch `agent-runner.ts` but on unrelated concerns:
- **#3454** (expose `pdf_metadata` as agent MCP tool) — **Acknowledge.** Different
  surface (MCP tool parity, not cost). Remains open.
- **#3242** (`tool_use` WS event lacks raw name field) — **Acknowledge.** Different
  surface (WS event shape). Remains open.

Neither touches the `persistTurnCost` call site (`:2359`) this plan edits; no
fold-in, no double-count.

## Test Scenarios

- Marker helper: throws-in-log → no throw out (fail-open); emitted object carries
  the `SOLEUR_CLAUDE_COST` discriminator + all 8 fields.
- cost-writer: each of the 3 callers threads a distinct `source` + a model.
- Substrate: `result`-event fixture parses cost; non-JSON fixture → undefined + no
  throw; a cron whose spawn omits `--output-format` gets the injected flag.
- cost-report cron: classify-fatal (401/403 RED, 429 rethrow, key-missing benign);
  single consolidated `step.run`; registry-count equality; `_cron-shared` relative import.
- Sentry `-target` scope guard: the new monitor is covered by every guard suite.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or `TBD` fails
  `deepen-plan` Phase 4.6 — this one is filled (threshold: none + reason).
- The sentry `-target=` allowlist is asserted by ≥3 artifacts (the jq/filter, its
  counter test, AND a separate scope-guard suite with a different name stem) —
  `git grep -ln 'sentry_cron_monitor\|-target=' apps/web-platform/test/ .github/ scripts/`
  and update EVERY hit, not just `apply-sentry-infra.yml`.
- `EXPECTED_CRON_FUNCTIONS` auto-derives the manual-trigger allowlist — do NOT add
  a second hardcoded allowlist entry (`function-registry-count.test.ts` (e) enforces).
- `_cron-shared` import MUST be relative (`from "./_cron-shared"`), not the `@/`
  alias — `cron-substrate-imports.test.ts` enforces it.
- Do NOT re-run `claude --print` without `--output-format` after Phase 0 pins the
  flag — the whole cron half depends on the JSON `result` event existing.
- The Admin `cost_report` cannot group by model/api_key_id — that split lives in
  `usage_report/messages`. Pull both; don't assume the cost endpoint alone gives
  per-model $.
- The `anthropic-admin-key.tf` no-default var will fail the WHOLE
  `apply-web-platform-infra.yml` merge-apply if `TF_VAR_anthropic_admin_key` is
  absent from `prd_terraform` — split the IaC to land after the mint (Apply path §).

## Research Insights

- **Session choke point:** `cost-writer.ts` `persistTurnCost` (`:98`) /
  `persistTurnCostAwaitable` (`:299`), called from `agent-runner.ts:2359`,
  `cc-dispatcher.ts:4002`, `agent-on-spawn-requested.ts:583`.
- **Cron substrate:** `_cron-claude-eval-substrate.ts` `spawnClaudeEval` (`:737`,
  spawn at `:818`, stdout line handler `:830`, `SpawnResult` `:22`). No cost
  accumulated today.
- **Marker ship path:** Vector `app_container_journald` Source 3 (`vector.toml`),
  filter `app_container_warn_filter` = pino level ≥ 40. Query via
  `betterstack-query.sh --grep` (already supports `raw LIKE`). Runbook
  `betterstack-log-query.md:85-111`.
- **Credit-probe template:** `cron-anthropic-credit-probe.ts` (registration,
  classify-fatal, heartbeat). `_cron-shared.ts` transport `postAnthropicMessage`
  (`:547`), `AnthropicApiError` (`:536`), `formatTailForSentry` (`:1060`),
  `postSentryHeartbeat` (`:277`), `finalizeOutputAwareHeartbeat` (`:435`).
- **Models:** `model-tiers.ts` — `EXECUTION_MODEL` (sonnet), `AUDIT_MODEL`
  (`claude-opus-4-8`). Leader loop uses `MODEL_PRICING[leaderModule.model]`
  (sonnet|haiku).
- **New-cron surfaces:** `route.ts:120` `functions:`, `cron-manifest.ts`
  `EXPECTED_CRON_FUNCTIONS`, `routine-metadata.ts`, `infra/sentry/cron-monitors.tf`,
  `apply-sentry-infra.yml:197-201`. Secret pattern: `inngest-betterstack-token.tf`.
- **PHASE-0 PINNED AT /work (2026-07-09):**
  - **(a) `claude -p --output-format json` result shape — LIVE PROBE (confirmed).**
    A single final JSON object: `{"type":"result","subtype":"success","is_error":false,
    "api_error_status":null,"result":"<assistant text>","total_cost_usd":<number>,
    "usage":{"input_tokens":N,"output_tokens":N,"cache_read_input_tokens":N,
    "cache_creation_input_tokens":N,…},"modelUsage":{"claude-opus-4-8[1m]":{…}},
    "session_id":"…"}`. Load-bearing pins: `total_cost_usd` is TOP-LEVEL; the token
    field names match `cost-writer`'s `UsageDeltas` EXACTLY (`input_tokens`,
    `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`); the
    **model id is the KEY of `modelUsage`** — there is NO top-level `model` field.
    `--output-format json` emits a single result line (low log volume) — chosen over
    `stream-json --verbose`.
  - **I8 HARD-GATE (reconciled, unit-pinned).** `classifyEvalFatal` reads
    `stdoutTail + stderrTail`. Under `--output-format json`, stderr is UNCHANGED (an
    Anthropic API error still prints there), AND the substrate extracts the result
    event's `.result` text (which carries the API error message on an error run) INTO
    `stdoutTail` via `parseClaudeResultLine`. A credit-exhaustion / auth-failure /
    spawn-fault fixture still classifies fatal; a benign max-turns fixture stays benign
    (AC4b unit tests in `cron-claude-eval-substrate.test.ts`). I8 survives the format
    change. Recorded in ADR-033 I9.
  - **(b) Admin `cost_report.amount` unit — UNVERIFIED (no admin key in the /work env).**
    The live probe requires the minted admin key (the sequenced IaC follow-up). Documented
    shape: `data[].results[].amount` as a decimal STRING alongside `currency:"USD"` — the
    code treats it as **dollars** (`parseCostReportTotal`), with a prominent code comment +
    a fixture-pinned unit test; the follow-up that mints the key MUST run the live probe and,
    if cents, divide by 100 + update the fixture (plan R-D). Admin API contract confirmed via
    docs: `GET /v1/organizations/cost_report` (`bucket_width="1d"`), `GET /v1/organizations/
    usage_report/messages` (`group_by[]=model`), auth `x-api-key: sk-ant-admin01-…` +
    `anthropic-version: 2023-06-01`.
