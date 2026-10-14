#!/usr/bin/env bash
#
# git-data-wipe.sh — the Hetzner API half of retiring the plaintext rollback volume (#10138 / #6897,
# ADR-239 DL-2, ADR-241). Called from the `wipe` job of .github/workflows/git-data-cutover.yml; every
# step that calls it runs this script as the child of `exec env -i <allow-list> bash`, so the
# credential below reaches only this process.
#
# CREDENTIAL HAND-OVER (CTO 12b). The token is ONE line on STDIN, read here with `read -r`; it is never
# an argument (the caller hands it over by here-string) and never read from the inherited environment
# (the two token names are unset before the read, so an exported value cannot stand in for the line).
# The read-only verbs read HCLOUD_TOKEN_READONLY; `detach` and `delete` read HCLOUD_TOKEN, the Tier-B
# write token, and nothing else. A verb whose line is empty refuses; there is NO fall-back from one
# name to the other, ever (the precedent `workspaces-luks-cutover.yml` fell back; this does not). The
# value reaches curl only through scripts/lib/bearer-curl.sh (its stdin config channel), by NAME.
#
# VERBS (each fail-closed; every refusal is `verdict=<word>` on stdout, a `::error` annotation, a
# `verdict=<word>` line in $GITHUB_OUTPUT when the runner provides it, and exit 5; usage errors exit 2;
# xtrace exits 78). Values printed are digits and fixed words only, never a name read from a volume.
#   phases                              prints the closed phase vocabulary, one word per line
#   state                               [ro]  prints whether the plaintext volume is attached,
#                                       detached or absent, and whether the LUKS volume is attached
#   identity --expect attached|detached --volume-id N [--record write|check] [--show-ids]
#                                       [ro]  R1-R6 of the design: the typed id is the one volume named
#                                       soleur-git-data-store, is not the LUKS volume, is attached to
#                                       the one soleur-git-data server (or detached), unprotected,
#                                       labelled and located like the LUKS volume
#   actions --volume-id N [--since EPOCH]
#                                       [ro]  GET /volumes/<id>/actions: without --since it reports the
#                                       count and the latest command word (then refuses
#                                       wipe_detach_in_flight when the newest attach/detach is running); with --since it requires the
#                                       newest attach/detach action to be detach_volume success started
#                                       at or after EPOCH, NO attach_volume action started at or after
#                                       EPOCH anywhere in the list (detach, attach, detach is refused),
#                                       and nothing running
#   detach --volume-id N                [rw]  record_check w7, ONE POST detach (201), poll the SAME
#                                       action every 2 s at most 30 times, never re-POST, then confirm
#                                       the volume has no server
#   delete --volume-id N                [rw]  record_check w10b, ONE DELETE (204)
#   readback --volume-id N              [ro]  the id answers 404 AND the name lists nothing AND the LUKS
#                                       volume is still the one attached to the one server
#   record_check --epoch w7|w10b [--volume-id N]
#                                       no network: the verdict record exists, is mode 0600, binds the
#                                       volume and its epoch is inside the pinned bound
#   stamp --epoch w7                    no network: stamps the W7 epoch into the record
# The verdict record is $RUNNER_TEMP/git-data-wipe-record (server id, created, both volume ids, epochs;
# never a token). `identity --record write` creates it, `stamp --epoch w7` stamps the host look,
# `identity --record check` re-reads Hetzner against it and stamps the W10b epoch.
#
# $GITHUB_OUTPUT keys: verdict (refusals), refusal (volume_already_detached only), volume_state
# (attached|detached|absent), luks_state, phase (detached | delete_sent | deleted, written the moment
# the call is confirmed: `detached` only by the detach verb after its confirm read, never by
# `identity`, whose subject is an input of the run and not an event of it), actions_count,
# actions_latest, detach_evidence (ok: the --since proof held), detach_action, record_age_s.
#
# SHAPES PINNED FROM A LIVE READ-ONLY CALL (2026-10-14, HCLOUD_TOKEN_READONLY): GET /servers?name= and
# GET /volumes?name= answer 200 with .servers[] / .volumes[] (id number, name, server number|null,
# protection.delete boolean, labels.app, location.name, created); GET /volumes/<id> answers
# {"volume":{...}}; GET /volumes/<id>/actions answers {"actions":[{id,command,status,started,
# finished,progress,resources}],"meta":{"pagination":{...}}} with sort=id:desc honoured, timestamps
# like 2026-10-14T14:33:56Z; GET /actions/<id> answers {"action":{...}}; an unknown id answers 404
# {"error":{"code":"not_found",...}}. PINNED FROM PRECEDENT, NOT YET SEEN LIVE: the detach POST
# (201, .action.id), the action's `error` end state and the DELETE (204, 423 while attached).
#
# WORDING (CLO ruling): the only claim made about the end state is that the DEVICE was deleted at the
# provider API; nothing here says what the bytes were, and no name from a volume is ever read.
set -uo pipefail

case "$-" in
  *x*) printf '[git-data-wipe] refusing to run under xtrace: this script binds Hetzner API tokens and -x would print them (see #7797)\n' >&2; exit 78 ;;
esac

readonly WIPE_API_BASE='https://api.hetzner.cloud/v1'
readonly WIPE_SERVER_NAME='soleur-git-data'
readonly WIPE_PLAINTEXT_NAME='soleur-git-data-store'
readonly WIPE_LUKS_NAME='soleur-git-data-luks-store'
readonly WIPE_LABEL_APP='soleur-web-platform'
# Pinned, assigned unconditionally: no environment value, input or argument can move them (the soak
# floor's rule). The W7 bound is sized from the loader measurement of plan Phase 0.4 (twice the
# largest observed W7b + loader + gaps, floor 120 s). MEASURED 2026-10-14 over 83 samples of recent
# apply/drift runs: the Tier-B loader step took 0 s x3, 1 s x73, 2 s x7; so the formula lands on its
# floor and the bound is that floor, 120 s.
readonly WIPE_W7_BOUND_SECONDS=120
readonly WIPE_W10B_BOUND_SECONDS=60
readonly WIPE_W4_OUTER_BOUND_SECONDS=900
readonly WIPE_POLL_INTERVAL_SECONDS=2
readonly WIPE_POLL_MAX_ATTEMPTS=30
readonly WIPE_CURL_MAX_TIME=20
readonly WIPE_CURL_MAX_FILESIZE=1048576

# `phases` is a static vocabulary: no workspace, no library, no token, no network. It is dispatched here,
# before the library source, so a sandbox with nothing but PATH (preflight's probe) can run it.
do_phases() {
  if [[ $# -gt 0 ]]; then printf '[git-data-wipe] verdict=wipe_usage reason=option_not_allowed\n' >&2; exit 2; fi
  printf '%s\n' detach_attempted detached delete_attempted delete_sent deleted
}
if [[ "${1-}" == phases ]]; then shift; do_phases "$@"; exit 0; fi

# The sibling scripts pin the locale: a UTF-8 locale would widen the [A-Za-z] classes that guard the
# $GITHUB_OUTPUT and verdict-record writes below.
export LC_ALL=C

if
  source "${GITHUB_WORKSPACE:?}/scripts/lib/bearer-curl.sh"
then
  :
else
  printf '[git-data-wipe] verdict=wipe_library_missing\n' >&2
  exit 1
fi

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (the fixture-dir-operand-assert suite
# pins every tracked copy byte-identical). It guards the verdict-record writes below, whose operand
# comes from the environment ($RUNNER_TEMP).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

# --- output --------------------------------------------------------------------------------------
out() { printf '[git-data-wipe] %s\n' "$*"; }

gho() { # <key> <value>: append to $GITHUB_OUTPUT when the runner provides it; fixed charset only
  [[ -n "${GITHUB_OUTPUT-}" && "$GITHUB_OUTPUT" == /* ]] || return 0
  [[ "$1" =~ ^[a-z_0-9]+$ && "$2" =~ ^[A-Za-z0-9_.:+-]*$ ]] || return 0
  printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
}

refuse() { # <verdict-word> [<detail: digits and fixed words only>]
  local word="$1"; shift
  local detail="${*-}"
  printf '[git-data-wipe] verdict=%s%s\n' "$word" "${detail:+ $detail}"
  printf '::error title=git-data-wipe::verdict=%s%s\n' "$word" "${detail:+ $detail}"
  gho verdict "$word"
  if [[ "$word" == wipe_volume_already_detached ]]; then gho refusal volume_already_detached; fi
  exit 5
}

usage_fail() { # <fixed-reason-word>
  printf '[git-data-wipe] verdict=wipe_usage reason=%s\n' "$1" >&2
  exit 2
}

# --- scratch -------------------------------------------------------------------------------------
HZ_BODY="$(mktemp)" || { printf '[git-data-wipe] verdict=wipe_scratch_unavailable\n' >&2; exit 1; }
trap 'rm -f "$HZ_BODY"' EXIT
HZ_CODE=000
JV=""

# --- time ----------------------------------------------------------------------------------------
NOW=0
now_epoch() {
  local t
  t="$(date +%s)" || refuse wipe_clock_unreadable
  [[ "$t" =~ ^[0-9]{9,11}$ ]] || refuse wipe_clock_unreadable
  NOW=$((10#$t))
}

# --- credentials: one stdin line, by NAME, no fall-back -------------------------------------------
read_token() { # <ro|rw>
  local _var _line=""
  case "$1" in
    ro) _var=HCLOUD_TOKEN_READONLY ;;
    rw) _var=HCLOUD_TOKEN ;;
    *) usage_fail token_class ;;
  esac
  # An exported value of either name must not be able to stand in for the stdin line.
  unset HCLOUD_TOKEN HCLOUD_TOKEN_READONLY
  IFS= read -r -t 10 _line || true
  _line="${_line%$'\r'}"
  if [[ -z "$_line" ]]; then
    if [[ "$1" == ro ]]; then refuse wipe_readonly_token_absent; fi
    refuse wipe_write_token_absent
  fi
  printf -v "$_var" '%s' "$_line"
  _line=""
  if ! bc_ok_var "$_var"; then
    bc_refuse git-data-wipe "$_var" || true
    if [[ "$1" == ro ]]; then refuse wipe_readonly_token_unusable; fi
    refuse wipe_write_token_unusable
  fi
}

# --- the two Hetzner calls (the only bearer-curl statements) ---------------------------------------
hz_get() { # <path>: read-only token; sets HZ_CODE, body in $HZ_BODY
  : > "$HZ_BODY"
  HZ_CODE="$(bc_curl git-data-wipe 'Authorization:Bearer :HCLOUD_TOKEN_READONLY' -- -sS --max-time "$WIPE_CURL_MAX_TIME" --max-filesize "$WIPE_CURL_MAX_FILESIZE" -o "$HZ_BODY" -w '%{http_code}' "${WIPE_API_BASE}$1")" || HZ_CODE=000
  [[ "$HZ_CODE" =~ ^[0-9]{3}$ ]] || HZ_CODE=000
}

hz_write() { # <METHOD> <path>: the write token; sets HZ_CODE, body in $HZ_BODY
  : > "$HZ_BODY"
  HZ_CODE="$(bc_curl git-data-wipe 'Authorization:Bearer :HCLOUD_TOKEN' -- -sS --max-time "$WIPE_CURL_MAX_TIME" --max-filesize "$WIPE_CURL_MAX_FILESIZE" -X "$1" -o "$HZ_BODY" -w '%{http_code}' "${WIPE_API_BASE}$2")" || HZ_CODE=000
  [[ "$HZ_CODE" =~ ^[0-9]{3}$ ]] || HZ_CODE=000
}

# --- JSON ------------------------------------------------------------------------------------------
JQ_PRE='def must(c): if c then . else error("shape") end; def uint: type=="number" and .==floor and .>0;'
jget() { # <filter> [jq options...]: sets JV; returns jq's status (non-zero on any shape error)
  local f="$1"; shift
  JV="$(jq -r "$@" "${JQ_PRE} ${f}" "$HZ_BODY" 2>/dev/null)"
}
is_uint() { [[ "${1-}" =~ ^[1-9][0-9]{0,15}$ ]]; }

# --- arguments -------------------------------------------------------------------------------------
EXPECT=""; VOLUME_ID=""; RECORD_MODE=""; EPOCH_NAME=""; SINCE=""; SHOW_IDS=0; GIVEN=" "
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --expect)    [[ $# -ge 2 ]] || usage_fail missing_value; EXPECT="$2"; GIVEN+="expect "; shift 2 ;;
      --volume-id) [[ $# -ge 2 ]] || usage_fail missing_value; VOLUME_ID="$2"; GIVEN+="volume "; shift 2 ;;
      --record)    [[ $# -ge 2 ]] || usage_fail missing_value; RECORD_MODE="$2"; GIVEN+="record "; shift 2 ;;
      --epoch)     [[ $# -ge 2 ]] || usage_fail missing_value; EPOCH_NAME="$2"; GIVEN+="epoch "; shift 2 ;;
      --since)     [[ $# -ge 2 ]] || usage_fail missing_value; SINCE="$2"; GIVEN+="since "; shift 2 ;;
      --show-ids)  SHOW_IDS=1; GIVEN+="show "; shift ;;
      *) usage_fail unknown_argument ;;
    esac
  done
}
only_opts() { # <allowed option names, space separated>: every option given must be allowed
  local g
  for g in $GIVEN; do
    [[ " $1 " == *" $g "* ]] || usage_fail option_not_allowed
  done
}
VID=0
need_volume_id() {
  [[ "$GIVEN" == *" volume "* ]] || usage_fail volume_id_required
  [[ "$VOLUME_ID" =~ ^[0-9]{1,12}$ ]] || refuse wipe_volume_id_shape
  VID=$((10#$VOLUME_ID))
  (( VID >= 1 )) || refuse wipe_volume_id_shape
}

# --- the verdict record ------------------------------------------------------------------------------
REC=""
R_server_id=""; R_server_created=""; R_plaintext_id=""; R_luks_id=""; R_w4_epoch=""; R_w7_epoch=""; R_w10b_epoch=""
REC_AGE=0
rec_init() {
  assert_fixture_dir "${RUNNER_TEMP-}"
  REC="${RUNNER_TEMP}/git-data-wipe-record"
}
rec_load() {
  local mode line k v seen=" "
  rec_init
  [[ -e "$REC" || -L "$REC" ]] || refuse wipe_record_absent
  [[ -f "$REC" && ! -L "$REC" && -O "$REC" ]] || refuse wipe_record_invalid reason=type
  mode="$(stat -c %a -- "$REC")" || refuse wipe_record_invalid reason=stat
  [[ "$mode" == 600 ]] || refuse wipe_record_invalid reason=mode
  R_server_id=""; R_server_created=""; R_plaintext_id=""; R_luks_id=""; R_w4_epoch=""; R_w7_epoch=""; R_w10b_epoch=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^(server_id|server_created|plaintext_id|luks_id|w4_epoch|w7_epoch|w10b_epoch)=([A-Za-z0-9:+-]*)$ ]] || refuse wipe_record_invalid reason=line
    k="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"
    [[ "$seen" != *" $k "* ]] || refuse wipe_record_invalid reason=duplicate
    seen+="$k "
    case "$k" in
      server_created) [[ "$v" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:[0-9]{2})$ ]] || refuse wipe_record_invalid reason=value ;;
      *_epoch)        [[ -z "$v" || "$v" =~ ^[0-9]{9,11}$ ]] || refuse wipe_record_invalid reason=value ;;
      *)              [[ "$v" =~ ^[1-9][0-9]{0,15}$ ]] || refuse wipe_record_invalid reason=value ;;
    esac
    printf -v "R_${k}" '%s' "$v"
  done < "$REC"
  [[ -n "$R_server_id" && -n "$R_server_created" && -n "$R_plaintext_id" && -n "$R_luks_id" && -n "$R_w4_epoch" ]] || refuse wipe_record_invalid reason=incomplete
}
rec_save() {
  local tmp
  rec_init
  umask 077
  tmp="$(mktemp "${RUNNER_TEMP}/git-data-wipe-record.XXXXXX")" || refuse wipe_record_invalid reason=write
  # The canonical guard on each write operand (the relative-operand ratchet reads these statements).
  assert_fixture_dir "$tmp"
  assert_fixture_dir "$REC"
  if ! printf 'server_id=%s\nserver_created=%s\nplaintext_id=%s\nluks_id=%s\nw4_epoch=%s\nw7_epoch=%s\nw10b_epoch=%s\n' \
    "$R_server_id" "$R_server_created" "$R_plaintext_id" "$R_luks_id" "$R_w4_epoch" "$R_w7_epoch" "$R_w10b_epoch" > "$tmp"; then
    rm -f "$tmp"; refuse wipe_record_invalid reason=write
  fi
  chmod 600 "$tmp" || { rm -f "$tmp"; refuse wipe_record_invalid reason=write; }
  mv -f "$tmp" "$REC" || { rm -f "$tmp"; refuse wipe_record_invalid reason=write; }
}
record_verify() { # <w7|w10b> [<typed volume id, normalised>]
  local e bound age
  rec_load
  if [[ -n "${2-}" && "$2" != "$R_plaintext_id" ]]; then refuse wipe_record_volume_mismatch; fi
  case "$1" in
    w7)   e="$R_w7_epoch"; bound="$WIPE_W7_BOUND_SECONDS" ;;
    w10b) e="$R_w10b_epoch"; bound="$WIPE_W10B_BOUND_SECONDS"
          [[ -n "$R_w7_epoch" ]] || refuse wipe_assertion_stale reason=w7_unstamped ;;
    *)    usage_fail epoch_name ;;
  esac
  [[ -n "$e" ]] || refuse wipe_assertion_stale reason=unstamped
  now_epoch
  # e passed the ^[0-9]{9,11}$ shape check in rec_load; 10# keeps a leading zero from reading as octal.
  if (( 10#$e > NOW + 5 )); then refuse wipe_assertion_stale reason=future; fi
  age=$(( NOW - 10#$e ))
  (( age >= 0 )) || age=0
  (( age <= bound )) || refuse wipe_assertion_stale "reason=expired age_s=$age bound_s=$bound"
  REC_AGE="$age"
}

# --- Hetzner reads shared by the verbs ----------------------------------------------------------------
SRV_ID=""; SRV_CREATED=""
read_server() { # R1: exactly one server named soleur-git-data
  hz_get "/servers?name=${WIPE_SERVER_NAME}"
  [[ "$HZ_CODE" == 200 ]] || refuse wipe_server_unreadable "code=$HZ_CODE"
  jget '.servers | must(type=="array") | length' || refuse wipe_server_unreadable reason=shape
  [[ "$JV" =~ ^[0-9]{1,6}$ ]] || refuse wipe_server_unreadable reason=shape
  [[ "$JV" == 1 ]] || refuse wipe_server_count "count=$JV"
  jget '.servers[0] | must(type=="object" and .name==$n and (.id|uint) and (.created|type=="string")) | "\(.id) \(.created)"' --arg n "$WIPE_SERVER_NAME" || refuse wipe_server_unreadable reason=shape
  SRV_ID="${JV%% *}"; SRV_CREATED="${JV#* }"
  is_uint "$SRV_ID" || refuse wipe_server_unreadable reason=shape
  [[ "$SRV_CREATED" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:[0-9]{2})$ ]] || refuse wipe_server_unreadable reason=shape
}

# read_volume_list <name> <unreadable-word>: sets V_N and, for exactly one volume, V_ID,
# V_SERVER (digits or null), V_LOC, V_APP. Protection is read separately (its own verdict words).
V_N=0; V_ID=""; V_SERVER=""; V_LOC=""; V_APP=""
read_volume_list() {
  V_N=0; V_ID=""; V_SERVER=""; V_LOC=""; V_APP=""
  hz_get "/volumes?name=$1"
  [[ "$HZ_CODE" == 200 ]] || refuse "$2" "code=$HZ_CODE"
  jget '.volumes | must(type=="array") | length' || refuse "$2" reason=shape
  [[ "$JV" =~ ^[0-9]{1,6}$ ]] || refuse "$2" reason=shape
  V_N="$JV"
  [[ "$V_N" == 1 ]] || return 0
  jget '.volumes[0] | must(type=="object" and .name==$n and (.id|uint)) | .id' --arg n "$1" || refuse "$2" reason=shape
  V_ID="$JV"; is_uint "$V_ID" || refuse "$2" reason=shape
  jget '.volumes[0].server | must(.==null or uint) | if .==null then "null" else tostring end' || refuse "$2" reason=shape
  V_SERVER="$JV"; [[ "$V_SERVER" == null ]] || is_uint "$V_SERVER" || refuse "$2" reason=shape
  jget '.volumes[0].location.name | must(type=="string") | select(test("^[a-z0-9-]{1,32}$"))' || refuse "$2" reason=shape
  V_LOC="$JV"
  [[ -n "$V_LOC" ]] || refuse "$2" reason=shape
  jget '.volumes[0].labels | must(type=="object") | (.app // "") | must(type=="string") | select(test("^[A-Za-z0-9._-]{0,64}$"))' || refuse "$2" reason=shape
  V_APP="$JV"
}
read_protection() { # of the single volume in the body: sets V_PROT (true|false)
  jget '.volumes[0].protection.delete | must(type=="boolean") | tostring' || refuse wipe_protection_unreadable
  V_PROT="$JV"
}
V_PROT=""

# --- verbs ----------------------------------------------------------------------------------------------
classify_server() { # <volume server field> -> attached|detached|other_host (relative to SRV_ID)
  if [[ "$1" == null ]]; then CLS=detached
  elif [[ "$1" == "$SRV_ID" ]]; then CLS=attached
  else CLS=other_host
  fi
}
CLS=""

do_state() {
  local pt_n pt_cls luks_n luks_cls
  only_opts "show"
  read_token ro
  read_server
  read_volume_list "$WIPE_LUKS_NAME" wipe_luks_unreadable
  luks_n="$V_N"
  case "$luks_n" in
    0) luks_cls=absent ;;
    1) classify_server "$V_SERVER"; luks_cls="$CLS" ;;
    *) refuse wipe_luks_count "count=$luks_n" ;;
  esac
  local luks_id="$V_ID"
  read_volume_list "$WIPE_PLAINTEXT_NAME" wipe_volume_unreadable
  pt_n="$V_N"
  case "$pt_n" in
    0) pt_cls=absent ;;
    1) classify_server "$V_SERVER"; pt_cls="$CLS" ;;
    *) refuse wipe_volume_count "count=$pt_n" ;;
  esac
  gho volume_state "$pt_cls"
  gho luks_state "$luks_cls"
  if (( SHOW_IDS )); then
    out "state plaintext=$pt_cls luks=$luks_cls plaintext_volumes=$pt_n luks_volumes=$luks_n servers=1 server_id=$SRV_ID plaintext_id=${V_ID:-none} luks_id=${luks_id:-none}"
  else
    out "state plaintext=$pt_cls luks=$luks_cls plaintext_volumes=$pt_n luks_volumes=$luks_n servers=1"
  fi
}

do_identity() {
  local ptid pt_server pt_loc pt_app luks_id luks_loc
  only_opts "expect volume record show"
  case "$EXPECT" in attached|detached) : ;; *) usage_fail expect_value ;; esac
  case "$RECORD_MODE" in ""|write|check) : ;; *) usage_fail record_value ;; esac
  need_volume_id
  if [[ "$RECORD_MODE" == check ]]; then rec_load; fi
  read_token ro
  read_server
  # R3 first: the LUKS volume decides `wipe_target_is_luks` before any other judgement of the typed id.
  read_volume_list "$WIPE_LUKS_NAME" wipe_luks_unreadable
  [[ "$V_N" == 1 ]] || refuse wipe_luks_count "count=$V_N"
  luks_id="$V_ID"; luks_loc="$V_LOC"
  [[ "$VID" != "$luks_id" ]] || refuse wipe_target_is_luks
  [[ "$V_SERVER" == "$SRV_ID" ]] || refuse wipe_not_attached_to_current_host which=luks
  # R2
  read_volume_list "$WIPE_PLAINTEXT_NAME" wipe_volume_unreadable
  case "$V_N" in
    0)
      [[ "$EXPECT" == detached ]] || refuse wipe_volume_count count=0
      hz_get "/volumes/${VID}"
      case "$HZ_CODE" in
        404)
          jget '.error | must(type=="object" and .code=="not_found") | .code' || refuse wipe_volume_unreadable reason=not_found_shape
          [[ "$JV" == not_found ]] || refuse wipe_volume_unreadable reason=not_found_shape
          [[ "$RECORD_MODE" != check ]] || refuse wipe_target_changed reason=absent
          gho volume_state absent
          gho luks_state attached
          out "identity ok expect=detached volume_state=absent luks_state=attached servers=1 plaintext_volumes=0 luks_volumes=1 record=none"
          return 0 ;;
        200) refuse wipe_volume_id_mismatch reason=exists_under_other_name ;;
        *)   refuse wipe_volume_unreadable "code=$HZ_CODE" ;;
      esac ;;
    1) : ;;
    *) refuse wipe_volume_count "count=$V_N" ;;
  esac
  ptid="$V_ID"; pt_server="$V_SERVER"; pt_loc="$V_LOC"; pt_app="$V_APP"
  [[ "$ptid" == "$VID" ]] || refuse wipe_volume_id_mismatch
  [[ "$ptid" != "$luks_id" ]] || refuse wipe_target_is_luks
  # R5
  read_protection
  [[ "$V_PROT" == false ]] || refuse wipe_delete_protected
  # R6
  [[ "$pt_app" == "$WIPE_LABEL_APP" && "$pt_loc" == "$luks_loc" ]] || refuse wipe_label_mismatch
  # R4
  classify_server "$pt_server"
  case "$EXPECT:$CLS" in
    attached:attached|detached:detached) : ;;
    attached:detached) refuse wipe_volume_already_detached ;;
    detached:attached) refuse wipe_volume_not_detached ;;
    *) refuse wipe_not_attached_to_current_host which=plaintext ;;
  esac
  case "$RECORD_MODE" in
    write)
      now_epoch
      R_server_id="$SRV_ID"; R_server_created="$SRV_CREATED"; R_plaintext_id="$ptid"; R_luks_id="$luks_id"
      R_w4_epoch="$NOW"; R_w7_epoch=""; R_w10b_epoch=""
      rec_save ;;
    check)
      [[ "$R_server_id" == "$SRV_ID" ]] || refuse wipe_target_changed reason=server
      [[ "$R_server_created" == "$SRV_CREATED" ]] || refuse wipe_target_changed reason=server_created
      [[ "$R_plaintext_id" == "$ptid" ]] || refuse wipe_target_changed reason=plaintext_volume
      [[ "$R_luks_id" == "$luks_id" ]] || refuse wipe_target_changed reason=luks_volume
      [[ -n "$R_w7_epoch" ]] || refuse wipe_assertion_stale reason=w7_unstamped
      now_epoch
      R_w10b_epoch="$NOW"
      rec_save ;;
  esac
  gho volume_state "$CLS"
  gho luks_state attached
  local ids=""
  if (( SHOW_IDS )); then ids=" server_id=$SRV_ID plaintext_id=$ptid luks_id=$luks_id"; fi
  out "identity ok expect=$EXPECT volume_state=$CLS luks_state=attached servers=1 plaintext_volumes=1 luks_volumes=1 protection_delete=false label=ok location=ok record=${RECORD_MODE:-none}${ids}"
}

do_actions() {
  local count latest verdict
  only_opts "volume since"
  need_volume_id
  if [[ "$GIVEN" == *" since "* ]]; then
    [[ "$SINCE" =~ ^[0-9]{9,11}$ ]] || refuse wipe_actions_unreadable reason=since_shape
  fi
  read_token ro
  hz_get "/volumes/${VID}/actions?sort=id:desc&per_page=50"
  [[ "$HZ_CODE" == 200 ]] || refuse wipe_actions_unreadable "code=$HZ_CODE"
  jget '.actions | must(type=="array") | must(all(.[]; type=="object" and (.id|uint) and (.command|type=="string") and (.status|type=="string"))) | length' || refuse wipe_actions_unreadable reason=shape
  [[ "$JV" =~ ^[0-9]{1,6}$ ]] || refuse wipe_actions_unreadable reason=shape
  count="$JV"
  jget '.actions | sort_by(-.id) | (.[0].command // "none") | if . == "none" or . == "attach_volume" or . == "detach_volume" or . == "create_volume" or . == "resize_volume" or . == "change_protection" then . else "other" end' || refuse wipe_actions_unreadable reason=shape
  latest="$JV"
  gho actions_count "$count"
  gho actions_latest "$latest"
  if [[ "$GIVEN" != *" since "* ]]; then
    out "actions ok count=$count latest=$latest"
    # An accepted detach that is still running leaves the volume listing its server: the evidence line above is
    # printed first (wipe_check keeps it), then the call refuses, with or without --since.
    jget '.actions | sort_by(-.id) | ([ .[] | select(.command=="attach_volume" or .command=="detach_volume") ] | first) | if . != null and .status=="running" then "yes" else "no" end' || refuse wipe_actions_unreadable reason=shape
    [[ "$JV" == yes ]] && refuse wipe_detach_in_flight
    return 0
  fi
  jget '.actions | sort_by(-.id) as $a
    | if any($a[]; .status=="running") then "in_flight"
      else ([ $a[] | select(.command=="attach_volume" or .command=="detach_volume") ] | first) as $n
        | if $n == null then "no_detach"
          elif $n.command == "attach_volume" then "attach_after"
          elif any($a[]; .command=="attach_volume" and ((.started|type) != "string" or (.started|fromdateiso8601) >= $since)) then "attach_after"
          elif $n.status != "success" then "status_not_success"
          elif ($n.started|type) != "string" then error("shape")
          elif ($n.started|fromdateiso8601) < $since then "started_before_origin"
          else "ok" end
        end' --argjson since "$SINCE" || refuse wipe_actions_unreadable reason=shape
  verdict="$JV"
  case "$verdict" in
    ok) gho detach_evidence ok; out "actions ok count=$count latest=$latest evidence=detach_success" ;;
    in_flight) refuse wipe_detach_in_flight ;;
    no_detach|attach_after|status_not_success|started_before_origin) refuse wipe_detach_not_evidenced "reason=$verdict" ;;
    *) refuse wipe_actions_unreadable reason=shape ;;
  esac
}

do_detach() {
  local aid polls=0 status=running
  only_opts "volume"
  need_volume_id
  read_token rw
  record_verify w7 "$VID"
  hz_write POST "/volumes/${VID}/actions/detach"
  case "$HZ_CODE" in
    201) : ;;
    4[0-9][0-9]) refuse wipe_detach_rejected "code=$HZ_CODE" ;;
    *) refuse wipe_detach_not_confirmed "reason=post_unconfirmed code=$HZ_CODE" ;;
  esac
  jget '.action | must(type=="object" and (.id|uint)) | .id' || refuse wipe_detach_not_confirmed reason=no_action_id
  aid="$JV"; is_uint "$aid" || refuse wipe_detach_not_confirmed reason=no_action_id
  # Poll the SAME action; there is exactly one POST statement in this script and it is above.
  while (( polls < WIPE_POLL_MAX_ATTEMPTS )); do
    polls=$((polls + 1))
    hz_write GET "/actions/${aid}"
    [[ "$HZ_CODE" == 200 ]] || refuse wipe_detach_not_confirmed "reason=poll_unreadable code=$HZ_CODE"
    jget '.action | must(type=="object" and (.status|type=="string")) | .status' || refuse wipe_detach_not_confirmed reason=poll_shape
    status="$JV"
    [[ -n "$status" ]] || refuse wipe_detach_not_confirmed reason=poll_shape
    case "$status" in
      running) if (( polls < WIPE_POLL_MAX_ATTEMPTS )); then sleep "$WIPE_POLL_INTERVAL_SECONDS"; fi ;;
      success) break ;;
      *) refuse wipe_detach_not_confirmed reason=action_not_success ;;
    esac
  done
  [[ "$status" == success ]] || refuse wipe_detach_not_confirmed "reason=poll_exhausted polls=$polls"
  hz_write GET "/volumes/${VID}"
  [[ "$HZ_CODE" == 200 ]] || refuse wipe_detach_not_confirmed "reason=confirm_unreadable code=$HZ_CODE"
  jget '.volume | must(type=="object" and .id==$v and .server==null) | "ok"' --argjson v "$VID" || refuse wipe_detach_not_confirmed reason=still_attached
  [[ "$JV" == ok ]] || refuse wipe_detach_not_confirmed reason=still_attached
  gho detach_action "$aid"
  gho phase detached
  out "detach ok action=$aid polls=$polls volume_server=none"
}

do_delete() {
  only_opts "volume"
  need_volume_id
  read_token rw
  record_verify w10b "$VID"
  hz_write DELETE "/volumes/${VID}"
  case "$HZ_CODE" in
    204) : ;;
    404) refuse wipe_delete_not_found ;;
    4[0-9][0-9]) refuse wipe_delete_rejected "code=$HZ_CODE" ;;
    *) refuse wipe_delete_unconfirmed "code=$HZ_CODE" ;;
  esac
  gho phase delete_sent
  out "delete ok http=204"
}

do_readback() {
  local srv luks_cls
  only_opts "volume"
  need_volume_id
  read_token ro
  hz_get "/volumes/${VID}"
  case "$HZ_CODE" in
    404) jget '.error | must(type=="object" and .code=="not_found") | .code' || refuse wipe_readback_unreadable reason=not_found_shape
         [[ "$JV" == not_found ]] || refuse wipe_readback_unreadable reason=not_found_shape ;;
    200) refuse wipe_readback_still_exists ;;
    *)   refuse wipe_readback_unreadable "code=$HZ_CODE" ;;
  esac
  hz_get "/volumes?name=${WIPE_PLAINTEXT_NAME}"
  [[ "$HZ_CODE" == 200 ]] || refuse wipe_readback_unreadable "code=$HZ_CODE"
  jget '.volumes | must(type=="array") | length' || refuse wipe_readback_unreadable reason=shape
  [[ "$JV" =~ ^[0-9]{1,6}$ ]] || refuse wipe_readback_unreadable reason=shape
  [[ "$JV" == 0 ]] || refuse wipe_readback_name_still_listed "count=$JV"
  # The presence proof: this token can see the server and the LUKS volume, so the 404 above is an answer.
  read_server
  srv="$SRV_ID"
  read_volume_list "$WIPE_LUKS_NAME" wipe_readback_unreadable
  [[ "$V_N" == 1 ]] || refuse wipe_readback_luks_missing "count=$V_N"
  classify_server "$V_SERVER"
  luks_cls="$CLS"
  [[ "$luks_cls" == attached && "$V_SERVER" == "$srv" ]] || refuse wipe_readback_luks_detached
  gho volume_state absent
  gho luks_state attached
  gho phase deleted
  out "readback ok volume_state=absent plaintext_volumes=0 luks_state=attached servers=1"
}

do_record_check() {
  only_opts "epoch volume"
  case "$EPOCH_NAME" in w7|w10b) : ;; *) usage_fail epoch_name ;; esac
  if [[ "$GIVEN" == *" volume "* ]]; then
    need_volume_id
    record_verify "$EPOCH_NAME" "$VID"
  else
    record_verify "$EPOCH_NAME" ""
  fi
  gho record_age_s "$REC_AGE"
  out "record_check ok epoch=$EPOCH_NAME age_s=$REC_AGE"
}

do_stamp() {
  only_opts "epoch"
  [[ "$EPOCH_NAME" == w7 ]] || usage_fail epoch_name
  rec_load
  now_epoch
  if (( NOW - 10#$R_w4_epoch > WIPE_W4_OUTER_BOUND_SECONDS )); then refuse wipe_assertion_stale reason=w4_expired; fi
  R_w7_epoch="$NOW"
  R_w10b_epoch=""
  rec_save
  out "stamp ok epoch=w7"
}

VERB="${1-}"
if [[ $# -gt 0 ]]; then shift; fi
parse_args "$@"
case "$VERB" in
  state)        do_state ;;
  identity)     do_identity ;;
  actions)      do_actions ;;
  detach)       do_detach ;;
  delete)       do_delete ;;
  readback)     do_readback ;;
  record_check) do_record_check ;;
  stamp)        do_stamp ;;
  *) usage_fail unknown_verb ;;
esac
exit 0
