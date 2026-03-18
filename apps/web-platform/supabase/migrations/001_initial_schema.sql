-- Initial schema for Soleur Web Platform
-- Tables: users, api_keys, conversations, messages
-- RLS enabled on all tables

-- Users table (extends Supabase auth.users)
create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  workspace_path text not null default '',
  workspace_status text not null default 'provisioning'
    check (workspace_status in ('provisioning', 'ready')),
  created_at timestamptz not null default now()
);

alter table public.users enable row level security;

create policy "Users can read own profile"
  on public.users for select
  using (auth.uid() = id);

create policy "Users can update own profile"
  on public.users for update
  using (auth.uid() = id);

-- API keys table (BYOK encrypted keys)
create table public.api_keys (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  encrypted_key bytea not null,
  provider text not null default 'anthropic'
    check (provider in ('anthropic', 'bedrock', 'vertex')),
  is_valid boolean not null default false,
  validated_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.api_keys enable row level security;

create policy "Users can manage own API keys"
  on public.api_keys for all
  using (auth.uid() = user_id);

create index idx_api_keys_user_id on public.api_keys(user_id);

-- Conversations table
create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  domain_leader text not null
    check (domain_leader in ('cmo', 'cto', 'cfo', 'cpo', 'cro', 'coo', 'clo', 'cco')),
  session_id text,
  status text not null default 'active'
    check (status in ('active', 'waiting_for_user', 'completed', 'failed')),
  last_active timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.conversations enable row level security;

create policy "Users can manage own conversations"
  on public.conversations for all
  using (auth.uid() = user_id);

create index idx_conversations_user_id on public.conversations(user_id);
create index idx_conversations_status on public.conversations(status);

-- Messages table
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null,
  tool_calls jsonb,
  created_at timestamptz not null default now()
);

alter table public.messages enable row level security;

create policy "Users can read own messages"
  on public.messages for select
  using (
    exists (
      select 1 from public.conversations c
      where c.id = conversation_id and c.user_id = auth.uid()
    )
  );

create policy "Users can insert own messages"
  on public.messages for insert
  with check (
    exists (
      select 1 from public.conversations c
      where c.id = conversation_id and c.user_id = auth.uid()
    )
  );

create index idx_messages_conversation_created
  on public.messages(conversation_id, created_at);

-- Function to auto-create user profile on signup
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.users (id, email, workspace_path)
  values (
    new.id,
    new.email,
    '/workspaces/' || new.id::text
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
