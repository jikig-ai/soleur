---
title: Egress audit rollup — data-subject export and erasure by workspace
status: active
issue: 9545
related_adrs: [ADR-288, ADR-278]
---

# Egress audit rollup — data-subject export and erasure by workspace

Use this when an Art. 15 (access) or Art. 17 (erasure) request concerns what a workspace's agents contacted on the open web, and
before collection is ever enabled for an external workspace (it is dark until PR2 of #9545 ships). The table
`public.workspace_egress_audit_rollup` is keyed by `workspace_id`; it holds the host, allowed/denied, best-effort counts and
timestamps, and no IP, user, session or path value (ADR-288). Rows are kept 30 days and are deleted with the workspace.

Everything below runs from a workstation with Doppler access, never over SSH, and never prints the connection string.

## Who a request maps to

- **Solo workspace:** the workspace id equals the user's id. Account erasure already deletes these rows (saga step 5.15,
  `erase_egress_audit_rollup`, which only erases a workspace with no member left, so it runs after the member row is removed);
  this runbook is for an explicit request made while the account stays open, where the requester is still the member and the RPC
  would (correctly) do nothing.
- **Team workspace:** the rows describe the workspace's agents, not a named member, and persist for the remaining members. An
  erasure request from one member does not delete them; route the request to the workspace owner and note it on the request.

## Export (Art. 15)

```bash
export WS=<workspace uuid>   # solo workspace: the requester's user id
[[ "$WS" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || { echo "not a lowercase uuid"; exit 1; }
doppler run -p soleur -c prd -- bash -c 'psql "$DATABASE_URL_POOLER" --csv -v ON_ERROR_STOP=1 -v ws="$WS" -f -' <<'SQL' > "egress-audit-${WS}.csv"
select bucket_start, requested_host, decision, source_host, request_count, bytes_out, first_seen, last_seen
  from public.workspace_egress_audit_rollup
 where workspace_id = :'ws'::uuid
 order by bucket_start, requested_host;
SQL
```

The CSV holds the requester's data: write it to a private directory, hand it over through the DSAR channel and delete the file
afterwards.

State in the response that counts are best-effort lower bounds and that the 90-day Better Stack copy of the raw gateway log is a
separate operator-side record (covered by the privacy policy's log-retention wording, not by this export).

## Erasure (Art. 17)

Two steps, both read from the same connection. First a **read-only preview**: it shows how many rows would go and confirms the
workspace has exactly one member and that member is the requester. Stop if the member count is not 1 or the member is not the
requester (a team workspace: see above).

```bash
export WS=<workspace uuid>      # solo workspace: the requester's user id
export REQUESTER=<requester user uuid>
for v in "$WS" "$REQUESTER"; do
  [[ "$v" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || { echo "not a lowercase uuid"; exit 1; }
done
doppler run -p soleur -c prd -- bash -c 'psql "$DATABASE_URL_POOLER" -At -v ON_ERROR_STOP=1 -v ws="$WS" -v req="$REQUESTER" -f -' <<'SQL'
select 'rows', count(*) from public.workspace_egress_audit_rollup where workspace_id = :'ws'::uuid
union all
select 'members', count(*) from public.workspace_members where workspace_id = :'ws'::uuid
union all
select 'requester_is_member', count(*) from public.workspace_members where workspace_id = :'ws'::uuid and user_id = :'req'::uuid;
SQL
```

Proceed only when `members` is 1 and `requester_is_member` is 1. **Switch web access off first** (the owner's workspace toggle, or
the per-organisation flag for a canary) **and wait at least 20 minutes**: Vector's reduce, its disk buffer and the sink retries can
still post buckets for the period just erased, and the function refuses while web access is on. Then erase through the one audited path, which repeats the
same guard under a member-row lock (it deletes nothing for a workspace that gained a member between the two steps) and returns the
number of rows deleted:

```bash
doppler run -p soleur -c prd -- bash -c 'psql "$DATABASE_URL_POOLER" -At -v ON_ERROR_STOP=1 -v ws="$WS" -v req="$REQUESTER" -f -' <<'SQL'
select public.erase_egress_audit_rollup_for_requester(:'ws'::uuid, :'req'::uuid);
SQL
```

Record the count and the request reference on the request (the request record is the audit trail; PR1 adds no audit table for
this). A second run returns 0. `erase_egress_audit_rollup` is for the account-deletion saga only.

## Checks

- Retention and freshness: `doppler run -p soleur -c prd -- bash scripts/egress-audit-retention-check.sh` prints `OK` when no row is
  older than 35 days (see ADR-288 for when freshness is asserted).
- A throttled workspace shows a `SOLEUR_EGRESS_AUDIT_THROTTLED` marker in Better Stack (see `betterstack-log-query.md`).
