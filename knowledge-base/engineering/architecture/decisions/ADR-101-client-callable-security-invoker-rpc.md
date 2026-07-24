---
title: Client-callable SECURITY INVOKER RPC pattern (RLS-preserving reads)
status: accepted
date: 2026-07-07
amends: none
amended_by: [ADR-112]
supersedes: none
issue: none
related: []
related_adrs: [ADR-044, ADR-112]
brand_survival_threshold: single-user incident
---

# ADR-101: Client-callable `SECURITY INVOKER` RPC pattern (RLS-preserving reads)

## Context

`list_conversations_enriched` (migration 125) is the **first** Postgres RPC in this
codebase that is called **directly by the browser client** under the end-user JWT and is
meant to **preserve** Row-Level Security, rather than bypass it.

Every prior conversation/message-reading RPC is the opposite shape:

- `027_mtd_cost_aggregate.sql` (`sum_user_mtd_cost`) — `SECURITY DEFINER`,
  `SET search_path`, `REVOKE EXECUTE … FROM authenticated, anon`, server-invoked only.
- `037_stuck_active_finder_rpc.sql` (`find_stuck_active_conversations`) — `SECURITY
  DEFINER`, `GRANT EXECUTE … TO service_role` only, cross-user maintenance scan.

Those are DEFINER **because they intentionally bypass RLS** for server-side aggregation
/ maintenance and are never reachable from the browser. A future author reaching for a
"read conversations in one RPC" precedent would find only these and could wrongly clone
the DEFINER + service_role shape onto a client-callable path — which would **bypass** the
migration-075 owner/shared policies and force re-implementing tenant scope by hand in the
function body (a strictly higher isolation risk, and the exact trap this ADR exists to
prevent).

## Decision

For an RPC that is **client-callable under the user JWT** and must return **only the
rows the caller could already read via direct client queries**, use this pattern:

1. **`SECURITY INVOKER`** (the function runs as the calling role), so the caller's RLS
   policies bound every table the body reads — the trust boundary is byte-identical to the
   direct client queries the RPC replaces. **No new trust boundary; no DEFINER escalation.**
2. **`SET search_path = public, pg_temp`** (defense-in-depth even under INVOKER) and
   schema-qualify body relations as `public.<table>`.
3. **GRANT hygiene inverts the DEFINER precedents:**
   `REVOKE ALL … FROM PUBLIC;` `REVOKE ALL … FROM anon;` `GRANT EXECUTE … TO authenticated;`
   — with the full argument-type signature on every statement. **Never** `GRANT … TO
   service_role` (service_role is `BYPASSRLS` → would return every tenant's rows unfiltered).
4. **Correlate every cross-table read on an RLS-bounded outer row.** When a joined table's
   RLS is *broader* than the outer table's (e.g. `messages_workspace_member_select` is
   workspace-broad while `conversations` is owner-or-shared), isolation of the joined data
   rests on a `LATERAL` (or equivalent) that strictly correlates on the outer row's primary
   key (`m.conversation_id = c.id`). Never read the broader table uncorrelated /
   independently-filtered inside the body — that would surface rows the outer RLS hides.
5. **Caller-supplied scope params are functional discriminators, not a security layer.**
   Params like `p_repo_url` / `p_workspace_id` decide *which* RLS-visible slice to render;
   the *only* tenant boundary is RLS. Do not credit them as defense-in-depth in reviews — a
   future reader must not weaken RLS believing these filters back it up.

## Consequences

- A client-facing read optimization (collapsing N client queries into one RPC) is now a
  documented, low-risk pattern with an explicit "INVOKER, not DEFINER" precedent to cite.
- Escalating any such RPC to `SECURITY DEFINER` is a **new trust boundary** and requires its
  own ADR + a `search_path` pin + an explicit WHERE clause that reproduces RLS scope exactly
  + a data-integrity review — never the default.
- Reviewers of future client-callable RPCs verify: INVOKER, no `service_role` grant, and
  every cross-table read correlated on an RLS-bounded outer row (a set-returning
  `LANGUAGE sql SECURITY INVOKER` function applies the caller's row policies to every table —
  RLS is not skipped for INVOKER).

Migration 125's header contains the concrete instance; this ADR generalizes it.
