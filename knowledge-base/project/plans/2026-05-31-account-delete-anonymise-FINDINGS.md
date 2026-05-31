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

## 1b. ROOT CAUSE CONFIRMED via production Sentry event

> An earlier version of this section wrongly claimed "prod Sentry ingestion is
> dead / firstEvent null / 0 events". **Retracted** — that came from the wrong
> token (`SENTRY_AUTH_TOKEN` lacks issues scope → HTTP 403, which I misread as 0)
> and delayed tool output. Correct facts and the real event are below.

Correct access (prd Doppler): `SENTRY_ORG=jikigai-eu`, `SENTRY_PROJECT=web-platform`,
and the issues endpoint requires the **issue-scoped** token `SENTRY_ISSUE_RW_TOKEN`
(`SENTRY_AUTH_TOKEN` → 403). The project's `firstEvent` is `2026-05-17` — it
ingests events normally.

**The real production event** (query `op:anonymise-action-sends`, HTTP 200, n=1):

- Issue `WEB-PLATFORM-3J` (id `6862074819`), culprit `deleteAccount`, count **2**,
  `environment=production`, `level=error`, `url=https://app.soleur.ai/settings`,
  tags `op=anonymise-action-sends` / `feature=account-delete`.
- Outer exception: `Error: anonymise_action_sends failed — aborting deletion to
  avoid FK-block` (the saga's wrapper at account-delete.ts:274-281).
- **Nested cause: `PostgrestError: permission denied to set parameter
  "session_replication_role"`, SQLSTATE `42501`.**

This is the exact failure the plan hypothesised as "Defect A", now **confirmed by
production telemetry** (not just reasoned from source). The `session_replication_role`
free-text Sentry search returned 0 only because Sentry indexes the outer Error
title, not the nested `PostgrestError.value` — the substring isn't tokenised. The
event payload itself carries the SQLSTATE.

**Regression-assertion string (now sourced from the real event):**
`permission denied to set parameter "session_replication_role"` / code `42501`.

Minor follow-up (not blocking the fix): the saga error groups under the generic
outer Error title, making the real PG cause un-searchable by SQLSTATE in Sentry.
Worth adding the PG `code` as a Sentry tag in `reportSilentFallback` so future
anonymise failures are queryable by SQLSTATE. Track as a small observability
issue.

## 2. Root cause (CONFIRMED — see §1b)

`session_replication_role` is a superuser-only GUC (PGC_SUSET) in stock
PostgreSQL. The anonymise RPCs are `SECURITY DEFINER` owned by `postgres`, which
on managed Supabase is **not** a full superuser, so `SET LOCAL
session_replication_role = 'replica'` raises `42501 permission denied to set
parameter "session_replication_role"` before the UPDATE. The RPC throws,
`account-delete.ts:268-290` catches it and returns the observed UI error. **The
production Sentry event `WEB-PLATFORM-3J` confirms exactly this** (§1b) — it is no
longer a hypothesis. The two other draft "defects" (NOT NULL, missing grant)
remain correctly retracted.

Note `psql` is not installed in this environment, so transactional dev-DB
validation of the fix migration cannot run here; the fix still needs that
validation (or CI) before merge.

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
