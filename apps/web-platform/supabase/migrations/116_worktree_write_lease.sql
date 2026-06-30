-- Migration 116: worktree_write_lease — per-(workspace_id, worktree_id) write-lease
-- for the multi-host /workspaces layer (epic #5274, Phase 2, ADR-068 §2).
--
-- Mirrors the canonical acquire_conversation_slot fenced-upsert precedent
-- (029_plan_tier_and_concurrency_slots.sql:86-210, re-issued
-- 093_acquire_slot_workspace_id.sql:50-91) — NOT a new pattern. The
-- lease-specific adaptations over the slot precedent are: (a) a same-host /
-- cross-host CASE on DO UPDATE so a same-host re-acquire is idempotent
-- (keeps gen — the self-lockout fix), while a different host takes over only
-- past the 120s heartbeat expiry and bumps lease_generation in-statement; and
-- (b) touch/release match on lease_generation so a host learns when it lost.
--
-- LAWFUL_BASIS: legitimate interest (service operation — per-worktree write
-- coordination across hosts). Operational state only (host_id, generation,
-- timestamps); no special-category data (GDPR Art. 9 N/A).
--
-- Fencing (writer-side CAS at the git-data host) is a SEPARATE Phase-2 surface
-- (PR B) — this migration provides only the lease (the gen source). The lease
-- generation returned by acquire is the token a host presents to the git-data
-- host's pre-receive fence, which atomically rejects any write with
-- `gen < stored_max` (ADR-068 §3, the unmodified Kleppmann reject). That fence
-- requires `lease_generation` to be a GLOBALLY-MONOTONIC token PER
-- (workspace_id, worktree_id) that SURVIVES lock release — so release does NOT
-- delete the row (which would reset gen to the default on the next acquire and
-- invert the fence into a write outage). Instead release TOMBSTONES the row
-- (ages heartbeat_at to the distant past so the next acquire takes over
-- immediately) — see release_worktree_lease below. CTO ruling 2026-06-30
-- (ADR-068 §2/§3 amendment): the monotonic-token responsibility lives at the
-- lock service (here), never at the resource server (the fence stays a dumb
-- `gen < max` compare). The slot precedent (029 acquire_conversation_slot) was
-- ONLY a concurrency slot, never a fence token, so its DELETE-on-release was
-- correct there and silently wrong here — this is the one seam where the 1:1
-- mirror breaks.

create table if not exists public.worktree_write_lease (
  -- ON DELETE CASCADE (intentionally NOT the 059 workspace_id RESTRICT norm):
  -- the lease is operational state with ZERO audit lineage, so an Art.17
  -- erasure of a workspace SHOULD remove its leases automatically rather than
  -- block deletion (TR4 — erasure reaches the row). The 059 RESTRICT precedent
  -- exists to force explicit anonymisation of lineage-bearing rows; the lease
  -- carries none. Note: a released lease is TOMBSTONED (retained, heartbeat
  -- aged-out — see release_worktree_lease), so a row now persists for the life
  -- of the workspace rather than per-release; this is a retention change for
  -- NON-personal operational state (an int generation + ids), still bounded by
  -- worktree count and still cascade-erased on workspace delete — NOT an Art.17
  -- concern (data-integrity-guardian APPROVED the cascade 2026-06-30; the
  -- tombstone does not touch it). DO NOT add a WORM `BEFORE` trigger to this
  -- table later without revisiting this cascade — it would deadlock the cascade
  -- UPDATE/DELETE (learning 2026-05-25-art17-cascade-deadlock-and-worm-trigger-carveout).
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  worktree_id text not null,
  -- Infra identity: a host-stable server id (NEVER auth.uid(); host_id is not a
  -- user — an auth.uid()=host_id predicate would be a category error).
  host_id text not null,
  -- Globally-monotonic fence token per (workspace_id, worktree_id): kept on
  -- same-host re-acquire, bumped +1 on cross-host takeover, NEVER reset (release
  -- tombstones rather than deletes). The git-data fence rejects `gen < max`.
  lease_generation bigint not null default 1,
  acquired_at timestamptz not null default now(),
  heartbeat_at timestamptz not null default now(),
  primary key (workspace_id, worktree_id)
);

-- RLS (mirror 029:86-93 EXACTLY): enable RLS + a SELECT-ONLY policy. Writes are
-- denied by the ABSENCE of any INSERT/UPDATE/DELETE policy (a `FOR ALL USING`
-- would apply to writes — see rf-rls-for-all-using-applies-to-writes); they go
-- through the service_role SECURITY DEFINER RPCs below. NOTE: do NOT add a
-- table-level `revoke ... from authenticated` — that would strip the GRANT the
-- member SELECT policy needs to be reachable (RLS filters rows; the role still
-- needs the table SELECT grant). 029 revokes only the FUNCTIONS, not the table;
-- anon is gated by RLS (no anon policy ⇒ no rows). Confirmed against 029:86-93.
alter table public.worktree_write_lease enable row level security;

-- Member read: a workspace member may observe their workspace's lease state.
-- is_workspace_member is plpgsql (non-inlinable, 053:115-140) so the SECURITY
-- DEFINER boundary is preserved (mirror 059:227-229).
drop policy if exists worktree_write_lease_member_select on public.worktree_write_lease;
create policy worktree_write_lease_member_select on public.worktree_write_lease
  for select to authenticated
  using (public.is_workspace_member(workspace_id, auth.uid()));

-- acquire_worktree_lease — atomic fenced upsert (ONE statement). The RETURNING
-- list is table-qualified so it does not collide with the OUT-param names.
-- A live lease held by ANOTHER host ⇒ the WHERE is false ⇒ zero rows ⇒ caller
-- lost. Same-host re-acquire of its own (even expired) lease keeps gen and
-- returns its row (idempotent). Expiry uses server-side now() only.
create or replace function public.acquire_worktree_lease(
  p_workspace_id uuid,
  p_worktree_id text,
  p_host_id text
) returns table (host_id text, lease_generation bigint)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Bound contention on the per-key advisory lock so a same-worktree acquire
  -- race fails fast with 55P03 (lock_not_available) — which the TS client's
  -- jittered transient-retry covers — instead of blocking unboundedly (mirror
  -- 029:119). Without this, 55P03 can never arise from this RPC and that half of
  -- the client's mirrored transient set would be dead for this function.
  perform set_config('lock_timeout', '500ms', true);
  -- Shape-parity with 029:125 (per-key advisory xact lock, released on commit).
  -- Redundant-but-harmless for atomicity here (that rests on the ON CONFLICT …
  -- WHERE EvalPlanQual re-check, not this lock — no multi-statement window like
  -- 029's sweep+count+cap); kept for precedent parity + the lock_timeout above.
  perform pg_advisory_xact_lock(
    hashtextextended(p_workspace_id::text || ':' || p_worktree_id, 0)
  );

  return query
  insert into public.worktree_write_lease as wl (workspace_id, worktree_id, host_id)
  values (p_workspace_id, p_worktree_id, p_host_id)
  on conflict (workspace_id, worktree_id) do update
    set host_id = excluded.host_id,
        lease_generation = case
          when wl.host_id = excluded.host_id
            then wl.lease_generation              -- same host: idempotent refresh, keep gen
          else wl.lease_generation + 1            -- cross-host takeover: bump in-statement
        end,
        acquired_at = case
          when wl.host_id = excluded.host_id
            then wl.acquired_at
          else now()
        end,
        heartbeat_at = now()
    where wl.host_id = excluded.host_id
       or wl.heartbeat_at < now() - interval '120 seconds'
  returning wl.host_id, wl.lease_generation;
end;
$$;

-- touch_worktree_lease — heartbeat. Returns the updated row_count. A 0 return
-- means the lease was reclaimed (host_id changed, gen bumped, or row gone) —
-- the caller MUST treat 0 as "you no longer hold it" and fail loud. The host
-- passes the gen from its most-recent successful acquire. No time predicate ⇒
-- no clock-skew false-zero. Mirror touch_conversation_slot (029:174-191).
create or replace function public.touch_worktree_lease(
  p_workspace_id uuid,
  p_worktree_id text,
  p_host_id text,
  p_lease_generation bigint
) returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_updated integer;
begin
  update public.worktree_write_lease
  set heartbeat_at = now()
  where workspace_id = p_workspace_id
    and worktree_id = p_worktree_id
    and host_id = p_host_id
    and lease_generation = p_lease_generation;
  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

-- release_worktree_lease — graceful release as a TOMBSTONE, not a DELETE
-- (CTO ruling 2026-06-30, ADR-068 §2/§3 amendment). Retains the row and its
-- lease_generation but ages heartbeat_at to the distant past, so the NEXT
-- acquire takes over IMMEDIATELY (no 120s wait) via the expiry disjunct while
-- lease_generation keeps climbing — a DELETE would reset gen to the column
-- default on re-insert and invert the git-data fence (`gen < max`) into a
-- write outage. Updates only if host_id AND lease_generation still match, so a
-- reclaimer's row is never stomped (a stale-gen release is a no-op, AC2(f)).
-- host_id is kept on the tombstone (not nulled) so the acquire CASE is
-- unchanged: same-host re-acquire keeps gen (safe — a graceful release means no
-- in-flight writer), cross-host re-acquire bumps +1. Returns the updated
-- row_count (0 = already reclaimed/released).
create or replace function public.release_worktree_lease(
  p_workspace_id uuid,
  p_worktree_id text,
  p_host_id text,
  p_lease_generation bigint
) returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_released integer;
begin
  update public.worktree_write_lease
  set heartbeat_at = '-infinity'::timestamptz  -- tombstone: next acquire takes over immediately
  where workspace_id = p_workspace_id
    and worktree_id = p_worktree_id
    and host_id = p_host_id
    and lease_generation = p_lease_generation;
  get diagnostics v_released = row_count;
  return v_released;
end;
$$;

-- Grants: writes via service_role only. The named-role REVOKE (PUBLIC + anon +
-- authenticated) is load-bearing — Supabase's ALTER DEFAULT PRIVILEGES grants
-- EXECUTE to anon/authenticated/service_role, so revoking from PUBLIC alone is
-- insufficient (learning 2026-05-06-supabase-default-privileges-defeat-revoke-from-public;
-- enforced by test/migration-rpc-grants.test.ts).
revoke all on function public.acquire_worktree_lease(uuid, text, text) from public, anon, authenticated;
revoke all on function public.touch_worktree_lease(uuid, text, text, bigint) from public, anon, authenticated;
revoke all on function public.release_worktree_lease(uuid, text, text, bigint) from public, anon, authenticated;
grant execute on function public.acquire_worktree_lease(uuid, text, text) to service_role;
grant execute on function public.touch_worktree_lease(uuid, text, text, bigint) to service_role;
grant execute on function public.release_worktree_lease(uuid, text, text, bigint) to service_role;
