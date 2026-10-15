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
  `erase_egress_audit_rollup`); this runbook is for an explicit request made outside account deletion.
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

State in the response that counts are best-effort lower bounds and that the 90-day Better Stack copy of the raw gateway log is a
separate operator-side record (covered by the privacy policy's log-retention wording, not by this export).

## Erasure (Art. 17)

```bash
export WS=<workspace uuid>
[[ "$WS" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || { echo "not a lowercase uuid"; exit 1; }
doppler run -p soleur -c prd -- bash -c 'psql "$DATABASE_URL_POOLER" -At -v ON_ERROR_STOP=1 -v ws="$WS" -f -' <<'SQL'
select public.erase_egress_audit_rollup(:'ws'::uuid);
SQL
```

The function is service-role only, idempotent and returns the number of rows deleted. Record the count and the request reference on
the request. A second run returns 0.

## Checks

- Retention and freshness: `doppler run -p soleur -c prd -- bash scripts/egress-audit-retention-check.sh` prints `OK` when no row is
  older than 35 days (see ADR-288 for when freshness is asserted).
- A throttled workspace shows a `SOLEUR_EGRESS_AUDIT_THROTTLED` marker in Better Stack (see `betterstack-log-query.md`).
