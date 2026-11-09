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
#      web-1, soleur-web-2 = web-2). The line sits at raw.message.msg (JSON-wrapped). The SQL filters on STRUCTURED fields
#      (host_name, CONTAINER_NAME, startsWith(message.msg, 'relay_probe proxy_state=')) and selects the line FROM message.msg
#      itself, never from a whole-row position()/extract() (a log line that merely echoes a probe sentence must not be able to
#      become the newest row; the same filters as the shipped alerts in betterstack-logs-alerts.tf). The judge matches the
#      WHOLE line against the closed grammar. Any other spelling (a new field, a reordered field, a new state, trailing text) is a malformed
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
#      Because it is sparse, the peer read spans the hot window AND the S3 archive (see wrr_peer_sql; a hot-only read
#      silently misses it, measured 2026-11-08).
#      No row, a malformed newest row, or any other result refuses. A refused/denied/tls/timeout newest row means: fix
#      it, then redeploy web-1 (which re-probes) before dispatching. Since #12288 (ADR-323) a peer whose allowlist lacks
#      web-1's address resets web-1 BEFORE the handshake, so that case reads result=tls (RED reason=peer_tls), never denied once web-2 runs that image;
#      the peer's createProxyServer.peer-deny Sentry events tell it apart from a certificate fault. The peer SQL filters on SYSLOG_IDENTIFIER = 'ci-deploy' and
#      startsWith(message, 'relay_peer_probe peer=<ip> '), and selects the line from that same field.
#      ACCEPTED RESIDUAL (structural, not fixable here: no SSH at serve time): web-1's probe is journaled at web-1's deploy
#      BEFORE it fans the deploy out to web-2, so it probes web-2's PREVIOUS container and cannot prove web-2's newest one.
#      The fresh evidence is (1) web-2's own 60 s line and (3) the reverse probe written by web-2's own deploy. Operator
#      practice: dispatch serve right after a release deploy so all three describe the same build.
#
#  (3) THE REVERSE DIRECTION (the same wrr_peer_judge, dialing host soleur-web-2). When the LB sends users to web-2,
#      existing sessions are owned by web-1, so web-2's relay CLIENT must reach web-1:8443. web-2's own deploy journals
#      `relay_peer_probe peer=<web-1 ip> result=...` with host_name soleur-web-2. The owner-recorded gate is "ok in BOTH
#      directions": the judge is parameterised on the dialing host and every verdict carries dir=w1_to_w2 or dir=w2_to_w1,
#      so a missing or bad row in either direction is a RED with its own label, never a GREEN. Redeploy web-2 to re-probe.
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
# hot table only (180 s is far inside it; the sparse PEER read is hot + archive, see wrr_peer_sql). `$BS_TABLE` is substituted by the query script, so it stays literal.
# No output alias reuses a source column name (`dt`, `raw`).
wrr_sql() {
  cat <<SQL
SELECT dateDiff('second', dt, now()) AS age_s, JSONExtractString(raw,'host_name') AS host_name, JSONExtractString(raw,'message','msg') AS line
FROM remote(\$BS_TABLE)
WHERE dt > now() - INTERVAL ${WRR_WINDOW_S} SECOND
  AND JSONExtractString(raw,'host_name') = '${WRR_HOST_NAME}'
  AND JSONExtractString(raw,'CONTAINER_NAME') = 'soleur-web-platform'
  AND startsWith(JSONExtractString(raw,'message','msg'), 'relay_probe proxy_state=')
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

# wrr_peer_dir <dialing_host_name> — the direction label for a dialer, empty (rc 1) for any host that is not one of
# the two roster hosts. soleur-web-platform is web-1, soleur-web-2 is web-2 (raw.host_name; CONTAINER_NAME is the
# same on both hosts and is never used to tell them apart).
wrr_peer_dir() {
  case "${1:-}" in
    "$WRR_PEER_HOST_NAME") printf 'w1_to_w2' ;;
    "$WRR_HOST_NAME") printf 'w2_to_w1' ;;
    *) return 1 ;;
  esac
}

# wrr_peer_sql <dialing_host_name> <ipv4> — the dialing host's newest peer-probe rows about the given peer address.
# Both arguments are validated by the caller (wrr_peer_fetch) before they reach the SQL text.
# HOT + ARCHIVE (2026-11-08, run 42457219868). This row is written once per deploy, so it is usually OLDER than the
# ~40-minute hot window: a remote()-only read answered zero rows and the serve step refused RED reason=peer_rows_none
# although result=ok rows existed hours back. Rows past the hot window are readable ONLY through the s3Cluster archive,
# so the FROM is the runbook's UNION ALL of both (betterstack-log-query.md "Hot vs archive"). A row present in both arms
# is harmless: same dt, same age_s, same verdict (the judge's newest-row/tie rules are pinned for duplicates by JP11j-m).
# ORDER BY dt DESC puts the newest row first and LIMIT 50 (WRR_PEER_LIMIT) stays enough with overlap doubling it: the
# judge reads only the newest age, so 50 rows still cover >= 25 distinct probes. Both lines are pinned by the test's guard.
# The own-line read (wrr_sql) is one row a minute over 180 s and stays hot-only. `$BS_TABLE_S3` is substituted by the
# query script, derived from the default hot table, so the three BETTERSTACK_QUERY_* variables are all it needs.
wrr_peer_sql() {
  cat <<SQL
SELECT dateDiff('second', dt, now()) AS age_s, JSONExtractString(raw,'host_name') AS host_name, JSONExtractString(raw,'message') AS line
FROM (SELECT dt, raw FROM remote(\$BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
WHERE dt > now() - INTERVAL ${WRR_PEER_LOOKBACK_S} SECOND
  AND JSONExtractString(raw,'host_name') = '$1'
  AND JSONExtractString(raw,'SYSLOG_IDENTIFIER') = 'ci-deploy'
  AND startsWith(JSONExtractString(raw,'message'), 'relay_peer_probe peer=$2 ')
ORDER BY dt DESC LIMIT ${WRR_PEER_LIMIT}
FORMAT JSONEachRow
SQL
}

# wrr_peer_fetch <outfile> <dialing_host_name> <peer_private_ipv4> — same rc contract as wrr_fetch (plus rc 1 on an
# unknown dialing host or a non-IPv4 argument, before any query is sent).
wrr_peer_fetch() {
  if ! wrr_peer_dir "${2:-}" >/dev/null; then
    echo "wrr_peer_fetch: dialing host is not a roster host" >&2; return 1
  fi
  if [[ ! "${3:-}" =~ ^10\.0\.1\.[0-9]{1,3}$ ]]; then
    echo "wrr_peer_fetch: peer address is not a 10.0.1.x IPv4" >&2; return 1
  fi
  w2l_query "$(wrr_peer_sql "$2" "$3")" "$1"
}

# wrr_peer_judge <rows.jsonl> <dialing_host_name> <peer_private_ipv4> — the PEER-LINE judge for ONE direction. GREEN iff
# the NEWEST row (smallest age_s; every row tied at that age) from the DIALING host about this peer, within the 24 h
# lookback, is result=ok. The serve gate needs it GREEN in BOTH directions (web-1 dialing web-2, and web-2 dialing web-1:
# existing sessions are owned by web-1, so web-2's relay client must reach it). Every verdict carries the direction:
#   GREEN peer_age_s=<s> peer=<ip> dir=<w1_to_w2|w2_to_w1>
#   RED reason=<peer_addr_invalid|body_unparseable|peer_row_age_malformed|peer_rows_none|peer_row_malformed|peer_<result>|peer_skipped> dir=<...>
#   RED reason=peer_dialer_invalid                (the dialing host is not a roster host; no direction exists)
wrr_peer_judge() {
  local f="$1" dh="${2:-}" ip="${3:-}" out dir
  dir="$(wrr_peer_dir "$dh")" || { printf 'RED reason=peer_dialer_invalid\n'; return 0; }
  if [[ ! "$ip" =~ ^10\.0\.1\.[0-9]{1,3}$ ]]; then
    printf 'RED reason=peer_addr_invalid dir=%s\n' "$dir"; return 0
  fi
  if ! jq -e -s 'all(.[]; type == "object")' "$f" >/dev/null 2>&1; then
    printf 'RED reason=body_unparseable dir=%s\n' "$dir"; return 0
  fi
  out="$(jq -r -s --arg host "$dh" --arg ip "$ip" --argjson win "$WRR_PEER_LOOKBACK_S" '
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
  printf '%s dir=%s\n' "$out" "$dir"
}
