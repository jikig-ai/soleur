# Learning: "tenant-integration breakage on main" was test-correctness + shared-dev grant drift, not a code regression

## Problem

Running the opt-in tenant-integration suite (`TENANT_INTEGRATION_TEST=1` /
`SUPABASE_DEV_INTEGRATION=1`) against the **shared dev** Supabase project
failed 7–16 tests with run-to-run variance. CI was green the whole time
(these suites are opt-in and never run in CI). Framed as "a breakage on main."

## Root cause — three independent causes, none a production code regression

1. **Latent test bug (deterministic).** `conversation-visibility.tenant-isolation.test.ts`
   asserted the non-owner RPC raises `P0001`, but migration 075 has ALWAYS
   raised `USING ERRCODE = 'insufficient_privilege'` → SQLSTATE **42501**.
   `P0001` is the *default* `RAISE EXCEPTION` code; an explicit `USING ERRCODE`
   overrides it. The assertion was wrong since the migration+test landed in the
   same commit (#4521) and stayed hidden because the suite is opt-in.

2. **Shared-dev grant state diverges from the migration files (deterministic).**
   Migration 075's `REVOKE UPDATE(visibility) ON conversations FROM authenticated`
   is a **no-op on a real Supabase project**: Supabase's blanket
   `GRANT ALL ON public.<table> TO anon, authenticated` subsumes the narrower
   column REVOKE. Read-only catalog introspection confirmed `authenticated` AND
   `anon` retain UPDATE on `conversations.visibility` on BOTH dev and prd. The
   enforced write guard is the RLS policy `conversations_owner_update`
   (`user_id = auth.uid()`), not the REVOKE — so the security impact is nil (a
   user can only change their own conversation's visibility either way), but a
   test asserting the column REVOKE cannot pass against any real project.

3. **GoTrue rate limits / transient "Database error deleting user" (flaky).**
   The suites mass-create/sign-in/delete synthetic users; under batch load they
   trip per-IP/per-email rate limits and an opaque 500-class delete transient.
   This is the 7↔16 run-to-run variance.

The account-delete cascade (migs 065/066) was suspected but **verified correct
on both dev and prd** via read-only `pg_constraint`/`pg_proc` introspection:
`organizations.owner_user_id` and `audit_byok_use.founder_id` FKs are both
`ON DELETE SET NULL`, the WORM carve-out function is present, and
`set_conversation_visibility` is SECURITY DEFINER. No GDPR Art-17 incident.

## Solution

- Fixed the stale assertion (`P0001` → `42501`).
- Reframed the column-REVOKE test to assert the **RLS-effective** contract
  (owner CAN write own; non-owner + anon CANNOT, proven by service-role
  read-back of the unchanged value) instead of the dead defense-in-depth REVOKE.
- Added `test/helpers/gotrue-retry.ts` (`withGoTrueRetry` + grounded
  `isRetryableGoTrueError`, unit-tested) and wrapped the synthetic-user
  create/sign-in/delete sites; documented the dedicated-project requirement in
  `test/README.md`.
- Recorded the column-REVOKE no-op as a `SOLEUR-DEBT` marker.

## Key Insights

- **Integration tests against the shared dev project must assert RLS-EFFECTIVE
  behavior, not raw column grants.** Shared dev accumulates manual dashboard
  state, and Supabase's blanket table GRANT silently subsumes targeted column
  REVOKEs. Prove deny via service-role read-back of the unchanged value (dual
  shape: a 42501 error OR a 0-row match are both correct RLS denies), never via
  an assertion on a column privilege a clean-migration replica would have.
- **Behavioral integration suites need a DEDICATED, freshly-migrated project**
  (the repo already says so in `test/supabase-migrations/079-*.test.ts`). The
  shared dev project's grant/trigger/FK enforcement state is not a faithful
  replica of the migration files.
- **An applied migration file is byte-frozen.** The dev-migration-drift probe
  compares the dev/prd `_schema_migrations.content_sha` (git blob SHA-1 captured
  at apply time) against `origin/main`'s blob. ANY byte change to an applied
  migration — *including comments* — diverges the hash and raises a standing
  content-drift warning requiring a prod ledger reconciliation. Put debt
  markers / explanatory notes in the consuming artifact (here: the test), NEVER
  in the applied migration. The plan prescribed a "comment-only edit to mig
  075" — that assumption was wrong and had to be reverted.
- **Opt-in suites that never run in CI accumulate latent-wrong assertions.** The
  `P0001` bug survived from day one. When touching such a suite, run it against
  live dev and treat every deterministic failure as a real signal.

## Session Errors

1. **Plan prescribed editing applied migration 075's comment; it trips the
   content_sha drift probe.** — Recovery: reverted mig 075 to byte-identical,
   relocated the `SOLEUR-DEBT` marker to the reframed test's AC8 comment block.
   — Prevention: applied migrations are immutable down to bytes; debt markers
   and notes go in the consuming source, not the migration. (Routed to the work
   skill's migration guidance.)
2. **Edit-before-Read on mig 075** (read in a sibling worktree, not this one). —
   Recovery: Read then Edit. — Prevention: the Read requirement is per-worktree;
   re-Read after switching worktrees.
3. **`node` probe run from `/tmp` failed `ERR_MODULE_NOT_FOUND`.** — Recovery:
   ran the script from `apps/web-platform` so node_modules resolves. — Prevention:
   ad-hoc node scripts must live under the package whose deps they import.
4. **`npm install pg --no-save` pruned node_modules and the restoring
   `npm install` dirtied `package-lock.json` in a SIBLING worktree.** — Recovery:
   `git checkout -- package-lock.json`. — Prevention: run transient/`--no-save`
   installs in a throwaway dir or the worktree you own, and restore the lockfile
   before leaving; better, use a read-only introspection path that needs no new
   dep.
5. **Two-dot `git diff origin/main` after `git fetch` showed sibling
   feature-tweet files as deletions.** — Recovery: confirmed via `git status` +
   three-dot `origin/main...HEAD` that my working tree never touched them
   (stale-ref artifact: origin/main advanced past the branch point). — Prevention:
   use three-dot / `git status` for "what did I change," never two-dot vs a
   moved ref (already documented in the review diff-direction learning).

## Tags
category: integration-issues
module: apps/web-platform/test
