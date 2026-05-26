DROP TRIGGER IF EXISTS trg_flag_flip_audit_no_update ON public.flag_flip_audit;
DROP TRIGGER IF EXISTS trg_flag_flip_audit_no_delete ON public.flag_flip_audit;
DROP FUNCTION IF EXISTS public.flag_flip_audit_no_update();
DROP FUNCTION IF EXISTS public.flag_flip_audit_no_delete();
DROP FUNCTION IF EXISTS public.audit_flag_flip(text,text,text,text,bool,bool,text);
DROP TABLE IF EXISTS public.flag_flip_audit;
