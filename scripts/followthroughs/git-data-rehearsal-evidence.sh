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
# NOT A FOLLOW-THROUGH PROBE. It lives beside the probes but is never enrolled in a tracker: exit 0 here means "every
# machine-collected field was read", which the sweeper would otherwise render as PASS and close an issue on.
#
# USAGE (the Better Stack credentials are injected by the caller; the Sentry token is read to the environment only):
#   SENTRY_ISSUE_RO_TOKEN="$(doppler secrets get SENTRY_ISSUE_RO_TOKEN -p soleur -c prd --plain)" \
#   doppler run -p soleur -c prd_terraform --only-secrets BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD \
#     --no-exit-on-missing-only-secrets -- scripts/followthroughs/git-data-rehearsal-evidence.sh \
#       --flip <run id> --rollback <run id> --exit <run id> [--refs <run id>] [--proof-before <run id>] [--rotate <run id>] [--level 1|2]
# The token is SENTRY_ISSUE_RO_TOKEN ([event:read, org:read], Doppler soleur/prd) because the sweeper's SENTRY_ACTIONS_RO_TOKEN is
# a repository secret no owner workstation can read; this is an owner-run exception to the followthrough convention (ADR-031).
#
# WHAT THE BLOCK MEANS, where it differs from the section 5 template:
#   * `refs read:` is REFS-CONFIRMED read from the `mode=refs_assert` run the owner names with --refs (#11431): the run title
#     `git-data refs_assert`, created after the rollback and before the proofs, the step `Host-side refs assertion` with
#     conclusion success, exactly ONE `REFS-CONFIRMED` log line in that step and exactly ONE anchored `REFS_ASSERT ok repos=1 ...`
#     line. The block prints the run URL and the counts, never a commit id. A log line in a red run is not a verdict; at Level 2
#     a missing --refs reads UNREAD(refs-run) (the verdict that gates R6, the deletion and the real flip is never owner-typed).
#   * `finalizer ran yes (unwound no)` is the healthy reading: the Finalizer step is `if: always()`, so it runs on every path,
#     and "unwound" is read from the log (`finalizer: unwind complete.`), not from the step conclusion.
#   * the per-host timestamps are the runner-log time of the workflow's own readback, up to a poll interval after the host emitted.
#   * the startup-line counts are bounded below by the rollback's flag-off write (the redeploy follows it, so the bound is a safe
#     superset) and above by the exit proof run's dispatch; the Sentry count uses the same window, printed in the block.
#
# EXIT CODES. 0 = every machine-collected field was read; 3 = the block was printed but at least one field reads
# UNREAD(<token>) (the token names the read that failed; stderr carries the tokens); 64 = usage or a missing tool;
# 78 = refused under xtrace with a live credential. A block with UNREAD in it is NOT evidence for that field: a failed read
# and a zero count are different facts, and this script never prints a zero for a read that did not run.
#
# FIELDS THE OWNER SUPPLIES (printed as <owner: ...>, because no read can establish them after the fact): the Level when
# --level is omitted and no --proof-before is given, the stamp before the flip and after R8, the reconcile counts, the queue
# check, the session control and the active-session counts. They are not UNREAD: they were never a read.
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

for _tool in jq gh awk timeout date mktemp; do
  command -v "$_tool" >/dev/null 2>&1 || { printf 'FATAL: required tool missing: %s\n' "$_tool" >&2; exit 64; }
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BSQ="${ROOT}/scripts/betterstack-query.sh"
REPO="jikig-ai/soleur"
RUN_URL_BASE="https://github.com/${REPO}/actions/runs"
PREDECESSOR_ISSUE=10166

# The Sentry destination is pinned to literals (ADR-202 Rule D): the read token is never sent anywhere else.
readonly SENTRY_HOST="jikigai-eu.sentry.io"
readonly SENTRY_ORG="jikigai-eu"
readonly SENTRY_PROJECT_ID="4511404943671376"

# shellcheck source=../lib/betterstack-sources.sh
source "${ROOT}/scripts/lib/betterstack-sources.sh" || { echo "FATAL: cannot load betterstack-sources.sh" >&2; exit 64; }
# shellcheck source=../lib/betterstack-read-classify.sh
source "${ROOT}/scripts/lib/betterstack-read-classify.sh" || { echo "FATAL: cannot load betterstack-read-classify.sh" >&2; exit 64; }
# shellcheck source=../lib/bearer-curl.sh
source "${ROOT}/scripts/lib/bearer-curl.sh" || { echo "FATAL: cannot load bearer-curl.sh" >&2; exit 64; }
# shellcheck source=../lib/git-data-rotate-stamp.sh
source "${ROOT}/scripts/lib/git-data-rotate-stamp.sh" || { echo "FATAL: cannot load git-data-rotate-stamp.sh" >&2; exit 64; }

usage() {
  printf 'usage: %s --flip <run id> --rollback <run id> --exit <run id> [--refs <run id>] [--proof-before <run id>] [--rotate <run id>] [--level 1|2]\n' \
    "$(basename "$0")" >&2
  exit 64
}

FLIP="" ROLLBACK="" EXITRUN="" REFS="" PROOF_BEFORE="" ROTATE="" LEVEL=""
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || usage
  case "$1" in
    --flip) FLIP="$2" ;;
    --rollback) ROLLBACK="$2" ;;
    --exit) EXITRUN="$2" ;;
    --refs) REFS="$2" ;;
    --proof-before) PROOF_BEFORE="$2" ;;
    --rotate) ROTATE="$2" ;;
    --level) LEVEL="$2" ;;
    *) usage ;;
  esac
  shift 2
done
for _id in "$FLIP" "$ROLLBACK" "$EXITRUN"; do [[ "$_id" =~ ^[0-9]{1,20}$ ]] || usage; done
for _id in "$PROOF_BEFORE" "$ROTATE" "$REFS"; do [[ -z "$_id" || "$_id" =~ ^[0-9]{1,20}$ ]] || usage; done
[[ -z "$LEVEL" || "$LEVEL" == 1 || "$LEVEL" == 2 ]] || usage
# One run cannot fill two slots (a pasted id repeated would certify a verdict from the wrong run).
_seen=" "
for _id in "$FLIP" "$ROLLBACK" "$EXITRUN" "$PROOF_BEFORE" "$ROTATE" "$REFS"; do
  [[ -z "$_id" ]] && continue
  [[ "$_seen" == *" $_id "* ]] && usage
  _seen+="$_id "
done
# A pre-deletion proof only exists in a Level 2 rehearsal.
[[ "$LEVEL" == 1 && -n "$PROOF_BEFORE" ]] && usage
[[ -n "$PROOF_BEFORE" && -z "$LEVEL" ]] && LEVEL=2

WORK="$(mktemp -d -t gd-rehearsal-evidence.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 64; }
case "$WORK" in /?*) : ;; *) echo "FATAL: scratch dir is not absolute" >&2; exit 64 ;; esac
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

unread=0
note_unread() { # $1 = token. One value-free stderr line; the block carries UNREAD(<token>).
  unread=$((unread + 1))
  printf 'UNREAD(%s)\n' "$1" >&2
}

TAB=$'\t'
ISO_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'

# A usable timestamp: well-formed AND not gh's zero time (0001-01-01T00:00:00Z) for an unset field.
iso_ok() { [[ "$1" =~ $ISO_RE ]] && (( 10#${1:0:4} >= 2020 )); }
iso_epoch() { iso_ok "$1" && date -u -d "$1" +%s 2>/dev/null; }
# ClickHouse and Sentry literals are built ONLY from a value that passed iso_ok.
ck_ts() { local t="${1/T/ }"; printf '%s' "${t%Z}"; }
sentry_ts() { printf '%s' "${1%Z}"; }

# gh sees neither credential it has no use for.
GHQ=(env -u SENTRY_ISSUE_RO_TOKEN -u BETTERSTACK_QUERY_PASSWORD gh)

# ---------------------------------------------------------------------------------------------------------------------
# GitHub reads
# ---------------------------------------------------------------------------------------------------------------------
# fetch_run <id> <slot> <expected displayTitle or ""> <expected workflowName prefix> <1 = also fetch the log>
# The run must BE the run the slot claims: workflow name, ref, event, completion and (when known) the run-name. A wrong id
# is refused rather than rendered, so a pasted id from the wrong run cannot produce a plausible block.
fetch_run() {
  local id="$1" slot="$2" title="$3" wf="$4" want_log="$5" att
  local json="${WORK}/${slot}.json"
  if ! timeout 90 "${GHQ[@]}" run view "$id" --repo "$REPO" \
      --json databaseId,attempt,workflowName,displayTitle,headBranch,event,status,conclusion,createdAt,updatedAt,jobs >"$json" 2>/dev/null; then
    note_unread "gh-run-view-${slot}"; return 1
  fi
  if ! jq -e --arg id "$id" --arg t "$title" --arg w "$wf" \
      '(.databaseId|tostring) == $id and ((.workflowName // "")|startswith($w)) and .headBranch == "main" and .event == "workflow_dispatch" and .status == "completed" and ($t == "" or .displayTitle == $t) and (.jobs|type) == "array"' \
      "$json" >/dev/null 2>&1; then
    note_unread "run-identity-${slot}"; return 1
  fi
  if [[ "$want_log" == 1 ]]; then
    att="$(jq -r '.attempt // 1' "$json")"
    [[ "$att" =~ ^[0-9]+$ ]] || att=1
    # The log is the SAME attempt as the jobs JSON (a re-run's createdAt is the original's, its jobs and log the latest).
    if ! timeout 180 "${GHQ[@]}" run view "$id" --repo "$REPO" --attempt "$att" --log >"${WORK}/${slot}.log" 2>/dev/null || [[ ! -s "${WORK}/${slot}.log" ]]; then
      note_unread "gh-run-log-${slot}"; return 1
    fi
  fi
  return 0
}

jfield() { jq -r --arg f "$2" '.[$f] // "absent" | tostring' "$1"; }

# stepc <json> <step-name prefix> <token> -> REPLY = the step's conclusion. A step missing from the job list (a rename) or
# with no conclusion is UNREAD, never a plain fact: only an explicit `skipped` means "did not run". The prefix is ASCII
# (the real names carry an em dash, or are cut at a YAML comment, after it).
stepc() {
  REPLY="$(jq -r --arg p "$2" \
    '[.jobs[]?.steps[]? | select((.name // "") | startswith($p))] | if length == 0 then "MISSING" else (.[0].conclusion // "") | if . == "" then "NONE" else . end end' "$1" 2>/dev/null)"
  case "$REPLY" in
    MISSING|NONE|"") note_unread "step-$3"; REPLY="UNREAD(step-$3)" ;;
  esac
}
# stepts <json> <prefix> -> the step's completedAt, but ONLY when the step succeeded: a skipped step carries a timestamp too
# (the job's), and a stamp from a step that never ran is not a flag write.
stepts() {
  jq -r --arg p "$2" \
    '[.jobs[]?.steps[]? | select((.name // "") | startswith($p))] | (.[0] // {}) | if .conclusion == "success" then (.completedAt // "") else "" end' "$1" 2>/dev/null
}

# Log lines are `<job>\t<step>\t<timestamp> <message>`, and the first line of a step section carries a UTF-8 BOM before the
# timestamp (stripped here). Matching is scoped to the EMITTING step and anchored at the start of the MESSAGE, so the step
# source that `run:` echoes at the head of each group (it contains the same words after `echo "`) is never counted, and
# neither is a line a dispatcher input echoed into another step's header.
LOG_TS='^[0-9T:.-]+Z '
lcount() { # <log> <emitting step prefix> <message regex after the timestamp> -> REPLY = count; returns 1 when awk failed
  REPLY="$(awk -F "$TAB" -v re="${LOG_TS}$3" -v st="$2" 'BEGIN { n = 0 } { gsub(/\357\273\277/, "", $3) } index($2, st) == 1 && $3 ~ re { n++ } END { print n }' "$1" 2>/dev/null)" || return 1
  [[ "$REPLY" =~ ^[0-9]+$ ]]
}
lfirst() { # <log> <emitting step prefix> <message regex> -> first matching line's timestamp truncated to seconds
  awk -F "$TAB" -v re="${LOG_TS}$3" -v st="$2" '{ gsub(/\357\273\277/, "", $3) } index($2, st) == 1 && $3 ~ re { split($3, a, " "); print substr(a[1], 1, 19) "Z"; exit }' "$1" 2>/dev/null
}

fetch_ok_flip=0
fetch_ok_rb=0
exit_ok=0
pb_ok=0
rot_ok=0
refs_ok=0
WFC="git-data cutover"
if fetch_run "$FLIP" flip "git-data flip" "$WFC" 1; then fetch_ok_flip=1; fi
if fetch_run "$ROLLBACK" rollback "git-data rollback" "$WFC" 1; then fetch_ok_rb=1; fi
if fetch_run "$EXITRUN" exit "git-data proof" "$WFC" 1; then exit_ok=1; fi
if [[ -n "$REFS" ]] && fetch_run "$REFS" refs "git-data refs_assert" "$WFC" 1; then refs_ok=1; fi
if [[ -n "$PROOF_BEFORE" ]] && fetch_run "$PROOF_BEFORE" proofbefore "git-data proof" "$WFC" 1; then pb_ok=1; fi
if [[ -n "$ROTATE" ]] && fetch_run "$ROTATE" rotate "" "Apply web-platform infra" 0; then rot_ok=1; fi

# The runs must be in the rehearsal's order: rotate, flip, rollback, refs_assert, [proof before deletion], exit proof. A run from another
# day passes every identity check, so ordering is what ties the four ids to ONE rehearsal.
created_epoch() { [[ -s "${WORK}/$1.json" ]] && iso_epoch "$(jq -r '.createdAt // ""' "${WORK}/$1.json")"; }
prev_epoch=0
# shellcheck disable=SC2034  # okflag is a nameref: the assignments set the caller's flag
order_check() { # <slot> <name of the slot's ok flag>
  local e
  local -n okflag="$2"
  e="$(created_epoch "$1")" || e=""
  if [[ -z "$e" ]]; then okflag=0; note_unread "run-created-$1"; return; fi
  if (( e < prev_epoch )); then okflag=0; note_unread "run-order-$1"; return; fi
  prev_epoch="$e"
}
(( fetch_ok_flip )) && order_check flip fetch_ok_flip
(( fetch_ok_rb )) && order_check rollback fetch_ok_rb
(( refs_ok )) && order_check refs refs_ok
(( pb_ok )) && order_check proofbefore pb_ok
(( exit_ok )) && order_check exit exit_ok
# the rotate precedes the flip it discharged
if (( rot_ok )); then
  rot_e="$(created_epoch rotate)"; flip_e="$(created_epoch flip)"
  if [[ -z "$rot_e" ]]; then rot_ok=0; note_unread run-created-rotate
  elif [[ -n "$flip_e" ]] && (( rot_e > flip_e )); then rot_ok=0; note_unread run-order-rotate; fi
fi

# ---------------------------------------------------------------------------------------------------------------------
# flip / rollback lines
# ---------------------------------------------------------------------------------------------------------------------
UNRD() { printf 'UNREAD(%s)' "$1"; }
FLIP_LINE="$(UNRD flip-run)"
ROLLBACK_LINE="$(UNRD rollback-run)"
flip_flag_at="" rb_flag_at=""
FLAGSTEP="Write GIT_DATA_STORE_ENABLED"

if (( fetch_ok_flip )); then
  j="${WORK}/flip.json"; l="${WORK}/flip.log"
  stepc "$j" 'Write GIT_DATA_LUKS_CUTOVER_AT' flip-stamp; stamp_c="$REPLY"
  stepc "$j" 'Finalizer' flip-finalizer; fin="$REPLY"
  if lcount "$l" 'Finalizer' 'finalizer: unwind complete[.]'; then done_n="$REPLY"; else done_n=""; fi
  if lcount "$l" 'Finalizer' 'finalizer: writing GIT_DATA_STORE_ENABLED=false'; then start_n="$REPLY"; else start_n=""; fi
  if [[ -z "$done_n" || -z "$start_n" ]]; then note_unread log-scan-flip; ran="$(UNRD log-scan-flip)"
  else
    if (( done_n > 0 )); then unwound="yes"; elif (( start_n > 0 )); then unwound="STARTED-NOT-COMPLETED"; else unwound="no"; fi
    case "$fin" in skipped) ran="no" ;; UNREAD*) ran="$fin" ;; *) ran="yes (unwound ${unwound})" ;; esac
  fi
  FLIP_LINE="$(printf '%s/%s   dispatched %s   conclusion %s   stamp step %s   finalizer ran %s' \
    "$RUN_URL_BASE" "$FLIP" "$(jfield "$j" createdAt)" "$(jfield "$j" conclusion)" "$stamp_c" "$ran")"
  flip_flag_at="$(stepts "$j" "$FLAGSTEP")"
fi
if (( fetch_ok_rb )); then
  j="${WORK}/rollback.json"; l="${WORK}/rollback.log"
  stepc "$j" 'Positive replication probe' rb-probe; probe_c="$REPLY"
  if lcount "$l" 'Positive replication probe' '([[]git-data-cutover[]] )?STORE probe=probe verdict=ok'; then
    if (( REPLY > 0 )); then seen="seen"; else seen="not seen"; fi
  else note_unread log-scan-rollback; seen="$(UNRD log-scan-rollback)"; fi
  ROLLBACK_LINE="$(printf '%s/%s   dispatched %s   conclusion %s   probe step %s   "STORE probe=probe verdict=ok" %s' \
    "$RUN_URL_BASE" "$ROLLBACK" "$(jfield "$j" createdAt)" "$(jfield "$j" conclusion)" "$probe_c" "$seen")"
  rb_flag_at="$(stepts "$j" "$FLAGSTEP")"
fi

# window: flag-on from the flip's flag_write completion to the rollback's flag-off completion. Both writes must have SUCCEEDED
# (a resumed flip and a nothing_to_rollback rollback skip the step but the API still stamps it).
WINDOW_LINE="$(UNRD window)"
WINDOW_OK=0
if iso_ok "$flip_flag_at" && iso_ok "$rb_flag_at"; then
  a="$(iso_epoch "$flip_flag_at")"; b="$(iso_epoch "$rb_flag_at")"
  if [[ -n "$a" && -n "$b" && "$b" -ge "$a" ]]; then
    mins="$(awk -v d=$((b - a)) 'BEGIN { printf "%.1f", d / 60 }')"
    WINDOW_LINE="flag-on from ${flip_flag_at} to ${rb_flag_at} = ${mins} minutes"
    WINDOW_OK=1
  fi
fi
if (( ! WINDOW_OK )); then
  # A flag_write that did not succeed in either run is a finding of its own (a resume arm, a nothing_to_rollback run).
  if (( fetch_ok_flip && fetch_ok_rb )); then printf 'window: a flag_write step did not succeed, or the writes are out of order\n' >&2; fi
  note_unread window
fi

# per-host: the workflow's own readback lines (`host web-N: git_data_store=<state> observed`) and their log timestamps.
host_ts() { # <slot> <host label> <state>
  local l="${WORK}/$1.log" t=""
  [[ -s "$l" ]] && t="$(lfirst "$l" 'Per-host git_data_store=' "host $2: git_data_store=$3 observed")"
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

# collect_bs <table> <s3 table> <sql> -> stdout in $WORK/bs.out; sets BS_READ_CLASS (a value-free class) and returns the reader's rc
collect_bs() {
  local rc=0
  BS_TABLE="$1" BS_TABLE_S3="$2" timeout -k 5 150 env -u SENTRY_ISSUE_RO_TOKEN bash "$BSQ" "$3" >"${WORK}/bs.out" 2>"${WORK}/bs.err" || rc=$?
  if (( rc != 0 )); then
    # The reader's credential-refusal marker is value-free and is the only stderr line surfaced.
    grep -m1 '^SOLEUR_CREDENTIAL_REFUSED' "${WORK}/bs.err" >&2 || true
    BS_READ_CLASS="bs-$(bs_read_classify "$rc" "${WORK}/bs.out")"
  fi
  return "$rc"
}

# The exit proof run's dispatch bounds every read from above.
exit_created=""
(( exit_ok )) && exit_created="$(jfield "${WORK}/exit.json" createdAt)"

APP_LINE="$(UNRD app-path)"
if (( WINDOW_OK )) && iso_ok "$exit_created"; then
  t0="$(ck_ts "$rb_flag_at")"; t9="$(ck_ts "$exit_created")"
  sql="SELECT JSONExtractString(raw,'host_name') AS h,
  countIf(positionCaseInsensitive(raw,'git_data_pin=present fp=') > 0) AS pin_n,
  countIf(positionCaseInsensitive(raw,'git_data_ssh_client=present') > 0) AS ssh_n,
  countIf(positionCaseInsensitive(raw,'git_data_store=disabled') > 0) AS store_n,
  groupUniqArrayIf(extract(raw,'git_data_pin=present fp=(SHA256:[A-Za-z0-9+/]{43})'), positionCaseInsensitive(raw,'git_data_pin=present fp=') > 0) AS fps
FROM (SELECT dt, raw FROM remote(\$BS_TABLE) WHERE dt >= '${t0}' AND dt <= '${t9}'
      UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1 AND dt >= '${t0}' AND dt <= '${t9}')
WHERE dt >= '${t0}' AND dt <= '${t9}' AND JSONExtractString(raw,'host_name') IN (${WEB_HOSTS_SQL})
  AND (positionCaseInsensitive(raw,'git_data_pin=') > 0 OR positionCaseInsensitive(raw,'git_data_ssh_client=') > 0 OR positionCaseInsensitive(raw,'git_data_store=') > 0)
GROUP BY h FORMAT JSONEachRow"
  if ! collect_bs "$BS_CONTROL_TABLE" "$BS_CONTROL_TABLE_S3" "$sql"; then
    note_unread "$BS_READ_CLASS"
  elif ! summary="$(jq -s -c --argjson map "$LABEL_MAP" '
        [ .[] | select(type == "object") | {l: ($map[.h] // "other"), pin: (.pin_n|tonumber), ssh: (.ssh_n|tonumber), st: (.store_n|tonumber),
          fps: [ (.fps // [])[] | select(test("^SHA256:[A-Za-z0-9+/]{43}\\z")) ]} ] as $r
        | { hosts: (["web-1","web-2"] | map(. as $l | ([ $r[] | select(.l == $l) ]) as $s
              | {l: $l, pin: ($s | map(.pin) | add // 0), ssh: ($s | map(.ssh) | add // 0), st: ($s | map(.st) | add // 0),
                 fps: ($s | map(.fps[]) | unique)})) }' <"${WORK}/bs.out" 2>/dev/null)" || [[ -z "$summary" ]]; then
    note_unread "bs-response-shape"
  elif [[ "$(jq -r '[.hosts[] | .pin + .ssh + .st] | add' <<<"$summary")" == "0" ]]; then
    # Zero rows from both hosts is the AMBIGUOUS silence (dark ingest, wrong table, or a fleet that never restarted);
    # it is not a measured "pin absent".
    note_unread "bs-silent-window"
  else
    # One silent host beside a speaking one is the same ambiguity at host scope: UNREAD, with the zero printed beside it.
    for l in web-1 web-2; do
      [[ "$(jq -r --arg l "$l" '.hosts[] | select(.l == $l) | .pin + .ssh + .st' <<<"$summary")" == "0" ]] && note_unread "bs-host-silent-${l}"
    done
    cnt() { jq -r --arg k "$1" '"(" + ([ .hosts[] | "\(.l) \(.[$k])" ] | join(", ")) + ")"' <<<"$summary"; }
    all_ge1() { jq -e --arg k "$1" '[.hosts[] | .[$k] >= 1] | all' <<<"$summary" >/dev/null 2>&1; }
    # the fingerprint: one value when both hosts agree, per host otherwise; counts without a parseable fingerprint are UNREAD
    if [[ "$(jq -r '[.hosts[] | .pin] | add' <<<"$summary")" == "0" ]]; then fp_part="none $(cnt pin)"
    elif [[ "$(jq -r '[.hosts[] | select(.pin > 0) | .fps | length] | min' <<<"$summary")" == "0" ]]; then note_unread bs-fp-shape; fp_part="$(UNRD bs-fp-shape) $(cnt pin)"
    elif jq -e '([.hosts[] | select(.pin > 0) | .fps] | unique | length) == 1' <<<"$summary" >/dev/null 2>&1; then
      fp_part="$(jq -r '[.hosts[] | select(.pin > 0)][0].fps | join(",")' <<<"$summary") $(cnt pin)"
    else fp_part="$(jq -r '[.hosts[] | select(.pin > 0) | "\(.l)=" + (.fps | join(","))] | join(" ")' <<<"$summary") $(cnt pin)"; fi
    if all_ge1 ssh; then ssh_part="ssh_client present $(cnt ssh)"; else ssh_part="ssh_client MISSING $(cnt ssh)"; fi
    if all_ge1 st; then st_part="store disabled $(cnt st)"; else st_part="store disabled MISSING $(cnt st)"; fi
    APP_LINE="startup lines after rollback flag-off: pin ${fp_part}, ${ssh_part}, ${st_part}"
  fi
fi
# Without a valid window and the exit run's dispatch there is no bound for the read; the cause is already named by the
# window / exit-run token, so the app-path field is marked here without a second count.
if [[ "$APP_LINE" == "UNREAD(app-path)" ]] && (( WINDOW_OK && unread == 0 )); then note_unread app-path; fi

# Sentry events between R1 (the flip dispatch) and the exit proof's dispatch.
SC_VAL="" SC_ERR=""
sentry_count() { # <query> -> SC_VAL = the count, or returns 1 with SC_ERR = a value-free token
  local body="${WORK}/sentry.json" code
  SC_VAL="" SC_ERR=""
  code="$(bc_curl git-data-rehearsal-evidence 'Authorization:Bearer :SENTRY_ISSUE_RO_TOKEN' -- -sS --max-time 30 -G \
    -o "$body" -w '%{http_code}' \
    --data-urlencode "project=${SENTRY_PROJECT_ID}" --data-urlencode "start=${S_START}" --data-urlencode "end=${S_END}" \
    --data-urlencode "field=count()" --data-urlencode "query=$1" \
    "https://${SENTRY_HOST}/api/0/organizations/${SENTRY_ORG}/events/")" || code=000
  case "$code" in
    200) : ;;
    401|403) SC_ERR="sentry-auth"; return 1 ;;
    *) SC_ERR="sentry-read"; return 1 ;;
  esac
  SC_VAL="$(jq -er 'if (type == "object") and ((.data|type) == "array") and ((.data|length) == 1) then .data[0]["count()"] else empty end' "$body" 2>/dev/null)" || { SC_ERR="sentry-read"; return 1; }
  [[ "$SC_VAL" =~ ^[0-9]+$ ]] || { SC_ERR="sentry-read"; SC_VAL=""; return 1; }
  return 0
}
SENTRY_PART="$(UNRD sentry)"
flip_created=""
(( fetch_ok_flip )) && flip_created="$(jfield "${WORK}/flip.json" createdAt)"
if iso_ok "$flip_created" && iso_ok "$exit_created"; then
  S_START="$(sentry_ts "$flip_created")"
  S_END="$(sentry_ts "$exit_created")"
  if [[ -z "${SENTRY_ISSUE_RO_TOKEN:-}" ]]; then
    note_unread sentry-token-absent
  elif ! bc_ok_var SENTRY_ISSUE_RO_TOKEN; then
    # The library's own value-free marker, and no request.
    bc_refuse git-data-rehearsal-evidence SENTRY_ISSUE_RO_TOKEN || true
    note_unread sentry-token-refused
  else
    # A Sentry zero is also what a wrong project, dark ingest or a lost org membership returns with HTTP 200, so the same
    # window is first read UNFILTERED: it must be non-zero for the filtered zeros below to be a measurement.
    if ! sentry_count ''; then note_unread "$SC_ERR"
    elif (( SC_VAL == 0 )); then note_unread sentry-silent-window
    elif ! sentry_count 'op:git-data-bare-repo-erasure'; then note_unread "$SC_ERR"
    else
      er="$SC_VAL"
      if ! sentry_count 'has:pin_fault'; then note_unread "$SC_ERR"
      else SENTRY_PART="$((er + SC_VAL)) (erasure ${er}, pin_fault ${SC_VAL}) in ${S_START}..${S_END}"; fi
    fi
  fi
else
  note_unread sentry-window
fi

# level 2 lines: proof before / after the synthetic account's deletion.
proof_verdict() { # <slot> -> clear | store_not_empty | unknown | conflict | scan
  local l="${WORK}/$1.log" c ne
  [[ -s "$l" ]] || { echo unknown; return; }
  local re='((##[[][a-z]+[]]|::[a-z]+ title=[^:]*::)|[[]git-data-cutover[]] (STORE )?)(probe=[a-z-]+ )?verdict='
  lcount "$l" 'Host-side proof' "${re}clear" || { echo scan; return; }; c="$REPLY"
  lcount "$l" 'Host-side proof' "${re}store_not_empty" || { echo scan; return; }; ne="$REPLY"
  if (( c > 0 && ne > 0 )); then echo conflict
  elif (( c > 0 )); then echo clear
  elif (( ne > 0 )); then echo store_not_empty
  else echo unknown; fi
}
EXIT_V="$(UNRD exit-verdict)"
EXIT_LINE="$(UNRD exit-run)"
if (( exit_ok )); then
  v="$(proof_verdict exit)"
  case "$v" in clear|store_not_empty) EXIT_V="$v" ;; *) note_unread "exit-verdict-${v}" ;; esac
  # A clear proof is a green run; a clear verdict line inside a red run is not a verdict.
  if [[ "$EXIT_V" == clear && "$(jfield "${WORK}/exit.json" conclusion)" != success ]]; then note_unread exit-verdict-conclusion; EXIT_V="$(UNRD exit-verdict-conclusion)"; fi
  EXIT_LINE="mode=proof run ${RUN_URL_BASE}/${EXITRUN}   dispatched $(jfield "${WORK}/exit.json" createdAt)   conclusion $(jfield "${WORK}/exit.json" conclusion)   verdict ${EXIT_V}"
fi

LEVEL2_LINE="level 2 only: n/a (level 1)"
if [[ "$LEVEL" == 2 ]]; then
  pbv="$(UNRD proof-before)"
  if (( pb_ok )); then
    v="$(proof_verdict proofbefore)"
    case "$v" in clear|store_not_empty) pbv="$v" ;; *) note_unread "proof-before-verdict-${v}" ;; esac
  fi
  LEVEL2_LINE="level 2 only: proof before deletion ${pbv}, proof after deletion ${EXIT_V}"
elif [[ -z "$LEVEL" ]]; then
  LEVEL2_LINE="level 2 only: <owner: pass --proof-before <run id> for a Level 2 rehearsal>"
fi
LEVEL_TXT="${LEVEL:-<owner: 1|2>}"

# ---------------------------------------------------------------------------------------------------------------------
# REFS-CONFIRMED: read from the mode=refs_assert run (the gate for R6, the account deletion and the real flip).
# ---------------------------------------------------------------------------------------------------------------------
REFS_STEP='Host-side refs assertion'
REFS_ANS_RE='^REFS_ASSERT ok repos=1 namespaces=[1-9][0-9]* refs=[1-9][0-9]* heads=[1-9][0-9]* shas=[0-9a-f]{40}(,[0-9a-f]{40})?$'
REFS_LINE="n/a (level 1; no synthetic session ran)"
if [[ -n "$REFS" ]]; then
  REFS_LINE="$(UNRD refs-run)"
  if (( refs_ok )); then
    j="${WORK}/refs.json"; l="${WORK}/refs.log"
    stepc "$j" "$REFS_STEP" refs-step; refs_step="$REPLY"
    refs_conf=""; refs_ans=""
    if lcount "$l" "$REFS_STEP" '([[]git-data-cutover[]] )?REFS-CONFIRMED$'; then refs_conf="$REPLY"; fi
    refs_msgs="$(awk -F "$TAB" -v re="${LOG_TS}([[]git-data-cutover[]] )?REFS_ASSERT ok " -v st="$REFS_STEP" \
      '{ gsub(/\357\273\277/, "", $3) } index($2, st) == 1 && $3 ~ re { m = $3; sub(/^[^ ]+ /, "", m); sub(/^[[]git-data-cutover[]] /, "", m); print m }' "$l" 2>/dev/null)" || refs_msgs=""
    refs_n="$(printf '%s' "$refs_msgs" | awk 'END { print NR }')"
    refs_c="$(jfield "$j" conclusion)"
    if [[ -z "$refs_conf" ]]; then note_unread log-scan-refs; REFS_LINE="$(UNRD log-scan-refs)"
    elif [[ "$refs_c" == success && "$refs_step" == success && "$refs_conf" == 1 && "$refs_n" == 1 && "$refs_msgs" =~ $REFS_ANS_RE ]]; then
      refs_ans="${refs_msgs#REFS_ASSERT ok }"; refs_ans="${refs_ans% shas=*}"
      REFS_LINE="mode=refs_assert run ${RUN_URL_BASE}/${REFS}   dispatched $(jfield "$j" createdAt)   conclusion ${refs_c}   step success   REFS-CONFIRMED yes (${refs_ans})"
    else
      note_unread refs-not-confirmed
      REFS_LINE="mode=refs_assert run ${RUN_URL_BASE}/${REFS}   dispatched $(jfield "$j" createdAt)   conclusion ${refs_c}   step ${refs_step}   REFS-CONFIRMED NOT CONFIRMED (confirmed lines ${refs_conf}, answer lines ${refs_n}): $(UNRD refs-not-confirmed)"
    fi
  fi
elif [[ "$LEVEL" == 2 ]]; then
  note_unread refs-run
  REFS_LINE="$(UNRD refs-run)"
elif [[ -z "$LEVEL" ]]; then
  REFS_LINE="<owner: pass --refs <run id> for a Level 2 rehearsal>"
fi

# ---------------------------------------------------------------------------------------------------------------------
# predecessor: the rotate run, the apply step, plan_only, and the new server's boot_complete.
# ---------------------------------------------------------------------------------------------------------------------
PRED_LINE="<owner: pass --rotate <run id>>"
if [[ -n "$ROTATE" ]]; then
  PRED_LINE="$(UNRD predecessor)"
  if (( rot_ok )); then
    rj="${WORK}/rotate.json"
    rv="$(git_data_rotate_run_verdict "$(cat "$rj")")" || true
    if [[ "$rv" != stamped ]]; then
      # Only a stamped rotate has an apply step that ran for real and a new server to read a boot from.
      note_unread "rotate-${rv}"
    else
      apply_prefix="${GDRS_APPLY_STEP%% —*}"
      stepc "$rj" "$apply_prefix" rotate-apply; apply_c="$REPLY"
      rot_at="$(stepts "$rj" "$apply_prefix")"
      boot_at="$(UNRD boot_complete)"
      if iso_ok "$rot_at"; then
        t1="$(ck_ts "$rot_at")"
        upper=""
        (( fetch_ok_flip )) && iso_ok "$flip_created" && upper=" AND dt <= '$(ck_ts "$flip_created")'"
        sql="SELECT formatDateTime(min(dt), '%Y-%m-%dT%H:%i:%SZ') AS t, count() AS n
FROM (SELECT dt, raw FROM remote(\$BS_TABLE) WHERE dt >= '${t1}'${upper}
      UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1 AND dt >= '${t1}'${upper})
WHERE dt >= '${t1}'${upper} AND JSONExtractString(raw,'stage') = 'boot_complete' AND JSONExtractString(raw,'host_name') = 'soleur-git-data'
FORMAT JSONEachRow"
        if ! collect_bs "$BS_GIT_DATA_TABLE" "$BS_GIT_DATA_TABLE_S3" "$sql"; then
          note_unread "$BS_READ_CLASS"
        else
          bt="$(jq -r 'select(type == "object" and ((.n|tonumber) > 0)) | .t' <"${WORK}/bs.out" 2>/dev/null | head -1)"
          if iso_ok "$bt"; then boot_at="$bt"; else note_unread boot-complete-absent; fi
        fi
      else
        note_unread boot-complete-window
      fi
      st_issue="$(timeout 60 "${GHQ[@]}" issue view "$PREDECESSOR_ISSUE" --repo "$REPO" --json state -q .state 2>/dev/null)" || st_issue=""
      [[ "$st_issue" =~ ^(OPEN|CLOSED)$ ]] || { note_unread "issue-${PREDECESSOR_ISSUE}"; st_issue="$(UNRD "issue-${PREDECESSOR_ISSUE}")"; }
      PRED_LINE="rotate run ${ROTATE}, apply step ${apply_c}, plan_only false, new-server boot_complete ${boot_at}; #${PREDECESSOR_ISSUE} ${st_issue}"
    fi
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
  "refs read:     ${REFS_LINE}" \
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
