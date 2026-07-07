-- Enriched conversation-list RPC — client-callable, RLS-preserving.
--
-- PERF FIX (dashboard conversation-list load). The rail's useConversations
-- hook previously issued TWO client queries:
--   1. `conversations` (scoped by repo_url + workspace_id), then
--   2. `messages … WHERE conversation_id IN (<up to 50 ids>)` with NO limit —
--      pulling EVERY message's full `content` for all shown conversations,
--      only to derive a title (first user/assistant message) + a 100-char
--      preview (last message) per conversation. Payload scaled O(all messages)
--      i.e. 250–2,500 full message bodies to the browser per dashboard load.
--
-- This RPC returns each conversation PLUS only the four short message snippets
-- the UI actually needs, each computed by a LATERAL subquery over `messages`
-- ordered by created_at using the existing idx_messages_conversation_created
-- index (LIMIT 1 per snippet). Payload drops to O(conversations).
--
-- SECURITY MODEL — SECURITY INVOKER (RLS-PRESERVING), NOT DEFINER.
--   This is the first client-callable, RLS-preserving RPC in the codebase; the
--   general pattern (INVOKER + never-service_role + correlate-on-RLS-bounded-row)
--   is recorded in ADR-101.
--   The two existing conversation-read RPCs (027 sum_user_mtd_cost, 037
--   find_stuck_active_conversations) are SECURITY DEFINER + service_role-only:
--   they intentionally BYPASS RLS for server-side aggregation and are never
--   callable by the browser. This RPC is the opposite — CLIENT-callable with
--   the user JWT — and must PRESERVE tenant scope. There is no precedent for a
--   client-callable conversation-read RPC, so it diverges deliberately:
--     • SECURITY INVOKER → the function runs as the caller, so migration-075
--       RLS (conversations_owner_select / conversations_shared_select) AND the
--       messages RLS (059 messages_workspace_member_select) bound the result
--       set EXACTLY as today's direct client queries do. No new trust boundary.
--       The client already reads both tables directly under these policies, so
--       `authenticated` has the required SELECT and the LATERAL messages read
--       is RLS-reachable. A LANGUAGE sql SECURITY INVOKER set-returning
--       function applies the caller's row policies to every table it reads —
--       RLS is NOT skipped for INVOKER.
--     • GRANT EXECUTE … TO authenticated (the INVERSE of the DEFINER
--       precedents' REVOKE-from-authenticated) — this one is called by the
--       browser client. NEVER grant service_role (BYPASSRLS → would return all
--       rows unfiltered across tenants).
--     • search_path pinned to `public, pg_temp` (defense-in-depth; matches 037)
--       even under INVOKER; relations qualified `public.<table>` in the body.
--
-- ISOLATION — the private-snippet boundary rests on the LATERAL strictly
--   correlating on the RLS-bounded OUTER conversation
--   (m.conversation_id = c.id). The messages RLS is workspace-BROAD
--   (is_workspace_member) — it alone does not enforce per-conversation
--   visibility; a snippet stays private only because the outer `conversations`
--   row is already gated to owner-or-shared by 075. The messages subqueries are
--   therefore NEVER read uncorrelated / independently-filtered.
--
-- The p_repo_url / p_workspace_id filters are caller-supplied FUNCTIONAL
--   DISCRIMINATORS (which rail to render — e.g. an owner with two same-repo
--   workspaces), NOT a security layer: a caller can pass any workspace id; the
--   only tenant boundary is RLS. Do NOT credit them as defense-in-depth.
--
-- FORWARD-SAFE. Read-only; rollback is `drop function` (see .down.sql). The RPC
-- is unused by existing code until the deploy lands, and the hook handles
-- "function not found" (42883) via its error branch. Recommended order:
-- migration first, then deploy.

create or replace function public.list_conversations_enriched(
  p_repo_url text,
  p_workspace_id uuid,
  p_archive text default 'active',
  p_status text default null,
  p_domain text default null,
  p_limit int default 50
) returns table (
  id uuid,
  user_id uuid,
  domain_leader text,
  session_id text,
  status text,
  total_cost_usd numeric,
  input_tokens int,
  output_tokens int,
  last_active timestamptz,
  created_at timestamptz,
  archived_at timestamptz,
  context_path text,
  repo_url text,
  active_workflow text,
  workflow_ended_at timestamptz,
  workspace_id uuid,
  visibility text,
  first_user_content text,
  first_assistant_content text,
  last_content text,
  last_leader text
)
language sql
security invoker
set search_path = public, pg_temp
as $$
  select
    c.id,
    c.user_id,
    c.domain_leader,
    c.session_id,
    c.status,
    c.total_cost_usd,
    c.input_tokens,
    c.output_tokens,
    c.last_active,
    c.created_at,
    c.archived_at,
    c.context_path,
    c.repo_url,
    c.active_workflow,
    c.workflow_ended_at,
    c.workspace_id,
    c.visibility,
    fu.content  as first_user_content,
    fa.content  as first_assistant_content,
    lm.content  as last_content,
    lm.leader_id as last_leader
  from public.conversations c
  -- First user message (for the derived title). Correlated on the RLS-bounded
  -- outer conversation; ordered by created_at ASC via idx_messages_conversation_created.
  -- `m.id` is a deterministic tiebreaker for messages sharing an exact created_at
  -- timestamp (possible for rapid tool-call bursts) — without it the "first"
  -- pick is arbitrary-but-nondeterministic across runs.
  left join lateral (
    select m.content
    from public.messages m
    where m.conversation_id = c.id and m.role = 'user'
    order by m.created_at asc, m.id asc
    limit 1
  ) fu on true
  -- First assistant message (title fallback).
  left join lateral (
    select m.content
    from public.messages m
    where m.conversation_id = c.id and m.role = 'assistant'
    order by m.created_at asc, m.id asc
    limit 1
  ) fa on true
  -- Last message overall (for the preview + last-message leader). DESC tiebreaker
  -- mirrors the ASC ones so "last" is the deterministic complement of "first".
  left join lateral (
    select m.content, m.leader_id
    from public.messages m
    where m.conversation_id = c.id
    order by m.created_at desc, m.id desc
    limit 1
  ) lm on true
  where c.repo_url = p_repo_url
    and c.workspace_id = p_workspace_id
    and (
      case
        when p_archive = 'archived' then c.archived_at is not null
        else c.archived_at is null
      end
    )
    and (p_status is null or c.status = p_status)
    and (
      p_domain is null
      or (p_domain = 'general' and c.domain_leader is null)
      or (p_domain <> 'general' and c.domain_leader = p_domain)
    )
  order by c.last_active desc, c.created_at desc
  limit p_limit;
$$;

comment on function public.list_conversations_enriched(text, uuid, text, text, text, int) is
  'Client-callable (SECURITY INVOKER) enriched conversation-list read for the dashboard rail. '
  'Returns each RLS-visible conversation plus 4 short message snippets (first-user, first-assistant, '
  'last-content, last-leader) via LATERAL joins on idx_messages_conversation_created, replacing the '
  'unbounded messages fan-out. RLS-075 + messages RLS (059) are the tenant boundary; the repo_url/'
  'workspace_id params are functional rail discriminators, NOT a security layer. See migration header.';

-- GRANT hygiene inverts the DEFINER precedents (027/037 revoke from
-- authenticated): this RPC is browser-callable, so authenticated needs EXECUTE.
-- The default-privileges ALTER (037 header) auto-grants EXECUTE to PUBLIC on
-- CREATE, so REVOKE-from-PUBLIC/anon first, then GRANT the single intended role.
-- NEVER grant service_role (BYPASSRLS would return all tenants' rows).
revoke all on function public.list_conversations_enriched(text, uuid, text, text, text, int) from public;
revoke all on function public.list_conversations_enriched(text, uuid, text, text, text, int) from anon;
grant execute on function public.list_conversations_enriched(text, uuid, text, text, text, int) to authenticated;

-- Supporting index for the rail predicate (workspace_id + repo_url filter,
-- last_active-desc order, active-only default). Existing indexes do not cover
-- this shape: idx_conversations_user_repo is (user_id, repo_url) with no
-- workspace_id / last_active ordering. Plain CREATE INDEX — NEVER CONCURRENTLY
-- (the Supabase migration runner wraps each migration in a txn; CONCURRENTLY
-- raises SQLSTATE 25001).
create index if not exists idx_conversations_rail
  on public.conversations (workspace_id, repo_url, last_active desc)
  where archived_at is null;
