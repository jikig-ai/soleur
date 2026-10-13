# Brainstorm: BYOK Usage/Cost Indicator

**Date:** 2026-04-10
**Issue:** #1691
**Status:** Decided
**Approach:** A — Single-pass full build

## What We're Building

A usage and cost indicator for BYOK users that provides full transparency into AI model spending. The feature has three surfaces:

1. **Live cost indicator** — Dollar cost displayed during active conversations, updating after each agent turn completes
2. **Billing page usage section** — Cumulative usage data (daily/weekly/monthly) extending the existing `/dashboard/billing` page with three views: dollars per conversation, dollars + tokens breakdown, and cost per domain/agent type
3. **Multi-model support** — Per-model cost attribution (Opus, Sonnet, Haiku) using SDK-provided `costUSD` data

**Pricing framing:** BYOK cost is on top of the subscription. The subscription covers platform costs (hosting, development, orchestration, core value). AI model costs are separate and borne by the user via their own API keys.

## Why This Approach

- The Agent SDK already exposes `total_cost_usd`, `usage` (token counts), and `modelUsage` (per-model breakdown with `costUSD`) on every result message — the codebase currently discards this data entirely (`agent-runner.ts:370-378`)
- Per-conversation columns on the `conversations` table (not a separate events table) keeps storage simple while supporting all three display views since conversations already carry `domain_leader`
- SDK's `costUSD` as the sole pricing source avoids maintaining an independent pricing table that drifts when Anthropic changes rates
- Per-turn cost updates (not real-time streaming estimation) give accurate cost display without needing to verify SDK streaming event usage data or maintain token-counting heuristics
- Single-pass build ships a coherent feature in one PR rather than three incremental ones

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Live indicator behavior | Dollar cost always visible, updating per agent turn | User wants full transparency; accepted taxi meter trade-off |
| Cost display unit | All three: $/conversation, $+tokens, $/domain | Rich views for different user questions |
| Dashboard location | Extend existing billing page | Keeps cost info in one place; page already exists |
| Storage model | Per-conversation columns on `conversations` table | Simpler than events table; sufficient for all views |
| Pricing source | SDK `costUSD` only | Authoritative, zero maintenance, no drift risk |
| Live update strategy | After each agent turn completes | Accurate, no estimation; multi-turn provides natural update points |
| BYOK/subscription relationship | BYOK cost is additive to subscription | Subscription = platform value; AI models = user's direct cost |
| Budgeting feature | Deferred to #1866 | Budget progress bars are a distinct feature with different UX |
| Implementation approach | Single-pass full build (Approach A) | One coherent feature, one PR, one review cycle |

## Open Questions

1. **SDK streaming usage verification** — The CTO noted that `BetaRawMessageStreamEvent` may include per-chunk usage data. If verified, could enable smoother live updates in a future iteration beyond per-turn granularity.
2. **GDPR data retention** — Usage data is financial PII. Must be included in account deletion cascade and privacy disclosures (blocked by roadmap items 2.4 and 2.9, not yet implemented). Track as a follow-up.
3. **Cost accuracy labeling** — SDK's `costUSD` is authoritative but should be labeled as "estimated" in the UI to avoid disputes if it diverges from actual Anthropic billing.
4. **Model selection behavior** — If users see Opus costs $2 vs Haiku at $0.05, they may default to cheapest model. Is model selection user-controlled or agent-determined? Answer affects whether cost per model needs guardrails.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Feature is correctly placed in Phase 3 with multi-turn dependency (#1044) cleared. Primary risks: scope is broader than P2 priority warrants, no users to validate assumptions against, and pricing model is undecided. Recommends verifying SDK feasibility (confirmed: data is available) and considering minimum viable version — user chose full scope.

### Marketing (CMO)

**Summary:** Live cost indicator creates a "taxi meter effect" (loss aversion) that may cause users to truncate conversations. Pricing tension exists between $49/month flat messaging and visible BYOK API costs on top. Opportunity: full cost transparency is a trust differentiator ("your money, your visibility, no surprises") and enables content marketing about real AI organization costs. Recommends delegating dashboard layout to conversion-optimizer and mobile viewport to ux-design-lead.

### Engineering (CTO)

**Summary:** SDK already provides all required data (`total_cost_usd`, `usage`, `modelUsage`) but codebase discards it. No storage schema exists — needs a migration adding columns to `conversations`. Live streaming usage is unverified but per-turn updates avoid the issue. Recommends Option A (end-of-session capture) as MVP — user chose full scope. Affected components: `agent-runner.ts`, `lib/types.ts`, `ws-client.ts`, billing page, new migration + RLS policies.
