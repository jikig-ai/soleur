# Learning: Supabase Management REST API bypasses MCP OAuth for read-only diagnostics

**Date:** 2026-05-06
**Source session:** Brainstorm for prod Disk IO Budget alert (`feat-supabase-disk-io-budget`, issue #3358).
**Category:** integration-issues / database-issues
**Tags:** category=integration-issues, module=supabase, vendor=supabase, tool=mcp

## Problem

The Supabase MCP server's two-step OAuth flow (`mcp__plugin_supabase_supabase__authenticate` → `mcp__plugin_supabase_supabase__complete_authentication`) failed twice in the same session. Each call to `authenticate` produced a fresh `client_id` + `state`, the user authorized in browser, the user pasted back the callback URL — and `complete_authentication` returned `"No OAuth flow is in progress"` both times. The in-progress flow state did not persist between the two tool calls.

This blocks any task that needs the MCP server (running queries, listing projects, reading analytics) on the very first hop.

## Root cause

The MCP server appears to discard the OAuth flow state between consecutive tool invocations in the same session. Whether this is a server bug, a session-id mismatch in the MCP transport, or intentional we do not know — but the symptom is reproducible and stops the workflow cold if treated as the only path.

## Working solution

Bypass the MCP server entirely for read-only diagnostics. The `SUPABASE_ACCESS_TOKEN` is already stored in Doppler `prd`, and the Supabase Management REST API (`https://api.supabase.com/v1/...`) covers everything an incident-response brainstorm needs:

```bash
SUPA_TOKEN=$(doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd --plain)
REF=ifsccnjhymdmidffkzhl

# Project info + region + Postgres version + status
curl -sS -H "Authorization: Bearer $SUPA_TOKEN" \
  "https://api.supabase.com/v1/projects/$REF"

# Compute add-on tier currently selected (and tier catalog with $ + IO baselines)
curl -sS -H "Authorization: Bearer $SUPA_TOKEN" \
  "https://api.supabase.com/v1/projects/$REF/billing/addons"

# Run any read-only SQL — pg_stat_statements, pg_stat_user_tables, cron.job, etc.
QUERY='SELECT * FROM cron.job ORDER BY jobid'
curl -sS -X POST \
  -H "Authorization: Bearer $SUPA_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.supabase.com/v1/projects/$REF/database/query" \
  -d "{\"query\": $(jq -Rn --arg q "$QUERY" '$q')}"
```

This bypasses both MCP auth state and `psql` (which is not installed in agent environments and cannot be apt-installed without sudo).

## Key insight

When an MCP server's OAuth handoff fails, **check Doppler for a vendor access token first** before asking the user to retry. The Soleur stack already stores access tokens for vendors with management APIs (Supabase, Cloudflare, Stripe, Vercel) in Doppler's `prd` config. Direct REST + Doppler is a deterministic fallback that wastes zero user time.

This generalizes: for any vendor whose MCP server is unreliable or absent, the priority order is (1) Doppler-stored access token + REST, (2) MCP, (3) ask user to authorize. The `hr-exhaust-all-automated-options-before` rule already prescribes this priority for credentials; this learning extends it specifically to the MCP-unavailable failure mode.

## Prevention

- When an MCP server requires OAuth, assume it might fail and have a Doppler+REST fallback ready in the same turn.
- Do NOT block a brainstorm on MCP auth state — fall through to REST in seconds, not minutes.

## Session errors

- **`curl ... | head -c 1500` truncated mid-stream** — Recovery: data was still partially readable; re-running without `head` would have returned complete output. **Prevention:** pipe to a file first (`curl -sS ... -o /tmp/x && head -c 4000 /tmp/x`) instead of piping through `head` for binary-safe truncation.
- **Wrong Doppler key guess (`SUPABASE_PROJECT_REF`)** — Recovery: `doppler secrets --only-names -p soleur -c <cfg> | grep -i supabase` enumerated the correct names (`SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_ACCESS_TOKEN`, `SUPABASE_SERVICE_ROLE_KEY`, `DATABASE_URL`, `DATABASE_URL_POOLER`). **Prevention:** always run `--only-names` first when looking for vendor secrets you have not used recently in this repo.
- **MCP OAuth state lost between tool calls** — see Problem above. **Prevention:** prefer REST + Doppler-stored access token for read-only diagnostics; treat MCP as the secondary path, not the primary.
- **`psql` not installed and no sudo** — Recovery: REST `database/query` covers every read-only DB diagnostic. **Prevention:** do not propose `psql` in agent runbooks; document REST instead.
