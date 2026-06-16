-- 106_denied_jti_founder_cascade.down.sql
-- Revert denied_jti.founder_id FK back to ON DELETE RESTRICT (mig 037 state).
-- NOTE: any founders erased while CASCADE was active already had their
-- denied_jti rows removed; this only restores the constraint behaviour.

ALTER TABLE public.denied_jti
  DROP CONSTRAINT IF EXISTS denied_jti_founder_id_fkey;

ALTER TABLE public.denied_jti
  ADD CONSTRAINT denied_jti_founder_id_fkey
  FOREIGN KEY (founder_id) REFERENCES public.users(id) ON DELETE RESTRICT;
