-- 178_api_data_grants_narrowing.sql
--
-- #11193 — the deferred narrowing pass ADR-303 §Consequences names
-- explicitly: migration 174 reproduced prd's EFFECTIVE api-role privileges
-- verbatim (zero-prd-change by construction), so several relations still
-- hold default-era full-DML grants they never needed. This file revokes
-- them per-relation against the repo-census evidence below and re-grants
-- only what live consumers use. Unlike 174, this migration CHANGES prd: it
-- removes privilege bits — every retained verb traces to a live call site,
-- every revoked verb is provably inert (no client call site, or RLS already
-- denies the operation for the role).
--
-- Per-relation evidence (repo census re-run 2026-10-26 — every
-- .from('<rel>')/.rpc(...) call site classified by client binding:
-- cookie-bound SSR lib/supabase/server.ts, browser lib/supabase/client.ts,
-- tenant getFreshTenantClient, or service createServiceClient/getServiceClient):
--   _schema_migrations      — ZERO api-role clients: every reader/writer is a
--                             psql $DATABASE_URL script running as the
--                             postgres role (run-migrations.sh,
--                             dev-ledger-parity*, dev-ledger-reconcile.sh,
--                             preflight-schema-vs-ledger.sh, the CI drift
--                             probe). Revoked from all three api roles.
--   api_keys                — authenticated SELECT only: byok-lease.ts,
--                             codex-credential-provider.ts, agent-runner.ts
--                             (tenant client), GET /api/services (cookie).
--                             All writes are service-client.
--   audit_byok_use          — authenticated SELECT only: dashboard/audit,
--                             GET /api/dashboard/today/[id]/cost (cookie).
--                             Writes via write_byok_audit +
--                             record_byok_use_and_check_cap +
--                             check_and_record_byok_delegation_use — all
--                             SECURITY DEFINER.
--   audit_github_token_use  — authenticated SELECT only: dashboard/audit/github
--                             (cookie). Writes via record_github_token_use
--                             (definer, called over service client).
--   dsar_export_jobs        — authenticated SELECT only: settings/privacy page
--                             + /api/account/export/[jobId]/* (cookie). GDPR
--                             data-portability surface — the SELECT is a
--                             must-keep. Writes via server/dsar-export.ts +
--                             server/account-delete.ts (service).
--   flag_flip_audit         — no client readers at all; writes only via
--                             audit_flag_flip (definer, EXECUTE granted to
--                             service_role). service_role keeps full grants
--                             per the 175 service-role-only convention.
--   users                   — authenticated SELECT (middleware post-auth,
--                             identity, dashboard, API routes) plus UPDATE on
--                             a censused column set only: email (migration
--                             006's original column grant, re-asserted here),
--                             onboarding_completed_at / pwa_banner_dismissed_at
--                             / runtime_explainer_dismissed_at (browser
--                             hooks/use-onboarding.ts updateUserField),
--                             nudges_dismissed (cookie /api/team-names).
--                             kb_sync_history is deliberately NOT in the set —
--                             017's RESTRICTIVE policy pins it and the write
--                             path moved to append_kb_sync_row (053 definer
--                             RPC) in server/session-sync.ts. All other users
--                             write sites are service-client; every RPC
--                             touching users (accept_terms,
--                             set_current_workspace_id,
--                             set_current_organization_id, handle_new_user
--                             trigger) is SECURITY DEFINER.
--
-- Per-relation revokes sit behind to_regclass preconditions (174/175
-- convention): an absent relation is skipped, not fatal. Inside each block
-- the REVOKE precedes any re-GRANT — the ordering is load-bearing: a later
-- REVOKE ALL would strip the re-grants (plan Guard Contract matrix row 5).
--
-- service_role is untouched everywhere EXCEPT _schema_migrations (the only
-- relation whose target is zero api-role grants). runtime_mint_intent (049)
-- and dsar_export_audit_pii (175) are already narrow — untouched.
--
-- On users, this restores migration 006's intent: authenticated holds SELECT
-- plus the column-level UPDATE census — no table-level UPDATE (the wart 174's
-- header documents is removed). Note: a table-level REVOKE ALL does not
-- clear column-level attacl entries, and the re-GRANT is idempotent either
-- way, so the post-state is deterministic regardless of what attacl held.

DO $$ BEGIN IF to_regclass('public."_schema_migrations"') IS NOT NULL THEN
    REVOKE ALL ON TABLE public."_schema_migrations" FROM anon, authenticated, service_role;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."api_keys"') IS NOT NULL THEN
    REVOKE ALL ON TABLE public."api_keys" FROM anon, authenticated;
    GRANT SELECT ON TABLE public."api_keys" TO authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."audit_byok_use"') IS NOT NULL THEN
    REVOKE ALL ON TABLE public."audit_byok_use" FROM anon, authenticated;
    GRANT SELECT ON TABLE public."audit_byok_use" TO authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."audit_github_token_use"') IS NOT NULL THEN
    REVOKE ALL ON TABLE public."audit_github_token_use" FROM anon, authenticated;
    GRANT SELECT ON TABLE public."audit_github_token_use" TO authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."dsar_export_jobs"') IS NOT NULL THEN
    REVOKE ALL ON TABLE public."dsar_export_jobs" FROM anon, authenticated;
    GRANT SELECT ON TABLE public."dsar_export_jobs" TO authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."flag_flip_audit"') IS NOT NULL THEN
    REVOKE ALL ON TABLE public."flag_flip_audit" FROM anon, authenticated;
END IF; END $$;

DO $$ BEGIN IF to_regclass('public."users"') IS NOT NULL THEN
    REVOKE ALL ON TABLE public."users" FROM anon;
    REVOKE ALL ON TABLE public."users" FROM authenticated;
    GRANT SELECT ON TABLE public."users" TO authenticated;
    GRANT UPDATE (email, onboarding_completed_at, pwa_banner_dismissed_at, runtime_explainer_dismissed_at, nudges_dismissed) ON TABLE public."users" TO authenticated;
END IF; END $$;
