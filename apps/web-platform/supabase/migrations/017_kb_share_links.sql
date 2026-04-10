-- KB share links: link-based read-only sharing of individual KB documents.
-- Stores token → document mappings with revocation support.
-- Public access uses service-role client, not anon RLS bypass.

create table public.kb_share_links (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  token text not null unique,
  document_path text not null,
  created_at timestamptz not null default now(),
  revoked boolean not null default false
);

alter table public.kb_share_links enable row level security;

-- Owner can read, create, and update (revoke) their own share links.
create policy "Users can manage own share links"
  on public.kb_share_links for all
  using (auth.uid() = user_id);

-- Indexes for fast lookups.
create index idx_kb_share_links_token on public.kb_share_links(token);
create index idx_kb_share_links_user_id on public.kb_share_links(user_id);
