#!/usr/bin/env bash
# web2-luks-rows.sh — the ONE definition of "web-2's LUKS evidence rows in Better Stack" (#6931, Guard 3).
#
# Two readers need the same answer to "is web-2's /mnt/data on a LUKS mapper, per its own telemetry":
#   - .github/workflows/workspaces-luks-verify.yml, job `web2_marker` — writes or deletes the soak
#     marker WORKSPACES_LUKS_CUTOVER_AT;
#   - scripts/followthroughs/web2-luks-live-6931.sh — the soak-gated closure of #6931, which grades from the
#     probe rows alone (it never reads the marker, so it holds no Doppler credential).
# Re-implementing the query or the parse in the second one is how the two drift into disagreeing about
# what "green" means, so both source this file. Sourceable under `set -u`/`set -e`; sets no shell options.
#
# ROW CONTRACT (the emitters are owned elsewhere; this parser is coded to EXACTLY this):
#
#   Readiness row — direct-curl to Better Stack Logs (source 2457081), message text only. It carries NO
#   host dimension of its own (no host_name/SYSLOG_IDENTIFIER: it does not travel through Vector), so
#   its attribution to web-2 is the self-asserted `host=` token in the message, and nothing else.
#   It is emitted ONCE PER INSTANCE (cloud-init runcmd), not per boot:
#     SOLEUR_FRESH_BOOT_READY ready=<0|1> stage=cloud_init_complete token=<0|1> vector=<0|1> volume=<0|1>
#       luks=<0|1> luks_arm=<formatted|opened|noop|none> escrow=<ok|missing|none> boot_id=<lowercase uuid>
#       host=<hostname> reason=<word> boot_window_s=900
#
#   Probe row — SyslogIdentifier luks-monitor, shipped by Vector (host_name is Vector-injected, so this
#   row's attribution is the stronger one), written daily and stamped with the CURRENT boot's id. Each log() line is journaled
#   twice (the logger copy, and the unit's stdout copy prefixed `[luks-monitor] `); only the stdout copy
#   carries _SYSTEMD_UNIT, so the SQL keeps that copy and the parse still accepts both spellings:
#     OK: /mnt/data is LUKS-backed (device_type=crypto_LUKS mount_source=/dev/mapper/workspaces escrow=ok header=readable boot_id=<lowercase uuid>)
#   A failing probe logs `FAIL (<reason>): ...` instead, which is a RED row.
#
# NB the two `escrow=ok` tokens differ: the probe row's is the Doppler passphrase re-test (the escrowed passphrase
# still opens the header); the readiness row's is the off-host HEADER copy. Both are required to earn the marker.
# The `key=value` tokens are parsed as a MAP, not a fixed sequence: an unknown extra key is ignored (an
# emitter may grow a field), while a duplicated key, a missing required key or an unequal one is RED.
# `boot_id` is printed (uuid, else `unknown`) and is NOT part of the age join, because the readiness row is
# per-instance and the probe row per-boot, so the two legitimately differ after any reboot. It is also not part of
# the verdict: no reboot is required (owner decision 2026-10-07, ADR-263 addendum 2026-10-08). What the marker-absent decision
# in w2l_judge and the follow-through need instead is w2l_ready_arm: the newest readiness row must say the boot
# FORMATTED or OPENED the volume.
#
# THE JOIN IS INSTANCE-LEVEL. A probe row certifies the instance that wrote a green readiness row when it is
# NOT OLDER than that row (probe age_s <= readiness age_s): older, and it may belong to the host this one
# replaced (`RED reason=probe_predates_ready`).
#
# VERDICT VOCABULARY. A judge prints exactly one line on stdout and returns 0 (the verdict is the data):
#   GREEN boot_id=<uuid|unknown> age_s=<n>   a POSITIVE count: >=1 probe row, shape-checked, every required
#                                       field present and equal, probe age <= W2L_MAX_AGE_S; and, when EARNING
#                                       the marker, a green readiness row that the probe row is not older than
#                                       and whose luks_arm is formatted|opened (`RED reason=ready_luks_arm`;
#                                       w2l_ready_verdict alone also tolerates noop, which only the marker refuses)
#   RED reason=<token>                  negative evidence, OR an empty / unparseable body (zero counted rows)
# GREEN is decided from the positive count and never from "no culprit named". A QUERY FAILURE (transport,
# 5xx, 429, timeout, credentials absent) is NEITHER: w2l_query returns non-zero, no judge is ever called, and
# the caller must leave the marker exactly as it is (a vendor blip must not reset a 3-day soak).
#
# EARNING vs KEEPING. With the marker ABSENT both rows are required, the readiness row with a formatted|opened arm
# (a noop or arm-less boot never heals by waiting: only replacing the host does). With it PRESENT the newest probe row alone
# keeps it (the readiness row's W2L_READY_LOOKBACK_D lookback expires on a host that never reboots); a
# readiness row NEWER than that probe row is a rebirth and still turns it RED.

# The W2L_* constants are read by the sourcing scripts (the workflow step, the follow-through).
# shellcheck disable=SC2034
[[ -n "${_W2L_LIB_LOADED:-}" ]] && return 0
_W2L_LIB_LOADED=1

export LC_ALL=C

W2L_HOST_NAME="soleur-web-2"
W2L_PROBE_IDENT="luks-monitor"
W2L_PROBE_UNIT="luks-monitor.service"
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
# the latest verdict, and pins the emitting UNIT as well as the identifier: SYSLOG_IDENTIFIER is sender-chosen
# (`logger -t luks-monitor ...` from any local process), _SYSTEMD_UNIT is not. The readiness predicate anchors
# the marker at the START of the message, because a GitHub issue or webhook body that merely QUOTES the marker
# is shipped under other identifiers. It uses startsWith()/position(), never LIKE: the marker name contains
# `_`, which LIKE reads as a one-character wildcard.
# $1 lookback hours, $2 row limit.
w2l_sql_probe() {
  printf '%s' "SELECT toString(dt) AS ts, dateDiff('second', dt, now()) AS age_s, JSONExtractString(raw,'message') AS message, JSONExtractString(raw,'host_name') AS host_name, JSONExtractString(raw,'SYSLOG_IDENTIFIER') AS ident, JSONExtractString(raw,'_SYSTEMD_UNIT') AS unit
FROM (SELECT dt, raw FROM remote(\$BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
WHERE dt > now() - INTERVAL ${1:?} HOUR
  AND JSONExtractString(raw,'host_name') = '${W2L_HOST_NAME}'
  AND JSONExtractString(raw,'SYSLOG_IDENTIFIER') = '${W2L_PROBE_IDENT}'
  AND JSONExtractString(raw,'_SYSTEMD_UNIT') = '${W2L_PROBE_UNIT}'
  AND (JSONExtractString(raw,'message') LIKE '%OK: /mnt/data is LUKS-backed%' OR JSONExtractString(raw,'message') LIKE '%FAIL (%')
ORDER BY dt DESC LIMIT ${2:?}
FORMAT JSONEachRow"
}

# $1 lookback days, $2 row limit.
w2l_sql_ready() {
  printf '%s' "SELECT toString(dt) AS ts, dateDiff('second', dt, now()) AS age_s, JSONExtractString(raw,'message') AS message
FROM (SELECT dt, raw FROM remote(\$BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
WHERE dt > now() - INTERVAL ${1:?} DAY
  AND startsWith(JSONExtractString(raw,'message'), '${W2L_READY_MARKER} ')
  AND position(JSONExtractString(raw,'message'), ' host=${W2L_HOST_NAME} ') > 0
ORDER BY dt DESC LIMIT ${2:?}
FORMAT JSONEachRow"
}

# --- Query ------------------------------------------------------------------------------------------
# w2l_query <sql> <outfile>
#   rc 0  the query ANSWERED; <outfile> holds the body (possibly empty — that is evidence, not failure)
#   rc 1  the query FAILED (any non-zero from the query script, including the timeout's 124): no judgement
#         may be made and the caller must leave state untouched. A one-line scrubbed class goes to stderr.
# EVERY credential-shaped variable except the three BETTERSTACK_QUERY_* values is withheld from the child: the
# query script needs only those, and a marker write token (or any token a sourcing script happens to hold) must
# not travel into a process that does not use it. Name-pattern based, so a secret added later is covered too.
w2l_query() {
  local sql="$1" out="$2" rc=0 cls v
  local -a unset_args=()
  while IFS= read -r v; do
    case "$v" in
      BETTERSTACK_QUERY_HOST|BETTERSTACK_QUERY_USERNAME|BETTERSTACK_QUERY_PASSWORD) ;;
      *TOKEN*|*SECRET*|*PASSWORD*|*KEY*|*CREDENTIAL*|*AUTH*|*_CLIENT_ID|DOPPLER*) unset_args+=(-u "$v") ;;
    esac
  done < <(compgen -e)
  env ${unset_args[@]+"${unset_args[@]}"} timeout "${W2L_QUERY_TIMEOUT_S}" bash "$W2L_QUERY_SCRIPT" "$sql" >"$out" 2>"$out.err" || rc=$?
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
def bid: ((.f.boot_id // "") | if uuid then . else "unknown" end);
def classify_probe($host; $ident; $unit):
  (str(.message) | sub("^\\[luks-monitor\\] "; "")) as $m
  | age as $age
  | if (.host_name != $host or .ident != $ident or .unit != $unit or $age == null) then {kind: "junk", age: ($age // 0)}
    elif ($m | test("^OK: /mnt/data is LUKS-backed \\([^()]*\\)$")) then
      (kvs($m | capture("^OK: /mnt/data is LUKS-backed \\((?<b>[^()]*)\\)$").b)) as $f
      | if $f == null then {kind: "junk", age: $age} else {kind: "ok", age: $age, f: $f} end
    elif ($m | test("^FAIL \\([a-z_]+\\): ")) then {kind: "fail", age: $age}
    else {kind: "junk", age: $age} end;
def row_green:
  .kind == "ok" and (.f.device_type // "") == "crypto_LUKS"
  and (.f.mount_source // "") == "/dev/mapper/workspaces" and (.f.escrow // "") == "ok";
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

# w2l_probe_verdict <probe.jsonl> — GREEN/RED on the NEWEST probe row alone (fresh, LUKS, escrow ok).
w2l_probe_verdict() {
  local f="$1" out
  if ! _w2l_body_ok "$f"; then printf 'RED reason=probe_body_unparseable\n'; return 0; fi
  out="$(jq -r -s --arg host "$W2L_HOST_NAME" --arg ident "$W2L_PROBE_IDENT" --arg unit "$W2L_PROBE_UNIT" --argjson max "$W2L_MAX_AGE_S" \
    "${_W2L_JQ_DEFS}"'
    [ .[] | classify_probe($host; $ident; $unit) ] | sort_by(.age) as $rows
    | if ($rows | length) == 0 then "RED reason=no_probe_row"
      else $rows[0] as $r
      | if $r.kind == "fail" then "RED reason=probe_fail_row"
        elif $r.kind != "ok" then "RED reason=probe_malformed"
        elif $r.age > $max then "RED reason=probe_stale"
        elif ($r.f.device_type // "") != "crypto_LUKS" then "RED reason=probe_not_luks"
        elif ($r.f.mount_source // "") != "/dev/mapper/workspaces" then "RED reason=probe_mount_source"
        elif ($r.f.escrow // "") != "ok" then "RED reason=probe_escrow"
        else "GREEN boot_id=\($r | bid) age_s=\($r.age)" end
      end' "$f" 2>/dev/null)" || out=""
  [[ -n "$out" ]] || out="RED reason=probe_judge_error"
  printf '%s\n' "$out"
}

# w2l_ready_verdict <ready.jsonl> — GREEN/RED on the NEWEST readiness row alone.
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
        else "GREEN boot_id=\($r | bid) age_s=\($r.age)" end
      end' "$f" 2>/dev/null)" || out=""
  [[ -n "$out" ]] || out="RED reason=ready_judge_error"
  printf '%s\n' "$out"
}

# w2l_ready_newest_age <ready.jsonl> — age_s of the newest WELL-FORMED readiness row for this host, whatever its
# verdict; prints nothing when there is none or the body is unparseable (then nothing is known about a rebirth).
w2l_ready_newest_age() {
  _w2l_body_ok "$1" || return 0
  jq -r -s --arg host "$W2L_HOST_NAME" "${_W2L_JQ_DEFS}"'
    [ .[] | classify_ready | select(.kind == "row" and (.f.host // "") == $host) ] | sort_by(.age) | (.[0].age // empty)' "$1" 2>/dev/null || true
}

# w2l_ready_arm <ready.jsonl> — the luks_arm of the NEWEST readiness row (the row w2l_ready_verdict judges: a newer
# malformed or foreign row hides an older good one); rc 0 only for `formatted` or `opened`. This is the one definition
# of the rule that replaced the reboot proof (owner decision 2026-10-07, ADR-263 addendum 2026-10-08): the boot that
# wrote the readiness row must have FORMATTED a raw volume or OPENED an existing LUKS container. `noop` (which
# w2l_ready_verdict still tolerates) is NOT accepted, nor is a row with no arm. Prints the arm when it is a known
# value so a caller can name it; fails closed (rc 1) on an unparseable body, no row, or a row that is not this host's.
w2l_ready_arm() {
  local arm
  _w2l_body_ok "$1" || return 1
  arm="$(jq -r -s --arg host "$W2L_HOST_NAME" "${_W2L_JQ_DEFS}"'
    [ .[] | classify_ready ] | sort_by(.age) | .[0] // empty
    | select(.kind == "row" and (.f.host // "") == $host)
    | (.f.luks_arm // "") | select(. == "formatted" or . == "opened" or . == "noop")' "$1" 2>/dev/null)" || return 1
  [[ -n "$arm" ]] || return 1
  printf '%s\n' "$arm"
  [[ "$arm" == formatted || "$arm" == opened ]]
}

# w2l_judge <probe.jsonl> <ready.jsonl> [absent|present] — the combined verdict; the third argument is the
# marker's CURRENT state (default `absent`, the strict one). The probe row is judged first (its reasons are the
# ones an operator can act on). Then:
#   marker present  the probe row keeps it, unless a readiness row is NEWER than the probe row (a rebirth: the
#                   probe belongs to the host that was replaced) -> RED probe_predates_ready
#   marker absent   the newest readiness row must be GREEN too, its luks_arm must be formatted|opened (w2l_ready_arm),
#                   and the probe row must not be older than it. No reboot is required (ADR-263 addendum 2026-10-08).
w2l_judge() {
  local pv rv pa ra marker="${3:-absent}"
  pv="$(w2l_probe_verdict "$1")"
  [[ "$pv" == GREEN* ]] || { printf '%s\n' "$pv"; return 0; }
  pa="$(sed -nE 's/^GREEN .* age_s=([0-9]+)$/\1/p' <<<"$pv")"
  [[ "$pa" =~ ^[0-9]+$ ]] || { printf 'RED reason=probe_judge_error\n'; return 0; }
  if [[ "$marker" == present ]]; then
    ra="$(w2l_ready_newest_age "$2")"
  else
    rv="$(w2l_ready_verdict "$2")"
    [[ "$rv" == GREEN* ]] || { printf '%s\n' "$rv"; return 0; }
    ra="$(sed -nE 's/^GREEN .* age_s=([0-9]+)$/\1/p' <<<"$rv")"
    [[ "$ra" =~ ^[0-9]+$ ]] || { printf 'RED reason=ready_judge_error\n'; return 0; }
  fi
  if [[ "$ra" =~ ^[0-9]+$ ]] && (( pa > ra )); then printf 'RED reason=probe_predates_ready\n'; return 0; fi
  # Marker absent: the readiness row must say the boot formatted or opened the volume (the one shared definition).
  if [[ "$marker" != present ]] && ! w2l_ready_arm "$2" >/dev/null; then printf 'RED reason=ready_luks_arm\n'; return 0; fi
  printf '%s\n' "$pv"
}

# w2l_soak_scan <probe.jsonl> <window_s> — "<green_days> <not_green_rows>" over the probe verdict rows younger than
# <window_s> (the age of the readiness row that opens the soak). A "day" is a 24 h bucket counted from that
# readiness row (bucket = floor((window_s - row age) / 86400)), so three distinct buckets span at least 48 h and
# daily rows cannot collapse into fewer days. A not-green row is a FAIL line, a malformed line, or an OK line that
# does not report LUKS. Prints nothing and returns 1 when the body is unparseable.
w2l_soak_scan() {
  _w2l_body_ok "$1" || return 1
  jq -r -s --arg host "$W2L_HOST_NAME" --arg ident "$W2L_PROBE_IDENT" --arg unit "$W2L_PROBE_UNIT" --argjson win "$2" \
    "${_W2L_JQ_DEFS}"'
    [ .[] | classify_probe($host; $ident; $unit) | select(.age <= $win) ] as $rows
    | ($rows | map(select(row_green) | ((($win - .age) / 86400) | floor)) | unique | length) as $d
    | ($rows | map(select(row_green | not)) | length) as $r
    | "\($d) \($r)"' "$1" 2>/dev/null
}
