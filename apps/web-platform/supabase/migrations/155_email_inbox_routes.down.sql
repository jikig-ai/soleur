-- 155_email_inbox_routes.down.sql
-- Reverts mig 155. Routes are configuration (no correspondent data, no
-- statutory evidence), so dropping the table loses no user data; every address
-- reverts to the env-pinned EMAIL_TRIAGE_OWNER_USER_ID fallback.

DROP TABLE IF EXISTS public.email_inbox_routes;
