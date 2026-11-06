#!/usr/bin/env bash
# web2-relay-rows.sh — the ONE definition of "is web-2's relay actually bound where the serve flip expects",
# per web-2's OWN telemetry in Better Stack (#12167). Read by the `relay bind probe (serve only)` step of
# .github/workflows/cf-lb-overlay.yml (job ga_pool_update), which runs before the plan that sets web-2's LB weight to 1.
#
# WHY TELEMETRY. The runner cannot reach web-2 and must not: the app on web-2 reports its own relay state,
# the runner reads that report with the Better Stack read credentials from the ENVIRONMENT (nothing on argv),
# exactly as scripts/lib/web2-luks-rows.sh does. The query and the credential withholding are that file's
# w2l_query (sourced, not copied: one egress definition).
#
# ROW CONTRACT (the emitter is owned by the app; this parser is coded to EXACTLY this). WARN level, every 60 s,
# host_name `soleur-web-2`, the message carries one line:
#   relay_probe proxy_state=<listening|disabled|no_bind|no_allowlist|error> addr=<ip|none> port=<n> workspaces_populated=<0|1>
# The SQL pulls the line out of the row (`extract(raw, 'relay_probe [^"\\]*')`, it ends at a quote or a backslash,
# so a JSON-wrapped message works); the judge then matches the WHOLE line against the closed grammar. Any other
# spelling (a new field, a reordered field, a new state, trailing text) is a malformed row, which refuses.
#
# JUDGE (pure, no network, no clock: age_s is computed by the server). wrr_judge <rows.jsonl> <expected_addr>
# prints exactly one line and returns 0 (the verdict is the data):
#   GREEN rows=<n> newest_age_s=<s> addr=<ip>
#   RED reason=<token>
# GREEN needs ALL of: >= 2 rows in the last 180 s; the newest row <= 120 s old; every in-window row well-formed,
# proxy_state=listening, addr == expected (the IP in Terraform state; a wildcard / none never matches), port 8443.
# workspaces_populated is parsed (it must be 0 or 1 or the row is malformed) and RECORDED, never judged: owner ruling
# 2026-11-06 on #8211, CTO ruling same day. web-2 holds no workspace directories until it serves (ADR-143 D3), so a
# populated=1 requirement before serving was circular. Volume identity is proven by the WORKSPACES_LUKS_CUTOVER_AT
# and GIT_DATA_LUKS_CUTOVER_AT markers, which the gate chain checks before this step. An empty body is zero rows (RED), never a pass. A QUERY FAILURE is neither: wrr_fetch
# returns non-zero and the caller refuses without judging. The judge echoes only its closed vocabulary, never row text.
#
# Sourceable under `set -u`/`set -e`; sets no shell options.

# shellcheck disable=SC2034
[[ -n "${_WRR_LIB_LOADED:-}" ]] && return 0
_WRR_LIB_LOADED=1

export LC_ALL=C
_wrr_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/web2-luks-rows.sh
source "$_wrr_lib_dir/web2-luks-rows.sh"

WRR_HOST_NAME="soleur-web-2"
WRR_PORT=8443
WRR_WINDOW_S=180
WRR_MAX_NEWEST_AGE_S=120
WRR_MIN_ROWS=2
WRR_LIMIT=200

# wrr_sql — raw SQL (betterstack-query.sh mode 1). The host predicate is an explicit AND, the window is the
# hot table only (180 s is far inside it). `$BS_TABLE` is substituted by the query script, so it stays literal.
# No output alias reuses a source column name (`dt`, `raw`).
wrr_sql() {
  cat <<SQL
SELECT dateDiff('second', dt, now()) AS age_s, JSONExtractString(raw,'host_name') AS host_name, extract(raw, 'relay_probe [^"\\\\\\\\]*') AS line
FROM remote(\$BS_TABLE)
WHERE dt > now() - INTERVAL ${WRR_WINDOW_S} SECOND
  AND JSONExtractString(raw,'host_name') = '${WRR_HOST_NAME}'
  AND position(raw, 'relay_probe proxy_state=') > 0
ORDER BY dt DESC LIMIT ${WRR_LIMIT}
FORMAT JSONEachRow
SQL
}

# wrr_fetch <outfile> — rc 0: the query ANSWERED (body possibly empty); rc 1: it FAILED (credentials absent,
# transport, 4xx/5xx, timeout), a scrubbed one-line class on stderr. Credential withholding is w2l_query's.
wrr_fetch() { w2l_query "$(wrr_sql)" "$1"; }

# wrr_judge <rows.jsonl> <expected_addr>
wrr_judge() {
  local f="$1" exp="${2:-}" out
  if [[ ! "$exp" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "$exp" == "0.0.0.0" ]]; then
    printf 'RED reason=expected_addr_invalid\n'; return 0
  fi
  if ! jq -e -s 'all(.[]; type == "object")' "$f" >/dev/null 2>&1; then
    printf 'RED reason=body_unparseable\n'; return 0
  fi
  out="$(jq -r -s --arg host "$WRR_HOST_NAME" --arg exp "$exp" --arg port "$WRR_PORT" \
    --argjson win "$WRR_WINDOW_S" --argjson maxnew "$WRR_MAX_NEWEST_AGE_S" --argjson minrows "$WRR_MIN_ROWS" --argjson lim "$WRR_LIMIT" '
    def age: ((.age_s | tostring) as $a | if ($a | test("^[0-9]+$")) then ($a | tonumber) else null end);
    def parsed: (if (.line | type) == "string" then
        (.line | capture("^relay_probe proxy_state=(?<state>listening|disabled|no_bind|no_allowlist|error) addr=(?<addr>[0-9A-Fa-f:.]+|none) port=(?<port>[0-9]{1,5}) workspaces_populated=(?<wp>[01])$"))
      else null end) // null;
    . as $all
    | if ($all | length) >= $lim then "RED reason=rows_truncated"
      else
        [ $all[] | select(.host_name == $host) | . + {a: age} ] as $mine
        | if ($mine | any(.a == null)) then "RED reason=row_age_malformed"
          else
            [ $mine[] | select(.a <= $win) ] as $in
            | if ($in | length) < $minrows then "RED reason=rows_below_floor"
              else
                ($in | map(.a) | min) as $newest
                | [ $in[] | (parsed) as $p | {p: $p} ] as $rows
                | if $newest > $maxnew then "RED reason=newest_stale"
                  elif ($rows | any(.p == null)) then "RED reason=row_malformed"
                  elif ($rows | any(.p.state != "listening")) then "RED reason=proxy_state_not_listening"
                  elif ($rows | any(.p.addr == "none" or .p.addr == "::" or .p.addr == "0.0.0.0")) then "RED reason=addr_wildcard"
                  elif ($rows | any(.p.addr != $exp)) then "RED reason=addr_mismatch"
                  elif ($rows | any(.p.port != $port)) then "RED reason=port_mismatch"
                  else "GREEN rows=\($in | length) newest_age_s=\($newest) addr=\($exp)" end
              end
          end
      end' "$f" 2>/dev/null)" || out=""
  [[ -n "$out" ]] || out="RED reason=judge_error"
  printf '%s\n' "$out"
}
