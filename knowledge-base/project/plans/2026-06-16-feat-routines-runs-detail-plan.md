---
title: Routines runs detail + filters + per-routine drawer
type: feat
issue: 5412
follows: 5342, 5400
branch: feat-routines-runs-detail
worktree: .worktrees/feat-routines-runs-detail
draft_pr: 5410
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Plan — Routines runs detail + filters + per-routine drawer (PR-4)

## Overview

Four read-only enhancements to the merged routines dashboard, all over the existing `routine_runs` run-log — **no DB change, no migration, no write surface, no new MCP tool**:
1. Tab rename → "Draft a routine with Concierge" (drop `✨` + `new` badge).
2. Per-run detail panel (the "log system"): click a run row → full record.
3. Recent Runs filters: routine, status, trigger source, date-range presets.
4. Per-routine slide-over drawer: click a routine → metadata + that routine's scoped run-log (reuses the detail panel).

## Research Reconciliation — Spec vs. Codebase (current `main`)

| Claim | Reality (verified) | Plan response |
|-------|--------------------|---------------|
| `listRecentRuns` keyset-paginates | `server/routines/list-routines.ts:93` — `opts: {cursor?, limit?}`; cursor is `started_at\|id` tuple via `.or()` (PR-1 review fix). `OrderedQuery` structural type exposes `.limit()` + `.or()` only. | Add optional `routineId`/`status`/`triggerSource`/`since` to `opts`; chain `.eq()`/`.gte()` BEFORE `.or()`/`.limit()`; extend `OrderedQuery` type with `.eq()`/`.gte()`. Preserve the tuple cursor. |
| `RUN_COLS` projection | `list-routines.ts:62` projects `id,routine_id,status,trigger_source,started_at,ended_at,duration_ms,error_summary` — already omits actor_id/delegating_principal/run_id. | Widen to add `run_id` + `actor_class` ONLY. `RunSummary`/`RecentRun` gain `run_id`, `actor_class`. **Never add actor_id/delegating_principal.** |
| Runs route | `app/api/dashboard/routines/runs/route.ts` — session-gated GET, parses cursor+limit, calls `listRecentRuns`. | Parse + validate the 4 filter params, pass through. Same session gate. |
| Tab state | `routines-surface.tsx:81` — `useState<"routines"|"runs"|"draft">`; tab label `✨ Draft a routine` + `new` badge at :104. | Rename label, drop sparkles + badge. |
| `listRecentRuns` has ONE consumer (runs route) | **WRONG (plan-review P1).** Second caller: the agent MCP tool `routine_runs_list` (`server/routines-tools.ts:83`) calls `listRecentRuns(getServiceClient(), {cursor,limit})`. New params stay optional → no breakage, BUT the widened `RUN_COLS` (run_id+actor_class) flows into the agent payload too. | Add `routines-tools.ts` to Files to Edit: update the `routine_runs_list` tool description to mention run_id+actor_class now in the payload. SAFE — actor_class is a coarse enum (system/human/agent), no PII; security review confirmed. Keep params optional. |
| Client-side run interfaces | `routines-surface.tsx:17-36` hand-maintains its OWN `RunSummary`/`RecentRun` copies (separate from list-routines.ts). | Add `run_id`/`actor_class` to BOTH the server interfaces AND the client copies. |
| `RecentRunRow` already has inline failed-row expansion | `routines-surface.tsx:537-577` — click a failed row → inline `expanded` `<tr>` showing error_summary. | The new per-run detail panel REPLACES this inline expansion (one detail path, reused by tab + drawer) — do not ship two run-detail UIs. |

## User-Brand Impact

- **If this lands broken, the user experiences:** filters return wrong/missing runs (operator can't trust the history); the per-routine drawer shows another routine's runs (mis-scoped filter); the detail panel renders nothing.
- **If it leaks, the user's workflow data is exposed via:** the widened projection or detail panel surfacing `actor_id`/`delegating_principal` (operator-PII UUIDs) the list view omits. Mitigated by projecting only `run_id` + `actor_class` (a coarse enum), never the raw actor UUIDs. CPO sign-off carried from brainstorm; `user-impact-reviewer` runs at review-time.
- **Brand-survival threshold:** single-user incident.

## Domain Review

**Domains relevant:** Engineering, Product (carry-forward from brainstorm).

### Engineering (CTO)
**Status:** reviewed (carry-forward)
**Assessment:** Pure read-path enhancement. Filter params = optional `.eq()`/`.gte()` chained before the existing `.or()`/`.limit()` keyset; preserve the `(started_at,id)` tuple cursor (PR-1 review fix). Widen `RUN_COLS` to `run_id`/`actor_class` only. Drawer + detail panel are client components over the existing list. No migration, no write surface.

### Product (CPO)
**Status:** reviewed (carry-forward) — sign-off recorded
**Assessment:** Detail panel + per-routine drawer + filters improve operator trust in the run history. Drawer (no route) is the right v1 weight. actor_class-not-actor_id keeps the surface honest.

### Product/UX Gate
**Tier:** blocking (modifies a user-facing dashboard surface + adds a drawer/panel)
**Decision:** reviewed — wireframes 09-12 approved by operator (mock sign-off 2026-06-16)
**Agents invoked:** ux-design-lead (brainstorm Phase 3.55), spec-flow-analyzer + plan-review panel (plan phase)
**Pencil available:** yes

## Observability

```yaml
liveness_signal:
  what: existing dashboard route telemetry — the runs route + listRecentRuns already capture to Sentry on error (no new session type)
  cadence: per request
  alert_target: Sentry (existing routine-runs-list surface tag)
  configured_in: app/api/dashboard/routines/runs/route.ts (existing 502 capture)
error_reporting:
  destination: Sentry (existing runs route 502 capture + a capture on the new per-routine route if added)
  fail_loud: yes — query errors surface as 502 + Sentry; the UI shows an error state
failure_modes:
  - mode: filter param injected/invalid → bad query
    detection: server validates/bounds params (TR2) and ignores/400s invalid; unit-tested
    alert_route: CI test + Sentry on 502
  - mode: projection leaks actor_id/delegating_principal
    detection: unit test asserts RUN_COLS excludes the PII columns; per-run detail render test asserts actor_class shown, actor_id absent
    alert_route: CI test-webplat
  - mode: per-routine drawer mis-scoped (shows other routines)
    detection: listRecentRuns({routineId}) unit test asserts the .eq("routine_id",…) filter; component test asserts scoped fetch
    alert_route: CI test-webplat
logs:
  where: existing dashboard request logs (Sentry)
  retention: existing platform retention
discoverability_test:
  command: grep -m1 -o actor_class apps/web-platform/server/routines/list-routines.ts
  expected_output: "actor_class (RUN_COLS widened to surface actor_class; single local grep, no ssh, no shell operators)"
```

## Implementation Phases

### Phase 1 — RED (tests first)
1.1 `test/server/routines/list-routines.test.ts` (extend): (a) `listRecentRuns({routineId})` chains `.eq("routine_id", …)`; (b) `{status}`/`{triggerSource}` chain `.eq(...)`; (c) `{since}` chains `.gte("started_at", …)`; (d) the `(started_at,id)` tuple cursor still works with filters applied; (e) **`RUN_COLS` includes `run_id`+`actor_class` and EXCLUDES `actor_id`/`delegating_principal`** (assert the projection string).
1.2 `test/server/routines/run-now-route.test.ts` or a runs-route test (extend/create): the runs route validates filter params — rejects/ignores an out-of-set status/triggerSource, a non-EXPECTED_CRON_FUNCTIONS routineId, an unparseable `since`; passes valid ones through.
1.3 `test/components/routines/routines-surface.test.tsx` (extend): tab label is "Draft a routine with Concierge" (no `✨`, no "new"); filter bar renders + changing a filter triggers a scoped refetch; clicking a run row opens the detail panel showing actor_class text (NOT a raw UUID); clicking a routine opens the drawer with metadata + scoped run-log; drawer row opens the detail panel.

### Phase 2 — GREEN
2.1 `server/routines/list-routines.ts`: extend `OrderedQuery` structural type with `eq(col,val)`/`gte(col,val)` that **return `OrderedQuery` itself (recursive)** so multiple filters chain and the cursor `.or()`/`.limit()` still follow (plan-review P2 — NOT a one-shot type ending in or/limit). Add optional `routineId`/`status`/`triggerSource`/`since` to `listRecentRuns` opts; apply as `.eq()`/`.gte()` before the cursor `.or()`/`.limit()`. Widen `RUN_COLS` to add `run_id`,`actor_class`; add both to `RunSummary`/`RecentRun`. (Phase 1.1 RED test must also extend the test mock's `chain` object — `list-routines.test.ts:22-33` — with `.eq()/.gte()` returning `chain`, else GREEN calls undefined methods.)
2.2 `app/api/dashboard/routines/runs/route.ts`: parse `routineId`/`status`/`triggerSource`/`since` query params; validate (status ∈ {completed,failed} — **NOT "running"**, which is a client-only optimistic state never persisted (107 stores only completed/failed); triggerSource ∈ {scheduled,manual,agent}; routineId ∈ EXPECTED_CRON_FUNCTIONS; since = parseable ISO → else ignore); pass valid ones to `listRecentRuns`.
2.3 `server/routines-tools.ts`: update the `routine_runs_list` tool description to mention `run_id` + `actor_class` are now in the run payload (the widened RUN_COLS flows here via the shared `listRecentRuns`). No behavior change; keep the service-client read; do NOT add actor_id.
2.4 `components/routines/routines-surface.tsx`: (a) rename tab label (drop sparkles+badge); (b) filter bar component (routine dropdown from the routines list, status segmented = All/Completed/Failed only, trigger dropdown, range presets → since) wired to the runs fetch with active-filter chips + Clear; (c) per-run detail panel component that **REPLACES the existing inline failed-row expansion** (`RecentRunRow` :537-577) — one detail-rendering path reused by both the Recent Runs tab and the drawer; renders the full record incl. `actor_class` mapped to plain text via a `{system,human,agent}`→label map with a plain fallback for any unmapped value (do NOT synthesize "(you)" — actorId is not projected); (d) per-routine slide-over drawer (metadata header from the routine list item + manualTrigger badge + scoped run-log via the runs fetch with `routineId` + keyset Load more; rows open the detail panel). Add `run_id`/`actor_class` to the client-side `RunSummary`/`RecentRun` copies at :17-36.

### Phase 3 — Verify
3.1 tsc clean. 3.2 routines + runs-route + component tests green; full webplat suite green. 3.3 soleur:qa (ship): filters work, detail panel shows full record (no actor UUID), drawer scoped + paginated.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] Tab reads "Draft a routine with Concierge" (no `✨`, no "new" badge); other tabs unaffected.
- [ ] Filter bar (routine/status/trigger/range) filters server-side via `listRecentRuns` params; active-filter chips + Clear work.
- [ ] Filter params validated server-side (status/triggerSource enums, routineId ∈ EXPECTED_CRON_FUNCTIONS, since parseable) — invalid ignored/400, never injected.
- [ ] `RUN_COLS` widened to `run_id`+`actor_class` ONLY; unit test asserts `actor_id`/`delegating_principal` absent from the projection.
- [ ] Per-run detail panel shows the full record with actor_class as human text; renders NO raw actor UUID.
- [ ] Per-routine drawer is scoped (`.eq("routine_id",…)`), keyset-paginated, opens the detail panel; metadata header shows manualTrigger badge.
- [ ] Keyset `(started_at,id)` tuple cursor preserved with filters applied.
- [ ] tsc clean; CI green; `Closes #5412`.

### Post-merge (operator/agent)
- [ ] Browser QA on dev (soleur:qa during ship) — filters, detail panel, drawer.
- [ ] No prd migration (no DB change) — N/A.

## Files to Edit
- `apps/web-platform/server/routines/list-routines.ts` — filter params + recursive OrderedQuery `.eq()/.gte()` + RUN_COLS widen + server interfaces.
- `apps/web-platform/app/api/dashboard/routines/runs/route.ts` — parse + validate + pass filter params.
- `apps/web-platform/server/routines-tools.ts` — update `routine_runs_list` tool description (run_id+actor_class now in payload; plan-review P1).
- `apps/web-platform/components/routines/routines-surface.tsx` — tab rename + filter bar + detail panel (replaces inline expansion) + per-routine drawer + client interface fields.

## Files to Create
- (extend) `apps/web-platform/test/server/routines/list-routines.test.ts`, `apps/web-platform/test/components/routines/routines-surface.test.tsx`; a runs-route filter test (extend existing or new `test/server/routines/runs-route-filters.test.ts`).

## Open Code-Review Overlap
None — checked open `code-review` issues; none reference `list-routines.ts`, the runs route, or `routines-surface.tsx` for this scope.

## Sharp Edges
- **Preserve the `(started_at,id)` tuple cursor.** PR-1's review fixed a keyset tie-break bug; filters must chain `.eq()/.gte()` BEFORE the cursor `.or()`/`.limit()`, not replace them. Re-verify pagination with a filter active.
- **Never widen the projection to actor PII.** FR4 adds `run_id`+`actor_class` only. A unit test asserts `actor_id`/`delegating_principal` are absent from `RUN_COLS` — this is the load-bearing PII guard.
- **Filter params are user input → validate before query.** status/triggerSource as enums, routineId ∈ EXPECTED_CRON_FUNCTIONS, since as parseable ISO. PostgREST parameterizes values (no SQLi), but bound them to avoid noisy 502s and reject nonsense (TR2).
- **actor_class "you" rendering:** actorId is NOT projected (PII), so the detail panel cannot show "manual (you)" keyed on the operator's id — render actor_class plainly ("manual"/"scheduled (system)"/"agent"). The wireframe's "(you)" is cosmetic; on a single-operator tenant a human-triggered run IS the operator, so "manual" suffices. Do not project actor_id just to render "(you)".
- A plan whose `## User-Brand Impact` is empty/placeholder fails deepen-plan Phase 4.6 — this one is filled.
