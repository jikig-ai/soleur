---
title: "Tasks — owner-less workspace reconcile audit-row fix (#4906)"
plan: knowledge-base/project/plans/2026-06-07-fix-ownerless-workspace-reconcile-audit-row-plan.md
issue: 4906
branch: feat-one-shot-4906
lane: single-domain
---

# Tasks — owner-less workspace self-heal writes no `kb_sync_history` audit row (#4906)

Scope: part 1 (audit-row gap) only. Part 2 (abort over-reported) is already fixed on
`origin/main` by #4972/#4979 — covered by a regression-guard task, not a code change.

## Phase 0 — Preconditions (verify before coding)

- 0.1 Re-confirm the three `if (ownerId)` gates still exist at
  `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` (`:272`,
  `:304`, `:323`): `grep -nE "if \(ownerId\)" <file>` → 3.
- 0.2 Re-confirm part-2 is still fixed: `apps/web-platform/server/workspace-sync.ts`
  `non_fast_forward` path is `log.info` + `selfHealNonFastForward` (no pre-self-heal
  `reportSilentFallback`); recovery success emits `warnSilentFallback` (`:231`).
- 0.3 Re-confirm the next free migration number (`ls apps/web-platform/supabase/migrations/`;
  latest was `099` on 2026-06-07 → `100`, but re-check in case another landed).
- 0.4 Read the precedent `apps/web-platform/supabase/migrations/037_audit_byok_use.sql:79-104`
  (`write_byok_audit` + the named-role-revoke rationale) and `053_append_kb_sync_row_rpc.sql`
  (read-merge-cap CTE to reuse).
- 0.5 Confirm runner is vitest: existing test
  `apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts` runs via
  `./node_modules/.bin/vitest run <path>` (bun test blocked by `bunfig.toml [test]`).

## Phase 1 — RED (failing tests first; `cq-write-failing-tests-before`)

- 1.1 In `workspace-reconcile-on-push.test.ts`: add an `appendKbSyncRowForWorkspace` mock
  alongside `appendKbSyncRowSpy` (mock `@/server/session-sync`); add owner-less workspace
  rows to the `OWNERS` map fixture (an entry whose owner lookup returns null).
- 1.2 AC-T1 (AC5): owner-less + `syncWorkspace → {ok:true, recovered:true}` →
  `appendKbSyncRowForWorkspace(ws.id, {ok:true, recovered:true, workspace_id, trigger:"webhook_push"})`
  called once; owner-path `appendKbSyncRow` NOT called. (RED)
- 1.3 AC-T2 (AC3): owner-less + `{ok:false, errorClass:"sync_failed"}` →
  `appendKbSyncRowForWorkspace` with the failure row AND `reportSilentFallback op="sync"`
  still fires. (RED)
- 1.4 AC-T3 (AC4): owner-less → exactly one `warnSilentFallback op:"ownerless-reconcile"`
  naming `workspace_id`; no error-level `reportSilentFallback` for the benign case. (RED)
- 1.5 AC-T4 (AC4/skip-not-ready): owner-less + dir not provisioned →
  `appendKbSyncRowForWorkspace(ws.id, {ok:false, error_class:"workspace_not_ready", workspace_id})`. (RED)
- 1.6 AC-T6 (AC6, part-2 regression guard): in
  `apps/web-platform/test/kb-route-helpers.test.ts` (re-exports `syncWorkspace`), assert the
  `non_fast_forward` self-heal path emits no error-level `reportSilentFallback` pre-self-heal
  and only `warnSilentFallback` on recovery. If #4972's tests already cover this, satisfy
  AC6 with a source-grep guard instead.

## Phase 2 — GREEN (implement)

- 2.1 Create `apps/web-platform/supabase/migrations/100_append_kb_sync_row_for_user_rpc.sql`:
  `append_kb_sync_row_for_user(p_user_id uuid, p_row jsonb, p_cap int DEFAULT 100)`,
  `SECURITY DEFINER`, `SET search_path = public, pg_temp`, body = migration 053's
  read-merge-cap CTE with `WHERE id = p_user_id` (drop the `auth.uid()` guard;
  `LANGUAGE sql` ok). Then:
  `REVOKE ALL ON FUNCTION public.append_kb_sync_row_for_user(uuid, jsonb, int) FROM PUBLIC, anon, authenticated;`
  `GRANT EXECUTE ON FUNCTION public.append_kb_sync_row_for_user(uuid, jsonb, int) TO service_role;`
  (named-role revoke is load-bearing — `037:98-104`). Add a `.down.sql` if the repo
  convention requires one (check sibling migrations).
- 2.2 In `apps/web-platform/server/session-sync.ts`: add
  `export async function appendKbSyncRowForWorkspace(workspaceId: string, row: KbSyncRow): Promise<void>`
  — service-role client (`createServiceClient`), `.rpc("append_kb_sync_row_for_user",
  { p_user_id: workspaceId, p_row: row, p_cap: KB_SYNC_HISTORY_CAP })`, best-effort
  try/catch mirroring `appendKbSyncRow` (`:372-398`) with
  `reportSilentFallback op:"appendKbSyncRowForWorkspace"` on error.
- 2.3 In `workspace-reconcile-on-push.ts`: at the three `appendKbSyncRow` sites (`:272`,
  `:304`, `:323`), write `ownerId ? appendKbSyncRow(ownerId, row) : appendKbSyncRowForWorkspace(ws.id, row)`
  (extract a small `writeAuditRow(row)` helper inside the step closure to avoid repetition).
- 2.4 In `workspace-reconcile-on-push.ts`: when `ownerId === null`, emit one
  `warnSilentFallback(new Error("owner-less workspace reconciled"), { feature:
  WORKSPACE_RECONCILE_SENTRY_FEATURE, op:"ownerless-reconcile", extra:{ workspaceId: ws.id,
  installationId, deliveryId }, message:"Owner-canary row missing — reconciled via workspace-keyed audit" })`.
- 2.5 Run the RED tests until green:
  `./node_modules/.bin/vitest run test/server/inngest/workspace-reconcile-on-push.test.ts test/kb-route-helpers.test.ts`.

## Phase 3 — Verify ACs

- 3.1 AC1: `grep -n "export async function appendKbSyncRowForWorkspace" apps/web-platform/server/session-sync.ts` → 1.
- 3.2 AC2: `grep -cE "SET search_path = public, pg_temp|REVOKE ALL.*FROM PUBLIC, anon, authenticated|GRANT EXECUTE.*TO service_role" apps/web-platform/supabase/migrations/100_*.sql` ≥ 3.
- 3.3 AC3: no bare `if (ownerId) {` gate remains around `appendKbSyncRow` (each has an else).
- 3.4 AC6: part-2 regression guard green (or source-grep guard present).
- 3.5 AC7/AC8: full reconcile + kb-route-helpers vitest suites green (owner-path unchanged).
- 3.6 `tsc --noEmit` clean for `apps/web-platform`.

## Phase 4 — Ship

- 4.1 PR body: `Closes #4906`; `## Changelog` (semver:patch — bug fix); note the new
  migration `100_*` for the ship migration-apply step.
- 4.2 GDPR-gate (advisory) given the `.sql` surface — no Critical anticipated.
- 4.3 Capture a learning if the named-role-revoke gotcha or the part-2-already-fixed
  stale-premise finding is worth compounding (directory + topic only; no dated filename).

## Notes

- Part 2 ("abort over-reported") is **not** a code change — already fixed by #4972/#4979.
  The plan's Research Reconciliation records this; AC6/AC-T6 only guard against regression.
- `KbSyncRow` already carries `workspace_id` (`session-sync.ts:346`) — no row-type widening.
- The audit row's consumer is forensic (admin analytics + 30-day drift), not the
  user-facing chip (which is keyed to a logged-in user's own solo workspace).
