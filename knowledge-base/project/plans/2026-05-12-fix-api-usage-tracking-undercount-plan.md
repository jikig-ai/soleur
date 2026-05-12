---
title: "fix: API usage tracking dramatically under-reports vs Anthropic Console"
type: fix
date: 2026-05-12
branch: feat-one-shot-fix-api-usage-tracking
issue: TBD
semver: minor
requires_cpo_signoff: true
deepened_on: 2026-05-12
---

# Fix: API Usage Tracking Dramatically Under-Reports vs Anthropic Console

## Enhancement Summary

**Deepened on:** 2026-05-12
**Sections enhanced:** 6 (Overview, Phase 1, Phase 2, Phase 3, Phase 5, Risks)
**Research dimensions:** Anthropic Admin API field shapes (live fetch), installed SDK `usage` types (`node_modules/@anthropic-ai/claude-agent-sdk/sdk-tools.d.ts:69-70`), Supabase migration 037 actual signature (live grep), existing `write_byok_audit` RPC contract.

### Key corrections from deepen pass

1. **Migration 043 is unnecessary.** `write_byok_audit(uuid, uuid, text, int, int)` **already exists** in `037_audit_byok_use.sql:79-96` with signature `(p_invocation_id, p_founder_id, p_agent_role, p_token_count, p_unit_cost_cents)`. The plan now binds to the existing RPC verbatim instead of creating a redundant migration. **Schema constraint surfaced:** the audit row carries a **single combined `token_count`** (not split input/output/cache) and `unit_cost_cents` is `int` (sub-cent precision lost). This is acceptable for the WORM forensic surface; the cent-precision UI continues to read `conversations.total_cost_usd`.
2. **Admin Cost API doc prose IS misleading but in a different way than originally written.** Re-reading the doc: `"amount: '123.45'` is in lowest currency units (e.g. cents) ... `'123.45'` in `'USD'` represents `$1.23`." This is *internally inconsistent* — `"123.45"` cents is `$1.2345`, not `$1.23`. The doc rounds the example to 2dp prose-side without saying so. **Verified treatment:** `Number(amount) / 100` preserves sub-cent precision (`$1.2345`); the pinned conversion test (Phase 1.3) defends against future drift in either direction.
3. **Admin Messages Usage Report shape ≠ SDK result message shape.** SDK exposes flat `cache_creation_input_tokens` + `cache_read_input_tokens` (verified at `node_modules/@anthropic-ai/claude-agent-sdk/sdk-tools.d.ts:69-70`). Admin API exposes NESTED `cache_creation: { ephemeral_1h_input_tokens, ephemeral_5m_input_tokens }` plus `cache_read_input_tokens` plus a NEW `uncached_input_tokens` field that the SDK does NOT expose flat (SDK's `input_tokens` is total-input-minus-cache-read, roughly equivalent to `uncached_input_tokens`). Phase 5's reconciliation must normalize both into a comparable shape (Phase 5.2 ¬ shape-normalization layer added).
4. **Admin API supports `api_key_ids[]` filter.** This is a real architectural lever: Soleur can fetch ONLY the rows for the user's specific API key by retrieving the key's `api_key_id` from the Anthropic Console at admin-key save time (or by inferring it from the Messages Usage Report `group_by: ["api_key_id"]` aggregate). Without this filter, an Admin key with multiple workspaces/keys would over-count.
5. **The semver label is `minor`, not `patch`.** Plan adds three new columns + a new optional UI surface (Phase 5). Per AGENTS.md "Plans should specify semver label intent", `minor` is the right label.

### New considerations discovered

- The SDK `usage.input_tokens` field on the result message is the **uncached** input tokens, not total input. Display must NOT label it as "Total input" — copy says "Input" but the literal number is uncached. The "true" total input is `uncached + cache_read + cache_creation` and that's what the Anthropic Console headline shows. The dashboard's MTD/per-row "Input" pill should switch to displaying the SUM (uncached + cache_read + cache_creation) for parity with the Console — otherwise the cross-check footnote remains technically false even after Phase 3 lands.
- Per migration 037 the WORM trigger raises on UPDATE/DELETE — Phase 3.1's `audit_byok_use` write MUST use INSERT only. No ON CONFLICT. No upsert. Idempotency belongs at the helper layer (skip if a per-turn key already wrote) or be tolerated as duplicate audit rows on retry.
- `audit_byok_use` schema has no `model` column. The model used per turn is captured at the `conversations` granularity (last model used) but NOT at the per-turn audit row. If multi-model per-conversation breakdown is ever a goal, a migration adds `model text` to `audit_byok_use` — for v1 it's a non-goal (NG1).
- Admin API `bucket_width: "1d"` snaps to UTC midnight. The dashboard renders "$X in May" against the user's locale month. For a user in a UTC- timezone whose month boundary differs from UTC, the Admin API total for "May 1 UTC → May 31 UTC" can differ from the user's locally-perceived month by up to one day's worth of cost at each end. **Mitigation:** Phase 5 labels the banner "Verified against Anthropic Console (UTC month)" to disambiguate. Sub-day reconciliation would require `bucket_width: "1h"` and is deferred (NG7).

## Overview

The "API Usage" panel in `/dashboard/settings/billing` shows **$0.24 / 1 conversation / 16 input tokens / 2,722 output tokens** for May, while the Anthropic Console reports **~921,944 input tokens / 5,750 output tokens / $0.57** for the same month on `claude-sonnet-4-6` for the same user/key. Multiple under-report axes stack:

1. **The cc-soleur-go runner does not call `increment_conversation_cost`.** `apps/web-platform/server/cc-dispatcher.ts:1202-1205` wires `onResult` as a no-op stub with the comment "wire in Stage 3 when the aggregate conversation cost reader lands". Every conversation routed through `dispatchSoleurGo` (i.e., every non-`kind: "legacy"` route — which is the chat surface today) emits cost telemetry into the void. The dashboard reads `conversations.total_cost_usd` which is mutated only by the legacy `agent-runner.ts:1880` RPC call. **This is the primary cause of the 60-90% undercount.**
2. **Cache tokens are never persisted.** Anthropic SDK surfaces `usage.cache_creation_input_tokens` and `usage.cache_read_input_tokens`; the schema (migration 017) only has `input_tokens` and `output_tokens`. Cache-read input tokens were explicitly cut from the original BYOK plan (`feat-byok-cost-tracking/spec.md` NG, see brainstorm 2026-04-10) but with prompt caching turned on (`scripts/spike/cache-control-forwarding.ts`) the bulk of "real" input tokens land in `cache_read_input_tokens` and are silently dropped from both the per-row display and the MTD sum.
3. **The schema-without-writer table `audit_byok_use` was provisioned by migration 037 but no code writes to it.** Open scope-out #3392 documents this as the unfinished PR-D §3.5 wire-up (`record_byok_use_and_check_cap`). The dashboard read path doesn't read it either.
4. **No org-level reconciliation source exists.** The Anthropic Admin API exposes `/v1/organizations/usage_report/messages` and `/v1/organizations/cost_report` — the same data the Anthropic Console renders — and would catch any class of under-write at the application layer (router-only costs, sub-agent costs, retry costs, system-prompt cache writes, web-search/code-exec server-tool costs).

This plan closes the three application-layer holes (cc-dispatcher cost write, cache-token persistence, BYOK audit writer) AND adds an optional Admin Usage/Cost API reconciliation surface for users who provide an Admin API key. Application-layer + reconciliation together close the loop: the per-conversation list keeps its narrative ("this conversation cost $X"), the Admin API gives the unambiguous month total that always matches the Console.

## User-Brand Impact

**If this lands broken, the user experiences:** the API Usage section continues to under-count by 50-99% (today's state), or — worse — shows costs that exceed reality and lose user trust in the no-markup positioning that CMO won during 2026-04-17 ("Actual API cost", no "estimated" hedging, footnote inviting Anthropic Console cross-check). The brand positioning of the dashboard is **"figures come straight from the Anthropic SDK ... cross-check any row in your Anthropic Console under Usage — the numbers will match to the cent."** This claim is currently false. A user who follows the footnote sees a 4-50x discrepancy. The "no markup" trust differentiator collapses for any user who actually verifies.

**If this leaks, the user's data is exposed via:** N/A — usage data is the user's own data scoped by `user_id` and RLS. No new data category is added. Per-row totals stay on `conversations` (no per-message granularity added). If the Admin Usage/Cost API path is added, the Admin key is encrypted at rest using the existing BYOK envelope (HKDF per-user, AES-GCM, same as `api_keys`), and lives in the same `api_keys` table with `provider = "anthropic_admin"`.

**Brand-survival threshold:** `single-user incident`. One user who cross-checks against the Anthropic Console and posts a 4x discrepancy publicly (the exact footnote we invite) is a brand-survival event for the no-markup positioning. CPO sign-off required: the existing precedent (brainstorm 2026-04-17 §Marketing/CMO) already governs the framing — the choice to ship "Actual API cost" labelling, and the QA gate "one real conversation cross-checked against Anthropic console during QA; values match to the precision rendered" (`feat-restore-byok-usage-dashboard/spec.md` AC #11), is the contract. This plan reinstates that contract.

## Research Reconciliation — Spec vs. Codebase

| Spec / Brainstorm Claim | Reality (verified 2026-05-12) | Plan Response |
|---|---|---|
| `feat-byok-cost-tracking/spec.md` FR1: "Capture `total_cost_usd`, `usage` (input/output/cache tokens), and `modelUsage` (per-model breakdown) from SDK result messages in `agent-runner.ts`" | Cache tokens never captured; `modelUsage` never persisted (schema dropped them per `feat-restore-byok-usage-dashboard/brainstorm.md` §Per-model breakdown). Only `input_tokens` + `output_tokens` written. | Persist `cache_read_input_tokens` + `cache_creation_input_tokens` (new columns) AND backfill the cc-soleur-go path's writer; defer model-level breakdown to a follow-up. |
| `feat-restore-byok-usage-dashboard/spec.md` AC #11: "QA gate: one real conversation cross-checked against Anthropic console during QA; values match to the precision rendered" | The 2026-04-17 ship verified one legacy-routed conversation. The cc-soleur-go path was not routed by the chat surface in that QA window. The current chat surface routes through cc-dispatcher whose `onResult` is a no-op, so AC #11 is silently violated on every chat conversation today. | Add a pre-merge probe: run a fresh chat-case conversation through cc-soleur-go, read the resulting `total_cost_usd` from Supabase, cross-check the SAME `request_id` (or per-conversation total within a 5-minute window) against the Admin Usage Report API. Pin both in the PR description. |
| #3392 says PR-D §3.5 will wire `record_byok_use_and_check_cap` against `audit_byok_use`. | PR-D never landed (`rg record_byok_use_and_check_cap` returns 0 hits). The migration shipped 4 weeks ago without a writer. | Decide explicitly in this plan: (a) write to `audit_byok_use` for forensic/audit parity OR (b) drop the table in a follow-up if conversation-level writes are the source of truth. Default: (a), because forensic per-invocation rows survive conversation deletion and unblock the future "Today" surface PR-D §3.1 mentions. |
| Anthropic Admin Cost API doc example says `amount: "123.45"` in USD represents `$1.23`. | Decimal string in lowest currency units = cents. So `"123.45"` cents = `$1.2345`. The doc's prose example contradicts the field semantics (verified by example field `"123.45"` would otherwise round to `$1.23` losing 0.45¢). | Plan treats `amount` as **cents (decimal string, 2-decimal sub-cent precision)** and converts via `Number(amount) / 100`. Add a unit test pinning the conversion at $1.2345 to defend against the doc's misleading prose. |

## Open Code-Review Overlap

5 open scope-outs touch files this plan will edit:

- **#3392 — review: PR-B (#3244) deferrals.** **Fold in (partial)** the `audit_byok_use` writer sub-finding (§"audit_byok_use writer"). The other 5 sub-findings (denied_jti wire-up, timer pair, /proc test, mock DRY, allowlist tightening) stay deferred — they are not on the under-count critical path. Close one sub-bullet with this PR; leave the issue open.
- **#3243 — arch: decompose cc-dispatcher.ts into focused modules.** **Acknowledge.** This plan adds ~30 LoC to `cc-dispatcher.ts` `realSdkQueryFactory` and `onResult` (plus a small helper extraction for the cost writer). It does not perform the larger decomposition. Rationale: bundling the under-count fix with a 1000+ line restructure would double the review surface for an urgent brand-survival bug.
- **#3242 — review: tool_use WS event lacks raw name field.** **Acknowledge.** Unrelated to cost tracking.
- **#3343 — review: case-insensitive `</document>` escape across cc + leader prompt builders.** **Acknowledge.** Unrelated to cost tracking.
- **#3370 — Dev Supabase _schema_migrations tracking table drifts.** **Acknowledge.** This plan adds new migrations; the verification path (`supabase migration list`) will surface the drift independently. Out of scope.

## Implementation Phases

### Phase 1 — Diagnostic probe & baseline (RED)

Before any code change, prove the size of the gap with a deterministic probe.

- **1.1** Write `apps/web-platform/scripts/spike/usage-tracking-gap-probe.ts` (one-off, not shipped) that:
  1. Reads MTD `total_cost_usd` sum from Supabase for a chosen test user via `loadApiUsageForUser`.
  2. Reads MTD totals from the Anthropic Admin Cost Report API (`GET /v1/organizations/cost_report?starting_at=<month-start>&bucket_width=1d`) using a provided admin key.
  3. Reads MTD token totals from the Anthropic Admin Messages Usage Report API.
  4. Prints a 3-column table: `Supabase | Admin Cost API | Admin Usage API` with the per-axis ratio.
- **1.2** Add `test/api-usage-gap.test.ts` with a fixture that simulates the cc-soleur-go path: a Query factory whose `onResult` carries `total_cost_usd: 0.0042` and `usage.input_tokens: 521, output_tokens: 88, cache_read_input_tokens: 14_000, cache_creation_input_tokens: 800`. Assert that after the turn, `conversations.total_cost_usd === 0.0042` and the four token columns match. **This test fails today** — that's the RED.
- **1.3** Add `test/api-usage-admin-report-shape.test.ts` pinning Anthropic Admin Cost API decimal-string → USD conversion at `$1.2345` for `"123.45"` cents (defends against the docs' misleading prose example).

### Phase 2 — Schema migrations

- **2.1** Migration `041_conversation_cache_tokens.sql` — add `cache_read_input_tokens INTEGER NOT NULL DEFAULT 0` + `cache_creation_input_tokens INTEGER NOT NULL DEFAULT 0` to `conversations` with the matching `>= 0` CHECK constraint. Extend the `INCLUDE` list of `idx_conversations_user_cost` (created in 027) to cover the new columns so the dashboard list query stays index-only. **Note:** migration 017 + 027 + 041 establish the convention — keep `NOT NULL DEFAULT 0` so existing rows are valid; no backfill from Admin API in this PR (deferred). Drop & recreate the index in the same migration (Supabase wraps in a transaction; CONCURRENTLY forbidden per `2026-04-18-supabase-migration-concurrently-forbidden`).
- **2.2** Migration `042_increment_conversation_cost_v2.sql` — replace `increment_conversation_cost(UUID, NUMERIC, INT, INT)` with the v2 signature `(UUID, NUMERIC, INT, INT, INT, INT)` (adds `cache_read_delta`, `cache_creation_delta`). Must `DROP FUNCTION IF EXISTS public.increment_conversation_cost(UUID, NUMERIC, INTEGER, INTEGER);` then `CREATE OR REPLACE` with new signature; `REVOKE EXECUTE` from PUBLIC/authenticated/anon, `GRANT EXECUTE` to service_role only (mirrors 017 ACL).
- **2.3** **DROPPED — `write_byok_audit` already exists.** Deepen pass confirmed that migration `037_audit_byok_use.sql:79-96` ships `public.write_byok_audit(p_invocation_id uuid, p_founder_id uuid, p_agent_role text, p_token_count int, p_unit_cost_cents int)` with the correct WORM trigger + ACL (`REVOKE FROM PUBLIC, anon, authenticated; GRANT TO service_role`). **What was missing is the CALLER**, not the function. #3392's "audit_byok_use writer" sub-finding refers to wiring the caller, not creating the RPC. Phase 3.1 binds to the existing signature verbatim. **Constraint surfaced:** single combined `token_count` (not split) and `int` cents — see Risks §R7.

### Phase 3 — Wire the cc-soleur-go cost writer (the smoking gun)

- **3.1** Extract `apps/web-platform/server/cost-writer.ts` with a `persistTurnCost(userId, conversationId, leaderId, modelHint, result)` helper that:
  - Calls `increment_conversation_cost` v2 RPC with the 5 deltas.
  - Calls `write_byok_audit(p_invocation_id, p_founder_id, p_agent_role, p_token_count, p_unit_cost_cents)` fire-and-forget. **Signature constraints (verified migration 037:79-96):** (a) `p_invocation_id` is a uuid — generate a fresh `crypto.randomUUID()` per turn (no per-message granularity required); (b) `p_token_count` is a single int → use `usage.input_tokens + usage.output_tokens + (usage.cache_read_input_tokens ?? 0) + (usage.cache_creation_input_tokens ?? 0)` (sum-of-all-tokens, the forensic axis); (c) `p_unit_cost_cents` is int → use `Math.round(total_cost_usd * 100)` (sub-cent precision lost intentionally — the cent-precision surface stays on `conversations.total_cost_usd`); (d) `p_agent_role` is text → use `leaderId ?? "cc-soleur-go"`. WORM trigger raises on UPDATE/DELETE, so use plain INSERT semantics via `.rpc()` and accept duplicate audit rows on retry (idempotency is not load-bearing for a forensic surface).
  - Fans out `usage_update` WS event with the same shape `agent-runner.ts:1898` already sends, widened to include `cacheReadInputTokens` + `cacheCreationInputTokens`.
  - Mirrors silent fallbacks to Sentry per `cq-silent-fallback-must-mirror-to-sentry`.
  - Stage-2 typed `UsageDeltas` interface widening — surfaces `cache_read_input_tokens` + `cache_creation_input_tokens` to all consumers.
  - **Implementation note:** SDK exposes flat `cache_creation_input_tokens` + `cache_read_input_tokens` (verified at `node_modules/@anthropic-ai/claude-agent-sdk/sdk-tools.d.ts:69-70`). These can be `null` per SDK type — coerce with `?? 0` at the boundary so DB writes never see NULL on a NOT NULL column.
- **3.2** Soleur-go-runner: widen `onResult` event payload from `{ totalCostUsd: number }` to `{ totalCostUsd: number; usage: UsageDeltas; modelHint: string | null }` at `soleur-go-runner.ts:662`. Source from `msg.usage` and `msg.model` (the SDK result message). All consumer call sites (cc-dispatcher, tests) must update. Per `cq-union-widening-grep-three-patterns`, after the edit run `tsc --noEmit` and treat every `not assignable` error as a rail to widen — DO NOT pre-enumerate.
- **3.3** cc-dispatcher: replace the `onResult: (_result) => {}` no-op stub at `cc-dispatcher.ts:1202-1205` with a call to `persistTurnCost(userId, conversationId, CC_SOLEUR_GO_LEADER_ID, result.modelHint, result)`. Stay fire-and-forget — turn termination must not block on DB writes. Keep the legacy agent-runner.ts:1880 path untouched; both paths converge on the same helper.
- **3.4** Update tests: `agent-runner-cost.test.ts` plus new `cc-dispatcher-cost.test.ts` asserting (a) cc-soleur-go conversations write the same deltas the SDK emitted, (b) cache tokens are persisted, (c) `audit_byok_use` row is written, (d) usage_update WS event carries cache deltas.

### Phase 4 — Display surface

- **4.1** `apps/web-platform/server/api-usage.ts` — `ConversationListRow` gains `cache_read_input_tokens`, `cache_creation_input_tokens`. `ApiUsageRow` gains `cacheReadTokens`, `cacheCreationTokens`. The SELECT at `:90` expands to include the two new columns. `monthRes` RPC stays the same (still summing `total_cost_usd`).
- **4.2** `apps/web-platform/components/settings/api-usage-section.tsx` — per-row display gains a "Cache read" pill (only renders when `> 0`) and "Cache write" pill. Header stays unchanged ("$X in May · N conversations"). Per-conversation list row shape stays "one row, multiple stat pills" — no schema redesign.
- **4.3** Copy: extend the existing tooltip set with a "What about cache tokens?" tooltip (`api-usage-info-tooltip.tsx`) explaining that prompt caching reduces real cost: input pricing is split between uncached/cache-write/cache-read, all three are billed by Anthropic and shown here. Footnote unchanged — values still match the Anthropic Console.
- **4.4** Update `api-messages.ts` GET endpoint to surface the two new token columns in its 200 response (chat-surface cost badge restoration on resume; pairs with the `2026-04-16-kb-chat-cost-estimate-not-restored-on-resume.md` learning).

### Phase 5 — Anthropic Admin Usage & Cost API integration (DEFERRED to #3629)

**Status (2026-05-12):** Deferred to follow-up issue [#3629](https://github.com/jikig-ai/soleur/issues/3629). Phases 1-4 land in PR #3626; Phase 5 is opt-in and adds ~1500 LoC. Splitting keeps PR #3626's blast radius manageable while restoring the cross-check footnote immediately. The detail below is preserved for the #3629 author.



This is the **complementary org-level truth-source**. Single-user use case: a user who provides both their workspace API key (for inference) AND their Admin API key (for reconciliation) gets a "Verified against Anthropic Console: $X.YZ ✓" row at the top of the API Usage section.

- **5.1** Storage: re-use the existing `api_keys` table with `provider = "anthropic_admin"` (add to `PROVIDER_CONFIG`). Same HKDF-per-user envelope, same `runWithByokLease` scope at fetch time. **Do not** persist the Admin key in any cache outside the lease — same threat model as the regular Anthropic key. Add it as a service token (per the `getUserServiceTokens` shape) but with a dedicated typed loader because the consumer is server-side reconciliation, not the agent runtime.
- **5.2** Module `apps/web-platform/server/anthropic-admin-client.ts`:
  - `fetchCostReport({ adminKey, startingAt, endingAt }): Promise<{ totalCostUsdSubCents: number; perWorkspace: ...; perTokenType: ...; }>` — paginates via `next_page`, handles `has_more`. **Field semantics:** `amount` is a decimal string in cents (per Phase 1.3 pinned test); preserve sub-cent precision via `Number(amount) / 100`. **Auth:** `X-Api-Key: ${adminKey}` header + `anthropic-version: 2023-06-01` header (per the cURL example).
  - `fetchMessagesUsageReport({ adminKey, apiKeyId?, startingAt, endingAt, groupBy: ["model"] }): Promise<NormalizedUsageReport>` — same pagination. **Critical: pass `api_key_ids[]=<apiKeyId>` when the user has registered their workspace API key separately.** Without the filter, an admin key spanning multiple workspaces or multiple API keys over-counts. If `apiKeyId` is unknown, fall back to the workspace-wide total and label the banner "Verified against your Anthropic workspace (all keys)".
  - **Shape normalization layer.** The Admin API returns nested `cache_creation: { ephemeral_1h_input_tokens, ephemeral_5m_input_tokens }` + flat `cache_read_input_tokens` + `uncached_input_tokens` + `output_tokens`. The SDK returns flat `cache_creation_input_tokens` + `cache_read_input_tokens` + `input_tokens` (uncached) + `output_tokens`. Normalize Admin response to the SDK-flat shape via `cache_creation_input_tokens = cache_creation.ephemeral_1h_input_tokens + cache_creation.ephemeral_5m_input_tokens` and `input_tokens = uncached_input_tokens`. **Unit test in Phase 5.6** pins this normalization against a synthetic Admin response with non-zero `ephemeral_1h` AND `ephemeral_5m` values to defend against drift.
  - Bounded `AbortSignal.timeout(30_000)` per request; surface failures via `reportSilentFallback` rather than throwing (the section already has an ErrorState).
  - Add a 60-second in-memory cache keyed by `(userId, monthStartIso)` so the per-RSC-render cost stays bounded even when the user opens the dashboard repeatedly.
- **5.3** Loader: `loadAdminUsageForUser(userId)` runs in parallel to the existing `loadApiUsageForUser` in `api-usage-section.tsx`. Returns `null` if the user has no admin key on file (graceful empty), or a reconciled `{ adminMtdUsd, sdkMtdUsd, deltaPct }` triple.
- **5.4** UI: a single banner row above the per-conversation list:
  - If admin key present + APIs reachable: "Verified against Anthropic Console: **$0.57** · matches your in-app total to within $0.001 ✓" (green) OR "**Discrepancy**: $0.24 in-app vs $0.57 on Anthropic Console (-58%). Likely a tracking gap — please report." (yellow, with a "Report" link to a prefilled GitHub issue).
  - If no admin key: a faint "Add an Admin API key to verify against your Anthropic Console" link.
  - No PII in the report-link prefill (founder_id only, no key material).
- **5.5** A `/dashboard/settings/services` UI tile for the Admin API key — mirror the existing OpenAI/GitHub service token tiles. Form validation against the admin-key prefix (`sk-ant-admin-...`); a probe call to `GET /v1/organizations/cost_report?starting_at=<now>&limit=1` on save to verify the key works before persisting; encrypt + store on success.
- **5.6** Tests:
  - Unit: `admin-client.test.ts` — pagination, decimal-string conversion, timeout, error mapping.
  - Unit: `admin-client-pagination.test.ts` — assert `has_more: true` triggers the `next_page` follow-up and that the aggregated total matches.
  - Integration: `api-usage-admin-reconcile.test.ts` — synthetic admin response with known totals, assert the banner renders the correct delta colour and copy.
  - Pinned doc-conformance: `admin-cents-conversion.test.ts` — `"123.45"` cents → `1.2345` USD (defends against the doc-prose-vs-field-semantics mismatch).

### Phase 6 — QA gate & validation

- **6.1** Reproduce the original bug: open the dashboard before deploying any code, screenshot the May totals against the Anthropic Console. Pin both in PR body. Use a fresh chat-case conversation to confirm the no-op `onResult` is reachable in current production routing.
- **6.2** Deploy migrations 041 + 042 + 043 to **dev Supabase first** per `hr-dev-prd-distinct-supabase-projects`. Verify each migration applies cleanly via `supabase migration list`. Apply to prd only after dev confirms via the in-app dashboard.
- **6.3** Manual reconciliation: with the dev deployment + a fresh chat-case conversation, read `conversations.total_cost_usd` directly from dev Supabase and compare against the same conversation's row in the dev Anthropic workspace's Console. **Must match to the cent.**
- **6.4** If Phase 5 is included: provide an admin key, refresh the dashboard, confirm the green "Verified against Anthropic Console ✓" banner renders with deltaPct ≤ 0.5%.
- **6.5** Sentry budget: scan `silent-fallback` events for 24h post-deploy with `feature: "agent-cost-tracking"` or `feature: "anthropic-admin-client"` and pin the count in a follow-up comment on the issue.

## Files to Edit

- `apps/web-platform/server/cc-dispatcher.ts` — wire `onResult` (Phase 3.3)
- `apps/web-platform/server/soleur-go-runner.ts` — widen `onResult` event payload (Phase 3.2)
- `apps/web-platform/server/agent-runner.ts` — refactor cost write to use shared helper (Phase 3.1)
- `apps/web-platform/server/api-usage.ts` — select cache token columns (Phase 4.1)
- `apps/web-platform/server/api-messages.ts` — surface cache tokens in 200 (Phase 4.4)
- `apps/web-platform/components/settings/api-usage-section.tsx` — render cache pills (Phase 4.2)
- `apps/web-platform/components/settings/api-usage-info-tooltip.tsx` — new tooltip (Phase 4.3)
- `apps/web-platform/lib/types.ts` — widen `usage_update` WSMessage variant with cache tokens (Phase 3.2)
- `apps/web-platform/lib/ws-client.ts` — propagate cache tokens through `usage_update` handler (Phase 3.2)
- `apps/web-platform/lib/chat-state-machine.ts` — accept cache tokens in cost state (Phase 3.2)
- `apps/web-platform/server/providers.ts` — add `anthropic_admin` PROVIDER_CONFIG entry (Phase 5.1)
- `apps/web-platform/server/byok-lease.ts` — extend lease shape to optionally yield admin key (Phase 5.1)
- All consumers flagged by `tsc --noEmit` after the `onResult` widening (Phase 3.2) — per `2026-05-07-tsc-not-source-grep-enumerates-exhaustiveness-rails`, do not pre-enumerate exhaustiveness sites.

## Files to Create

- `apps/web-platform/supabase/migrations/041_conversation_cache_tokens.sql`
- `apps/web-platform/supabase/migrations/042_increment_conversation_cost_v2.sql`
- ~~`apps/web-platform/supabase/migrations/043_write_byok_audit_function.sql`~~ **[Dropped 2026-05-12 deepen pass — `write_byok_audit` already shipped in migration 037; the gap was the caller, not the function.]**
- `apps/web-platform/server/cost-writer.ts`
- `apps/web-platform/server/anthropic-admin-client.ts` (Phase 5)
- `apps/web-platform/server/api-usage-admin.ts` (Phase 5 — admin loader)
- `apps/web-platform/scripts/spike/usage-tracking-gap-probe.ts` (Phase 1.1, not committed for prod)
- `apps/web-platform/test/api-usage-gap.test.ts`
- `apps/web-platform/test/api-usage-admin-report-shape.test.ts`
- `apps/web-platform/test/cc-dispatcher-cost.test.ts`
- `apps/web-platform/test/admin-client.test.ts` (Phase 5)
- `apps/web-platform/test/admin-client-pagination.test.ts` (Phase 5)
- `apps/web-platform/test/api-usage-admin-reconcile.test.ts` (Phase 5)
- `apps/web-platform/test/admin-cents-conversion.test.ts` (Phase 5)

## Acceptance Criteria

### Pre-merge (PR)

1. **Cost write parity:** a fresh chat-case conversation routed through `dispatchSoleurGo` writes `total_cost_usd`, `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens` to its `conversations` row matching the SDK result message's `usage` object exactly (after `?? 0` coercion for SDK's nullable cache fields). Verified by `cc-dispatcher-cost.test.ts`.
2. **Audit row written:** the same conversation produces one `audit_byok_use` row per turn via the existing `write_byok_audit` RPC, with `token_count = uncached_input + output + cache_read + cache_creation` and `unit_cost_cents = round(total_cost_usd * 100)`. Verified by query in test. NOT idempotent on retry (WORM table) — duplicate audit rows on retry are tolerated.
3. **Cache token display:** the API Usage section UI renders a "Cache read" pill on rows where `cache_read_input_tokens > 0` and a "Cache write" pill on rows where `cache_creation_input_tokens > 0`. The existing "Input" pill renders `(input_tokens + cache_read_input_tokens + cache_creation_input_tokens)` so it matches the Anthropic Console's headline total input (per R8).
4. **MTD aggregate unchanged for legacy rows:** the `sum_user_mtd_cost` RPC still returns the same SUM for conversations that pre-date this PR. Verified by `api-usage-parity.test.ts` (already exists; extend with a cache-token fixture).
5. **Schema additivity:** migrations 041 + 042 apply cleanly on a copy of dev Supabase; existing rows are NOT NULL-violating (default 0). Migration 043 dropped from plan — `write_byok_audit` already shipped in 037.
6. **Cross-check:** ONE real chat-case conversation in dev cross-checked against the dev Anthropic workspace's Console. Pin both screenshots in PR body. Numbers MUST match to the cent on `total_cost_usd`; "Total input" (uncached + cache_read + cache_creation) MUST match to the token.
7. **No new dependencies** for Phases 1-4. Phase 5 may use `globalThis.fetch` (Node 20+ stdlib) — no `@anthropic-ai/sdk` admin client; the surface is too small.
8. **TypeScript:** `tsc --noEmit` passes; the widened `onResult` payload covers every consumer (legacy + cc-soleur-go + tests). Per `2026-05-07-tsc-not-source-grep-enumerates-exhaustiveness-rails`, do NOT pre-enumerate consumer sites — treat each `tsc` error as a rail to widen.
9. **Tests:** all new tests RED before Phase 3 changes, GREEN after.
10. **Open scope-out #3392** has its `audit_byok_use writer` sub-finding ticked or closed via the post-merge close step (use `Ref #3392` in PR body per `wg-use-closes-n-in-pr-body-not-title-to`; the issue remains open for the other sub-bullets — close only the audit_byok_use bullet manually).
11. **Decimal-string-cents conversion** has a pinned unit test asserting `"123.45"` cents = `$1.2345` (Phase 5 only).
12. **Admin shape normalization** has a pinned unit test asserting nested `cache_creation: {ephemeral_1h_input_tokens: 100, ephemeral_5m_input_tokens: 200}` collapses to flat `cache_creation_input_tokens: 300` (Phase 5 only).
13. **api_key_ids[] filter** is exercised in `admin-client.test.ts` — when a `apiKeyId` is provided, the fetch URL contains `api_key_ids[]=<id>` (URL-encoded); when omitted, the URL does NOT contain the parameter.

### Post-merge (operator)

14. Migrations 041 + 042 applied to dev (`supabase migration list`).
15. Migrations 041 + 042 applied to prd after 1 dev-day soak.
16. Dashboard refreshed; live cross-check against the user's Anthropic Console for May. Discrepancy ≤ $0.01 OR (with admin key) the green "Verified ✓" banner renders.
17. Sentry `silent-fallback` 24h budget check: `feature: "agent-cost-tracking"` and `feature: "anthropic-admin-client"` events stable or lower than pre-deploy baseline.
18. `gh issue comment <#3392> --body "audit_byok_use writer sub-finding closed by PR #<this>; other sub-bullets remain open."` to keep the umbrella issue accurate per `cq-rule-ids-are-immutable`-style audit-trail discipline.

## Test Scenarios (Given / When / Then)

- **Given** a cc-soleur-go chat conversation whose SDK result emits `total_cost_usd: 0.0042, usage.input_tokens: 521, usage.output_tokens: 88, usage.cache_read_input_tokens: 14_000, usage.cache_creation_input_tokens: 800`; **When** the turn completes via `cc-dispatcher.ts`; **Then** `conversations` row has all five deltas committed and one `audit_byok_use` row appended with matching values.
- **Given** a user with no Admin API key on file; **When** the user opens `/dashboard/settings/billing`; **Then** the per-conversation list renders unchanged (no banner regression) and a single faint "Add Admin API key to verify" link appears.
- **Given** a user with a valid Admin API key on file and a $0.57 month total in the Anthropic Console; **When** the dashboard loads; **Then** the banner renders `Verified against Anthropic Console: $0.57 · matches your in-app total to within $0.001 ✓`.
- **Given** a user with an Admin API key whose in-app total is $0.24 but Console total is $0.57 (today's state); **When** the dashboard loads; **Then** the banner renders the yellow discrepancy form with a Report link.
- **Given** the Admin API returns `amount: "123.45"` cents; **When** `Number(amount) / 100` is applied; **Then** the result is `1.2345`, not `1.23` (defends against the doc-prose-vs-field-semantics misread).
- **Given** the Admin Cost Report has `has_more: true`; **When** `fetchCostReport` is invoked; **Then** the second page is fetched via `next_page` and the totals are aggregated.

## Risks

- **R1 (HIGH) — sub-cent persistence drift.** `total_cost_usd NUMERIC(12, 6)` truncates Anthropic cents at the 5th decimal (Anthropic cost report emits up to 2-decimal sub-cents in the `amount` decimal string). For a $0.0042 row this is moot; for high-volume aggregations the drift is < $0.001 per conversation but compounds. Verified by the existing `api-usage-parity.test.ts` AC1 wide bound. **Mitigation:** widen to `NUMERIC(14, 8)` in a follow-up if real deployments show drift > $0.01 MTD; cosmetic for v1.
- **R2 (MEDIUM) — server-tool cost untracked at app layer.** `cost_report` lists `cost_type: "web_search"` and `"code_execution"`; per-turn `total_cost_usd` from the SDK already includes server-tool cost, but the per-message `usage` object doesn't break it out. The discrepancy between SDK and Admin Cost Report should therefore be near-zero. **Mitigation:** if Phase 6.3 shows a residual gap, file a follow-up to break out server-tool cost using `group_by: ["description"]` on the cost report.
- **R3 (MEDIUM) — concurrent multi-leader cost double-count.** The existing `increment_conversation_cost` v1 is documented as race-safe (migration 017 §Atomic increment). The v2 signature preserves the atomic UPDATE pattern. **Mitigation:** test `cc-dispatcher-cost.test.ts` includes a concurrent-turn fixture.
- **R4 (LOW) — Admin API rate limits.** The Anthropic Admin API does not publish explicit rate limits in the public docs as of 2026-05-12 fetch. Phase 5 page loads call the Admin Cost Report once per dashboard render. **Mitigation:** the loader is a React Server Component that runs per-request; if observed >5 req/s, add a 60-second in-memory cache keyed by `(userId, monthStart)`.
- **R5 (LOW) — Admin API beta header changes.** The doc currently allows `anthropic-beta` headers (optional). The plan does NOT pin a beta. **Mitigation:** if Anthropic ships a breaking change requiring a beta header, the API will return a clear 4xx with `error.type`; the loader's silent-fallback path surfaces this to Sentry.
- **R6 (MEDIUM) — schema drift between dev and prd.** Per learning `hr-dev-prd-distinct-supabase-projects` and #3370. **Mitigation:** apply to dev first; reconcile `_schema_migrations` per the runbook; do NOT apply to prd until dev is green for at least one workflow.
- **R7 (LOW) — audit_byok_use precision loss.** The existing `write_byok_audit` RPC takes a single combined `token_count int` and `unit_cost_cents int`. For sub-cent conversations (`$0.0042`), `Math.round(0.0042 * 100) = 0` — the audit row records `unit_cost_cents=0` while `conversations.total_cost_usd=0.004200`. **This is intentional.** The cent-precision UI reads from `conversations`; `audit_byok_use` is the forensic WORM surface where ¢-resolution is acceptable. Do NOT display `audit_byok_use.unit_cost_cents` in the dashboard list — data-quality mismatch with `conversations.total_cost_usd`. Documented in Sharp Edges.
- **R8 (MEDIUM) — "Input" pill semantics mismatch.** SDK `usage.input_tokens` is uncached-input-only; Anthropic Console shows total input (uncached + cache_read + cache_creation). Today's dashboard renders SDK `input_tokens` under a label "Input" — for cached prompts (`scripts/spike/cache-control-forwarding.ts`), the rendered Input value is ~5-15% of the Console's headline number. **Mitigation:** in Phase 4.2, change the "Input" pill to render `inputTokens + cacheReadInputTokens + cacheCreationInputTokens` (total bytes of context Anthropic billed). Add tooltip "Total input tokens, including cache reads. Anthropic prices these at different rates — see the Cache pills for the breakdown." Otherwise the cross-check footnote stays false even after the cc-dispatcher hole is closed.
- **R9 (LOW) — multi-workspace admin key over-count.** A user with one Anthropic admin key spanning multiple workspaces would see the banner's "Verified" total include workspaces unrelated to Soleur. **Mitigation:** Phase 5.2's `api_key_ids[]` filter narrows to the specific key Soleur uses. If the user's admin key is org-wide but their Anthropic API key has not been "linked" to Soleur (no `api_key_id` captured at admin-key save time), the banner falls back to workspace-wide and labels "(all keys)". The fallback path is acceptable for v1; a "link your API key" UX is deferred.
- **R10 (LOW) — UTC month boundary mismatch.** Admin Cost API `bucket_width: "1d"` snaps to UTC midnight. Dashboard `computeMonthStartIso` already uses UTC (`api-usage.ts:40-43`), so the in-app MTD total is UTC-month-aligned. **Mitigation:** label the banner "Verified against Anthropic Console (UTC month)" for explicit alignment.

## Non-Goals

- **NG1 — per-model breakdown.** The schema doesn't carry `model_usage` JSONB (cut in the 2026-04-17 ship). Display the last model used per conversation as a column ONLY if the Admin Usage Report makes per-model data trivially available; otherwise defer.
- **NG2 — Admin API auto-backfill of historical data.** This PR captures forward-going data only. A separate backfill PR could backfill `conversations.total_cost_usd` from the Admin Cost Report for the last N days.
- **NG3 — per-turn / per-message persistence.** The current schema is per-conversation aggregate (migration 017 NG4). This PR maintains that model.
- **NG4 — Admin key required.** Phase 5 is opt-in. The bulk of the value (closing the cc-dispatcher hole + cache tokens) lands without any user action.
- **NG5 — Anthropic Console iframe / deep link.** Out of scope; the footnote stays as prose.
- **NG6 — billing dispute UX.** If the user reports a discrepancy via the yellow banner's Report link, the GitHub issue is the resolution surface.
- **NG7 — sub-day reconciliation.** Admin Cost API supports `bucket_width: "1d"` only. A user whose locale month boundary differs from UTC sees an Admin total over UTC-month windows; the in-app total is already UTC-aligned (per `api-usage.ts:40-43`). Sub-day or local-tz reconciliation would require `bucket_width: "1h"` on the Messages Usage Report (cost is not exposed at 1h granularity) plus a separate cost-derivation step from token deltas, which is brittle. Defer.
- **NG8 — multi-key linking UX.** If a user has multiple Anthropic API keys mapped to Soleur, surfacing per-key cost is deferred. Admin API supports it via `group_by: ["api_key_id"]` but the dashboard schema collapses to per-user.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| **Fix cc-dispatcher only (Phase 3 alone)** | Smallest blast radius, closes ~80% of the gap | Cache tokens still silently dropped — Console will still show ~30% more input tokens than app | **Rejected** — leaves the AC #11 "match to the cent" promise broken. |
| **Admin API only (Phase 5 alone)** | Most authoritative; matches Console by definition | Requires every user to provision an admin key; doesn't fix the per-conversation list which still reads `conversations.total_cost_usd` | **Rejected** — UX regression for the 99% of users who won't bother with an admin key. |
| **Both layers** (this plan) | Per-conversation narrative + org-level reconciliation; admin key optional | Larger PR; more migrations | **Accepted.** |
| **Switch storage to per-turn `usage_events` table** | Granular forensic surface; matches the original 2026-04-10 brainstorm's "events table" idea | Big migration, full backfill, breaks `api-usage-parity.test.ts` | **Rejected as out-of-scope** — defer to a future PR. The `audit_byok_use` WORM table fills 80% of the forensic need. |
| **Hardcode Anthropic pricing table** | Independent of SDK | Drift risk; explicit non-goal NG2 of the original spec | **Rejected** by precedent. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- The Anthropic Admin Cost Report endpoint's `amount` field is documented as "lowest currency units" (cents) but the prose example `"$1.23"` is **incorrect** — a `"123.45"` cents amount represents `$1.2345`. Phase 5.6 includes a pinned conversion test specifically to defend against re-reading the docs and getting it wrong.
- The Admin Cost Report supports `bucket_width: "1d"` ONLY (not `1h` or `1m`); Messages Usage Report supports all three. Plan does NOT depend on sub-day cost bucketing.
- `increment_conversation_cost` v1 → v2 signature migration MUST `DROP FUNCTION IF EXISTS public.increment_conversation_cost(UUID, NUMERIC, INTEGER, INTEGER);` before `CREATE OR REPLACE` — without it, Postgres raises `function is not unique` at call sites (migration 027 documents this).
- `idx_conversations_user_cost`'s `INCLUDE` list extension is index-rebuild — Supabase wraps the migration in a transaction, so CONCURRENTLY is forbidden (per `2026-04-18-supabase-migration-concurrently-forbidden`). Brief AccessExclusive lock at current scale is acceptable; document the trade in the migration comment.
- The cc-dispatcher `onResult` widening will trigger TypeScript exhaustiveness errors at consumers; per `2026-05-07-tsc-not-source-grep-enumerates-exhaustiveness-rails`, run `tsc --noEmit` after the change and treat every TS error as a rail to widen — do NOT pre-enumerate consumers in this plan.
- Phase 5's "Report" GitHub issue prefill must NOT include the admin key, any session token, or PII; only `founder_id` (UUID) and the rendered delta percentage. Use a heredoc-style URL-encoded body.
- **DROPPED — migration 043.** The 037 migration's WORM trigger raises on UPDATE/DELETE — the existing `write_byok_audit` writer is INSERT-only (verified migration 037:79-96). Phase 3.1 calls the existing RPC; do not create a new one.
- The `audit_byok_use` table has `unit_cost_cents int` and a single combined `token_count int` — sub-cent precision is lost at write time AND the input/output/cache breakdown is collapsed to a single sum. For the per-row dashboard the source of truth stays `conversations.total_cost_usd NUMERIC(12, 6)`; `audit_byok_use` is the forensic surface where these collapses are acceptable. Don't surface `audit_byok_use.unit_cost_cents` in the dashboard list (data quality mismatch with `conversations.total_cost_usd`).
- Per CONTRIBUTING guide and `hr-dev-prd-distinct-supabase-projects`, apply migrations to dev first via `supabase migration list` before prd.
- **SDK shape ≠ Admin API shape.** The SDK exposes flat `cache_creation_input_tokens` (verified at `node_modules/@anthropic-ai/claude-agent-sdk/sdk-tools.d.ts:69`); the Admin Messages Usage Report exposes nested `cache_creation: {ephemeral_1h_input_tokens, ephemeral_5m_input_tokens}`. The normalization layer in Phase 5.2 collapses the Admin shape via SUM into the SDK-flat shape; without this, an Admin row with `ephemeral_5m=1000` would silently drop 1000 tokens from the reconciliation total.
- **SDK `usage.input_tokens` is uncached-input-only**, not total input. Phase 4.2 widens the "Input" pill to render `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` so the Console cross-check footnote holds for cached prompts (R8).
- **Admin Cost API doc prose example is internally inconsistent.** The doc says `"amount: '123.45'"` represents `$1.23` (2dp rounding), but `123.45 / 100 = 1.2345` (sub-cent precision present). The plan treats `amount` as cents-as-decimal-string and preserves sub-cent precision via `Number(amount) / 100`. The pinned conversion test (Phase 1.3) defends against either re-read direction.
- **`api_key_ids[]` filter is critical for admin-key over-count avoidance.** A user with an org-wide admin key spanning multiple workspaces or multiple API keys would see the banner over-count without the filter. Phase 5.2 requires `apiKeyId` capture at admin-key save time; the fallback banner label is "(all keys)".
- **Admin API authentication uses `X-Api-Key` header, NOT `Authorization: Bearer`.** The plan's loader must build `headers: { "X-Api-Key": adminKey, "anthropic-version": "2023-06-01" }`. Forgetting `anthropic-version` is the most common 4xx failure mode against this surface.

## Domain Review

**Domains relevant:** Engineering, Product, Marketing, Legal

### Engineering (CTO)

**Status:** reviewed (inline, plan author has direct codebase evidence).
**Assessment:** Three independent application-layer bugs stack: (1) no-op `onResult` in cc-dispatcher (primary), (2) cache tokens never captured (secondary, ~30% of input volume on cached prompts), (3) `audit_byok_use` WORM table provisioned but never written (silent gap from #3392). The fix is mechanical and additive — three migrations, one shared cost-writer module, surface fan-out. Risk: TypeScript exhaustiveness fan-out after widening `onResult` — mitigated by running `tsc --noEmit` and treating each error as a rail. Plan correctly defers the Admin Usage/Cost API to an opt-in Phase 5 rather than gating the primary fix on it.

### Product (CPO)

**Status:** reviewed (inline carry-forward from brainstorm 2026-04-17).
**Assessment:** The original "Actual API cost — cross-check any row in your Anthropic Console — the numbers will match to the cent" framing (CMO won 2026-04-17) is currently false. Brand-survival threshold is `single-user incident`. The fix-vs-positioning ratio is straightforward: a single PR brings the rendered numbers back into agreement with the Console; no positioning change is required. CPO sign-off via the threshold convention (Phase 2.6) — no separate review needed because the framing is unchanged from 2026-04-17.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (advisory + pipeline mode per Phase 2.5)
**Skipped specialists:** ux-design-lead (advisory tier + no new pages), copywriter (existing copy from `feat-restore-byok-usage-dashboard/copy.md` is reused; new tooltip copy is one short paragraph that adopts the existing voice)
**Pencil available:** N/A

#### Findings

No new pages or flows. Two surface adjustments only: (a) one extra info tooltip ("What about cache tokens?"), (b) one banner row above the existing per-conversation list (Phase 5, optional). Both adopt existing copy + layout conventions. Mobile viewport: the pills are inline-flex-wrap in the existing row layout — same pattern as Input/Output today.

### Marketing (CMO)

**Status:** reviewed (inline carry-forward).
**Assessment:** The 2026-04-17 brainstorm record settles the framing ("Actual API cost", no estimated hedging, Anthropic Console cross-check footnote). This plan reinstates the contract, not changes it. The yellow "Discrepancy" banner copy in Phase 5.4 follows CMO's no-hedging rule — describes the gap as a tracking issue, not a billing dispute. If Phase 5 reveals a sustained discrepancy across many users in production, escalate.

### Legal (CLO)

**Status:** reviewed (inline carry-forward).
**Assessment:** No new data category. The Admin API path collects no additional PII — only the admin API key (encrypted with the existing BYOK envelope per `cc-pg-security-definer-search-path-pin-pg-temp`). Account-deletion cascade per GDPR is already a tracked roadmap item (2.4/2.9) and unaffected. The Vendor DPA Status for Anthropic is unchanged (already a Sub-Processor for the Soleur product per `knowledge-base/legal/vendor-dpa-status.md`).

## GDPR / Compliance

The plan touches a regulated-data surface (`apps/web-platform/supabase/migrations/`, auth-adjacent `api_keys` table for the admin key storage). Per `hr-gdpr-gate-on-regulated-data-surfaces`:

- **Article 9 special-category?** No.
- **Lawful basis?** Existing (legitimate interest — providing the user with their own usage data; the data is the user's own).
- **Article 30 trigger?** No new processing activity beyond the existing BYOK record; the admin key is an additional credential for the same purpose.
- **Disclaimer:** This compliance call is advisory, not a substitute for a privacy review. If Phase 5 ships, update `knowledge-base/legal/vendor-dpa-status.md` row for Anthropic Admin API as "same vendor, expanded scope: usage reporting endpoint" — no new sub-processor.

## Network-Outage Hypothesis

Not applicable. Feature description does not match SSH/network-outage trigger patterns.

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-12-fix-api-usage-tracking-undercount-plan.md. Branch: feat-one-shot-fix-api-usage-tracking. Worktree: .worktrees/feat-one-shot-fix-api-usage-tracking/. Plan reviewed, implementation next.
```
