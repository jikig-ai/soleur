-- Down-migration for 115_worktree_write_lease.sql.
-- Drop the RPCs (all signatures) first, then the table. The member SELECT
-- policy drops with the table. No Storage/external resources to reverse.

drop function if exists public.release_worktree_lease(uuid, text, text, bigint);
drop function if exists public.touch_worktree_lease(uuid, text, text, bigint);
drop function if exists public.acquire_worktree_lease(uuid, text, text);

drop table if exists public.worktree_write_lease;
