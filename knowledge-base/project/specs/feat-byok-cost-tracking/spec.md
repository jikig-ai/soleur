# Spec: BYOK Usage/Cost Indicator

**Issue:** #1691
**Branch:** byok-cost-tracking
**Date:** 2026-04-10
**Brainstorm:** [2026-04-10-byok-cost-tracking-brainstorm.md](../../brainstorms/2026-04-10-byok-cost-tracking-brainstorm.md)

## Problem Statement

BYOK users bear AI model costs directly via their own API keys but have zero visibility into per-conversation or cumulative spending. Without cost transparency, users cannot budget, understand which agent conversations are expensive, or evaluate the value they're getting from the platform.

## Goals

- G1: Display per-conversation cost (dollars) after each agent turn completes
- G2: Show cumulative usage on the billing page (daily/weekly/monthly) with three views: dollars per conversation, dollars + tokens breakdown, cost per domain/agent type
- G3: Support multi-model cost attribution (Opus, Sonnet, Haiku) using SDK-provided data
- G4: Work on mobile viewport (PWA-first)

## Non-Goals

- NG1: Real-time streaming cost estimation (per-chunk updates during a single agent turn)
- NG2: Independent pricing table maintained separately from SDK
- NG3: Budget setting and progress bar UI (deferred to #1866)
- NG4: Per-message or per-turn granular storage (per-conversation aggregate only)
- NG5: "What-if" model comparison ("if you used Haiku instead...")
- NG6: Subagent cost attribution breakdown

## Functional Requirements

- FR1: Capture `total_cost_usd`, `usage` (input/output/cache tokens), and `modelUsage` (per-model breakdown) from SDK result messages in `agent-runner.ts`
- FR2: Store cost data as new columns on the `conversations` table: `total_cost_usd`, `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_creation_tokens`, `model_usage` (JSONB)
- FR3: Stream a `usage_update` WebSocket message to the client after each agent turn completes with the accumulated cost
- FR4: Display a live cost indicator in the conversation UI showing accumulated dollar cost, updating per turn
- FR5: Add a usage section to `/dashboard/billing` with three views:
  - Dollars per conversation (list with cost, domain, timestamp)
  - Dollars + tokens breakdown (aggregate with model-level detail)
  - Cost per domain/agent type (grouped by `domain_leader`)
- FR6: Support daily, weekly, and monthly time range selection for cumulative views
- FR7: Display per-model cost breakdown (Opus, Sonnet, Haiku) using `modelUsage` data
- FR8: Label all cost figures as "estimated" (SDK cost is authoritative but may differ from final Anthropic billing)

## Technical Requirements

- TR1: New Supabase migration adding cost columns to `conversations` table
- TR2: RLS policy on new columns scoped to `user_id` (read-only for the owning user)
- TR3: New `usage_update` variant in the `WSMessage` discriminated union (`lib/types.ts`)
- TR4: WebSocket client handler for `usage_update` message type (`ws-client.ts`)
- TR5: Responsive design for mobile viewport — cost indicator must not consume excessive screen real estate on small screens
- TR6: Usage data must be included in future account deletion cascade (GDPR — tracked separately in roadmap items 2.4/2.9)

## Affected Components

| Component | Change |
|-----------|--------|
| `apps/web-platform/server/agent-runner.ts` | Capture cost data from SDK result messages (lines 370-378) |
| `apps/web-platform/lib/types.ts` | Add `usage_update` WSMessage variant and usage data types |
| `apps/web-platform/lib/ws-client.ts` | Handle `usage_update` message type, expose usage state |
| `apps/web-platform/supabase/migrations/` | New migration: add cost columns to `conversations` |
| `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx` | Add usage section with three cost views |
| Conversation UI component | Add live cost indicator |

## Dependencies

- Agent SDK `SDKResultMessage` exposes `total_cost_usd`, `usage`, `modelUsage` (verified: available in current SDK)
- Multi-turn conversations (#1044) — CLOSED, dependency met
