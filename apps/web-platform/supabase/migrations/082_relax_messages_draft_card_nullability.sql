-- 082: relax messages NOT NULL for user_id-routed draft action cards (#4579).
--
-- The nightly KB-drift walker (and the github/cfo sibling producers) persist a
-- "draft action card" row in messages that carries NO conversation_id/role/
-- content. messages required those NOT NULL since migration 001, so the insert
-- has never succeeded. This finishes the intent migration 046 documented but
-- never completed ("route via user_id — no conversation_id required") and
-- honors ADR-037 (messages stays the canonical draft-card row; no per-source
-- table).
--
-- LOCK/SAFETY: run-migrations.sh applies each file with `psql
-- --single-transaction`, so the ADD CONSTRAINT ... NOT VALID and VALIDATE
-- CONSTRAINT below run in ONE AccessExclusive-holding transaction → there is
-- no concurrent-write window between them, and the NOT VALID/VALIDATE split
-- defers no lock here (it is forward-portable only). Phase 0.2 of the plan
-- verified 0 pre-existing violators on prd (ifsccnjhymdmidffkzhl, 2026-05-29),
-- so VALIDATE cannot fail. NO CREATE INDEX CONCURRENTLY (forbidden inside the
-- transaction-wrapped runner — see migration 046).
--
-- DECISION A: template_id and workspace_id stay column-level NOT NULL; the
-- shared insertDraftCard helper supplies template_id='default_legacy' and
-- workspace_id=<founder solo workspace>. Only conversation_id/role/content are
-- relaxed (3 cols, smaller hot-table blast radius than 4).

ALTER TABLE public.messages ALTER COLUMN conversation_id DROP NOT NULL;
ALTER TABLE public.messages ALTER COLUMN role            DROP NOT NULL;
ALTER TABLE public.messages ALTER COLUMN content         DROP NOT NULL;

-- Discriminator: every row is EITHER a chat row OR a draft-card row.
-- The card branch intentionally EXCLUDES user_id: the GDPR Art. 17
-- anonymization cascade (migration 068) sets messages.user_id = NULL on
-- authored rows, so a user_id-anchored card branch would make an anonymized
-- card satisfy NEITHER branch (23514) and ABORT a Right-to-Erasure operation.
-- It also excludes workspace_id/template_id (kept column-level NOT NULL,
-- Decision A). Any FUTURE `DROP NOT NULL` on workspace_id or template_id MUST
-- add the dropped column to this CHECK.
-- Idempotent DROP+ADD (046:264 convention) — re-apply / ledger-drift recovery
-- must not 42710 on a DB where the constraint already exists.
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_row_kind_chk;
ALTER TABLE public.messages
  ADD CONSTRAINT messages_row_kind_chk CHECK (
    (conversation_id IS NOT NULL AND role IS NOT NULL AND content IS NOT NULL)
    OR
    (source IS NOT NULL AND owning_domain IS NOT NULL AND draft_preview IS NOT NULL)
  ) NOT VALID;
ALTER TABLE public.messages VALIDATE CONSTRAINT messages_row_kind_chk;

COMMENT ON CONSTRAINT messages_row_kind_chk ON public.messages IS
  'Discriminator: chat row (conversation_id+role+content) OR draft card '
  '(source+owning_domain+draft_preview). user_id excluded — Art.17 '
  'anonymization (068) nulls it on cards. Migration 082 finishes the '
  'mig-046 intent. See ADR-037 (canonical-by-filename; dedup design).';
