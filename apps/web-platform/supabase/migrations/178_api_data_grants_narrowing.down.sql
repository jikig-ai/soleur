-- 178_api_data_grants_narrowing.down.sql — restores the exact pre-178 grant
-- state (the default-era verb sets 174 materialized). Safe to replay: every
-- verb re-granted below was provably held pre-178. Rollback machinery only —
-- this knowingly re-opens the default-era posture #11193 narrowed.

DO $$ BEGIN IF to_regclass('public."_schema_migrations"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."_schema_migrations" TO anon, authenticated, service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."api_keys"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."api_keys" TO anon, authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."audit_byok_use"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."audit_byok_use" TO anon, authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."audit_github_token_use"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."audit_github_token_use" TO anon, authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."dsar_export_jobs"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."dsar_export_jobs" TO anon, authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."flag_flip_audit"') IS NOT NULL THEN
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."flag_flip_audit" TO anon, authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."users"') IS NOT NULL THEN
    -- Column-level grants live in attacl, not relacl — they survive 178's
    -- table-level REVOKE and are NOT subsumed by the re-grant below (a
    -- redundant column grant under a held table-level verb is still a live
    -- ACL entry the fuzz gate's attacl sweep would flag). Drop them first so
    -- the restored state is exactly 174's recorded posture.
    REVOKE UPDATE (email, onboarding_completed_at, pwa_banner_dismissed_at, runtime_explainer_dismissed_at, nudges_dismissed) ON TABLE public."users" FROM authenticated;
    GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public."users" TO anon, authenticated;
END IF; END $$;
