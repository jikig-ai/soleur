# Runbook — manually supplying the four DSAR-excluded user-keyed tables

**Status:** active
**Owner:** operations
**Created:** 2026-08-12 (#7349, review of PR #7416)
**Tracked successor:** #7487 (promote these tables to the export allowlist and retire this runbook)

## Why this exists

`docs/legal/data-protection-disclosure.md` §5.3(a) — a **published** legal undertaking —
tells a data subject that four tables are excluded from the self-serve Art. 15 bundle
today, and that they may ask us by email and we will **supply them manually using the
documented queries**. This file is those queries.

Without it that sentence is an undertaking with nothing behind it, and the Art. 12(3)
deadline is one month from receipt. An operator receiving such a request must not have to
invent a query under a statutory clock.

The four tables and why each is currently excluded (`apps/web-platform/server/dsar-export-allowlist.ts`):

| Table | Owner column | What the subject gets |
|---|---|---|
| `workspace_activity` | `actor_user_id` | activity events they generated in shared workspaces |
| `kb_files` | `user_id` | knowledge-base uploads attributed to them (filename, path, timestamps) |
| `user_session_state` | `user_id` | their current-organisation interface preference |
| `routine_runs` | `actor_id`, `delegating_principal` | routine executions they initiated or delegated |

## Preconditions

- The requester's identity is verified to the same standard as the self-serve flow.
- You have the subject's `auth.users.id` (`:uid` below).
- Run against **prd** with the service-role key, read-only.

## The queries

Run each and attach the result as one JSON file per table, named `tables/<table>.json`, so
the manual bundle matches the shape of the self-serve one.

```sql
-- 1. workspace_activity
SELECT * FROM public.workspace_activity WHERE actor_user_id = :uid ORDER BY created_at;

-- 2. kb_files
SELECT * FROM public.kb_files WHERE user_id = :uid ORDER BY created_at;

-- 3. user_session_state  (0 or 1 row)
SELECT * FROM public.user_session_state WHERE user_id = :uid;

-- 4. routine_runs — TWO owner columns; a subject can appear as either, so
--    querying only actor_id under-supplies a delegated run.
SELECT * FROM public.routine_runs
WHERE actor_id = :uid OR delegating_principal = :uid
ORDER BY created_at;
```

A table returning zero rows becomes a statement in a statutory response, so confirm the
query actually reached prd before reporting it as "no data": `doppler run -p soleur -c prd --
scripts/supabase-logs-query.sh --ref ifsccnjhymdmidffkzhl --source postgres_logs --since <window>` shows
the read in the platform logs and answers with a coverage verdict rather than a bare zero.
**The ref is required and it is the APPLICATION project (`soleur-web-platform`)** — the
subject's data does not live in the Inngest backing project. Runbook:
`knowledge-base/engineering/operations/runbooks/supabase-log-query.md`.

## Art. 15(4) check before sending

`workspace_activity` and `kb_files` are **shared-workspace** tables: rows the subject
generated can name other people, and a co-member's `filename` can itself be personal data.
The self-serve bundle redacts foreign-authored content (`redactRow` / `pseudonymiseUserId`
in `apps/web-platform/server/dsar-export.ts`). A manual supply must apply the same
standard — otherwise the manual path discloses more about third parties than the automated
one, which is a fresh breach committed while answering a lawful request.

Concretely: return only rows whose owner column equals `:uid`, and do not widen to
"everything in the workspaces they belong to".

## Record the fulfilment

Append a row to the DSAR log with the request date, the tables supplied, and the Art. 15(4)
redactions applied, so the one-month clock and the redaction decision are both evidenced.

## Retire this runbook when

#7487 lands. Once the four tables are in `DSAR_TABLE_ALLOWLIST` with export chains, they
appear in the self-serve bundle, §5.3(a) moves them from the excluded list to the contained
list, and this manual path — along with the undertaking that requires it — goes away.
