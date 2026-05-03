---
date: 2026-05-03
category: integration-issues
tags: [postgrest, postgres, supabase, on-conflict, partial-index, ux-audit, migrations]
related: [PR #2584, #2585, scheduled-ux-audit run 25210899975]
---

# PostgREST cannot infer ON CONFLICT against a partial unique index

## Symptom

The Scheduled UX Audit workflow failed on every run starting 2026-05-01 at the `Seed bot fixture (DB-only v1)` step. PostgREST returned HTTP 409 with body:

```json
{
  "code": "42P10",
  "details": null,
  "hint": null,
  "message": "there is no unique or exclusion constraint matching the ON CONFLICT specification"
}
```

The failing request was a normal upsert:

```http
POST /rest/v1/conversations?on_conflict=user_id,session_id
Prefer: return=representation,resolution=merge-duplicates
{ "user_id": "...", "session_id": "...", "domain_leader": "...", "status": "completed" }
```

The arbiter expected by `?on_conflict=user_id,session_id` was migration 028's partial unique index:

```sql
create unique index if not exists
  uniq_conversations_user_id_session_id
  on public.conversations (user_id, session_id)
  where session_id is not null;
```

Live verification (2026-05-03) confirmed the index existed on prod and the table/FK chain was healthy: a plain `POST /rest/v1/conversations` (no `on_conflict`) and `?on_conflict=id` (the PK) both gated cleanly on the FK. Only `?on_conflict=user_id,session_id` failed at inference.

## Root cause

PostgREST's `on_conflict=<col-list>` parameter compiles to PostgreSQL's `INSERT ... ON CONFLICT (<col-list>) DO UPDATE`. PostgreSQL's index inference for `ON CONFLICT` cannot pick a partial unique index unless the `INSERT` provides an explicit `index_predicate` clause (the `WHERE ...` after the conflict target columns):

```sql
-- This statement could infer a partial unique index on "did"
-- with a predicate of "WHERE is_active", but it could also
-- just use a regular unique constraint on "did"
INSERT INTO distributors (did, dname) VALUES (10, 'Conrad International')
    ON CONFLICT (did) WHERE is_active DO NOTHING;
```

(<https://www.postgresql.org/docs/17/sql-insert.html>)

PostgREST does not synthesize this `WHERE` predicate. Its docs only describe `on_conflict` as resolving against "columns with a UNIQUE constraint" — partial unique indexes are nowhere in scope. There is no PostgREST API path (`Prefer`, query param, header) that emits an inference predicate, and `ON CONSTRAINT <name>` (which would bypass inference) is also not exposed.

## Recovery

Migration `035_conversations_user_id_session_id_unique_total.sql`:

```sql
drop index if exists public.uniq_conversations_user_id_session_id;

create unique index if not exists
  uniq_conversations_user_id_session_id_total
  on public.conversations (user_id, session_id);
```

The non-partial swap is safe even when `session_id` is nullable: NULLS DISTINCT is the Postgres default, so multiple `(user_id, NULL)` rows continue to coexist (verified 14 NULL rows on prod, including two users with 6 each). `CONCURRENTLY` is forbidden inside Supabase's migration transaction (SQLSTATE 25001), matching the 025/027/028 precedent.

Locked in by `bot-fixture.test.ts` "PostgREST infers ON CONFLICT against (user_id, session_id) without 42P10" — a contract test that POSTs with a bogus user_id and asserts the response code is anything except 42P10. A future migration that reverts to a partial form fails CI before the cron does.

## Lessons

1. **Live-probe rule for query-shape claims.** When a plan asserts that PostgREST (or any other ORM/query layer) resolves a particular query construct against a particular DDL shape, the plan MUST include a live-probe step that exercises the exact request shape against the target database stack. The prior plan (`2026-04-18-fix-bot-fixture-hardening-plan.md` line 20) asserted "no live probe required; Supabase docs confirm" partial-index support. Both halves were wrong: the docs do not confirm it, and the live probe (when finally run by the first cron firing on 2026-05-01) returned 42P10. Documentation silence is not documentation support.
2. **Follow-through SLA-exceeded items that verify load-bearing post-merge invariants are not deferrable.** Issues #2584 ("verify migration 028 partial unique index applied to prod") and #2585 ("run scheduled-ux-audit.yml dry-run to exercise upsert + concurrency") were filed 2026-04-18, both flagged `needs-attention`, and both still open at the time of failure. The cron's first natural firing was the verification step those issues called for — and it failed. Issue tracker SLAs need to distinguish "nice-to-do follow-through" from "this is the verification that would have caught a regression already in main."

## References

- Failing run: <https://github.com/jikig-ai/soleur/actions/runs/25210899975>
- Postgres 17 `INSERT ON CONFLICT`: <https://www.postgresql.org/docs/17/sql-insert.html>
- PostgREST `on_conflict`: <https://postgrest.org/en/stable/references/api/preferences.html#prefer-resolution>
- Originating plan: `knowledge-base/project/plans/2026-04-18-fix-bot-fixture-hardening-plan.md`
- Remediation plan: `knowledge-base/project/plans/2026-05-03-fix-ux-audit-seed-conflict-plan.md`
- Migration 035: `apps/web-platform/supabase/migrations/035_conversations_user_id_session_id_unique_total.sql`
- Contract test: `plugins/soleur/test/ux-audit/bot-fixture.test.ts` "PostgREST infers ON CONFLICT against (user_id, session_id) without 42P10"
