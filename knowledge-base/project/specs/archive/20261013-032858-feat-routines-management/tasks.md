---
feature: feat-routines-management
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-15-feat-routines-management-ui-plan.md
brand_survival_threshold: single-user incident
---

# Tasks: Inngest Routines Management UI (PR-1)

PR-2 (Concierge authoring) is gated on #5346 and gets its own plan — not tasked here.

## Phase 1 — Data model

- [x] 1.1 `server/inngest/routine-metadata.ts` — client-free leaf; `ROUTINE_METADATA: Record<fnId, {domain, ownerRole, scheduleLabel, manualTrigger}>` with one entry per `EXPECTED_CRON_FUNCTIONS` id; `manualTrigger:"confirm"` for protected crons (content-publisher, legal-audit, github-app-drift-guard, content-vendor-drift). No raw `cron` field.
  - [x] 1.1.1 `test/server/inngest/routine-metadata-parity.test.ts` — assert `keys(ROUTINE_METADATA) === EXPECTED_CRON_FUNCTIONS` (bound to the array). Hard CI gate.
- [x] 1.2 Migration `107_routine_runs.sql` + `.down.sql` — terminal-only-append WORM table; `-- LAWFUL_BASIS:` + `-- RETENTION:` headers; `ON DELETE RESTRICT` FKs (Art-17: pre-anonymised in account-delete.ts before auth-delete, #5372); no-mutate BEFORE UPDATE/DELETE trigger (037 pattern) honoring `app.worm_bypass` + REVOKE from anon/authenticated; RLS select-only; `write_routine_run()` + `anonymise_routine_runs()` SECURITY DEFINER RPCs (service-role grant, `search_path` pinned); index `(routine_id, started_at desc)`, NOT CONCURRENTLY. (Renumbered 104→107 + Art-17 cascade fix per #5372.)

## Phase 2 — Run-log middleware

- [x] 2.1 `server/inngest/middleware/run-log.ts` (model `sentry-correlation.ts`); register at `client.ts:68` after `sentryCorrelation`; write terminal row via `lib/supabase/service.ts` on `transformOutput`.
- [x] 2.2 Final-attempt gate (`ctx.attempt >= (maxAttempts ?? 1) - 1`, fail-safe to write); NOT inside a memoized `step.run`. Test: fail-then-succeed → one `completed` row.
- [x] 2.3 Derive `trigger_source` from `event.name`; read actor fields only from chokepoint-set keys; ignore caller-supplied actor fields. Test: forged `data.actor_class` overridden.
- [x] 2.4 Fail-soft: write failure mirrors to Sentry, never throws into the handler. Test: throwing RPC → routine ok.

## Phase 3 — Shared run chokepoint

- [x] 3.1 `server/routines/run-routine.ts` — `runRoutine({fnId, actorClass, actorId, delegatingPrincipal, confirmed})`: validate `fnId ∈ EXPECTED_CRON_FUNCTIONS`; enforce `manualTrigger` policy (409 on confirm && !confirmed); `inngest.send` with route-controlled keys spread LAST.
- [x] 3.2 Refactor `app/api/internal/trigger-cron/route.ts` to dispatch via `runRoutine` (`actorClass:'system'`, `confirmed:true`) — single `inngest.send` site. Test: legacy path records `system` attribution; policy enforced on session/agent path.

## Phase 4 — Session routes (thin adapters)

- [x] 4.1 `GET /api/dashboard/routines` + shared `listRoutinesWithLastRun()` (metadata ⋈ latest run; null-guard missing metadata).
- [x] 4.2 `GET /api/dashboard/routines/runs?cursor=` + shared keyset reader (empty-state shape).
- [x] 4.3 `POST /api/dashboard/routines/run` → `runRoutine(actorClass:'human', actorId:user.id, confirmed)`; 401 unauth; 409 confirmation_required. NOT in PUBLIC_PATHS.

## Phase 5 — Agent MCP tools (parity)

- [x] 5.1 `server/routines-tools.ts` — `routines_list`/`routine_runs_list` (shared read fns) + `routine_run` (runRoutine actor=agent).
- [x] 5.2 `server/tool-tiers.ts` — FQ keys: reads `auto-approve`, `routine_run` `gated`.
- [x] 5.3 `buildGateMessage` `routine_run` case (routine name + policy); agent confirm = review-gate (call runRoutine confirmed:true post-approve); no double-gate.

## Phase 6 — UI

- [x] 6.1 `app/(dashboard)/dashboard/routines/page.tsx` (template `audit/page.tsx`) + tab bar + grouped-by-domain list + row + Recent Runs table + Run-now confirm modal (wireframe 03/04 screens 01-03).
- [x] 6.2 Nav rail entry "Routines" (`next/link`).
- [x] 6.3 States: P0-1 ack + optimistic Running + disable-while-in-flight (covers P2-10); P1-4 empty; P1-5 failed-run drill-in (non-empty scrubbed `error_summary`); P1-6 keyset pagination. (P2-11 archived cut.)

## Phase 7 — Verify

- [x] 7.1 typecheck — clean.
- [x] 7.2 vitest — 515 feature tests + 1930 inngest tests green; `vitest run test/server/inngest/routine-metadata-parity.test.ts test/server/inngest/function-registry-count.test.ts test/lint/inngest-key-server-only.test.ts` + the new run-log/runRoutine tests.
- [ ] 7.3 (operator/CI) Observability discoverability_test: query `routine_runs` via Supabase MCP (no SSH).
- [ ] 7.4 (operator/CI) Browser test the Routines + Recent Runs tabs + Run-now modal.
