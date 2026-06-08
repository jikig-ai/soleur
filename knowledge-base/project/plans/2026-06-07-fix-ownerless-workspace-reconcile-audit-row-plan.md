---
title: "fix: owner-less workspace self-heal writes no kb_sync_history audit row"
type: fix
date: 2026-06-07
issue: 4906
branch: feat-one-shot-4906
lane: single-domain
brand_survival_threshold: aggregate pattern
---

# fix: owner-less workspace self-heal writes no `kb_sync_history` audit row (#4906)

## Enhancement Summary

**Deepened on:** 2026-06-07
**Sections enhanced:** Technical Considerations, Acceptance Criteria (AC2), Dependencies & Risks (precedent-diff added)
**Gates passed:** 4.6 User-Brand Impact (threshold `aggregate pattern`, valid), 4.7 Observability (5 fields, no SSH), 4.8 PAT-shaped (no matches), 4.9 UI-wireframe (no UI surface — skip)

### Key Improvements

1. **Precedent locked to `037_audit_byok_use.sql:79` `write_byok_audit`** — the canonical
   service-role-only SECURITY DEFINER writer taking a target-identity param. The new
   `append_kb_sync_row_for_user` mirrors this shape, NOT the `auth.uid()`-pinned
   migration-053 shape. Side-by-side precedent-diff added to Risks & Mitigations (Phase 4.4 gate).
2. **Auto-grant REVOKE gotcha codified into AC2.** Supabase runs
   `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon,
   authenticated, service_role`, so a bare `REVOKE ALL FROM PUBLIC` does **not** undo the
   `authenticated` grant (`037:98-104`). AC2 now requires the explicit named-role revoke
   `REVOKE ALL ... FROM PUBLIC, anon, authenticated` — without it a tenant client could
   write another user's history (the exact `aggregate-pattern` leak vector this plan guards).
3. **Migration number pinned to `100`** — latest applied is `099`
   (`apps/web-platform/supabase/migrations/` confirmed 2026-06-07).
4. **`workspace_id` keying precedent** — `057_byok_audit_workspace_id_rpcs.sql:39`
   (`p_workspace_id` threaded into a service-role audit RPC) confirms the codebase
   convention for service-role audit writes keyed on a workspace/identity param.

### New Considerations Discovered

- **Verify-the-negative pass confirmed** the load-bearing claim "no workspace-keyed
  `kb_sync_history` write path exists" — `git grep kb_sync_history` across migrations +
  server returned zero `workspace_id`/`p_user_id`/`for_user` hits. The new RPC is genuinely
  the first such path; nothing to reuse, the pattern is the 037 service-role writer.
- **`LANGUAGE sql` vs `plpgsql`**: 037's `write_byok_audit` uses `LANGUAGE sql` (a bare
  INSERT). The new RPC needs the read-merge-cap-write CTE from migration 053, which is
  expressible as a single `UPDATE` — so `LANGUAGE sql` is viable and simpler than the
  053 `plpgsql` wrapper (053 only used plpgsql for the `auth.uid()` guard, which the new
  service-role RPC drops). Implementer may choose either; `LANGUAGE sql` preferred for the
  single-statement body.

## Overview

Issue #4906 reports two pre-existing observability gaps surfaced while fixing the
dirty-clone reconcile freeze (#4901). **Premise validation (below) found that part 2
is already fixed on `origin/main`** — the unconditional pre-self-heal error mirror was
removed by PR #4972 and PR #4979. Only **part 1 remains live**: owner-less workspaces
self-heal (KB content syncs via `reset --hard`) but write **no `kb_sync_history` audit
row**, because all three `appendKbSyncRow` call sites in
`workspace-reconcile-on-push.ts` are gated behind `if (ownerId)`. So a successful
recovery on an owner-less workspace leaves no forensic trail.

This plan is therefore **scoped to part 1 only** (audit-row gap), with part 2 explicitly
recorded as already-resolved. The fix is a focused observability refinement on a single
Inngest fan-out handler plus one new co-tenant audit write path.

## Problem Statement / Motivation

`workspace-reconcile-on-push.ts` fans a GitHub push webhook out to every workspace
matching `(github_installation_id, normalizeRepoUrl(full_name))`. For each workspace it
resolves the owner via `workspace_members` (`role='owner'`) and writes a
`kb_sync_history` audit row attributed to that owner
(`apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts:259`):

```ts
const ownerId = (ownerRow as { user_id?: string } | null)?.user_id ?? null;
// ...
if (ownerId) {                                    // :272 (skip-not-ready)
  await appendKbSyncRow(ownerId, { ... });
}
// ...
if (ownerId) {                                    // :304 (sync failed)
  await appendKbSyncRow(ownerId, { ... });
}
// ...
if (ownerId) {                                    // :323 (ok / recovered)
  await appendKbSyncRow(ownerId, { ... });
}
```

When the owner lookup returns null (`ownerId === null`), all three writes are skipped.
The workspace that generated the chronic `git pull --ff-only` aborts (Sentry
`WEB-PLATFORM-1V`, count 39) has a null `ownerId`. #4901 now makes that workspace
self-heal (`WEB-PLATFORM-20` confirmed), and the KB content **is** synced — but no audit
row records the recovery, so the forensic trail (admin analytics, 30-day drift analysis)
is blind to it.

**Why an owner-less workspace is an anomaly.** The data model
(`apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql`)
guarantees every solo workspace a canary `workspace_members(role='owner')` row via a
backfill + a trigger (`workspaces.id = owner_user_id = users.id`, ADR-038 N2). An
owner-less workspace means that invariant has drifted for a specific workspace — itself a
signal worth recording. The fix must therefore both (a) record the recovery and (b) make
the missing-owner condition observable rather than silent.

## Proposed Solution

Two coordinated changes in `workspace-reconcile-on-push.ts`, plus a new audit write path
in `session-sync.ts`:

1. **New service-role audit write keyed on `workspace_id`.** Add
   `appendKbSyncRowForWorkspace(workspaceId, row)` to `session-sync.ts` that writes the
   audit row to `users.kb_sync_history` for the workspace's *backing user*. For solo
   workspaces `workspaces.id === users.id` (ADR-038 N2), so the workspace id resolves
   directly to a user row — the audit row lands on that user's history exactly as an
   owner-attributed row would. Because there is no `auth.uid()` in the Inngest context,
   this path uses the **service-role client** (the handler already holds service-role per
   `.service-role-allowlist:232`) and a new `append_kb_sync_row_for_user(p_user_id, ...)`
   SECURITY DEFINER RPC variant, rather than the `auth.uid()`-pinned tenant RPC.

2. **Fall back to workspace-keyed write when `ownerId` is null.** Replace the three
   `if (ownerId)` gates with `appendKbSyncRow(ownerId, row)` when an owner exists, else
   `appendKbSyncRowForWorkspace(ws.id, row)`. The `workspace_id` discriminator field is
   already on every row (`:283`, `:317`, `:334`), so the reader can still distinguish it.

3. **Make the missing-owner condition observable.** When `ownerId === null`, emit a
   single `warnSilentFallback` (non-paging warn) per workspace recording the
   owner-invariant drift, so the operator sees that an owner-less workspace was
   reconciled (and can repair the canary row), instead of the current silent skip.

**Part 2 (abort over-reported) is already resolved — no change.** See Research
Reconciliation below.

## Research Reconciliation — Issue Premise vs. Codebase

| Issue claim | Reality on `origin/main` (verified 2026-06-07) | Plan response |
|---|---|---|
| Part 1: owner-less self-heal writes no audit row; `appendKbSyncRow` gated on `if (ownerId)` at `workspace-reconcile-on-push.ts:323` | **Live.** Gate confirmed at lines 272, 304, **323**. `appendKbSyncRow` (`session-sync.ts:372`) routes through `getFreshTenantClient(userId)` → `append_kb_sync_row` RPC pinned to `auth.uid()`; there is **no** workspace-keyed write path. `kb_sync_history` is a JSONB column on `public.users` only — no workspace-keyed store exists. | Fixed by this plan (new `appendKbSyncRowForWorkspace` + service-role RPC variant). |
| Part 2: `syncWorkspace` calls `reportSilentFallback(syncError)` **before** self-heal, so a self-healed push still emits an error-level Sentry issue every time | **STALE — already fixed.** The unconditional pre-self-heal error mirror is gone. Current `workspace-sync.ts:115-139` routes `non_fast_forward` to a `log.info` breadcrumb only, then delegates to `selfHealNonFastForward`, which emits `warnSilentFallback` (warn, non-paging) on successful recovery (`:231`) and `reportSilentFallback` (error) only when recovery genuinely fails (`:204`, `:243`). Removed by PR #4972 ("stop error-level Sentry page for a self-healed reconcile ff-only abort") and PR #4979. | **Scope out** — record as already-resolved; no code change. Adds an AC asserting the no-pre-self-heal-error-mirror invariant as a regression guard. |
| "The `KbSyncStatus` chip for such a workspace cannot reflect the recovery" | **Partially accurate, but the consumer is forensic, not chip.** `/api/kb/tree:32-40` reads `kb_sync_history` only when `access.activeWorkspaceId === user.id` (solo own-row). An owner-less workspace has no logged-in user viewing its chip. The audit row's real consumer is the **admin analytics page** (`app/(dashboard)/dashboard/admin/analytics/page.tsx:30`, reads `kb_sync_history` across users) and the 30-day drift analysis. | Plan frames the audit row as forensic/operator-facing, not chip-facing. No chip change needed. |
| Cited refs #4901, #4882 | #4901 = PR (MERGED, the dirty-clone self-heal fix). #4882 = issue (CLOSED, KB-sync-stale alert follow-up). Both resolved. | No blockers; premise holds that these predate and are unrelated to part 1. |

**Premise Validation note:** Checked both cited premises against `origin/main`. Part 1
(audit-row gap) holds and is the load-bearing scope. Part 2 (pre-self-heal error mirror)
is stale — the code was restructured post-issue-filing by #4972/#4979; building a fix for
it would be wasted effort. All cited file:line references in the issue body were verified
against current source; the `:323` citation is exact. `appendKbSyncRow` and
`syncWorkspace` were both relocated since the issue was filed (`appendKbSyncRow` →
`session-sync.ts:372`, `syncWorkspace` → `workspace-sync.ts:96` via re-export), so the
issue's "`syncWorkspace` calls `reportSilentFallback`" path no longer lives where implied.

## Technical Considerations

- **No new audit-row schema.** The `KbSyncRow` shape (`session-sync.ts:327-347`) already
  carries `workspace_id`; no union widening, no migration to the row type.
- **New RPC variant required (model on 037, not 053).** The existing `append_kb_sync_row`
  RPC (`migration 053_append_kb_sync_row_rpc.sql`) is pinned to `auth.uid()` and raises
  `no auth.uid()` for service-role-without-JWT callers — so it is the wrong model to copy.
  The canonical model is `037_audit_byok_use.sql:79` `write_byok_audit`: a service-role-only
  SECURITY DEFINER writer taking a target identity as a parameter. The owner-less path has
  no user JWT, so it needs a sibling RPC `append_kb_sync_row_for_user(p_user_id uuid,
  p_row jsonb, p_cap int)` granted to `service_role` only. **The grant must use the explicit
  named-role revoke** `REVOKE ALL … FROM PUBLIC, anon, authenticated` (a bare
  `REVOKE … FROM PUBLIC` leaves the Supabase `ALTER DEFAULT PRIVILEGES` auto-grant to
  `authenticated` intact — `037:98-104`). Pin `search_path = public, pg_temp` per
  `cq-pg-security-definer-search-path-pin-pg-temp`. The body reuses migration 053's
  read-merge-cap CTE, parameterizing `WHERE id = p_user_id` instead of `v_caller`; the
  053 `auth.uid()` guard is dropped (so `LANGUAGE sql` suffices, like 037). See the
  Precedent-Diff table in Dependencies & Risks.
- **`workspaces.id → users.id` identity must be validated at write time.** For solo
  workspaces `workspaces.id = users.id` (ADR-038 N2), so `ws.id` is a valid `users.id`.
  But an owner-less workspace is *already* an invariant violation — `ws.id` may not have a
  backing `users` row in a non-solo / org workspace. The new RPC's UPDATE simply affects
  zero rows if `p_user_id` is not a `users.id` (no error, no row written); the handler
  logs the warn regardless, so an unresolvable workspace still surfaces. Document this as
  a deliberate best-effort: the audit row is written iff the workspace id maps to a user
  row, else only the drift warn fires.
- **Service-role allowlist already covers this handler** (`.service-role-allowlist:232`),
  so no allowlist edit is needed — but the new `createServiceClient().rpc(...)` call must
  stay inside the existing `step.run` closure where the service client is already created
  (`:249-250`), reusing it rather than re-importing.
- **NFR impacts:** observability/forensics completeness (audit trail). No latency-path
  change (Inngest worker, not user-interactive). No new external dependency.

## User-Brand Impact

- **If this lands broken, the user experiences:** an owner-less workspace's KB still syncs
  (the load-bearing self-heal from #4901 is untouched), but its recovery remains invisible
  in the admin analytics audit trail — i.e. a forensics gap, not a user-data loss. A
  buggy new RPC could in the worst case write an audit row to the wrong user's history.
- **If this leaks, the user's workflow is exposed via:** the new `workspace_id`-keyed
  write must land on the correct backing user's `kb_sync_history`; a mis-keyed
  `p_user_id` would surface one workspace's sync metadata in another user's analytics row.
  Mitigation: the RPC is `service_role`-only (no tenant reachability) and writes iff
  `p_user_id` is an exact `users.id` match.
- **Brand-survival threshold:** `aggregate pattern` — this is an audit-trail completeness
  refinement (`priority/p3-low`); a single missing forensic row is not a user-facing
  incident. The KB content itself syncs correctly regardless (self-heal unchanged). The
  cross-user-leak risk is bounded by the service-role-only + exact-id-match RPC design and
  would only matter as a pattern, not a single occurrence.

## Observability

```yaml
liveness_signal:
  what: "kb_sync_history audit row appended per reconciled workspace (owner-attributed OR workspace-keyed); admin analytics page reads the array"
  cadence: "per GitHub push webhook (per reconciled workspace)"
  alert_target: "Sentry issue (warn-level) on owner-invariant drift; no page"
  configured_in: "apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts (warnSilentFallback op=ownerless-reconcile); apps/web-platform/server/session-sync.ts (appendKbSyncRowForWorkspace)"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN (reportSilentFallback / warnSilentFallback in @/server/observability)"
  fail_loud: "warnSilentFallback op=ownerless-reconcile emits a WARN-level Sentry breadcrumb naming the workspace_id whose owner-canary row is missing; RPC failure mirrors via reportSilentFallback op=appendKbSyncRowForWorkspace"

failure_modes:
  - mode: "Owner-less workspace reconciles (owner-canary invariant drifted)"
    detection: "warnSilentFallback op=ownerless-reconcile fires once per such workspace; visible in Sentry without paging"
    alert_route: "operator via Sentry warn-level issue (non-paging)"
  - mode: "append_kb_sync_row_for_user RPC fails or affects 0 rows (workspace id has no backing users row)"
    detection: "reportSilentFallback op=appendKbSyncRowForWorkspace mirrors the RPC error; 0-row case logs the drift warn but no audit row lands"
    alert_route: "operator via Sentry"

logs:
  where: "Better Stack drain (pino) for info/warn breadcrumbs; Sentry for warn+ mirrors"
  retention: "Better Stack per plan retention; Sentry per project retention"

discoverability_test:
  command: "./node_modules/.bin/vitest run test/server/inngest/workspace-reconcile-on-push.test.ts --reporter=dot"
  expected_output: "all tests pass, including the new owner-less-fallback + drift-warn cases"
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — workspace-keyed audit write exists.** `session-sync.ts` exports
  `appendKbSyncRowForWorkspace(workspaceId: string, row: KbSyncRow): Promise<void>` that
  writes via the service-role client to `append_kb_sync_row_for_user`. Verify:
  `grep -n "export async function appendKbSyncRowForWorkspace" apps/web-platform/server/session-sync.ts` returns 1 line.
- [ ] **AC2 — new RPC migration is service-role-only + search_path pinned + named-role
  revoke.** `apps/web-platform/supabase/migrations/100_append_kb_sync_row_for_user_rpc.sql`
  adds `append_kb_sync_row_for_user(p_user_id uuid, p_row jsonb, p_cap int)` with
  `SECURITY DEFINER`, `SET search_path = public, pg_temp`, an **explicit named-role**
  `REVOKE ALL ON FUNCTION … FROM PUBLIC, anon, authenticated`, then
  `GRANT EXECUTE … TO service_role`. **The named-role revoke is load-bearing, NOT a bare
  `REVOKE … FROM PUBLIC`:** Supabase runs `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT
  EXECUTE ON FUNCTIONS TO anon, authenticated, service_role`, so a new function is
  auto-granted to `authenticated`; `REVOKE … FROM PUBLIC` alone does NOT undo that
  (precedent + rationale at `037_audit_byok_use.sql:98-104`). Without the named-role
  revoke, a tenant client could call the RPC and write another user's `kb_sync_history` —
  the exact cross-user leak vector named in User-Brand Impact. Verify all four:
  `grep -cE "SET search_path = public, pg_temp|REVOKE ALL.*FROM PUBLIC, anon, authenticated|GRANT EXECUTE.*TO service_role" apps/web-platform/supabase/migrations/100_*.sql` ≥ 3. (Read the 2-3 most recent migration files first; transaction-wrapped DDL — no `CONCURRENTLY`.)
- [ ] **AC3 — owner-less path writes a workspace-keyed row.** The three `if (ownerId)`
  branches in `workspace-reconcile-on-push.ts` (`:272`, `:304`, `:323`) each call
  `appendKbSyncRow(ownerId, …)` when `ownerId` is set, else
  `appendKbSyncRowForWorkspace(ws.id, …)`. Verify: zero remaining bare
  `if (ownerId) {` gates around `appendKbSyncRow` —
  `grep -nE "if \(ownerId\)" apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` returns only branches that also have an else.
- [ ] **AC4 — owner-invariant drift is observable.** When `ownerId === null`, the handler
  emits exactly one `warnSilentFallback` per workspace with `op: "ownerless-reconcile"`
  naming `workspace_id`. Verify via test (AC-T3 below), and no `reportSilentFallback`
  (error-level) fires for the benign owner-less recovery case.
- [ ] **AC5 — recovered owner-less self-heal lands an `{ok:true, recovered:true}` row.**
  Regression test: an owner-less workspace whose `syncWorkspace` returns
  `{ok:true, recovered:true}` produces a `kb_sync_history` append with
  `ok:true, recovered:true, workspace_id: ws.id` via the workspace-keyed path.
- [ ] **AC6 — part-2 already-fixed invariant guarded.** Assert (test or grep) that
  `workspace-sync.ts` does **not** call `reportSilentFallback` on the `non_fast_forward`
  pre-self-heal path: `grep -nE "non_fast_forward" -A20 apps/web-platform/server/workspace-sync.ts` shows `log.info` + delegation to `selfHealNonFastForward`, and the only error-level mirror on the recovery-success path is `warnSilentFallback` (`:231`). This codifies the stale-premise finding as a regression guard.
- [ ] **AC7 — tests run under vitest (not bun).** New/changed tests live under
  `apps/web-platform/test/**/*.test.ts` and pass via
  `./node_modules/.bin/vitest run test/server/inngest/workspace-reconcile-on-push.test.ts`
  (bun test is blocked by `apps/web-platform/bunfig.toml [test] pathIgnorePatterns`).
- [ ] **AC8 — owner-attributed path unchanged.** Existing tests for the owner-present
  happy path, fan-out, sync-failure, and recovered cases still pass (no regression to the
  `appendKbSyncRow(ownerId, …)` path).
- [ ] **AC9 — PR body uses `Closes #4906` (code fix lands at merge, no post-merge
  operator step beyond the migration apply which `/soleur:ship` handles).**

### Post-merge (operator / ship)

- [ ] **AC10 — migration applied to prod.** The new `append_kb_sync_row_for_user`
  migration is applied (handled by `/soleur:ship` post-merge migration verify via the
  Supabase MCP / `web-platform-release.yml#migrate` path — NOT a manual SSH step).

## Test Scenarios

### Acceptance Tests (RED phase targets)

- **AC-T1 (AC5):** Given an owner-less workspace (`workspace_members` owner lookup returns
  null) whose `syncWorkspace` resolves `{ok:true, recovered:true}`, when the reconcile
  handler runs, then `appendKbSyncRowForWorkspace` is called once with
  `{ok:true, recovered:true, workspace_id: ws.id, trigger:"webhook_push"}` and
  `appendKbSyncRow` (owner path) is NOT called.
- **AC-T2 (AC3):** Given an owner-less workspace whose `syncWorkspace` resolves
  `{ok:false, errorClass:"sync_failed"}`, when the handler runs, then
  `appendKbSyncRowForWorkspace` is called with the failure row (`ok:false,
  error_class:"sync_failed"`) AND `reportSilentFallback op="sync"` still fires (the
  genuine failure is still paged — unchanged from owner path).
- **AC-T3 (AC4):** Given an owner-less workspace, when the handler runs, then exactly one
  `warnSilentFallback` with `op:"ownerless-reconcile"` naming the `workspace_id` fires,
  and no error-level `reportSilentFallback` fires for the benign recovery case.
- **AC-T4 (AC4 / skip-not-ready):** Given an owner-less workspace whose dir is not
  provisioned, when the handler runs, then `appendKbSyncRowForWorkspace` is called with
  `{ok:false, error_class:"workspace_not_ready", workspace_id: ws.id}` (the `:272` skip
  branch also writes via the workspace path now).

### Regression Tests

- **AC-T5 (AC8):** Given an owner-present workspace, the existing happy-path / fan-out /
  sync-failure / recovered tests pass unchanged — `appendKbSyncRow(ownerId, …)` still
  called, `appendKbSyncRowForWorkspace` NOT called.
- **AC-T6 (AC6):** Given a `non_fast_forward` (dirty-tree) abort that self-heals, then
  `workspace-sync.ts` emits no error-level `reportSilentFallback` on the pre-self-heal
  path — only `log.info` then `warnSilentFallback` on recovery success (guards against a
  future re-introduction of the #4972-removed error mirror).

### Edge Cases

- **Owner-less + workspace id has no backing `users` row** (org/non-solo workspace
  drift): `append_kb_sync_row_for_user` UPDATE affects 0 rows (no error), the drift warn
  still fires, no audit row lands. Test the RPC-returns-no-error / 0-row contract at the
  handler level via the `appendKbSyncRowForWorkspace` spy (the spy resolves; the handler
  does not throw).

## Files to Edit

- `apps/web-platform/server/session-sync.ts` — add
  `appendKbSyncRowForWorkspace(workspaceId, row)` (service-role client →
  `append_kb_sync_row_for_user` RPC), mirroring the best-effort try/catch +
  `reportSilentFallback` shape of `appendKbSyncRow` (`:372-398`).
- `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` — replace
  the three `if (ownerId)` gates (`:272`, `:304`, `:323`) with owner-or-workspace
  branching; add the `ownerId === null` → `warnSilentFallback op="ownerless-reconcile"`
  drift signal; import `appendKbSyncRowForWorkspace` (and `warnSilentFallback` if not
  already imported — it is, `:22`).
- `apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts` — add
  AC-T1..AC-T5 cases; extend the `appendKbSyncRowForWorkspace` mock alongside the existing
  `appendKbSyncRowSpy`; add owner-less rows to the `OWNERS` map fixture (`:50-64`,
  `:75-83`).
- `apps/web-platform/test/kb-route-helpers.test.ts` — the existing self-heal warn/error
  split tests live here (`syncWorkspace` is re-exported via `kb-route-helpers`; there is
  no dedicated `workspace-sync.test.ts`). Add AC-T6 here if #4972's tests do not already
  assert the no-pre-self-heal-error-mirror invariant; otherwise satisfy AC6 with a
  grep-based source guard.

## Files to Create

- `apps/web-platform/supabase/migrations/100_append_kb_sync_row_for_user_rpc.sql` —
  service-role-only SECURITY DEFINER RPC keyed on `p_user_id`. Mirror the **037
  `write_byok_audit` shape** (service-role-only writer taking an identity param), NOT the
  053 `auth.uid()`-pinned shape. Body reuses migration 053's read-merge-cap CTE with
  `WHERE id = p_user_id`. (Number `100` = latest applied `099` + 1, confirmed 2026-06-07;
  re-confirm the next free number at /work time in case another migration lands first.)

## Domain Review

**Domains relevant:** Engineering (CTO)

This is a single-domain engineering/observability bug fix (`domain/engineering`,
`priority/p3-low`). No Product/UX surface (no new pages, components, or user-facing
flows — the audit row's consumer is the admin analytics page, which already reads
`kb_sync_history` and needs no change). No marketing/legal/finance/sales/support/ops
implications.

**Product/UX Gate:** NONE. Mechanical UI-surface check — `## Files to Edit` and
`## Files to Create` contain zero paths under `components/**`, `app/**/page.tsx`,
`app/**/layout.tsx`, or any UI-surface glob. The plan implements an Inngest handler +
SQL RPC + tests only.

**GDPR / Compliance (Phase 2.7):** The migration touches `.sql` (regulated-data surface
per the canonical regex). Assessment: the new RPC writes operational sync-metadata
(timestamps, sha, ok/error_class, workspace_id) to an existing `kb_sync_history` column —
no new personal-data category, no new lawful-basis question, no Article 9 special
category. It is a service-role-scoped variant of an existing tenant RPC (migration 053)
with an identical data shape. The cross-user-write risk is bounded by `service_role`-only
grant + exact `p_user_id` match. No Critical finding; advisory note only — no
`compliance-posture.md` write required. (A full `/soleur:gdpr-gate` pass at /work time is
cheap and recommended given the `.sql` surface, but no Critical is anticipated.)

**Infrastructure (Phase 2.8):** None. The handler already runs on provisioned Inngest
infrastructure; the migration applies via the existing `web-platform-release.yml#migrate`
path. No new server, secret, vendor, cron, or persistent runtime process. Skip the
`## Infrastructure (IaC)` section.

## Dependencies & Risks

### Precedent-Diff (Phase 4.4 gate) — new RPC vs. canonical service-role writer

The new `append_kb_sync_row_for_user` RPC is a **pattern-bound** SQL `SECURITY DEFINER`
function with an established sibling precedent. Grepped precedents:

| Aspect | Migration 053 `append_kb_sync_row` (the WRONG model to copy) | Migration 037 `write_byok_audit` (the RIGHT model) | New RPC |
|---|---|---|---|
| Caller identity | `auth.uid()`-pinned; `RAISE EXCEPTION` if null | passed as `p_founder_id` param | `p_user_id` param (no `auth.uid()`) |
| Grant | `TO authenticated` | `TO service_role` | `TO service_role` |
| Revoke | `FROM PUBLIC, anon, authenticated` | `FROM PUBLIC, anon, authenticated` (named-role, load-bearing per `:98-104`) | `FROM PUBLIC, anon, authenticated` (named-role) |
| `search_path` | `public, pg_temp` | `public, pg_temp` | `public, pg_temp` |
| Language | `plpgsql` (only for the auth.uid guard) | `sql` (bare statement) | `sql` (single UPDATE; guard dropped) |
| Body | read-merge-cap CTE → `UPDATE … WHERE id = v_caller` | `INSERT … VALUES (p_*)` | read-merge-cap CTE (from 053) → `UPDATE … WHERE id = p_user_id` |

**Why 037 is the model, not 053:** the owner-less reconcile has no user JWT, so the
`auth.uid()` pin in 053 would `RAISE EXCEPTION 'no auth.uid()'` and lose the row. 037's
`write_byok_audit` is the canonical service-role-only writer taking a target identity as a
parameter — exactly this shape. The body keeps 053's read-merge-cap CTE (so the heterogeneous
JSONB array + 100-cap semantics are preserved), but parameterizes `WHERE id = p_user_id`.
`057_byok_audit_workspace_id_rpcs.sql:39` further confirms the convention of threading an
identity param into a service-role audit RPC. **No prior art for a `workspace_id`-keyed
`kb_sync_history` write exists (verified-negative grep), so the pattern is the 037 writer.**

- **Risk: new RPC mis-keys the audit row to the wrong user.** Mitigation: exact
  `WHERE id = p_user_id` match; **named-role** `service_role`-only grant (AC2 — the
  `authenticated` auto-grant gotcha is the real trap here, not the WHERE clause); tests
  assert the `workspace_id` discriminator on the written row and that the spy is called
  with `ws.id`.
- **Risk: `workspaces.id` is not a `users.id` for a non-solo/org owner-less workspace.**
  Mitigation: the RPC's UPDATE affects 0 rows (no error), the drift warn still fires; the
  audit row is best-effort by design (documented). The fix does not assume the solo
  identity holds — it degrades to "warn only" when it doesn't.
- **Risk: re-introducing the #4972-removed error mirror.** Mitigation: AC6/AC-T6 codify
  the no-pre-self-heal-error-mirror invariant as a regression guard.
- **Dependency:** the migration must apply before the new `appendKbSyncRowForWorkspace`
  path is exercised in prod. Handled by `/soleur:ship` migration-apply ordering (the code
  path is best-effort try/catch, so a not-yet-applied RPC only loses an audit row, never
  throws — graceful degradation if ordering slips).

## References & Research

### Internal References

- Owner gate (the bug): `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts:259,272,304,323`
- Tenant audit RPC (the precedent to mirror): `apps/web-platform/server/session-sync.ts:372-398` + `apps/web-platform/supabase/migrations/053_append_kb_sync_row_rpc.sql`
- `KbSyncRow` shape (already carries `workspace_id`): `apps/web-platform/server/session-sync.ts:327-347`
- Self-heal flow (part 2 already-fixed): `apps/web-platform/server/workspace-sync.ts:96-255` (`reportSilentFallback` split by recoverability, `warnSilentFallback` on recovery `:231`)
- Owner-canary invariant: `apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql:184-323`
- Service-role allowlist (handler already covered): `apps/web-platform/.service-role-allowlist:225-238`
- Chip reader (consumer is forensic, not chip): `apps/web-platform/app/api/kb/tree/route.ts:32-50`; admin analytics reader: `apps/web-platform/app/(dashboard)/dashboard/admin/analytics/page.tsx:30`
- Test conventions: vitest only (`apps/web-platform/package.json` `"test": "vitest"`, `vitest.config.ts` node project glob `test/**/*.test.ts`); bun test blocked (`apps/web-platform/bunfig.toml [test]`)

### Related Work

- Closes: #4906
- Refs: #4901 (PR, dirty-clone self-heal — load-bearing fix this refines), #4882 (issue, KB-sync-stale alert)
- Part-2 already-fixed by: #4972 (stop error-level Sentry page for self-healed reconcile), #4979 (render model.likec4.json off-tree)
- `workspace_id` discriminator precedent: #4728
