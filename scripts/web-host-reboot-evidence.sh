#!/usr/bin/env bash
# Read-only evidence for the web-host reboot workflow (#9372): what do the rows in Better Stack show after a reboot request
# for web-2? Called by .github/workflows/web-host-reboot.yml (job `observe`, and a snapshot step before the request) and,
# later and with no second approval, by the dispatching agent under `doppler run -p soleur -c prd_terraform --`.
# Retires together with scripts/web-host-reboot.sh.
#
#   snapshot                                   print `pre-request context:` (the newest readiness row, probe row and journald
#                                              boot, as ids and ages). A read fault prints `unavailable` and still exits 0.
#   grade --anchor <epoch> [--window-min <n>] [--poll-s <n>]
#                                              read the rows until a wall-clock deadline (default 40 min, 60 s apart) or until a
#                                              PASS, FAIL or a re-created instance ends it. --window-min 0 is a single read.
#
# Exit: 0 PASS (row presence only), 1 FAIL, 2 NOT YET (the expected pending state, or a read fault), 3 cannot establish
# (credentials, helper, arguments), 4 the deadline passed with no boot seen, with the old boot still shipping, or with a
# new boot that went silent, 64 usage, 78 xtrace refused.
#
# WHAT IT READS. Three reads per iteration, all through the shared rows helper's own query function (the same hot-plus-cold
# union): (1) the newest well-formed readiness row for the host, of any verdict, for its boot id and age; (2) the probe rows,
# reduced to the newest row's class, boot id and age; (3) one journald query over the host's own rows, per distinct _BOOT_ID,
# the row count and the ages of the first and the newest row. journald sets _BOOT_ID itself, but whoever holds an ingest token
# can write any text, so every id is format-gated (32 lowercase hex) before it is compared or printed; a dropped id is only
# counted. Probe row ids carry dashes and journald ids do not: both are compared lowercased with the dashes removed.
#
# WHAT IT NEVER DOES. It never echoes a row's text: only classes, boot ids, ages and counts are printed. It makes no statement
# about the volume (the fixed footer says so, on every exit path). PASS here means "a probe row of the OK class was seen on a
# boot that began after the request"; the strict grading stays in scripts/followthroughs/web2-luks-live-6931.sh. A read fault
# is never a verdict. It carries no write verb of any spelling: the census in workspaces-luks-verify-workflow.test.sh holds it.
set -uo pipefail

FOOTER='This run reports rows only. It makes no statement about the volume or its encryption; grading belongs to scripts/followthroughs/web2-luks-live-6931.sh.'
tmp="$(mktemp -d)" || { printf 'CANNOT ESTABLISH: mktemp failed.\n'; exit 3; }
# shellcheck disable=SC2329  # invoked through the EXIT trap
finish() {
  rm -rf "$tmp"
  printf '%s\n' "$FOOTER"
  [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || printf '\n%s\n' "$FOOTER" >> "$GITHUB_STEP_SUMMARY"
}
trap finish EXIT

# Refuse to run under xtrace: tracing prints expanded commands, and the query credentials are in scope (#7797).
case "$-" in
  *x*) printf '[FATAL] refusing to trace: Better Stack credentials are in scope\n' >&2; exit 78 ;;
esac

_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOT_LOOKBACK_H=48
SILENT_S=600          # a boot whose newest row is older than this has gone silent
FAIL_MARGIN_S=120     # a probe row this close to the new boot's first row is resolved toward NOT YET
PROBE_LIMIT=50
GRADE_HINT='bash scripts/web-host-reboot-evidence.sh grade'
DOPPLER_HINT='under doppler run -p soleur -c prd_terraform --'

out() { local v="${2//$'\r'/ }"; v="${v//$'\n'/ }"; [[ -z "${GITHUB_OUTPUT:-}" ]] || printf '%s=%s\n' "$1" "$v" >> "$GITHUB_OUTPUT"; }
summary_add() { [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || printf '%s\n' "$@" >> "$GITHUB_STEP_SUMMARY"; }
die3() { printf 'CANNOT ESTABLISH: %s\n' "$1"; summary_add "CANNOT ESTABLISH: $1"; exit 3; }
now_epoch() { date -u +%s; }

# --- loading: credentials first (nothing is read without them), then the helper and every function this file calls ------------
load_helper() {
  local v
  for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
    [[ -n "${!v:-}" ]] || die3 "${v} is not injected. Nothing was read."
  done
  local lib="${_ROOT}/scripts/lib/web2-luks-rows.sh"
  # shellcheck source=scripts/lib/web2-luks-rows.sh
  if ! source "$lib" || ! declare -F w2l_fetch_probe >/dev/null || ! declare -F w2l_fetch_ready >/dev/null || ! declare -F w2l_query >/dev/null \
     || [[ -z "${W2L_HOST_NAME:-}" || -z "${_W2L_JQ_DEFS:-}" ]]; then
    die3 "the shared rows helper could not be loaded (lib=${lib}). Nothing was measured."
  fi
}

# --- the three reads ---------------------------------------------------------------------------------------------------------
FAULTS=()
READY_JSON=null; PROBE_JSON=null; BOOTS_JSON='{"dropped":0,"boots":[]}'
note_fault() { # <read> [class]
  local cls="${2:-}"
  if [[ -z "$cls" && -s "$tmp/err" ]]; then cls="$(sed -n 's/.* class=\([a-z0-9-]*\) .*/\1/p' "$tmp/err" | head -1)"; fi
  FAULTS+=("$1 class=${cls:-unknown}")
}
body_ok() { jq -e -s 'all(.[]; type == "object")' "$1" >/dev/null 2>&1; }
sql_boots() {
  printf '%s' "SELECT JSONExtractString(raw,'_BOOT_ID') AS bid, count() AS n, min(dateDiff('second', dt, now())) AS newest_age_s, max(dateDiff('second', dt, now())) AS first_age_s
FROM (SELECT dt, raw FROM remote(\$BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
WHERE dt > now() - INTERVAL ${BOOT_LOOKBACK_H} HOUR
  AND JSONExtractString(raw,'host_name') = '${W2L_HOST_NAME}'
  AND JSONExtractString(raw,'_BOOT_ID') != ''
GROUP BY bid ORDER BY first_age_s ASC LIMIT 50
FORMAT JSONEachRow"
}
read_ready() {
  local f="$tmp/ready.jsonl" r
  READY_JSON=null
  if ! w2l_fetch_ready "$f" 90 20 2>"$tmp/err"; then note_fault ready; return 1; fi
  if ! body_ok "$f"; then note_fault ready unparseable; return 1; fi
  # kind == "row" only: a junk row (a malformed line, an unparseable age) is a read-shape fault, never evidence
  if ! r="$(jq -c -s --arg host "$W2L_HOST_NAME" "${_W2L_JQ_DEFS}"'
      [ .[] | classify_ready | select(.kind == "row" and (.f.host // "") == $host) ] | sort_by(.age)
      | (.[0] | if . == null then null else {age: .age, boot: bid} end)' "$f" 2>/dev/null)" || [[ -z "$r" ]]; then
    note_fault ready jq; return 1
  fi
  READY_JSON="$r"
}
read_probe() {
  local f="$tmp/probe.jsonl" r
  PROBE_JSON=null
  if ! w2l_fetch_probe "$f" "$W2L_PROBE_LOOKBACK_H" "$PROBE_LIMIT" 2>"$tmp/err"; then note_fault probe; return 1; fi
  if ! body_ok "$f"; then note_fault probe unparseable; return 1; fi
  if ! r="$(jq -c -s --arg host "$W2L_HOST_NAME" --arg ident "$W2L_PROBE_IDENT" --arg unit "$W2L_PROBE_UNIT" "${_W2L_JQ_DEFS}"'
      [ .[] | . as $r | ($r | age) as $a
        | if ($r.host_name != $host or $r.ident != $ident or $r.unit != $unit) then empty
          elif $a == null then {kind: "agefault"}
          else ($r | classify_probe($host; $ident; $unit)) as $c
            | if $c.kind == "ok" then {kind: "ok", age: $a, boot: ((($c.f.boot_id // "") | ascii_downcase | gsub("-"; "")) | if test("^[0-9a-f]{32}$") then . else "" end)}
              elif $c.kind == "fail" then {kind: "fail", age: $a, boot: ""}
              else {kind: "malformed", age: $a, boot: ""} end
          end ]
      | {fault: any(.[]; .kind == "agefault"),
         row: ([ .[] | select(.kind != "agefault") ] | sort_by([.age, (if .kind == "ok" then 1 else 0 end)]) | .[0])}' "$f" 2>/dev/null)" || [[ -z "$r" ]]; then
    note_fault probe jq; return 1
  fi
  if [[ "$(jq -r '.fault' <<<"$r")" == true ]]; then note_fault probe age_unparseable; return 1; fi
  PROBE_JSON="$(jq -c '.row' <<<"$r")"
}
read_boots() {
  local f="$tmp/boots.jsonl" r
  BOOTS_JSON='{"dropped":0,"boots":[]}'
  if ! w2l_query "$(sql_boots)" "$f" 2>"$tmp/err"; then note_fault boots; return 1; fi
  if ! body_ok "$f"; then note_fault boots unparseable; return 1; fi
  # Every id is format-gated here, in jq, before anything compares or prints it; the rest is dropped and counted.
  if ! r="$(jq -c -s '
      def num: if type == "number" then . elif type == "string" and test("^[0-9]+$") then tonumber else null end;
      [ .[] | {id: (.bid // ""), n: (.n | num), first: (.first_age_s | num), newest: (.newest_age_s | num)} ] as $all
      | ($all | map(select((.id | type) == "string" and (.id | test("^[0-9a-f]{32}$")) and .n != null and .first != null and .newest != null))) as $ok
      | {dropped: (($all | length) - ($ok | length)), boots: ($ok | sort_by(.first))}' "$f" 2>/dev/null)" || [[ -z "$r" ]]; then
    note_fault boots jq; return 1
  fi
  if [[ "$(jq -r '.boots | length' <<<"$r")" == 0 ]]; then note_fault boots no_readable_boot_id; return 1; fi
  BOOTS_JSON="$r"
}
read_all() { FAULTS=(); read_ready || true; read_probe || true; read_boots || true; }

# --- the verdict: a pure function over (seconds since the request, readiness row, probe row, boots, fault) ---------------------
# first match wins; ages are seconds before the query, and a boot BEGAN after the request when its first row is younger than that.
verdict_json() { # since ready probe boots fault
  jq -cn --argjson since "$1" --argjson ready "$2" --argjson probe "$3" --argjson boots "$4" --argjson fault "$5" \
    --argjson silent "$SILENT_S" --argjson margin "$FAIL_MARGIN_S" '
    def res($v; $r; $poll; $dl): {v: $v, reason: $r, poll: $poll, dexit: $dl};
    ($boots.boots | map(select(.first < $since))) as $after
    | ($boots.boots | map(select(.first >= $since)) | .[0]) as $before
    | ($after | .[0]) as $newest_after
    | ($after | .[-1]) as $earliest_after
    | if ($ready != null and $ready.age < $since) then res("NOT_YET"; "instance_recreated_after_request"; false; 2)
      elif $fault then res("NOT_YET"; "read_fault"; true; 2)
      elif ($after | length) == 0 then
        (if ($before != null and $before.newest < $since) then res("NOT_YET"; "request_not_acted_on"; true; 4)
         else res("NOT_YET"; "host_silent_no_new_boot"; true; 4) end)
      elif ($probe != null and ($probe.kind == "fail" or $probe.kind == "malformed") and ($probe.age + $margin) < $earliest_after.first) then
        res("FAIL"; "probe_fail_row_after_new_boot"; false; 1)
      elif ($probe != null and $probe.kind == "ok" and $probe.age < $since and $probe.boot != "" and any($after[]; .id == $probe.boot)) then
        res("PASS"; "probe_row_on_a_boot_that_began_after_the_request"; false; 0)
      elif ($newest_after.newest > $silent) then res("NOT_YET"; "new_boot_seen_then_silent"; true; 4)
      else res("NOT_YET"; "new_boot_seen_probe_pending"; true; 2) end'
}
label_of() { case "$1" in PASS) printf 'PASS (row presence only)' ;; FAIL) printf 'FAIL' ;; *) printf 'NOT YET' ;; esac; }

next_line() { # <reason> <anchor>
  local anchor="$2"
  case "$1" in
    instance_recreated_after_request) printf 'next: the readiness row is newer than the request, so the instance was re-created, not rebooted; run again after the new instance, with a new anchor.' ;;
    read_fault) printf 'next: Better Stack could not be read, so the rows say nothing yet; re-grade later with: %s --anchor %s --window-min 0 (%s).' "$GRADE_HINT" "$anchor" "$DOPPLER_HINT" ;;
    request_not_acted_on) printf 'next: nothing is dark: the old boot keeps shipping rows, so the guest did not act on the request. Do not replace the host; record this on #9372 and let the owner decide.' ;;
    host_silent_no_new_boot|new_boot_seen_then_silent) printf "next: the host stopped shipping rows: follow the runbook's dark-host path (web_host_replace, image_tag without a leading v, #9669); the owner approves it." ;;
    probe_fail_row_after_new_boot) printf "next: a FAIL row after the new boot also spoils the #6931 soak by the grader's rule; recovery is a web_host_replace and a re-grade from the new instance's readiness row (see the runbook)." ;;
    probe_row_on_a_boot_that_began_after_the_request) printf 'next: nothing further for this run; the stricter grading of the soak stays with scripts/followthroughs/web2-luks-live-6931.sh.' ;;
    *) printf 'next: a boot began after the request; the daily probe row lands in the 00:00 to 00:30 UTC window (up to about 24.5 h after a boot). Re-grade later with: %s --anchor %s --window-min 0 (%s). Do not re-dispatch to force a row.' "$GRADE_HINT" "$anchor" "$DOPPLER_HINT" ;;
  esac
}

# --- printing (ids, ages and counts only) -------------------------------------------------------------------------------------
describe() { # prints the baseline, boots and probe lines for the current reads
  if ((${#FAULTS[@]} > 0)); then
    local f; for f in "${FAULTS[@]}"; do printf 'read fault: %s\n' "$f"; done
  fi
  jq -r 'if . == null then "baseline: readiness row none" else "baseline: readiness row boot_id=\(.boot) age_s=\(.age)" end' <<<"$READY_JSON"
  jq -r '"boots seen: total=\(.boots | length) dropped_ids=\(.dropped)"' <<<"$BOOTS_JSON"
  jq -r 'if . == null then "latest probe row: none" else "latest probe row: class=\(.kind) boot_id=\(if .boot == "" then "none" else .boot end) age_s=\(.age)" end' <<<"$PROBE_JSON"
}
describe_after() { # <since>
  jq -r --argjson since "$1" '[.boots[] | select(.first < $since)] as $a
    | "boots began after the request: \($a | length)",
      ($a | .[:5][] | "boot after the request: id=\(.id) first_row_age_s=\(.first) newest_row_age_s=\(.newest) rows=\(.n)")' <<<"$BOOTS_JSON"
}

cmd_snapshot() {
  load_helper
  read_all
  local block=""
  block+="pre-request context:"$'\n'
  if printf '%s\n' "${FAULTS[@]-}" | grep -q '^ready'; then block+="  readiness row: unavailable"$'\n'
  else block+="  $(jq -r 'if . == null then "readiness row: none" else "readiness row: boot_id=\(.boot) age_s=\(.age)" end' <<<"$READY_JSON")"$'\n'; fi
  if printf '%s\n' "${FAULTS[@]-}" | grep -q '^probe'; then block+="  probe row: unavailable"$'\n'
  else block+="  $(jq -r 'if . == null then "probe row: none" else "probe row: class=\(.kind) boot_id=\(if .boot == "" then "none" else .boot end) age_s=\(.age)" end' <<<"$PROBE_JSON")"$'\n'; fi
  if printf '%s\n' "${FAULTS[@]-}" | grep -q '^boots'; then block+="  newest boot: unavailable"$'\n'
  else block+="  $(jq -r '.boots[0] | "newest boot: id=\(.id) rows=\(.n) first_row_age_s=\(.first) newest_row_age_s=\(.newest)"' <<<"$BOOTS_JSON")"$'\n'; fi
  printf '%s' "$block"
  summary_add '```text' "${block%$'\n'}" '```'
  exit 0
}

cmd_grade() {
  local anchor="" window=40 poll=60 now
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --anchor) anchor="${2:-}"; shift 2 || break ;;
      --window-min) window="${2:-}"; shift 2 || break ;;
      --poll-s) poll="${2:-}"; shift 2 || break ;;
      *) printf 'usage: web-host-reboot-evidence.sh grade --anchor <epoch> [--window-min <n>] [--poll-s <n>] | snapshot\n' >&2; exit 64 ;;
    esac
  done
  [[ "$anchor" =~ ^[0-9]{1,10}$ ]] || die3 "grade needs --anchor <epoch> (digits only, got '$(printf '%s' "$anchor" | tr -cd '[:alnum:]-' | head -c 40)')."
  [[ "$window" =~ ^[0-9]{1,4}$ ]] || die3 "--window-min must be a whole number of minutes."
  [[ "$poll" =~ ^[0-9]{1,5}$ && "$poll" -ge 1 ]] || die3 "--poll-s must be a whole number of seconds, at least 1."
  now="$(now_epoch)"
  (( anchor <= now + 60 )) || die3 "the anchor ${anchor} is in the future; it must be the request time."
  load_helper
  printf 'web-host-reboot-evidence grade: anchor=%s window_min=%s poll_s=%s\n' "$anchor" "$window" "$poll"
  local iter=0 start="" deadline=0 t since vj v reason pollmore dexit rem step rc ended=""
  while :; do
    # the runner clock is read BEFORE this iteration's queries, so a slow read can only make the request look older
    t="$(now_epoch)"
    if [[ -z "$start" ]]; then start="$t"; deadline=$(( start + window * 60 )); fi
    iter=$((iter + 1)); since=$(( t - anchor )); (( since >= 0 )) || since=0
    read_all
    if ! vj="$(verdict_json "$since" "$READY_JSON" "$PROBE_JSON" "$BOOTS_JSON" "$([[ ${#FAULTS[@]} -gt 0 ]] && echo true || echo false)")" || [[ -z "$vj" ]]; then
      vj='{"v":"NOT_YET","reason":"read_fault","poll":true,"dexit":2}'
      FAULTS+=("verdict class=jq")
    fi
    v="$(jq -r '.v' <<<"$vj")"; reason="$(jq -r '.reason' <<<"$vj")"; pollmore="$(jq -r '.poll' <<<"$vj")"; dexit="$(jq -r '.dexit' <<<"$vj")"
    printf 'iteration %s (since_request_s=%s): %s reason=%s\n' "$iter" "$since" "$(label_of "$v")" "$reason"
    [[ "$v" == NOT_YET && "$pollmore" == true ]] || break
    if (( t >= deadline )); then ended=" (window ended)"; break; fi
    rem=$(( deadline - t )); step="$poll"; (( rem < step )) && step="$rem"
    sleep "$step"
  done
  case "$v" in PASS) rc=0 ;; FAIL) rc=1 ;; *) rc="$dexit" ;; esac
  local block=""
  [[ "$reason" != read_fault ]] || block+="Nothing was measured: Better Stack could not be read."$'\n'
  block+="$(describe)"$'\n'"$(describe_after "$since")"$'\n'
  block+="verdict: $(label_of "$v") reason=${reason}${ended}$([[ "$rc" == 4 ]] && printf ' (exit 4)')"$'\n'
  [[ "$v" != PASS ]] || block+="a probe row of the OK class was seen on a boot that began after the request (row presence only)."$'\n'
  block+="$(next_line "$reason" "$anchor")"
  printf '%s\n' "$block"
  out verdict "$v"; out reason "$reason"; out exit_code "$rc"
  summary_add '## web host reboot evidence (#9372)' '' '```text' "$block" '```'
  exit "$rc"
}

case "${1:-}" in
  snapshot) shift; [[ $# -eq 0 ]] || { printf 'usage: web-host-reboot-evidence.sh snapshot\n' >&2; exit 64; }; cmd_snapshot ;;
  grade) shift; cmd_grade "$@" ;;
  *) printf 'usage: web-host-reboot-evidence.sh snapshot | grade --anchor <epoch> [--window-min <n>] [--poll-s <n>]\n' >&2; exit 64 ;;
esac
