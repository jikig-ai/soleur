-- 155_email_inbox_routes.down.sql
-- Reverts mig 155. Routes are configuration (no correspondent data, no
-- statutory evidence), so dropping the table loses no user data; every address
-- reverts to the env-pinned EMAIL_TRIAGE_OWNER_USER_ID fallback.
--
-- ORDER: roll back the CODE first, or accept that the resolver's routes lookup
-- fails (PGRST205) until it is. That failure degrades to the env owner and is
-- reported to Sentry (op route-degraded); it does not lose mail.

DROP TABLE IF EXISTS public.email_inbox_routes;
