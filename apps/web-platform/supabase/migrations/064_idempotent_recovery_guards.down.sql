-- 064_idempotent_recovery_guards.down.sql
-- Manual rollback for 064_idempotent_recovery_guards.sql. Down files are
-- NOT auto-applied by run-migrations.sh — operator only.
--
-- Each forward block is a guarded re-create (IF NOT EXISTS in pg_policies
-- / pg_constraint). A "down" of a guarded re-create is the inverse: if
-- the construct exists AND was not created by an earlier mig (058/060),
-- drop it. In practice, mig 064 only creates these objects when 058/060
-- partially applied; rolling back is equivalent to re-introducing the
-- partial-apply state, which is rarely what operators want.
--
-- This down file is a no-op by design. The forward mig is idempotent;
-- "rolling back" it has no meaningful semantics. Provided to satisfy the
-- paired-edit convention (every forward mig has a down sibling).

SELECT 'mig 064 down: intentional no-op (forward is idempotent; rolling back the guards is meaningless)' AS notice;
