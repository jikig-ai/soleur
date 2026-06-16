-- =====================================================================
-- 109_backfill_residual_personal_workspace_membership.down.sql
--
-- Intentional NO-OP. This migration is a pure data BACKFILL — it creates no
-- schema. The owner-membership rows it inserts are BYTE-IDENTICAL to the rows
-- the handle_new_user trigger (mig 091) creates for every organic signup, so
-- there is no marker distinguishing "backfilled" from "organic" rows. Deleting
-- by shape would strip legitimate owner memberships and re-break the ADR-044
-- resolver / owner-gate for real users — a far worse outcome than leaving the
-- canonical state in place.
--
-- The rows ARE the correct end state (every user owns their personal
-- workspace), so there is nothing to revert. Reverting ADR-044 entirely is the
-- job of the 053 down.sql (which drops the tables wholesale), not this backfill.
-- =====================================================================

-- (no-op)
SELECT 1;
