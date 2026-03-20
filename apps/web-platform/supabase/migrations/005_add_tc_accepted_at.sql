-- Add T&C acceptance timestamp to users table
-- NULL means user signed up before clickwrap was introduced (grandfathered)
alter table public.users
  add column tc_accepted_at timestamptz;

comment on column public.users.tc_accepted_at is
  'Timestamp when user accepted T&C via clickwrap checkbox. NULL = signed up before clickwrap was introduced.';

-- Update handle_new_user() to record T&C acceptance from signup metadata
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.users (id, email, workspace_path, tc_accepted_at)
  values (
    new.id,
    new.email,
    '/workspaces/' || new.id::text,
    case
      when (new.raw_user_meta_data->>'tc_accepted')::boolean = true
      then now()
      else null
    end
  );
  return new;
end;
$$ language plpgsql security definer;
