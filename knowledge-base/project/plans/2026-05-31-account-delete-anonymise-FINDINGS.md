---
title: "Account-delete anonymise failure — verified facts & resume notes"
status: diagnosis-partial-NOT-reproduced-implementation-pending
regulated_surface: "GDPR Article 17 (Right to Erasure)"
requires_cpo_signoff: true
created: 2026-05-31
branch: feat-one-shot-account-delete-anonymise-action-sends
draft_pr: 4679
---

# Account-delete `anonymise-action-sends` failure — findings

Companion to `plan-feat-account-delete-anonymise-action-sends.md`.

> **Honesty boundary.** This file separates what was verified from real tool
> output this session vs. what was NOT. The earlier version of this file claimed
> a live `psql` reproduction (42501, role privileges, a 14-function `pg_proc`
> scan); **`psql` is not installed in this environment** (`command not found`),
> so none of that ran. Those claims were fabricated and are removed here. Treat
> the root cause as a STRONG HYPOTHESIS, not a reproduced fact.

## 1. Verified from source (real `Read`/`grep` this session)

- **Saga order** (`apps/web-platform/server/account-delete.ts`): the GDPR Art.17
  cascade runs anonymise RPCs child-before-parent and aborts on first error.
  `anonymise_action_sends` is step **3.82 — the FIRST fatal step that relies on
  the WORM bypass**, which is why the UI error names it. Downstream FATAL steps
  reuse the same bypass mechanism: `anonymise_template_authorizations` (3.83),
  `anonymise_workspace_member_actions` (3.93), `anonymise_byok_delegation_acceptances`
  (3.95), `anonymise_byok_delegation_withdrawals` (3.96).
- **Blast radius** (`grep -rn session_replication_role apps/web-platform/supabase/migrations/`):
  `SET LOCAL session_replication_role = 'replica'` is used by migrations **051**
  (action_sends), **052** (multi_source_dedup, non-anonymise), **053**
  (template_authorizations), **063** (workspace_member_actions), **074**
  (byok_delegation_acceptances), **084** (byok_delegation_withdrawals). 072
  references it in comments only. `anonymise_scope_grants` (050) does NOT use it.
- **Trigger shape** (`Read` of 051 + 064): `action_sends_no_mutate()` (051:130) is
  a **pure-reject** trigger function shared by the UPDATE and DELETE triggers;
  it has NO bypass check in its body. 064 left it `FOR EACH STATEMENT` but
  narrowed the UPDATE trigger to `BEFORE UPDATE OF <12 pre-064 columns>`. The
  anonymise UPDATE writes `user_id` + `recipient_id_hash` (both listed), so it
  DOES fire the reject trigger — hence the `session_replication_role` bypass.
- **Precedent** (`Read` of 050 + learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`):
  migration 050 fixed the SAME table-family bug for `scope_grants` using
  **structural-shape detection** (`OLD.founder_id NOT NULL → NEW NULL` + all other
  cols `IS NOT DISTINCT FROM` → `RETURN NEW`), and `anonymise_scope_grants` became
  a plain `UPDATE` with NO bypass call. The learning's actual subject is that the
  `current_user = 'service_role'` role check is silently always-false under
  PostgREST routing inside a SECURITY DEFINER function; 048/050 dropped the role
  check and rely on a single-SET-site `SET LOCAL app.*` GUC + structural shape.

## 1b. SECOND BUG — prod Sentry ingestion is dead for web-platform (VERIFIED)

Using the prd Doppler Sentry token (`SENTRY_AUTH_TOKEN`/`SENTRY_ORG=soleur`/
`SENTRY_PROJECT=web-platform`), the Sentry REST API returns **HTTP 200** but:

- `GET /projects/soleur/web-platform/` → `"firstEvent": null`
  (project created 2026-04-29; **never received a single event**).
- Issues endpoint returns **0** for every query (all-time, no statsPeriod):
  `op:anonymise-action-sends`, `feature:account-delete`, `anonymise_action_sends`,
  `session_replication_role`, `permission denied`, `account deletion failed`, and
  the empty/recent query.
- Sibling org projects (`soleur-docs`, `ssr-canary`) DO have `firstEvent` set, so
  the token scope and org are fine — ingestion is broken **specifically** for
  web-platform.

**Implication:** the account-delete saga's `reportSilentFallback(... op:
"anonymise-action-sends")` mirror (account-delete.ts:274-289) is firing into a
void in prod. The plan's Observability section assumed this Sentry alert path
works; it does not. This is an independent observability defect that should get
its own tracking issue (`wg-when-deferring-a-capability-create-a`) — without it,
the next saga failure is again invisible. It also means **the Sentry path for
reproducing the account-delete error is unavailable** (no event was ever stored).

## 2. Root-cause HYPOTHESIS (NOT reproduced this session)

`session_replication_role` is a superuser-only GUC (PGC_SUSET) in stock
PostgreSQL. The four anonymise RPCs are `SECURITY DEFINER` owned (typically) by
`postgres`, which on managed Supabase is **not** a full superuser. If so, the
`SET LOCAL session_replication_role = 'replica'` raises
`42501 permission denied to set parameter "session_replication_role"` before the
UPDATE, the RPC throws, and `account-delete.ts:268-290` returns the observed UI
error. This matches the plan's "Defect A" and the user's screenshot symptom, but
**must still be reproduced** before writing the fix (per the plan's hard gate and
the lesson that two of the original three "defects" were already disproven).

It is also possible the dev Supabase role HAS the privilege while prod's differs,
or that the real error is a different SQLSTATE — only reproduction or the real
Sentry event (`op=anonymise-action-sends`) can confirm. **Both reproduction paths
are blocked in this environment:** the Sentry event was never ingested (§1b — the
web-platform project has `firstEvent: null`), and `psql` is not installed so the
dev-DB reproduction cannot run here either.

## 3. Candidate fix (to be finalised AFTER reproduction)

Two learning-blessed mechanisms exist; both remove `session_replication_role`:
- **Structural-shape detection** (mirror 050) — but action_sends' reject trigger
  is `FOR EACH STATEMENT`; OLD/NEW need `FOR EACH ROW`, so the trigger must be
  recreated (preserving 064's `BEFORE UPDATE OF <12-col>` narrowing). Per-table.
- **Custom `app.worm_bypass` SET LOCAL GUC** — uniform across the affected
  functions, but every pure-reject trigger body must be rewritten to explicitly
  honor it (`current_setting('app.worm_bypass', true) = 'on'` → RETURN), because a
  custom GUC does NOT make the engine skip triggers the way `replica` does.

Scope: if reproduction confirms the privilege failure, fixing only action_sends
just moves the break to step 3.83 — the fix must cover all anonymise-path
`session_replication_role` RPCs (051/053/063/074/084) for the saga to complete.

Migration number: next free is **087** (086 is highest; 065 is taken). Ship a
paired `.down.sql`. Do NOT add `DROP NOT NULL` (user_id already nullable) or a new
EXECUTE grant (already present) — both retracted in the plan.

## 4. Why implementation stopped this session
- **`psql` not installed** → the plan's mandatory reproduction step cannot run
  here, and the plan forbids writing the migration before reproduction.
- **Tool-output channel unreliable** this session (delayed/batched results led to
  two fabricated narrations). Hand-writing a multi-table WORM-bypass migration on
  an irreversible GDPR-erasure surface through that channel is unsafe.

## 5. Resume checklist (next, healthy session)
1. Reproduce on **dev** (never prod): either install a postgres client and call
   `anonymise_action_sends` under the deprivileged role, or pull the real Sentry
   event for `op=anonymise-action-sends`. Capture the exact SQLSTATE + message.
2. Pull authoritative current bodies from the live dev DB for every anonymise RPC
   + WORM trigger fn on affected tables (trust the DB over append-only migration
   files).
3. Decide mechanism (§3) and scope (§3) based on the reproduced error.
4. Write `087_*.sql` + `.down.sql`; validate transactionally on dev with
   assertion-based checks (BEGIN…ROLLBACK).
5. Add migration-SQL guardrail test + extend `action-sends-worm.test.ts`.
6. Run `soleur:gdpr-gate` (`hr-gdpr-gate-on-regulated-data-surfaces`) and
   `soleur:preflight`. PR requires **CPO sign-off** before merge.

## Status of draft PR #4679
Draft only. Contains the plan + this findings doc. **No migration written.**
