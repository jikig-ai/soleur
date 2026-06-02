---
title: "Tasks — fix acquire_conversation_slot 23502 (missing workspace_id post-mig-059)"
branch: feat-one-shot-concurrency-silent-fallback-acquireslot
lane: single-domain
plan: knowledge-base/project/plans/2026-06-02-fix-acquire-slot-workspace-id-not-null-violation-plan.md
---

# Tasks

## Phase 0 — Preconditions (verify only)

- [ ] 0.1 Confirm next migration number is `093` (`ls .../migrations/*.sql | sed … | sort -n | tail -1` → 092).
- [ ] 0.2 Re-read `029:101-166` (canonical RPC body), `059:205-229` (column + NOT NULL + RLS).
- [ ] 0.3 Read precedent `061_byok_audit_workspace_id_rpcs.sql` + down-file convention in `063_post_workspace_rpc_repair.down.sql`.
- [ ] 0.4 Confirm solo-canary invariant in `053:184-210` (handle_new_user owner-workspace backfill).
- [ ] 0.5 Live read-only repro on DEV Supabase (MCP): `BEGIN; SELECT public.acquire_conversation_slot(<seed-user>, gen_random_uuid(), 5); ROLLBACK;` → expect 23502 on `workspace_id`. DEV only.

## Phase 1 — Failing test (RED)

- [ ] 1.1 Create `apps/web-platform/test/concurrency-acquire-slot-workspace-id.integration.test.ts` (model on `conversation-archive-release-slot.integration.test.ts`).
- [ ] 1.2 Synthesize a solo user, call the RPC with a fresh conversation id, assert `status='ok'` + persisted `workspace_id = userId`.
- [ ] 1.3 Run against pre-fix RPC → confirm RED (23502 / status error).

## Phase 2 — Re-issue RPC (GREEN)

- [ ] 2.1 Create `apps/web-platform/supabase/migrations/093_acquire_slot_workspace_id.sql`: verbatim `029:101-166` body + (a) `v_workspace_id` declare + `workspace_members` solo-canary resolution SELECT with fail-loud `RAISE EXCEPTION` on null, (b) add `workspace_id` to INSERT column list + value `v_workspace_id`. Keep 3-arg signature, `security definer`, `set search_path = public, pg_temp`. Do NOT touch `do update set`.
- [ ] 2.2 Create `093_acquire_slot_workspace_id.down.sql` restoring `029:101-166` verbatim with `knowingly-broken` header caveat (mirror `063` down-file).
- [ ] 2.3 Run AC6/AC7 integration test → GREEN; confirm `reportSilentFallback` branch no longer fires.

## Phase 3 — Regression + types

- [ ] 3.1 `vitest run` over slots + ws-handler + agent-runner test set → green (AC8).
- [ ] 3.2 `tsc --noEmit` from `apps/web-platform/` → clean (AC9).
- [ ] 3.3 Confirm `concurrency.ts` / `ws-handler.ts` untouched (`git diff --stat`) (AC2).

## Phase 4 — Ship + post-merge verify

- [ ] 4.1 PR body: `Closes #<tracking-issue>`, link Sentry `52442f7a9b77462b9927b1f055204cce` + post-mig-059 learning.
- [ ] 4.2 Post-merge: migration applies via `web-platform-release.yml#migrate`; verify function body contains `workspace_id` via Supabase MCP (AC10).
- [ ] 4.3 Post-merge: confirm zero new `op:acquireSlot pg_code:23502` Sentry events post-deploy; close tracking issue (AC11).
