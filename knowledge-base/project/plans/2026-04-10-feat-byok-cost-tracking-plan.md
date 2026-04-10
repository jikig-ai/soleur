---
title: "feat: Usage/cost indicator for BYOK spending"
type: feat
date: 2026-04-10
---

# feat: Usage/cost indicator for BYOK spending

## Overview

Add full cost transparency for BYOK users across two UI surfaces: a live cost indicator during active conversations (updating per agent turn) and a cumulative usage section on the billing page with three views (per-conversation, tokens breakdown, per-domain). The Agent SDK already provides all required data (`total_cost_usd`, `usage`, `modelUsage`) — the codebase currently discards it.

**Issue:** #1691
**Brainstorm:** `knowledge-base/project/brainstorms/2026-04-10-byok-cost-tracking-brainstorm.md`
**Spec:** `knowledge-base/project/specs/feat-byok-cost-tracking/spec.md`
**Deferred:** #1866 (budget setting/progress bar)

## Problem Statement

BYOK users bear AI model costs directly via their own API keys but have zero visibility into spending. The subscription covers platform costs; AI model costs are separate. Without cost transparency, users cannot budget or understand which conversations are expensive.

## Proposed Solution

Single-pass implementation across four layers: database migration, server-side capture, WebSocket transport, and frontend display. Ships as one coherent PR.

## Technical Approach

### Architecture

```text
SDK Result Message ──► agent-runner.ts ──► UPDATE conversations SET cost columns
                              │
                              ▼
                       sendToClient({ type: "usage_update", ... })
                              │
                              ▼
                       ws-client.ts ──► React state update
                              │
                              ▼
                 ┌─────────────┴─────────────┐
                 │                           │
        Conversation UI              Billing Page
        (live indicator)         (cumulative dashboard)
```

### Implementation Phases

#### Phase 1: Database Migration

**File:** `apps/web-platform/supabase/migrations/017_conversation_cost_tracking.sql`

Add cost columns to `conversations` table:

```sql
ALTER TABLE conversations
  ADD COLUMN total_cost_usd NUMERIC(10, 6) DEFAULT 0,
  ADD COLUMN input_tokens INTEGER DEFAULT 0,
  ADD COLUMN output_tokens INTEGER DEFAULT 0,
  ADD COLUMN cache_read_tokens INTEGER DEFAULT 0,
  ADD COLUMN cache_creation_tokens INTEGER DEFAULT 0,
  ADD COLUMN model_usage JSONB DEFAULT '{}';
```

RLS policy: existing `conversations` RLS already scopes to `user_id`. New columns inherit the table-level grant — no separate column policy needed (per learning: column-level REVOKE is silently ineffective with table-level grants).

**Gotcha:** No down migration. Cost data is financial PII — irreversible by design per GDPR remediation learning.

#### Phase 2: Server-Side Cost Capture

**File:** `apps/web-platform/server/agent-runner.ts` (insertion at lines 711-714)

In the `message.type === "result"` handler, after `saveMessage` and before `syncPush`:

```typescript
// Capture cost data from SDK result
const costUpdate = {
  total_cost_usd: message.total_cost_usd ?? 0,
  input_tokens: message.usage?.input_tokens ?? 0,
  output_tokens: message.usage?.output_tokens ?? 0,
  cache_read_tokens: message.usage?.cache_read_input_tokens ?? 0,
  cache_creation_tokens: message.usage?.cache_creation_input_tokens ?? 0,
  model_usage: message.modelUsage ?? {},
};

// Persist to conversations table (accumulate for multi-turn)
const { error: costError } = await supabase
  .from("conversations")
  .update({
    total_cost_usd: supabase.rpc("increment_cost", {
      conv_id: conversationId,
      cost_delta: costUpdate.total_cost_usd,
    }),
    // ... or simpler: read-then-write with accumulated values
  })
  .eq("id", conversationId);

if (costError) {
  console.error("Failed to save cost data:", costError.message);
  // Non-blocking — don't fail the conversation over cost tracking
}

// Stream cost update to client
sendToClient(userId, {
  type: "usage_update",
  conversationId,
  ...costUpdate,
});
```

**Cost accumulation strategy:** For multi-turn conversations, each turn's `total_cost_usd` from the SDK is the cumulative session cost (not a delta). Store the latest value directly — no need to sum. The `modelUsage` JSONB should be deep-merged (accumulate per-model token counts across turns).

**Gotcha:** Always destructure `{ error }` from Supabase calls — client never throws (per learning). Log errors but don't block the conversation.

#### Phase 3: WebSocket Types and Client

**File:** `apps/web-platform/lib/types.ts` (lines 34-48)

Add to the `WSMessage` discriminated union:

```typescript
| {
    type: "usage_update";
    conversationId: string;
    totalCostUsd: number;
    inputTokens: number;
    outputTokens: number;
    cacheReadTokens: number;
    cacheCreationTokens: number;
    modelUsage: Record<string, {
      costUSD: number;
      inputTokens: number;
      outputTokens: number;
    }>;
  }
```

**File:** `apps/web-platform/lib/ws-client.ts` (lines 132-284)

Add `case "usage_update"` to the switch handler. Expose usage state via a new `usageData` field returned from `useWebSocket`:

```typescript
case "usage_update":
  setUsageData({
    totalCostUsd: msg.totalCostUsd,
    inputTokens: msg.inputTokens,
    outputTokens: msg.outputTokens,
    cacheReadTokens: msg.cacheReadTokens,
    cacheCreationTokens: msg.cacheCreationTokens,
    modelUsage: msg.modelUsage,
  });
  break;
```

**Gotcha:** Follow error sanitization pattern — the `usage_update` message contains no sensitive data (just numbers), but never include raw error messages if the cost update fails (per CWE-209 learning).

#### Phase 4: Live Cost Indicator (Conversation UI)

**File:** `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`

Add a cost badge in the status bar area (lines 282-289), next to the `{activeLeaderIds.length} leaders responding` text:

```tsx
{usageData && usageData.totalCostUsd > 0 && (
  <span className="text-xs text-neutral-400">
    ~${usageData.totalCostUsd.toFixed(4)}
    <span className="text-neutral-500 ml-1">estimated</span>
  </span>
)}
```

Design tokens: match existing status bar — `text-xs`, `text-neutral-400`, no additional background. The `~` prefix and "estimated" label address the cost accuracy concern from the brainstorm.

Mobile: `text-xs` is already compact. No special mobile treatment needed — it's a single line of text.

#### Phase 5: Billing Page Usage Section

**File:** `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx`

Add a usage section below the existing subscription card inside the `max-w-md space-y-6` wrapper. Three tab views:

**Tab 1: Per-Conversation Costs**

Query `conversations` WHERE `user_id = current` AND `total_cost_usd > 0`, ordered by `created_at DESC`. Display as a list: domain leader icon, timestamp, cost.

**Tab 2: Tokens Breakdown**

Aggregate query grouping by date range (daily/weekly/monthly toggle). Show total input/output/cache tokens and total cost. Per-model breakdown from `model_usage` JSONB.

**Tab 3: Cost by Domain**

Aggregate query grouping by `domain_leader`. Show per-domain cost and conversation count.

**Time range selector:** Three buttons (Day / Week / Month) filtering the `created_at` range. Default: current month.

**Design tokens:** Match existing billing page — `bg-neutral-900` cards, `border-neutral-700` borders, `text-neutral-400` secondary text, `rounded-lg`, `text-sm`.

**Supabase queries:** All queries must destructure `{ data, error }` and handle errors gracefully. Use the existing Supabase client pattern from the billing page.

## Alternative Approaches Considered

| Approach | Why Rejected |
|----------|-------------|
| Separate `usage_events` table (per-turn records) | Over-engineered for MVP — per-conversation columns suffice for all three views. Revisit if per-turn drill-down is requested. |
| Independent pricing table | Maintenance burden when Anthropic changes rates. SDK's `costUSD` is authoritative. |
| Real-time streaming estimation (per-chunk) | Requires verifying SDK streaming event usage data. Per-turn updates are accurate and simpler. |
| New `/dashboard/usage` page | Extra surface to maintain. Billing page already exists and is the natural home for cost data. |
| Token-count estimation during streaming | Inaccurate (character-count heuristic). Users would see wrong numbers corrected on turn end. |

## Acceptance Criteria

### Functional Requirements

- [ ] Per-conversation cost captured from SDK result and stored in `conversations` table (`agent-runner.ts`)
- [ ] `usage_update` WebSocket message sent to client after each agent turn
- [ ] Live cost indicator visible in conversation UI during active conversations
- [ ] Billing page shows usage section with per-conversation, tokens, and per-domain views
- [ ] Time range selector (day/week/month) filters cumulative views
- [ ] Multi-model cost breakdown (Opus, Sonnet, Haiku) displayed in tokens view
- [ ] All cost figures labeled as "estimated"
- [ ] Works on mobile viewport (PWA)

### Non-Functional Requirements

- [ ] Cost tracking does not block conversation flow (non-blocking error handling)
- [ ] New migration is forward-only (no down migration)
- [ ] RLS enforced — users see only their own cost data
- [ ] No raw error messages exposed to client via WebSocket

## Domain Review

**Domains relevant:** Product, Marketing, Engineering

### Marketing (CMO) — carried forward from brainstorm

**Status:** reviewed
**Assessment:** Live cost indicator creates a "taxi meter effect" (loss aversion). Pricing tension between $49/month flat messaging and visible BYOK API costs. Opportunity: full cost transparency as trust differentiator. Recommends delegating layout to conversion-optimizer and mobile to ux-design-lead.

### Engineering (CTO) — carried forward from brainstorm

**Status:** reviewed
**Assessment:** SDK provides all required data but codebase discards it. Per-conversation columns on conversations table. Per-turn updates avoid streaming estimation complexity. Affected: agent-runner.ts, types.ts, ws-client.ts, billing page, migration + RLS.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed (partial)
**Agents invoked:** none (rate-limited)
**Skipped specialists:** spec-flow-analyzer (agent rate-limited), cpo (agent rate-limited), ux-design-lead (blocked by upstream failures), copywriter (blocked by upstream failures)
**Pencil available:** yes

#### Findings

Spec-flow-analyzer and CPO agents hit API rate limits during plan generation. Key UX considerations from the brainstorm carry forward:

- **Flow gap: No API key state** — If a BYOK user has no API key configured, the cost indicator should not render (guard on key existence). The billing usage section should show an empty state prompting key setup.
- **Flow gap: WS disconnect** — If WebSocket disconnects mid-conversation, the last-known cost should persist in React state (not reset to zero). On reconnect, the next turn will update with the authoritative SDK total.
- **Flow gap: Loading state** — Before the first turn completes, the cost indicator should not render (no skeleton/spinner for a cost badge — just absent until data arrives).
- **Mobile consideration** — Status bar already uses `text-xs`. Cost badge fits inline. Billing page tabs should stack vertically on mobile if `max-w-md` is too narrow for three horizontal tabs.

Wireframes and copywriter review should run before implementation. Consider running `/soleur:plan` domain review agents when rate limits reset.

## Test Scenarios

### Acceptance Tests

- Given a BYOK user starts a conversation, when the agent completes a turn, then the conversation's `total_cost_usd` column is updated with the SDK's reported cost
- Given a BYOK user is viewing an active conversation, when an agent turn completes, then the live cost indicator updates to show the accumulated dollar cost
- Given a BYOK user visits the billing page, when they have conversations with cost data, then three views (per-conversation, tokens, per-domain) display correct aggregations
- Given a BYOK user selects "Week" time range, when viewing the billing page, then only conversations from the current week are included in aggregations
- Given a conversation uses multiple models (Opus + Haiku), when viewing the tokens breakdown, then per-model costs are displayed separately

### Edge Cases

- Given a conversation where the SDK result has `total_cost_usd: 0` (e.g., cached response), when viewing the billing page, then zero-cost conversations are included in the list but don't inflate totals
- Given a Supabase cost update fails, when the agent completes a turn, then the conversation still completes normally (cost tracking is non-blocking) and the error is logged server-side
- Given a user with no conversations, when visiting the billing page usage section, then an empty state message is shown (not an error)
- Given a user on mobile viewport, when viewing the live cost indicator, then the indicator fits within the status bar without overflow

### Integration Verification

- **Browser:** Navigate to `/dashboard/billing`, verify usage section appears with tab navigation (Per-Conversation / Tokens / By Domain)
- **Browser:** Start a conversation with a BYOK key, verify cost indicator appears in status bar after first agent turn completes
- **API verify:** After a conversation, query `conversations` table for `total_cost_usd > 0` to verify persistence

## Dependencies and Prerequisites

- Agent SDK `SDKResultMessage` exposes `total_cost_usd`, `usage`, `modelUsage` — **verified available** in current SDK (`@anthropic-ai/claude-agent-sdk`)
- Multi-turn conversations (#1044) — **CLOSED**, dependency met
- Supabase migration infrastructure — exists, next number is `017`

## Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| SDK changes `total_cost_usd` field name | Low | High | Pin SDK version in package.json. Add type assertion. |
| Cost data diverges from Anthropic billing | Medium | Medium | Label as "estimated" in all UI. SDK cost is best-effort. |
| Taxi meter effect reduces conversation quality | Medium | Medium | Accepted trade-off per brainstorm. Budget feature (#1866) deferred. |
| GDPR deletion cascade missing cost data | Low | High | TR6 in spec tracks this. Blocked by roadmap items 2.4/2.9. |

## References and Research

### Internal References

- `apps/web-platform/server/agent-runner.ts:711-732` — SDK result handler (insertion point)
- `apps/web-platform/lib/types.ts:34-48` — WSMessage discriminated union
- `apps/web-platform/lib/ws-client.ts:132-284` — WS message switch handler
- `apps/web-platform/supabase/migrations/016_github_username.sql` — latest migration
- `apps/web-platform/supabase/migrations/001_initial_schema.sql:46-56` — conversations table
- `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx` — billing page (126 lines)
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:282-289` — conversation status bar

### Institutional Learnings Applied

- Supabase silent error returns — always destructure `{ data, error }` (`2026-03-20`)
- Column-level REVOKE ineffective — rely on table-level RLS (`2026-03-20`)
- WebSocket error sanitization CWE-209 — never forward raw err.message (`2026-03-20`)
- GDPR migration — no down migration for financial PII (`2026-03-20`)
- WebSocket TOCTOU race — check `ws.readyState` after async (`2026-03-20`)

### Related Issues

- #1691 — This feature
- #1866 — Deferred budget setting/progress bar
- #1044 — Multi-turn conversations (CLOSED, dependency met)
- #672 — Phase 3 parent epic
