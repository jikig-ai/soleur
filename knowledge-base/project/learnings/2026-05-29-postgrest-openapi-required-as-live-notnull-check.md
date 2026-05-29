# Learning: Verify prod NOT-NULL columns live via PostgREST OpenAPI; design-intent comments aren't schema changes

## Problem

During the #4579 brainstorm we needed to confirm, against **live prod**, whether
`messages.{conversation_id,role,content,template_id}` were actually NOT NULL before
choosing a migration strategy. The usual paths were blocked: `psql` is not installed
on this host, and the Supabase MCP requires an interactive OAuth flow (dev/prd are
distinct projects, so the target had to be prd specifically).

Separately, the root cause of the bug was a schema/contract mismatch that had hidden
for months: migration 046 *commented* that draft cards "route via `user_id` (no
`conversation_id` required)" but **never issued the `ALTER ... DROP NOT NULL`**. The
intent existed only in a comment + ADRs; the DDL never matched. All three draft-card
inserters (`kb-drift-ingest`, `github-on-event`, `cfo-on-payment-failed`) were therefore
latently un-insertable, surfacing only when the kb-drift route first executed.

## Solution

**1. PostgREST OpenAPI as an authoritative live NOT-NULL check.** A Supabase project's
PostgREST root returns an OpenAPI doc whose `definitions.<table>.required` array is
exactly the set of NOT-NULL-without-default columns. It's a pure read, needs only the
service-role key, and requires no psql/MCP/OAuth:

```bash
URL=$(doppler secrets get SUPABASE_URL --project soleur --config prd --plain)
KEY=$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY --project soleur --config prd --plain)
curl -s "$URL/rest/v1/" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
  | jq '.definitions.messages.required'
# => ["id","conversation_id","role","content","created_at","status","template_id","workspace_id"]
```

Pipe the key from Doppler straight into the header — never echo it (`hr-never-paste-secrets-via-bang-prefix`). The `.properties.<col>.description` also surfaces column comments (useful nullability hints, e.g. `user_id` "NULL for legacy conversation-bound rows").

**Limits:** OpenAPI does **not** expose grants or RLS policies. For "does role X hold
INSERT?" / "is there a RESTRICTIVE policy?", read the migration DDL — authoritative for
a migration-managed DB (and faster than live SQL).

**2. A design-intent comment is not a schema change.** When a feature's design (comment,
ADR, plan) says a column is optional for a row type, grep for the actual
`ALTER ... DROP NOT NULL` before trusting it. The mismatch here was invisible because the
write path used `createServiceClient()` (no insert ever exercised it) and tests mocked the
tenant client (any row shape passes). Cross-check: `git grep -nE "alter .*drop not null|alter .*set not null" <migrations>` for the column, not just the column name.

## Key Insight

For a migration-managed Supabase DB, **prod schema truth has two cheap authoritative
sources that don't need a DB connection**: PostgREST `definitions.<table>.required` for
NOT-NULL-no-default columns (live), and the migration DDL for grants/policies/constraints
(version-controlled). Reach for these before an interactive MCP OAuth or a missing psql.
And never let a design-intent comment stand in for verified DDL — "the comment says
nullable" is a falsifiable claim, so falsify it.

## Tags
category: integration-issues
module: supabase / schema-verification
related: 2026-05-22-tenant-integration-runtime-failures-post-mig-059, 2026-05-17-mocked-tests-miss-shared-table-schema-gaps
issue: 4579
