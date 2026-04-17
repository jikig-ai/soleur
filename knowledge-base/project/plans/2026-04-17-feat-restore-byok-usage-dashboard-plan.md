---
date: 2026-04-17
feature: Restore BYOK Usage Dashboard
issue: "#1691"
pr: "#2464"
branch: feat-restore-byok-usage-dashboard
worktree: .worktrees/feat-restore-byok-usage-dashboard
milestone: "Phase 3: Make it Sticky"
spec: knowledge-base/project/specs/feat-restore-byok-usage-dashboard/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-04-17-restore-byok-usage-dashboard-brainstorm.md
copy: knowledge-base/project/specs/feat-restore-byok-usage-dashboard/copy.md
detail_level: MORE
review_applied: 2026-04-17  # DHH + Kieran + simplicity reviews
---

# Plan: Restore BYOK Usage Dashboard

## Overview

Restore the "API Usage" section to `/dashboard/settings/billing` dropped in
PR #2036. Backend cost-capture is intact (migration 017 + agent-runner RPC

+ ws-client stream). Only the display shelf is missing.

**Scope shape:** one section below `<BillingSection>` — month-to-date
summary + latest 50 conversations list. No schema migration, no new nav,
no new top-level page. "Actual API cost" labeling. One-row QA cross-check
against the Anthropic console.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| Spec FR4 + copy.md §3/§4 require a "Model" column | No `model` column exists on `conversations` or `messages`. Model is selected at runtime in `server/agent-runner.ts:828` and `server/domain-router.ts:131`, never persisted. | **Descope Model column.** Row format: `[Department] · 2h ago` with three numeric columns (Input / Output / Cost). File follow-up issue (below) for persisting last-used model. |
| Spec frontmatter `bundled_with: "#2436"` implies the camelCase API shape is pending | `server/api-messages.ts:40, 65-70` already returns `totalCostUsd`, `inputTokens`, `outputTokens` on main. | **Drop bundled-with framing.** Note the shape is already shipped. Plan consumes it directly; no API work. |
| PR #1867 original code used `leader.name` for `[Marketing]` label | `server/domain-leaders.ts` stores `name` as ROLE abbrev (`"CMO"`) and `domain` as DEPARTMENT (`"Marketing"`). | **Use `leader.domain`.** Matches spec FR10. Tested. |
| Spec TR4 "Prefer server-side aggregate" for MTD total | No existing PostgREST `sum()` prior art; only `count: "exact", head: true` in production use. | **Client-side sum over scoped fetch.** Select `total_cost_usd` filtered by month + `> 0`, sum in JS. Defer trying untested `sum()` aggregate. |
| Spec FR8 "Retry re-runs the query" | Target is a server component; RSC `<button onClick>` cannot re-run server query. | **Tiny client `<RetryButton>`** calls `router.refresh()`. Verified cache posture (see Phase 3). |
| Spec FR5 empty-state trigger | Original fired empty-state whenever list was empty, regardless of MTD. Causes confusing "$0 in April · 0 conversations" above a non-empty prior-month list. | **Gate empty state on `MTD === 0 && list.length === 0`.** Zero-MTD-with-history renders copy §2b helper line. |

## Spec Amendments (applied inline in Phase 1, not a separate phase)

+ `spec.md` frontmatter: replace `bundled_with: "#2436"` with note "API shape already on main".
+ `spec.md` FR4: drop `model id`; columns are Input / Output / Cost.
+ `spec.md` FR8: retry re-runs via `router.refresh()` in a client island.
+ `spec.md` AC #4: remove model reference.
+ `spec.md` Open Question #2: close — "No model persisted. See follow-up issue."
+ `copy.md` §3: remove `Model` column header.
+ `copy.md` §4: pattern becomes `[{Department}] · {relativeTime}`.
+ `copy.md` §2b (new): `Showing your last 50 conversations with cost. Nothing billed this month yet.`
+ `copy.md` §10: note retry is `router.refresh()`.

## Timezone Decision (Kieran P0)

Month boundary is computed in **UTC** for v1. Rationale: (a) no user
timezone is stored anywhere today; (b) the Anthropic console reports in
UTC; (c) the footnote in copy §8 sends users there to cross-check, so
matching their reference surface is correct; (d) deferring user-local TZ
avoids cross-cutting a timezone column into auth/session. Copy §2 reads
`$X.XX this month` — we add the word `(UTC)` nowhere in rendered copy;
the cross-check footnote implicitly anchors the frame.

Implementation: `monthStartIso = new Date(Date.UTC(year, month, 1)).toISOString()`.
Test fixture: a conversation created at `2026-04-01T04:00:00Z` is counted
as April (UTC); a conversation at `2026-03-31T23:30:00Z` is counted as
March.

Follow-up issue filed if/when we introduce user-local TZ.

## Auth Boundary (Kieran P0)

`loadApiUsageForUser(userId)` uses `createServiceClient()` — bypasses RLS.
Authorization reduces to "caller passed the correct userId." The billing
page reads `user.id` from the server session (line ~8 of
`billing/page.tsx`) so that's fine today, but we add guardrails so a
future caller cannot IDOR through this function:

1. Validate `userId` is a UUID (regex or `z.string().uuid()` — match
   codebase's existing validator if one exists).
2. File header comment: `// Caller MUST have verified the userId belongs to the authenticated session. This function trusts its input.`
3. Unit test: calling with a non-UUID string throws before hitting
   Supabase.

## Partial-Failure Contract (Kieran P0)

Two Supabase queries run in `Promise.all`: list + MTD scoped fetch. If
**either** returns `{ error }`, the whole loader returns `null` and the
section renders the error state. No partial render. Tested.

## Implementation Phases

### Phase 1 — Data layer + spec/copy edits

Files to create:

+ `apps/web-platform/server/api-usage.ts`
  + Exports `loadApiUsageForUser(userId: string): Promise<ApiUsage | null>`.
  + Type `ApiUsage = { mtdTotalUsd: number; mtdCount: number; rows: ApiUsageRow[] }`. Error → `null`.
  + Row type: `{ id, domainLabel, createdAt, inputTokens, outputTokens, costUsd }`.
  + Validates `userId` is a UUID; throws on invalid input (per auth boundary).
  + Builds a `Map<leaderId, domain>` once from `DOMAIN_LEADERS`; lookup returns `domain` or `"—"` for null/unknown.
  + Two queries in `Promise.all`:
    1. List: `.select("id, domain_leader, created_at, input_tokens, output_tokens, total_cost_usd").eq("user_id", userId).gt("total_cost_usd", 0).order("created_at", { ascending: false }).limit(50)`.
    2. Month scope: `.select("total_cost_usd", { count: "exact" }).eq("user_id", userId).gt("total_cost_usd", 0).gte("created_at", monthStartIso)`.
  + Coerces every `total_cost_usd` via `Number(raw ?? 0)`.
  + Inline helpers at bottom of file: `formatRelativeTime(date: Date)`, `formatUsd(n: number)`. No separate module. No separate test file.

Files to modify:

+ `knowledge-base/project/specs/feat-restore-byok-usage-dashboard/spec.md` — apply amendments.
+ `knowledge-base/project/specs/feat-restore-byok-usage-dashboard/copy.md` — apply amendments.

Test scenarios (TDD — write RED first):

+ `apps/web-platform/test/api-usage.test.ts`
  + Returns empty rows + 0 MTD when no conversations.
  + Returns rows + MTD total when current-month (UTC) conversations exist.
  + Returns rows with MTD=0 when only prior-month conversations exist.
  + Counts a conversation at `2026-04-01T04:00:00Z` as April; at `2026-03-31T23:30:00Z` as March (UTC boundary).
  + Maps `leader.domain` for known leader IDs, `"—"` for null, `"—"` for unknown (legacy removed leader).
  + Returns `null` when list query errors.
  + Returns `null` when MTD query errors.
  + Returns `null` when both error.
  + Coerces PostgREST NUMERIC strings to numbers.
  + Throws on non-UUID input before hitting Supabase.
  + Asserts `.gte("created_at", monthStartIso)` is called with the exact UTC boundary string (regression protection — Kieran P1).
  + Inline helper tests within this file (not separate file): `formatUsd` for `0 / 0.0043 / 0.01 / 4.27`; `formatRelativeTime` for now / 5m / 2h / 3d / 30d.

### Phase 2 — UI components

Files to create:

+ `apps/web-platform/components/billing/api-usage-section.tsx`
  — **server component**. Calls `loadApiUsageForUser(userId)`. Renders
  (in this order of precedence):
  1. Error shell (when `loadApiUsageForUser` returns `null`) — includes `<RetryButton>`.
  2. Pure empty state (when `mtdTotal === 0 && rows.length === 0`) — copy §5.
  3. Zero-MTD-with-history state (when `mtdTotal === 0 && rows.length > 0`) — summary line + copy §2b helper + list.
  4. Populated state — summary line + list.

  Empty-state and helper line are inline JSX branches, not separate
  components. List rendering is inline JSX — no separate
  `<ApiUsageList>` component. Column headers sourced from
  `copy.md §3`. Row secondary label pattern from `copy.md §4`.

+ `apps/web-platform/components/billing/retry-button.tsx`
  — `"use client"`. Renders `<button>` with copy §10 retry label.
  `onClick = () => router.refresh()`. `useRouter` from
  `next/navigation`.

+ `apps/web-platform/components/billing/info-tooltip.tsx`
  — `"use client"`. Click-to-open `Popover` (Radix, if already in
  deps — see Risks) or `<details>`/`<summary>` fallback. Takes
  `label` (trigger) + `content` (markdown or string) as props. Used
  twice: for copy §6 ("What is a token?") and copy §7 ("Why does cost
  vary?"). Single file; both usages instantiate with different props.

Files to modify:

+ `apps/web-platform/app/(dashboard)/dashboard/settings/billing/page.tsx`
  — mount `<ApiUsageSection userId={user.id} />` below `<BillingSection>` (one-line addition).

**Cache posture check:** grep `billing/page.tsx` for `export const dynamic`.
If present and set to `force-dynamic`, `router.refresh()` re-runs the
loader. If absent (default caching), add `export const dynamic = "force-dynamic"` to the page so Retry actually re-fetches.
Document the decision inline in the page file.

Test scenarios:

+ `apps/web-platform/test/api-usage-section.test.tsx`
  + Renders rows with correct `[Department]` labels.
  + MTD header shows total + count.
  + Renders copy §2b helper line when `MTD=0 && rows.length > 0`.
  + Does **NOT** render copy §2b helper when `MTD > 0` (regression protection — Kieran P1).
  + Renders pure empty state only when both MTD=0 AND rows empty.
  + Current-month conversation with `total_cost_usd = 0` does not count toward MTD (excluded by filter) but list may show prior-month rows — helper line renders, not empty state.
  + Error state renders `<RetryButton>` when loader returns null.
  + No word "estimated", "approximate", or `~` in rendered DOM.
  + Tooltip opens on click (via `<InfoTooltip>`).
  + Row containers have `cursor-default` and no `role="button"`.

+ `apps/web-platform/test/retry-button.test.tsx`
  + Clicking the button calls `router.refresh`.
  (This is the minimum test that proves the wiring exists;
  cache-posture integration is out of scope for unit tests and covered
  by manual QA.)

Test rules:

+ Run via `cd apps/web-platform && ./node_modules/.bin/vitest run`
  (per `cq-in-worktrees-run-vitest-via-node-node`).
+ Supabase mock uses thenable builder pattern (per learning
  `supabase-query-builder-mock-thenable-20260407.md`).
+ Single-DOM-tree responsive layout — no `hidden md:flex` (per learning).
+ No `require()` in tests (per `cq-vite-test-files-esm-only`).
+ `next/navigation` stubbed: `useRouter → { refresh: vi.fn() }`.

### Phase 3 — QA + ship

Tasks:

+ [ ] `cd apps/web-platform && ./scripts/dev.sh`; navigate to
      `/dashboard/settings/billing`. Screenshots at 1440px and 375px.
+ [ ] Create one real BYOK conversation. Cross-check dashboard row USD
      cost against the Anthropic console's per-request charge for that
      conversation. Must match to the cent (per copy §8). Attach both
      screenshots to the PR.
+ [ ] Update PR #2464 body: `Closes #1691` + `## Changelog` section +
      link to spec/copy/plan files + link to the descope follow-up
      issue.
+ [ ] `/ship` (applies `semver:patch`).
+ [ ] Post-merge: verify deploy workflows; add footnote to roadmap row
      3.6 referencing the regression-and-restore (PR #2036 → PR #2464);
      file the follow-up issue below if not already done.

## Files to Create / Modify (final)

**Create (4):**

+ `apps/web-platform/server/api-usage.ts`
+ `apps/web-platform/components/billing/api-usage-section.tsx`
+ `apps/web-platform/components/billing/retry-button.tsx`
+ `apps/web-platform/components/billing/info-tooltip.tsx`

**Tests (2 files):**

+ `apps/web-platform/test/api-usage.test.ts` (data layer + inline helpers)
+ `apps/web-platform/test/api-usage-section.test.tsx` (component)

Plus minimal `retry-button.test.tsx` — optional, keep if convenient.

**Modify (3):**

+ `apps/web-platform/app/(dashboard)/dashboard/settings/billing/page.tsx` (mount + cache directive if needed)
+ `knowledge-base/project/specs/feat-restore-byok-usage-dashboard/spec.md`
+ `knowledge-base/project/specs/feat-restore-byok-usage-dashboard/copy.md`

Post-merge only:

+ `knowledge-base/product/roadmap.md` (row 3.6 footnote)

## Acceptance Criteria

### Automated (CI / local vitest)

1. Section renders below subscription on `/dashboard/settings/billing`.
2. MTD summary renders correct total + count (UTC boundary).
3. List shows latest 50 conversations, newest first, scoped to user,
   filtered to `cost > 0`.
4. Row format: `[Department] · relativeTime` + Input + Output + Cost.
5. Zero-MTD-with-history renders copy §2b helper; does NOT render it
   when MTD > 0.
6. Pure empty state fires only when MTD=0 AND list empty.
7. No "estimated", "approximate", or `~` in rendered DOM.
8. Sub-cent values render 4dp; ≥ 0.01 renders 2dp.
9. Mobile 375px: no horizontal scroll; single DOM tree; tooltip
   opens on tap.
10. Error state renders `<RetryButton>` which calls `router.refresh()`
    on click.
11. Unknown/null `domain_leader` renders `"—"`.
12. Data layer throws on non-UUID input.
13. Any Supabase query error → whole view renders error state
    (all-or-nothing).
14. Vitest suite passes locally and in CI.
15. All copy sourced from `copy.md` (not hardcoded strings).

### Manual QA (PR ready-for-review gate)

16. One real conversation's dashboard row USD cost matches the
    Anthropic console figure to the cent. Screenshot in PR.
17. PR body contains `Closes #1691`.

## Risks / Open Decisions

| Risk | Mitigation |
|---|---|
| `router.refresh()` may serve stale data if page has default caching | Verified in Phase 2 cache-posture check; add `export const dynamic = "force-dynamic"` if missing. |
| UTC month boundary confuses users in far-west timezones (sees $0 early in their local month) | Accepted for v1. Footnote's Anthropic-console cross-check anchors users to the same UTC frame. File follow-up when user-TZ storage exists. |
| Radix Popover may not be in deps | Check `apps/web-platform/package.json` before Phase 2; if absent, use `<details>`/`<summary>` instead of adding a new dep for two tooltips (per `cq-before-pushing-package-json-changes`). |
| Chat cost badge and dashboard might diverge in formatting later | Out of scope for this PR; the badge renders via `usageData.totalCostUsd` in `chat-surface.tsx` with its own formatter. Follow-up task: grep cost-format call sites and consolidate. |

## Non-Goals (carried from spec)

+ New `/dashboard/usage` top-level route.
+ Per-model cost breakdown (no schema support).
+ 3-view toggle.
+ Date-range picker or day/week bucketing.
+ Per-domain-leader rollup view.
+ CSV export.
+ Budget threshold / progress bar (#1866).
+ Per-subagent cost attribution.
+ Pagination > 50 rows.
+ New chat cost badge (already mounted).
+ Persisting per-conversation model (one follow-up issue, below).
+ User-local timezone month boundary.
+ Shared cost-formatter consolidation across chat badge + dashboard.

## Follow-up Issue to File (Phase 3 exit)

**feat: Persist last-used model per conversation** — required to
re-introduce the Model column in the dashboard row. Add `last_model TEXT`
to `conversations`, write from `agent-runner.ts`. Milestone: `Post-MVP /
Later`. Re-evaluation: when a user asks "which model is my money going
to?" or when the landing page screenshots need refresh.

(Other potential follow-ups — date-range, CSV, pagination, TZ, shared
formatter — are covered by Non-Goals above. Do not file speculatively
per `wg-when-deferring-a-capability-create-a-issue` — file only when
there's active user pull.)

## Domain Review

Carry-forward from brainstorm — see `brainstorm:` in frontmatter for CPO

+ CMO assessments. spec-flow-analyzer ran during planning; G2
(retry-on-RSC), G3 (mobile tooltip), G4 (row interactivity), G6
(empty-state gating) are addressed in this plan. G1 (BYOK learn-more
link) and G5 (external-link icon) are deferred without tracking —
non-blocking polish.

Product/UX Gate: **blocking** tier (new `components/**/*.tsx`).
**Decision:** reviewed via carry-forward — prior shipped PR #1867
screenshots at `knowledge-base/product/design/byok-cost-tracking/screenshots/`
cover page design; layout here is a superset minus the Model column.
Copywriter ran during brainstorm. ux-design-lead skipped (prior-shipped
artifacts exist — not brainstorm-only).
