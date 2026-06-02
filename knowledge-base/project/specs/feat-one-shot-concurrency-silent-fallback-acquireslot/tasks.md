---
title: "Tasks — fix acquire_conversation_slot 23502 (missing workspace_id post-mig-059)"
branch: feat-one-shot-concurrency-silent-fallback-acquireslot
lane: single-domain
plan: knowledge-base/project/plans/2026-06-02-fix-acquire-slot-workspace-id-not-null-violation-plan.md
deepened: 2026-06-02
---

# Tasks

> Deepen-plan correction (2026-06-02): fix shape changed from "pure-SQL solo derivation" to
> "TS supplies the active workspace + widen RPC to a 4-arg `p_workspace_id`" (DROP+CREATE per mig-061
> precedent). Slot workspace_id MUST equal the conversation's (`getUserWorkspace(userId)`). Phase
> order is load-bearing: RPC contract (Phase 2) before TS callers (Phase 3).

## Phase 0 — Preconditions (verify only)

- [ ] 0.1 Confirm next migration number is `093` (`ls .../migrations/*.sql | sed … | sort -n | tail -1` → 092).
- [ ] 0.2 Re-read `029:101-166` (canonical RPC body), `059:205-229` (column + NOT NULL + RLS).
- [ ] 0.3 Read precedent `061_byok_audit_workspace_id_rpcs.sql` — note `DROP FUNCTION IF EXISTS …(old-sig)` + `CREATE` (lines 37,79), NOT `CREATE OR REPLACE`; and `063_*.down.sql` knowingly-broken caveat.
- [ ] 0.4 Read canonical workspace resolution: `workspace-resolver.ts:190-218` (`resolveCurrentWorkspaceId`, fails closed to userId), `getUserWorkspace`/`setUserWorkspace` (`ws-handler.ts:46,2294`), and `createConversation:808-819` (conversation gets `workspace_id = getUserWorkspace(userId)`).
- [ ] 0.5 Live read-only repro on DEV Supabase (MCP): `BEGIN; SELECT public.acquire_conversation_slot(<seed-user>, gen_random_uuid(), 5); ROLLBACK;` → expect 23502 on `workspace_id`. DEV only.

## Phase 1 — Failing test (RED)

- [ ] 1.1 Create `apps/web-platform/test/concurrency-acquire-slot-workspace-id.integration.test.ts` (model on `conversation-archive-release-slot.integration.test.ts`).
- [ ] 1.2 RED baseline: call pre-fix 3-arg RPC → confirm 23502 on `workspace_id`.
- [ ] 1.3 Post-fix assertions (after Phase 2): (a) solo user, `p_workspace_id = userId` → `status='ok'` + slot `workspace_id = userId`; (b) distinct owned non-solo workspace → slot carries THAT workspace_id.

## Phase 2 — Re-issue RPC as 4-arg (GREEN, contract first)

- [ ] 2.1 Create `apps/web-platform/supabase/migrations/093_acquire_slot_workspace_id.sql`: (1) `DROP FUNCTION IF EXISTS public.acquire_conversation_slot(uuid, uuid, integer);` (2) `CREATE FUNCTION …(p_user_id uuid, p_conversation_id uuid, p_effective_cap integer, p_workspace_id uuid)` = verbatim `029:101-166` body + add `workspace_id` to INSERT cols + value `p_workspace_id`; keep `security definer set search_path = public, pg_temp`, advisory lock, lazy sweep, cap-check, return shape verbatim; do NOT touch `do update set`. (3) `revoke all … (uuid,uuid,integer,uuid) from public` + `grant execute … (uuid,uuid,integer,uuid) to service_role`.
- [ ] 2.2 Create `093_acquire_slot_workspace_id.down.sql`: `DROP FUNCTION IF EXISTS …(uuid,uuid,integer,uuid)` then restore verbatim 3-arg `029:101-166` body + `029:205,208` grants; `knowingly-broken` header caveat (mirror `063` down-file).

## Phase 3 — TS call sites (GREEN, after contract)

- [ ] 3.1 `concurrency.ts`: add `workspaceId: string` param to `acquireSlot`; pass `p_workspace_id: workspaceId` in `supabase.rpc(...)` (`:83-87`). `touchSlot`/`releaseSlot` unchanged.
- [ ] 3.2 `ws-handler.ts`: resolve `getUserWorkspace(userId)` once in the start_session acquire block (fail-loud via existing "No workspace binding for user" path if null); pass to all 3 `acquireSlot` calls (`1445`, `1479`, `1497`).
- [ ] 3.3 Update `conversation-archive-release-slot.integration.test.ts:130-147` local direct-RPC helper to pass `p_workspace_id: user.id` (contract-pair sweep). `git grep 'rpc("acquire_conversation_slot"'` → 2 hits, both updated.
- [ ] 3.4 Run AC6/AC7 integration test → GREEN; confirm `reportSilentFallback` branch no longer fires.

## Phase 4 — Regression + types

- [ ] 4.1 `tsc --noEmit` from `apps/web-platform/` → clean (the new required arg makes `tsc` enumerate any missed call site).
- [ ] 4.2 `vitest run` over slots + ws-handler + agent-runner test set → green (AC8).

## Phase 5 — Ship + post-merge verify

- [ ] 5.1 PR body: `Closes #<tracking-issue>`, link Sentry `52442f7a9b77462b9927b1f055204cce` + post-mig-059 learning.
- [ ] 5.2 Post-merge: migration applies via `web-platform-release.yml#migrate`; verify via Supabase MCP exactly ONE `acquire_conversation_slot` overload remains, 4-arg `(uuid,uuid,integer,uuid)`, body contains `workspace_id`, no stale 3-arg (AC10).
- [ ] 5.3 Post-merge: confirm zero new `op:acquireSlot pg_code:23502` Sentry events post-deploy; close tracking issue (AC11).
