-- 042_dsar_exports_storage_bucket.sql
-- feat-dsar-art15-export-endpoint Phase 1 (issue #3637, plan rev-2 TR2).
--
-- Private `dsar-exports` Storage bucket. Path layout:
--   dsar-exports/<userId>/<jobId>.zip
--
-- The first folder component is the owner user_id; folder-prefix RLS
-- restricts SELECT to objects whose `(storage.foldername(name))[1] =
-- auth.uid()::text` — mirrors the chat-attachments pattern in
-- migration 019. SELECT is the only operation a user-role can reach;
-- worker uploads, signed-URL issuance, and post-download deletion all
-- happen via service_role bypass.
--
-- Per ADR-028 §D4 + plan TR4: per-file size cap is 1024 MB by default;
-- operator may raise via dashboard / API for prd. Migrations should
-- NOT hard-code a project-level cap (Supabase plan tiers vary).

-- ============================================================================
-- 1. Create private bucket. Idempotent — re-applies safely.
-- ============================================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('dsar-exports', 'dsar-exports', false)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- 2. Folder-prefix RLS for SELECT.
--
-- Users can read only objects whose first folder component matches
-- their own user_id. Defense-in-depth against the (worker-side) bug
-- class where a signed URL points at a stale path: even if a signed
-- URL leaks, RLS would block a re-issuance under a different user's
-- session.
--
-- Per `2026-04-11-idor-via-storage-folder-prefix.md`: the
-- `(storage.foldername(name))[1]` extraction is the authoritative way
-- to derive the owner from the path; never use a route parameter or
-- request body for that derivation.
-- ============================================================================

CREATE POLICY "Users can read own dsar-exports objects"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'dsar-exports'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- No INSERT/UPDATE/DELETE policies: the worker (service_role) handles
-- all writes + the hard-delete-on-download flow + the TTL-expiry sweep.
