-- 175_tom4_shape_iv_client_grant_revokes.sql
--
-- check-tom4-rls-posture's assertion 8 codifies the DPA's TOM-4 shape-(iv)
-- promise: customer-data tables that carry zero RLS policies are
-- service-role-only — no client-held credential (anon/authenticated) reaches
-- them. Migration 174's catalog snapshot materialized default-era grants that
-- Supabase's platform had been attaching silently: seven shape-(iv) tables
-- hold anon+authenticated grants on prd today.
--
-- Those grants are INERT — every table below has zero policies for those
-- roles, so RLS already denies every read and write. Revoking them therefore
-- changes no observable behavior on prd (P1 holds): it removes privilege bits
-- that could never be exercised, and brings prd AND fresh replays into the
-- TOM-4 posture the DPA documents. Reproducing them verbatim was the wrong
-- default for exactly these seven relations; check 8 enforces the corrected
-- intent.
--
-- Per-relation revokes sit behind to_regclass preconditions, same convention
-- as 174. service_role grants are untouched — service-role-only is the
-- documented shape, not "no grants".

DO $$ BEGIN IF to_regclass('public."denied_jti"') IS NOT NULL THEN
    REVOKE ALL ON TABLE public."denied_jti" FROM anon, authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."dsar_export_audit_pii"') IS NOT NULL THEN
    REVOKE ALL ON TABLE public."dsar_export_audit_pii" FROM anon, authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."mint_rate_window"') IS NOT NULL THEN
    REVOKE ALL ON TABLE public."mint_rate_window" FROM anon, authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."pending_checkout_sessions"') IS NOT NULL THEN
    REVOKE ALL ON TABLE public."pending_checkout_sessions" FROM anon, authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."tc_acceptances"') IS NOT NULL THEN
    REVOKE ALL ON TABLE public."tc_acceptances" FROM anon, authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."tenant_deploy_audit"') IS NOT NULL THEN
    REVOKE ALL ON TABLE public."tenant_deploy_audit" FROM anon, authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."workspace_member_actions"') IS NOT NULL THEN
    REVOKE ALL ON TABLE public."workspace_member_actions" FROM anon, authenticated;
END IF; END $$;
