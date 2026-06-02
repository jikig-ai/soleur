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
related_prs: [4343, 4356, 4225, 2617]
---

# fix: `acquire_conversation_slot` 23502 — RPC INSERT missing `workspace_id` after mig 059 NOT NULL

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

## 🎯 User-Brand Impact

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
| "find which column is null, fix the upstream value" | The upstream value is **not** a TS argument — both `acquireSlot` callers pass non-null `userId` + `pendingId=randomUUID()` (`ws-handler.ts:1445/1497`). The gap is **in the RPC body**, which never learned about the column mig 059 added. | Fix lives in a new migration that re-issues `acquire_conversation_slot`, not in `concurrency.ts`. |
| "ensure the fallback no longer fires for this case" | The `reportSilentFallback` mirror in `concurrency.ts` is **correct as designed** (per `cq-silent-fallback-must-mirror-to-sentry`) — it should stay. Once the RPC populates `workspace_id`, the 23502 stops and the fallback stops firing naturally. | Do **not** remove the fallback; verify it no longer fires via the integration test. |
| `acquire_conversation_slot` re-issued in a later migration? | **No.** Only defined in `029:101`; `git grep "function public.acquire_conversation_slot"` returns only 029. | New migration `093` is the first re-issue. |
| `touch_conversation_slot` / `release_conversation_slot` also broken? | **No.** `touch` is an UPDATE (`029:185`), `release` is a DELETE (`029:201`) — neither writes `workspace_id`, so neither violates the NOT NULL. | Out of scope; leave both unchanged. |

## 📋 Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — RPC re-issued.** A new migration `apps/web-platform/supabase/migrations/093_acquire_slot_workspace_id.sql`
  contains exactly one `create or replace function public.acquire_conversation_slot(uuid, uuid, integer)`
  whose INSERT column list includes `workspace_id`. Verify:
  `grep -c "workspace_id" apps/web-platform/supabase/migrations/093_acquire_slot_workspace_id.sql` ≥ 2
  (one in the resolution SELECT/derivation, one in the INSERT column list).
- [ ] **AC2 — Signature + grants preserved.** The re-issued function keeps the **same 3-arg signature**
  `(p_user_id uuid, p_conversation_id uuid, p_effective_cap integer)` and the same
  `returns table (status text, active_count integer, effective_cap integer)`. No `revoke`/`grant`
  churn needed (CREATE OR REPLACE preserves existing ACLs); if the body changes the arg list the
  existing grants at `029:205-210` break — so the arg list MUST be byte-identical. Verify the TS
  caller `concurrency.ts:83-87` is **unchanged** (still passes 3 params): `git diff --stat` shows no
  change to `concurrency.ts`.
- [ ] **AC3 — `workspace_id` derived via solo-canary, fail-loud on miss.** The RPC resolves
  `v_workspace_id` from `public.workspace_members WHERE user_id = p_user_id AND workspace_id = p_user_id
  AND role = 'owner'` (the permanent solo-backfill row guaranteed by `handle_new_user`, mig
  `053:208-210`). If no row is found, `RAISE EXCEPTION` with a clear message rather than INSERTing NULL
  (a NULL would re-trigger 23502 anyway; an explicit raise gives a queryable error). Verify the body
  contains `workspace_members` and `role = 'owner'`.
- [ ] **AC4 — `search_path` + SECURITY DEFINER pinned.** Re-issued function retains
  `language plpgsql security definer set search_path = public, pg_temp` per
  `cq-pg-security-definer-search-path-pin-pg-temp`. Verify the body contains
  `set search_path = public, pg_temp`.
- [ ] **AC5 — down migration with knowingly-broken caveat.** `093_acquire_slot_workspace_id.down.sql`
  restores the verbatim `029:101-166` body and documents in its header that applying the down WHILE
  the `059:223` NOT NULL is in place leaves a knowingly-broken state (acquire fails 23502) — mirrors
  the `063_post_workspace_rpc_repair.down.sql` convention. Verify header contains the substring
  `knowingly-broken`.
- [ ] **AC6 — integration test (RED→GREEN).** A new test
  `apps/web-platform/test/concurrency-acquire-slot-workspace-id.integration.test.ts` calls the RPC for
  a synthesized solo user with a fresh conversation id and asserts the returned `status = 'ok'` AND
  that the persisted `user_concurrency_slots` row has `workspace_id = userId`. Written first against
  the pre-fix RPC to confirm it reproduces 23502 (per `cq-write-failing-tests-before`), then passes
  after the migration. Runner: vitest (`test/**/*.test.ts` per `vitest.config.ts:44`). Verify with
  `./node_modules/.bin/vitest run test/concurrency-acquire-slot-workspace-id.integration.test.ts` from
  `apps/web-platform/`.
- [ ] **AC7 — fallback no-fire assertion.** AC6's GREEN run, executed against the real dev-Supabase
  schema, returns `status = 'ok'` (not `error`) — proving the `reportSilentFallback` branch in
  `concurrency.ts:102` no longer fires for the new-acquire path. The `reportSilentFallback` call itself
  is **not removed** (it correctly guards the genuine-error path per `cq-silent-fallback-must-mirror-to-sentry`).
- [ ] **AC8 — existing slot tests still pass.** `conversation-archive-release-slot.integration.test.ts`
  and the `ws-handler-cap-hit-self-heal` / `agent-runner-*` suites that mock `acquireSlot` are
  unaffected (they mock the TS wrapper, whose signature is unchanged). Verify `vitest run` over the
  slots + ws-handler test set is green.
- [ ] **AC9 — `tsc --noEmit` clean** for `apps/web-platform` (no TS changes expected, but the gate
  confirms no accidental drift). Run from `apps/web-platform/`: `./node_modules/.bin/tsc --noEmit`.

### Post-merge (operator)

- [ ] **AC10 — migration applied to prd.** Migration `093` is applied via the existing
  `web-platform-release.yml#migrate` job on merge to `main` (path-filtered on
  `apps/web-platform/**`). **Automation: feasible** — the release pipeline already runs migrations;
  no separate operator apply step. Verify post-deploy via the Supabase MCP (read-only):
  `select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='acquire_conversation_slot'` returns 1, AND introspect the function body contains `workspace_id`.
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
- [ ] Read the precedent re-issue `061_byok_audit_workspace_id_rpcs.sql` and the down-file convention
  in `063_post_workspace_rpc_repair.down.sql` (knowingly-broken caveat).
- [ ] Confirm the solo-canary invariant in `053_organizations_and_workspace_members.sql:184-210`
  (`handle_new_user` provisions one permanent `workspace_members(workspace_id=u.id, user_id=u.id,
  role='owner')` per user).
- [ ] **Live read-only repro (recommended, per Sharp Edge "write-path internally-consistent claim"):**
  against dev-Supabase via the Supabase MCP, run
  `BEGIN; SELECT public.acquire_conversation_slot('<seed-user>'::uuid, gen_random_uuid(), 5); ROLLBACK;`
  for a seeded solo user and capture the actual SQLSTATE — expect `23502` on column `workspace_id`.
  This confirms the failing column before writing the fix. (DEV only — never prod, per
  `hr-dev-prd-distinct-supabase-projects`.)

### Phase 1 — Write the failing test (RED)

- [ ] Create `apps/web-platform/test/concurrency-acquire-slot-workspace-id.integration.test.ts`
  modeled on `conversation-archive-release-slot.integration.test.ts` (same dev-Supabase service-client
  harness). Synthesize a solo user (which gets the `handle_new_user` solo-workspace backfill), call
  `acquire_conversation_slot(userId, randomUUID(), 5)`, assert `status = 'ok'` and the persisted row's
  `workspace_id = userId`. Run it against the **pre-fix** RPC and confirm it fails with the 23502
  symptom (status `error` from the wrapper, or raw RPC error in the direct-RPC test). This is the
  RED gate per `cq-write-failing-tests-before`.

### Phase 2 — Re-issue the RPC (GREEN)

- [ ] Create `apps/web-platform/supabase/migrations/093_acquire_slot_workspace_id.sql`. Body = verbatim
  copy of `029:101-166` with two changes:
  1. Add a `v_workspace_id uuid;` declare + a resolution SELECT immediately after the advisory lock:
     ```sql
     select workspace_id into v_workspace_id
       from public.workspace_members
      where user_id = p_user_id
        and workspace_id = p_user_id
        and role = 'owner';
     if v_workspace_id is null then
       raise exception 'acquire_conversation_slot: no solo workspace for user %', p_user_id
         using errcode = 'P0001';
     end if;
     ```
     (Resolving via `workspace_members` rather than hardcoding `p_user_id` keeps the derivation
     correct if multi-workspace support later widens the RPC to accept an explicit `p_workspace_id`;
     for the solo case the resolved value equals `p_user_id`, matching the `059:215-216` backfill.)
  2. Add `workspace_id` to the INSERT column list + value:
     ```sql
     insert into public.user_concurrency_slots (user_id, conversation_id, workspace_id)
     values (p_user_id, p_conversation_id, v_workspace_id)
     on conflict (user_id, conversation_id)
       do update set last_heartbeat_at = now()
     returning (xmax = 0) into v_was_insert;
     ```
- [ ] Keep the file header in the FORWARD-ONLY + `cq-pg-security-definer-search-path-pin-pg-temp`
  documentation style of migrations 029/059/063. Cite the root cause (mig 059 NOT NULL + this PR's
  re-issue) and the learning file.
- [ ] Create `093_acquire_slot_workspace_id.down.sql` restoring the `029:101-166` body verbatim, with
  a header caveat copied in spirit from `063_post_workspace_rpc_repair.down.sql` (applying down while
  `059:223` NOT NULL stands re-introduces the 23502; down is for controlled rollback only).
- [ ] Run AC6/AC7 integration test → GREEN.

### Phase 3 — Regression + type gates

- [ ] Run the slots + ws-handler test set (AC8) and `tsc --noEmit` (AC9).
- [ ] Confirm `concurrency.ts` is **untouched** (`git diff --stat` shows no app-code change) — the fix
  is purely SQL.

### Phase 4 — Ship

- [ ] PR body uses `Closes #<tracking-issue>` (migration applies synchronously in
  `web-platform-release.yml#migrate` on merge — see `wg-use-closes-n-in-pr-body-not-title-to`). Link
  Sentry issue `52442f7a9b77462b9927b1f055204cce` and the post-mig-059 learning.
- [ ] Post-merge: verify AC10 (function body contains `workspace_id` via Supabase MCP introspection)
  and AC11 (Sentry no-fire).

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

- **Multi-workspace future:** the solo-canary derivation assumes one owner-workspace per user. When
  team-workspace assigns a conversation to a *non-personal* workspace, the RPC must be widened to
  accept an explicit `p_workspace_id` (changing the signature + the TS caller + the grants). Track as
  Future Work (see learning §"solo-canary invariant as derivation source"). For today's solo-tenant
  reality this is correct and matches the `059` backfill semantics.
- **Signature immutability:** the existing `grant execute … (uuid, uuid, integer)` at `029:208` is
  keyed on the exact arg types. The re-issue MUST NOT change the arg list, or the grants silently
  stop applying. `CREATE OR REPLACE` with an identical signature preserves ACLs.
- **`on conflict do update` path is unaffected** — it does not touch `workspace_id`, so existing rows
  keep their backfilled value. Only the new-row INSERT branch needed the fix; do not add
  `workspace_id` to the `do update set` clause (would be a no-op churn and risks overwriting a valid
  backfilled value with a re-derived one).
- **Do NOT remove the `reportSilentFallback` mirror** in `concurrency.ts` — it is the correct,
  rule-mandated observability for the genuine-error path (`cq-silent-fallback-must-mirror-to-sentry`).
  The fix is to stop *causing* the error, not to silence its reporting.
- **Empty `## User-Brand Impact` would fail `deepen-plan` Phase 4.6** — section is filled above with a
  concrete artifact, exposure note, and `single-user incident` threshold.
- **Migration is non-transactional-safe:** the body is a single `CREATE OR REPLACE FUNCTION` — no
  `CREATE INDEX CONCURRENTLY`/`VACUUM`/`ALTER SYSTEM`, so it runs cleanly inside Supabase's
  per-migration transaction wrapper (per the 029/025/027 CONCURRENTLY caveat).

## 🗂 Files to Edit

- _none_ (no application-code change — confirming `concurrency.ts` and `ws-handler.ts` stay untouched
  is itself an acceptance criterion, AC2).

## 🆕 Files to Create

- `apps/web-platform/supabase/migrations/093_acquire_slot_workspace_id.sql`
- `apps/web-platform/supabase/migrations/093_acquire_slot_workspace_id.down.sql`
- `apps/web-platform/test/concurrency-acquire-slot-workspace-id.integration.test.ts`

## Open Code-Review Overlap

None — no open `code-review` issue touches these files (new migration + new test; the SQL writer was
missed by the #4343/#4356 sweep, which filed no scope-out for the slots table).

## Domain Review

**Domains relevant:** Product (availability/first-impression), Engineering (DB contract-pair).

This is an infrastructure/correctness fix (a missing column on a SECURITY DEFINER RPC INSERT). No new
user-facing surface, no new UI component, no new flow — the fix *restores* the existing
new-conversation flow that mig 059 silently broke. Product/UX Gate tier: **NONE** (no new
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
  - mode: no solo workspace_members row for user (post-fix RAISE P0001)
    detection: Sentry pg_code:P0001 op:acquireSlot (distinct from 23502)
    alert_route: same Sentry routing — distinguishable by pg_code tag
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
| Populate `workspace_id = p_user_id` directly in the INSERT (skip the `workspace_members` SELECT) | Functionally correct for solo tenancy (equals the resolved value) but loses the fail-loud check and the multi-workspace-ready shape. Rejected in favor of the `workspace_members` resolution per the learning's "solo-canary invariant as derivation source" guidance. |
| Add a `DEFAULT` to `workspace_id` in a new ALTER | Wrong: there is no sensible table-level default for a per-user workspace id; the value is request-scoped (the acquiring user's workspace). |
| Make `workspace_id` nullable again | Reverts a deliberate tenant-isolation invariant from mig 059; unacceptable. |
| Fix in TS (`concurrency.ts` passes a 4th `p_workspace_id` arg) | Requires changing the RPC signature + the grants + the caller, larger blast radius, and the workspace resolution belongs server-side in the SECURITY DEFINER function (where `workspace_members` is reachable without RLS). Deferred to the multi-workspace Future Work item if/when an explicit workspace selection is needed. |

## Future Work (deferred — track as issue if multi-workspace ships)

- Widen `acquire_conversation_slot` to accept an explicit `p_workspace_id` (4-arg signature) when
  conversations can be assigned to non-personal workspaces. This changes the signature, grants, and TS
  caller. File a tracking issue at that time; out of scope for this single-tenant fix.
