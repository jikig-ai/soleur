#!/usr/bin/env bash
# Shared WORM audit-append helper for the flag-tooling skills (#4581 PR-1).
#
# Appends a row to public.flag_flip_audit via the SECURITY DEFINER PostgREST RPC
# `audit_flag_flip` (migration 071), replacing the prior `psql` binary dependency
# so the sanctioned path runs on any machine (no psql/sudo).
#
# Sourced by:
#   plugins/soleur/skills/flag-create/scripts/create.sh
#   plugins/soleur/skills/flag-set-role/scripts/flip.sh
#   plugins/soleur/skills/user-set-role/scripts/set-role.sh
#
# Contract:
#   audit_flag_flip_rpc <url> <srk> <flag> <env> <target> <action> <before> <after> <actor>
#
#   <url>    SUPABASE_URL of the audit DB (callers resolve from Doppler -c dev,
#            matching the historical DATABASE_URL_POOLER -c dev audit target).
#   <srk>    SUPABASE_SERVICE_ROLE_KEY for <url> (the RPC is GRANTed to service_role only).
#   <before>/<after>  LITERAL JSON tokens: `true` | `false` | `null`. Passed via
#                     `jq --argjson` so they reach the bool columns as JSON bool/null,
#                     not strings (a `--arg` string fails PostgREST bool coercion).
#
# Behavior: append-before-flip — the caller MUST call this BEFORE any Flagsmith /
# Supabase mutation, and abort the flip on a non-zero return. Returns:
#   0  audit row written (echoes the row uuid on stdout)
#   4  audit append failed (non-2xx, empty body, or missing/null id) — caller exits 4
#
# Requires: curl, jq.
audit_flag_flip_rpc() {
  local url="$1" srk="$2" flag="$3" env="$4" target="$5" action="$6" before="$7" after="$8" actor="$9"
  local body resp code id

  command -v jq >/dev/null   || { echo "FATAL: jq not found (audit append)" >&2; return 4; }
  command -v curl >/dev/null || { echo "FATAL: curl not found (audit append)" >&2; return 4; }

  # --argjson for the bool/null args; --arg for the text args.
  body=$(jq -nc \
    --arg  f  "$flag"   --arg e  "$env"    --arg t "$target" \
    --arg  a  "$action" --arg ac "$actor" \
    --argjson b  "$before" --argjson af "$after" \
    '{p_flag_name:$f, p_env:$e, p_target:$t, p_action:$a, p_before_bool:$b, p_after_bool:$af, p_actor:$ac}') \
    || { echo "FATAL: failed to build audit RPC body (bad before/after token: '$before'/'$after')" >&2; return 4; }

  resp=$(curl -sS -w '\n%{http_code}' -X POST \
    -H "apikey: ${srk}" -H "Authorization: Bearer ${srk}" \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    "${url}/rest/v1/rpc/audit_flag_flip" -d "$body") \
    || { echo "FATAL: audit RPC request failed (curl error)" >&2; return 4; }

  code=$(printf '%s' "$resp" | tail -n1)
  body=$(printf '%s' "$resp" | sed '$d')
  [[ "$code" =~ ^2[0-9][0-9]$ ]] \
    || { echo "FATAL: audit RPC non-2xx (HTTP $code): $body" >&2; return 4; }

  # RETURNS uuid -> PostgREST emits a bare JSON scalar; array branch is dead-but-safe.
  id=$(printf '%s' "$body" | jq -r 'if type=="array" then .[0] else . end' 2>/dev/null)
  [[ -n "$id" && "$id" != "null" ]] \
    || { echo "FATAL: audit RPC returned no id: $body" >&2; return 4; }

  printf '%s' "$id"
}
