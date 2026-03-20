# Learning: PL/pgSQL `::boolean` cast on user-controlled metadata can block all signups

## Problem
A database trigger used `::boolean` to cast `raw_user_meta_data->>'tc_accepted'` when updating the `tc_accepted_at` column on new user creation. PL/pgSQL's `::boolean` cast throws an exception on any value that is not exactly `'true'`, `'false'`, `'t'`, `'f'`, `'1'`, `'0'`, `'yes'`, `'no'`, `'on'`, or `'off'`. If a client sends an unexpected value (empty string, `'True'`, `null` string, JSON `true` serialized differently), the cast raises:

```
ERROR: invalid input syntax for type boolean: "..."
```

Because this runs inside a `BEFORE INSERT` trigger on `auth.users`, the exception aborts the entire INSERT — silently blocking **all** signups through that code path. Supabase surfaces this as a generic 500 to the client with no indication that the trigger is the cause.

## Solution
Replace `::boolean` with a text comparison:

```sql
-- Before (dangerous):
IF (NEW.raw_user_meta_data->>'tc_accepted')::boolean THEN

-- After (safe):
IF NEW.raw_user_meta_data->>'tc_accepted' = 'true' THEN
```

Text equality is a total function — it returns `false` for any non-matching value instead of throwing. The trigger degrades gracefully: unexpected metadata values simply skip the `tc_accepted_at` update rather than killing the transaction.

## Key Insight
Never use `::boolean` (or any narrowing cast) on user-controlled data inside a PL/pgSQL trigger. Triggers run in the same transaction as the triggering statement — an unhandled exception in a trigger rolls back the entire operation. For `BEFORE INSERT` triggers on authentication tables, this means a single malformed metadata value blocks all user creation. Prefer text comparison (`= 'true'`) or `COALESCE` with a safe default. The same principle applies to `::integer`, `::timestamptz`, and other casts on JSONB-extracted text — if the data comes from a client, treat the cast as a potential exception source.

## Session Errors
1. Next.js build fails in worktrees because Turbopack infers the workspace root from `node_modules` location, which resolves to the bare repo root instead of the worktree — run `npm install` in the worktree to create a local `node_modules`
2. TypeScript compiler not found in worktree — same root cause as above, `npx tsc` resolves to the bare repo's `node_modules` which may not have `typescript` installed
3. Next.js lint via `npx next lint` picks up wrong Next.js version when bare repo has a different version in its `node_modules` — always use the worktree-local `./node_modules/.bin/next` binary

## Related
- [supabase-silent-error-return-values](2026-03-20-supabase-silent-error-return-values.md) — another Supabase failure mode that silently discards errors
- [postgresql-set-not-null-self-validating](2026-03-18-postgresql-set-not-null-self-validating.md) — PostgreSQL DDL safety patterns
- Issues: #889, #911

## Tags
category: database-issues
module: web-platform/auth
