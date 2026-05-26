-- 074_byok_delegation_acceptances.down.sql — reverse of 074.

DROP TRIGGER IF EXISTS byok_delegation_acceptances_no_delete ON public.byok_delegation_acceptances;
DROP TRIGGER IF EXISTS byok_delegation_acceptances_no_update ON public.byok_delegation_acceptances;
DROP FUNCTION IF EXISTS public.byok_delegation_acceptances_no_mutate();
DROP FUNCTION IF EXISTS public.anonymise_byok_delegation_acceptances(uuid);
DROP TABLE IF EXISTS public.byok_delegation_acceptances;
