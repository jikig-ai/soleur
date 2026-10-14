---
feature: routines-runs-detail
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-routines-runs-detail
draft_pr: 5410
---

# Spec — Routines runs detail + filters + per-routine drawer (PR-4)

## Problem Statement

The merged routines dashboard (PR-1 #5342, PR-2 #5400) shows a flat Recent Runs table and a routines list with no drill-in. Operators can't filter the run history, can't see a run's full record, and can't view one routine's runs in isolation. PR-4 adds these — all read-only over the existing `routine_runs` WORM run-log.

## Goals

- Rename the third tab to "Draft a routine with Concierge" (drop sparkles + "new" badge).
- Per-run detail panel: click a run row → full record (run_id, status+duration, exact timestamps, actor_class as human text, full error_summary).
- Recent Runs filters: routine, status, trigger source, date-range presets.
- Per-routine slide-over drawer: click a routine → metadata + that routine's scoped run-log (reuses the detail panel).

## Non-Goals

- No DB change / migration / new write surface (pure read path).
- No richer captured log lines (step-by-step capture deferred — would need middleware + schema change).
- No dedicated `/dashboard/routines/[fnId]` route (drawer chosen instead; shareable-URL deferred).
- Never surface `actor_id` / `delegating_principal` raw UUIDs (PR-1 PII-omission posture preserved).

## Functional Requirements

- **FR1** — Tab label → "Draft a routine with Concierge" in `components/routines/routines-surface.tsx` (remove `✨` + `new` badge). Wireframe 09.
- **FR2** — Recent Runs filter bar (wireframe 10): Routine dropdown (all fnIds from the routines list), Status segmented (All/Completed/Failed), Trigger dropdown (All/scheduled/manual/agent), Range presets (24h/7d/30d/All). Active filters shown as removable chips; "Clear" resets. Filtering is server-side via `listRecentRuns` params.
- **FR3** — `server/routines/list-routines.ts::listRecentRuns` gains optional filter params: `routineId?`, `status?`, `triggerSource?`, `since?` (ISO). Each becomes an `.eq()`/`.gte()` on the existing keyset query; the `(started_at,id)` tuple cursor (PR-1 review fix) is preserved.
- **FR4** — Widen `RUN_COLS` to add `run_id` + `actor_class`. **Do NOT add `actor_id`/`delegating_principal`.** `RunSummary`/`RecentRun` interfaces gain `run_id`, `actor_class`.
- **FR5** — Per-run detail panel (wireframe 11): clicking a run row opens a panel with routine name, run_id, status+duration, trigger_source + actor_class rendered as human text ("manual (you)" when actor_class==="human", "scheduled (system)", "agent"), exact started/ended, and full error_summary on failures. No raw actor UUIDs.
- **FR6** — Per-routine slide-over drawer (wireframe 12): clicking a routine in the Routines tab opens an in-place drawer (no route change) with metadata header (fnId, domain, ownerRole, scheduleLabel, manualTrigger badge [allowed|confirm], last-run summary) + that routine's run-log (`listRecentRuns({ routineId })`) with keyset "Load more". Drawer rows open the FR5 detail panel.

## Technical Requirements

- **TR1** — Read-only; reuse PR-1's `routine_runs` run-log + `list-routines.ts`. No migration, no new MCP tool, no write surface.
- **TR2** — Server filter params validated/bounded (status ∈ {completed,failed}; triggerSource ∈ {scheduled,manual,agent}; since parseable ISO; routineId ∈ EXPECTED_CRON_FUNCTIONS) — reject/ignore invalid rather than injecting into the query.
- **TR3** — `routine_runs_latest`/`routine_runs` reads stay RLS-enforced (session client) for the dashboard routes; agent tools (if extended) keep the service-client + projection that omits actor PII.
- **TR4** — Tests: filter param WHERE-clause assembly + the actor-PII-omission projection (assert `RUN_COLS` excludes actor_id/delegating_principal), per-run detail render, per-routine drawer mount + scoped query, tab rename.
- **TR5** — `.pen` wireframes (09–12) committed under `knowledge-base/product/design/routines/`.

## User-Brand Impact

- **If broken:** filters return wrong/missing runs; per-routine drawer shows another routine's runs (mis-scoped); detail panel renders nothing.
- **If it leaks:** the widened projection or detail panel surfaces `actor_id`/`delegating_principal` UUIDs the list view omits — the one exposure vector. Mitigated by projecting only `run_id` + `actor_class`.
- **Brand-survival threshold:** single-user incident.
