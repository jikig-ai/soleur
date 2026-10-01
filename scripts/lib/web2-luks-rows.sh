#!/usr/bin/env bash
# web2-luks-rows.sh — the ONE definition of "web-2's LUKS evidence rows in Better Stack" (#6931, Guard 3).
#
# Two readers need the same answer to "is web-2's /mnt/data on a LUKS mapper, per its own telemetry":
#   - .github/workflows/workspaces-luks-verify.yml, job `web2_marker` — writes or deletes the soak
#     marker WORKSPACES_LUKS_CUTOVER_AT;
#   - scripts/followthroughs/web2-luks-live-6931.sh — the soak-gated closure of #6931.
# Re-implementing the query or the parse in the second one is how the two drift into disagreeing about
# what "green" means, so both source this file. Sourceable under `set -u`/`set -e`; sets no shell options.
#
# ROW CONTRACT (the emitters are owned elsewhere; this parser is coded to EXACTLY this):
#
#   Readiness row — direct-curl to Better Stack Logs (source 2457081), message text only. It carries NO
#   host dimension of its own (no host_name/SYSLOG_IDENTIFIER: it does not travel through Vector), so
#   its attribution to web-2 is the self-asserted `host=` token in the message, and nothing else:
#     SOLEUR_FRESH_BOOT_READY ready=<0|1> stage=cloud_init_complete token=<0|1> vector=<0|1> volume=<0|1>
#       luks=<0|1> luks_arm=<formatted|opened|noop|none> escrow=<ok|missing|none> boot_id=<lowercase uuid>
#       host=<hostname> reason=<word> boot_window_s=900
#
#   Probe row — SyslogIdentifier luks-monitor, shipped by Vector (host_name is Vector-injected, so this
#   row's attribution is the stronger one). Each log() line is journaled twice (the logger copy, and the
#   unit's stdout copy prefixed `[luks-monitor] `); both spellings are accepted and are identical in content:
#     OK: /mnt/data is LUKS-backed (device_type=crypto_LUKS mount_source=/dev/mapper/workspaces escrow=ok header=readable boot_id=<lowercase uuid>)
#   A failing probe logs `FAIL (<reason>): ...` instead, which is a RED row.
#
# The `key=value` tokens are parsed as a MAP, not a fixed sequence: an unknown extra key is ignored (an
# emitter may grow a field), while a duplicated key, a missing required key or an unequal one is RED.
#
# VERDICT VOCABULARY. A judge prints exactly one line on stdout and returns 0 (the verdict is the data):
#   GREEN boot_id=<uuid> age_s=<n>      a POSITIVE count: >=1 probe row AND >=1 readiness row, shape-checked,
#                                       every required field present and equal, probe row age <= W2L_MAX_AGE_S,
#                                       and both rows name the same boot_id
#   RED reason=<token>                  negative evidence, OR an empty / unparseable body (zero counted rows)
# GREEN is decided from the positive count and never from "no culprit named". A QUERY FAILURE (transport,
# 5xx, 429, timeout, credentials absent) is NEITHER: w2l_query returns non-zero, no judge is ever called, and
# the caller must leave the marker exactly as it is (a vendor blip must not reset a 3-day soak).
#
# Readiness-row age is deliberately unbounded within W2L_READY_LOOKBACK_D: it is written once per BOOT, so a
# healthy host that has been up for a week has a week-old readiness row. What bounds it is the join: the
# probe row (daily, <=26h) must carry the same boot_id.

# The W2L_* constants are read by the sourcing scripts (the workflow step, the follow-through).
# shellcheck disable=SC2034
[[ -n "${_W2L_LIB_LOADED:-}" ]] && return 0
_W2L_LIB_LOADED=1

export LC_ALL=C

W2L_HOST_NAME="soleur-web-2"
W2L_PROBE_IDENT="luks-monitor"
W2L_READY_MARKER="SOLEUR_FRESH_BOOT_READY"
W2L_MARKER_NAME="WORKSPACES_LUKS_CUTOVER_AT"
W2L_MARKER_PROJECT="soleur"
W2L_MARKER_CONFIG="prd_workspaces_luks_marker"
# 26h: the daily probe can space two runs 24h30m apart (OnCalendar=daily + RandomizedDelaySec=1800), so 24h
# would read stale on a healthy day; 26h clears it with margin and is the ceiling the plan states.
W2L_MAX_AGE_S=93600
W2L_PROBE_LOOKBACK_H=48
W2L_READY_LOOKBACK_D=90
W2L_QUERY_TIMEOUT_S=120

_w2l_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# NOT overridable from the environment: betterstack-query.sh is the egress boundary (host allowlist, trace
# refusal), and a seam an actor can set is the seam that pin exists to close. A test shims `curl` instead.
W2L_QUERY_SCRIPT="$_w2l_lib_dir/../betterstack-query.sh"

# bs_read_classify names a failed read (credentials-absent / transport / credentials-rejected / ...).
# shellcheck source=scripts/lib/betterstack-read-classify.sh
source "$_w2l_lib_dir/betterstack-read-classify.sh"

# --- SQL ------------------------------------------------------------------------------------------
# Raw SQL (betterstack-query.sh mode 1) on purpose: that script has no host flag and its repeated --grep
# terms OR-combine, so a --grep-based read would let another host's row certify this one. The host predicate
# is an explicit AND in the OUTER WHERE, which binds both the hot arm and the archive arm. The archive arm is
# required: remote() alone is the ~40-minute hot window, and a 26h freshness judgement over it would read
# every healthy host as absent. `$BS_TABLE` / `$BS_TABLE_S3` are substituted by the query script, so they
# are single-quoted here on purpose.
#
# age_s is computed by the SERVER (dateDiff against now()), so the freshness verdict has no runner-clock
# or timestamp-format dependency and a fixture can state the age it means.
# NO output alias may reuse the name of a source column (`dt`, `raw`): ClickHouse resolves a SELECT alias ahead
# of a column of the same name inside WHERE/ORDER BY, so `toString(dt) AS dt` would turn the time filter into
# a String-vs-DateTime comparison. The string form is `ts`.
#
# The probe predicate selects VERDICT rows only (the OK line and the FAIL line), so the newest such row is
# the latest verdict; the readiness predicate anchors the marker at the START of the message, because a
# GitHub issue or webhook body that merely QUOTES the marker is shipped under other identifiers.
# $1 lookback hours, $2 row limit.
w2l_sql_probe() {
  printf '%s' "SELECT toString(dt) AS ts, dateDiff('second', dt, now()) AS age_s, JSONExtractString(raw,'message') AS message, JSONExtractString(raw,'host_name') AS host_name, JSONExtractString(raw,'SYSLOG_IDENTIFIER') AS ident
FROM (SELECT dt, raw FROM remote(\$BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
WHERE dt > now() - INTERVAL ${1:?} HOUR
  AND JSONExtractString(raw,'host_name') = '${W2L_HOST_NAME}'
  AND JSONExtractString(raw,'SYSLOG_IDENTIFIER') = '${W2L_PROBE_IDENT}'
  AND (JSONExtractString(raw,'message') LIKE '%OK: /mnt/data is LUKS-backed%' OR JSONExtractString(raw,'message') LIKE '%FAIL (%')
ORDER BY dt DESC LIMIT ${2:?}
FORMAT JSONEachRow"
}

# $1 lookback days, $2 row limit.
w2l_sql_ready() {
  printf '%s' "SELECT toString(dt) AS ts, dateDiff('second', dt, now()) AS age_s, JSONExtractString(raw,'message') AS message
FROM (SELECT dt, raw FROM remote(\$BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
WHERE dt > now() - INTERVAL ${1:?} DAY
  AND JSONExtractString(raw,'message') LIKE '${W2L_READY_MARKER} %'
  AND JSONExtractString(raw,'message') LIKE '% host=${W2L_HOST_NAME} %'
ORDER BY dt DESC LIMIT ${2:?}
FORMAT JSONEachRow"
}

# --- Query ------------------------------------------------------------------------------------------
# w2l_query <sql> <outfile>
#   rc 0  the query ANSWERED; <outfile> holds the body (possibly empty — that is evidence, not failure)
#   rc 1  the query FAILED (any non-zero from the query script, including the timeout's 124): no judgement
#         may be made and the caller must leave state untouched. A one-line scrubbed class goes to stderr.
# DOPPLER_TOKEN is withheld from the child: the query script needs only the three BETTERSTACK_QUERY_* values,
# and the marker WRITE token must not travel into a process that does not use it.
w2l_query() {
  local sql="$1" out="$2" rc=0 cls
  env -u DOPPLER_TOKEN timeout "${W2L_QUERY_TIMEOUT_S}" bash "$W2L_QUERY_SCRIPT" "$sql" >"$out" 2>"$out.err" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    cls="$(bs_read_classify "$rc" "$out")"
    printf 'web2-luks-rows: Better Stack read FAILED rc=%s class=%s first-stderr-line=%s\n' \
      "$rc" "$cls" "$(bs_read_scrub_err1 "$out.err")" >&2
    return 1
  fi
  return 0
}

# w2l_fetch_probe <outfile> [lookback_hours] [limit] / w2l_fetch_ready <outfile> [lookback_days] [limit]
w2l_fetch_probe() { w2l_query "$(w2l_sql_probe "${2:-$W2L_PROBE_LOOKBACK_H}" "${3:-20}")" "$1"; }
w2l_fetch_ready() { w2l_query "$(w2l_sql_ready "${2:-$W2L_READY_LOOKBACK_D}" "${3:-20}")" "$1"; }

# --- Parse ------------------------------------------------------------------------------------------
# jq definitions shared by every judge. `kvs` turns "k=v k2=v2" into a map, or null when any token is not
# k=v or a key repeats; `age` accepts ClickHouse's quoted-64-bit-integer spelling ("3600") and a bare number.
_W2L_JQ_DEFS="$(cat <<'JQ'
def uuid: test("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$");
def kvs($body):
  ($body | split(" ")) as $t
  | if (($t | all(test("^[a-z_]+=[^ =]+$"))) | not) then null
    else ($t | map(capture("^(?<k>[a-z_]+)=(?<v>[^ =]+)$"))) as $p
      | if (($p | map(.k) | length) != ($p | map(.k) | unique | length)) then null
        else ($p | map({(.k): .v}) | add) end
    end;
def age: ((.age_s | tostring) as $a | if ($a | test("^[0-9]+$")) then ($a | tonumber) else null end);
def str($v): ($v | if type == "string" then . else "" end);
def classify_probe($host; $ident):
  (str(.message) | sub("^\\[luks-monitor\\] "; "")) as $m
  | age as $age
  | if (.host_name != $host or .ident != $ident or $age == null) then {kind: "junk", age: ($age // 0)}
    elif ($m | test("^OK: /mnt/data is LUKS-backed \\([^()]*\\)$")) then
      (kvs($m | capture("^OK: /mnt/data is LUKS-backed \\((?<b>[^()]*)\\)$").b)) as $f
      | if $f == null then {kind: "junk", age: $age} else {kind: "ok", age: $age, f: $f} end
    elif ($m | test("^FAIL \\([a-z_]+\\): ")) then {kind: "fail", age: $age}
    else {kind: "junk", age: $age} end;
def classify_ready:
  str(.message) as $m
  | age as $age
  | if ($age == null) then {kind: "junk", age: 0}
    elif ($m | test("^SOLEUR_FRESH_BOOT_READY( [a-z_]+=[^ =]+)+$")) then
      (kvs($m | sub("^SOLEUR_FRESH_BOOT_READY "; ""))) as $f
      | if $f == null then {kind: "junk", age: $age} else {kind: "row", age: $age, f: $f} end
    else {kind: "junk", age: $age} end;
JQ
)"

# _w2l_body_ok <file> — the body is zero or more JSON objects, one per line. A body that is not (an HTML
# error page, an exception echoed with HTTP 200, a truncated line) is UNPARSEABLE, which is RED: it counted
# zero rows. An EMPTY body is parseable and counts zero rows too.
_w2l_body_ok() {
  jq -e -s 'all(.[]; type == "object")' "$1" >/dev/null 2>&1
}

# w2l_probe_verdict <probe.jsonl> — GREEN/RED on the probe row alone (fresh, LUKS, escrow ok, uuid boot_id).
w2l_probe_verdict() {
  local f="$1" out
  if ! _w2l_body_ok "$f"; then printf 'RED reason=probe_body_unparseable\n'; return 0; fi
  out="$(jq -r -s --arg host "$W2L_HOST_NAME" --arg ident "$W2L_PROBE_IDENT" --argjson max "$W2L_MAX_AGE_S" \
    "${_W2L_JQ_DEFS}"'
    [ .[] | classify_probe($host; $ident) ] | sort_by(.age) as $rows
    | if ($rows | length) == 0 then "RED reason=no_probe_row"
      else $rows[0] as $r
      | if $r.kind == "fail" then "RED reason=probe_fail_row"
        elif $r.kind != "ok" then "RED reason=probe_malformed"
        elif $r.age > $max then "RED reason=probe_stale"
        elif ($r.f.device_type // "") != "crypto_LUKS" then "RED reason=probe_not_luks"
        elif ($r.f.mount_source // "") != "/dev/mapper/workspaces" then "RED reason=probe_mount_source"
        elif ($r.f.escrow // "") != "ok" then "RED reason=probe_escrow"
        elif ((($r.f.boot_id // "") | uuid) | not) then "RED reason=probe_boot_id"
        else "GREEN boot_id=\($r.f.boot_id) age_s=\($r.age)" end
      end' "$f" 2>/dev/null)" || out=""
  [[ -n "$out" ]] || out="RED reason=probe_judge_error"
  printf '%s\n' "$out"
}

# w2l_ready_verdict <ready.jsonl> — GREEN/RED on the newest readiness row alone.
w2l_ready_verdict() {
  local f="$1" out
  if ! _w2l_body_ok "$f"; then printf 'RED reason=ready_body_unparseable\n'; return 0; fi
  out="$(jq -r -s --arg host "$W2L_HOST_NAME" \
    "${_W2L_JQ_DEFS}"'
    [ .[] | classify_ready ] | sort_by(.age) as $rows
    | if ($rows | length) == 0 then "RED reason=no_ready_row"
      else $rows[0] as $r
      | if $r.kind != "row" then "RED reason=ready_malformed"
        elif ($r.f.host // "") != $host then "RED reason=ready_host"
        elif ($r.f.ready // "") != "1" then "RED reason=ready_not_ready"
        elif ($r.f.stage // "") != "cloud_init_complete" then "RED reason=ready_stage"
        elif ($r.f.token // "") != "1" or ($r.f.vector // "") != "1" or ($r.f.volume // "") != "1" then "RED reason=ready_unit"
        elif ($r.f.luks // "") != "1" then "RED reason=ready_not_luks"
        elif (["formatted","opened","noop"] | index($r.f.luks_arm // "")) == null then "RED reason=ready_luks_arm"
        elif ($r.f.escrow // "") != "ok" then "RED reason=ready_escrow"
        elif ((($r.f.boot_id // "") | uuid) | not) then "RED reason=ready_boot_id"
        else "GREEN boot_id=\($r.f.boot_id)" end
      end' "$f" 2>/dev/null)" || out=""
  [[ -n "$out" ]] || out="RED reason=ready_judge_error"
  printf '%s\n' "$out"
}

# w2l_judge <probe.jsonl> <ready.jsonl> — the combined verdict. Probe first (its reasons are the ones an
# operator can act on), then the readiness row, then the join on boot_id: a probe row that predates the
# current boot can never certify it.
w2l_judge() {
  local pv rv pb rb
  pv="$(w2l_probe_verdict "$1")"
  [[ "$pv" == GREEN* ]] || { printf '%s\n' "$pv"; return 0; }
  rv="$(w2l_ready_verdict "$2")"
  [[ "$rv" == GREEN* ]] || { printf '%s\n' "$rv"; return 0; }
  pb="$(sed -nE 's/^GREEN boot_id=([^ ]+).*$/\1/p' <<<"$pv")"
  rb="$(sed -nE 's/^GREEN boot_id=([^ ]+).*$/\1/p' <<<"$rv")"
  if [[ -z "$pb" || "$pb" != "$rb" ]]; then printf 'RED reason=boot_id_mismatch\n'; return 0; fi
  printf '%s\n' "$pv"
}

# w2l_reds_since <probe.jsonl> <window_s> — how many NON-GREEN probe verdict rows (a FAIL line or a
# malformed one) are younger than <window_s> seconds. Used by the follow-through's "no red row since the
# marker was written". Prints an integer; prints nothing and returns 1 when the body is unparseable.
w2l_reds_since() {
  _w2l_body_ok "$1" || return 1
  jq -r -s --arg host "$W2L_HOST_NAME" --arg ident "$W2L_PROBE_IDENT" --argjson win "$2" \
    "${_W2L_JQ_DEFS}"'
    [ .[] | classify_probe($host; $ident) | select(.kind != "ok" and .age <= $win) ] | length' "$1" 2>/dev/null
}
