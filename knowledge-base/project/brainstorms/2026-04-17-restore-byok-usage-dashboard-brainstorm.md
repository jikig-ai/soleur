---
date: 2026-04-17
topic: Restore BYOK usage dashboard
status: Decided
issue: "#1691"
pr: "#2464"
branch: feat-restore-byok-usage-dashboard
spec: knowledge-base/project/specs/feat-restore-byok-usage-dashboard/spec.md
precursor:
  - knowledge-base/project/brainstorms/2026-04-10-byok-cost-tracking-brainstorm.md
  - knowledge-base/project/specs/feat-byok-cost-tracking/spec.md
regressed_in: "PR #2036 (commit f4fcb738)"
original_ship: "PR #1867 (commit 086cf1ab)"
---

# Restore BYOK Usage Dashboard

## What We're Building

Restore the "API Usage" section that shipped in PR #1867 and was dropped by the
billing consolidation in PR #2036. The surface lives as a new section inside
`/dashboard/settings/billing`, below the existing subscription block:

- Month-to-date summary line (total USD + conversation count for current
  calendar month).
- Latest 50 conversations with `total_cost_usd > 0`, one row per conversation,
  showing: time (relative), domain leader label, model used, input tokens,
  output tokens, cost in USD.
- "Actual API cost" positioning (NOT "estimated") with a footnote inviting the
  user to cross-check any row in the Anthropic console.
- Empty state + token/cost tooltips from the copywriter agent.

No new top-level nav. No 3-view toggle. No per-model rollup (schema does not
support it — `model_usage` JSONB was cut in the original review). The live
chat cost badge already exists in `chat-surface.tsx` and is out of scope here.

## Why This Approach

The backend has been capturing per-conversation cost the entire time (migration
017, `agent-runner.ts` RPC, `ws-client.ts` usage_update stream). Only the UI
shelf was dropped in a refactor. The cheapest correct fix is to re-mount the
shelf against the existing schema, with copy tightened for the BYOK positioning
("pay the API, no markup").

YAGNI: the prior brainstorm's 3-view toggle (per-conversation / tokens /
per-domain) is over-built for zero beta users. A single list with columns
answers all three views at once. Rollups and date-range filters are deferred
to follow-up issues.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Placement | `/dashboard/settings/billing` (existing page), new section below subscription | Matches prior UX screenshots + 2026-04-10 spec + PR #2036 architectural choice. Settings-tab is correct for a trust/money artifact, not a flow artifact. |
| Scope shape | Per-conversation list + month-to-date summary, latest 50 | Single list serves as the per-conv, per-token, and per-domain view simultaneously via columns. |
| Cost labeling | "Actual API cost" (no "estimated", no "~") | Values come from Anthropic SDK `total_cost_usd`; they ARE actuals. Hedging language undercuts the no-markup positioning CMO flagged. QA gate added: cross-check one row against Anthropic console before merge. |
| Time window | Month-to-date total + latest 50 rows | Month is the billing mental model. List stays bounded. Defer date-range picker. |
| Schema changes | None | All needed fields exist on `conversations`. Migration 017 partial index `idx_conversations_user_cost` matches the query exactly. |
| Per-model breakdown | Not shown | `model_usage` JSONB was cut; no per-model data stored. Display the single `model` field the SDK returns per turn (last model used in the conversation). |
| Pagination | None for v1 | Tracks latest 50. No pagination primitive in codebase; decide paginate-vs-infinite-scroll when list overflows in real usage. |
| Issue tracking | Reopen #1691, link PR #2464 | Issue was closed on ship of #1867; regressed by #2036 without sync. Reopening is cleaner than splitting thread. |
| Bundle with #2436 | Yes | Dashboard list + chat badge resume both need the camelCase API shape and `Number(NUMERIC)` conversion. Same QA surface, one PR. |
| Copy source | Spawned copywriter agent (in flight at time of brainstorm) | Empty state, tooltips, footnote, loading/error states written to `specs/feat-restore-byok-usage-dashboard/copy.md`. |
| Design source | Reuse existing `knowledge-base/product/design/byok-cost-tracking/screenshots/` | Product/UX Gate substantially satisfied. Refresh only if copy pass surfaces layout conflicts. |

## Acceptance Criteria

1. `/dashboard/settings/billing` renders an "API Usage" section below the
   subscription block (server component, queries `conversations` table).
2. Section header shows month-to-date total USD and conversation count.
3. List shows up to 50 rows, newest first, filtered to
   `total_cost_usd > 0` and scoped by `user_id`.
4. Each row shows: relative time, domain leader label (department name, not
   role), model name, input tokens, output tokens, USD cost (to 4 decimal
   places for sub-cent precision).
5. Empty state renders when no rows exist (copy from copywriter).
6. Footnote present under the list inviting Anthropic console cross-check.
7. No word "estimated", "approximate", or tilde-prefixed ("~$") appears in the
   rendered UI.
8. `total_cost_usd` values from Supabase (returned as string by PostgREST)
   are converted via `Number(...)` before formatting (pairs with #2436).
9. Supabase query destructures `{ data, error }` and distinguishes error from
   empty (per learnings `2026-03-20-supabase-silent-error-return-values.md`).
10. Mobile viewport (375px) renders the list without horizontal scroll.
11. QA gate: one real conversation cross-checked against Anthropic console
    during QA; values match to the precision rendered.

## Non-Goals

- **New top-level /dashboard/usage tab** — deferred. CMO wanted this for
  landing-page screenshotability; CPO and founder agreed settings-tab is
  correct for v1. Revisit if beta users ask for in-flow visibility.
- **Per-model rollup** — schema does not support it. Separate follow-up to
  decide whether to add `model_usage JSONB` and backfill.
- **Date-range picker / week/day bucketing** — follow-up issue.
- **Group-by-domain-leader rollup view** — follow-up issue.
- **Export to CSV** — follow-up issue. No "Coming soon" placeholders.
- **Budget threshold / progress bar** — tracked in #1866.
- **Per-subagent cost attribution** — explicit non-goal in prior spec (NG6).
- **New chat cost badge** — already mounted in `chat-surface.tsx`.
- **Pagination of >50 rows** — follow-up issue.

## Open Questions

1. **Data retention** (carry-over from 2026-04-10 brainstorm): no documented
   retention policy for `total_cost_usd`. Acceptable for pre-beta; must be
   resolved before any external user sees this. Blocks Phase 4 recruitment
   (tracked by roadmap items 2.4 / 2.9).
2. **Cost precision for display**: render `$0.0043` (4dp) vs `$0.00` (2dp)?
   Defaulting to 4dp for sub-cent conversations; confirm during copy review.
3. **Model column when multiple models used in one conversation**: today we
   only store the last model seen. Render as `claude-sonnet-4-5` (last) or
   `claude-sonnet-4-5 (+1)` if we detect churn? Default: last only, keep
   simple; follow-up if multi-model conversations become common.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Restoration, not new feature — prior spec and UX screenshots
already exist. Recommended Option A (reduced scope): keep placement in
settings/billing, drop the 3-view toggle, don't rebuild the live chat badge
(already mounted). Flagged workflow violation: issue #1691 was closed when
feature shipped, then regressed by #2036 without reopening. Fix: reopen #1691
and update roadmap row 3.6 in the same commit.

### Marketing (CMO)

**Summary:** BYOK transparency is a headline positioning lever, not internal
plumbing. Pushed for top-level Usage tab to make the surface screenshottable
for the landing page; founder chose to keep settings placement for v1 with
revisit criteria. Won the copy fight: no "estimated" hedging — values are
actuals from the Anthropic SDK and the UI should say so. Copywriter spawned
for empty state, tooltips, footnote.

## Capability Gaps

None blocking. Two soft gaps:

- **No pagination primitive** in the web-platform codebase — if a future
  iteration wants >50 rows, this becomes blocking.
- **Brand guide verification** — copywriter agent will read
  `knowledge-base/marketing/brand-guide.md` if present; if it isn't, defaults
  apply.
