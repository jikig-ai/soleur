-- 026_kb_share_links_content_sha256.sql
-- Bind KB share links to content, not path, to prevent token resurrection
-- after file delete/rename/overwrite. See issue #2326.
--
-- Pre-apply: run the REST probe documented in the runbook
-- (knowledge-base/engineering/ops/runbooks/supabase-migrations.md) to count
-- existing rows. If 0 rows, the defensive revoke below is a no-op. If >10
-- rows, pause and switch to a soft-legacy path (keep nullable, backfill job).

alter table public.kb_share_links
  add column content_sha256 text;

-- Existing rows have no hash. Mark them revoked so they cannot be
-- resurrected by a new file at the same path — users must re-create any
-- links they still want.
update public.kb_share_links
   set revoked = true
 where content_sha256 is null
   and revoked = false;

-- New rows MUST carry a hash.
alter table public.kb_share_links
  alter column content_sha256 set not null,
  add constraint kb_share_links_content_sha256_format
    check (content_sha256 ~ '^[a-f0-9]{64}$');

-- Small index for future auditability (e.g. "how many share links point
-- at identical content?"). Not required for correctness.
create index idx_kb_share_links_content_sha256
  on public.kb_share_links(content_sha256);
