#!/usr/bin/env bash
# web2-relay-rows.sh — the ONE definition of "is web-2's relay actually serving where the serve flip expects",
# per the fleet's OWN telemetry in Better Stack (#12167). Read by the `relay bind probe (serve only)` step of
# .github/workflows/cf-lb-overlay.yml (job ga_pool_update), which runs before the plan that sets web-2's LB weight to 1.
#
# WHY TELEMETRY. The runner cannot reach web-2 and must not: the hosts report their own relay state, the runner reads
# those reports with the Better Stack read credentials from the ENVIRONMENT (nothing on argv), exactly as
# scripts/lib/web2-luks-rows.sh does. The query and the credential withholding are that file's w2l_query (sourced, not
# copied: one egress definition).
#
# RELAY DESIGN (shipped, #12167 PR-E). The app container sits on the default docker bridge, so it binds the WILDCARD
# inside the container (ci-deploy.sh passes -e SOLEUR_PROXY_BIND=0.0.0.0) and docker PUBLISHES 8443 on the host's private
# IP. The app therefore can never report the private IP, and its own line proves the listener, not the publish. Two
# pieces of evidence, both required:
#
#  (1) OWN LINE (wrr_judge). WARN level, every 60 s, from web-2's app container, one line in the message:
#        relay_probe proxy_state=<listening|disabled|no_bind|no_allowlist|error> addr=<ip|none> port=<n> workspaces_populated=<0|1>
#      Both hosts' rows carry CONTAINER_NAME 'soleur-web-platform'; the hosts differ by raw.host_name (soleur-web-platform =
#      web-1, soleur-web-2 = web-2). The line sits at raw.message.msg (JSON-wrapped). The SQL pulls it out of the row
#      (`extract(raw, 'relay_probe [^"\\]*')`, it ends at a quote or a backslash); the judge matches the WHOLE line against
#      the closed grammar. Any other spelling (a new field, a reordered field, a new state, trailing text) is a malformed
#      row, which refuses. GREEN needs ALL of: >= 2 rows in the last 180 s; the newest <= 120 s old; every in-window row
#      well-formed, proxy_state=listening, addr=0.0.0.0 (the container wildcard; anything else, including `none`, is a
#      mismatch), port 8443.
#      workspaces_populated is parsed (it must be 0 or 1 or the row is malformed) and RECORDED, never judged: owner ruling
#      2026-11-06 on #8211, CTO ruling same day. web-2 holds no workspace directories until it serves (ADR-143 D3), so a
#      populated=1 requirement before serving was circular. Volume identity is proven by the WORKSPACES_LUKS_CUTOVER_AT and
#      GIT_DATA_LUKS_CUTOVER_AT markers, which the gate chain checks before this step.
#
#  (2) PEER LINE (wrr_peer_judge). web-1's ci-deploy.sh relay_peer_probe dials every roster peer's published :8443 from inside
#      its app container after each prod swap and journals (SYSLOG_IDENTIFIER ci-deploy, raw.message a PLAIN string):
#        relay_peer_probe peer=<10.0.1.x> result=<ok|refused|timeout|tls|denied>   |   relay_peer_probe peer=<10.0.1.x> skipped=exec_failed
#      This is the only evidence that web-2's relay is reachable on its PRIVATE address (publish bound, sysctl, source
#      allowlist, pinned TLS). It is emitted once per web-1 deploy, not per minute, so it is judged by the NEWEST row
#      for web-2's state address from web-1 (host_name soleur-web-platform) within 24 h: GREEN iff that row is result=ok.
#      No row, a malformed newest row, or any other result refuses. A refused/denied/tls/timeout newest row means: fix
#      it, then redeploy web-1 (which re-probes) before dispatching.
#
# JUDGES (pure, no network, no clock: age_s is computed by the server). Each prints exactly one line and returns 0 (the
# verdict is the data): GREEN ... | RED reason=<token>. An empty body is zero rows (RED), never a pass. A QUERY FAILURE is
# neither: the fetch returns non-zero and the caller refuses without judging. The judges echo only their closed
# vocabulary, never row text.
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
WRR_BIND_ADDR="0.0.0.0"   # the in-container wildcard (ci-deploy.sh -e SOLEUR_PROXY_BIND=0.0.0.0)
WRR_PORT=8443
WRR_WINDOW_S=180
WRR_MAX_NEWEST_AGE_S=120
WRR_MIN_ROWS=2
WRR_LIMIT=200
WRR_PEER_HOST_NAME="soleur-web-platform"   # web-1: the host whose deploys probe web-2
WRR_PEER_LOOKBACK_S=86400
WRR_PEER_LIMIT=50

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

# wrr_judge <rows.jsonl> — the OWN-LINE judge (web-2's app container).
wrr_judge() {
  local f="$1" out
  if ! jq -e -s 'all(.[]; type == "object")' "$f" >/dev/null 2>&1; then
    printf 'RED reason=body_unparseable\n'; return 0
  fi
  out="$(jq -r -s --arg host "$WRR_HOST_NAME" --arg exp "$WRR_BIND_ADDR" --arg port "$WRR_PORT" \
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
                  elif ($rows | any(.p.addr != $exp)) then "RED reason=addr_mismatch"
                  elif ($rows | any(.p.port != $port)) then "RED reason=port_mismatch"
                  else "GREEN rows=\($in | length) newest_age_s=\($newest) addr=\($exp)" end
              end
          end
      end' "$f" 2>/dev/null)" || out=""
  [[ -n "$out" ]] || out="RED reason=judge_error"
  printf '%s\n' "$out"
}

# wrr_peer_sql <ipv4> — web-1's newest peer-probe rows for web-2's private address. The address is validated by the
# caller (wrr_peer_fetch) before it reaches the SQL text.
wrr_peer_sql() {
  cat <<SQL
SELECT dateDiff('second', dt, now()) AS age_s, JSONExtractString(raw,'host_name') AS host_name, extract(raw, 'relay_peer_probe peer=[0-9.]+ [a-z_]+=[a-z_]+') AS line
FROM remote(\$BS_TABLE)
WHERE dt > now() - INTERVAL ${WRR_PEER_LOOKBACK_S} SECOND
  AND JSONExtractString(raw,'host_name') = '${WRR_PEER_HOST_NAME}'
  AND position(raw, 'relay_peer_probe peer=$1 ') > 0
ORDER BY dt DESC LIMIT ${WRR_PEER_LIMIT}
FORMAT JSONEachRow
SQL
}

# wrr_peer_fetch <outfile> <web2_private_ipv4> — same rc contract as wrr_fetch (plus rc 1 on a non-IPv4 argument).
wrr_peer_fetch() {
  if [[ ! "${2:-}" =~ ^10\.0\.1\.[0-9]{1,3}$ ]]; then
    echo "wrr_peer_fetch: peer address is not a 10.0.1.x IPv4" >&2; return 1
  fi
  w2l_query "$(wrr_peer_sql "$2")" "$1"
}

# wrr_peer_judge <rows.jsonl> <web2_private_ipv4> — the PEER-LINE judge. GREEN iff the NEWEST row (smallest age_s;
# every row tied at that age) from web-1 for this peer, within the 24 h lookback, is result=ok.
#   GREEN peer_age_s=<s> peer=<ip>
#   RED reason=<peer_addr_invalid|body_unparseable|peer_row_age_malformed|peer_rows_none|peer_row_malformed|peer_<result>|peer_skipped>
wrr_peer_judge() {
  local f="$1" ip="${2:-}" out
  if [[ ! "$ip" =~ ^10\.0\.1\.[0-9]{1,3}$ ]]; then
    printf 'RED reason=peer_addr_invalid\n'; return 0
  fi
  if ! jq -e -s 'all(.[]; type == "object")' "$f" >/dev/null 2>&1; then
    printf 'RED reason=body_unparseable\n'; return 0
  fi
  out="$(jq -r -s --arg host "$WRR_PEER_HOST_NAME" --arg ip "$ip" --argjson win "$WRR_PEER_LOOKBACK_S" '
    def age: ((.age_s | tostring) as $a | if ($a | test("^[0-9]+$")) then ($a | tonumber) else null end);
    def parsed: (if (.line | type) == "string" then
        ((.line | capture("^relay_peer_probe peer=(?<peer>[0-9.]+) (result=(?<res>ok|refused|timeout|tls|denied)|skipped=(?<skip>exec_failed))$")) // null)
      else null end);
    [ .[] | select(.host_name == $host) | . + {a: age} ] as $mine
    | if ($mine | any(.a == null)) then "RED reason=peer_row_age_malformed"
      else
        [ $mine[] | select(.a <= $win) ] as $in
        | if ($in | length) == 0 then "RED reason=peer_rows_none"
          else
            ($in | map(.a) | min) as $newest
            | [ $in[] | select(.a == $newest) | (parsed) ] as $top
            | if ($top | any(. == null)) or ($top | any(.peer != $ip)) then "RED reason=peer_row_malformed"
              elif ($top | any(.skip != null)) then "RED reason=peer_skipped"
              elif ($top | any(.res != "ok")) then "RED reason=peer_\($top | map(select(.res != "ok")) | .[0].res)"
              else "GREEN peer_age_s=\($newest) peer=\($ip)" end
          end
      end' "$f" 2>/dev/null)" || out=""
  [[ -n "$out" ]] || out="RED reason=judge_error"
  printf '%s\n' "$out"
}
