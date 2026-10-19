#!/usr/bin/env bash
#
# Read-only evidence collector for the git-data flip-then-rollback rehearsal (#8211, CPO condition).
#
# WHAT THIS PRINTS. The evidence block of knowledge-base/project/specs/archive/20261013-002507-feat-one-shot-git-data-luks-cutover-8211/
# design-rollback-rehearsal.md section 5, filled from reads and nothing else (hr-no-dashboard-eyeball-pull-data-yourself):
#   * `gh run view --json jobs` (and the run log) for the run ids the owner names: flip, rollback, exit proof, and
#     optionally the Level 2 pre-deletion proof and the rotate predecessor;
#   * the pinned Better Stack reads, through scripts/betterstack-query.sh (aggregated in SQL, so no row body reaches this
#     script's output, and the credentials are the reader's own);
#   * the Sentry read token, through scripts/lib/bearer-curl.sh (the bearer rides curl's stdin config, never argv).
# COUNTS, RUN IDS, TIMESTAMPS, STEP CONCLUSIONS AND ONE PUBLIC KEY FINGERPRINT. Never a secret, a row body, a repository id
# or a host name (web-1 / web-2 are labels this script assigns; the real names stay inside the SQL and the label map).
#
# WHAT IT NEVER DOES. It dispatches nothing, writes nothing (no Doppler, no GitHub, no Better Stack, no Sentry write),
# and reads no host over SSH. Every call is a GET or a SELECT.
#
# USAGE (the Better Stack credentials are injected by the caller; the Sentry token is read to the environment only):
#   SENTRY_ISSUE_RO_TOKEN="$(doppler secrets get SENTRY_ISSUE_RO_TOKEN -p soleur -c prd --plain)" \
#   doppler run -p soleur -c prd_terraform --only-secrets BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD \
#     --no-exit-on-missing-only-secrets -- scripts/followthroughs/git-data-rehearsal-evidence.sh \
#       --flip <run id> --rollback <run id> --exit <run id> [--proof-before <run id>] [--rotate <run id>] [--level 1|2]
#
# EXIT CODES. 0 = every machine-collected field was read; 3 = the block was printed but at least one field reads
# UNREAD(<token>) (the token names the read that failed; stderr carries one value-free line per failure); 64 = usage;
# 78 = refused under xtrace with a live credential. A block with UNREAD in it is NOT evidence for that field: a failed read
# and a zero count are different facts, and this script never prints a zero for a read that did not run.
#
# FIELDS THE OWNER SUPPLIES (printed as <owner: ...>, because no read can establish them after the fact): the Level when
# --level is omitted, the stamp before the flip and after R8, the reconcile counts, the queue check, the session control and
# the active-session counts. They are not UNREAD: they were never a read.
set -uo pipefail

# (#7797) Shell tracing would echo the credentials once expanded. The test uses `${VAR:+x}` (non-emptiness without
# expanding the value). Tracing stays available with the credentials unset.
case "$-" in
  *x*)
    if [ -n "${SENTRY_ISSUE_RO_TOKEN:+x}${BETTERSTACK_QUERY_PASSWORD:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (see #7797). Unset it to trace safely.\n' >&2
      exit 78
    fi
    ;;
esac
export LC_ALL=C
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BSQ="${ROOT}/scripts/betterstack-query.sh"
REPO="jikig-ai/soleur"
RUN_URL_BASE="https://github.com/${REPO}/actions/runs"

# The Sentry destination is pinned to literals (ADR-202 Rule D): the read token is never sent anywhere else.
readonly SENTRY_HOST="jikigai-eu.sentry.io"
readonly SENTRY_ORG="jikigai-eu"
readonly SENTRY_PROJECT_ID="4511404943671376"

# shellcheck source=../lib/betterstack-sources.sh
source "${ROOT}/scripts/lib/betterstack-sources.sh" || { echo "FATAL: cannot load betterstack-sources.sh" >&2; exit 64; }
# shellcheck source=../lib/bearer-curl.sh
source "${ROOT}/scripts/lib/bearer-curl.sh" || { echo "FATAL: cannot load bearer-curl.sh" >&2; exit 64; }
# shellcheck source=../lib/git-data-rotate-stamp.sh
source "${ROOT}/scripts/lib/git-data-rotate-stamp.sh" || { echo "FATAL: cannot load git-data-rotate-stamp.sh" >&2; exit 64; }

usage() {
  printf 'usage: %s --flip <run id> --rollback <run id> --exit <run id> [--proof-before <run id>] [--rotate <run id>] [--level 1|2]\n' \
    "$(basename "$0")" >&2
  exit 64
}

FLIP="" ROLLBACK="" EXITRUN="" PROOF_BEFORE="" ROTATE="" LEVEL=""
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || usage
  case "$1" in
    --flip) FLIP="$2" ;;
    --rollback) ROLLBACK="$2" ;;
    --exit) EXITRUN="$2" ;;
    --proof-before) PROOF_BEFORE="$2" ;;
    --rotate) ROTATE="$2" ;;
    --level) LEVEL="$2" ;;
    *) usage ;;
  esac
  shift 2
done
for _id in "$FLIP" "$ROLLBACK" "$EXITRUN"; do [[ "$_id" =~ ^[0-9]{1,20}$ ]] || usage; done
for _id in "$PROOF_BEFORE" "$ROTATE"; do [[ -z "$_id" || "$_id" =~ ^[0-9]{1,20}$ ]] || usage; done
[[ -z "$LEVEL" || "$LEVEL" == 1 || "$LEVEL" == 2 ]] || usage

WORK="$(mktemp -d -t gd-rehearsal-evidence.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 64; }
case "$WORK" in /?*) : ;; *) echo "FATAL: scratch dir is not absolute" >&2; exit 64 ;; esac
trap 'rm -rf "$WORK" 2>/dev/null' EXIT INT TERM HUP

unread=0
note_unread() { # $1 = token. One value-free stderr line; the block carries UNREAD(<token>).
  unread=$((unread + 1))
  printf 'UNREAD(%s)\n' "$1" >&2
}

TAB=$'\t'
ISO_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'

iso_epoch() { [[ "$1" =~ $ISO_RE ]] && date -u -d "$1" +%s 2>/dev/null; }
# ClickHouse and Sentry literals are built ONLY from a value that matched ISO_RE.
ck_ts() { local t="${1/T/ }"; printf '%s' "${t%Z}"; }
sentry_ts() { printf '%s' "${1%Z}"; }

# ---------------------------------------------------------------------------------------------------------------------
# GitHub reads
# ---------------------------------------------------------------------------------------------------------------------
# fetch_run <id> <slot> <expected displayTitle>  ->  $WORK/<slot>.json (+ $WORK/<slot>.log when a log is wanted)
# The run must BE the run the slot claims: workflow name, ref, event and mode (displayTitle is the run-name). A wrong id
# is refused rather than rendered, so a pasted id from the wrong run cannot produce a plausible block.
fetch_run() {
  local id="$1" slot="$2" title="$3" want_log="${4:-log}"
  local json="${WORK}/${slot}.json"
  if ! timeout 90 gh run view "$id" --repo "$REPO" \
      --json databaseId,workflowName,displayTitle,headBranch,event,status,conclusion,createdAt,updatedAt,jobs >"$json" 2>/dev/null; then
    note_unread "gh-run-view-${slot}"; return 1
  fi
  if ! jq -e --arg id "$id" --arg t "$title" \
      '(.databaseId|tostring) == $id and ((.workflowName // "")|startswith("git-data cutover")) and .headBranch == "main" and .event == "workflow_dispatch" and .displayTitle == $t and (.jobs|type) == "array"' \
      "$json" >/dev/null 2>&1; then
    note_unread "run-identity-${slot}"; return 1
  fi
  if [[ "$want_log" == log ]]; then
    if ! timeout 180 gh run view "$id" --repo "$REPO" --log >"${WORK}/${slot}.log" 2>/dev/null; then
      note_unread "gh-run-log-${slot}"; return 2
    fi
  fi
  return 0
}

jfield() { jq -r --arg f "$2" '.[$f] // "absent" | tostring' "$1"; }
# step_get <json> <step-name prefix> <field>. The prefix is ASCII (the real names carry an em dash after it).
step_get() {
  jq -r --arg p "$2" --arg f "$3" \
    '[.jobs[]?.steps[]? | select((.name // "") | startswith($p))] | (.[0] // {}) | (.[$f] // "absent") | if . == "" then "absent" else . end' "$1"
}

# Log lines are `<job>\t<step>\t<timestamp> <message>`. Matching is anchored at the start of the MESSAGE, so the step
# source that `run:` echoes at the head of each group (it contains the same words after `echo "`) is never counted.
LOG_TS='^[0-9T:.-]+Z '
log_count() { # <log> <message regex after the timestamp>
  awk -F "$TAB" -v re="${LOG_TS}$2" 'BEGIN { n = 0 } $3 ~ re { n++ } END { print n }' "$1" 2>/dev/null
}
log_first_ts() { # <log> <message regex> -> first matching line's timestamp truncated to seconds
  awk -F "$TAB" -v re="${LOG_TS}$2" '$3 ~ re { split($3, a, " "); print substr(a[1], 1, 19) "Z"; exit }' "$1" 2>/dev/null
}

fetch_ok_flip=0
fetch_ok_rb=0
exit_ok=0
pb_ok=0
if fetch_run "$FLIP" flip "git-data flip"; then fetch_ok_flip=1; fi
if fetch_run "$ROLLBACK" rollback "git-data rollback"; then fetch_ok_rb=1; fi
if fetch_run "$EXITRUN" exit "git-data proof"; then exit_ok=1; fi
if [[ -n "$PROOF_BEFORE" ]] && fetch_run "$PROOF_BEFORE" proofbefore "git-data proof"; then pb_ok=1; fi

# ---------------------------------------------------------------------------------------------------------------------
# flip / rollback lines
# ---------------------------------------------------------------------------------------------------------------------
UNRD() { printf 'UNREAD(%s)' "$1"; }
FLIP_LINE="$(UNRD flip-run)"
ROLLBACK_LINE="$(UNRD rollback-run)"
flip_flag_at="" rb_flag_at=""

if (( fetch_ok_flip )); then
  j="${WORK}/flip.json"; l="${WORK}/flip.log"
  unwound="no"
  [[ -s "$l" && "$(log_count "$l" 'finalizer: (unwind complete[.]|writing GIT_DATA_STORE_ENABLED=false)')" -gt 0 ]] && unwound="yes"
  fin="$(step_get "$j" 'Finalizer' conclusion)"
  case "$fin" in absent|skipped) ran="no" ;; *) ran="yes (unwound ${unwound})" ;; esac
  FLIP_LINE="$(printf '%s/%s   dispatched %s   conclusion %s   stamp step %s   finalizer ran %s' \
    "$RUN_URL_BASE" "$FLIP" "$(jfield "$j" createdAt)" "$(jfield "$j" conclusion)" \
    "$(step_get "$j" 'Write GIT_DATA_LUKS_CUTOVER_AT' conclusion)" "$ran")"
  flip_flag_at="$(step_get "$j" 'Write GIT_DATA_STORE_ENABLED' completedAt)"
fi
if (( fetch_ok_rb )); then
  j="${WORK}/rollback.json"; l="${WORK}/rollback.log"
  seen="not seen"
  [[ -s "$l" && "$(log_count "$l" '([[]git-data-cutover[]] )?STORE probe=probe verdict=ok')" -gt 0 ]] && seen="seen"
  ROLLBACK_LINE="$(printf '%s/%s   dispatched %s   conclusion %s   probe step %s   "STORE probe=probe verdict=ok" %s' \
    "$RUN_URL_BASE" "$ROLLBACK" "$(jfield "$j" createdAt)" "$(jfield "$j" conclusion)" \
    "$(step_get "$j" 'Positive replication probe' conclusion)" "$seen")"
  rb_flag_at="$(step_get "$j" 'Write GIT_DATA_STORE_ENABLED' completedAt)"
fi

# window: flag-on from the flip's flag_write completion to the rollback's flag-off completion.
WINDOW_LINE="$(UNRD window)"
if [[ "$flip_flag_at" =~ $ISO_RE && "$rb_flag_at" =~ $ISO_RE ]]; then
  a="$(iso_epoch "$flip_flag_at")"; b="$(iso_epoch "$rb_flag_at")"
  if [[ -n "$a" && -n "$b" && "$b" -ge "$a" ]]; then
    mins="$(awk -v d=$((b - a)) 'BEGIN { printf "%.1f", d / 60 }')"
    WINDOW_LINE="flag-on from ${flip_flag_at} to ${rb_flag_at} = ${mins} minutes"
  fi
fi
if [[ "$WINDOW_LINE" == "UNREAD(window)" ]]; then
  # A missing flag_write step in either run is a finding of its own (a resume arm, a nothing_to_rollback run), not a typo.
  (( fetch_ok_flip && fetch_ok_rb )) && printf 'window: a flag_write completedAt is absent or out of order\n' >&2
  note_unread window
fi

# per-host: the workflow's own readback lines (`host web-N: git_data_store=<state> observed`) and their log timestamps.
host_ts() { # <slot> <host label> <state>
  local l="${WORK}/$1.log" t=""
  [[ -s "$l" ]] && t="$(log_first_ts "$l" "host $2: git_data_store=$3 observed")"
  [[ -n "$t" ]] && printf '%s' "$t" || return 1
}
PERHOST_LINE=""
for h in web-1 web-2; do
  en="" dis=""
  (( fetch_ok_flip )) && en="$(host_ts flip "$h" enabled)"
  (( fetch_ok_rb )) && dis="$(host_ts rollback "$h" disabled)"
  if [[ -z "$en" ]]; then en="$(UNRD "${h}-enabled")"; note_unread "${h}-enabled"; fi
  if [[ -z "$dis" ]]; then dis="$(UNRD "${h}-disabled")"; note_unread "${h}-disabled"; fi
  PERHOST_LINE="${PERHOST_LINE}${PERHOST_LINE:+;  }${h} git_data_store=enabled ${en} / disabled ${dis}"
done

# ---------------------------------------------------------------------------------------------------------------------
# Better Stack: startup lines after the rollback's flag-off write, aggregated in SQL.
# ---------------------------------------------------------------------------------------------------------------------
# Real host names live only here. web-1's source host is `soleur-web-platform`, and `soleur-inngest-prd` until the #6616
# recreate lands (the workflow's per-host readback matches both for the same reason).
WEB_HOSTS_SQL="'soleur-web-platform','soleur-inngest-prd','soleur-web-2'"
LABEL_MAP='{"soleur-web-platform":"web-1","soleur-inngest-prd":"web-1","soleur-web-2":"web-2"}'

bs_read() { # <table> <s3 table> <sql>  -> stdout; rc is the reader's
  BS_TABLE="$1" BS_TABLE_S3="$2" timeout -k 5 150 bash "$BSQ" "$3" 2>"${WORK}/bs.err"
}
bs_unread_token() { # classify by rc only; the stderr text is never printed
  case "$1" in 3) echo "bs-credentials-not-injected" ;; 2) echo "bs-credential-refused" ;; 124|137) echo "bs-timeout" ;; *) echo "bs-read-failed" ;; esac
}

APP_LINE="$(UNRD app-path)"
app_done=0
if [[ "$rb_flag_at" =~ $ISO_RE ]]; then
  t0="$(ck_ts "$rb_flag_at")"
  sql="SELECT JSONExtractString(raw,'host_name') AS h,
  countIf(positionCaseInsensitive(raw,'git_data_pin=present fp=') > 0) AS pin_n,
  countIf(positionCaseInsensitive(raw,'git_data_ssh_client=present') > 0) AS ssh_n,
  countIf(positionCaseInsensitive(raw,'git_data_store=disabled') > 0) AS store_n,
  groupUniqArrayIf(extract(raw,'git_data_pin=present fp=(SHA256:[A-Za-z0-9+/=]+)'), positionCaseInsensitive(raw,'git_data_pin=present fp=') > 0) AS fps
FROM (SELECT dt, raw FROM remote(\$BS_TABLE) WHERE dt >= '${t0}'
      UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1 AND dt >= '${t0}')
WHERE dt >= '${t0}' AND JSONExtractString(raw,'host_name') IN (${WEB_HOSTS_SQL})
  AND (positionCaseInsensitive(raw,'git_data_pin=') > 0 OR positionCaseInsensitive(raw,'git_data_ssh_client=') > 0 OR positionCaseInsensitive(raw,'git_data_store=') > 0)
GROUP BY h FORMAT JSONEachRow"
  rows="$(bs_read "$BS_CONTROL_TABLE" "$BS_CONTROL_TABLE_S3" "$sql")"; rc=$?
  if (( rc != 0 )); then
    note_unread "$(bs_unread_token "$rc")"
  elif ! summary="$(printf '%s\n' "$rows" | jq -s -c --argjson map "$LABEL_MAP" '
        [ .[] | select(type == "object") | {l: ($map[.h] // "other"), pin: (.pin_n|tonumber), ssh: (.ssh_n|tonumber), st: (.store_n|tonumber),
          fps: [ (.fps // [])[] | select(test("^SHA256:[A-Za-z0-9+/=]{20,64}$")) ]} ]
        | map(select(.l != "other"))
        | { total: (map(.pin + .ssh + .st) | add // 0),
            by: (group_by(.l) | map({l: .[0].l, pin: (map(.pin)|add), ssh: (map(.ssh)|add), st: (map(.st)|add)})),
            fps: ([ .[].fps[] ] | unique) }' 2>/dev/null)"; then
    note_unread "bs-response-shape"
  elif [[ "$(jq -r '.total' <<<"$summary")" == "0" ]]; then
    # Zero rows from both hosts is the AMBIGUOUS silence (dark ingest, wrong table, or a fleet that never restarted);
    # it is not a measured "pin absent".
    note_unread "bs-silent-window"
  else
    pin_part="$(jq -r '(.fps | if length == 0 then "none" else join(",") end) as $f
      | "pin \($f) (" + ([ .by[] | "\(.l) \(.pin)" ] | join(", ")) + ")"' <<<"$summary")"
    ssh_part="$(jq -r '"ssh_client present (" + ([ .by[] | "\(.l) \(.ssh)" ] | join(", ")) + ")"' <<<"$summary")"
    st_part="$(jq -r '"store disabled (" + ([ .by[] | "\(.l) \(.st)" ] | join(", ")) + ")"' <<<"$summary")"
    APP_LINE="startup lines after rollback flag-off: ${pin_part}, ${ssh_part}, ${st_part}"
  fi
  app_done=1
fi
# Without the rollback's flag-off time there is no lower bound for "after the rollback redeploy"; the failure is already
# named by the window / rollback-run token, so it is not double counted here.
if (( ! app_done )); then note_unread app-path-window; fi

# Sentry events between R1 (the flip dispatch) and now (R6 is read at collection time).
sentry_count() { # <query> -> prints an integer, rc 1 when unread
  local body="${WORK}/sentry.json" code n
  [[ -n "${SENTRY_ISSUE_RO_TOKEN:-}" ]] || return 2
  code="$(bc_curl git-data-rehearsal-evidence 'Authorization:Bearer :SENTRY_ISSUE_RO_TOKEN' -- -sS --max-time 30 -G \
    -o "$body" -w '%{http_code}' \
    --data-urlencode "project=${SENTRY_PROJECT_ID}" --data-urlencode "start=${S_START}" --data-urlencode "end=${S_END}" \
    --data-urlencode "field=count()" --data-urlencode "query=$1" \
    "https://${SENTRY_HOST}/api/0/organizations/${SENTRY_ORG}/events/")" || code=000
  [[ "$code" == 200 ]] || return 1
  n="$(jq -er 'if (type == "object") and ((.data|type) == "array") and ((.data|length) == 1) then .data[0]["count()"] else empty end' "$body" 2>/dev/null)" || return 1
  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$n"
}
SENTRY_PART="$(UNRD sentry)"
flip_created=""
(( fetch_ok_flip )) && flip_created="$(jfield "${WORK}/flip.json" createdAt)"
if [[ "$flip_created" =~ $ISO_RE ]]; then
  S_START="$(sentry_ts "$flip_created")"
  S_END="$(date -u +%Y-%m-%dT%H:%M:%S)"
  er="" pf=""
  er="$(sentry_count 'op:git-data-bare-repo-erasure')"; rc_er=$?
  pf="$(sentry_count 'has:pin_fault')"; rc_pf=$?
  if (( rc_er == 0 && rc_pf == 0 )); then
    SENTRY_PART="$((er + pf)) (erasure ${er}, pin_fault ${pf})"
  elif (( rc_er == 2 || rc_pf == 2 )); then
    note_unread sentry-token-absent
  else
    note_unread sentry-read
  fi
else
  note_unread sentry-window
fi

# level 2 lines: proof before / after the synthetic account's deletion.
proof_verdict() { # <slot> -> clear | store_not_empty | unknown | conflict
  local l="${WORK}/$1.log" c ne
  [[ -s "$l" ]] || { echo unknown; return; }
  c="$(log_count "$l" '((##[[][a-z]+[]]|::[a-z]+ title=[^:]*::)|[[]git-data-cutover[]] (STORE )?)(probe=[a-z-]+ )?verdict=clear')"
  ne="$(log_count "$l" '((##[[][a-z]+[]]|::[a-z]+ title=[^:]*::)|[[]git-data-cutover[]] (STORE )?)(probe=[a-z-]+ )?verdict=store_not_empty')"
  if (( c > 0 && ne > 0 )); then echo conflict
  elif (( c > 0 )); then echo clear
  elif (( ne > 0 )); then echo store_not_empty
  else echo unknown; fi
}
EXIT_V="$(UNRD exit-verdict)"
if (( exit_ok )); then
  v="$(proof_verdict exit)"
  case "$v" in clear|store_not_empty) EXIT_V="$v" ;; *) note_unread "exit-verdict-${v}" ;; esac
fi
EXIT_LINE="mode=proof run ${RUN_URL_BASE}/${EXITRUN} verdict ${EXIT_V}"
(( exit_ok )) || EXIT_LINE="$(UNRD exit-run)"

LEVEL2_LINE="level 2 only: n/a (level 1)"
if [[ "$LEVEL" == 2 || -n "$PROOF_BEFORE" ]]; then
  pbv="$(UNRD proof-before)"
  if (( pb_ok )); then
    v="$(proof_verdict proofbefore)"
    case "$v" in clear|store_not_empty) pbv="$v" ;; *) note_unread "proof-before-verdict-${v}" ;; esac
  elif [[ -n "$PROOF_BEFORE" ]]; then :; else note_unread proof-before-absent; fi
  LEVEL2_LINE="level 2 only: proof before deletion ${pbv}, proof after deletion ${EXIT_V}"
elif [[ -z "$LEVEL" ]]; then
  LEVEL2_LINE="level 2 only: <owner: pass --proof-before <run id> for a Level 2 rehearsal>"
fi
LEVEL_TXT="${LEVEL:-<owner: 1|2>}"

# ---------------------------------------------------------------------------------------------------------------------
# predecessor: the rotate run, the apply step, plan_only, and the new server's boot_complete.
# ---------------------------------------------------------------------------------------------------------------------
PRED_LINE="<owner: pass --rotate <run id>>"
if [[ -n "$ROTATE" ]]; then
  PRED_LINE="$(UNRD predecessor)"
  rj="${WORK}/rotate.json"
  if timeout 90 gh run view "$ROTATE" --repo "$REPO" --json databaseId,event,conclusion,createdAt,jobs >"$rj" 2>/dev/null \
     && jq -e --arg id "$ROTATE" '(.databaseId|tostring) == $id and .event == "workflow_dispatch" and (.jobs|type) == "array"' "$rj" >/dev/null 2>&1; then
    rv="$(git_data_rotate_run_verdict "$(cat "$rj")")" || true
    apply_c="$(step_get "$rj" 'Terraform apply (git-data-host -replace)' conclusion)"
    if [[ "$rv" == stamped ]]; then plan_only="false"; else plan_only="not established (verdict ${rv})"; fi
    rot_at="$(jfield "$rj" createdAt)"
    boot_at="$(UNRD boot_complete)"
    if [[ "$rot_at" =~ $ISO_RE ]]; then
      t1="$(ck_ts "$rot_at")"
      sql="SELECT formatDateTime(min(dt), '%Y-%m-%dT%H:%i:%SZ') AS t, count() AS n
FROM (SELECT dt, raw FROM remote(\$BS_TABLE) WHERE dt >= '${t1}'
      UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1 AND dt >= '${t1}')
WHERE dt >= '${t1}' AND JSONExtractString(raw,'stage') = 'boot_complete' AND JSONExtractString(raw,'host_name') = 'soleur-git-data'
FORMAT JSONEachRow"
      brow="$(bs_read "$BS_GIT_DATA_TABLE" "$BS_GIT_DATA_TABLE_S3" "$sql")"; brc=$?
      if (( brc != 0 )); then
        note_unread "$(bs_unread_token "$brc")"
      else
        bt="$(printf '%s\n' "$brow" | jq -r 'select(type == "object" and ((.n|tonumber) > 0)) | .t' 2>/dev/null | head -1)"
        if [[ "$bt" =~ $ISO_RE ]]; then boot_at="$bt"; else note_unread boot-complete-absent; fi
      fi
    else
      note_unread boot-complete-window
    fi
    st10166="$(timeout 60 gh issue view 10166 --repo "$REPO" --json state -q .state 2>/dev/null)" || st10166=""
    [[ "$st10166" =~ ^(OPEN|CLOSED)$ ]] || { note_unread issue-10166; st10166="$(UNRD issue-10166)"; }
    PRED_LINE="rotate run ${ROTATE}, apply step ${apply_c}, plan_only ${plan_only}, new-server boot_complete ${boot_at}; #10166 ${st10166}"
  else
    note_unread rotate-run
  fi
fi

# ---------------------------------------------------------------------------------------------------------------------
# the block
# ---------------------------------------------------------------------------------------------------------------------
printf '%s\n' \
  "git-data flip-then-rollback rehearsal (#8211, CPO condition)" \
  "flip run:      ${FLIP_LINE}" \
  "rollback run:  ${ROLLBACK_LINE}" \
  "window:        ${WINDOW_LINE}" \
  "per-host:      ${PERHOST_LINE}" \
  "app path:      level ${LEVEL_TXT}; ${APP_LINE}; Sentry events R1..R6: ${SENTRY_PART}" \
  "               ${LEVEL2_LINE}" \
  "exit read:     ${EXIT_LINE}" \
  "stamp:         <owner: before R1 / after rollback / after R8 are name listings of GIT_DATA_LUKS_CUTOVER_AT in prd; flip stamp step is on the flip line>" \
  "reconcile:     <owner: repositories written in the window (by proof); non-canary NVMe trees at R3b; incident none|url>" \
  "predecessor:   ${PRED_LINE}" \
  "queue check:   <owner: R4 lever used; proof pair; active sessions at R0/R1/R4>" \
  "session ctl:   <owner: control name or the recorded acceptance; rotate dispatched between R1 and a clear exit read>" \
  "not covered:   real-user replication load, web-2 behaviour beyond the log line, any state a flip writes that a" \
  "               rollback does not remove (the stamp, until R8), the Art. 17 requests refused during the freeze (swept per the runbook)"

(( unread == 0 )) || exit 3
exit 0
