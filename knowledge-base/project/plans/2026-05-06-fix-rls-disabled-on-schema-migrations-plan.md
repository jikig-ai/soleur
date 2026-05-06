---
type: security-fix
classification: prod-write-via-migration
requires_cpo_signoff: true
issue: TBD (Supabase advisor alert 2026-05-03, not yet filed)
related: PR #2598 (RLS semantics), migration 030 (service-role-only RLS precedent)
---

# fix(security): enable RLS on `public._schema_migrations` to clear `rls_disabled_in_public` advisor lint

## Enhancement Summary

**Deepened on:** 2026-05-06
**Sections enhanced:** Acceptance Criteria (probe form), Risks, Test Strategy
**Research used:** live anon-key probe against `soleur-dev`; PostgREST docs (Context7 `/postgrest/postgrest`); two prior learnings in `knowledge-base/project/learnings/`; AGENTS.md rule cross-reference.

### Key Improvements
1. **Probe expected status codes are now load-bearing-correct.** Pre-fix baseline confirmed live: anon GET `_schema_migrations` returns `200`, anon POST returns `201`, anon DELETE returns `204` (verified 2026-05-06 19:07 UTC against project ref `mlwiodleouzwniehynfz`). Post-fix expectation pinned per PostgREST docs `docs/references/errors.md`: anon GET → `200 []`, anon POST → `401` (insufficient_privilege; PostgREST maps PG `42501` → 401 for unauthenticated, 403 for authenticated; the Supabase anon key is a JWT claiming the `anon` role, so PostgREST classifies as unauthenticated → 401).
2. **Zero-policy choice cross-checked against learning `rls-column-takeover-github-username-20260407.md`.** Any permissive policy on `_schema_migrations` (e.g., a "let anon read" policy) would inherit Supabase's row-level (not column-level) semantics and re-expose the schema-enumeration surface. Zero-policy is provably the minimum-viable AND minimum-risk fix.
3. **Cited migration 030 precedent verified by Read.** Migration 030 lines 27-30 explicitly document the "enable RLS, zero policies, service-role-only" pattern as defense-in-depth for service-role-only tables — exact match for `_schema_migrations`'s access profile.

### New Considerations Discovered
- The Supabase advisor lint may take **5-15 min** to clear after migration apply — advisors are scheduled, not realtime. The post-merge probe is the immediate signal; the dashboard is the lagging confirmation.
- A nightly CI advisor scan (post-merge) is the structural fix that would have caught this earlier — explicitly scoped out of this PR but called out as a follow-up issue at ship time (see "Out of Scope").

## Overview

Supabase's `rls_disabled_in_public` advisor lint fired on `soleur-dev`
(project ref `mlwiodleouzwniehynfz`) on 2026-05-03 with the alert text
"Anyone with your project URL can read, edit, and delete all data in
this table because Row-Level Security is not enabled."

Direct probing of the dev REST API with the public anon key
(`NEXT_PUBLIC_SUPABASE_ANON_KEY` from Doppler) confirms the alert is
not a false positive: anyone with the public URL can `SELECT`, `INSERT`,
and `DELETE` against `public._schema_migrations` today (verified live
during planning — a `hax.sql` row was inserted with the anon key, then
cleaned up via the service role).

**Single affected table:** `public._schema_migrations` — the migration
runner's tracking table. No application table is exposed.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified) | Plan response |
| --- | --- | --- |
| "Identify which table(s) have RLS disabled" implies multiple tables | The PostgREST OpenAPI for `soleur-dev` exposes 11 paths under the public schema. 10 application tables (`users`, `api_keys`, `conversations`, `messages`, `kb_share_links`, `team_names`, `user_concurrency_slots`, `push_subscriptions`, `processed_stripe_events`, `message_attachments`) all have `enable row level security` in their migration. Only `public._schema_migrations` lacks RLS. | The migration enables RLS on exactly one table. The plan does NOT speculatively add RLS to other tables. |
| `_schema_migrations` is a Supabase-managed system table | The runner script `apps/web-platform/scripts/run-migrations.sh` line 87 creates it with `CREATE TABLE IF NOT EXISTS public._schema_migrations`. It is application-owned, not Supabase-managed. RLS additions are within our control. | Migration is forward-only; safe to commit. |
| Enabling RLS will break the migration runner | The runner uses `psql "$DATABASE_URL"` (line 83), which connects as the `postgres` role. RLS does not apply to superuser/owner connections. | No code changes to the runner are required. |
| Fix needs anon-readable policy for app code | No application code reads `_schema_migrations`. `grep -rn "_schema_migrations"` across `apps/`, `plugins/`, and `scripts/` returns zero non-runner references. | Migration uses **zero policies** (matches migration 030 precedent for `processed_stripe_events`). |

## User-Brand Impact

**If this lands broken, the user experiences:** the migration runner
fails on its next CI run (`web-platform-release.yml` `migrate` job
against prd) with a permissions error, blocking all subsequent
schema deploys until reverted. Worst-case operator impact: a few
hours of inability to deploy DB changes; no user-data exposure.

**If this leaks, the user's data is exposed via:** *(failure-to-fix
scenario)* an attacker with the public Soleur project URL can today
enumerate every migration filename ever applied (revealing schema
evolution timeline, table names, security column names like
`encrypted_key`, `tc_accepted_version`, `subscription_billing_columns`),
and can also `INSERT` arbitrary filenames or `DELETE` existing
tracking rows. A deletion would cause the runner to re-attempt an
already-applied migration on the next run; many of our migrations
are not strictly idempotent (e.g., `CREATE TABLE` without
`IF NOT EXISTS`, `ALTER TABLE ... ADD COLUMN`), so a malicious
delete is a **direct path to a failed prd deploy** — i.e., a
production incident triggerable by anyone with the public anon key.

**Brand-survival threshold:** `single-user incident`. The exposure
is data-disclosure (low-stakes, schema-only) plus prod-deploy DoS
(operator-stakes). A successful malicious delete on prd would force
manual `INSERT INTO _schema_migrations` recovery and could publicly
demonstrate that "anyone on the internet can break Soleur deploys"
— that's brand-survival territory for a security-positioned product
in dev tooling.

CPO sign-off required at plan time before `/work` begins.
`user-impact-reviewer` will be invoked at review time per
`hr-weigh-every-decision-against-target-user-impact`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] New migration file `apps/web-platform/supabase/migrations/038_rls_schema_migrations.sql` created.
- [ ] Migration enables RLS on `public._schema_migrations` with **zero policies** (service-role-only / superuser-only access pattern).
- [ ] Migration includes a `COMMENT ON TABLE` documenting the service-role-only access pattern (matches the precedent set in migration 030).
- [ ] Migration is wrapped in the standard implicit transaction (no `CONCURRENTLY`, no `VACUUM`, no `ALTER SYSTEM` — matches sibling migrations 025/027/028/029/035 conventions).
- [ ] PR description includes a verification snippet showing (a) anon-key `INSERT` returns `42501` insufficient_privilege after the migration, and (b) anon-key `SELECT` returns empty rows (or `42501`) after the migration.
- [ ] PR body includes `Closes #<issue-number>` once the tracking issue is filed (see operator step 1 below).
- [ ] Pre-merge dev rehearsal completed per `knowledge-base/engineering/ops/runbooks/supabase-migrations.md` §0:
  ```bash
  cd apps/web-platform
  doppler run -p soleur -c dev -- bash scripts/run-migrations.sh
  ```
  AND verified with the anon-key probe (operator step 3 below).

### Post-merge (operator)

1. **File a tracking issue** for the Supabase advisor alert (was not pre-filed; this plan creates it inline). Title: `security: rls_disabled_in_public on public._schema_migrations (soleur-dev)`. Update PR body's `Ref #N` → `Closes #N` once filed.
2. **Verify CI `migrate` job succeeds against prd** in `web-platform-release.yml` after merge. The runner uses `psql` over `DATABASE_URL` and is RLS-exempt; no behavioral change is expected.
3. **Re-run the anon-key probe against both dev and prd** to confirm the lint cleared.

   Pre-fix baseline (verified live 2026-05-06 19:07 UTC against `soleur-dev`,
   project ref `mlwiodleouzwniehynfz`): anon `SELECT` → `200`, anon `INSERT`
   → `201`, anon `DELETE` → `204`. Post-fix expected: anon `SELECT` → `200`
   with `[]` body, anon `INSERT` → `401` (insufficient_privilege).

   ```bash
   for env in dev prd; do
     URL=$(doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c "$env" --plain)
     ANON=$(doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c "$env" --plain)
     echo "=== $env ==="
     # SELECT: must be 200 with body == "[]" (RLS hides rows, table-level
     # GRANT to anon is preserved so PostgREST returns 200 not 401).
     # See knowledge-base/project/learnings/integration-issues/2026-04-07-supabase-postgrest-anon-key-schema-listing-401.md
     SELECT_OUT=$(curl -sS -w "\n%{http_code}" \
       -H "apikey: $ANON" -H "Authorization: Bearer $ANON" \
       "$URL/rest/v1/_schema_migrations?select=filename&limit=1")
     SELECT_BODY=$(echo "$SELECT_OUT" | head -n -1)
     SELECT_CODE=$(echo "$SELECT_OUT" | tail -n 1)
     echo "anon SELECT: status=$SELECT_CODE body=$SELECT_BODY"
     [[ "$SELECT_CODE" == "200" && "$SELECT_BODY" == "[]" ]] || \
       echo "  FAIL: expected 200 with []; lint NOT cleared"

     # INSERT: must be 401 (PostgREST maps PG 42501 insufficient_privilege
     # → 401 for the anon role per docs/references/errors.md).
     INSERT_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
       -X POST -H "apikey: $ANON" -H "Authorization: Bearer $ANON" \
       -H "Content-Type: application/json" -d '{"filename":"probe.sql"}' \
       "$URL/rest/v1/_schema_migrations")
     echo "anon INSERT: status=$INSERT_CODE"
     [[ "$INSERT_CODE" == "401" || "$INSERT_CODE" == "403" ]] || \
       echo "  FAIL: expected 401/403; lint NOT cleared"
   done
   ```
   <!-- verified: 2026-05-06 source: live curl against mlwiodleouzwniehynfz.supabase.co + /postgrest/postgrest docs/references/errors.md -->

   If `INSERT` accidentally returns `201` after the migration applies, the
   migration did NOT take effect (or a permissive policy was added). Halt
   the rollout and investigate before closing the issue.
4. **Re-fetch the Supabase advisor lint list** for both projects and confirm `rls_disabled_in_public` is no longer present. (Use the Supabase MCP `list_advisors` once authenticated, or the dashboard's Advisors tab.)
5. **Close the tracking issue** with a link to the verification output.

## Files to Edit

(None — this is an additive migration only.)

## Files to Create

- `apps/web-platform/supabase/migrations/038_rls_schema_migrations.sql`

## Implementation

The migration body (final form, ~25 lines including comments):

```sql
-- 038_rls_schema_migrations.sql
-- Clear Supabase advisor lint `rls_disabled_in_public` on
-- public._schema_migrations (alert dated 2026-05-03 on soleur-dev,
-- project ref mlwiodleouzwniehynfz).
--
-- Pre-fix exposure (verified live with anon key on 2026-05-06):
--   - anon SELECT: 200 OK with all 40 migration filenames
--   - anon INSERT: 201 Created (arbitrary filename accepted)
--   - anon DELETE: 204 No Content (matched rows removed)
-- A malicious DELETE would force the runner to re-attempt an applied
-- migration; many migrations are not idempotent (`CREATE TABLE`
-- without IF NOT EXISTS, ALTER TABLE ADD COLUMN), so this is a
-- direct prd-deploy DoS vector available to any internet user with
-- the public Soleur URL.
--
-- Fix pattern: enable RLS, zero policies. Matches migration 030
-- (processed_stripe_events) for service-role-only tables.
--   - The migration runner (apps/web-platform/scripts/run-migrations.sh)
--     uses psql over DATABASE_URL, which connects as the postgres role
--     and is RLS-exempt. No runner change required.
--   - Service-role HTTP clients bypass RLS via the Authorization
--     header (no application code reads this table; verified by
--     `rg "_schema_migrations" apps/ plugins/ scripts/`).
--   - anon and authenticated roles are denied by default once RLS is
--     on with zero policies — both reads and writes return empty/403.
--
-- Forward-only. Rollback path: `ALTER TABLE public._schema_migrations
-- DISABLE ROW LEVEL SECURITY;` — re-exposes the lint surface, do NOT
-- run unprompted.
--
-- CONCURRENTLY / VACUUM / ALTER SYSTEM are not used; the migration
-- is transaction-safe per the Supabase migration runner contract
-- (see comments in 025, 027, 028, 029, 035).
--
-- DO NOT add `ALTER TABLE ... FORCE ROW LEVEL SECURITY`. The runner
-- (apps/web-platform/scripts/run-migrations.sh) connects as the
-- `postgres` role, which OWNS this table. Postgres docs: row
-- security policies do not apply to the table owner unless FORCE
-- is set. FORCE would break the runner's INSERT at line 104/139.
--
-- DO NOT add a permissive SELECT policy for `anon`. Per learning
-- knowledge-base/project/learnings/security-issues/rls-column-takeover-github-username-20260407.md,
-- permissive RLS is row-level (not column-level) — a single permissive
-- policy would re-expose the entire migration history to any internet
-- user with the anon key, undoing this fix.

ALTER TABLE public._schema_migrations ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public._schema_migrations IS
  'Migration runner tracking table. Service-role-only / postgres-role-only '
  'access (no policies; RLS-empty for anon and authenticated roles). '
  'Written by apps/web-platform/scripts/run-migrations.sh via psql/'
  'DATABASE_URL as the postgres role, which OWNS the table and is '
  'therefore RLS-exempt by default (do not add FORCE ROW LEVEL '
  'SECURITY — it would break the runner). See migration 038.';
```

### Why no policies (and why that matches a documented precedent)

Migration 030 (`processed_stripe_events`) sets the exact precedent:

> Defense in depth: enable RLS with zero policies. Service-role
> bypasses RLS via the Authorization header; anon and authenticated
> clients are denied by default. This protects against a future
> misconfig that exposes the table through PostgREST without us
> noticing.

`_schema_migrations` shares the same access profile (no application
code reads it; only the runner writes it via `psql`).

### Why no `SECURITY DEFINER` function is needed

The `cq-pg-security-definer-search-path-pin-pg-temp` rule applies to
any new `SECURITY DEFINER` function. This migration adds none; it is
DDL-only (`ALTER TABLE` + `COMMENT`). The rule does not apply.

### Why no PostgREST grant changes are needed

PostgREST's exposure is driven by table-level `GRANT` to the `anon`
role; RLS sits in front of those grants and short-circuits the
result-set. We do not revoke the grants because that would
invalidate any future read-only policy we might add and is more
invasive than the lint requires. RLS-with-zero-policies is the
minimum viable fix that clears the lint AND matches the established
codebase pattern.

## Domain Review

**Domains relevant:** Engineering (CTO), Security (security-sentinel
will run at review).

### CTO

**Status:** carried forward from research notes (no separate Task
spawn — this is a 25-line additive migration with one in-repo
precedent).
**Assessment:** The fix is mechanically the smallest possible change
(one `ALTER TABLE`, one `COMMENT`), uses an established codebase
pattern (migration 030), and is provably runner-compatible (psql is
RLS-exempt). No architectural impact.

### Product/UX Gate

**Tier:** none (no user-facing surface). Skipped.

## Test Strategy

This is an infrastructure-only / DDL-only migration. There are NO
unit tests prescribed (per AGENTS.md `cq-write-failing-tests-before`
TDD-Gate exemption: "Infrastructure-only tasks (config, CI,
scaffolding) are exempt").

Verification is the live-probe sequence in the post-merge operator
checklist above. The probe is the test.

A future improvement would be a periodic CI job that runs the
Supabase advisor against both `dev` and `prd` projects and fails on
new lint hits — that is a separate enhancement and **out of scope**
for this PR. (Tracking: file a follow-up issue at ship time titled
`ci: nightly Supabase advisor lint scan against dev + prd`.)

## Risks

- **Runner regression** (false-alarm risk). The migration runner
  connects via `psql` as the `postgres` role (the database owner of
  `_schema_migrations`). Postgres docs: "Row security policies do
  not apply to the table owner unless `ALTER TABLE ... FORCE ROW
  LEVEL SECURITY` is set." This migration intentionally does NOT
  set `FORCE` — the runner relies on the owner-bypass behavior.
  Verified by reading `apps/web-platform/scripts/run-migrations.sh`
  lines 83/87/97/104/129/139.
  **Mitigation:** dev-rehearsal step in acceptance criteria runs
  the runner end-to-end before merge. Inline `COMMENT` warns future
  operators not to add `FORCE`.

- **Future application code adds an anon-key read of
  `_schema_migrations` and silently breaks.** Currently zero such
  reads exist (`rg "_schema_migrations" apps/ plugins/ scripts/`
  returns only the runner). **Mitigation:** the `COMMENT ON TABLE`
  inline documents the access pattern, so a future developer is
  warned. A read for legitimate purposes (e.g., a deploy-status
  endpoint) should use the service role, not the anon key.

- **Zero-policy pattern overuse.** This pattern is correct ONLY for
  tables with no anon/authenticated client access. For application
  tables, restrictive policies (per the constitution line 88 rule
  about RLS-enabled tables and auth/authz columns) are required.
  The plan does NOT apply zero-policy to any application table.

- **Permissive policy temptation.** A future maintainer might "fix"
  a perceived limitation by adding `CREATE POLICY "anon can read"
  ON public._schema_migrations FOR SELECT USING (true)`. Per
  learning `rls-column-takeover-github-username-20260407.md`,
  permissive RLS is row-level (not column-level) — such a policy
  would re-expose the entire migration filename history to any
  internet user with the anon key, undoing this fix.
  **Mitigation:** inline `COMMENT` explicitly warns; PR reviewers
  must reject any future migration that adds a policy here without
  a documented use case.

- **`SECURITY DEFINER` rule does NOT apply** (sharp-edge clarification
  to avoid review-time confusion). AGENTS.md
  `cq-pg-security-definer-search-path-pin-pg-temp` requires
  `SET search_path = public, pg_temp` and qualified relation names
  for new `SECURITY DEFINER` functions. This migration adds none —
  it is two DDL statements (`ALTER TABLE` + `COMMENT ON TABLE`).
  Reviewers can confirm the rule is N/A and move on.

## Out of Scope

- Adding policies to allow `anon` to read migration history (no app
  code needs this; would only re-expose the schema-disclosure surface).
- Auditing other Supabase advisor lints beyond `rls_disabled_in_public`
  (file a separate ticket if any other lint fires).
- A CI job that runs Supabase advisors on every PR (file a follow-up
  issue at ship; nightly cadence is sufficient given the static
  schema-change rate).
- Migrating `_schema_migrations` to the modern Supabase canonical
  location `supabase_migrations.schema_migrations` (would require
  rewriting the entire migration runner; this plan only clears the
  lint without changing tracking-table location).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. This plan's section is fully populated;
  the threshold resolves to `single-user incident`.
- Do NOT remove RLS from `_schema_migrations` "to debug" — that
  reopens the prd-deploy DoS vector for the duration of the debug
  session. Use a service-role HTTP client or `psql` instead.
- If `dev` and `prd` ever resolve to the same Supabase project ref
  (per `hr-dev-prd-distinct-supabase-projects`), the dev rehearsal
  silently doubles as a prd apply. Verify distinct refs before the
  rehearsal step.
- The advisor lint may take a few minutes to clear after the migration
  applies — Supabase advisors are scheduled, not realtime. Re-check
  the dashboard 5–15 min after the prd apply if the post-merge probe
  passes but the dashboard still shows the alert.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no
open issues touching `apps/web-platform/supabase/migrations/` paths
at planning time.
