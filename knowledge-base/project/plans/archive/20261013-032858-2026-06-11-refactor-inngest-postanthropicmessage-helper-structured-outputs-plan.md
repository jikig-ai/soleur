---
title: "refactor(inngest): extract shared postAnthropicMessage helper + migrate cron call sites to structured outputs"
type: refactor
issue: 5186
branch: feat-one-shot-inngest-anthropic-helper-structured-outputs-5186
lane: single-domain
date: 2026-06-11
status: planned
---

# ♻️ refactor(inngest): extract `postAnthropicMessage` helper + migrate call sites to structured outputs

## Enhancement Summary

**Deepened on:** 2026-06-11
**Sections enhanced:** Phase 1 (helper precedent + signature), Phase 3 (structured-output migration ACs), Observability, User-Brand Impact
**Research used:** `claude-api` skill (authoritative structured-outputs API contract), repo-research-analyst, learnings-researcher, functional-discovery, architecture-strategist (plan review), Explore (precedent-diff on `_cron-shared.ts`)

### Key Improvements (from deepen pass)
1. **Sibling test file already exists** — `apps/web-platform/test/server/inngest/cron-shared.test.ts`. `postAnthropicMessage` tests go there; `Files to Create` corrected to none.
2. **Three P1 behavior-preservation traps surfaced & encoded:** (a) compound's `max_tokens` branch emits a caller-side `logger.warn("anthropic-response-truncated")` that must not drift into the helper; (b) the object-wrapper migration needs prompt + parse-site + guard edits (3 coordinated changes), not just a schema; (c) `domain-router.test.ts` has zero classify-path coverage, so a NEW fetch-mock test is mandatory (AC9 would otherwise be vacuously green).
3. **Observability accuracy fix** — digest's `JSON.parse` is NOT in a try/catch; a parse failure routes through the Inngest-retry → cron-heartbeat path, not `reportSilentFallback`. Failure-modes now distinguishes digest vs compound routes.
4. **Helper-style precedent pinned** — `postDiscordWebhook` (redact-then-throw, no logger) is the model, not `postSentryHeartbeat` (swallow-and-report). Confirms transport-only design.

### New Considerations Discovered
- The import-weight constraint (`_cron-shared.ts:3-4` static-import octokit/github-app) is confirmed load-bearing — domain-router migrates inline, never gains the helper.
- `model-tiers.test.ts`'s `RAW_MODEL_LITERAL` guard requires the helper to take the model as an argument (no `"claude-…"` literal in `functions/`).

---

Closes #5186. Follow-up consolidation of the two scope-extension comments left open when #5106 closed (PR #5156) on its primary model-tier-registry scope.

## Overview

Two sequential parts, both internal `apps/web-platform` TypeScript with no UI, no new infra, no new secret:

1. **Extract `postAnthropicMessage` into `_cron-shared.ts`.** `curateViaAnthropic` (`cron-weekly-release-digest.ts:299-353`) and the cluster fetch in `cron-compound-promote.ts:392-451` duplicate the direct Anthropic Messages API call shape (fetch + headers + `stop_reason` guard + content extraction). Extract a shared `postAnthropicMessage` helper. The digest copy (`AbortSignal.timeout`, throw-to-fallback) is the better seed.

2. **Migrate the three Messages-API call sites to structured outputs, then retire `extractModelJson`.** `claude-sonnet-4-6` and `claude-haiku-4-5` both support structured outputs (`output_config.format` with a `json_schema`), which guarantees schema-valid JSON and makes the `extractModelJson` (`@/server/model-json`) fence-stripping helper dead defensive code. Migrate `cron-weekly-release-digest.ts`, `cron-compound-promote.ts`, and `domain-router.ts`, then delete `model-json.ts` + its test once `git grep extractModelJson` returns zero production hits.

Do Part 1 first (extract the helper), then Part 2 on the single helper for the two crons + inline for domain-router.

### Key grounding facts (verified at plan time)

- **Structured-outputs API contract (verified via `claude-api` skill, 2026-06-11):**
  - Request shape: `output_config: { format: { type: "json_schema", schema: SCHEMA } }` — top-level `output_config` field on the Messages request body. The old top-level `output_format` is deprecated; do not use it.
  - **Version header unchanged:** `anthropic-version: 2023-06-01` (all three sites already send this).
  - **Beta header: NONE.** Structured outputs is GA on Sonnet 4.6 / Haiku 4.5 (and Opus 4.8 / Fable 5). No `anthropic-beta` header.
  - **Response shape unchanged at the wire level:** the model's JSON arrives in `data.content[0].text` (still a text block). These are raw-`fetch` call sites (not the SDK), so they keep reading `content[0].text` and `JSON.parse`-ing it — just **without the `extractModelJson` fence-strip**, because the output is now guaranteed schema-valid (no markdown fences).
  - **Model support confirmed for every site:** digest + compound-promote use `EXECUTION_MODEL` = `SONNET_MODEL` = `claude-sonnet-4-6` (`model-tiers.ts:42`, `leader-prompts/constants.ts`); domain-router uses `claude-haiku-4-5-20251001` (`domain-router.ts:132`). Both are on the structured-outputs support list.
  - **Schema constraints (load-bearing — see Sharp Edges):** `additionalProperties: false` is REQUIRED on every object. NOT supported: numeric constraints (`minimum`/`maximum`/`maxItems`), string constraints (`minLength`/`maxLength`), recursive schemas, complex array constraints. The digest's `MAX_HIGHLIGHTS = 5` cap and compound-promote's `slice(0, remaining)` cap are enforced in TS **after** parse — keep them there; do NOT try to express them in the schema.
  - **Refusal / truncation still apply:** `stop_reason: "refusal"` and `stop_reason: "max_tokens"` can still yield non-schema-valid or incomplete JSON. Both existing sites already guard `stop_reason === "max_tokens"`; those guards MUST be preserved through the migration.

- **`_cron-shared.ts` carries octokit/github-app import weight** (`_cron-shared.ts:3-4` import `createProbeOctokit` + `generateInstallationToken`). `model-json.ts:1-3` exists as a deliberate **leaf module** so `domain-router.ts` can fence-strip without dragging in that chain. Therefore: `postAnthropicMessage` lives in `_cron-shared.ts` and is used by the **two crons only**. `domain-router.ts` does NOT import `_cron-shared` and migrates to structured outputs **inline** (it loses the `extractModelJson` call but does not gain the helper). This keeps domain-router's import graph leaf-light. After migration, `model-json.ts` has zero consumers and is deleted.

- **Both crons already import `_cron-shared` via the relative `./_cron-shared` form** (`cron-weekly-release-digest.ts:35`, `cron-compound-promote.ts:46`). Add `postAnthropicMessage` to those existing import statements. Use the **relative** form, never the `@/server/inngest/functions/_cron-shared` alias (matches every sibling cron; alias-in-`functions/` is the known substrate-import smell).

- **No new cron, no new Inngest function.** The five-registry lockstep (`route.ts` / `cron-manifest.ts` / `function-registry-count.test.ts` / `cron-monitors.tf` / `apply-sentry-infra.yml`) does NOT apply — this edits existing handlers only.

- **The `model-tiers.test.ts` parity guard must stay green.** Its `RAW_MODEL_LITERAL = /"claude-sonnet-4-6"|"claude-opus-4-8"/` rejects raw model-ID literals on non-comment lines in `functions/*.ts`. All three sites already source model IDs from constants (`EXECUTION_MODEL`, or the haiku literal in `domain-router.ts` which is OUTSIDE `functions/` and not scanned). The helper must accept the model ID as an **argument** (passed from each caller's existing constant) — do NOT hardcode a model literal in `_cron-shared.ts`.

## Research Reconciliation — Spec vs. Codebase

| Issue-body claim | Codebase reality | Plan response |
| --- | --- | --- |
| Files at `apps/web-platform/server/inngest/cron-*.ts` | Actually under `.../inngest/functions/cron-*.ts` (the `functions/` segment was omitted in the issue) | Use the verified `functions/` paths throughout |
| "three call sites — digest, compound-promote, domain-router" | Confirmed exactly 3 production consumers of `extractModelJson` via `git grep` (+ 1 test) | Migrate all 3; delete helper + test after |
| "Migrate … to structured outputs on the single helper" | domain-router cannot use the `_cron-shared` helper (octokit import weight; leaf-module constraint) | Helper covers the 2 crons; domain-router migrates inline. `extractModelJson` deletion still valid (all 3 stop calling it) |
| "`claude-sonnet-4-6` supports structured outputs" | Verified via `claude-api` skill: GA on Sonnet 4.6 AND Haiku 4.5 (covers all 3 sites). No beta header | Premise holds; proceed |

## User-Brand Impact

**If this lands broken, the user experiences:** a silently-degraded weekly Discord `#releases` digest (curation falls back to the deterministic renderer) or a stalled `compound-promote` learnings-clustering run / mis-routed `@`-domain-leader classification — all internal automation surfaces, not customer-facing product UI.
**If this leaks, the user's data is exposed via:** N/A — no new data surface. The same release notes / learnings corpus / chat-routing text already flows to the Anthropic Messages API today; structured outputs change only the response *format*, not what is sent or stored.
**Brand-survival threshold:** none — internal-automation refactor, no customer-facing artifact and no new exposure vector.

- `threshold: none, reason: edits live under apps/web-platform/server/ (matches the preflight sensitive-path regex) but introduce no auth/secret/data/payment surface — they only restructure how an existing Anthropic-bound LLM call is shaped and parsed; no behavior or data movement changes.`

> Sharp edge: a `## User-Brand Impact` section that is empty, placeholder, or omits the threshold fails `deepen-plan` Phase 4.6. This one is filled. The `threshold: none` scope-out bullet above is required because the diff touches `apps/web-platform/server/` (a preflight Check-6 sensitive path) — without it, ship-time preflight FAILs.

## Implementation Phases

> Phase order is load-bearing: Part 1 (helper exists) precedes Part 2 (callers route through it). Within a single atomic PR, `/work` reads phases sequentially — a caller edit before the helper exists is dead code at its phase boundary.

### Phase 0 — Preconditions (read-only, no edits)

1. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — confirm a green baseline before touching anything.
2. `git grep -n "extractModelJson" -- apps/web-platform/` — confirm the exact consumer set is `{cron-weekly-release-digest.ts, cron-compound-promote.ts, domain-router.ts}` + `model-json.ts` (def) + `test/server/model-json.test.ts`. If the set differs from this plan, STOP and reconcile.
3. Read the current bodies one more time before editing (`hr-always-read-a-file-before-editing-it`): `cron-weekly-release-digest.ts:297-354`, `cron-compound-promote.ts:373-452`, `domain-router.ts:119-176`, `_cron-shared.ts` (helper-style precedent: `postDiscordWebhook:229-253`, `postSentryHeartbeat:164-216`).
4. Confirm the digest's `validAnthropicResponse()` test fixture (`cron-weekly-release-digest.test.ts:129-137`) and the curate-suite assertions (`:418-512`) so Part 2's structured-output change updates the right fixtures.

### Phase 1 (Part 1) — Extract `postAnthropicMessage` into `_cron-shared.ts`

**Files to Edit:** `apps/web-platform/server/inngest/functions/_cron-shared.ts`, `cron-weekly-release-digest.ts`, `cron-compound-promote.ts`, **`apps/web-platform/test/server/inngest/cron-shared.test.ts`** (this sibling test file ALREADY EXISTS — verified at deepen-plan time; add a `describe("postAnthropicMessage", …)` block to it, do NOT create a new file).
**Files to Create:** none.

Design `postAnthropicMessage` to mirror the sibling `post*` helpers (single `args` object, timeout via `AbortSignal.timeout`). The digest copy is the seed. The helper is **mechanical transport only** — it does NOT own observability or fallback policy (see learning `2026-05-12-centralized-at-helper-boundary-transforms-overclaim...`): each caller keeps its own `reportSilentFallback` / throw-to-fallback / `logger.warn` at the call site.

**Sibling-helper precedent (verified at deepen-plan time, `_cron-shared.ts`):**
- `postDiscordWebhook:229-253` is the closest model — single `args` object, `AbortSignal.timeout(10_000)`, **redacts-then-rethrows** (`new Error(\`… (${e.name})\`)`) so the credential never reaches a logger/Sentry payload. `postAnthropicMessage` should likewise redact-then-throw on fetch error if the `x-api-key` could surface in an undici error message (digest/compound both already `throw new Error(\`Anthropic API ${status}\`)` — preserve that non-leaking shape; do NOT pass the raw caught error through).
- `postSentryHeartbeat:164-216` takes `logger: HandlerArgs["logger"]` and calls `reportSilentFallback` INSIDE because a heartbeat failure is non-fatal. `postAnthropicMessage` should NOT follow this — it is the transport-only/Discord pattern. No `logger` param needed: both cron callers log at the call site (digest throws, compound `logger.warn` + `reportSilentFallback` at the call site).

Proposed signature (refine at `/work` against the real call shapes — name the model arg so no model literal lands in `_cron-shared.ts`, preserving the `model-tiers.test.ts` guard):

```ts
// _cron-shared.ts
export async function postAnthropicMessage(args: {
  apiKey: string;
  model: string;          // caller passes EXECUTION_MODEL / its own constant
  maxTokens: number;
  messages: Array<{ role: "user"; content: string }>;
  timeoutMs?: number;     // digest passes 60_000; compound passes undefined (no timeout today)
  outputConfig?: { format: { type: "json_schema"; schema: unknown } }; // added in Phase 3
}): Promise<{ text: string; stopReason?: string }>;
```

Helper responsibilities (intersection of both call sites, nothing more):
- POST `https://api.anthropic.com/v1/messages` with `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`.
- `signal: args.timeoutMs != null ? AbortSignal.timeout(args.timeoutMs) : undefined`.
- `if (!resp.ok) throw new Error(\`Anthropic API ${resp.status}\`)` — both callers already throw on non-ok; preserve.
- Return `{ text: data.content?.[0]?.text ?? "", stopReason: data.stop_reason }`. The helper does **not** decide what an empty/truncated/refused response means — it returns the raw `stopReason` and `text`; each caller keeps its existing branch logic (`max_tokens` guard, empty-content guard, shape validation, `reportSilentFallback`).

Caller edits (behavior-preserving — see learning `2026-06-11-pipeline-consolidation-behavior-preserving-migration-traps.md`):
- **`cron-weekly-release-digest.ts` `curateViaAnthropic`:** replace the inline `fetch(...)` + `resp.ok` + `data` read with `postAnthropicMessage({ apiKey, model: ANTHROPIC_MODEL, maxTokens: ANTHROPIC_MAX_TOKENS, messages: [{ role: "user", content: buildCuratePrompt(releases) }], timeoutMs: ANTHROPIC_TIMEOUT_MS })`. Keep the `stopReason === "max_tokens"` throw, the empty-text throw, the `extractModelJson` parse (until Phase 3), the `{highlights}` shape validation, the verbatim-tag filter, and `MAX_HIGHLIGHTS` slice exactly as-is.
- **`cron-compound-promote.ts` cluster step:** replace the inline fetch with `postAnthropicMessage({ apiKey, model: ANTHROPIC_MODEL, maxTokens: ANTHROPIC_MAX_TOKENS, messages: [...] })` (no `timeoutMs` — compound has no timeout today; do NOT add one, that is a behavior change). Keep the `stop_reason === "max_tokens"` → `{ truncated: true }` branch, the empty-content `reportSilentFallback`, the `extractModelJson` parse, the `Array.isArray` shape guard + its `reportSilentFallback`, and the `slice(0, weekCapResult.remaining)` exactly as-is.
  - **Caller-side log preservation (P1, deepen-plan):** compound's `max_tokens` branch ALSO emits `logger.warn({ fn: "cron-compound-promote" }, "anthropic-response-truncated")` (`cron-compound-promote.ts:415-416`) — this `logger.warn` is **caller-side** and MUST stay at the call site; `postAnthropicMessage` has no `logger`. Do NOT pattern-match against the digest (which throws on `max_tokens` and has no logger call at that branch) and accidentally drop this log line — `"anthropic-response-truncated"` is a distinct dashboard-keyed event.

**Acceptance Criteria — Phase 1:**
- AC1: `git grep -n 'fetch("https://api.anthropic.com/v1/messages"' -- apps/web-platform/server/inngest/functions/` returns **0** (both crons now route through the helper). `domain-router.ts` (outside `functions/`) still has its inline fetch at this phase.
- AC2: `postAnthropicMessage` is exported from `_cron-shared.ts` and contains no `"claude-…"` model literal (`grep -c '"claude-' _cron-shared.ts` unchanged from baseline).
- AC3: Both crons import it via `} from "./_cron-shared"` (relative), confirmed by `grep -n 'postAnthropicMessage' cron-weekly-release-digest.ts cron-compound-promote.ts` showing the import on a `./_cron-shared` line.
- AC4 (behavior parity): existing suites green unchanged — `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-weekly-release-digest.test.ts test/server/inngest/cron-compound-promote.test.ts`.
- AC5: `model-tiers.test.ts` green (`./node_modules/.bin/vitest run test/server/inngest/model-tiers.test.ts`).

### Phase 2 (Part 1) — Helper unit test

Add `postAnthropicMessage` coverage under `test/server/inngest/` (path must satisfy the vitest `test/**/*.test.ts` node-project glob — NOT co-located in `functions/`). Use synthesized fixtures only (`cq-test-fixtures-synthesized-only`). Mock global `fetch`. Cover: happy path returns `{text, stopReason}`; non-ok status throws; `timeoutMs` wires `AbortSignal.timeout` (assert via a fake-timers + abort pattern per `cq-abort-signal-timeout-vs-fake-timers`); empty `content` returns `{text: ""}` (caller, not helper, decides that is an error). Type any `vi.fn` spy whose `.mock.calls` you destructure as `(...args: unknown[])` (learning `2026-06-02-...` Gotcha #4 / TS2493).

### Phase 3 (Part 2) — Migrate the three sites to structured outputs

**Files to Edit:** `cron-weekly-release-digest.ts`, `cron-compound-promote.ts`, `domain-router.ts`, plus the three test files (`cron-weekly-release-digest.test.ts`, `cron-compound-promote.test.ts`, `domain-router.test.ts`).

For each site: add `output_config: { format: { type: "json_schema", schema: <SCHEMA> } }` to the request body and DROP the `extractModelJson(...)` wrapper around `JSON.parse(text)` (parse the now-fence-free text directly). Preserve every `stop_reason`/shape/fallback guard.

- **digest** (`postAnthropicMessage` gains `outputConfig`): schema = object `{ highlights: array of { tag: string, title: string, why: string } }`, `additionalProperties: false` on both the root and each highlight object, `required: ["highlights"]` / `["tag","title","why"]`. **Do NOT** add `maxItems: 5` — unsupported; the `MAX_HIGHLIGHTS` slice stays in TS. Keep the verbatim-tag eligibility filter (the model can still emit a tag outside the window even under schema; `eligibleTags` guard is load-bearing).
- **compound-promote** (`postAnthropicMessage` gains `outputConfig`): the model returns a **top-level array**. Structured-output root schemas are objects; wrap as `{ clusters: array of <cluster> }` and read `parsed.clusters`, OR confirm at `/work` whether a top-level `array` root is accepted by the API — **verify against the structured-outputs docs before choosing** (default to the object-wrapper form, which is documented-safe). Each cluster object needs `additionalProperties: false` + `required` for every field the downstream code reads (`cluster_hash`, `tier`, `target_path`, `source_learnings`, `proposed_diff_unified`, `rationale`, `byte_impact{before,after,delta}`). **Object-wrapper form requires THREE coordinated edits (P1, deepen-plan) — not just the schema:**
  1. Reword the prompt's output instruction: `cron-compound-promote.ts:389` (`Output ONLY the JSON array, nothing else.`) → `Output ONLY a JSON object with a "clusters" key, nothing else.`, and update the `Schema:` example line at `:385` to wrap the array in `{clusters: [...]}`. A schema that expects an object while the prompt still says "JSON array" gives the model contradictory instructions.
  2. Change the parse-site read from `parsed` → `parsed.clusters`.
  3. Change the shape guard `Array.isArray(parsed)` (`:442`) → `Array.isArray(parsed.clusters)` (keep the `reportSilentFallback` on the negative).
  Keep `slice(0, weekCapResult.remaining)`.
- **domain-router** (inline, no helper): schema = a JSON array of strings. Same root-shape consideration — wrap as `{ leaders: string[] }` (object root) and read `parsed.leaders`, then keep the existing `validIds` filter + `slice(0, MAX_LEADERS_PER_MESSAGE)` + `["cpo"]` fallback. Add `output_config` to the inline `fetch` body; do NOT add a timeout or change the model. Reword the prompt's `Respond with ONLY a JSON array like ["cmo","clo"]` (`domain-router.ts:145`) to match the object wrapper.
  - **Test gap (P1, deepen-plan):** the existing `test/domain-router.test.ts` covers ONLY `parseAtMentions` + the mention-override branch of `routeMessage` — both return BEFORE `classify`'s fetch is reached. It has **zero coverage of the classify/fetch/parse path**, so a green `domain-router.test.ts` after this change is vacuously true for the migrated path. Phase 3 MUST add at least one `classify` fetch-mock test: stub global `fetch` to return `{ content: [{ type: "text", text: '{"leaders":["cmo"]}' }], stop_reason: "end_turn" }` and assert (a) the request body contains `output_config` with the json_schema, (b) `parsed.leaders` is extracted + `validIds`-filtered + sliced, and (c) the `["cpo"]` fallback fires on a parse failure / non-ok response. Add `test/domain-router.test.ts` to the Files to Edit list for this phase.

**Acceptance Criteria — Phase 3:**
- AC6: `git grep -n "extractModelJson" -- apps/web-platform/server/` returns **0** (all production call sites migrated; only the def in `model-json.ts` + the test remain at this phase).
- AC7: each of the three request bodies contains `output_config` with a `json_schema` format (`git grep -n "output_config" -- apps/web-platform/server/ | wc -l` ≥ 3).
- AC8: no schema in the diff uses `minimum`/`maximum`/`maxItems`/`minLength`/`maxLength` (`git grep -nE "minItems|maxItems|minLength|maxLength|minimum|maximum" <changed schema lines>` returns 0) and every schema object declares `additionalProperties: false`.
- AC8b (prompt/schema agreement): if the object-wrapper form is used, the prompts no longer instruct the model to emit a top-level array — `git grep -nE "JSON array|a JSON array" -- apps/web-platform/server/inngest/functions/cron-compound-promote.ts apps/web-platform/server/domain-router.ts` returns 0 (both prompts reworded to the object wrapper).
- AC9: the three sites' suites green with updated/added fixtures — `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-weekly-release-digest.test.ts test/server/inngest/cron-compound-promote.test.ts test/domain-router.test.ts`. Updates: (a) the digest's "fence-wrapped JSON parsing" case (`cron-weekly-release-digest.test.ts:446-467`) is replaced with a plain schema-valid-JSON case (keep the max_tokens-fallback and shape-invalid-fallback cases; the `validAnthropicResponse` helper at `:129-137` already emits un-fenced `JSON.stringify({highlights})` and needs NO change); (b) a NEW `classify` fetch-mock test is added to `test/domain-router.test.ts` (the existing suite has zero classify-path coverage — see the domain-router bullet above), asserting `output_config` in the request body, `leaders` extraction+filter, and the `["cpo"]` fallback.

### Phase 4 (Part 2) — Delete `extractModelJson`

**Files to Delete:** `apps/web-platform/server/model-json.ts`, `apps/web-platform/test/server/model-json.test.ts`.

- Grep-before-delete gate (learning `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`): `git grep -n "extractModelJson\|model-json" -- apps/web-platform/ plugins/ scripts/` MUST return **0** matches outside `knowledge-base/` (plans/learnings may cite it). Only then delete.
- Remove the now-dead imports (`import { extractModelJson } from ...`) from all three sites in the same commit as the deletion (or earlier in Phase 3 — they are dead the moment the parse-site stops calling them).

**Acceptance Criteria — Phase 4:**
- AC10: `apps/web-platform/server/model-json.ts` and its test no longer exist; `git grep -n "extractModelJson" -- apps/web-platform/ plugins/ scripts/` returns 0.
- AC11: no dangling `model-json` import remains (`git grep -n 'from "@/server/model-json"' -- apps/web-platform/` returns 0).

### Phase 5 — Full-suite + typecheck exit gate

- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w` — the repo root declares no `workspaces`; the `-w` form aborts. The in-package `npm run typecheck` also works when cwd is the package).
- `cd apps/web-platform && npm run test:ci` (= `vitest run`) — full suite, to catch any orphan suite that imports `model-json` or asserts on the inline-fetch shape (per the emit-site-removal coupling Sharp Edge).

## Observability

```yaml
liveness_signal:
  what: Sentry cron check-in heartbeats for both crons (digest slug "cron-weekly-release-digest", compound slug "scheduled-compound-promote")
  cadence: per scheduled run (weekly digest; compound-promote per its cron)
  alert_target: existing Sentry cron monitors (infra/sentry/cron-monitors.tf) — unchanged by this refactor
  configured_in: postSentryHeartbeat() in _cron-shared.ts:164-216, called by each handler
error_reporting:
  destination: Sentry via reportSilentFallback (apps/web-platform/server/observability.ts)
  fail_loud: yes — preserved at each call site (NOT moved into postAnthropicMessage); message strings carried verbatim so dashboard-keyed alerts keep firing
failure_modes:
  - mode: Anthropic API non-2xx / network error
    detection: helper throws "Anthropic API ${status}"; Inngest step retry then handler catch → Sentry heartbeat (digest) / reportSilentFallback (compound)
    alert_route: existing Sentry cron-failure + silent-fallback alerts
  - mode: stop_reason "max_tokens" (truncated JSON)
    detection: existing per-site guard (digest throws; compound returns {truncated:true} + heartbeat) — preserved
    alert_route: Sentry heartbeat OK-with-status / no new route
  - mode: structured-output schema-invalid or refusal (stop_reason "refusal")
    detection (compound) — JSON.parse is inside try/catch (cron-compound-promote.ts:430-439) → reportSilentFallback "anthropic-cluster" Sentry event (preserved)
    detection (digest) — JSON.parse is NOT in a try/catch; a parse failure THROWS → Inngest step retry → handler-level catch → ok:false Sentry cron heartbeat (NOT a reportSilentFallback event). The empty-text and shape-invalid guards in the digest DO route through reportSilentFallback; raw parse failure routes through the heartbeat. Both preserved exactly.
    alert_route: compound → "anthropic-cluster" silent-fallback alert; digest → ok:false cron-monitor alert (parse) + curate silent-fallback alert (empty/shape)
logs:
  where: pino structured logs via handler logger + Sentry events
  retention: existing Better Stack / Sentry retention (unchanged)
discoverability_test:
  command: "rg -n 'reportSilentFallback|postSentryHeartbeat' apps/web-platform/server/inngest/functions/cron-weekly-release-digest.ts apps/web-platform/server/inngest/functions/cron-compound-promote.ts"
  expected_output: "≥1 reportSilentFallback and ≥1 postSentryHeartbeat per cron — the error/heartbeat paths remain at the call sites after extraction (NO ssh)"
```

## Domain Review

**Domains relevant:** engineering (CTO) — owned by the issue's `domain/engineering` label.

### Engineering / CTO

**Status:** reviewed (inline)
**Assessment:** Pure internal refactor of `apps/web-platform` server code. Net complexity reduction (one shared helper replaces two duplicated fetch blocks; one defensive helper deleted). Risk is concentrated in three behavior-preservation traps, all enumerated in Sharp Edges: (a) swapping the inline fetch for the helper must preserve each caller's throw-vs-fallback semantics; (b) structured-output schemas must avoid unsupported constraints and keep the post-parse TS caps; (c) `extractModelJson` deletion needs the grep gate. No architectural decision, no new dependency, no cross-domain surface.

### Product/UX Gate

NONE — no `.tsx` / `app/**/page.tsx` / component file in Files to Edit/Create; the mechanical UI-surface override does not fire. Internal automation refactor.

## GDPR / Compliance Gate

Skipped — no regulated-data surface touched (no schema/migration/auth/API-route/`.sql` change). The conditional triggers were checked: structured outputs change only the *response format* of an **already-existing** Anthropic-bound LLM call on the same data (release notes, learnings corpus, chat-routing text); no NEW processing activity, no new external API, no new distribution surface, threshold = none. The DPA/data-flow posture is identical before and after.

## Infrastructure (IaC)

None — pure code change against the already-provisioned `apps/web-platform` runtime. No server, service, cron, secret, DNS, or vendor account introduced (`ANTHROPIC_API_KEY` already exists and is read identically). No `## Infrastructure (IaC)` subsections required.

## Test Strategy

Framework: **vitest** (verified: `apps/web-platform/package.json` `scripts.test = "vitest"`, `test:ci = "vitest run"`; `vitest.config.ts` collects `test/**/*.test.ts` as the node project; `bunfig.toml` ignores all bun-test discovery). Commands:
- Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- Targeted: `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`
- Full suite (exit gate): `cd apps/web-platform && npm run test:ci`

New tests live under `test/server/inngest/` (node project glob). Reuse the existing `fetch`-mock + `validAnthropicResponse()` fixture pattern from `cron-weekly-release-digest.test.ts`. Synthesized fixtures only.

## Sharp Edges

- **Structured-output schemas reject the constraints these prompts imply.** `maxItems`/`maximum`/`minLength` are NOT supported; `additionalProperties: false` is REQUIRED on every object. The digest `MAX_HIGHLIGHTS` cap and compound `slice(0, remaining)` cap MUST stay as post-parse TS slices, not schema constraints. Verified via `claude-api` skill.
- **Top-level array roots:** compound-promote returns a top-level JSON array and domain-router returns a top-level string array. Structured-output root schemas are documented around object roots — default to wrapping (`{clusters: [...]}`, `{leaders: [...]}`) and adjust the parse site + prompt; verify the top-level-array option against the structured-outputs docs before relying on it. (Live-probe the exact request shape at `/work` if uncertain — doc silence is not support.)
- **Do NOT put `postAnthropicMessage` where domain-router could import it.** `_cron-shared.ts` drags in octokit/github-app; `domain-router.ts` is intentionally leaf-light (`model-json.ts:1-3`). domain-router migrates inline, no helper.
- **Helper must not own observability/fallback.** Keep `reportSilentFallback` + throw-to-fallback at each call site with verbatim message strings (dashboard-keyed). The helper is transport only (learnings `2026-05-12-centralized-at-helper-boundary...`, `2026-06-11-pipeline-consolidation-behavior-preserving-migration-traps.md`).
- **No model literal in `_cron-shared.ts`.** Pass the model as an arg; `model-tiers.test.ts`'s `RAW_MODEL_LITERAL` guard scans `functions/*.ts` for raw `"claude-…"` strings.
- **Behavior parity is the bar.** compound has no request timeout today — do NOT add one when routing through the helper (the digest passes `timeoutMs`, compound passes none). Swapping a throwing fetch for the helper must keep each caller's exact branch logic (`max_tokens` guard, empty-content guard, shape guard).
- **Grep-before-delete for `extractModelJson`** across `apps/web-platform/`, `plugins/`, `scripts/` (exclude `knowledge-base/`). `tsc` green ≠ no string-reference references.
- **Typecheck command is the in-package `tsc`, not `npm run -w`** — repo root has no `workspaces` field; `npm run -w apps/web-platform typecheck` aborts with "No workspaces found". Use `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- **Test path glob:** new `_cron-shared`/helper tests must live under `test/**/*.test.ts` (node project) — a co-located `functions/**/*.test.ts` is silently never collected by `vitest.config.ts`.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` body-grep for `cron-weekly-release-digest`, `cron-compound-promote`, `_cron-shared`, `domain-router`, `model-json` returned zero matches (checked 2026-06-11).
