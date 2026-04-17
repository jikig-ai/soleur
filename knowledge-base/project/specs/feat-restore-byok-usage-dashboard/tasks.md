---
feature: Restore BYOK Usage Dashboard
issue: "#1691"
pr: "#2464"
branch: feat-restore-byok-usage-dashboard
plan: knowledge-base/project/plans/2026-04-17-feat-restore-byok-usage-dashboard-plan.md
spec: knowledge-base/project/specs/feat-restore-byok-usage-dashboard/spec.md
copy: knowledge-base/project/specs/feat-restore-byok-usage-dashboard/copy.md
status: ready-for-work
---

# Tasks: Restore BYOK Usage Dashboard

## Phase 1 — Data layer + spec/copy edits

### 1.1 Amend spec and copy

- [ ] 1.1.1 Update `spec.md` frontmatter: replace `bundled_with: "#2436"` with note that API shape already landed on main.
- [ ] 1.1.2 Update `spec.md` FR4: drop `model id`; columns are Input / Output / Cost.
- [ ] 1.1.3 Update `spec.md` FR8: retry re-runs via `router.refresh()` in a client island.
- [ ] 1.1.4 Update `spec.md` AC #4: remove model reference.
- [ ] 1.1.5 Update `spec.md` Open Question #2: close as "No model persisted; see follow-up issue."
- [ ] 1.1.6 Update `copy.md` §3: remove the `Model` column header.
- [ ] 1.1.7 Update `copy.md` §4: pattern becomes `[{Department}] · {relativeTime}`.
- [ ] 1.1.8 Add `copy.md` §2b (new): zero-MTD-with-history helper line.
- [ ] 1.1.9 Update `copy.md` §10: note retry calls `router.refresh()`.
- [ ] 1.1.10 Run `npx markdownlint-cli2 --fix` on both files (specific paths).

### 1.2 Data layer scaffold

- [ ] 1.2.1 Create `apps/web-platform/server/api-usage.ts` with:
  - File header comment: `// Caller MUST have verified the userId belongs to the authenticated session. This function trusts its input.`
  - Types: `ApiUsageRow`, `ApiUsage`, return shape `Promise<ApiUsage | null>`.
  - UUID validation helper; throws on invalid input.
  - `DOMAIN_LEADERS` → `Map<leaderId, domain>` built once at module load.
  - `monthStartIso = new Date(Date.UTC(y, m, 1)).toISOString()`.
  - Two Supabase queries in `Promise.all` (list + month scope) via `createServiceClient()`.
  - Destructures `{ data, error }` on both; returns `null` if either errors.
  - Coerces `total_cost_usd` via `Number(raw ?? 0)`.
  - Inline helpers: `formatRelativeTime(date)`, `formatUsd(n)`.

### 1.3 Data layer tests (TDD — RED first)

- [ ] 1.3.1 Create `apps/web-platform/test/api-usage.test.ts`.
- [ ] 1.3.2 Write failing tests for all scenarios in plan Phase 1 test list:
  - empty rows + 0 MTD with no conversations.
  - rows + correct MTD when current-month (UTC) conversations exist.
  - rows with MTD=0 when only prior-month conversations exist.
  - UTC boundary: `2026-04-01T04:00:00Z` → April; `2026-03-31T23:30:00Z` → March.
  - Domain label: known ID → `domain`; null → `"—"`; unknown legacy ID → `"—"`.
  - Returns `null` when list query errors / MTD query errors / both error.
  - NUMERIC string → `number` coercion.
  - Throws on non-UUID input before hitting Supabase.
  - `.gte("created_at", monthStartIso)` called with exact UTC boundary string.
  - Inline helpers: `formatUsd(0 | 0.0043 | 0.01 | 4.27)`, `formatRelativeTime(now | 5m | 2h | 3d | 30d)`.
- [ ] 1.3.3 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/api-usage.test.ts` — confirm tests fail (RED).
- [ ] 1.3.4 Implement `api-usage.ts` until all tests pass (GREEN).
- [ ] 1.3.5 Refactor if needed without breaking tests.

## Phase 2 — UI components

### 2.1 Tiny client islands

- [ ] 2.1.1 Create `apps/web-platform/components/billing/retry-button.tsx` — `"use client"`; renders button with copy §10 label; `onClick = () => router.refresh()`.
- [ ] 2.1.2 Create `apps/web-platform/components/billing/info-tooltip.tsx` — `"use client"`; click-to-open pattern. Check `apps/web-platform/package.json` for Radix Popover first; if absent, use `<details>`/`<summary>` fallback. Takes `label` and `content` props.

### 2.2 Section component + mount

- [ ] 2.2.1 Create `apps/web-platform/components/billing/api-usage-section.tsx` — server component. Branches in precedence:
  1. Error shell (loader returns null) + `<RetryButton>`.
  2. Pure empty state (MTD=0 AND rows empty) — copy §5.
  3. Zero-MTD-with-history (MTD=0 AND rows>0) — summary + copy §2b + list.
  4. Populated — summary + list.
- [ ] 2.2.2 Render column headers from copy §3; row secondary label from copy §4. No hardcoded strings.
- [ ] 2.2.3 Single-DOM-tree responsive layout (no `hidden md:flex`). Row container `cursor-default`, no `role="button"`.
- [ ] 2.2.4 Mount `<InfoTooltip>` twice in the section header: copy §6 ("What is a token?") and copy §7 ("Why does cost vary?").
- [ ] 2.2.5 Modify `apps/web-platform/app/(dashboard)/dashboard/settings/billing/page.tsx`: add `<ApiUsageSection userId={user.id} />` below `<BillingSection>`.
- [ ] 2.2.6 Cache posture check on `billing/page.tsx`: if no `export const dynamic`, add `export const dynamic = "force-dynamic"` with an inline comment explaining why.

### 2.3 Component tests

- [ ] 2.3.1 Create `apps/web-platform/test/api-usage-section.test.tsx`. Mock Supabase via thenable query-builder pattern (per learning). Stub `next/navigation`.
- [ ] 2.3.2 Write failing tests:
  - Rows render with correct `[Department]` labels.
  - MTD header shows total + count.
  - Copy §2b helper renders when `MTD=0 && rows.length > 0`.
  - Copy §2b does NOT render when `MTD > 0`.
  - Pure empty state renders only when MTD=0 AND rows empty.
  - Current-month `total_cost_usd = 0` conversation excluded; helper line renders if prior rows exist.
  - Error state + `<RetryButton>` renders when loader returns null.
  - No "estimated", "approximate", or `~` in rendered DOM.
  - Tooltip opens on click.
  - Row containers have `cursor-default` and no `role="button"`.
- [ ] 2.3.3 GREEN all tests.

- [ ] 2.3.4 Create `apps/web-platform/test/retry-button.test.tsx`: stub `useRouter`, assert click → `refresh` call.

### 2.4 Run full test suite

- [ ] 2.4.1 `cd apps/web-platform && ./node_modules/.bin/vitest run` — all tests pass locally.

## Phase 3 — QA + ship

### 3.1 Local verification

- [ ] 3.1.1 `cd apps/web-platform && ./scripts/dev.sh` — run dev server via Doppler.
- [ ] 3.1.2 Navigate to `/dashboard/settings/billing`. Verify:
  - Section renders below subscription.
  - MTD summary correct.
  - List renders with known rows.
  - Empty state copy correct if user has no conversations.
  - Mobile viewport (375px) has no horizontal scroll.
- [ ] 3.1.3 Screenshot at 1440px and 375px.

### 3.2 Anthropic console cross-check (QA gate)

- [ ] 3.2.1 Create one real BYOK conversation with a known prompt.
- [ ] 3.2.2 Note Anthropic console's per-request cost for that conversation.
- [ ] 3.2.3 Confirm dashboard row USD matches Anthropic console to the cent.
- [ ] 3.2.4 Capture the console screenshot alongside the dashboard screenshot.

### 3.3 PR finalization

- [ ] 3.3.1 Update PR #2464 body: `Closes #1691`, `## Changelog` section, links to plan/spec/copy, link to follow-up issue.
- [ ] 3.3.2 Attach screenshots from 3.1.3 and 3.2.4.
- [ ] 3.3.3 `/ship` skill — applies `semver:patch` label, runs pre-ship gates, marks ready for review.

### 3.4 Post-merge

- [ ] 3.4.1 Verify deploy workflows succeed (`after a PR merges to main, verify all release/deploy workflows succeed` — AGENTS.md).
- [ ] 3.4.2 File follow-up issue: `feat: Persist last-used model per conversation` → Post-MVP / Later.
- [ ] 3.4.3 Add footnote to `knowledge-base/product/roadmap.md` row 3.6 (line ~184) referencing the regression-and-restore cycle (PR #2036 → PR #2464).
- [ ] 3.4.4 Close #1691 via `Closes #1691` in PR body (auto-close on merge).

## Completion Gate

All boxes above checked. Manual QA screenshots attached. Anthropic
console cross-check confirmed to the cent. Follow-up issue filed.
Roadmap footnote updated.
