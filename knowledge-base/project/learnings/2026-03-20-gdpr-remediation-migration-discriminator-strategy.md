# Learning: GDPR data remediation -- metadata discriminator over timestamp proximity

## Problem

PR #898 introduced a fallback INSERT in the auth callback (`callback/route.ts`) that unconditionally set `tc_accepted_at = now()` for every new user, regardless of whether they actually accepted T&C. PR #927 fixed the code, but rows created during the 3-hour bug window (2026-03-20 14:07 to 17:28 UTC) already had fabricated consent timestamps. These false records violate GDPR Article 7(1), which requires the controller to demonstrate that consent was actually given.

The initial approach considered using timestamp proximity as the discriminator -- flagging rows where `tc_accepted_at` and `created_at` were within seconds of each other. This would have produced false positives: legitimate trigger-path users who genuinely accepted T&C also have both timestamps set to `now()` at INSERT time, making the two cases indistinguishable by timestamp alone.

## Solution

Migration `007_remediate_fabricated_tc_accepted_at.sql` uses `auth.users.raw_user_meta_data->>'tc_accepted'` as the authoritative ground truth. The migration joins `public.users` with `auth.users` and nulls `tc_accepted_at` only where the metadata does not confirm acceptance:

```sql
UPDATE public.users
SET tc_accepted_at = NULL
FROM auth.users a
WHERE public.users.id = a.id
  AND public.users.tc_accepted_at IS NOT NULL
  AND (a.raw_user_meta_data->>'tc_accepted') IS DISTINCT FROM 'true';
```

Key implementation decisions:

1. **`IS DISTINCT FROM` over `!=`** -- SQL three-valued logic means `NULL != 'true'` evaluates to `NULL`, not `TRUE`. `IS DISTINCT FROM` treats NULL as a concrete value, correctly catching both absent keys and non-`'true'` values without a separate `IS NULL` branch.

2. **DO block with `GET DIAGNOSTICS` + `RAISE NOTICE`** -- A bare UPDATE does not report its row count in migration output. The simplicity review recommended dropping the DO block, but the GDPR acceptance criteria required an auditable execution record. The DO block logs `[007] Remediated N row(s)` to Supabase's Postgres logs, providing evidence of the controller's corrective action.

3. **PII removed from dry-run query** -- The initial commented-out dry-run SELECT included `u.email`. Security review caught this: migration files are committed to the repo, and even commented SQL that selects PII creates a pattern that could be copy-pasted into production queries. The email column was removed.

4. **Irreversible by design** -- No down migration. Restoring fabricated timestamps would re-create false consent evidence, increasing liability rather than reducing it.

## Key Insight

When remediating data corruption from a code path that wrote incorrect values, always look for a source-of-truth field that distinguishes legitimate from fabricated records. Timestamp proximity, creation order, and other temporal heuristics are tempting but produce false positives when the legitimate and illegitimate paths share the same timing characteristics.

The general pattern: if a trigger and a fallback both write the same field at INSERT time, timestamps cannot distinguish which path fired. Only a field that captures the *input condition* (here, whether the user actually checked the T&C checkbox) can serve as a reliable discriminator.

A secondary insight: GDPR remediation migrations need an audit trail baked into the migration itself, not just in the PR description. Regulators examine database logs, not GitHub PRs. `RAISE NOTICE` in a DO block provides this without external dependencies.

A third insight: commented-out SQL in migration files is still code surface. PII in comments (emails, names, IDs) creates a pattern for future copy-paste. Dry-run queries should select only structural columns (IDs, timestamps, metadata flags), never identifying information.

## Session Errors

1. **`npx vitest run` failed with MODULE_NOT_FOUND for rolldown native binding** -- Pre-existing issue where `npx` resolves to a cached version that expects a platform-specific native binary not present in the worktree's `node_modules`. This is a known bare-repo worktree artifact, not caused by this migration. Workaround: use `bun test` or run `npm install` in the worktree to create a local `node_modules`.

2. **`gh issue create` failed with 'security' label not found** -- The first attempt to file issue #943 (client-writable metadata concern) used a `security` label that did not exist in the repo. Fix: omitted the label and added the security context to the issue body instead. Lesson: verify label existence with `gh label list` before using labels in issue creation.

## Related

- `knowledge-base/project/learnings/2026-03-20-supabase-trigger-fallback-parity.md` -- The learning from PR #927 that fixed the root cause. Documents the trigger/fallback conditional parity rule that, when violated, created the data this migration remediates.
- `knowledge-base/project/learnings/2026-03-20-supabase-column-level-grant-override.md` -- Migration 006 that locked down `tc_accepted_at` against client-side UPDATE. Same column, same compliance chain.
- `knowledge-base/project/learnings/2026-03-20-supabase-trigger-boolean-cast-safety.md` -- The `::boolean` cast vulnerability in the original trigger. Same `raw_user_meta_data->>'tc_accepted'` field, same text-comparison pattern.
- `knowledge-base/project/learnings/2026-03-20-supabase-signinwithotp-creates-users.md` -- Another path that creates users without T&C acceptance, fixed with `shouldCreateUser: false`.
- `knowledge-base/project/learnings/2026-02-21-gdpr-article-30-compliance-audit-pattern.md` -- GDPR audit pattern for this repo's dual-location legal documents.
- Issue #934: This remediation task.
- Issue #925: The original bug report.
- Issue #943: Pre-existing client-writable metadata concern discovered during this session's security review.
- PR #927: The code fix for the fallback INSERT.
- PR #898: The original PR that introduced the bug.
- Migration file: `apps/web-platform/supabase/migrations/007_remediate_fabricated_tc_accepted_at.sql`

## Tags

category: data-remediation
module: web-platform/supabase-migrations
