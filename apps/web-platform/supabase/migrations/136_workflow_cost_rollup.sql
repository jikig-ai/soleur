-- 136_workflow_cost_rollup.sql
-- Per-workflow partition of the SAME month-to-date predicate `sum_user_mtd_cost`
-- (mig 027) sums, PLUS the grand total, from ONE statement.
--
-- SINGLE-SNAPSHOT INVARIANT (load-bearing). ROLLUP returns the per-bucket rows and
-- the grand-total row from one statement, therefore one MVCC snapshot. Two RPCs
-- would be two snapshots, and `increment_conversation_cost` fires on every turn --
-- an increment landing between them makes the parts genuinely not sum, under a UI
-- that promises the numbers match to the cent. This is why the total is returned
-- here rather than read alongside from `sum_user_mtd_cost`.
--
-- `since` is a PARAMETER, never date_trunc of the current month in the body: a
-- request crossing the month rollover must not get two different windows.
--
-- The bucket expression is named ONCE in the derived table. An earlier draft
-- inlined it in four places (select list, two GROUPING() calls, the grouping
-- clause); that is where a later edit silently misbuckets real money, because one
-- copy drifts and GROUPING() over a non-identical expression errors or groups
-- differently.
--
-- `bucket IS NULL` on the super-aggregate row is produced by ROLLUP itself. That is
-- unambiguous ONLY because the CASE can never return NULL -- its `IS NULL` arm is
-- first and returns 'legacy'. `is_total` is returned as the EXPLICIT signal anyway,
-- so no caller has to rely on that reasoning.
--
-- SENTINEL NORMALISATION. `__unrouted__` is a storage-layer detail that
-- `server/conversation-routing.ts` documents as "must never leak past this module",
-- with `test/conversation-routing.test.ts` pinning that its constant is not
-- exported. This function emits neutral keys -- 'legacy' and 'unrouted' -- so no
-- `__`-prefixed sentinel crosses into TS. The literal below is the one controlled
-- violation of that rule and is pinned by the migration-shape test.
--
-- No index is created, so the no-CONCURRENTLY convention is satisfied vacuously.
-- `idx_conversations_user_cost` does not include `active_workflow`, so this
-- aggregate takes a heap fetch over one user's costed conversations for one month.
--
-- CORRECTED AT REVIEW. This previously justified that as "the index write would
-- land on every turn forever". It ALREADY does. `increment_conversation_cost`
-- (042_increment_conversation_cost_v2.sql) UPDATEs `total_cost_usd` on every turn,
-- and that column is BOTH an INCLUDE column of `idx_conversations_user_cost` and
-- its partial-index predicate (`WHERE total_cost_usd > 0`) -- a predicate column
-- blocks HOT, so a fresh index tuple is written per turn today. The marginal cost
-- of adding `active_workflow` is index TUPLE WIDTH (~21 bytes worst case; one
-- null-bitmap bit in the common NULL case), not a new write. The decision to omit
-- it still stands on YAGNI -- the read is bounded to one user and one month, 10-100
-- rows for a realistic user -- but the original reasoning overstated the saving and
-- would have misled whoever reconsidered it next.
--
-- NOTE there are TWO migrations numbered 041 -- cite the filename, not the number.
-- FORWARD-ONLY; rollback in the paired .down.sql.

CREATE OR REPLACE FUNCTION public.sum_user_mtd_cost_by_workflow(
  uid   UUID,
  since TIMESTAMPTZ
) RETURNS TABLE(bucket TEXT, total NUMERIC, n INTEGER, is_total BOOLEAN)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
  SELECT b.bucket::TEXT                    AS bucket,
         COALESCE(SUM(b.cost), 0)::NUMERIC AS total,
         COUNT(*)::INTEGER                 AS n,
         GROUPING(b.bucket) = 1            AS is_total
    FROM (
      SELECT CASE
               WHEN c.active_workflow IS NULL          THEN 'legacy'
               WHEN c.active_workflow = '__unrouted__' THEN 'unrouted'
               ELSE c.active_workflow
             END              AS bucket,
             c.total_cost_usd AS cost
        FROM public.conversations c
       WHERE c.user_id = uid
         AND c.total_cost_usd > 0
         AND c.created_at >= since
    ) b
   GROUP BY ROLLUP (b.bucket)
   ORDER BY GROUPING(b.bucket) DESC, 2 DESC, 1 ASC;
$$;

COMMENT ON FUNCTION public.sum_user_mtd_cost_by_workflow(UUID, TIMESTAMPTZ) IS
  'Service-role-only per-workflow MTD cost partition for the BYOK usage dashboard. '
  'The is_total row is the grand total from the SAME statement - do not read the '
  'headline from a second query. End users MUST NOT call this directly; '
  'see server/api-usage.ts. Issue #1055.';

REVOKE EXECUTE ON FUNCTION public.sum_user_mtd_cost_by_workflow(UUID, TIMESTAMPTZ) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sum_user_mtd_cost_by_workflow(UUID, TIMESTAMPTZ) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.sum_user_mtd_cost_by_workflow(UUID, TIMESTAMPTZ) FROM anon;
GRANT  EXECUTE ON FUNCTION public.sum_user_mtd_cost_by_workflow(UUID, TIMESTAMPTZ) TO   service_role;

-- Inline correctness fix (CTO R6, rf-review-finding-default-fix-inline). NOTE: this
-- repin is UNENFORCEABLE on its own -- `test/migration-rpc-grants.test.ts`'s
-- LEGACY_SEARCH_PATH_NO_PG_TEMP set still names `sum_user_mtd_cost`, and the gate
-- short-circuits on membership. That entry is removed in the same PR (see Files to
-- Edit); without it a future migration could silently un-pin pg_temp again. Migration
-- 027 predates cq-pg-security-definer-search-path-pin-pg-temp and pins
-- `SET search_path = public` with no `pg_temp`. Shipping a correct sibling beside an
-- incorrect original reads as intentional to the next reviewer. Signature and return
-- type are IDENTICAL to 027 (verified against the live catalog: owner postgres,
-- proacl {postgres=X/postgres,service_role=X/postgres}) so CREATE OR REPLACE is valid
-- and preserves the existing ACL; body verbatim, search_path only.
CREATE OR REPLACE FUNCTION public.sum_user_mtd_cost(uid UUID, since TIMESTAMPTZ)
RETURNS TABLE(total NUMERIC, n INTEGER)
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp STABLE
AS $$
  SELECT COALESCE(SUM(total_cost_usd), 0)::NUMERIC AS total,
         COUNT(*)::INTEGER                          AS n
    FROM public.conversations
   WHERE user_id = uid AND total_cost_usd > 0 AND created_at >= since;
$$;

-- The REVOKE trio is NOT redundant with 027's, and omitting it here was a real
-- security gap (caught at review). 027's own header states the rule: "on FIRST
-- create Postgres grants EXECUTE to PUBLIC by default. The REVOKE statements
-- below MUST run on every apply -- treating them as 'cleanup' after the CREATE
-- is a real security gap."
--
-- 136 is now a SECOND file that can create this function. CREATE OR REPLACE
-- preserves the ACL only when the function already exists; on any apply where
-- it is ABSENT -- a `db reset` against a squashed baseline postdating 027, a
-- fresh project bootstrapped from `db diff` output, or a DROP FUNCTION during
-- incident recovery followed by forward-only replay -- the REPLACE becomes a
-- first CREATE and PUBLIC gets EXECUTE on a function returning any user's
-- month-to-date spend.
--
-- A live `proacl` read cannot catch this: it can only be taken on a database
-- where 027 has already applied, which is precisely the state in which the
-- omission is invisible.
-- Re-issued for the SAME reason as the REVOKE trio below: on a first CREATE
-- there is no prior COMMENT to preserve, and 027's is lost precisely in the
-- scenario that block exists for. Text is 027's verbatim.
COMMENT ON FUNCTION public.sum_user_mtd_cost(UUID, TIMESTAMPTZ) IS
  'Service-role-only MTD cost aggregate for the BYOK usage dashboard. '
  'End users MUST NOT call this directly; see server/api-usage.ts. '
  'Issue #2478.';

REVOKE EXECUTE ON FUNCTION public.sum_user_mtd_cost(UUID, TIMESTAMPTZ) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sum_user_mtd_cost(UUID, TIMESTAMPTZ) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.sum_user_mtd_cost(UUID, TIMESTAMPTZ) FROM anon;
GRANT  EXECUTE ON FUNCTION public.sum_user_mtd_cost(UUID, TIMESTAMPTZ) TO   service_role;
