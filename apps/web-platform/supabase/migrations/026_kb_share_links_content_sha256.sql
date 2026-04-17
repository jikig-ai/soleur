-- 026_kb_share_links_content_sha256.sql
-- Bind KB share links to content, not path, to prevent token resurrection
-- after file delete/rename/overwrite. See issue #2326.
--
-- Pre-apply: run the REST probe documented in the runbook
-- (knowledge-base/engineering/ops/runbooks/supabase-migrations.md) to count
-- existing rows. If 0 rows, the defensive revoke below is a no-op. If >10
-- rows, pause and switch to a soft-legacy path (keep nullable, backfill job).
--
-- NOT NULL is deliberately NOT applied: we want revoked legacy rows to
-- retain audit metadata (token, user_id, document_path) with NULL hash.
-- Active (revoked = false) rows are still required to have a valid hash
-- via the CHECK constraint below, which is what actually prevents
-- resurrection. Do NOT backfill from current file bytes — that would
-- re-enable the very resurrection attack this migration prevents.

alter table public.kb_share_links
  add column content_sha256 text;

-- Revoke pre-existing rows. They predate the hash binding, so we cannot
-- trust their document_path → content mapping.
update public.kb_share_links
   set revoked = true
 where content_sha256 is null
   and revoked = false;

-- Active rows must carry a valid lowercase-hex SHA-256. Revoked rows may
-- retain NULL (no active view path can reach them — the route returns
-- 410 on revoked before any hash check).
alter table public.kb_share_links
  add constraint kb_share_links_content_sha256_format
    check (revoked = true or content_sha256 ~ '^[a-f0-9]{64}$');

-- One active share per (user_id, document_path). Without this, two
-- concurrent POSTs for the same (user, path) with a modified file can
-- both pass the existing-share check and both insert new rows, leaving
-- the older token as a dangling authorized link the user cannot see or
-- revoke via the UI — exactly the resurrection class this migration
-- closes. The POST handler catches the 23505 conflict and re-reads.
create unique index kb_share_links_one_active_per_doc
  on public.kb_share_links(user_id, document_path)
  where revoked = false;

-- Small index for future auditability (e.g. "how many share links point
-- at identical content?"). Not required for correctness.
create index idx_kb_share_links_content_sha256
  on public.kb_share_links(content_sha256);
