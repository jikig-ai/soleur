---
title: "fix: acquire_conversation_slot 23502 — RPC INSERT missing workspace_id after mig 059 NOT NULL"
type: fix
date: 2026-06-02
branch: feat-one-shot-concurrency-silent-fallback-acquireslot
lane: single-domain
status: planned
brand_survival_threshold: single-user incident
sentry_issue: 52442f7a9b77462b9927b1f055204cce
related_issues: [4342, 4356]
related_prs: [4343, 4356, 4225, 2617, 4229]
requires_cpo_signoff: true
---

# fix: `acquire_conversation_slot` 23502 — RPC INSERT missing `workspace_id` after mig 059 NOT NULL

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** Approach (materially revised), Acceptance Criteria, Files to Edit, Risks, Alternatives.
**Research agents used:** direct codebase precedent-diff (Phase 4.4), verify-the-negative pass (Phase 4.45), Phase 4.6/4.7/4.8 gates (all pass).

### Key Improvements (architecture correction — deepen-plan caught this; plan-review would not)

1. **CHANGED the fix shape from "pure-SQL solo-canary derivation" to "TS resolves the active workspace + widen RPC to a 4-arg `p_workspace_id`."** The original v1 derived `workspace_id = p_user_id` inside the RPC via the solo-canary `workspace_members` row. That is **correct only for solo users** — it mis-keys the slot for a user actively working inside a *shared/team* workspace. The slot's `workspace_id` MUST equal the workspace of the conversation it gates.
2. **Mirror the canonical conversation-insert pattern.** `createConversation` (`ws-handler.ts:808-819`) sets `workspace_id = getUserWorkspace(userId)` — the session-cached **active** workspace, resolved at session-open (`ws-handler.ts:2294` via `getWorkspaceForUserInOrganization` → `getDefaultWorkspaceForUser`). The slot acquire happens in the same handler with the same value in scope; `acquireSlot` must pass it through so `slot.workspace_id == conversation.workspace_id` (the equality `find_stuck_active_conversations` (`037:52-54`) and the RLS member-select (`059:227`) both assume).
3. **Adopt the exact migration-061 byok precedent** (`record_byok_use_and_check_cap` / `write_byok_audit` were widened to a `p_workspace_id` arg when their table got `workspace_id NOT NULL` in mig 055) rather than deriving inside the function. This is the established codebase convention for "table gained workspace_id NOT NULL; re-issue its writer RPC."

### New Considerations Discovered

- `resolveCurrentWorkspaceId` (`workspace-resolver.ts:190-218`, ADR-044) and the session cache `getUserWorkspace` (`ws-handler.ts:46`) both fail **closed to the solo workspace (`= userId`), never a sibling** — so the new arg can never cross-tenant a slot. The widened RPC inherits that safety from the caller.
- Widening the signature changes the grant target type list (`(uuid, uuid, integer)` → `(uuid, uuid, integer, uuid)`); the new migration MUST re-issue the `grant execute … to service_role` for the new signature (a `CREATE OR REPLACE` with a *different* arg list creates a NEW function overload, NOT a replacement — so old grants do not carry and a stale 3-arg overload could linger). See revised AC2 + Risks.

## 🐛 Summary

Production Sentry `concurrency silent fallback` (`feature=concurrency`, `op=acquireSlot`,
`pg_code=23502`) fires on **every new-conversation acquire** in `web-platform` production.

Root cause is a **NOT NULL ↔ SECURITY DEFINER RPC contract-pair break** (the exact class
documented in `knowledge-base/project/learnings/2026-05-22-tenant-integration-runtime-failures-post-mig-059.md`):

- Migration `059_workspace_keyed_rls_sweep.sql:206` adds `workspace_id uuid` to
  `public.user_concurrency_slots` **with no `DEFAULT`**, backfills it (lines 208–221), then
  `ALTER COLUMN workspace_id SET NOT NULL` at `059:223`.
- The only writer that INSERTs new rows into `user_concurrency_slots` is the
  `public.acquire_conversation_slot` RPC, defined **only** in
  `029_plan_tier_and_concurrency_slots.sql:101` and **never re-issued** after mig 059.
  Its INSERT (`029:133-137`) supplies only `(user_id, conversation_id)`:

  ```sql
  insert into public.user_concurrency_slots (user_id, conversation_id)
  values (p_user_id, p_conversation_id)
  on conflict (user_id, conversation_id)
    do update set last_heartbeat_at = now()
  returning (xmax = 0) into v_was_insert;
  ```

  `workspace_id` therefore falls to its (NULL) column default → the NOT NULL constraint
  from `059:223` rejects the INSERT with SQLSTATE **23502** (`not_null_violation`).

- The TS wrapper `apps/web-platform/server/concurrency.ts:102-109` catches the error,
  fires `reportSilentFallback(error, { feature: "concurrency", op: "acquireSlot", … })`
  (which tags `pg_code=23502` via `sqlStateFromError`, `observability.ts:197`), and returns
  `{ status: "error" }`. Per `ws-handler.ts:1501` an `"error"` status is treated **fail-closed**
  exactly like `cap_hit` — the WS is closed with `WS_CLOSE_CODES.CONCURRENCY_CAP`. **Every user
  attempting a brand-new conversation is silently denied** and shown the concurrency-cap modal.

The 2026-05-22 post-mig-059 sweep (PR #4343 / #4356) repaired the `conversations`, `messages`,
`grant_action_class`, and `anonymise_scope_grants` writers but **missed
`acquire_conversation_slot`** — its discovery grep was scoped to `INSERT INTO public.conversations`
and the tenant-isolation test file glob, neither of which reaches the slots-table RPC. This is the
**residual Class D** (the "conversations.workspace_id 23502" class) for the `user_concurrency_slots`
table.

**First-seen June 2, 2026 09:49 CEST** is consistent with the first production user whose
`acquireSlot` hit the *new-row* INSERT path post-deploy (the `on conflict do update` branch for an
*existing* slot does not touch `workspace_id`, so users with a pre-existing slot row were masked
until they started a genuinely new conversation).

## Why the existing self-heal / retry machinery does NOT mask this

- `TRANSIENT_SQLSTATES` (`concurrency.ts:61`) = `{40P01, 55P03}` only. `23502` is **not** transient,
  so the retry loop does not retry — it goes straight to `reportSilentFallback` + `return error`
  on the first attempt.
- `tryLedgerDivergenceRecovery` (`ws-handler.ts:1493`) only runs on `status === "cap_hit"`, not
  `"error"`, so it never fires for this failure.
- The Stripe webhook-lag re-acquire (`ws-handler.ts:1447-1484`) also gates on `cap_hit`. None of
  the three recovery paths touch the `"error"` branch.

## User-Brand Impact

**If this lands broken, the user experiences:** every attempt to start a *new* conversation in the
Command Center is silently denied with the "Concurrent-conversation limit reached" upgrade modal —
even on a fresh account with zero active conversations. The product is unusable for new-conversation
flows; the user has no signal that this is a bug, not a paywall.

**If this leaks, the user's workflow is exposed via:** N/A — no data exposure. This is an
availability/correctness fault: the cap gate fails closed and blocks legitimate work. (`workspace_id`
is the user's own solo-workspace id, never cross-tenant.)

**Brand-survival threshold:** `single-user incident`. A single new user hitting an unconditional
"limit reached" wall on first use is a first-impression brand failure; the fix touches a
SECURITY DEFINER RPC and a NOT NULL invariant where a wrong `workspace_id` derivation would be a
tenant-isolation concern. CPO sign-off required at plan time (frontmatter `requires_cpo_signoff`
carried via threshold); `user-impact-reviewer` runs at review time.

## Research Reconciliation — Spec vs. Codebase

| Hypothesis (from issue) | Reality (verified in repo) | Plan response |
| --- | --- | --- |
| "acquireSlot inserts a row where a NOT NULL column receives null" | Correct. The null column is **`workspace_id`** (added NOT NULL in mig `059:223`, no default), not `user_id`/`conversation_id` (both supplied non-null by the RPC). | Re-issue the RPC to populate `workspace_id`. |
| "find which column is null, fix the upstream value" | The null is `workspace_id`, which the RPC never populated. The correct value is the user's **active** workspace (`getUserWorkspace(userId)`, the session cache set at `ws-handler.ts:2294`) — the same value `createConversation` writes to the conversation row (`ws-handler.ts:808-819`). | **Revised (deepen-plan):** resolve `workspace_id` in TS at the call site and pass it to a **widened 4-arg RPC** (`p_workspace_id uuid`), mirroring the mig-061 byok precedent and the conversation-insert pattern. The fix touches `concurrency.ts`, the two `acquireSlot` call sites in `ws-handler.ts`, AND a new migration. |
| (v1 alternative) derive `workspace_id` inside the RPC via solo-canary | **Incorrect for team workspaces:** `workspace_members WHERE workspace_id = user_id` always resolves the *solo* workspace, so a member acting inside a shared workspace would get a slot keyed to their personal workspace — diverging from the conversation's `workspace_id` and the reaper's join. | Rejected in favor of caller-supplied active workspace (see Alternatives). Solo derivation is a *fallback* only, already provided by `resolveCurrentWorkspaceId`/`getUserWorkspace` failing closed to `userId`. |
| "ensure the fallback no longer fires for this case" | The `reportSilentFallback` mirror in `concurrency.ts` is **correct as designed** (per `cq-silent-fallback-must-mirror-to-sentry`) — it should stay. Once the RPC populates `workspace_id`, the 23502 stops and the fallback stops firing naturally. | Do **not** remove the fallback; verify it no longer fires via the integration test. |
| `acquire_conversation_slot` re-issued in a later migration? | **No.** Only defined in `029:101`; `git grep "function public.acquire_conversation_slot"` returns only 029. | New migration `093` is the first re-issue (DROP old 3-arg + CREATE 4-arg). |
| `touch_conversation_slot` / `release_conversation_slot` also broken? | **No.** `touch` is an UPDATE (`029:185`), `release` is a DELETE (`029:201`) — neither writes `workspace_id`, so neither violates the NOT NULL. | Out of scope; leave both unchanged. |
| Is `getUserWorkspace(userId)` in scope at the `acquireSlot` call sites? | **Yes.** Set at session-open (`ws-handler.ts:2294`, `setUserWorkspace`) before any `start_session` handler runs; `createConversation` already reads it at `ws-handler.ts:808`. Both `acquireSlot` calls (`1445`, `1497`) are in the same `start_session` handler. | Pass `getUserWorkspace(userId)` through `acquireSlot` to the RPC. Fail loud if absent (mirrors `createConversation:809-812`). |
| Does signature widening need a DROP? | **Yes.** Per mig-061 precedent (`061:37,79`), a different arg list under `CREATE OR REPLACE` makes a NEW overload and leaves the old function + its grant in place. | Migration does `DROP FUNCTION IF EXISTS …(uuid,uuid,integer)` then `CREATE FUNCTION …(uuid,uuid,integer,uuid)` + re-grant. |

## 📋 Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — RPC re-issued with 4-arg signature.** A new migration
  `apps/web-platform/supabase/migrations/093_acquire_slot_workspace_id.sql` does
  `DROP FUNCTION IF EXISTS public.acquire_conversation_slot(uuid, uuid, integer);` then
  `CREATE FUNCTION public.acquire_conversation_slot(p_user_id uuid, p_conversation_id uuid,
  p_effective_cap integer, p_workspace_id uuid)` whose INSERT column list includes `workspace_id`
  with value `p_workspace_id`. Verify:
  `grep -cE "drop function if exists public.acquire_conversation_slot|p_workspace_id" apps/web-platform/supabase/migrations/093_acquire_slot_workspace_id.sql` ≥ 3.
- [ ] **AC2 — grants re-issued for new signature.** Because the arg list changed, the migration
  re-issues `revoke all on function public.acquire_conversation_slot(uuid, uuid, integer, uuid) from public;`
  and `grant execute on function public.acquire_conversation_slot(uuid, uuid, integer, uuid) to service_role;`
  (mirrors `029:205-210` for the new signature, and the mig-061 DROP+CREATE+grant pattern). No stale
  3-arg overload remains (the DROP removes it). Verify both `grant execute` and `(uuid, uuid, integer, uuid)`
  appear in the migration.
- [ ] **AC3 — caller supplies the active workspace; fail-loud on absent.** `concurrency.ts` `acquireSlot`
  gains a `workspaceId: string` parameter and passes `p_workspace_id: workspaceId` in the RPC call.
  **All THREE** call sites in `ws-handler.ts` pass `getUserWorkspace(userId)`: `1445` (initial),
  `1479` (Stripe webhook-lag retry), `1497` (ledger-divergence retry). Resolve `getUserWorkspace(userId)`
  once at the top of the `start_session` acquire block; if null, abort the acquire via the existing
  "No workspace binding for user" error path (mirrors `createConversation:809-812`) rather than passing
  null (which would re-trigger 23502). Verify `concurrency.ts` contains `p_workspace_id`, the
  `acquireSlot` signature includes a workspace param, and all 3 `ws-handler.ts` call sites pass the
  resolved workspace id: `git grep -c "acquireSlot(" apps/web-platform/server/ws-handler.ts` = 3, none
  passing only 3 args.
- [ ] **AC4 — `search_path` + SECURITY DEFINER pinned.** Re-issued function retains
  `language plpgsql security definer set search_path = public, pg_temp` per
  `cq-pg-security-definer-search-path-pin-pg-temp`. Verify the body contains
  `set search_path = public, pg_temp`.
- [ ] **AC5 — down migration with knowingly-broken caveat.** `093_acquire_slot_workspace_id.down.sql`
  does `DROP FUNCTION IF EXISTS public.acquire_conversation_slot(uuid, uuid, integer, uuid);` then
  restores the verbatim 3-arg `029:101-166` body + its `029:205,208` grants, and documents in its
  header that applying the down WHILE the `059:223` NOT NULL is in place leaves a knowingly-broken
  state (acquire fails 23502) — mirrors the `063_post_workspace_rpc_repair.down.sql` convention.
  Verify header contains the substring `knowingly-broken`.
- [ ] **AC6 — integration test (RED→GREEN).** A new test
  `apps/web-platform/test/concurrency-acquire-slot-workspace-id.integration.test.ts` calls the RPC
  (post-fix 4-arg form) for a synthesized solo user with a fresh conversation id, passing
  `p_workspace_id = userId` (solo N2), and asserts `status = 'ok'` AND the persisted
  `user_concurrency_slots` row has `workspace_id = userId`. **Add a second case** that passes a
  distinct `p_workspace_id` (a synthesized non-solo workspace the user owns) and asserts the slot row
  carries THAT workspace_id — proving the slot tracks the active workspace, not a hardcoded solo value.
  Written first against the pre-fix RPC to confirm it reproduces 23502 (per `cq-write-failing-tests-before`),
  then passes after the migration. Runner: vitest (`test/**/*.test.ts` per `vitest.config.ts:44`).
  Verify with
  `./node_modules/.bin/vitest run test/concurrency-acquire-slot-workspace-id.integration.test.ts` from
  `apps/web-platform/`.
- [ ] **AC7 — fallback no-fire assertion.** AC6's GREEN run, executed against the real dev-Supabase
  schema, returns `status = 'ok'` (not `error`) — proving the `reportSilentFallback` branch in
  `concurrency.ts:102` no longer fires for the new-acquire path. The `reportSilentFallback` call itself
  is **not removed** (it correctly guards the genuine-error path per `cq-silent-fallback-must-mirror-to-sentry`).
- [ ] **AC8 — direct-RPC-caller test updated (contract-pair sweep).** `conversation-archive-release-slot.integration.test.ts`
  defines a **local** `acquireSlot` helper (`:130-147`) that calls the RPC **directly** with the
  **3-arg** form. After the migration DROPs the 3-arg overload, this call breaks (PGRST202 /
  function-not-found). It MUST be updated to pass `p_workspace_id: user.id`. This is the exact
  contract-pair sweep the post-mig-059 learning mandates — grep every direct RPC caller:
  `git grep -n 'rpc("acquire_conversation_slot"' apps/web-platform` and update each. The
  `ws-handler-cap-hit-self-heal` / `agent-runner-*` suites mock the TS `acquireSlot` wrapper via
  `vi.fn()` (return-value mocks, no arity assertions found via
  `git grep "acquireSlot).toHaveBeenCalledWith"` → 0 hits) so they are unaffected by the wrapper's new
  param — but re-run them to confirm. Verify `vitest run` over the slots + ws-handler + agent-runner
  test set is green.
- [ ] **AC9 — `tsc --noEmit` clean** for `apps/web-platform` after the `acquireSlot` signature change
  and both `ws-handler.ts` call-site updates. The widened param is a *required* positional arg, so
  `tsc` will flag any call site not updated — this is the compiler enumerating the call sites for us
  (3 known: `concurrency.ts:83` internal + `ws-handler.ts:1445,1497`; plus the `1479` retry call).
  Run from `apps/web-platform/`: `./node_modules/.bin/tsc --noEmit`.

### Post-merge (operator)

- [ ] **AC10 — migration applied to prd.** Migration `093` is applied via the existing
  `web-platform-release.yml#migrate` job on merge to `main` (path-filtered on
  `apps/web-platform/**`). **Automation: feasible** — the release pipeline already runs migrations;
  no separate operator apply step. Verify post-deploy via the Supabase MCP (read-only): introspect
  `pg_proc` for `acquire_conversation_slot` and assert exactly ONE overload remains, with arg types
  `(uuid, uuid, integer, uuid)` (the 4-arg form) and NO lingering 3-arg `(uuid, uuid, integer)`
  overload, AND the function body (`pg_get_functiondef`) contains `workspace_id`.
- [ ] **AC11 — Sentry issue resolved.** After deploy, confirm Sentry issue
  `52442f7a9b77462b9927b1f055204cce` (`pg_code:23502 op:acquireSlot`) stops receiving new events for
  the new-acquire path. **Automation: feasible** — query Sentry events API for the issue filtered to
  `release >= <deploy release>`; expect zero new `op:acquireSlot pg_code:23502` events. Close the
  tracking issue with `gh issue close` once confirmed. Use `Ref #<N>` in the PR body (the actual fix
  lands at merge via the migrate job, so `Closes` is acceptable here since the migration applies
  synchronously in the release pipeline; if the team prefers ops-remediation semantics use `Ref`).

## 🛠 Implementation Phases

### Phase 0 — Preconditions (verify, no code)

- [ ] Confirm latest migration number is `092` (next is `093`):
  `ls apps/web-platform/supabase/migrations/*.sql | sed -E 's#.*/([0-9]+)_.*#\1#' | sort -n | tail -1`.
- [ ] Re-read `029_plan_tier_and_concurrency_slots.sql:101-166` (the canonical body to base the
  re-issue on) and `059_workspace_keyed_rls_sweep.sql:205-229` (the column/NOT NULL/RLS it added).
- [ ] Read the precedent re-issue `061_byok_audit_workspace_id_rpcs.sql` — note it uses
  **`DROP FUNCTION IF EXISTS …(old-sig)` + `CREATE`** (lines 37, 79), NOT `CREATE OR REPLACE`, because
  the arg list changes — and the down-file convention in `063_post_workspace_rpc_repair.down.sql`
  (knowingly-broken caveat).
- [ ] Read the canonical workspace resolution: `workspace-resolver.ts:190-218` (`resolveCurrentWorkspaceId`,
  fails closed to `userId`, never a sibling) and the session cache `getUserWorkspace`/`setUserWorkspace`
  (`ws-handler.ts:46,2294`). Confirm `createConversation:808-819` reads `getUserWorkspace(userId)` as
  the conversation's `workspace_id` — the slot must use the same value.
- [ ] **Live read-only repro (per Sharp Edge "write-path internally-consistent claim"):**
  against dev-Supabase via the Supabase MCP, run
  `BEGIN; SELECT public.acquire_conversation_slot('<seed-user>'::uuid, gen_random_uuid(), 5); ROLLBACK;`
  for a seeded solo user and capture the actual SQLSTATE — expect `23502` on column `workspace_id`.
  This confirms the failing column before writing the fix. (DEV only — never prod, per
  `hr-dev-prd-distinct-supabase-projects`.)

### Phase 1 — Write the failing test (RED)

- [ ] Create `apps/web-platform/test/concurrency-acquire-slot-workspace-id.integration.test.ts`
  modeled on `conversation-archive-release-slot.integration.test.ts` (same dev-Supabase service-client
  harness). Synthesize a solo user (which gets the `handle_new_user` solo-workspace backfill). RED
  baseline: call the **pre-fix 3-arg** RPC `acquire_conversation_slot(userId, randomUUID(), 5)` and
  confirm it fails with raw RPC error SQLSTATE `23502` on `workspace_id`. After Phase 2, switch the
  call to the 4-arg form and assert (a) `status='ok'` + persisted `workspace_id = userId` for the
  solo case, and (b) for a distinct owned non-solo workspace, the slot row carries THAT workspace_id
  (AC6 case 2). RED gate per `cq-write-failing-tests-before`.

### Phase 2 — Re-issue the RPC (4-arg, GREEN)

- [ ] Create `apps/web-platform/supabase/migrations/093_acquire_slot_workspace_id.sql`:
  1. `DROP FUNCTION IF EXISTS public.acquire_conversation_slot(uuid, uuid, integer);` (per mig-061
     pattern — the arg list changes, so this is a new function, not a replacement).
  2. `CREATE FUNCTION public.acquire_conversation_slot(p_user_id uuid, p_conversation_id uuid,
     p_effective_cap integer, p_workspace_id uuid)` — body = verbatim copy of `029:101-166` with one
     change: add `workspace_id` to the INSERT column list + value `p_workspace_id`:
     ```sql
     insert into public.user_concurrency_slots (user_id, conversation_id, workspace_id)
     values (p_user_id, p_conversation_id, p_workspace_id)
     on conflict (user_id, conversation_id)
       do update set last_heartbeat_at = now()
     returning (xmax = 0) into v_was_insert;
     ```
     Keep `language plpgsql security definer set search_path = public, pg_temp`, the advisory lock,
     the lazy sweep, the cap-check, and the return shape all **verbatim** from 029. Do NOT add
     `workspace_id` to the `do update set` clause (the existing row keeps its backfilled value).
  3. `revoke all on function public.acquire_conversation_slot(uuid, uuid, integer, uuid) from public;`
     + `grant execute on function public.acquire_conversation_slot(uuid, uuid, integer, uuid) to service_role;`
     (mirror `029:205,208` for the new signature).
- [ ] Header in the FORWARD-ONLY + `cq-pg-security-definer-search-path-pin-pg-temp` style of
  029/059/061/063. Cite the root cause (mig 059 NOT NULL + un-re-issued writer) and the post-mig-059
  learning file.
- [ ] Create `093_acquire_slot_workspace_id.down.sql`:
  `DROP FUNCTION IF EXISTS public.acquire_conversation_slot(uuid, uuid, integer, uuid);` then restore
  the verbatim 3-arg `029:101-166` body + its `029:205,208` grants; header caveat copied in spirit
  from `063_post_workspace_rpc_repair.down.sql` (down re-introduces the 23502 while `059:223` stands —
  controlled rollback only).

### Phase 3 — TS call sites (GREEN)

- [ ] `concurrency.ts`: add `workspaceId: string` param to `acquireSlot(userId, conversationId,
  effectiveCap, workspaceId)` and pass `p_workspace_id: workspaceId` in the `supabase.rpc(...)` call
  (`:83-87`). `touchSlot`/`releaseSlot` unchanged (they don't write `workspace_id`).
- [ ] `ws-handler.ts`: resolve `const slotWorkspaceId = getUserWorkspace(userId)` once at the top of the
  `start_session` acquire block; if null, abort via the existing "No workspace binding for user" error
  path. Pass `slotWorkspaceId` to all THREE `acquireSlot(...)` calls (`1445`, `1479`, `1497`).
- [ ] Update the direct-RPC test caller in `conversation-archive-release-slot.integration.test.ts:130-147`
  to pass `p_workspace_id: user.id` (AC8 contract-pair sweep). Grep
  `git grep -n 'rpc("acquire_conversation_slot"' apps/web-platform` → 2 hits (concurrency.ts +
  this test); both updated.
- [ ] Run AC6/AC7 integration test → GREEN.

### Phase 4 — Regression + type gates

- [ ] `./node_modules/.bin/tsc --noEmit` from `apps/web-platform/` → clean. The new required param means
  `tsc` flags every un-updated `acquireSlot` call — use that as the call-site enumerator (AC9).
- [ ] Run the slots + ws-handler + agent-runner test set → green (AC8).

### Phase 5 — Ship

- [ ] PR body uses `Closes #<tracking-issue>` (migration applies synchronously in
  `web-platform-release.yml#migrate` on merge — see `wg-use-closes-n-in-pr-body-not-title-to`). Link
  Sentry issue `52442f7a9b77462b9927b1f055204cce` and the post-mig-059 learning.
- [ ] Post-merge: verify AC10 (4-arg function body contains `workspace_id` via Supabase MCP
  introspection; no stale 3-arg overload) and AC11 (Sentry no-fire).

## 🔍 Hypotheses (ruled in / out)

- ✅ **`workspace_id` NOT NULL violation** (mig 059 + un-re-issued RPC) — **confirmed root cause**.
- ❌ `user_id` null → would fail at `pg_advisory_xact_lock(hashtextextended(p_user_id::text,0))`
  (`029:125`) with a null-argument error (not 23502), and both callers pass non-null `userId`.
- ❌ `conversation_id` null → both callers pass `randomUUID()` (`ws-handler.ts:1438`), never null.
- ❌ `p_effective_cap` null → `effectiveCap` (`plan-limits.ts:31`) always returns a number; and it is
  never an inserted column.
- ❌ A DB trigger inserting elsewhere → no INSERT/UPDATE trigger exists on `user_concurrency_slots`
  (`release_slot_on_archive` in mig 036 fires on `conversations` and only DELETEs a slot).

## ⚠️ Risks & Sharp Edges

- **Precedent-diff (Phase 4.4) — SECURITY DEFINER RPC signature widening:** the established codebase
  pattern for "table gained `workspace_id NOT NULL`; re-issue its writer RPC" is mig 061
  (`record_byok_use_and_check_cap`, `write_byok_audit`): **`DROP FUNCTION IF EXISTS …(old-sig)` +
  `CREATE` with the new `p_workspace_id` arg + re-grant** (`061:37,79`). This plan mirrors it exactly.
  Do NOT use `CREATE OR REPLACE` — a changed arg list creates a NEW overload and leaves a stale 3-arg
  function (with its grant) in place; the DROP is load-bearing.
- **`on conflict do update` path is unaffected** — it does not touch `workspace_id`, so existing rows
  keep their backfilled value. Only the new-row INSERT branch needed the fix; do NOT add
  `workspace_id` to the `do update set` clause (would risk overwriting a valid backfilled value).
- **Slot workspace_id MUST equal the conversation's workspace_id.** `createConversation` writes
  `workspace_id = getUserWorkspace(userId)` (`ws-handler.ts:808-819`); the slot acquire MUST use the
  same value so `find_stuck_active_conversations`'s join (`037:52-54`) and the RLS member-select
  (`059:227`) line up. Passing a *different* workspace (e.g., a hardcoded solo id while the conversation
  is in a team workspace) would make the reaper unable to match slot↔conversation and could hide the
  slot from the workspace's member-select. This is precisely why the caller-supplied value (not an
  in-RPC solo derivation) is correct.
- **`getUserWorkspace` / `resolveCurrentWorkspaceId` fail closed to `userId`, never a sibling**
  (`workspace-resolver.ts:215,217`). So the new `p_workspace_id` arg cannot cross-tenant a slot even
  on a stale/absent session claim — the worst case degrades to the solo workspace, identical to v1's
  derivation. The RPC trusts the caller because the caller is server-side WS code with the session
  cache, and the RPC is SECURITY DEFINER reachable only by `service_role` (AC2 grant).
- **Do NOT remove the `reportSilentFallback` mirror** in `concurrency.ts` — it is the correct,
  rule-mandated observability for the genuine-error path (`cq-silent-fallback-must-mirror-to-sentry`).
  The fix is to stop *causing* the error, not to silence its reporting.
- **Empty `## User-Brand Impact` would fail `deepen-plan` Phase 4.6** — section is filled above with a
  concrete artifact, exposure note, and `single-user incident` threshold.
- **Migration is non-transactional-safe:** the body is `DROP FUNCTION` + `CREATE FUNCTION` + grants —
  no `CREATE INDEX CONCURRENTLY`/`VACUUM`/`ALTER SYSTEM`, so it runs cleanly inside Supabase's
  per-migration transaction wrapper (per the 029/025/027 CONCURRENTLY caveat).
- **Phase order is load-bearing** (`2026-05-10-plan-phase-order-load-bearing-when-contract-changes`):
  Phase 2 (RPC contract: new 4-arg signature) MUST land before Phase 3 (TS callers passing the 4th
  arg). The whole PR merges atomically, but `/work` executes phases sequentially — a Phase-3 caller
  built against a not-yet-existing 4-arg overload is dead/failing until Phase 2.

## 🗂 Files to Edit

- `apps/web-platform/server/concurrency.ts` — add `workspaceId` param to `acquireSlot`; pass
  `p_workspace_id` in the RPC call. (`touchSlot`/`releaseSlot` unchanged.)
- `apps/web-platform/server/ws-handler.ts` — resolve `getUserWorkspace(userId)` once in the
  `start_session` acquire block (fail-loud if null) and pass it to all 3 `acquireSlot` calls
  (`1445`, `1479`, `1497`).
- `apps/web-platform/test/conversation-archive-release-slot.integration.test.ts` — update the local
  direct-RPC `acquireSlot` helper (`:130-147`) to pass `p_workspace_id: user.id` (contract-pair sweep,
  AC8).

## 🆕 Files to Create

- `apps/web-platform/supabase/migrations/093_acquire_slot_workspace_id.sql`
- `apps/web-platform/supabase/migrations/093_acquire_slot_workspace_id.down.sql`
- `apps/web-platform/test/concurrency-acquire-slot-workspace-id.integration.test.ts`

## Open Code-Review Overlap

None — no open `code-review` issue touches these files (new migration + new test; the SQL writer was
missed by the #4343/#4356 sweep, which filed no scope-out for the slots table).

## Domain Review

**Domains relevant:** Product (availability/first-impression), Engineering (DB contract-pair).

This is an infrastructure/correctness fix (a missing column on a SECURITY DEFINER RPC INSERT, plus the
TS callers that supply it). No new user-facing surface, no new UI component, no new flow — the fix
*restores* the existing new-conversation flow that mig 059 silently broke. Product/UX Gate tier:
**NONE** (no new
user-facing page/flow/component; mechanical-escalation file scan finds no `components/**/*.tsx` /
`app/**/page.tsx` in Files to Create). CPO sign-off is required at plan time per the
`single-user incident` threshold (frontmatter), not because of a new UI surface.

## Infrastructure (IaC)

Skipped — no new server, secret, vendor, cron, DNS, or persistent runtime process. Pure schema change
applied through the existing `web-platform-release.yml#migrate` pipeline.

## Observability

```yaml
liveness_signal:
  what: Sentry issue 52442f7a9b77462b9927b1f055204cce stops receiving events
  cadence: per-acquire (every new-conversation start_session)
  alert_target: existing Sentry alert routing for level:error feature:concurrency
  configured_in: apps/web-platform/server/observability.ts reportSilentFallback (pg_code tag)
error_reporting:
  destination: Sentry (captureException with tags feature/op/pg_code) + pino mirror to container stdout/Better Stack
  fail_loud: true  # the silent-fallback mirror IS the loud signal; it correctly fired for this bug
failure_modes:
  - mode: workspace_id NOT NULL violation on acquire INSERT (this bug)
    detection: Sentry pg_code:23502 op:acquireSlot
    alert_route: Sentry level:error feature:concurrency
  - mode: getUserWorkspace(userId) null at acquire call site (post-fix fail-loud abort)
    detection: Sentry "No workspace binding for user" op:acquireSlot (TS-side, no pg_code)
    alert_route: same Sentry routing feature:concurrency — abort BEFORE the RPC, so never a NULL INSERT
  - mode: PostgREST RPC timeout returning {data:null,error:null}
    detection: concurrency.ts:115 "exhausted 3 retries" captureMessage
    alert_route: Sentry level:error feature:concurrency
logs:
  where: Sentry (queryable pg_code tag) + pino structured logs (Better Stack)
  retention: per existing Sentry + Better Stack retention
discoverability_test:
  command: "gh api -X GET /api/0/issues/52442f7a9b77462b9927b1f055204cce/events/ (or Sentry MCP) filtered to release >= deploy; expect zero new op:acquireSlot pg_code:23502 events post-deploy"
  expected_output: "0 new events for the new-acquire 23502 path"
```

## Alternative Approaches Considered

| Approach | Verdict |
| --- | --- |
| **CHOSEN: caller supplies `p_workspace_id` (4-arg RPC), resolved from `getUserWorkspace(userId)`** | Mirrors the conversation-insert pattern (`ws-handler.ts:808-819`) and the mig-061 byok precedent. The slot tracks the *active* workspace, identical to the conversation it gates. Correct for both solo and team workspaces today; no Future Work deferral needed. |
| Derive `workspace_id = p_user_id` (or solo-canary `workspace_members`) **inside** the RPC (v1) | **Rejected.** Correct only for solo users — a member acting in a shared workspace would get a slot keyed to their personal workspace, diverging from the conversation's `workspace_id`, breaking the reaper join (`037:52-54`) and the RLS member-select (`059:227`). The deepen-plan precedent-diff (Phase 4.4) surfaced the conversation-insert pattern that makes the caller-supplied value the correct source. |
| Add a `DEFAULT` to `workspace_id` in a new ALTER | Wrong: there is no sensible table-level default for a per-request workspace id; the value is request-scoped (the acquiring user's *active* workspace). |
| Make `workspace_id` nullable again | Reverts a deliberate tenant-isolation invariant from mig 059; unacceptable. |

## Future Work

- None required for correctness. The 4-arg RPC already handles solo and team workspaces. If a future
  flow needs to acquire a slot for a workspace the caller is not actively in, add an explicit
  membership check inside the RPC (it is SECURITY DEFINER and can read `workspace_members` without
  RLS) — but no such flow exists today, so this is not deferred work, just a note.
