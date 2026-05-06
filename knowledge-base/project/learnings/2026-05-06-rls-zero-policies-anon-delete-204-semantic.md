---
title: RLS-with-zero-policies + anon DELETE returns 204 (no-op), not 401
date: 2026-05-06
category: security-issues
module: supabase
related:
  - PR #3355
  - migration 030 (precedent: processed_stripe_events)
  - migration 038 (this PR)
  - learnings/security-issues/2026-04-18-rls-for-all-using-applies-to-writes.md
---

# Learning: RLS-with-zero-policies + anon DELETE returns 204 (no-op), not 401

## Problem

PR #3355 plan's pre-merge verification probe predicted post-fix anon HTTP
status codes as:

```
SELECT → 200 []   INSERT → 401   DELETE → 401
```

Live result post-migration:

```
SELECT → 200 []   INSERT → 401   DELETE → 204
```

A naïve probe that asserts `[[ "$DELETE_CODE" =~ ^40[13]$ ]]` would FAIL
the gate and report "RLS not applied" even though RLS is correctly
blocking the delete. A naïve probe that asserts only on status code
without re-checking the row's continued existence would PASS even if
RLS were misconfigured to allow the delete.

## Root Cause

PostgREST + Postgres RLS semantics for `DELETE FROM x WHERE y` when RLS
is enabled with zero policies and the role is `anon`:

1. PostgREST translates `DELETE /rest/v1/x?y=eq.z` into
   `DELETE FROM x WHERE y = 'z' RETURNING *`.
2. Postgres applies RLS *before* the WHERE filter — anon sees zero rows
   in `x` because there is no permissive policy. The RETURNING clause
   sees zero rows.
3. Postgres returns "0 rows deleted" — this is a successful query with
   an empty result, not a permissions error.
4. PostgREST maps "successful query, empty result" to `204 No Content`.
5. INSERT is different — `INSERT` triggers a permissions check at the
   GRANT layer (anon doesn't have INSERT-with-RLS-WITH-CHECK passing),
   so PG raises `42501 insufficient_privilege` → PostgREST `401`.

The asymmetry is real: RLS denies SELECT/UPDATE/DELETE by *hiding rows*,
not by raising auth errors. INSERT denies by *raising a permissions
error* because there's no row to hide yet.

## Solution

Verification probe MUST re-check row existence via service-role after
attempted DELETE, not rely on status code alone. Pattern:

```bash
# 1. Insert a probe row via service-role.
PROBE=$(date +%s)-rls-test
curl -X POST -H "apikey: $SVC" -H "Authorization: Bearer $SVC" \
  -d "{\"id\":\"$PROBE\"}" "$URL/rest/v1/<table>"

# 2. Attempt anon DELETE (will return 204 regardless of RLS state).
curl -X DELETE -H "apikey: $ANON" -H "Authorization: Bearer $ANON" \
  "$URL/rest/v1/<table>?id=eq.$PROBE"

# 3. Verify row still exists via service-role.
RESULT=$(curl -H "apikey: $SVC" -H "Authorization: Bearer $SVC" \
  "$URL/rest/v1/<table>?id=eq.$PROBE")

if [[ "$RESULT" == *"$PROBE"* ]]; then
  echo "PASS: anon DELETE was a no-op (RLS hid the row)"
else
  echo "FAIL: anon DELETE actually deleted the row -- RLS misconfigured"
fi
```

Expected status codes for RLS-with-zero-policies on anon role:

| Verb   | Status | Body | Why |
|--------|--------|------|-----|
| SELECT | 200    | `[]` | Table-level GRANT preserved; RLS hides rows |
| INSERT | 401    | err  | PG `42501` → PostgREST 401 (no row to hide) |
| UPDATE | 204    | none | Zero rows match the (RLS-filtered) WHERE |
| DELETE | 204    | none | Zero rows match the (RLS-filtered) WHERE |

PR #3355's plan was updated; future plans for service-role-only tables
should cite this learning when prescribing verification probes.

## Key Insight

**Status code alone is not sufficient evidence that RLS is denying a
DELETE.** A `204` post-fix could mean (a) RLS correctly hid the row
and the delete was a no-op, or (b) the migration didn't apply and
anon successfully deleted nothing because the WHERE filter matched
nothing. The only way to distinguish is to seed a known row via
service-role, attempt the delete via anon, and re-check existence.

This applies symmetrically to UPDATE — both row-mutation verbs are
"hidden by RLS" rather than "denied by RLS."

## Related Operational Notes

### Local dev rehearsal: prefer pooler URL over direct DB URL

Direct `DATABASE_URL` (`db.<ref>.supabase.co:5432`) resolves to an
IPv6-only host. Local machines without IPv6 connectivity (or behind
IPv4-only NAT) get `Network is unreachable`. Use `DATABASE_URL_POOLER`
instead — it points to `aws-0-eu-west-1.pooler.supabase.com` (IPv4)
and accepts the same `psql` connection string format. Both are in
Doppler `dev` and `prd` configs.

### `psql` not on PATH for runner script

`apps/web-platform/scripts/run-migrations.sh` requires `psql`. If not
installed locally, fall back to:

```bash
docker run --rm --network host \
  -v "$PWD/apps/web-platform/supabase/migrations:/migrations:ro" \
  postgres:15 psql "$DATABASE_URL_POOLER" \
  -v ON_ERROR_STOP=1 -f /migrations/<NNN>_<file>.sql
```

`--network host` is required for the container to reach the pooler URL
via the host's DNS/network stack.

## Session Errors

**psql not in default tooling** — Recovery: `docker run --rm postgres:15
psql ...`. Prevention: documented above.

**DATABASE_URL direct connection fails on IPv6-unreachable hosts** —
Recovery: switch to DATABASE_URL_POOLER. Prevention: documented above
as the canonical local-dev rehearsal pattern.

**session-state.md plan path written as worktree-absolute** — Recovery:
caught by code-quality-analyst review and fixed inline to repo-relative
path. Prevention: one-shot's session-state writer should always emit
repo-relative paths so the doc remains navigable post-merge.

**Plan verification probe predicted DELETE → 401, actual is 204** —
Recovery: probe assertion updated to accept `204` AND re-check row
existence via service-role. Prevention: this learning file.
