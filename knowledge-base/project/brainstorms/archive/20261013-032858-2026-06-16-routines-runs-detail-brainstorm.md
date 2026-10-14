# Brainstorm — Routines runs detail + filters + per-routine drawer (PR-4)

**Date:** 2026-06-16
**Branch:** feat-routines-runs-detail · **Draft PR:** #5410
**Builds on:** merged PR #5342 (PR-1 dashboard + run-log) + #5400 (PR-2 Concierge tab)
**Brand-survival threshold:** single-user incident (read-only, but touches the routine_runs run-log read path + widens the column projection; the PII-omission posture is load-bearing)

## What We're Building

Four enhancements to the merged routines dashboard, all **read-only** over the existing `routine_runs` WORM run-log — **no DB change, no migration, no writes**:

1. **Tab rename** — replace the shipped `✨ Draft a routine` + `new` badge with **"Draft a routine with Concierge"** (`components/routines/routines-surface.tsx`). Trivial; folds into this PR.
2. **Per-run detail panel** (the "log system") — clicking a Recent Runs row opens a detail panel showing the full record: `run_id`, `actor_class` (e.g. "manual (you)"), exact start/end timestamps, duration, status, and the full stored `error_summary` (un-truncated from the row preview). Today only failed rows drill in to a short summary.
3. **Recent Runs filters** — by routine (fnId), status (completed/failed), trigger source (scheduled/manual/agent), and date range.
4. **Per-routine slide-over drawer** — clicking a routine in the Routines tab opens an in-place drawer (no route change, no shareable URL) with the routine's metadata (domain, ownerRole, scheduleLabel, manualTrigger policy, last run) + that routine's filtered run log (reuses the per-run detail panel for rows).

## Why This Approach

- **Reuse, not rebuild.** `server/routines/list-routines.ts::listRecentRuns` already keyset-paginates the run-log; add optional filter params (`routineId`, `status`, `triggerSource`, `since`/`until`) as WHERE clauses. The per-routine drawer (#4) is just `listRecentRuns({ routineId })` — same code path as #3.
- **Drawer over dedicated route** (operator choice): lighter, stays in context, no new Next.js route. A client drawer component over the Routines list.
- **Detail panel uses existing data** (operator choice): the run-log row already holds every field. The only server change is widening the read projection to include `run_id` + `actor_class` (currently `RUN_COLS` omits them). **`actor_id` / `delegating_principal` stay omitted** — the detail panel shows `actor_class` ("manual"/"agent"/"system" + "you" for the operator), never the raw UUID, preserving PR-1's PII-omission posture.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Tab label → "Draft a routine with Concierge"; drop sparkles + "new" badge | Operator request; the tab is no longer "new" |
| 2 | "Log system" = per-run **detail panel** (full stored record), not richer captured log lines | Operator choice; no schema change, uses existing row |
| 3 | Filters: routine, status, trigger source, date range — server WHERE clauses on listRecentRuns | Reuses the existing keyset query; add optional params |
| 4 | Per-routine view = **slide-over drawer** (no route) | Operator choice; lighter than a dedicated page |
| 5 | Widen `RUN_COLS` projection to add `run_id` + `actor_class`; **NOT** `actor_id`/`delegating_principal` | Detail needs run_id + actor_class; PII columns stay omitted (PR-1 posture) |
| 6 | No DB change, no migration, no new write surface | Pure read-path enhancement |
| 7 | Visual design | Wireframes: `knowledge-base/product/design/routines/` (Phase 3.55) — TO LINK |

## User-Brand Impact

- **If this lands broken, the user experiences:** filters return wrong/missing runs (operator can't trust the history), or the per-routine drawer shows another routine's runs (mis-scoped filter), or the detail panel renders nothing.
- **If it leaks:** the widened projection or detail panel surfaces `actor_id`/`delegating_principal` (operator-PII UUIDs) that the list view deliberately omits — the one real exposure vector. Mitigated by keeping `RUN_COLS` projecting only `run_id` + `actor_class` (a coarse enum), never the raw actor UUIDs.
- **Brand-survival threshold:** single-user incident. `user-impact-reviewer` runs at plan time.

## Open Questions

1. **Filter UX** — inline filter bar above the Recent Runs table vs. a filter popover. → wireframe to propose (lean inline bar).
2. **Date-range control** — presets (24h / 7d / 30d / all) vs. a date picker. → lean presets for v1.
3. **Drawer run-log pagination** — reuse the existing "Load more" keyset, scoped to the routine. → yes.

## Domain Assessments

**Assessed:** Engineering, Product (CTO/CPO — the run-log read path + projection widening + a single-user-incident-family feature). Legal: no new data surface/table → no DSAR/legal change. Marketing/Operations/Sales/Finance/Support: not relevant (internal operator tool).

### Engineering (CTO)
**Summary:** Pure read-path enhancement; add optional filter params to `listRecentRuns` (WHERE clauses on the existing keyset query) + widen `RUN_COLS` to `run_id`/`actor_class` (NOT actor_id). Drawer is a client component over the Routines list; detail panel reuses the run row. No migration, no write surface. Keep the keyset cursor tuple (started_at,id) the PR-1 review fixed.

### Product (CPO)
**Summary:** The per-run detail panel + per-routine drawer + filters directly improve operator trust in "what the autonomous company did". Drawer (no route) is the right v1 weight. PII-omission (actor_class not actor_id) keeps the surface honest.
