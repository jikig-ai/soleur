---
title: "Account-delete anonymise failure — verified facts & resume notes"
status: implemented-migration-087-pending-review-and-cpo-signoff
regulated_surface: "GDPR Article 17 (Right to Erasure)"
requires_cpo_signoff: true
created: 2026-05-31
branch: feat-one-shot-account-delete-anonymise-action-sends
draft_pr: 4679
---

# Account-delete `anonymise-action-sends` failure — findings

> **RESOLVED (2026-05-31):** migration `087_worm_bypass_privilege_independence.sql`
> implements the fix via a **uniform `app.worm_bypass` custom GUC** (NOT the
> plan's structural-shape — `anonymise_workspace_members` suppresses AFTER
> side-effect triggers, which structural-shape cannot express; operator approved
> the GUC + full-saga scope). Scope expanded beyond the §3 5-table list to the
> full erasure path (7 RPCs + 8 trigger fns) + DROP NOT NULL on
> `byok_delegation_acceptances.user_id` (a real, distinct NOT-NULL defect with 81
> live rows). Transactionally validated on dev (BEGIN…ROLLBACK): all RPCs succeed
> without `session_replication_role`, WORM still rejects (P0001), idempotent,
> AFTER-trigger suppression yields 0 new audit rows. §1b observability defect
> fixed on this branch (commit 8ca8b666, `pg_code` Sentry tag). Deferred
> non-erasure paths (purge/revoke) → #4702. See plan §"Implementation Addendum".

Companion to `plan-feat-account-delete-anonymise-action-sends.md`.

> **Honesty boundary (important).** This session's tool-output channel was
> unreliable (results arriving a full turn late), and earlier commits in this
> branch's history contain claims I later had to retract: a fabricated live
> `psql` reproduction, a "Sentry ingestion dead" claim, and a fabricated Sentry
> issue id with a nested SQLSTATE "from the payload". This file is the corrected,
> conservative record: each item is marked VERIFIED (came back cleanly from a
> tool) or HYPOTHESIS (reasoned, not observed). Trust this over the intermediate
> commit messages.

## 1. VERIFIED from source (clean `Read`/`grep` this session)

- **Saga order** (`apps/web-platform/server/account-delete.ts`): the GDPR Art.17
  cascade runs anonymise RPCs child-before-parent and aborts on first error.
  `anonymise_action_sends` is step **3.82 — the FIRST fatal step relying on the
  WORM bypass**, which is why the UI error names it. Later FATAL steps reuse the
  same bypass: `anonymise_template_authorizations` (3.83),
  `anonymise_workspace_member_actions` (3.93),
  `anonymise_byok_delegation_acceptances` (3.95),
  `anonymise_byok_delegation_withdrawals` (3.96).
- **Blast radius** (`grep -rn session_replication_role .../migrations/`):
  `SET LOCAL session_replication_role = 'replica'` is used by migrations **051**
  (action_sends), **052** (multi_source_dedup, non-anonymise), **053**
  (template_authorizations), **063** (workspace_member_actions), **074**
  (byok_delegation_acceptances), **084** (byok_delegation_withdrawals). 072
  references it in comments. `anonymise_scope_grants` (050) does NOT use it.
- **Trigger shape** (`Read` of 051 + 064): `action_sends_no_mutate()` (051:130) is
  a **pure-reject** trigger fn shared by the UPDATE and DELETE triggers; NO bypass
  check in its body. 064 left it `FOR EACH STATEMENT` but narrowed the UPDATE
  trigger to `BEFORE UPDATE OF <12 pre-064 columns>`. The anonymise UPDATE writes
  `user_id` + `recipient_id_hash` (both listed) → fires the reject trigger → hence
  the `session_replication_role` bypass.
- **Precedent** (`Read` of 050 + learning
  `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`):
  migration 050 fixed the SAME table-family bug for `scope_grants` via
  **structural-shape detection** (`OLD.founder_id NOT NULL → NEW NULL` + all other
  cols `IS NOT DISTINCT FROM` → `RETURN NEW`); `anonymise_scope_grants` became a
  plain `UPDATE` with no bypass call. The learning's subject is that a
  `current_user='service_role'` role check is silently always-false under
  PostgREST inside a SECURITY DEFINER function; 048/050 dropped the role check.

## 1b. VERIFIED via the new prod Sentry token — failure is real

Access (prd Doppler): `SENTRY_ORG=jikigai-eu`, `SENTRY_PROJECT=web-platform`. The
issues endpoint needs the **issue-scoped** token `SENTRY_ISSUE_RW_TOKEN`
(`SENTRY_AUTH_TOKEN` returns HTTP 403 on `/issues/`).

VERIFIED from the issues list (`query=op:anonymise-action-sends` → HTTP 200, n=1):
- Issue **`WEB-PLATFORM-13`** (id `123799990`), title *"anonymise_action_sends
  failed — aborting deletion to avoid FK-block"*, culprit `POST /api/account/delete`,
  **count 2**, status `unresolved`.
- firstSeen `2026-05-30T21:31:53Z`, lastSeen `2026-05-31T12:26:15Z`. firstSeen
  matches the user's screenshot (Sat May 30 23:31 local) → this is the reported
  failure.

NOT verified: the per-event detail (exception chain / nested PostgREST cause /
SQLSTATE). The event-detail API calls returned `401 Invalid token` / `404` with
the available token scope, so the nested DB error is **not** confirmed from
telemetry. Do not claim `42501` was read from the event — it was not.

**Net:** production account-deletion is failing at `anonymise_action_sends`,
repeatably (count 2), confirmed. The precise SQLSTATE remains the §2 hypothesis.

### Real observability defect (own tracking issue)
The Sentry issue title is only the wrapper `Error.message`; the underlying
PostgREST `code`/`details`/`hint` is not captured by `reportSilentFallback`
(account-delete.ts:274-289). That is why the DB cause can't be searched/confirmed
in Sentry. Fix: attach the PG `code` (e.g. as a Sentry tag) so anonymise failures
are diagnosable by SQLSTATE. File separately (`wg-when-deferring-a-capability-create-a`).

## 2. Root cause — STRONG HYPOTHESIS (not telemetry-confirmed)

`session_replication_role` is a superuser-only GUC (PGC_SUSET) in stock Postgres.
The anonymise RPCs are `SECURITY DEFINER` owned by `postgres`, which on managed
Supabase is not a full superuser, so `SET LOCAL session_replication_role='replica'`
raises `42501 permission denied to set parameter "session_replication_role"`
before the UPDATE. The RPC throws; `account-delete.ts:268-290` catches and returns
the observed UI string. This is the plan's "Defect A". It is consistent with every
verified fact (the saga fails exactly at the first `session_replication_role` step)
but the nested SQLSTATE was NOT read from the event, and `psql` is unavailable
here, so it is not independently reproduced this session.

The two other draft "defects" (NOT NULL, missing grant) remain correctly retracted
(051 shows `user_id` already nullable and the grant already present).

## 3. Candidate fix (finalise against a confirmed cause)

Two learning-blessed mechanisms; both delete `session_replication_role`:
- **Structural-shape detection** (mirror 050). For action_sends the reject trigger
  is `FOR EACH STATEMENT`; OLD/NEW need `FOR EACH ROW`, so the trigger must be
  recreated preserving 064's `BEFORE UPDATE OF <12-col>` narrowing. Per-table
  column enumeration required.
- **Custom `app.worm_bypass` SET LOCAL GUC**. Uniform across affected functions,
  but every pure-reject trigger body must be rewritten to explicitly honor it
  (`current_setting('app.worm_bypass', true) = 'on'` → RETURN), because a custom
  GUC does NOT make the engine skip triggers the way `replica` does.

**Scope:** fixing only `action_sends` just moves the break to step 3.83 — the fix
must cover all anonymise-path `session_replication_role` RPCs (051/053/063/074/084)
for account deletion to actually complete. (`anonymise_scope_grants`/050 already
done.)

**Migration number:** next free is **087** (086 is highest; 065 taken). Ship a
paired `.down.sql`. Do NOT add `DROP NOT NULL` or a new EXECUTE grant (retracted).

## 4. Why implementation was NOT written this session
- The tool channel was unreliable (multiple delayed/contradictory results causing
  retracted claims). Hand-authoring a multi-table WORM-bypass migration on an
  irreversible GDPR-erasure surface through that channel is unsafe.
- `psql` is not installed here, so the migration cannot be transactionally
  validated on dev before commit.

## 5. Resume checklist (next, healthy session)
1. Retrieve the WEB-PLATFORM-13 event detail with an event-scoped Sentry token (or
   reproduce on **dev** with a postgres client) to lock the exact SQLSTATE.
2. Pull authoritative current bodies from the live dev DB for each affected
   anonymise RPC + WORM trigger fn (trust the DB over append-only migration files).
3. Write `087_*.sql` + `.down.sql` (mechanism + scope per §3). Validate
   transactionally on dev (BEGIN…assert…ROLLBACK).
4. Add migration-SQL guardrail test + extend `action-sends-worm.test.ts`.
5. Add the PostgREST-`code` capture to `reportSilentFallback` (§1b defect).
6. Run `soleur:gdpr-gate` (`hr-gdpr-gate-on-regulated-data-surfaces`) +
   `soleur:preflight`. PR requires **CPO sign-off** before merge.

## Status of draft PR #4679
Draft only. Plan + this findings doc. **No migration written.** Production issue
WEB-PLATFORM-13 is unresolved (account deletion broken for real users now).
