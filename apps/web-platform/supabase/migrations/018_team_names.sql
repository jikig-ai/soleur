-- Custom names for domain leaders (FR1-FR7, TR1)
-- Users can assign friendly names to each of the 8 domain leaders.
-- Schema anticipates multi-user (workspace_id) but Phase 3 is user-level only.

create table public.team_names (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  leader_id text not null
    check (leader_id in ('cmo', 'cto', 'cfo', 'cpo', 'cro', 'coo', 'clo', 'cco')),
  custom_name text not null
    check (char_length(custom_name) between 1 and 30)
    check (custom_name ~ '^[a-zA-Z0-9 ]+$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, leader_id)
);

alter table public.team_names enable row level security;

create policy "Users can manage own team names"
  on public.team_names for all
  using (auth.uid() = user_id);

create index idx_team_names_user_id on public.team_names(user_id);

-- Add naming state columns to users table
-- naming_prompted_at: onboarding naming step shown (FR2)
-- nudges_dismissed: array of leader IDs whose contextual nudge was dismissed (FR3)
alter table public.users
  add column naming_prompted_at timestamptz,
  add column nudges_dismissed text[] not null default '{}';
