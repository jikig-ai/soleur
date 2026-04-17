---
feature: Restore BYOK Usage Dashboard
issue: "#1691"
pr: "#2464"
branch: feat-restore-byok-usage-dashboard
milestone: "Phase 3: Make it Sticky"
status: Ready for planning
brainstorm: knowledge-base/project/brainstorms/2026-04-17-restore-byok-usage-dashboard-brainstorm.md
copy: knowledge-base/project/specs/feat-restore-byok-usage-dashboard/copy.md
bundled_with: "#2436"
---

# Spec: Restore BYOK Usage Dashboard

## Problem Statement

PR #1867 (2026-03-24) shipped an "API Usage" section on `/dashboard/billing`
that listed per-conversation BYOK cost. PR #2036 (2026-04-13) consolidated
billing into `/dashboard/settings/billing` and dropped that section in the
refactor. The backend continues to capture per-conversation cost (migration
017 columns, `agent-runner.ts` RPC, `ws-client.ts` `usage_update` stream), but
users have no surface to see historical spend. This contradicts the
"pay the API, no markup" positioning that BYOK transparency is meant to
anchor.

Issue #1691 was closed when the original feature shipped and has been
reopened to track this restoration.

## Goals

- Re-mount a per-conversation API Usage section inside
  `/dashboard/settings/billing`, below the existing `<BillingSection>`.
- Show a month-to-date rollup (total USD, conversation count) above a list of
  the latest 50 conversations with `total_cost_usd > 0`.
- Use "Actual API cost" language (no "estimated", no tilde-prefixed values)
  to reinforce the no-markup positioning.
- Bundle with #2436 so the dashboard list and the resumed chat cost badge
  both consume the same camelCase-typed API shape.

## Non-Goals

- **New top-level `/dashboard/usage` route or nav entry** — settings-tab
  placement per brainstorm decision.
- **Per-model cost breakdown** — `model_usage` JSONB was cut during the
  prior review cycle; schema does not store multi-model per-conversation
  data. Show the last model used only.
- **3-view toggle** (per-conversation / tokens / per-domain) — single list
  with columns serves all three views.
- **Date-range picker / week/day bucketing** — follow-up issue.
- **Per-domain rollup view** — follow-up issue.
- **CSV export** — follow-up issue. No placeholder "Coming soon" text.
- **Budget threshold / progress bar** — tracked in #1866.
- **Per-subagent cost attribution** — carry-over non-goal from prior spec.
- **Pagination > 50 rows** — follow-up issue.
- **New chat cost badge** — already mounted in `chat-surface.tsx`.

## Functional Requirements

- **FR1.** `/dashboard/settings/billing` renders an "API Usage" section below
  the `<BillingSection>` component. Section header + subhead from
  `copy.md §1`.
- **FR2.** A month-to-date summary line (format `${total} in {Month} · {n}
  conversations`) sits directly below the section header. Copy per
  `copy.md §2`.
- **FR3.** Below the summary, a list of up to 50 conversation rows, newest
  first, scoped to `user_id = auth.uid()` and filtered to
  `total_cost_usd > 0`. Query shape matches partial index
  `idx_conversations_user_cost` from migration 017.
- **FR4.** Each row renders:
  relative time (e.g. `2h ago`), domain-leader department label
  (`[Marketing]` style — department name, not role), model id (last model
  used), input tokens, output tokens, USD cost to 4 decimal places.
  Column headers per `copy.md §3`; row secondary label pattern per
  `copy.md §4`.
- **FR5.** Empty state renders when query returns zero rows: headline, body,
  primary CTA per `copy.md §5`. CTA links to `/dashboard` (start a
  conversation).
- **FR6.** Footnote below the list invites Anthropic console cross-check
  (copy per `copy.md §8`). Must not contain "estimated", "approximate",
  "around", "roughly", or `~`.
- **FR7.** Tooltip affordances for "what is a token?" and "why does cost
  vary?" per `copy.md §6–7`. May be rendered as info icons beside the
  section header or as help links at the bottom.
- **FR8.** Error state: if the Supabase query returns `{ error }`, render
  error UI per `copy.md §10` (headline, body, retry action). Retry action
  re-runs the query.
- **FR9.** Loading state: SSR-first means no client-side spinner on first
  paint. If later iterations add client revalidation, show copy per
  `copy.md §9`.
- **FR10.** Domain-leader label resolution uses the existing
  `DOMAIN_LEADERS` registry — display the department `name`, not the id
  (e.g. `Marketing`, not `cmo`). If `domain_leader` is null (legacy
  conversations), render `—`.
- **FR11.** Bundled from #2436: `/api/conversations/:id/messages` returns
  `totalCostUsd`, `inputTokens`, `outputTokens` as numbers (not PostgREST
  NUMERIC strings) so that chat cost badge seeding from history and
  dashboard list display share a single typed API shape.

## Technical Requirements

- **TR1.** New section implemented as a **server component** fetching via
  `createServiceClient()` (or the equivalent per current settings/billing
  page pattern). Match the existing architectural choice from PR #2036
  (server component + parallel `Promise.all`).
- **TR2.** Supabase query MUST destructure `{ data, error }` and distinguish
  error from empty (per learnings
  `2026-03-20-supabase-silent-error-return-values.md`). Zero-row is
  empty-state; an actual error renders the error state in FR8.
- **TR3.** `total_cost_usd` values returned by PostgREST as strings MUST be
  converted via `Number(...)` before formatting. Covered by the #2436 API
  change but must also hold at any direct query site.
- **TR4.** Month-to-date rollup computed via a second query using
  `gte(created_at, <month-start>)` and `sum(total_cost_usd)` via a
  PostgREST aggregate, OR by summing client-side over the 50-row page
  PLUS issuing a count-only aggregate for the conversation count. Prefer
  server-side aggregate to keep the total accurate when >50 conversations
  exist in the current month.
- **TR5.** No schema migration. Existing columns on `conversations`
  (`total_cost_usd NUMERIC(12, 6)`, `input_tokens`, `output_tokens`,
  `domain_leader`, `created_at`, `user_id`) cover the surface. Partial
  index `idx_conversations_user_cost` is already in place.
- **TR6.** No changes to `agent-runner.ts` or `ws-client.ts`. The existing
  WS `usage_update` stream is out of scope.
- **TR7.** Mobile viewport (375px wide) must render the list without
  horizontal scroll. Columns may collapse to two-line rows on narrow
  breakpoints.
- **TR8.** Tests:
  (a) component test for the list section rendering rows + month-to-date
      summary from fixture data;
  (b) component test for the empty state (zero rows);
  (c) component test for the error state (query returns error);
  (d) unit test for any row-formatter helper (time, cost, domain label);
  (e) run via `./node_modules/.bin/vitest run` from `apps/web-platform/`
      per worktree vitest rule.
- **TR9.** Pre-commit: run `npx markdownlint-cli2 --fix` on changed `.md`
  files with specific paths, not repo-wide glob.
- **TR10.** QA gate before ready-for-review: create one real conversation
  with a known prompt, note the Anthropic-console charge for that API
  call, confirm the dashboard row matches the console figure. Document in
  the PR with a screenshot.

## Acceptance Criteria

1. Section renders on `/dashboard/settings/billing` below the subscription
   block.
2. Month-to-date summary shows correct total + conversation count for the
   current calendar month.
3. List shows latest 50 conversations (newest first) filtered to
   `total_cost_usd > 0` and scoped to the authenticated user.
4. Each row shows relative time, `[Department]` label, model id, input
   tokens, output tokens, USD cost.
5. Empty state, error state, loading state render correct copy from
   `copy.md`.
6. No "estimated", "approximate", "~", or similar hedging language in the
   rendered UI.
7. Sub-cent conversations render with 4 decimal places (e.g. `$0.0043`).
8. Mobile viewport (375px) has no horizontal scroll.
9. Vitest component tests pass.
10. QA cross-check: one dashboard row's USD cost matches Anthropic console
    to 4 decimal places.
11. Issue #1691 linked to PR #2464 via `Closes #1691` in the PR body.
12. Roadmap row 3.6 updated to reflect restoration post-merge.

## Open Questions

1. **Precision for non-sub-cent values**: 2dp (`$4.27`) or 4dp (`$4.2731`)
   for the month total and for rows ≥ $0.01? Default: 2dp for totals, 4dp
   for per-row when < $0.01 else 2dp. Confirm during implementation.
2. **Multi-model conversations**: render only the last model (simple) or
   annotate `model-id (+N)` when churn detected? Default: last only; revisit
   post-beta.
3. **Retention policy**: no documented policy for `total_cost_usd` data.
   Blocks Phase 4 recruitment; resolved by roadmap items 2.4 / 2.9, not
   by this PR.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-17-restore-byok-usage-dashboard-brainstorm.md`
- Precursor brainstorm: `knowledge-base/project/brainstorms/2026-04-10-byok-cost-tracking-brainstorm.md`
- Precursor spec: `knowledge-base/project/specs/feat-byok-cost-tracking/spec.md`
- Copy: `knowledge-base/project/specs/feat-restore-byok-usage-dashboard/copy.md`
- Original ship: PR #1867 (commit `086cf1ab`)
- Regression: PR #2036 (commit `f4fcb738`)
- Bundled issue: #2436 (fix-kb-chat-cost-estimate-resume)
- Migration: `apps/web-platform/supabase/migrations/017_conversation_cost_tracking.sql`
- Capture: `apps/web-platform/server/agent-runner.ts:1164-1190`
- Stream: `apps/web-platform/lib/ws-client.ts:86, 331-338, 435+`
- Badge (already mounted): `apps/web-platform/components/chat/chat-surface.tsx:408-423, 462-466, 467-481`
- Target page: `apps/web-platform/app/(dashboard)/dashboard/settings/billing/page.tsx`
- Screenshots: `knowledge-base/product/design/byok-cost-tracking/screenshots/`
- Learning: `knowledge-base/project/learnings/2026-03-20-supabase-silent-error-return-values.md`
