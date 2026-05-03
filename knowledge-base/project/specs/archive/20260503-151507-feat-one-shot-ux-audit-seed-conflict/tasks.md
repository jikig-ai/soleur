# Tasks: fix(ux-audit) seed conflict on partial unique index

Plan: `knowledge-base/project/plans/2026-05-03-fix-ux-audit-seed-conflict-plan.md`
Branch: `feat-one-shot-ux-audit-seed-conflict`
Issues: #2584, #2585 (referenced via `Ref #N`, closed post-merge)

## Phase 1 — Setup & migration

1.1 Create `apps/web-platform/supabase/migrations/035_conversations_user_id_session_id_unique_total.sql` with the swap DDL (drop partial 028 index, create non-partial unique index on `(user_id, session_id)`).
1.2 Verify the migration follows the `CONCURRENTLY`-forbidden pattern (no `CONCURRENTLY` keyword), with header comment citing 42P10 root cause + sibling precedent (025/027/028).
1.3 Add a one-line `-- Superseded by migration 035` breadcrumb at the top of `028_conversations_user_id_session_id_unique.sql` (no DDL changes — append-only contract).

## Phase 2 — Code update

2.1 Edit `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts` `upsertConversation()` comment block (lines 134-144). Reference migration 035, drop the partial-index narrative, keep the empty-`sessionId` guard.
2.2 Confirm the request shape (URL params, headers, body) is unchanged — only the comment changes.

## Phase 3 — Test (TDD)

3.1 Add the PostgREST inference contract test to `plugins/soleur/test/ux-audit/bot-fixture.test.ts` inside `describeIfCreds("bot-fixture (DB-only v1)", ...)`. Body must:
  - POST to `/rest/v1/conversations?on_conflict=user_id,session_id` with bogus `user_id` (FK should fail).
  - Assert response code is **not** `42P10`.
  - Clean up any inserted row if the FK somehow succeeded.
3.2 Run `bun test plugins/soleur/test/ux-audit/bot-fixture.test.ts` locally with Doppler `prd_scheduled` injected. The new test should be **RED** until migration 035 is applied to prd (verify the failure mode is exactly the 42P10 contract assertion firing).
3.3 (Apply migration 035 via Supabase migration runner — local against `dev` first if practical; otherwise rely on the migration runner in CI.)
3.4 Re-run the suite. Test should be **GREEN**.

## Phase 4 — Documentation + learning

4.1 Create `knowledge-base/project/learnings/integration-issues/<topic>.md` capturing:
  - 42P10 symptom + exact curl repro
  - Why PostgREST cannot infer ON CONFLICT against partial unique indexes
  - Why the prior plan's "no live probe required" assertion was wrong
  - Recovery: drop partial → create non-partial; NULLS DISTINCT default makes nullable columns safe in the conflict target

## Phase 5 — Compound + ship

5.1 Run `skill: soleur:compound` to capture learnings.
5.2 Run `skill: soleur:preflight` to validate migration shape and PR-body shape (the `Ref #` not `Closes #` enforcement is in preflight Check 6 / ship Phase 5.5 ops-remediation gate).
5.3 Run `skill: soleur:ship`. PR body must:
  - Reference `#2584` and `#2585` via `Ref` (not `Closes`).
  - Include a `## Changelog: fix` section.
  - Set semver:patch label.
  - Note the post-merge operator steps (apply verification, close #2584/#2585, run dispatch).

## Phase 6 — Post-merge (operator)

6.1 Verify migration 035 applied via Supabase Management API:
  - `select indexname from pg_indexes where indexname='uniq_conversations_user_id_session_id_total';` returns one row.
  - `select indexname from pg_indexes where indexname='uniq_conversations_user_id_session_id';` returns zero rows.
6.2 `gh workflow run scheduled-ux-audit.yml` then poll `gh run view <id> --json status,conclusion` until success.
6.3 Run the live repro curl from the plan's Acceptance Criteria → Post-merge section. Expected: `23503` (FK), not `42P10`.
6.4 `gh issue close 2584` and `gh issue close 2585` with verification comments linking to the dispatch run.
