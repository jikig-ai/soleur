-- 175_tom4_shape_iv_client_grant_revokes.down.sql — restores the exact
-- pre-175 grant state (the default-era verb sets 174 materialized). Safe to
-- replay: every verb re-granted below was provably held pre-175.

DO $$ BEGIN IF to_regclass('public."denied_jti"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."denied_jti" TO anon, authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."dsar_export_audit_pii"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."dsar_export_audit_pii" TO anon, authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."mint_rate_window"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."mint_rate_window" TO anon, authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."pending_checkout_sessions"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."pending_checkout_sessions" TO anon, authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."tc_acceptances"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."tc_acceptances" TO anon, authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."tenant_deploy_audit"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."tenant_deploy_audit" TO anon, authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."workspace_member_actions"') IS NOT NULL THEN
    GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE public."workspace_member_actions" TO anon, authenticated;
END IF; END $$;
