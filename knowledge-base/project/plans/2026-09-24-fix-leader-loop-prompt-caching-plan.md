---
title: "fix: leader loop prompt caching — drop per-tool breakpoints, cache the growing conversation"
date: 2026-09-24
slug: fix-leader-loop-prompt-caching
branch: feat-one-shot-leader-loop-prompt-caching
type: fix
priority: p1-high
domain: engineering
brand_survival_threshold: aggregate pattern
related: [8611, 8635]
lane: cross-domain
---

# fix: leader loop prompt caching

The spec has no valid `lane:` (there is no `spec.md` for this one-shot branch), so it defaulted to cross-domain (TR2 fail-closed).

## Overview

The BYOK leader loop in `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts`
marks the system block and every tool with an explicit cache breakpoint. Classes with four or
more tools exceed the Messages API's four-breakpoint ceiling, so their turns are rejected, and the
marked prefix is too short to cache anyway. The fix moves caching to where the loop actually
repeats bytes: the conversation that grows across up to eight calls per spawn.

## Research Insights

### Premise Validation (Phase 0.6, run 2026-09-24)

Each claim in the brief was re-checked against the worktree, which is at `origin/main` plus planning artifacts.

| Claim | Check | Result |
|---|---|---|
| The call puts `cache_control` on the system block and on every tool | Read `agent-on-spawn-requested.ts`, the `turn-${n}-claude` step (`client.messages.create`, currently lines 654-669) | **Holds.** `system[0].cache_control` plus `tools.map(t => ({...t, cache_control}))` |
| Tool counts are 5 / 3 / 2 / 2 / 1 | Loaded `LEADER_PROMPTS` with `npx tsx` (scratch script) and printed `tools.length` per class | **Holds.** security.cve_alert=5 (6 breakpoints), knowledge.kb_drift=3 (4), engineering.pr_review_pending=2 (3), triage.p0p1_issue=2 (3), engineering.ci_failed=1 (2) |
| The kill switch is empty in prd | `doppler secrets get LEADER_CLASSES_DISABLED -p soleur -c prd --plain` | **Holds, stronger than stated.** The secret *does not exist* in prd, so `process.env.LEADER_CLASSES_DISABLED ?? ""` is empty and every class is live. No other source sets it (`git grep` finds only the reader) |
| The marked prefix is below the minimum cacheable length | Measured characters per class: system prompt 410-696, tools JSON 372-1658, so roughly 220-670 tokens at about 3.5 characters per token | **Holds as an estimate.** Minimums: 1024 tokens on `claude-sonnet-5`, 4096 on `claude-haiku-4-5` (claude-api skill `shared/prompt-caching.md`, "Minimum cacheable prefix"). An exact `count_tokens` figure was not taken: this environment has no Anthropic credential (`ant` not installed, no key in Doppler `dev`) |
| The SDK accepts top-level `cache_control` | `apps/web-platform/package.json` pins `@anthropic-ai/sdk ^0.93.0` and the lockfile resolves `0.93.0`. `node_modules/@anthropic-ai/sdk/resources/messages/messages.d.ts`, `interface MessageCreateParamsBase`, declares `cache_control?: CacheControlEphemeral \| null` ("Top-level cache control automatically applies a cache_control marker to the last cacheable block in the request") | **Holds.** No SDK bump, no cast needed on that field |
| #8635 is open and watches this loop | `gh issue view 8635` | **Holds.** OPEN, follow-through. Its probe is `scripts/followthroughs/anthropic-double-bill-8611.sh`, which reads `SOLEUR_CLAUDE_COST` markers (`source`, `turn`, `attempt`). This plan changes none of those fields and does not touch the probe |
| No post-deploy leader-loop turn has run | Not independently re-measured. It is consistent with #8635 still reporting NOT YET | Taken as given. It does not change the fix |

**New premise found during validation. It changes scope (see Phase 2).** `classifyAnthropicOrLeaseError` branches on `err.status`. In production the error reaching the handler's `catch` has already been through Inngest's step-failure path: `node_modules/inngest/components/execution/v1.js` rejects with `new StepError(opId.id, result.error)`, and `StepError` (`node_modules/inngest/components/StepError.js`) keeps only `name`, `message`, `stack` and `cause`. The following was reproduced in `apps/web-platform`: an SDK `APIError.generate(429, …)` goes through Inngest's `serializeError` and becomes a `StepError` with `name="Error"`, `status=undefined`, `message="429 {…}"`. The Anthropic SDK's own error `.name` is also `"Error"` for every class (`new BadRequestError(...).name === "Error"`). So in production **every** Anthropic API error, including 429, is classified `anthropic_timeout`. The unit tests pass only because the mock `step.run` re-throws the raw SDK error in-process. The 400 this plan removes would have reached the founder as "Anthropic API timeout. Retry usually works." with a Retry button, and `retries: 3` (`createFunction` config) re-sends the rejected request three more times first. A second measurement, taken during the advisor consult, widens this: Inngest's `serialize-error-cjs` 0.1.4 also rewrites every **custom** `name` to `"Error"`. So `name === "ByokLeaseError"` is dead in production too. Plan-review correction (Kieran): Inngest's own `serializeError` wrapper keeps the string `cause`. So lease errors with cause `fetch_failed`, `decrypt_failed` or `escape` *do* classify correctly after the round-trip. What falls through to `anthropic_timeout` in production is every Anthropic API status (429 included), `MissingByokKeyError`, and lease `subscription_limit`.

### Property List (Phase 0.6b)

- **P1**: No leader-loop request is rejected for exceeding the API's cache-breakpoint cap, for any class in `LEADER_PROMPTS` and on any turn.
- **P2**: Once a spawn's prompt clears the model's minimum cacheable length, calls 2..N read the prior conversation from cache instead of paying full input price for it.
- **P3**: Cost attribution stays exact under caching. The 5-minute-TTL write rate (1.25x) and the read rate (0.1x) in `MODEL_PRICING` match what the request asks for.
- **P4** (fold-in): A request the API rejects is reported as a rejection (or as a key problem for 401 and 403), not as a timeout. It is not retried, because a retry fails the same way.
- **P5** (non-goal, preserved): The other direct Messages API callers stay uncached.

### Cut List (Phase 0.6b)

- **Per-tool `cache_control`.** It was meant for P2, but tools and system together are below the minimum, and the render order is tools → system, so the system marker already covers the tools. It buys nothing and it breaks P1. **Cut.**
- **1-hour TTL.** It would buy reuse across gaps longer than 5 minutes, but calls within a spawn are seconds apart, and it would silently break P3 (`MODEL_PRICING` comment, "if any call here ever passes `ttl: \"1h\"` this row silently under-attributes"). **Cut.**
- **Intermediate lookback breakpoints.** They would buy P2 for turns that append more than 20 positions. A turn appends one assistant message (text plus one run of `tool_use` blocks, which counts as one position) and one user message (one run of `tool_result` blocks, one position), so about 3-4 positions against a 20-position lookback. **Cut.**
- **The explicit system-block marker.** It buys cross-spawn reuse of the tools+system prefix. That is inert today because the prefix is below the minimum. **Kept.** The brief specifies it, it costs one breakpoint slot and no money, and it is the recommended "robust combination for agent loops" (claude-api `shared/prompt-caching.md`, "Automatic vs explicit breakpoints"). It starts paying if a class's prompt grows past 1024 tokens.

### Value proposition (Phase 0.6c)

The main reason for this change is correctness: P1 fixes a deterministic 400 on a live class. The cost saving (P2) is secondary and **not measured at plan time**. There is no Anthropic credential here, and no post-deploy leader turn has run. It is measured after deploy with the `discoverability_test` query in `## Observability`, which counts leader-loop turns ≥ 2 whose cost marker has `cache_read_input_tokens > 0`. Expected shape: the saving goes mostly to `security.cve_alert` and `engineering.pr_review_pending` (Sonnet, PR diffs and blob contents in the prompt, several turns). The Haiku classes rarely clear 4096 tokens, and for them automatic caching is a free no-op. A spawn that ends on turn 1 with a prompt of 1024 tokens or more pays a 25% input premium on that one call, because it writes a cache entry it never reads back. Every class's tool allowlist is non-empty and the prompts ask for an artifact, so typical spawns run at least 2 calls, which is the break-even point.

### Relevant files

- `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts`: `MODEL_PRICING` comment block (starts "Per-model unit pricing in USD per token"); the `turn-${n}-claude` step's `client.messages.create`; `classifyAnthropicOrLeaseError`; `FailureReason` union; `createFunction` config (`retries: 3`).
- `apps/web-platform/server/inngest/leader-prompts/{index,constants}.ts` and the five class modules. System prompts and tool defs are static module constants. `userPromptTemplate` is per-spawn and sits after the system block, so the prefix is safe. Changing only the request packaging needs **no** `promptVersion` bump (index.ts header: bump on edits to systemPrompt / userPromptTemplate / tools).
- `apps/web-platform/test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts`: the full harness (a `vi.mock` for supabase, octokit, lease, cost-writer and `@anthropic-ai/sdk` via `anthropicCreateSpy`; `makeStep` memoizes and re-throws in-process). No current test asserts on `cache_control`, so nothing goes red from removing it.
- `apps/web-platform/components/dashboard/failure-reason-copy.ts` (`FailureReason` union plus `FAILURE_REASON_COPY: Record<…>`), `apps/web-platform/test/components/dashboard/failure-reason-copy.test.ts` (`ALL_REASONS` list), `apps/web-platform/test/components/dashboard/today-card-state-matrix.test.ts` (the CPO-2 "no raw reason leaks" list). `action_sends.failure_reason` is plain `text` with no CHECK constraint (migration 064), so adding a reason needs no migration.
- `knowledge-base/engineering/architecture/decisions/ADR-042-anthropic-sdk-inside-inngest-leader-loop.md` §I5 says "markers on the system prompt + tool definitions". This change departs from that, so the ADR is amended (see `## Architecture Decision`).
- Out of scope, confirmed: `server/soleur-go-runner.ts` (Agent SDK path, one marker on a content block, not the Messages API), `scripts/spike/cache-control-forwarding.ts` (spike), and compound-promote, weekly-release-digest, domain-router and email-triage (deliberately uncached per the 2026-09-23 spend work).

### External facts (claude-api skill, `shared/prompt-caching.md`, cached 2026-06-24; SDK types cross-checked locally)

- Render order is tools → system → messages. A marker on the last system block caches tools and system together.
- A request may carry at most **4** breakpoints. The top-level automatic breakpoint **uses one of the 4 slots**. It works alongside explicit markers, with two documented 400s: all 4 slots already taken by explicit markers, or an explicit marker on the *last* block whose TTL differs from the top-level one. Neither applies here: there are 2 slots in use, and the explicit marker is on the system block, not the last block.
- Automatic placement goes on the last cacheable block and moves forward as the conversation grows. If the last block is not eligible it walks backward. Each breakpoint looks back at most 20 positions, and runs of consecutive `tool_use` blocks and of `tool_result` blocks each count as one.
- The default TTL is 5 minutes for both. A read refreshes the timer at no cost. Writes cost 1.25x (5m) and reads 0.1x.
- Thinking is not enabled on the leader loop, so the "thinking toggles invalidate the messages cache" row does not apply.
- Automatic caching is available on the Claude API. Only the legacy Bedrock integration rejects it, and BYOK uses the first-party API (`new Anthropic({ apiKey })`).

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-07-09-derive-db-object-sets-from-live-catalog-not-migration-grep.md`: derive the class population from `LEADER_PROMPTS` at runtime, never from a literal list.
- `knowledge-base/project/learnings/2026-07-19-a-mutation-battery-that-passes-can-still-leave-the-central-mechanism-untestable.md`: fixture *shape* diversity is its own coverage axis. Here the shapes are a 1-tool class, a 5-tool class, a multi-turn request, and a production-shaped `StepError` rather than a raw SDK error.
- `knowledge-base/project/learnings/integration-issues/2026-09-23-cloudflare-524-made-every-long-inngest-step-run-twice-and-commit-nothing.md`: the reason the other direct callers stay uncached (no reuse within the TTL, or below Haiku's minimum).
- ADR-042 I1/I2 (per-turn `step.run`, lease opened inside the step) are unchanged. The request shape changes inside the same step.
- ADR-108 (cost markers): the marker already carries `cache_read_input_tokens` and `cache_creation_input_tokens` (`server/claude-cost-marker.ts`), so caching becomes observable after deploy without new telemetry.

### Functional overlap (Phase 1.5b)

`soleur:engineering:discovery:functional-discovery` found no community artifact that overlaps (the closest was generic prompt-caching guidance). Nothing was installed. Community discovery (Phase 1.5) was skipped: the change is in TypeScript, which built-in agents already cover.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "cve_alert sends 6 breakpoints and every one of its leader turns 400s" | Confirmed (5 tools + 1 system). knowledge.kb_drift sits at exactly 4, the limit | Phase 1 fixes both. The Guard 1 test asserts ≤ 4 per class, with the class list read from `LEADER_PROMPTS` |
| The kill switch "is empty in Doppler prd" | The secret is **absent**, which has the same effect | No change. Recorded above |
| A 400 is a failed turn, full stop | A 400 is **misreported** as `anthropic_timeout` ("Retry usually works"), and retried 3× first. In production every Anthropic API error, 429 included, plus `MissingByokKeyError`, is classified as a timeout. `StepError` keeps `message`, `stack` and `cause` but drops `status` and custom `name` | Phase 2 fold-in. The pre-commit filing gate refused a deferral issue: the fix sits inside the inline threshold (≤100 lines, ≤4 files, per ADR-131) |
| ADR-042 §I5 prescribes markers on the system prompt and the tools | This change departs from it | ADR-042 §I5 amended in this PR (Phase 3) |

## Problem Statement

1. **Latent 400 (P1).** `security.cve_alert` sends 6 breakpoints, and the API caps a request at 4. Every turn of a live class is rejected. `knowledge.kb_drift` is at exactly 4, so adding one more tool to it would do the same.
2. **No caching where it matters (P2).** The only markers sit on a prefix that is too short to cache. The part that repeats (the whole conversation, re-sent on each of up to 8 calls, including PR diffs and blob contents) is never cached.
3. **Misreported rejections (P4).** Every Anthropic API error reaches the handler as an Inngest `StepError` with `name: "Error"` and no `status`, so `classifyAnthropicOrLeaseError` returns `anthropic_timeout` for all of them. A founder with no key configured (`MissingByokKeyError`) gets the same result. A deterministic 400 also burns `retries: 3` before the handler sees it.

## Proposed Solution

### Phase 1 — Request shape (P1, P2, P3)

In the `turn-${n}-claude` step of `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts`:

```ts
// apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts (turn-${n}-claude step)
const sdkResult = (await client.messages.create({
  model: leaderModule.model,
  max_tokens: LEADER_MAX_TOKENS,
  // Automatic caching: the API places this breakpoint on the last cacheable
  // block and advances it every turn, so calls 2..N read the conversation so
  // far from cache. It uses 1 of the request's 4 breakpoint slots. 5-minute
  // default TTL on purpose; MODEL_PRICING's cache-write rate assumes it.
  cache_control: { type: "ephemeral" },
  system: [
    {
      type: "text",
      text: leaderModule.systemPrompt,
      // The single explicit marker. Tools render before system, so this covers
      // the tool definitions too. Do NOT add per-tool markers: security.cve_alert
      // has 5 tools and 5 + 1 + 1 exceeds the 4-breakpoint cap (the request 400s).
      cache_control: { type: "ephemeral" },
    },
  ],
  tools: leaderModule.tools as never,
  messages: messages as never,
})) as unknown as AnthropicTurnResult;
```

- Keep the `as never` cast on `tools`. `AnthropicToolDef` is the repo's own type, and it was already cast before this change. Top-level `cache_control` needs no cast, because `MessageCreateParamsBase` declares it in SDK 0.93.0.
- Update the `MODEL_PRICING` comment block's TTL sentence (currently "(Checked: no `ttl` is passed today, so the 5m default applies.)") so it names **both** markers, the system block and the top-level request field, and points to the Guard 1 test that pins "no `ttl`". Rates, keys and the rest of that block stay as they are.
- `LEADER_MAX_TURNS × LEADER_MAX_TOKENS` ("≈$0.33 worst-case", constants.ts) is an **output-token** bound. Caching does not change output pricing, so that figure and `PER_SPAWN_COST_CEILING_CENTS` stay unchanged. Say so in one line in the plan's PR body, not in code.

### Phase 2 — Error classification fold-in (P4)

**Design: classify inside the step, where the live error still has its `status` and `name`, and *return* a deterministic rejection instead of throwing it.** Measured in `apps/web-platform` against `inngest` 3.54.2: a step's thrown error reaches the handler as an Inngest `StepError`. Inngest serializes the error with `serialize-error-cjs` 0.1.4, which rewrites every custom `name` to `"Error"` (so a `ByokLeaseError`, or a `NonRetriableError` subclass named anything, arrives as `"Error"`) and drops `status` and string `cause`. Only `message` and `stack` survive. A step's **return value**, by contrast, is memoized as-is: it survives replay untouched, and Inngest never retries a step that returned. So a deterministic failure is returned, not thrown. The earlier designs this replaces were dropped after review:

- Parsing the SDK's `"<status> "` message prefix in the handler depends on an SDK implementation detail.
- A custom-named error class used as the carrier is falsified by the measurement above: the name does not survive.
- A `[leader-failure:<reason>]` message tag plus `NonRetriableError` needs a parser, a membership check and a serializer fixture that a returned value makes unnecessary (plan-review, DHH).

1. **Widen `classifyAnthropicOrLeaseError`**, which still sees the live error in-step. Order:
   - The lease checks come first, as they are today.
   - `status === 429` → `anthropic_rate_limited`.
   - `status` 401/403 → `byok_lease_unavailable`. The founder's key was rejected, and the existing copy ("Verify your API key in Settings → BYOK") is the right action.
   - Any other 4xx **except 408, 409 and 429** → **new** `anthropic_request_rejected`. That covers 400, 402 `billing_error`, 404, 413, 422 and anything Anthropic adds later. 408 and 409 are ones the SDK itself treats as transient.
   - Everything else → `anthropic_timeout`, as today: 5xx/529, 408/409, connection and timeout errors, and non-Anthropic throws such as a cost-write failure.
2. **Return deterministic failures from the step.** Inside the lease callback of the `turn-${n}-claude` step, wrap the pre-billing statements in `try/catch`: `lease.getRestApiKey()`, `new Anthropic(...)` and `client.messages.create(...)`. The `try` ends where `create` resolves. Usage pricing and `persistTurnCostAwaitable` stay **outside** it, so nothing thrown after the founder has been billed can be taken for a rejection (Kieran P2-4). In the catch, a failure is **deterministic** when either:
   - `const status = (err as { status?: unknown }).status` is a number in the 4xx range other than 408, 409 or 429; or
   - `(err as { name?: unknown }).name === "MissingByokKeyError"`, meaning the founder has no key configured.

   Do **not** use `instanceof Anthropic.APIError`: the suite `vi.mock`s the SDK with no `APIError`, so the check would throw a TypeError there.
   - Deterministic → `return { rejected: classifyAnthropicOrLeaseError(err), message: String((err as Error).message), stack: (err as Error).stack ?? "" }`. That is plain JSON, so Inngest memoizes it and never retries the step.
   - Otherwise → `throw err` unchanged, so it stays retryable exactly as today.

   The step's return type widens to `AnthropicTurnResult | TurnRejection`.
3. **Handle the rejection in the handler.** Right after the `turn-${n}-claude` step, if the result has `rejected`, `return persistFailure(step, { reason: result.rejected, err: Object.assign(new Error(result.message), { stack: result.stack }), … })`. `persistFailure` → `reportSilentFallback` then sends Sentry the SDK's original message (`"400 {…A maximum of 4 blocks with cache_control…}"`) and the original stack, which addresses the CTO's Sentry-triage point. The handler's existing `catch` and its `classifyAnthropicOrLeaseError(err)` call stay unchanged, for the retryable path.
4. **Widen the `FailureReason` union at every site** (`hr-type-widening-cross-consumer-grep`; `git grep -n anthropic_rate_limited` lists them all):
   - `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts`: the `FailureReason` union.
   - `apps/web-platform/components/dashboard/failure-reason-copy.ts`: the union, plus a `FAILURE_REASON_COPY` row `anthropic_request_rejected: { copy: "Anthropic rejected this request, so retrying won't help. CTO has been notified.", retryEligible: false }`. Also add a line to the `retryEligible` docstring's "NOT shown" list.
   - `apps/web-platform/test/components/dashboard/failure-reason-copy.test.ts`: the `ALL_REASONS` list.
   - `apps/web-platform/test/components/dashboard/today-card-state-matrix.test.ts`: the CPO-2 "no raw reason leaks" list.

   `action_sends.failure_reason` is `text` with no CHECK constraint, so no migration is needed. Run `./node_modules/.bin/tsc --noEmit` after the union edit. `Record<FailureReason, …>` makes the compiler list any copy row that is missing.

**Known residual (accepted, recorded in Non-Goals).** Transient failures still throw. After Inngest exhausts `retries: 3`, the handler's `catch` sees a `StepError` with no `status` and no custom `name`, so a 429 that survives every retry still reads "Anthropic API timeout. Retry usually works." That is today's behavior, and every transient reason tells the founder the same thing: try again. Lease errors are unaffected: Inngest's own `serializeError` keeps the string `cause` (measured by Kieran), so `ByokLeaseError` `fetch_failed`, `decrypt_failed` and `escape` already classify correctly after the round-trip. Fixing the 429 residual would mean carrying a verdict through `message`, which is the protocol this revision deliberately dropped.

What does **not** change: the cost marker (a rejected call never emits one), `persistTurnCostAwaitable`, and the #8635 probe.

### Phase 3 — ADR-042 §I5 amendment

Amend `knowledge-base/engineering/architecture/decisions/ADR-042-anthropic-sdk-inside-inngest-leader-loop.md` §I5 in place, with a dated `Amended 2026-09-24` note:

- Markers are now **one explicit marker on the last system block plus top-level automatic caching**, never per tool. The reason: the 4-breakpoint cap, including the automatic slot, and the render order tools → system → messages.
- Both markers keep the 5-minute default TTL, which `MODEL_PRICING`'s cache-write rate assumes.
- Add an `## Alternatives Considered` row: "cache_control on every tool definition — rejected 2026-09-24: exceeds the 4-breakpoint cap at ≥ 3 tools with automatic caching (security.cve_alert has 5), and tools+system is below the minimum cacheable length anyway."
- The "Sentinel test" line under §I5 names the new breakpoint-cap test as well.

## Files to Edit

- `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts`: Phase 1 request shape and `MODEL_PRICING` TTL sentence; Phase 2 widened classifier, pre-billing `try/catch` in the step that *returns* deterministic rejections, the `rejected` check after the step, and the `FailureReason` union.
- `apps/web-platform/components/dashboard/failure-reason-copy.ts`: union member, copy row, docstring line.
- `apps/web-platform/test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts`: new `describe` blocks for Guard 1 and Guard 2 (see Test Scenarios).
- `apps/web-platform/test/components/dashboard/failure-reason-copy.test.ts`: `ALL_REASONS`.
- `apps/web-platform/test/components/dashboard/today-card-state-matrix.test.ts`: CPO-2 reason list.
- `plugins/soleur/test/preflight-discoverability-test.test.ts`: bump `BASELINE_DECLARED_PROBES` by 1, with a PLACEMENT / TRUTH / NO SUBSTITUTE comment, **after the final rebase** (AC9). This plan's `discoverability_test` declares `credentials_required` (Better Stack read), and G1 counts every declaring plan under `knowledge-base/project/plans/`.
- `knowledge-base/engineering/architecture/decisions/ADR-042-anthropic-sdk-inside-inngest-leader-loop.md`: §I5 amendment and the alternatives row.

## Files to Create

None. The breakpoint tests reuse the existing leader-loop harness, whose ~400 lines of `vi.mock` setup would otherwise have to be copied into a new file.

## Non-Goals

- Adding caching to compound-promote, weekly-release-digest, domain-router or email-triage. The 2026-09-23 measurement found no reuse within the TTL.
- Touching the #8635 probe (`scripts/followthroughs/anthropic-double-bill-8611.sh`) or the `SOLEUR_CLAUDE_COST` marker fields it reads.
- `soleur-go-runner.ts` (Agent SDK path, one marker, not affected).
- A 1-hour TTL, intermediate lookback breakpoints, or cache pre-warming (see the Cut List).
- Correct labelling of a *transient* failure that survives all 3 retries. A 429 or lease `subscription_limit` still reads "Anthropic API timeout" after the Inngest round-trip. That is today's behavior; every transient reason tells the founder to try again, and fixing it would need an error-borne carrier (see Phase 2, Known residual).
- A distinct "credit balance too low" reason. That arrives as a 400 `invalid_request_error` and will read as "rejected". See Sharp Edges.

## Technical Considerations

- **Breakpoint budget after the change: 2 per request for every class and every turn.** That is the system marker plus the automatic one. Nothing in the loop adds markers to `messages`: assistant content is echoed from the API response, which carries none, and `tool_result` blocks are built without them.
- **Composition rules.** An explicit marker together with top-level automatic caching is a documented combination. Its two 400 conditions (4 explicit markers, or an explicit marker on the *last* block with a different TTL) cannot occur here.
- **Prefix stability.** System prompts and tool defs are module constants, and the tool order is fixed by the module arrays. Per-spawn content (`userPromptTemplate`) comes after the system marker, and thinking is not enabled. So nothing silently invalidates the cache between turns of one spawn.
- **Lookback.** About 2 positions are appended per turn (one assistant message, one `tool_result` run), well under the 20-position window.
- **Inngest replay and retries (ADR-042 I1/I2).** The request is built inside the same `step.run`, from the same `messages` array reconstructed deterministically on replay, so replays send byte-identical prefixes. A step retry inside 5 minutes now *reads* the cache instead of re-paying full input. The #8635 probe still flags it (`attempt > 0`); a double bill simply costs less.
- **Cost attribution.** Already exact. `usage.cache_read_input_tokens` and `cache_creation_input_tokens` are priced from `MODEL_PRICING` and forwarded to `persistTurnCostAwaitable`, and ADR-042 §I5's existing sentinel test (AC17 in the leader-loop suite) pins that. The only new behaviour is that these fields become non-zero.
- **Haiku classes.** Below 4096 tokens, automatic caching is a free no-op: nothing is written and nothing is billed extra.
- **Plan gates that do not fire, with the reason for each.**
  - *Encryption Posture (Phase 2.11):* Soleur gains no persistent store and no new connection. Anthropic's prompt cache is ephemeral (5-minute TTL), internal to Anthropic's processing of the *same* request on the *existing* HTTPS edge (`engine -> anthropic`), isolated per workspace (per the founder's own key), and not configurable or readable by Soleur.
  - *GDPR gate (Phase 2.7):* no schema, migration, auth or API-route surface. It is not a new processing activity: the same prompt goes to the same processor under the same purpose, and caching only changes how Anthropic bills repeated prefix bytes.
  - *IaC (Phase 2.8):* no infrastructure.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-042** §I5 (Phase 3). This reverses one sentence of an existing ADR's decision: which blocks carry markers. No new ADR is needed. The substrate, trust boundary and topology are unchanged.

### C4 views

**No C4 impact.** Checked against all three model files:

- `knowledge-base/engineering/architecture/diagrams/model.c4`: the external system `anthropic = system "Anthropic API"` is already modeled (currently line 310), with the edge `engine -> anthropic "LLM calls with BYOK keys"` (currently line 475). The `inngest` container is modeled.
- No new human actor, external system, container, data store, or actor↔surface relationship is introduced. The change alters request *fields* on an existing edge.
- `views.c4` and `spec.c4` need no include changes, because no element was added. `bash plugins/soleur/test/c4-count-parity.test.sh` was run at plan time and printed `ALL TESTS PASSED` (0 failed). The change moves none of the derived cardinalities in `model.c4` edge prose.

### Sequencing

The ADR amendment ships in the same PR as the code.

## User-Brand Impact

- **If this lands broken, the user experiences:** the Today card's leader-loop row for a founder's action (for example a CVE-fix PR or a PR review comment) ends in a failed state instead of producing the artifact. A malformed request shape would do this for *every* class, not just `security.cve_alert`. After Phase 2 the row reads "Anthropic rejected this request…" rather than a misleading timeout.
- **If this leaks, the user's money is exposed via:** the founder's own Anthropic key (BYOK). A wrong TTL would under-attribute cache writes in `audit_byok_use`, which is WORM and cannot be corrected afterwards. A mis-shaped request that is *accepted* but caches badly would bill 1.25x cache writes that are never read. No data exposure: the same prompts already go to the same API, and caching is scoped to the founder's own Anthropic workspace.
- **Brand-survival threshold:** `aggregate pattern`. The failure is functional (actions don't complete) or a small cost skew spread across founders' keys. It is not a single-user breach, and rejected requests are not billed.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_CLAUDE_COST markers (component=claude-cost, source=leader-loop) in Better Stack; after this change, turns >= 2 carry cache_read_input_tokens > 0 once a spawn's prompt clears the model minimum"
  cadence: "per leader-loop turn (event-driven by agent.spawn.requested)"
  alert_target: "Sentry issue for deadlettered spawns (op=agent-on-spawn-requested); the #8635 follow-through sweeper for the marker channel"
  configured_in: "apps/web-platform/server/claude-cost-marker.ts (emitClaudeCostMarker), apps/web-platform/server/cost-writer.ts (persistTurnCostAwaitable), apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts (persistFailure -> reportSilentFallback)"

error_reporting:
  destination: "Sentry (web-platform project, SENTRY_DSN) via reportSilentFallback in persistFailure"
  fail_loud: "Sentry event 'agent-on-spawn deadlettered: anthropic_request_rejected' carrying the SDK's original error message, e.g. '400 {\"type\":\"error\",...A maximum of 4 blocks with cache_control...}', and the original stack"

failure_modes:
  - mode: "request rejected by the API (breakpoint cap or any other request-shape 400/404/413/422)"
    detection: "Sentry event from persistFailure tagged 'deadlettered: anthropic_request_rejected' (before Phase 2 this was mislabelled anthropic_timeout)"
    alert_route: "Sentry issue alert on the web-platform project"
  - mode: "founder key rejected (401/403)"
    detection: "Sentry event 'deadlettered: byok_lease_unavailable' whose message starts '401 ' or '403 ' (or is a MissingByokKeyError); founder sees the existing BYOK copy"
    alert_route: "Sentry issue alert on the web-platform project"
  - mode: "caching silently not engaging (a byte-unstable prefix, or a marker dropped by a refactor)"
    detection: "Success Metrics verdict query: cache_read_turns stays 0 while later_turns > 0 for Sonnet classes; the Guard 1 unit test fails first if the marker is dropped in code"
    alert_route: "CI failure on the leader-loop suite; post-deploy query run by the operator/agent (no SSH)"
  - mode: "cache-write mis-attribution (a ttl other than 5m reintroduced)"
    detection: "Guard 1 'no ttl on any cache_control' assertion fails in CI"
    alert_route: "CI failure"

logs:
  where: "Better Stack Logs (web-platform source) for SOLEUR_CLAUDE_COST markers; Sentry for deadletter events"
  retention: "Better Stack plan retention (hot + S3 archive, queried via remote()+s3Cluster()); Sentry project retention"

discoverability_test:
  command: "bash scripts/betterstack-query.sh --since 168h --grep leader-loop --limit 20"
  expected_output: "cache_read_input_tokens"
  credentials_required: "Better Stack ClickHouse query connection (BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD, Doppler soleur/prd_terraform) — log content has no unauthenticated read path; BETTERSTACK_LOGS_TOKEN is ingest-only"
```

## Guard Contract

### Guard 1 — leader-loop cache-breakpoint cap

**Property.** Every request the leader loop sends to `messages.create`, for every class in `LEADER_PROMPTS` and on every turn, carries at most 4 cache breakpoints in total. The top-level field is exactly `{ type: "ephemeral" }` and the last system block's marker is exactly `{ type: "ephemeral" }`, so no `ttl` is set. `tools` are sent exactly as the class module defines them, with no marker added.

**Assembly.** The chokepoint is the one `client.messages.create` call in the `turn-${n}-claude` step, and `anthropicCreateSpy` captures every request it makes. A breakpoint can sit in four places: the top-level `cache_control`, `system[*]`, `tools[*]`, and `messages[*].content[*]`. The total is counted as `JSON.stringify(params).match(/"cache_control"/g)?.length ?? 0`. That is recursive by construction, so there is no counter helper to self-test. The class population is `Object.keys(LEADER_PROMPTS)`, read at test time. The turn population is every request, captured per call with `anthropicCreateSpy.mockImplementation(p => { captured.push(structuredClone(p)); … })`: one turn-1 call per class, plus a 3-call run (tool_use → tool_use → end_turn) where message content accumulates. A second call site that bypasses the chokepoint is left to code review. The source-regex test was cut in plan review because it is brittle to harmless refactors and misses a wrapped call.

**Mutation matrix:**

| # | Mutation (to `agent-on-spawn-requested.ts` unless stated) | Expected |
|---|---|---|
| 1 | Re-add `cache_control: { type: "ephemeral" }` to every tool in a `tools.map` (the pre-fix shape) | RED: security.cve_alert totals 7 > 4, and `params.tools` toEqual `leaderModule.tools` fails for every class |
| 2 | Re-add per-tool markers **only** when `tools.length <= 2`. The precondition "total ≤ 4" still holds (ci_failed = 3, pr_review_pending = 4) | RED on `params.tools` toEqual `leaderModule.tools` while the ≤ 4 assertion stays green. The cap alone is not the guard |
| 3 | Delete the top-level `cache_control` | RED on `params.cache_control` toEqual `{ type: "ephemeral" }` |
| 4 | Add `ttl: "1h"` to either marker | RED: the exact `toEqual` rejects the extra key. This pins the `MODEL_PRICING` 5-minute assumption |
| 5 | Add `cache_control` to the `tool_result` blocks the loop appends (a second member after a compliant first: turn 1 is clean, turns 2+ are not) | RED on "total === 2" for captured calls 2 and 3 of the 3-call run. The handler mutates one shared `messages` array, so every `mock.calls[i]` shows the final state. The suite must `structuredClone` each request as it is made and assert `captured[0].messages.length === 1` (Kieran P1-2) |
| 6 | Own dispatch: set `process.env.LEADER_CLASSES_DISABLED` to every class in the test, so the handler exits before `create` | RED on the per-class `anthropicCreateSpy` call-count floor (> 0), instead of passing over zero calls |

**Harness rows:**

| # | Suite edit or input | Expected |
|---|---|---|
| H1 | Assert on the live `mock.calls[i][0]` (shared, mutated array) instead of per-call `structuredClone` captures | The `captured[0].messages.length === 1` assertion goes RED, and per-call totals stop being per-call. The suite keeps the clone capture |
| H2 | Must-PASS, non-canonical: the third call of the 3-call run, whose messages hold assistant `tool_use` and user `tool_result` blocks with no markers | PASS, with a total of exactly 2 |

**Anchor.** The ceiling of 4 comes from outside the repo: it is the Messages API contract, and a regression is a 400 from the API itself, which after Phase 2 lands in Sentry as `deadlettered: anthropic_request_rejected`. The exact-shape expectations are in-repo, and a single diff could weaken both the code and the test. The ADR-042 §I5 amendment states the same placement in a separately reviewed file. There is no machine-held anchor beyond that, stated honestly.

### Guard 2 — deterministic API rejections are returned, classified and not retried

**Property.** When `messages.create` fails with a 4xx other than 408, 409 or 429, or the founder has no key (`MissingByokKeyError`), the `turn-${n}-claude` step **returns** `{ rejected, message, stack }` instead of throwing. The spawn then fails with the right reason: 401/403 and a missing key → `byok_lease_unavailable`; every other such 4xx → `anthropic_request_rejected`. It makes exactly one `create` call, and Sentry receives the SDK's original message. Every other failure keeps today's throw path unchanged.

**Assembly.** There is one producer: the `try/catch` around the pre-billing statements inside the step (`getRestApiKey` → `create`). Post-billing code sits outside it by construction. There is one consumer, the `rejected` check right after the step. The rejection travels only as the step's return value, which Inngest memoizes as JSON. The error shapes it covers: an SDK error with `status` set (synthesized as `Object.assign(new Error("<status> {…}"), { status })`, because `@anthropic-ai/sdk` is `vi.mock`ed in this suite); `APIConnectionTimeoutError`-shaped errors (no status); a `MissingByokKeyError`; and a `ByokLeaseError("fetch_failed")`, both thrown from the mocked lease. `persistTurnCostAwaitable` swallows its own RPC errors (its docstring says "SWALLOWED"), so no post-billing throw is exercised.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-throw the 400 instead of returning it | RED: in the test that simulates Inngest retries (a `makeStep` variant that re-invokes a throwing callback up to 3 more times), `anthropicCreateSpy` is called 4 times, not once |
| 2 | Map 400 (or 402) to `anthropic_timeout` in `classifyAnthropicOrLeaseError` | RED on the 400 and 402 cases |
| 3 | Also return (instead of throw) on 429 or 500 | RED: those cases must still reach the handler's `catch` (the retrying step variant calls `create` more than once) |
| 4 | Treat a lease `ByokLeaseError("fetch_failed")` as deterministic, so it is returned | RED: it must still throw (the retrying step variant calls `getRestApiKey` more than once) and resolve to `byok_lease_unavailable` |
| 5 | Drop the `MissingByokKeyError` arm | RED: a missing key must be returned after one `getRestApiKey` call as `byok_lease_unavailable`, not retried |

**Harness rows:**

| # | Suite edit or input | Expected |
|---|---|---|
| H1 | Use the existing `makeStep`, which never retries, for mutation 1 | Mutation 1 goes GREEN, which proves the retrying step variant is load-bearing for the "no retry" property |
| H2 | Must-PASS, non-canonical: the returned rejection survives `JSON.parse(JSON.stringify(result))` with `rejected`, `message` and `stack` intact | PASS (the memoization shape) |

**Anchor.** Two facts about Inngest carry this guard: returned values are memoized, and thrown errors are retried. Both are Inngest's documented step semantics, and the `retries: 3` config is in the same file. Guard 2 does not depend on Inngest's error serializer, because the verdict never crosses the boundary as an error.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (76 issues) returned no body naming `agent-on-spawn-requested.ts`, `agent-on-spawn-requested-leader-loop.test.ts`, `ADR-042` or `leader-prompts/`.

## Acceptance Criteria

- [ ] **AC1** In the `turn-${n}-claude` step, `client.messages.create` carries top-level `cache_control: { type: "ephemeral" }`, one `cache_control: { type: "ephemeral" }` on the system block, and `tools: leaderModule.tools` with no per-tool marker. `rg -c 'client\.messages\.create\(' apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` prints `1`. The file header comment says `anthropic.messages.create`, which this pattern deliberately does not match.
- [ ] **AC2** Guard 1 tests exist in `agent-on-spawn-requested-leader-loop.test.ts` and pass (Test Scenarios 1-2). They cover, per class via `it.each(Object.keys(LEADER_PROMPTS))`, a `create` call-count above 0; totals ≤ 4 and === 2; exact `toEqual` on both markers; `params.tools` toEqual the module's tools; and a 3-call run asserted on per-call `structuredClone` captures, with `captured[0].messages.length === 1`.
- [ ] **AC3** Mutation check run during `soleur:work`: temporarily re-add the per-tool `tools.map(t => ({...t, cache_control: {type: "ephemeral"}}))`, then run `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts`. It must exit non-zero. The failing cases must include `security.cve_alert` (total 7) and `knowledge.kb_drift` (total 5), and every class must fail the `tools` toEqual. Revert and re-run: exit 0. Do the same for Guard 1 mutations 3 (drop the top-level field) and 5 (a marker on `tool_result`), and for Guard 2 mutation 1 (re-throw the 400). Record each red and green summary line in the PR body.
- [ ] **AC4** Phase 2 is in place. `classifyAnthropicOrLeaseError` maps 401/403 → `byok_lease_unavailable`, and every other 4xx except 408/409/429 → `anthropic_request_rejected`. The pre-billing `try/catch` in the step *returns* `{ rejected, message, stack }` for those statuses and for `MissingByokKeyError`, and re-throws everything else. The handler calls `persistFailure` with the returned reason. `anthropic_request_rejected` has been added to both `FailureReason` unions, to `FAILURE_REASON_COPY` (`retryEligible: false`), to `ALL_REASONS`, and to the CPO-2 list.
- [ ] **AC5** Guard 2 tests exist and pass (Test Scenarios 3-4). They cover:
  - 400, 402, 401 and `MissingByokKeyError`, each with a single call under the retrying step variant;
  - 429, 500 and `ByokLeaseError("fetch_failed")`, each retried (4 calls);
  - the Sentry mirror receiving the SDK's `"400 …"` message;
  - the JSON round-trip of the returned value.
- [ ] **AC6** The `MODEL_PRICING` TTL sentence names both markers. No pricing value changes: `git diff` touches neither the `[SONNET_MODEL]` row nor the `[HAIKU_MODEL]` row.
- [ ] **AC7** ADR-042 §I5 is amended (dated), the alternatives row is added, and the sentinel-test line is updated.
- [ ] **AC8** Both pass: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest test/components/dashboard` and `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. Baseline at plan time: the leader-loop suite is 28/28 green.
- [ ] **AC9** `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` passes, with `BASELINE_DECLARED_PROBES` bumped by exactly 1 for this plan's `credentials_required` declaration. The ratchet moved 5 times in about 48 hours, so make the bump **after the final rebase onto `origin/main`**, in `soleur:ship`'s pre-merge sync, not during `soleur:work`. Re-measure the base value first. Add a `// #<PR> (<date>): +1 …` comment with the PLACEMENT / TRUTH / NO SUBSTITUTE clauses its siblings carry.
- [ ] **AC10** Scope fence. `git diff --name-only origin/main...HEAD` lists only:
  - the 7 files in `## Files to Edit`;
  - this plan;
  - `knowledge-base/project/specs/feat-one-shot-leader-loop-prompt-caching/{tasks.md,decision-challenges.md,session-state.md}`;
  - any `knowledge-base/` index or learning files that the pipeline's work, review and compound phases generate.

  It includes no `scripts/followthroughs/`, no `server/soleur-go-runner.ts`, and none of the four direct callers named in Non-Goals.

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** CTO (`soleur:engineering:cto`) agreed with the direction. Folded in: (1) do not retry a deterministic 4xx, because `retries: 3` otherwise re-sends the same rejection (implemented as a returned value rather than `NonRetriableError`, per plan review); (2) a split between a key problem (401/403 → `byok_lease_unavailable`) and a request-shape problem (→ `anthropic_request_rejected`); (3) documenting that a turn-1-only spawn pays a 1.25x write premium (Research Insights, Value proposition); (4) counting the automatic breakpoint as a slot in the cap test; (5) noting that #8635 double bills become cheaper but are still flagged; (6) sweeping every union site. CTO's suggestion to recompute the "≈$0.33 worst-case" figure was checked and **not** applied, because that figure bounds output tokens only (Phase 1 note). No new ADR, only the §I5 amendment.

**Scoped advisor consult (Step 4.5, `resolveAdvisorTier()` → fable):** it recommended (1) classifying inside the step and carrying the verdict across the step boundary in a field that survives `StepError`, rather than parsing the SDK's message format in the handler; and (2) dropping the inert explicit system marker and keeping only the top-level field. (1) was **applied**. Its proposed carrier, a custom error `name`, was measured and does not survive serialization. Plan review (DHH) then replaced every error-borne carrier with the step's **return value**, which Inngest memoizes as-is. (2) is **not applied**: the brief explicitly asks to keep one explicit marker on the last system block, and the claude-api guidance calls that the robust combination for agent loops. That makes it a User-Challenge, recorded in `knowledge-base/project/specs/feat-one-shot-leader-loop-prompt-caching/decision-challenges.md`. DHH and code-simplicity concurred with the advisor at plan review.

**Plan review (DHH, Kieran, code-simplicity, CTO devex), applied:**

- The Phase 2 carrier became a returned `{ rejected, message, stack }` (DHH). That removed the tag protocol, the parser, the membership check, `NonRetriableError` and the serializer fixture.
- The 4xx set became a range minus 408/409/429, which picks up 402 `billing_error` (simplicity).
- The recursive counter helper and its self-test became a `JSON.stringify` match, and the exact `toEqual` on the markers and on `tools` replaced the separate "no ttl" and "no tool marker" walks (DHH, simplicity).
- The source-regex call-site test was cut; AC1 keeps a one-shot `rg -c` code-state check whose pattern skips the header comment (DHH, simplicity, Kieran P1-1).
- Per-call `structuredClone` capture is required, because the handler mutates one shared `messages` array (Kieran P1-2).
- The premise was corrected: Inngest keeps string `cause`, so lease `fetch_failed`/`decrypt_failed`/`escape` already classify correctly, and `MissingByokKeyError` is the lease case that needed fixing (Kieran P1-3).
- The `try` is scoped to pre-billing statements, so a post-billing throw can never become a rejection (Kieran P2-4).
- The ratchet bump moved to after the final rebase (CTO F4).
- The CTO's F2 concern, the same `err.status`-after-step bug class in other Inngest functions, was sampled. All three flagged sites (`cron-kb-template-health.ts`, `cron-github-app-drift-guard.ts`, `cron-stale-deferred-scope-outs.ts` via `sweepStaleScopeOuts` called inside `step.run`) read `status` **inside** a step callback on the live error, so no defect was found. It is left for the compound learning.
- Named panel: only the CTO (devex) was activated. The plan's single founder-facing change is one copy row in an existing `.ts` data map, so the CPO, CMO and UX panels were not.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

The only founder-facing change is one new copy row in an existing data map (`components/dashboard/failure-reason-copy.ts`). It is a `.ts` file, so it does not match the UI-surface globs in `ui-surface-terms.md`. No new page, component or flow. The copy follows the existing rows' two-clause pattern ("what happened. recovery path"), matching `leader_tool_invalid`. No domain leader recommended a copywriter, so the Content Review Gate did not fire.

## Test Scenarios

All scenarios go in `apps/web-platform/test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts` unless stated. They reuse the existing `vi.mock` harness, `anthropicCreateSpy`, `makeStep` and `endTurnResponse`.

1. **Per-class breakpoint cap (Guard 1, mutations 1-4, 6).** `it.each(Object.keys(LEADER_PROMPTS))`: mock one `endTurnResponse()`, then run the handler with `actionClass: cls` and sourceRef `pr-acme:repo:7`. A sourceRef parse failure is non-fatal for every class. Assert `anthropicCreateSpy` was called at least once (mutation 6). For each call's `params`:
   - `count(params) <= 4` and `=== 2`, where `count = JSON.stringify(params).match(/"cache_control"/g)?.length ?? 0`.
   - `params.cache_control` toEqual `{ type: "ephemeral" }`.
   - `params.system.at(-1).cache_control` toEqual `{ type: "ephemeral" }`.
   - `params.tools` toEqual `LEADER_PROMPTS[cls].tools`.
2. **Multi-turn accumulation (Guard 1, mutation 5, H1/H2).** For `engineering.pr_review_pending`, use `anthropicCreateSpy.mockImplementation(p => { captured.push(structuredClone(p)); return responses.shift(); })`. The responses are two tool-use turns and then `end_turn`, 3 calls in all; the tool-use turns reuse the happy-path `createComment` fixture. This capture matters because the handler passes one shared `messages` array and mutates it after each call, so raw `mock.calls[i][0]` all show the final state. Assert:
   - `captured.length === 3` and `captured[0].messages.length === 1`;
   - every Scenario 1 assertion holds on **every** captured request;
   - `captured[2].messages` holds `tool_use` and `tool_result` blocks.
3. **Rejections are returned, not retried (Guard 2).** Add a `makeStep({ retries: 3 })` variant: when a callback throws, it re-invokes the callback up to 3 more times before re-throwing, like Inngest's `retries: 3`. Each case below builds `anthropicCreateSpy.mockRejectedValue(Object.assign(new Error('<status> {"type":"error",…}'), { status }))`.
   - 400 and 402 → result `failureReason: "anthropic_request_rejected"`, with `anthropicCreateSpy` called exactly once.
   - 401 → `byok_lease_unavailable`, called once.
   - The mocked lease's `getRestApiKey` throws `MissingByokKeyError` → `byok_lease_unavailable`, `getRestApiKey` called once, `create` never called.
   - It throws `ByokLeaseError("fetch_failed", …)` → called 4 times (retried), then `byok_lease_unavailable`.
   - 429 → called 4 times, then `anthropic_rate_limited`. This works because the in-process mock re-throws the live error; in production this path is the documented residual.
   - 500 → called 4 times, then `anthropic_timeout`.
   - Sentry mirror: the `reportSilentFallback` spy (already mocked via `@/server/observability`) receives an error whose `message` starts with `"400 "`.
4. **Memoization shape (Guard 2, H2).** Take the value the `turn-1-claude` step returned in the 400 case, read from `step.memoized.get("turn-1-claude")`. Assert `JSON.parse(JSON.stringify(v))` deep-equals `v`, and that it has `rejected`, `message` and `stack`.
5. **Copy coverage.** In `test/components/dashboard/failure-reason-copy.test.ts`, "covers every reason" passes with the new member. `FAILURE_REASON_COPY.anthropic_request_rejected.retryEligible === false`. In `today-card-state-matrix.test.ts`, the CPO-2 check passes for the new reason: the rendered copy does not contain the raw reason string.
6. **Regression.** The existing AC10 `anthropic_rate_limited` and `anthropic_timeout` tests stay green, unchanged, as do AC17 (cache tokens flow into `persistTurnCostAwaitable`) and the #8611 marker test.

Run with: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts test/components/dashboard/failure-reason-copy.test.ts test/components/dashboard/today-card-state-matrix.test.ts`

## Success Metrics

- 0 leader-loop requests rejected for breakpoint count (no Sentry `deadlettered: anthropic_request_rejected` event with `cache_control` in its message).
- After deploy, the verdict query below returns `cache_read_turns > 0` once Sonnet-class spawns with multi-turn runs have occurred. It is run under `doppler run -p soleur -c prd_terraform --`. `remote()` alone is only the ~40-minute hot window, so the query unions the S3 archive, in the same shape as `scripts/followthroughs/anthropic-double-bill-8611.sh`:

  ```sql
  SELECT countIf(t >= 2) AS later_turns, countIf(t >= 2 AND cr > 0) AS cache_read_turns
  FROM (SELECT JSONExtractInt(raw, 'message', 'turn') AS t,
               JSONExtractInt(raw, 'message', 'cache_read_input_tokens') AS cr
        FROM (SELECT dt, raw FROM remote($BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1)
        WHERE dt > now() - INTERVAL 7 DAY
          AND raw LIKE '%"SOLEUR_CLAUDE_COST":true%'
          AND JSONExtractString(raw, 'message', 'component') = 'claude-cost'
          AND JSONExtractString(raw, 'message', 'source') = 'leader-loop')
  FORMAT JSONEachRow
  ```

- Leader-loop failures in Sentry carry an accurate reason: no `deadlettered: anthropic_timeout` event has an error message that starts with a 4xx status other than 408/409/429. The documented residual, a 429 after exhausted retries, is excluded.

## Dependencies & Risks

- **Automatic caching on `claude-haiku-4-5-20251001`.** It is documented as available on the Claude API for current models, but was not live-verified here because no credential is available. Mitigation: below Haiku's 4096 minimum it is a no-op, and any 400 now surfaces accurately (Phase 2) instead of as a timeout.
- **Phase 2 depends on Inngest memoizing a step's return value and retrying a step that throws.** Both are Inngest's core step semantics, and `retries: 3` is set in the same file. It does **not** depend on Inngest's error serializer or on the SDK's `"<status> <json>"` message format, because status is read from the live error in-step and the verdict crosses the boundary as a returned value.
- **Behavior change (intended).** A founder with no key configured now sees "Couldn't acquire your BYOK key. Verify your API key in Settings → BYOK." instead of "Anthropic API timeout". 401/403 and every deterministic 4xx now fail after **one** call instead of four. Note that an Anthropic 403 can also mean the key lacks access to the model; "Verify your API key" is acceptable copy for that (Kieran P2-7).
- **Turn-1-only spawns with a prompt of 1024 tokens or more pay a 25% input premium** on that call. This is accepted: typical spawns run 2 or more calls.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- `@anthropic-ai/sdk` is `vi.mock`ed in the leader-loop test file (a default-export class only), so `Anthropic.APIError` and its subclasses are **not** available from the mocked module. Synthesize `{status, message}` errors, and never use `instanceof Anthropic.APIError` in the production code either: under the mock it throws a TypeError. Detect deterministic failures by a numeric `status` and by `name === "MissingByokKeyError"`. That class sets `this.name`, and the live error is read in-step, before any serialization.
- The Anthropic SDK's error `.name` is `"Error"` for every class (measured). After Inngest serialization, every custom `name` becomes `"Error"` and `status` is dropped, though string `cause` survives (measured). Never route a decision that crosses the step boundary on an error's `name` or `status`. Return it from the step. Two earlier drafts of this plan were each falsified by this, one carrying the verdict in a custom-named error and one in a message tag.
- A founder whose Anthropic credit balance is exhausted gets a 400 `invalid_request_error`. After Phase 2 that reads "Anthropic rejected this request… CTO has been notified", which is honest but not actionable for them. It is noted rather than special-cased. Revisit if Sentry shows such events.
- Do not add a marker to the first user message "to cache the PR diff". Automatic caching already covers it, and an explicit marker there would be a third slot for no gain.

## References & Research

- claude-api skill `shared/prompt-caching.md`: "Automatic vs explicit breakpoints", "API reference" (the 4-breakpoint cap and minimums table), "20-block lookback window".
- SDK: `apps/web-platform/node_modules/@anthropic-ai/sdk/resources/messages/messages.d.ts` (`MessageCreateParamsBase.cache_control`), `core/error.js` (error classes, message format).
- Inngest: `apps/web-platform/node_modules/inngest/components/StepError.js`, `components/execution/v1.js` (`new StepError(opId.id, result.error)`, `NonRetriableError` handling).
- ADR-042 (§I1, I2, I5), ADR-108 (cost markers), ADR-131 (inline-fix threshold).
- Related: #8611 (streaming / double-bill), #8635 (follow-through, untouched).
