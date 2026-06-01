# Learning: verifying a column "does not exist" — line-scoped ALTER grep gives false negatives; trust existing consumers

## Problem

While planning the KB went-quiet detector (#4717), I needed to know whether
`public.users` carries a `repo_url` column (to decide users-centric vs
workspace-centric scan). I ran:

```bash
grep -rlnE "ALTER TABLE (public\.)?users.*repo_url|users ADD COLUMN repo_url" supabase/migrations/
```

It returned nothing, so I asserted in the plan: **"`users` has no `repo_url`."**
That false negative drove an entire workspace-centric design (scan `workspaces`,
join `workspace_members`, single-workspace-owner MVP scope, a `#4728` deferral).
Plan-review (Kieran) reversed the whole thing: `users` **does** have `repo_url`.

## Root cause

Migration `011_repo_connection.sql` adds the column with a **multi-line**
statement:

```sql
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS repo_url text,
  ...
```

The `ALTER TABLE` and the `ADD COLUMN ... repo_url` are on **different lines**, so
the line-scoped regex `users.*repo_url` (which requires both tokens on one line)
never matched. `grep` is line-oriented by default; multi-line DDL defeats any
single-line `table.*column` pattern. Columns added in an initial `CREATE TABLE`
defeat an `ALTER`-only pattern the same way.

Worse: I had **already read the disproving evidence** and didn't connect it. Arm 2
of the very cron I was extending queries `.from("users").select("id,
kb_sync_history").eq("repo_status","ready")` — proof that `users` carries the
`repo_*` column family. A consumer that already SELECTs sibling columns is a
stronger existence proof than any migration grep.

## Solution

To verify a column/field exists (or doesn't) on a table:

1. **Grep the bare column name across all migrations**, not a line-scoped
   `table.*column` pattern: `git grep -n "repo_url" supabase/migrations/`. Then
   read the hits to confirm the owning table.
2. **Cross-check existing consumers.** A query, RPC, or type that already reads a
   sibling column from the table proves the table carries that column family —
   and consumers are authoritative about *live* schema in a way that
   superseded/`.down.sql` migrations are not.
3. When the answer reverses a design decision, **prefer the live signal** (an
   existing `.from(table).select(col)` in shipped code) over inference from
   migration archaeology.

## Key Insight

**`grep` is line-oriented; SQL DDL is not.** A `table.*column` regex silently
returns a false negative for any multi-line `ALTER TABLE … ADD COLUMN` or initial
`CREATE TABLE` column. For existence questions, grep the *identifier alone* and
let the surrounding context tell you the table — and treat an existing consumer of
a sibling column as the load-bearing proof, since shipped code reflects live
schema and migration files can be superseded. The cheapest, most reliable
"does table T have column C?" check is often "does any shipped query already read
C-family columns from T?" — which I had in hand and ignored.

Generalizes the existing plan Sharp Edge "grep the defining module before claiming
a field exists" to the multi-line-DDL / column-existence case. Relates to
[[silence-detector-needs-out-of-band-liveness-signal]] (same feature).

## Session Errors

1. **False "users has no repo_url" premise** (plan v1) — line-scoped grep missed
   multi-line ALTER (mig 011); ignored arm 2's own `users` query as
   counter-evidence. **Recovery:** verified mig 011 + `app/api/repo/setup/route.ts:75`
   writer + arm-2 consumer; rewrote plan/spec/tasks to users-centric (which also
   delivered genuine by-construction mutual exclusivity with arm 2).
   **Prevention:** this learning + a routed plan-skill Sharp Edge bullet.

## Tags
category: logic-errors
module: plan-skill / supabase-migrations
issues: 4717
