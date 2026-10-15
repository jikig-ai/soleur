#!/usr/bin/env bash
#
# git-data-wipe.sh — the Hetzner helper of the plaintext-volume retirement (#10138 / #6897), driven
# end to end against a PATH-shim `curl` state machine. Plan Phase 2.4; Guard Contract Guards 2, 5, 8.
#
# Property: the helper detaches and deletes ONLY the volume the API names `soleur-git-data-store`,
# equal to the typed id, attached to the one `soleur-git-data` server (or detached), distinct from the
# LUKS volume; it never issues a second detach, never sends a request without a fresh in-bound verdict
# record, never reads a token from anywhere but its stdin line (no fall-back from the read-only name to
# the write name), and never puts a token on any argv or in any output.
#
# The shim is a STATE MACHINE (attached -> detaching -> detached -> deleted/404), not a script of canned
# answers: a reordered or repeated call reads the world it would really read. Every id and token below
# is synthesized (cq-test-fixtures-synthesized-only); nothing here reaches a network, Doppler or the
# repository's real volumes. The shapes the shim answers with were pinned from a live read-only call on
# 2026-10-14 (header of git-data-wipe.sh); the detach/delete shapes are pinned from the retired job.
#
# Harness conventions: scenario functions return 0 when the helper behaves as required, so the same
# scenario runs against a MUTANT copy (mutate() sed-edits a pristine copy, asserts the edit landed on
# the expected diff-line count, and the scenario must go RED). Coverage rows are derived from the
# helper's own text: every wipe_* verdict word it can print must have been printed by a row here.
#
# Seam of the SUITE: GDW_HELPER (the script under test).
# Run: bash apps/web-platform/infra/git-data-wipe.test.sh
# Presence under apps/web-platform/infra/ IS registration (run-registered-suites.sh derives it).

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
HELPER_PRISTINE="$DIR/git-data-wipe.sh"
HELPER="${GDW_HELPER:-$HELPER_PRISTINE}"
BASH_BIN="$(command -v bash)"

passes=0; fails=0; MUTANTS_RUN=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES+=("$1"); fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# Instrument self-test (ADR-193).
_st="$( (pass x >/dev/null; fail y >/dev/null; printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}") )"
if [ "$_st" != "1 1 1" ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() self-test read "%s", expected "1 1 1"\n' "$_st" >&2; exit 1
fi

for f in "$HELPER" "$ROOT/scripts/lib/bearer-curl.sh"; do
  [ -f "$f" ] || { printf 'FAIL SETUP: %s not found\n' "$f" >&2; exit 1; }
done
command -v jq >/dev/null 2>&1 || { printf 'FAIL SETUP: jq unavailable\n' >&2; exit 1; }

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (the fixture-dir-operand-assert suite
# pins every tracked copy byte-identical). Executed as a statement before writes under a root.
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

T="$(mktemp -d "${TMPDIR}/gdw-helper.XXXXXX")" || { printf 'FAIL SETUP: mktemp\n' >&2; exit 1; }
_REACHED_VERDICT=""; _rc=0
trap '_rc=$?; rm -rf "$T"; if [ "$_rc" -eq 0 ] && [ -z "$_REACHED_VERDICT" ]; then printf "FAIL: suite exited 0 before its verdict\n" >&2; exit 1; fi' EXIT
assert_fixture_dir "$T"
BIN="$T/bin"
mkdir -p "$BIN" "$T/w" "$T/mut" "$T/seen" || { printf 'FAIL SETUP: mkdir\n' >&2; exit 1; }
REALPATH_DIRS="$(dirname "$(command -v jq)"):/usr/bin:/bin"

# Synthesized tokens (the shim classifies the bearer value it reads on its --config stdin).
RO_TOK="synthro$(od -An -N10 -tx1 /dev/urandom | tr -d ' \n')"
RW_TOK="synthrw$(od -An -N10 -tx1 /dev/urandom | tr -d ' \n')"
OTHER_TOK="synthxx$(od -An -N10 -tx1 /dev/urandom | tr -d ' \n')"

printf '\n=== git-data-wipe.sh helper (plan Phase 2) ===\n\n'

# --- the shim `curl` -----------------------------------------------------------------------------------
cat > "$BIN/curl" <<'SHIM'
#!/usr/bin/env bash
W="${GDW_WORLD:?}"
n=$(( $(cat "$W/n" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$W/n"
mkdir -p "$W/calls"
printf '%s\n' "$@" > "$W/calls/$n.argv"
cat > "$W/calls/$n.stdin"
METHOD=GET; OUT=""; URL=""; FMT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X) METHOD="$2"; shift 2 ;;
    -o) OUT="$2"; shift 2 ;;
    -w) FMT="$2"; shift 2 ;;
    --max-time|--max-filesize|--noproxy|--config) shift 2 ;;
    https://*) URL="$1"; shift ;;
    *) shift ;;
  esac
done
tok="$(sed -nE 's/^header = "Authorization: Bearer (.*)"$/\1/p' "$W/calls/$n.stdin")"
if [ -z "$tok" ]; then cls=NONE
elif [ "$tok" = "$(cat "$W/ro_token")" ]; then cls=RO
elif [ "$tok" = "$(cat "$W/rw_token")" ]; then cls=RW
else cls=OTHER; fi
BASE='https://api.hetzner.cloud/v1'
case "$URL" in "$BASE"*) PQ="${URL#"$BASE"}" ;; *) PQ="BADHOST:$URL" ;; esac
printf '%s %s %s %s\n' "$n" "$METHOD" "$PQ" "$cls" >> "$W/calls.log"
set -a; . "$W/state.env"; set +a

respond() { # <code> <body>
  printf '%s' "$2" > "$OUT"
  [ -n "$FMT" ] && printf '%s' "$1"
  exit 0
}
vol_json() { # <id> <name> <server> <prot> <app> <loc>
  local prot
  case "$4" in
    missing) prot='' ;;
    string)  prot='"protection":{"delete":"false"},' ;;
    *)       prot="\"protection\":{\"delete\":$4}," ;;
  esac
  if [ "${EXTRA:-0}" = 1 ]; then
    printf '{"zz_extra":{"a":[1,2]},"status":"available",%s"server":%s,"name":"%s","location":{"name":"%s","city":"Helsinki"},"labels":{"other":"x","app":"%s"},"id":%s,"created":"2026-10-14T14:33:56+00:00","size":10}' "$prot" "$3" "$2" "$6" "$5" "$1"
  else
    printf '{"id":%s,"name":"%s","server":%s,%s"labels":{"app":"%s"},"location":{"name":"%s"},"created":"2026-10-14T14:33:56+00:00","size":10,"status":"available"}' "$1" "$2" "$3" "$prot" "$5" "$6"
  fi
}
srv_json() { printf '{"id":%s,"name":"soleur-git-data","created":"%s","status":"running","volumes":[%s,%s]}' "$SRV_ID" "$SRV_CREATED" "$PT_ID" "$LUKS_ID"; }
NOTFOUND='{"error":{"code":"not_found","message":"x","details":null}}'

# faults first (TAB-delimited: METHOD, REGEX on the path+query, CODE, BODY or -)
while IFS=$'\t' read -r fm fre fcode fbody; do
  [ -n "$fm" ] || continue
  if [ "$fm" = "$METHOD" ] && [[ "$PQ" =~ $fre ]]; then
    [ "$fbody" = "-" ] && fbody=""
    if [ "$fcode" = 000 ]; then printf '%s' "" > "$OUT"; [ -n "$FMT" ] && printf '000'; exit 28; fi
    respond "$fcode" "$fbody"
  fi
done < "$W/faults"

list() { # <items...>
  local IFS=,; printf '{"volumes":[%s],"meta":{"pagination":{"page":1,"per_page":25,"total_entries":0}}}' "$*"
}
case "$METHOD $PQ" in
  "GET /servers?name=soleur-git-data")
    items=""; i=0
    while [ "$i" -lt "${SRV_N:-1}" ]; do items="${items:+$items,}$(srv_json)"; i=$((i + 1)); done
    respond 200 "{\"servers\":[$items],\"meta\":{}}" ;;
  "GET /servers/$SRV_ID") respond 200 "{\"server\":$(srv_json)}" ;;
  "GET /volumes?name=soleur-git-data-store")
    if [ "$PT_SERVER" = gone ]; then respond 200 "$(list)"; fi
    one="$(vol_json "$PT_ID" soleur-git-data-store "$([ "$PT_SERVER" = null ] && echo null || echo "$PT_SERVER")" "$PT_PROT" "$PT_APP" "$PT_LOC")"
    if [ "${PT_DUP:-0}" = 1 ]; then respond 200 "$(list "$one" "$(vol_json 900000099 soleur-git-data-store null false "$PT_APP" "$PT_LOC")")"; fi
    respond 200 "$(list "$one")" ;;
  "GET /volumes?name=soleur-git-data-luks-store")
    one="$(vol_json "$LUKS_ID" soleur-git-data-luks-store "$([ "$LUKS_SERVER" = null ] && echo null || echo "$LUKS_SERVER")" false soleur-web-platform "$LUKS_LOC")"
    case "${LUKS_N:-1}" in
      0) respond 200 "$(list)" ;;
      2) respond 200 "$(list "$one" "$one")" ;;
      *) respond 200 "$(list "$one")" ;;
    esac ;;
  "GET /volumes/$PT_ID")
    [ "$PT_SERVER" = gone ] && respond 404 "$NOTFOUND"
    respond 200 "{\"volume\":$(vol_json "$PT_ID" soleur-git-data-store "$([ "$PT_SERVER" = null ] && echo null || echo "$PT_SERVER")" "$PT_PROT" "$PT_APP" "$PT_LOC")}" ;;
  "GET /volumes/$LUKS_ID")
    respond 200 "{\"volume\":$(vol_json "$LUKS_ID" soleur-git-data-luks-store "$LUKS_SERVER" false soleur-web-platform "$LUKS_LOC")}" ;;
  "GET /volumes/$PT_ID/actions?sort=id:desc&per_page=50")
    if [ -f "$W/actions.json" ]; then respond 200 "$(cat "$W/actions.json")"; fi
    respond 200 '{"actions":[],"meta":{"pagination":{"page":1,"per_page":50,"total_entries":0}}}' ;;
  "POST /volumes/$PT_ID/actions/detach")
    if [ "$PT_SERVER" = gone ]; then respond 404 "$NOTFOUND"; fi
    if [ "$PT_SERVER" = null ]; then respond 422 '{"error":{"code":"volume_not_attached","message":"x"}}'; fi
    printf 'ACT_STATE=running\nPOLLS_LEFT=%s\n' "${DETACH_POLLS:-2}" >> "$W/state.env"
    respond 201 "{\"action\":{\"id\":$AID,\"command\":\"detach_volume\",\"status\":\"running\",\"progress\":0,\"started\":\"2026-10-14T15:00:00Z\",\"finished\":null}}" ;;
  "GET /actions/$AID")
    if [ "${ACT_STATE:-idle}" != running ]; then respond 404 "$NOTFOUND"; fi
    if [ "${POLLS_LEFT:-0}" -gt 0 ]; then
      printf 'POLLS_LEFT=%s\n' "$((POLLS_LEFT - 1))" >> "$W/state.env"
      respond 200 "{\"action\":{\"id\":$AID,\"command\":\"detach_volume\",\"status\":\"running\",\"error\":null}}"
    fi
    case "${ACT_END:-success}" in
      never) respond 200 "{\"action\":{\"id\":$AID,\"command\":\"detach_volume\",\"status\":\"running\",\"error\":null}}" ;;
      error) printf 'ACT_STATE=done\n' >> "$W/state.env"
             respond 200 "{\"action\":{\"id\":$AID,\"command\":\"detach_volume\",\"status\":\"error\",\"error\":{\"code\":\"x\"}}}" ;;
      *)     printf 'ACT_STATE=done\nPT_SERVER=null\n' >> "$W/state.env"
             respond 200 "{\"action\":{\"id\":$AID,\"command\":\"detach_volume\",\"status\":\"success\",\"error\":null}}" ;;
    esac ;;
  "DELETE /volumes/$PT_ID")
    [ "$PT_SERVER" = gone ] && respond 404 "$NOTFOUND"
    if [ "$PT_SERVER" != null ]; then respond 423 '{"error":{"code":"locked","message":"x"}}'; fi
    printf 'PT_SERVER=gone\n' >> "$W/state.env"
    respond 204 "" ;;
esac
printf '%s %s UNEXPECTED\n' "$METHOD" "$PQ" >> "$W/unexpected.log"
respond 599 '{"error":{"code":"shim_unexpected"}}'
SHIM
chmod +x "$BIN/curl"

cat > "$BIN/date" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = "+%s" ] && [ -n "${GDW_WORLD:-}" ]; then cat "$GDW_WORLD/clock"; exit 0; fi
exec /usr/bin/date "$@"
SHIM
cat > "$BIN/sleep" <<'SHIM'
#!/usr/bin/env bash
printf 'sleep %s\n' "$*" >> "${GDW_WORLD:?}/sleeps.log"
# Opt-in simulated cost of one poll cycle (the sleep plus the read): a world that carries a sleep_adv file moves its clock by that many seconds per sleep.
if [ -f "$GDW_WORLD/sleep_adv" ]; then printf '%s\n' "$(( $(cat "$GDW_WORLD/clock") + $(cat "$GDW_WORLD/sleep_adv") ))" > "$GDW_WORLD/clock"; fi
SHIM
chmod +x "$BIN/date" "$BIN/sleep"

A0="$(date -u -d '2026-10-14T15:00:00Z' +%s)"   # the shim's detach action start
CLOCK0=$((A0 + 2000))
SRV=800000001; PT=900000001; LUKS=900000002

# --- world and runner ------------------------------------------------------------------------------------
CUR=""; WN=0; RC=0
reset_world() { # [KEY=VALUE ...] state overrides
  WN=$((WN + 1)); CUR="$T/w/$WN"
  assert_fixture_dir "$CUR"
  mkdir -p "$CUR/calls" "$CUR/rt" "$CUR/home"
  chmod 700 "$CUR/rt"
  : > "$CUR/calls.log"; : > "$CUR/faults"; : > "$CUR/sleeps.log"; : > "$CUR/gho"
  printf '%s' "$RO_TOK" > "$CUR/ro_token"; printf '%s' "$RW_TOK" > "$CUR/rw_token"
  printf '%s\n' "$CLOCK0" > "$CUR/clock"
  {
    printf 'SRV_ID=%s\nSRV_CREATED=2026-10-14T14:33:56+00:00\nSRV_N=1\n' "$SRV"
    printf 'PT_ID=%s\nLUKS_ID=%s\nPT_SERVER=%s\nLUKS_SERVER=%s\n' "$PT" "$LUKS" "$SRV" "$SRV"
    printf 'PT_PROT=false\nPT_APP=soleur-web-platform\nPT_LOC=hel1\nLUKS_LOC=hel1\nLUKS_N=1\nPT_DUP=0\nEXTRA=0\n'
    printf 'ACT_STATE=idle\nPOLLS_LEFT=0\nDETACH_POLLS=2\nACT_END=success\nAID=777000111\n'
    local kv; for kv in "$@"; do printf '%s\n' "$kv"; done
  } > "$CUR/state.env"
}
fault() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$CUR/faults"; }
set_state() { printf '%s\n' "$@" >> "$CUR/state.env"; }

EXTRA_ENV=()
run_helper() { # <stdin text | __CLOSED__> <verb> [args...]
  local stdin="$1"; shift
  RC=0
  if [ "$stdin" = "__CLOSED__" ]; then
    env -i PATH="$BIN:$REALPATH_DIRS" HOME="$CUR/home" RUNNER_TEMP="$CUR/rt" GITHUB_WORKSPACE="$ROOT" GITHUB_OUTPUT="$CUR/gho" GDW_WORLD="$CUR" LC_ALL=C \
      ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"} "$BASH_BIN" "$HELPER" "$@" <&- > "$CUR/stdout" 2> "$CUR/stderr" || RC=$?
  else
    env -i PATH="$BIN:$REALPATH_DIRS" HOME="$CUR/home" RUNNER_TEMP="$CUR/rt" GITHUB_WORKSPACE="$ROOT" GITHUB_OUTPUT="$CUR/gho" GDW_WORLD="$CUR" LC_ALL=C \
      ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"} "$BASH_BIN" "$HELPER" "$@" <<<"$stdin" > "$CUR/stdout" 2> "$CUR/stderr" || RC=$?
  fi
  grep -ohE 'verdict=wipe_[a-z0-9_]+' "$CUR/stdout" "$CUR/stderr" >> "$T/seen/words" 2>/dev/null || true
  return 0
}

# --- assertions over the last run ---------------------------------------------------------------------------
ncalls() { wc -l < "$CUR/calls.log" | tr -d ' '; }
nmut() { grep -cE ' (POST|DELETE) ' "$CUR/calls.log" || true; }
npost() { grep -cE ' POST ' "$CUR/calls.log" || true; }
ndelete() { grep -cE ' DELETE ' "$CUR/calls.log" || true; }
nactions_get() { grep -cE ' GET /actions/' "$CUR/calls.log" || true; }
classes() { awk '{print $4}' "$CUR/calls.log" | sort -u | tr '\n' ' '; }
unexpected() { [ ! -s "$CUR/unexpected.log" ]; }
verdict_is() { # <word>: on stdout and in GITHUB_OUTPUT
  grep -qE -- "^\[git-data-wipe\] verdict=$1( |\$)" "$CUR/stdout" && grep -qxF -- "verdict=$1" "$CUR/gho"
}
verdict_line_has() { grep -qF -- "verdict=$1 $2" "$CUR/stdout"; }
gho_has() { grep -qxF -- "$1" "$CUR/gho"; }
out_has() { grep -qF -- "$1" "$CUR/stdout"; }
refused() { # <word>: rc 5, the verdict, no mutating call, nothing unexpected
  [ "$RC" = 5 ] && verdict_is "$1" && [ "$(nmut)" = 0 ] && unexpected
}
ok_run() { [ "$RC" = 0 ] && unexpected; }
chk() { # <label> <command...>
  local label="$1"; shift
  if "$@"; then pass "$label"; else fail "$label" "rc=$RC calls=$(ncalls) stdout=$(head -c 300 "$CUR/stdout" | tr '\n' '|') stderr=$(head -c 200 "$CUR/stderr" | tr '\n' '|')"; fi
}

# --- verdict record fixtures ------------------------------------------------------------------------------------
mk_record() { # <w4> <w7> <w10b> [plaintext id]  (mode 0600, the helper's own format)
  ( umask 077
    printf 'server_id=%s\nserver_created=2026-10-14T14:33:56+00:00\nplaintext_id=%s\nluks_id=%s\nw4_epoch=%s\nw7_epoch=%s\nw10b_epoch=%s\n' \
      "$SRV" "${4:-$PT}" "$LUKS" "$1" "$2" "$3" > "$CUR/rt/git-data-wipe-record" )
}
rec_has() { grep -qxF -- "$1" "$CUR/rt/git-data-wipe-record"; }

# =====================================================================================================
# A. static rows over the helper's own text
# =====================================================================================================
echo "-- A. static --"
SRC_STM="$(sed -e ':a' -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta' "$HELPER_PRISTINE")"
SRC_NOCOMMENT="$(grep -vE '^[[:space:]]*#' "$HELPER_PRISTINE")"
n_bc="$(grep -cE '(^|[^_A-Za-z])bc_curl [A-Za-z]' <<<"$SRC_STM" || true)"
[ "$n_bc" = 2 ] && pass "A1 exactly two bearer-curl call statements (one read-only token name, one write token name): $n_bc" || fail "A1 bearer-curl call statement count is $n_bc, expected 2"
grep -E '(^|[^_A-Za-z])bc_curl ' <<<"$SRC_STM" > "$T/bc.lines"
bad=0; while IFS= read -r l; do
  case "$l" in *'/dev/null'*|*'2>&'*|*'&>'*) bad=1 ;; esac
done < "$T/bc.lines"
[ "$bad" = 0 ] && pass "A2 no bearer-curl statement discards or redirects stderr (the refusal marker stays visible)" || fail "A2 a bearer-curl statement redirects stderr"
[ "$(grep -cF "Authorization:Bearer :HCLOUD_TOKEN_READONLY'" "$T/bc.lines" || true)" = 1 ] && [ "$(grep -cF "Authorization:Bearer :HCLOUD_TOKEN'" "$T/bc.lines" || true)" = 1 ] \
  && pass "A3 the two statements name exactly HCLOUD_TOKEN_READONLY (reads) and HCLOUD_TOKEN (writes), by NAME" || fail "A3 token names in the two statements are not exactly the read-only name and the write name"
grep -qE -- '(-H|--header)[ =]' "$T/bc.lines" && fail "A4 a bearer-curl statement carries a header flag" || pass "A4 no -H / --header on a bearer-curl statement (the credential is a header spec only)"
fb=0
grep -qE 'HCLOUD_TOKEN_READONLY:-|HCLOUD_TOKEN:-|\$\{HCLOUD_TOKEN-|\$\{HCLOUD_TOKEN_READONLY-|HCLOUD_TOKEN_READONLY:=|HCLOUD_TOKEN:=' <<<"$SRC_NOCOMMENT" && fb=1
[ "$fb" = 0 ] && pass "A5 no default/fall-back expansion of either token name anywhere in the script" || fail "A5 a token name has a default or fall-back expansion"
src_first="$(grep -nE '^[[:space:]]*(source|\.)[[:space:]].*scripts/lib/bearer-curl\.sh' "$HELPER_PRISTINE" | head -1 | cut -d: -f1)"
use_first="$(grep -nE '(^|[^_A-Za-z])bc_(curl|ok_var|refuse)[ "$]' "$HELPER_PRISTINE" | grep -vE '^[0-9]+:[[:space:]]*#' | head -1 | cut -d: -f1)"
[ -n "$src_first" ] && [ -n "$use_first" ] && [ "$src_first" -lt "$use_first" ] && pass "A6 the library is sourced on a line of its own that opens with 'source' (the S4 population form) before its first use" || fail "A6 source line ($src_first) not before first library use ($use_first)"
grep -qE '^set -[a-z]*e|^set -e|set -o errexit' "$HELPER_PRISTINE" && fail "A7 the helper sets errexit (every status is handled explicitly)" || pass "A7 no errexit (statuses are handled explicitly; a silent abort cannot read as a verdict)"
grep -qiE 'erased|wiped|secure|no cop|snapshot|erasure|art\. ?17' "$HELPER_PRISTINE" && fail "A8 the script text carries a word the CLO ruling forbids" || pass "A8 no forbidden over-claiming word in the helper text (erased/wiped/secure/no copies/snapshot/erasure)"
[ "$(grep -cE '^(readonly WIPE_W7_BOUND_SECONDS=120|readonly WIPE_W10B_BOUND_SECONDS=60|readonly WIPE_POLL_INTERVAL_SECONDS=2|readonly WIPE_POLL_MAX_ATTEMPTS=90|readonly WIPE_POLL_WALL_CAP_SECONDS=240|readonly WIPE_W4_OUTER_BOUND_SECONDS=900)$' "$HELPER_PRISTINE" || true)" = 6 ] \
  && pass "A9 the time and poll constants are pinned literals, assigned unconditionally (W7 120 s, W10b 60 s, poll 2 s x 90 capped at 240 s wall clock, W4 outer 900 s)" || fail "A9 a pinned constant moved"
python3 "$ROOT/scripts/lint-shell-trace-credential-refusal.py" "$HELPER_PRISTINE" > "$T/lint.out" 2>&1; lrc=$?
[ "$lrc" = 0 ] && pass "A10 scripts/lint-shell-trace-credential-refusal.py is clean on the helper (Rules A/B/C/D/E, in no baseline)" || fail "A10 the xtrace-refusal lint fails on the helper" "$(head -c 300 "$T/lint.out")"
first_cmd="$(grep -vE '^[[:space:]]*(#|$)' "$HELPER_PRISTINE" | sed -n '1p')"
[[ "$first_cmd" == 'set -uo pipefail' ]] && [[ "$(grep -vE '^[[:space:]]*(#|$)' "$HELPER_PRISTINE" | sed -n '2p')" == 'case "$-" in' ]] \
  && pass "A12 the first executable statements are 'set -uo pipefail' then the xtrace case" || fail "A12 prologue order moved" "$first_cmd"
grep -nE 'rm -rf' "$HELPER_PRISTINE" > "$T/rmrf.out" || true
[ ! -s "$T/rmrf.out" ] && pass "A13 the helper has no rm -rf" || fail "A13 rm -rf present" "$(head -2 "$T/rmrf.out")"
PHASE_WORDS="$(sed -n 's/^  printf .%s\\n. detach_attempted detached delete_attempted delete_sent deleted$/detach_attempted detached delete_attempted delete_sent deleted/p' "$HELPER_PRISTINE")"
[ -n "$PHASE_WORDS" ] && pass "A14 the phases verb prints the five-word vocabulary" || fail "A14 phases vocabulary line not found"
phase_ok=1
for w in $(grep -oE 'gho phase [a-z_]+' "$HELPER_PRISTINE" | awk '{print $3}' | sort -u); do
  case " $PHASE_WORDS " in *" $w "*) : ;; *) phase_ok=0 ;; esac
done
[ "$phase_ok" = 1 ] && pass "A15 every phase value the helper writes to GITHUB_OUTPUT is in the phases vocabulary" || fail "A15 a phase value is outside the vocabulary"

# =====================================================================================================
# B. entry: phases, xtrace, usage, library, scratch
# =====================================================================================================
echo "-- B. entry --"
reset_world; run_helper "" phases
if [ "$RC" = 0 ] && [ "$(cat "$CUR/stdout")" = "$(printf 'detach_attempted\ndetached\ndelete_attempted\ndelete_sent\ndeleted')" ] && [ "$(ncalls)" = 0 ]; then pass "B1 phases prints exactly the five words in order, exit 0, no request"; else fail "B1 phases output"; fi
out_has "delete_attempted" && pass "B2 the discoverability probe literal delete_attempted is a line of the phases output" || fail "B2 probe literal missing"
reset_world; RC=0; env -i PATH="$BIN:$REALPATH_DIRS" HOME="$CUR/home" RUNNER_TEMP="$CUR/rt" GITHUB_WORKSPACE="$ROOT" GDW_WORLD="$CUR" "$BASH_BIN" -x "$HELPER" state <<<"$RO_TOK" > "$CUR/stdout" 2> "$CUR/stderr" || RC=$?
[ "$RC" = 78 ] && [ "$(ncalls)" = 0 ] && ! grep -qF -- "$RO_TOK" "$CUR/stderr" && pass "B3 bash -x: refuses with 78 before any request, token not in the trace" || fail "B3 xtrace not refused" "rc=$RC"
reset_world; RC=0; env -i PATH="$BIN:$REALPATH_DIRS" HOME="$CUR/home" RUNNER_TEMP="$CUR/rt" GITHUB_WORKSPACE="$ROOT" GDW_WORLD="$CUR" SHELLOPTS=xtrace "$BASH_BIN" "$HELPER" state <<<"$RO_TOK" > "$CUR/stdout" 2> "$CUR/stderr" || RC=$?
[ "$RC" = 78 ] && [ "$(ncalls)" = 0 ] && ! grep -qF -- "$RO_TOK" "$CUR/stderr" && pass "B4 SHELLOPTS=xtrace in the environment: refuses with 78, no request, token not traced" || fail "B4 SHELLOPTS xtrace not refused" "rc=$RC"
printf 'set -x\n' > "$T/bashenv.sh"
reset_world; RC=0; env -i PATH="$BIN:$REALPATH_DIRS" HOME="$CUR/home" RUNNER_TEMP="$CUR/rt" GITHUB_WORKSPACE="$ROOT" GDW_WORLD="$CUR" BASH_ENV="$T/bashenv.sh" "$BASH_BIN" "$HELPER" state <<<"$RO_TOK" > "$CUR/stdout" 2> "$CUR/stderr" || RC=$?
[ "$RC" = 78 ] && [ "$(ncalls)" = 0 ] && ! grep -qF -- "$RO_TOK" "$CUR/stderr" && pass "B5 BASH_ENV carrying set -x: refuses with 78, no request, token not traced" || fail "B5 BASH_ENV xtrace not refused" "rc=$RC"

usage_row() { # <label> <args...>
  local label="$1"; shift
  reset_world; run_helper "$RO_TOK" "$@"
  if [ "$RC" = 2 ] && [ "$(ncalls)" = 0 ] && grep -qF 'verdict=wipe_usage' "$CUR/stderr"; then pass "$label"; else fail "$label" "rc=$RC calls=$(ncalls) $(head -c 160 "$CUR/stderr")"; fi
}
usage_row "B6 no verb: usage, exit 2, no request"
usage_row "B7 unknown verb: usage, exit 2" bogus
usage_row "B8 unknown option: usage, exit 2" state --bogus
usage_row "B9 identity without --expect: usage" identity --volume-id $PT
usage_row "B10 identity --expect with a bad word: usage" identity --expect maybe --volume-id $PT
usage_row "B11 identity without --volume-id: usage" identity --expect attached
usage_row "B12 identity --volume-id with no value: usage" identity --expect attached --volume-id
usage_row "B13 phases with an option: option not allowed" phases --expect attached
usage_row "B14 state with --volume-id: option not allowed" state --volume-id $PT
usage_row "B15 stamp for the w10b epoch: usage (only w7 is stamped by a step)" stamp --epoch w10b
usage_row "B16 record_check with an unknown epoch: usage" record_check --epoch w9
usage_row "B17 identity --record with a bad word: usage" identity --expect attached --volume-id $PT --record maybe
usage_row "B18 detach with --expect: option not allowed" detach --volume-id $PT --expect attached

for bad in abc 12x '' 1234567890123 0 000 -5 ' 12' '1 2'; do
  reset_world; run_helper "$RO_TOK" identity --expect attached --volume-id "$bad"
  if [ "$RC" = 5 ] && [ "$(ncalls)" = 0 ] && gho_has verdict=wipe_volume_id_shape; then pass "B19 volume id '${bad:-<empty>}' refuses wipe_volume_id_shape before any request"; else fail "B19 volume id '${bad:-<empty>}'" "rc=$RC"; fi
done
reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) ""; run_helper "$RW_TOK" detach --volume-id abc
refused wipe_volume_id_shape && [ "$(ncalls)" = 0 ] && pass "B20 detach with a malformed id refuses before any request" || fail "B20 detach shape"

reset_world; RC=0; EMPTYWS="$T/emptyws"; mkdir -p "$EMPTYWS"; EXTRA_ENV=("GITHUB_WORKSPACE=$EMPTYWS"); run_helper "$RO_TOK" state; EXTRA_ENV=()
[ "$RC" = 1 ] && grep -qF 'verdict=wipe_library_missing' "$CUR/stderr" && pass "B21 a checkout without scripts/lib/bearer-curl.sh: wipe_library_missing, exit 1" || fail "B21 library missing" "rc=$RC"
reset_world; EXTRA_ENV=("GITHUB_WORKSPACE="); run_helper "$RO_TOK" state; EXTRA_ENV=()
[ "$RC" = 1 ] && pass "B22 GITHUB_WORKSPACE empty: refuses, exit 1, nothing sourced from an inherited path" || fail "B22 empty workspace" "rc=$RC"
reset_world; EXTRA_ENV=("TMPDIR=$T/no/such/dir"); run_helper "$RO_TOK" state; EXTRA_ENV=()
[ "$RC" = 1 ] && grep -qF 'verdict=wipe_scratch_unavailable' "$CUR/stderr" && pass "B23 no scratch file available: wipe_scratch_unavailable, exit 1" || fail "B23 scratch" "rc=$RC"
sc_phases_bare() { # preflight Check 10's sandbox: env -i, no GITHUB_WORKSPACE, no RUNNER_TEMP, no stdin
  reset_world
  RC=0; env -i PATH="$BIN:$REALPATH_DIRS" HOME="$CUR/home" "$BASH_BIN" "$HELPER" phases <&- > "$CUR/stdout" 2> "$CUR/stderr" || RC=$?
  [ "$RC" = 0 ] && [ "$(cat "$CUR/stdout")" = "$(printf 'detach_attempted\ndetached\ndelete_attempted\ndelete_sent\ndeleted')" ] && [ "$(ncalls)" = 0 ]
}
sc_phases_bare && pass "B24 phases needs no GITHUB_WORKSPACE, RUNNER_TEMP or stdin (env -i PATH only): the five words, rc 0, no request" || fail "B24 phases bare" "rc=$RC $(head -c 160 "$CUR/stderr")"

# =====================================================================================================
# C. credentials: one stdin line, by name, no fall-back
# =====================================================================================================
echo "-- C. credentials --"
reset_world; run_helper "" state
refused wipe_readonly_token_absent && [ "$(ncalls)" = 0 ] && pass "C1 empty stdin: wipe_readonly_token_absent, no request" || fail "C1"
reset_world; run_helper "__CLOSED__" state
refused wipe_readonly_token_absent && [ "$(ncalls)" = 0 ] && pass "C2 closed stdin: wipe_readonly_token_absent, no request" || fail "C2"
reset_world; EXTRA_ENV=("HCLOUD_TOKEN_READONLY=$RO_TOK"); run_helper "" state; EXTRA_ENV=()
refused wipe_readonly_token_absent && [ "$(ncalls)" = 0 ] && pass "C3 HCLOUD_TOKEN_READONLY exported but stdin empty: refuses, never read from the inherited environment" || fail "C3"
reset_world; EXTRA_ENV=("HCLOUD_TOKEN=$RW_TOK"); run_helper "" state; EXTRA_ENV=()
refused wipe_readonly_token_absent && [ "$(ncalls)" = 0 ] && pass "C4 only the WRITE token exported, stdin empty: a read-only verb never falls back to it" || fail "C4"
reset_world; EXTRA_ENV=("HCLOUD_TOKEN=$RW_TOK" "HCLOUD_TOKEN_READONLY=$RO_TOK"); run_helper "" identity --expect attached --volume-id $PT; EXTRA_ENV=()
refused wipe_readonly_token_absent && [ "$(ncalls)" = 0 ] && pass "C5 both names exported, stdin empty: identity refuses with no request" || fail "C5"
reset_world; EXTRA_ENV=("HCLOUD_TOKEN=$OTHER_TOK" "HCLOUD_TOKEN_READONLY=$OTHER_TOK"); run_helper "$RO_TOK" state; EXTRA_ENV=()
ok_run && [ "$(classes)" = "RO " ] && pass "C6 stdin wins over exported values: every request carries the stdin token (class RO), none the exported one" || fail "C6" "classes=$(classes)"
reset_world; run_helper "${RO_TOK}"$'\r' state
ok_run && [ "$(classes)" = "RO " ] && pass "C7 a trailing CR on the line is dropped; the token is sent as given" || fail "C7"
reset_world; run_helper "$RO_TOK"$'\n'"$OTHER_TOK" state
ok_run && [ "$(classes)" = "RO " ] && pass "C8 only the first stdin line is the token; a second line is ignored" || fail "C8"
reset_world; run_helper 'bad token"x' state
if [ "$RC" = 5 ] && verdict_is wipe_readonly_token_unusable && [ "$(ncalls)" = 0 ] && grep -qF 'SOLEUR_CREDENTIAL_REFUSED script=git-data-wipe' "$CUR/stderr" && ! grep -qF 'token"x' "$CUR/stdout" "$CUR/stderr" "$CUR/gho"; then
  pass "C9 an unusable token shape: wipe_readonly_token_unusable, the library's value-free marker names this file, no request, value not echoed"
else fail "C9" "rc=$RC"; fi
reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) ""; EXTRA_ENV=("HCLOUD_TOKEN_READONLY=$RO_TOK"); run_helper "" detach --volume-id $PT; EXTRA_ENV=()
refused wipe_write_token_absent && [ "$(ncalls)" = 0 ] && pass "C10 detach with only the READ-ONLY token exported and stdin empty: wipe_write_token_absent, no request" || fail "C10"
reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) $((CLOCK0 - 5)); EXTRA_ENV=("HCLOUD_TOKEN_READONLY=$RO_TOK" "HCLOUD_TOKEN=$RW_TOK"); run_helper "__CLOSED__" delete --volume-id $PT; EXTRA_ENV=()
refused wipe_write_token_absent && [ "$(ncalls)" = 0 ] && pass "C11 delete with both names exported and stdin closed: refuses, no request" || fail "C11"
reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) ""; run_helper 'bad token' detach --volume-id $PT
refused wipe_write_token_unusable && [ "$(ncalls)" = 0 ] && pass "C12 detach with an unusable write token shape: wipe_write_token_unusable, no request" || fail "C12"

# =====================================================================================================
# D. state
# =====================================================================================================
echo "-- D. state --"
reset_world; run_helper "$RO_TOK" state
ok_run && out_has "state plaintext=attached luks=attached plaintext_volumes=1 luks_volumes=1 servers=1" && gho_has volume_state=attached && gho_has luks_state=attached && [ "$(ncalls)" = 3 ] && [ "$(classes)" = "RO " ] \
  && ! grep -qF -e "$PT" -e "$LUKS" -e "$SRV" "$CUR/stdout" && pass "D1 attached/attached: three reads, read-only token only, outputs set, no id printed by default" || fail "D1"
reset_world; run_helper "$RO_TOK" state --show-ids
ok_run && out_has "server_id=$SRV" && out_has "plaintext_id=$PT" && out_has "luks_id=$LUKS" && pass "D2 --show-ids prints the live pair (digits) for the owner-facing wipe_check" || fail "D2"
reset_world PT_SERVER=null; run_helper "$RO_TOK" state; ok_run && out_has "plaintext=detached" && gho_has volume_state=detached && pass "D3 detached plaintext volume" || fail "D3"
reset_world PT_SERVER=gone; run_helper "$RO_TOK" state; ok_run && out_has "plaintext=absent" && out_has "plaintext_volumes=0" && gho_has volume_state=absent && pass "D4 absent plaintext volume" || fail "D4"
reset_world PT_SERVER=777; run_helper "$RO_TOK" state; ok_run && out_has "plaintext=other_host" && pass "D5 plaintext attached to another server is reported, not hidden" || fail "D5"
reset_world LUKS_N=0; run_helper "$RO_TOK" state; ok_run && out_has "luks=absent" && gho_has luks_state=absent && pass "D6 an absent LUKS volume is reported as absent" || fail "D6"
reset_world LUKS_SERVER=null; run_helper "$RO_TOK" state; ok_run && out_has "luks=detached" && pass "D7 a detached LUKS volume is reported as detached" || fail "D7"
reset_world PT_DUP=1; run_helper "$RO_TOK" state; refused wipe_volume_count && pass "D8 two volumes for the plaintext name refuse wipe_volume_count" || fail "D8"
reset_world LUKS_N=2; run_helper "$RO_TOK" state; refused wipe_luks_count && pass "D9 two volumes for the LUKS name refuse wipe_luks_count" || fail "D9"
reset_world SRV_N=0; run_helper "$RO_TOK" state; refused wipe_server_count && pass "D10 no server refuses wipe_server_count" || fail "D10"
reset_world SRV_N=2; run_helper "$RO_TOK" state; refused wipe_server_count && pass "D11 two servers refuse wipe_server_count" || fail "D11"
reset_world; fault GET '^/servers\?name=' 500 '{"error":{"code":"x"}}'; run_helper "$RO_TOK" state; refused wipe_server_unreadable && verdict_line_has wipe_server_unreadable code=500 && pass "D12 server read 500: wipe_server_unreadable code=500" || fail "D12"
reset_world; fault GET '^/volumes\?name=soleur-git-data-luks-store$' 500 '-'; run_helper "$RO_TOK" state; refused wipe_luks_unreadable && pass "D13 LUKS read 500: wipe_luks_unreadable" || fail "D13"
reset_world; fault GET '^/volumes\?name=soleur-git-data-store$' 404 '-'; run_helper "$RO_TOK" state; refused wipe_volume_unreadable && pass "D14 plaintext read 404: wipe_volume_unreadable" || fail "D14"
reset_world; fault GET '^/servers\?name=' 000 '-'; run_helper "$RO_TOK" state; refused wipe_server_unreadable && verdict_line_has wipe_server_unreadable code=000 && pass "D15 transport failure on the server read: wipe_server_unreadable code=000" || fail "D15"

# =====================================================================================================
# E. identity: R1-R6 and the classification
# =====================================================================================================
echo "-- E. identity --"
reset_world; run_helper "$RO_TOK" identity --expect attached --volume-id $PT --record write
RECMODE="$(stat -c %a "$CUR/rt/git-data-wipe-record" 2>/dev/null || echo none)"
if ok_run && out_has "identity ok expect=attached volume_state=attached" && gho_has volume_state=attached && gho_has luks_state=attached && [ "$(classes)" = "RO " ] \
   && [ "$RECMODE" = 600 ] && rec_has "server_id=$SRV" && rec_has "plaintext_id=$PT" && rec_has "luks_id=$LUKS" && rec_has "w7_epoch=" && rec_has "w10b_epoch=" && rec_has "w4_epoch=$CLOCK0" \
   && ! grep -qF -e "$RO_TOK" -e "$RW_TOK" "$CUR/rt/git-data-wipe-record"; then
  pass "E1 attached + record write: ok, record mode 0600 with the ids and the W4 epoch, no token in it, read-only token only"
else fail "E1" "rc=$RC mode=$RECMODE"; fi
reset_world EXTRA=1; run_helper "$RO_TOK" identity --expect attached --volume-id $PT
ok_run && pass "E2 must-PASS: extra unknown JSON fields and a different key order are accepted" || fail "E2"
reset_world; run_helper "$RO_TOK" identity --expect attached --volume-id 000900000001
ok_run && pass "E3 must-PASS: the typed id with leading zeros (12 digits) equals the live id numerically" || fail "E3"
reset_world; run_helper "$RO_TOK" identity --expect attached --volume-id $PT --show-ids
ok_run && out_has "luks_id=$LUKS" && pass "E4 --show-ids prints the pair" || fail "E4"
reset_world; run_helper "$RO_TOK" identity --expect attached --volume-id $PT
! grep -qF -e "$LUKS" -e "$SRV" "$CUR/stdout" && ok_run && pass "E5 default output prints neither the server id nor the LUKS id" || fail "E5"
reset_world PT_SERVER=null; run_helper "$RO_TOK" identity --expect detached --volume-id $PT --record write
ok_run && gho_has volume_state=detached && ! grep -q '^phase=' "$CUR/gho" && [ -e "$CUR/rt/git-data-wipe-record" ] && pass "E6 detached + record write (the wipe_finish front): ok, record created, NO phase key written (the volume's detached state is this run's input, not an event of it: a refused wipe_finish must not notify VOLUME_DETACHED)" || fail "E6"
reset_world PT_SERVER=null; run_helper "$RO_TOK" identity --expect detached --volume-id $PT
ok_run && ! grep -q '^phase=' "$CUR/gho" && pass "E7 detached without a record write does not emit a phase" || fail "E7"
reset_world; run_helper "$RO_TOK" identity --expect attached --volume-id $PT --record write
ok_run && ! grep -q '^phase=' "$CUR/gho" && pass "E7b identity (attached, record write) writes no phase key either" || fail "E7b"
reset_world PT_SERVER=gone; run_helper "$RO_TOK" identity --expect detached --volume-id $PT --record write
ok_run && gho_has volume_state=absent && out_has "record=none" && [ ! -e "$CUR/rt/git-data-wipe-record" ] && ! grep -qxF phase=detached "$CUR/gho" && [ "$(nmut)" = 0 ] && pass "E8 absent under --expect detached: ok volume_state=absent, NO record written, no phase, no mutating call" || fail "E8"

id_row() { # <label> <word> <expect> <typed> <state overrides...>
  local label="$1" word="$2" expect="$3" typed="$4"; shift 4
  reset_world "$@"; run_helper "$RO_TOK" identity --expect "$expect" --volume-id "$typed"
  if refused "$word"; then pass "$label"; else fail "$label" "rc=$RC calls=$(ncalls) $(head -c 200 "$CUR/stdout" | tr '\n' '|')"; fi
}
id_row "E10 typed id equals the LUKS id: wipe_target_is_luks" wipe_target_is_luks attached $LUKS
id_row "E11 typed id equals the LUKS id with leading zeros: wipe_target_is_luks" wipe_target_is_luks attached 000900000002
id_row "E12 typed id is the LUKS id and the stub also offers a different plaintext id: still wipe_target_is_luks" wipe_target_is_luks detached $LUKS PT_SERVER=null
id_row "E13 typed id differs from the volume named soleur-git-data-store: wipe_volume_id_mismatch" wipe_volume_id_mismatch attached 123456789
id_row "E14 volume attached to ANOTHER server: wipe_not_attached_to_current_host" wipe_not_attached_to_current_host attached $PT PT_SERVER=777
id_row "E15 the LUKS volume attached to another server: wipe_not_attached_to_current_host" wipe_not_attached_to_current_host attached $PT LUKS_SERVER=777
id_row "E16 the LUKS volume detached: wipe_not_attached_to_current_host" wipe_not_attached_to_current_host attached $PT LUKS_SERVER=null
id_row "E17 zero plaintext volumes under --expect attached: wipe_volume_count (never defaults to the typed id)" wipe_volume_count attached $PT PT_SERVER=gone
id_row "E18 two volumes for the plaintext name: wipe_volume_count" wipe_volume_count attached $PT PT_DUP=1
id_row "E19 zero LUKS volumes: wipe_luks_count" wipe_luks_count attached $PT LUKS_N=0
id_row "E20 two LUKS volumes: wipe_luks_count" wipe_luks_count attached $PT LUKS_N=2
id_row "E21 zero servers: wipe_server_count" wipe_server_count attached $PT SRV_N=0
id_row "E22 two servers: wipe_server_count" wipe_server_count attached $PT SRV_N=2
id_row "E23 a detached volume under --expect attached: wipe_volume_already_detached" wipe_volume_already_detached attached $PT PT_SERVER=null
gho_has refusal=volume_already_detached && pass "E24 wipe_volume_already_detached also writes refusal=volume_already_detached to GITHUB_OUTPUT (the notify word's source)" || fail "E24"
id_row "E25 an attached volume under --expect detached: wipe_volume_not_detached" wipe_volume_not_detached detached $PT
id_row "E26 protection.delete true: wipe_delete_protected" wipe_delete_protected attached $PT PT_PROT=true
id_row "E27 protection missing: wipe_protection_unreadable" wipe_protection_unreadable attached $PT PT_PROT=missing
id_row "E28 protection not a boolean: wipe_protection_unreadable" wipe_protection_unreadable attached $PT PT_PROT=string
id_row "E29 label.app differs: wipe_label_mismatch" wipe_label_mismatch attached $PT PT_APP=other-app
id_row "E30 label.app absent: wipe_label_mismatch" wipe_label_mismatch attached $PT PT_APP=
id_row "E31 location differs from the LUKS volume: wipe_label_mismatch" wipe_label_mismatch attached $PT PT_LOC=fsn1
reset_world PT_SERVER=gone; fault GET '^/volumes/'"$PT"'$' 200 '{"volume":{"id":900000001}}'; run_helper "$RO_TOK" identity --expect detached --volume-id $PT
refused wipe_volume_id_mismatch && pass "E32 empty name list but the id still answers 200 (renamed): wipe_volume_id_mismatch" || fail "E32"
reset_world PT_SERVER=gone; fault GET '^/volumes/'"$PT"'$' 404 '<html>not found</html>'; run_helper "$RO_TOK" identity --expect detached --volume-id $PT
refused wipe_volume_unreadable && pass "E33 absent branch: a 404 that is not Hetzner's not_found JSON is not a presence proof" || fail "E33"
reset_world PT_SERVER=gone; fault GET '^/volumes/'"$PT"'$' 500 '-'; run_helper "$RO_TOK" identity --expect detached --volume-id $PT
refused wipe_volume_unreadable && pass "E34 absent branch: a 500 on the id read is unreadable" || fail "E34"

# off-shape / empty / multi-document / error bodies on each of the three reads
shape_row() { # <label> <word> <path-regex> <code> <body>
  reset_world; fault GET "$3" "$4" "$5"; run_helper "$RO_TOK" identity --expect attached --volume-id $PT
  if refused "$2"; then pass "$1"; else fail "$1" "rc=$RC $(head -c 160 "$CUR/stdout" | tr '\n' '|')"; fi
}
SRVRE='^/servers\?name='; LUKSRE='^/volumes\?name=soleur-git-data-luks-store$'; PTRE='^/volumes\?name=soleur-git-data-store$'
shape_row "E40 server read: empty body" wipe_server_unreadable "$SRVRE" 200 '-'
shape_row "E41 server read: HTML" wipe_server_unreadable "$SRVRE" 200 '<html>x</html>'
shape_row "E42 server read: two JSON documents" wipe_server_unreadable "$SRVRE" 200 '{"servers":[]}{"servers":[]}'
shape_row "E43 server read: servers is not an array" wipe_server_unreadable "$SRVRE" 200 '{"servers":{"id":1}}'
shape_row "E44 server read: wrong name" wipe_server_unreadable "$SRVRE" 200 '{"servers":[{"id":1,"name":"other","created":"2026-10-14T14:33:56+00:00"}]}'
shape_row "E45 server read: id is a string" wipe_server_unreadable "$SRVRE" 200 '{"servers":[{"id":"800000001","name":"soleur-git-data","created":"2026-10-14T14:33:56+00:00"}]}'
shape_row "E46 server read: created missing" wipe_server_unreadable "$SRVRE" 200 '{"servers":[{"id":800000001,"name":"soleur-git-data"}]}'
shape_row "E47 server read: created off-shape" wipe_server_unreadable "$SRVRE" 200 '{"servers":[{"id":800000001,"name":"soleur-git-data","created":"yesterday"}]}'
shape_row "E48 server read: 403" wipe_server_unreadable "$SRVRE" 403 '{"error":{"code":"forbidden"}}'
shape_row "E49 LUKS read: empty body" wipe_luks_unreadable "$LUKSRE" 200 '-'
shape_row "E50 LUKS read: JSON null" wipe_luks_unreadable "$LUKSRE" 200 'null'
shape_row "E51 LUKS read: two documents" wipe_luks_unreadable "$LUKSRE" 200 '{"volumes":[]}{"volumes":[]}'
shape_row "E52 LUKS read: id is a float" wipe_luks_unreadable "$LUKSRE" 200 '{"volumes":[{"id":1.5,"name":"soleur-git-data-luks-store","server":800000001,"location":{"name":"hel1"},"labels":{}}]}'
shape_row "E53 LUKS read: server is a string" wipe_luks_unreadable "$LUKSRE" 200 '{"volumes":[{"id":900000002,"name":"soleur-git-data-luks-store","server":"800000001","location":{"name":"hel1"},"labels":{}}]}'
shape_row "E54 LUKS read: location missing" wipe_luks_unreadable "$LUKSRE" 200 '{"volumes":[{"id":900000002,"name":"soleur-git-data-luks-store","server":800000001,"labels":{}}]}'
shape_row "E55 LUKS read: 500" wipe_luks_unreadable "$LUKSRE" 500 '-'
shape_row "E56 plaintext read: empty body" wipe_volume_unreadable "$PTRE" 200 '-'
shape_row "E57 plaintext read: HTML" wipe_volume_unreadable "$PTRE" 200 '<html>x</html>'
shape_row "E58 plaintext read: wrong name in the entry" wipe_volume_unreadable "$PTRE" 200 '{"volumes":[{"id":900000001,"name":"another-volume","server":800000001,"location":{"name":"hel1"},"labels":{"app":"soleur-web-platform"}}]}'
shape_row "E59 plaintext read: id zero" wipe_volume_unreadable "$PTRE" 200 '{"volumes":[{"id":0,"name":"soleur-git-data-store","server":800000001,"location":{"name":"hel1"},"labels":{"app":"soleur-web-platform"}}]}'
shape_row "E60 plaintext read: labels is a list" wipe_volume_unreadable "$PTRE" 200 '{"volumes":[{"id":900000001,"name":"soleur-git-data-store","server":800000001,"location":{"name":"hel1"},"labels":[]}]}'
shape_row "E61 plaintext read: 502" wipe_volume_unreadable "$PTRE" 502 '-'

# --record check (the W10b re-read)
reset_world PT_SERVER=null; run_helper "$RO_TOK" identity --expect detached --volume-id $PT --record check
refused wipe_record_absent && [ "$(ncalls)" = 0 ] && pass "E70 --record check without a record refuses wipe_record_absent before any request (a wipe_finish that skipped its own record goes red here)" || fail "E70"
reset_world PT_SERVER=null; mk_record $((CLOCK0 - 90)) $((CLOCK0 - 80)) ""; run_helper "$RO_TOK" identity --expect detached --volume-id $PT --record check
if ok_run && rec_has "w10b_epoch=$CLOCK0" && rec_has "w7_epoch=$((CLOCK0 - 80))"; then pass "E71 --record check against an unchanged world: ok, the W10b epoch is stamped now, the W7 epoch untouched"; else fail "E71" "rc=$RC"; fi
reset_world PT_SERVER=null LUKS_ID=900000055; mk_record $((CLOCK0 - 90)) $((CLOCK0 - 80)) ""; run_helper "$RO_TOK" identity --expect detached --volume-id $PT --record check
refused wipe_target_changed && verdict_line_has wipe_target_changed reason=luks_volume && pass "E72 the LUKS volume id changed since the record: wipe_target_changed reason=luks_volume" || fail "E72"
reset_world PT_SERVER=null SRV_ID=800000777; mk_record $((CLOCK0 - 90)) $((CLOCK0 - 80)) ""; run_helper "$RO_TOK" identity --expect detached --volume-id $PT --record check
if [ "$RC" = 5 ] && [ "$(nmut)" = 0 ]; then pass "E73 the server id changed since the record: refused before any mutating call"; else fail "E73"; fi
reset_world PT_SERVER=null SRV_CREATED=2026-10-14T16:00:00+00:00; mk_record $((CLOCK0 - 90)) $((CLOCK0 - 80)) ""; run_helper "$RO_TOK" identity --expect detached --volume-id $PT --record check
refused wipe_target_changed && verdict_line_has wipe_target_changed reason=server_created && pass "E74 the server was re-created (created differs): wipe_target_changed reason=server_created" || fail "E74"
reset_world PT_SERVER=null; mk_record $((CLOCK0 - 90)) "" ""; run_helper "$RO_TOK" identity --expect detached --volume-id $PT --record check
refused wipe_assertion_stale && verdict_line_has wipe_assertion_stale reason=w7_unstamped && pass "E75 --record check on a record whose W7 epoch was never stamped: wipe_assertion_stale reason=w7_unstamped" || fail "E75"
reset_world PT_SERVER=gone; mk_record $((CLOCK0 - 90)) $((CLOCK0 - 80)) ""; run_helper "$RO_TOK" identity --expect detached --volume-id $PT --record check
refused wipe_target_changed && verdict_line_has wipe_target_changed reason=absent && pass "E76 the volume vanished between the record and the re-read: wipe_target_changed reason=absent" || fail "E76"
reset_world PT_SERVER=null PT_PROT=true; mk_record $((CLOCK0 - 90)) $((CLOCK0 - 80)) ""; run_helper "$RO_TOK" identity --expect detached --volume-id $PT --record check
refused wipe_delete_protected && pass "E77 protection turned on between the reads: refused at the re-read" || fail "E77"
reset_world PT_SERVER=null PT_APP=other; mk_record $((CLOCK0 - 90)) $((CLOCK0 - 80)) ""; run_helper "$RO_TOK" identity --expect detached --volume-id $PT --record check
refused wipe_label_mismatch && pass "E78 the label changed between the reads: refused at the re-read" || fail "E78"
reset_world; mk_record $((CLOCK0 - 90)) $((CLOCK0 - 80)) ""; run_helper "$RO_TOK" identity --expect detached --volume-id $PT --record check
refused wipe_volume_not_detached && pass "E79 re-attached before the re-read: wipe_volume_not_detached" || fail "E79"

# =====================================================================================================
# F. the verdict record: record_check and stamp
# =====================================================================================================
echo "-- F. record --"
reset_world; run_helper "" record_check --epoch w7
refused wipe_record_absent && [ "$(ncalls)" = 0 ] && pass "F1 no record: wipe_record_absent" || fail "F1"
reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) ""; run_helper "" record_check --epoch w7
ok_run && out_has "record_check ok epoch=w7 age_s=30" && gho_has record_age_s=30 && [ "$(ncalls)" = 0 ] && pass "F2 a fresh W7 stamp passes and makes no request" || fail "F2"
reset_world; mk_record $((CLOCK0 - 400)) $((CLOCK0 - 120)) ""; run_helper "" record_check --epoch w7
ok_run && pass "F3 boundary: a W7 epoch exactly at the 120 s bound passes" || fail "F3"
reset_world; mk_record $((CLOCK0 - 400)) $((CLOCK0 - 121)) ""; run_helper "" record_check --epoch w7
refused wipe_assertion_stale && verdict_line_has wipe_assertion_stale "reason=expired age_s=121 bound_s=120" && pass "F4 boundary: 121 s past the W7 stamp is wipe_assertion_stale" || fail "F4"
reset_world; mk_record $((CLOCK0 - 400)) $((CLOCK0 + 600)) ""; run_helper "" record_check --epoch w7
refused wipe_assertion_stale && verdict_line_has wipe_assertion_stale reason=future && pass "F5 an epoch in the future is stale (a forged or skewed stamp)" || fail "F5"
reset_world; mk_record $((CLOCK0 - 400)) "" ""; run_helper "" record_check --epoch w7
refused wipe_assertion_stale && verdict_line_has wipe_assertion_stale reason=unstamped && pass "F6 W7 never stamped: wipe_assertion_stale reason=unstamped" || fail "F6"
reset_world; mk_record $((CLOCK0 - 400)) $((CLOCK0 - 100)) $((CLOCK0 - 60)); run_helper "" record_check --epoch w10b
ok_run && pass "F7 boundary: a W10b epoch exactly at the 60 s bound passes" || fail "F7"
reset_world; mk_record $((CLOCK0 - 400)) $((CLOCK0 - 100)) $((CLOCK0 - 61)); run_helper "" record_check --epoch w10b
refused wipe_assertion_stale && verdict_line_has wipe_assertion_stale "reason=expired age_s=61 bound_s=60" && pass "F8 boundary: 61 s past the W10b stamp is stale (the W7 bound does not apply to the delete)" || fail "F8"
reset_world; mk_record $((CLOCK0 - 400)) $((CLOCK0 - 100)) ""; run_helper "" record_check --epoch w10b
refused wipe_assertion_stale && pass "F9 the W10b epoch never stamped: stale" || fail "F9"
reset_world; mk_record $((CLOCK0 - 400)) "" $((CLOCK0 - 5)); run_helper "" record_check --epoch w10b
refused wipe_assertion_stale && verdict_line_has wipe_assertion_stale reason=w7_unstamped && pass "F10 a W10b stamp without a W7 stamp is refused (the host look never happened)" || fail "F10"
reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) ""; chmod 644 "$CUR/rt/git-data-wipe-record"; run_helper "" record_check --epoch w7
refused wipe_record_invalid && verdict_line_has wipe_record_invalid reason=mode && pass "F11 a record that is not mode 0600 is invalid" || fail "F11"
reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) ""; mv "$CUR/rt/git-data-wipe-record" "$CUR/real-record"; ln -s "$CUR/real-record" "$CUR/rt/git-data-wipe-record"; run_helper "" record_check --epoch w7
refused wipe_record_invalid && verdict_line_has wipe_record_invalid reason=type && pass "F12 a symlinked record is invalid" || fail "F12"
reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) ""; printf 'extra=1\n' >> "$CUR/rt/git-data-wipe-record"; run_helper "" record_check --epoch w7
refused wipe_record_invalid && verdict_line_has wipe_record_invalid reason=line && pass "F13 an unknown line in the record is invalid" || fail "F13"
reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) ""; printf 'w4_epoch=%s\n' "$CLOCK0" >> "$CUR/rt/git-data-wipe-record"; run_helper "" record_check --epoch w7
refused wipe_record_invalid && verdict_line_has wipe_record_invalid reason=duplicate && pass "F14 a duplicated key is invalid" || fail "F14"
reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) ""; sed -i 's/^luks_id=.*/luks_id=abc/' "$CUR/rt/git-data-wipe-record"; run_helper "" record_check --epoch w7
refused wipe_record_invalid && verdict_line_has wipe_record_invalid reason=value && pass "F15 a non-numeric id in the record is invalid" || fail "F15"
reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) ""; sed -i '/^luks_id=/d' "$CUR/rt/git-data-wipe-record"; run_helper "" record_check --epoch w7
refused wipe_record_invalid && verdict_line_has wipe_record_invalid reason=incomplete && pass "F16 a record missing a required key is invalid" || fail "F16"
reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) ""; run_helper "" record_check --epoch w7 --volume-id 123456789
refused wipe_record_volume_mismatch && pass "F17 the record binds the volume: another typed id is wipe_record_volume_mismatch" || fail "F17"
reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) ""; run_helper "" record_check --epoch w7 --volume-id 000900000001
ok_run && pass "F18 must-PASS: the bound volume with leading zeros passes the binding" || fail "F18"
reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) ""; printf 'garbage\n' > "$CUR/clock"; run_helper "" record_check --epoch w7
[ "$RC" = 5 ] && verdict_is wipe_clock_unreadable && pass "F19 an unreadable clock refuses wipe_clock_unreadable" || fail "F19"
reset_world; mk_record $((CLOCK0 - 10)) "" ""; run_helper "" stamp --epoch w7
if ok_run && rec_has "w7_epoch=$CLOCK0" && rec_has "w10b_epoch=" && [ "$(stat -c %a "$CUR/rt/git-data-wipe-record")" = 600 ]; then pass "F20 stamp --epoch w7 sets the W7 epoch to now, clears any W10b epoch, keeps mode 0600"; else fail "F20" "rc=$RC"; fi
reset_world; run_helper "" stamp --epoch w7
refused wipe_record_absent && pass "F21 stamp without a record refuses (the W4 identity read did not happen)" || fail "F21"
reset_world; mk_record $((CLOCK0 - 901)) "" ""; run_helper "" stamp --epoch w7
refused wipe_assertion_stale && verdict_line_has wipe_assertion_stale reason=w4_expired && pass "F22 stamp more than 900 s after the W4 read is refused (the outer bound)" || fail "F22"
reset_world; mk_record $((CLOCK0 - 900)) "" ""; run_helper "" stamp --epoch w7
ok_run && pass "F23 boundary: stamp exactly 900 s after W4 passes" || fail "F23"
sc_octal_w7() { reset_world; mk_record $((CLOCK0 - 400)) "0$((CLOCK0 - 30))" ""; run_helper "" record_check --epoch w7; ok_run && out_has "record_check ok epoch=w7 age_s=30"; }
sc_octal_w4() { reset_world; mk_record "0$((CLOCK0 - 901))" "" ""; run_helper "" stamp --epoch w7; refused wipe_assertion_stale && verdict_line_has wipe_assertion_stale reason=w4_expired; }
sc_octal_w7 && pass "F24 a leading-zero W7 epoch (decimal, shape-checked) reads as decimal, not octal: age_s=30" || fail "F24" "rc=$RC $(head -c 160 "$CUR/stderr")"
sc_octal_w4 && pass "F25 a leading-zero W4 epoch 901 s old is refused w4_expired (read as octal the arithmetic errors and the bound check silently reads false: fail-open)" || fail "F25" "rc=$RC $(head -c 160 "$CUR/stderr")"
reset_world; EXTRA_ENV=("RUNNER_TEMP=relative/dir"); run_helper "" record_check --epoch w7; EXTRA_ENV=()
[ "$RC" = 2 ] && grep -qF 'is RELATIVE' "$CUR/stderr" && pass "F24 a relative RUNNER_TEMP is refused by the canonical guard before any record operand is used" || fail "F24" "rc=$RC"
reset_world; EXTRA_ENV=("RUNNER_TEMP="); run_helper "" record_check --epoch w7; EXTRA_ENV=()
[ "$RC" = 2 ] && grep -qF 'is EMPTY' "$CUR/stderr" && pass "F25 an empty RUNNER_TEMP is refused by the canonical guard" || fail "F25" "rc=$RC"

# =====================================================================================================
# G. actions
# =====================================================================================================
echo "-- G. actions --"
act_json() { # <command> <status> <started> <id> ... repeated 4-tuples -> JSON
  local items="" c s st id
  while [ $# -ge 4 ]; do c="$1"; s="$2"; st="$3"; id="$4"; shift 4
    local started='null'; [ "$st" != null ] && started="\"$st\""
    items="${items:+$items,}{\"id\":$id,\"command\":\"$c\",\"status\":\"$s\",\"started\":$started,\"finished\":null,\"progress\":100,\"resources\":[{\"id\":900000001,\"type\":\"volume\"}]}"
  done
  printf '{"actions":[%s],"meta":{"pagination":{"page":1,"per_page":50,"total_entries":0}}}' "$items"
}
reset_world; act_json attach_volume success 2026-10-14T14:34:00Z 30 detach_volume success 2026-10-14T14:00:00Z 29 create_volume success 2026-10-14T13:00:00Z 28 > "$CUR/actions.json"
run_helper "$RO_TOK" actions --volume-id $PT
ok_run && out_has "actions ok count=3 latest=attach_volume" && gho_has actions_count=3 && gho_has actions_latest=attach_volume && [ "$(classes)" = "RO " ] && pass "G1 report mode: count and the latest command word (shape verified on the real history before any destructive dispatch)" || fail "G1"
reset_world; run_helper "$RO_TOK" actions --volume-id $PT
ok_run && out_has "actions ok count=0 latest=none" && pass "G2 an empty history reports count=0 latest=none" || fail "G2"
reset_world; act_json resize_volume success 2026-10-14T14:00:00Z 9 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT
ok_run && out_has "latest=resize_volume" && pass "G3 a known command word is reported as itself" || fail "G3"
reset_world; act_json weird_new_command success 2026-10-14T14:00:00Z 9 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT
ok_run && out_has "latest=other" && ! grep -qF weird "$CUR/stdout" && pass "G4 an unknown command word is reported as 'other' (nothing from the API is echoed)" || fail "G4"
reset_world; act_json detach_volume success 2026-10-14T15:00:05Z 31 attach_volume success 2026-10-14T14:34:00Z 30 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT --since "$A0"
ok_run && out_has "evidence=detach_success" && gho_has detach_evidence=ok && pass "G5 finish mode: the newest relevant action is detach_volume success started at/after the origin W9a start" || fail "G5"
reset_world; act_json detach_volume success 2026-10-14T15:00:00Z 31 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT --since "$A0"
ok_run && pass "G6 boundary: started exactly at the origin start passes" || fail "G6"
reset_world; act_json detach_volume success 2026-10-14T14:59:59Z 31 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT --since "$A0"
refused wipe_detach_not_evidenced && verdict_line_has wipe_detach_not_evidenced reason=started_before_origin && pass "G7 boundary: one second before the origin start is not evidence" || fail "G7"
reset_world; act_json attach_volume success 2026-10-14T15:10:00Z 32 detach_volume success 2026-10-14T15:00:05Z 31 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT --since "$A0"
refused wipe_detach_not_evidenced && verdict_line_has wipe_detach_not_evidenced reason=attach_after && pass "G8 a re-attach after the detach: not evidence of a detached volume" || fail "G8"
reset_world; act_json detach_volume error 2026-10-14T15:00:05Z 31 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT --since "$A0"
refused wipe_detach_not_evidenced && verdict_line_has wipe_detach_not_evidenced reason=status_not_success && pass "G9 a detach that ended in error is not evidence" || fail "G9"
reset_world; act_json create_volume success 2026-10-14T13:00:00Z 3 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT --since "$A0"
refused wipe_detach_not_evidenced && verdict_line_has wipe_detach_not_evidenced reason=no_detach && pass "G10 no attach/detach action at all: no_detach" || fail "G10"
reset_world; act_json detach_volume running 2026-10-14T15:00:05Z 31 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT --since "$A0"
refused wipe_detach_in_flight && pass "G11 a running action: wipe_detach_in_flight" || fail "G11"
reset_world; act_json resize_volume running 2026-10-14T15:00:05Z 33 detach_volume success 2026-10-14T15:00:05Z 31 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT --since "$A0"
refused wipe_detach_in_flight && pass "G12 ANY running action blocks the finish, not only a detach" || fail "G12"
reset_world; act_json detach_volume success null 31 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT --since "$A0"
refused wipe_actions_unreadable && pass "G13 a successful detach with no start time is unreadable, not evidence" || fail "G13"
reset_world; printf '{"actions":{"id":1}}' > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT
refused wipe_actions_unreadable && pass "G14 actions is not an array: wipe_actions_unreadable" || fail "G14"
reset_world; printf '{"actions":[{"id":"x","command":"detach_volume","status":"success"}]}' > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT
refused wipe_actions_unreadable && pass "G15 an action with a string id is unreadable" || fail "G15"
reset_world; printf '{"actions":[{"id":9,"command":"detach_volume","status":"success","started":"2026-10-14T10:00:00Z"}],"meta":{"pagination":{"page":1,"per_page":50,"next_page":2,"total_entries":120}}}' > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT --since "$A0"
refused wipe_actions_unreadable && pass "G14b a history with a next page is truncated: refused (an attach on page 2 stays hidden otherwise)" || fail "G14b"
reset_world; printf '{"actions":[{"id":9,"command":"detach_volume","status":"success","started":"2026-10-14T10:00:00Z"}],"meta":{"pagination":{"page":1,"per_page":50,"next_page":null,"total_entries":51}}}' > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT
refused wipe_actions_unreadable && pass "G14c total_entries above the page's count is truncated even with next_page null" || fail "G14c"
reset_world; printf '{"actions":[{"id":9,"command":"detach_volume","status":"success","started":"2026-10-14T10:00:00Z"}],"meta":{"pagination":{"page":1,"per_page":50,"next_page":null,"total_entries":1}}}' > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT
[[ "$RC" == 0 ]] && pass "G14d a whole one-page history (next_page null, total_entries equals the count) is read normally" || fail "G14d rc=$RC"
reset_world; fault GET '/actions' 500 '-'; run_helper "$RO_TOK" actions --volume-id $PT
refused wipe_actions_unreadable && pass "G16 the history read fails: wipe_actions_unreadable" || fail "G16"
reset_world; printf '' > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT
refused wipe_actions_unreadable && pass "G17 an empty body: wipe_actions_unreadable" || fail "G17"
reset_world; run_helper "$RO_TOK" actions --volume-id $PT --since abc
refused wipe_actions_unreadable && [ "$(ncalls)" = 0 ] && pass "G18 a malformed --since refuses before any request" || fail "G18"
reset_world; act_json detach_volume success 2026-10-14T15:00:05+00:00 31 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT --since "$A0"
refused wipe_actions_unreadable && pass "G19 an off-format timestamp fails closed (only the pinned Z form is evidence)" || fail "G19"
sc_inflight_report() { reset_world; act_json detach_volume running 2026-10-14T15:00:05Z 32 attach_volume success 2026-10-14T14:34:00Z 30 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT; refused wipe_detach_in_flight && out_has "actions ok count=2 latest=detach_volume"; }
sc_inflight_report && pass "G24 report mode (no --since): the newest attach/detach is a RUNNING detach: the evidence line is printed, then wipe_detach_in_flight (rc 5, no mutating call)" || fail "G24"
reset_world; act_json detach_volume success 2026-10-14T15:00:05Z 31 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT
ok_run && out_has "latest=detach_volume" && pass "G25 report mode: a succeeded latest detach is ok" || fail "G25"
reset_world; act_json detach_volume error 2026-10-14T15:00:05Z 31 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT
ok_run && pass "G26 report mode: an errored latest detach is ok (a finished action is not in flight)" || fail "G26"
reset_world; act_json attach_volume success 2026-10-14T15:30:00Z 32 detach_volume running 2026-10-14T15:00:05Z 31 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT
ok_run && pass "G27 report mode: an older running detach under a newer succeeded attach is not the newest relevant action: ok" || fail "G27"
sc_dad() { reset_world; act_json detach_volume success 2026-10-14T15:20:00Z 33 attach_volume success 2026-10-14T15:10:00Z 32 detach_volume success 2026-10-14T15:00:05Z 31 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT --since "$A0"; refused wipe_detach_not_evidenced && verdict_line_has wipe_detach_not_evidenced reason=attach_after; }
sc_dad && pass "G20 detach, attach, detach: ANY attach started at/after the origin start refuses (reason=attach_after), though the newest action is a detach" || fail "G20"
reset_world; act_json detach_volume success 2026-10-14T15:00:05Z 32 attach_volume success 2026-10-14T15:00:00Z 31 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT --since "$A0"
refused wipe_detach_not_evidenced && verdict_line_has wipe_detach_not_evidenced reason=attach_after && pass "G21 boundary: an attach started exactly at the origin start refuses" || fail "G21"
reset_world; act_json detach_volume success 2026-10-14T15:00:05Z 32 attach_volume success 2026-10-14T14:59:59Z 31 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT --since "$A0"
ok_run && gho_has detach_evidence=ok && pass "G22 must-PASS: an attach started one second before the origin start (older history) does not refuse" || fail "G22"
reset_world; act_json detach_volume success 2026-10-14T15:20:00Z 33 attach_volume success null 32 detach_volume success 2026-10-14T15:00:05Z 31 > "$CUR/actions.json"; run_helper "$RO_TOK" actions --volume-id $PT --since "$A0"
refused wipe_detach_not_evidenced && verdict_line_has wipe_detach_not_evidenced reason=attach_after && pass "G23 an attach with no start time cannot be placed before the origin: refuses (fail closed)" || fail "G23"

# =====================================================================================================
# H. detach
# =====================================================================================================
echo "-- H. detach --"
rec_for_detach() { mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) ""; }
reset_world; rec_for_detach; run_helper "$RW_TOK" detach --volume-id $PT
if ok_run && out_has "detach ok action=777000111 polls=3" && [ "$(npost)" = 1 ] && [ "$(nactions_get)" = 3 ] && [ "$(classes)" = "RW " ] && gho_has phase=detached && gho_has detach_action=777000111 \
   && [ "$(wc -l < "$CUR/sleeps.log" | tr -d ' ')" = 2 ] && grep -qxF 'PT_SERVER=null' "$CUR/state.env"; then
  pass "H1 happy path: ONE detach POST, the same action polled (3 reads, 2 sleeps of 2 s), write token only, phase=detached written, volume confirmed server-less"
else fail "H1" "rc=$RC posts=$(npost) polls=$(nactions_get) classes=$(classes)"; fi
grep -qxF 'sleep 2' "$CUR/sleeps.log" && pass "H2 the poll interval is 2 s" || fail "H2"
grep -E ' (POST|GET) ' "$CUR/calls.log" | awk '{print $2" "$3}' > "$T/h1.seq"
[ "$(sed -n 1p "$T/h1.seq")" = "POST /volumes/$PT/actions/detach" ] && [ "$(sed -n 2p "$T/h1.seq")" = "GET /actions/777000111" ] && [ "$(tail -1 "$T/h1.seq")" = "GET /volumes/$PT" ] \
  && pass "H3 call order: POST detach, then the action polls, then the confirm read of the volume" || fail "H3" "$(tr '\n' '|' < "$T/h1.seq")"
reset_world DETACH_POLLS=0; rec_for_detach; run_helper "$RW_TOK" detach --volume-id $PT
ok_run && out_has "polls=1" && [ "$(wc -l < "$CUR/sleeps.log" | tr -d ' ')" = 0 ] && pass "H4 an action that is already success on the first poll needs no sleep" || fail "H4"
reset_world ACT_END=never; rec_for_detach; run_helper "$RW_TOK" detach --volume-id $PT
if [ "$RC" = 5 ] && verdict_is wipe_detach_not_confirmed && verdict_line_has wipe_detach_not_confirmed "reason=poll_exhausted polls=90" && [ "$(npost)" = 1 ] && [ "$(nactions_get)" = 90 ] && [ "$(ndelete)" = 0 ] \
   && [ "$(wc -l < "$CUR/sleeps.log" | tr -d ' ')" = 89 ] && ! grep -qxF phase=detached "$CUR/gho"; then
  pass "H5 a poll that never reaches success: exactly 90 reads (89 sleeps), the detach is NOT re-sent (one POST), no phase=detached"
else fail "H5" "posts=$(npost) polls=$(nactions_get)"; fi
reset_world DETACH_POLLS=69; rec_for_detach; run_helper "$RW_TOK" detach --volume-id $PT
if ok_run && out_has "detach ok action=777000111 polls=70" && [ "$(npost)" = 1 ] && [ "$(nactions_get)" = 70 ] && [ "$(wc -l < "$CUR/sleeps.log" | tr -d ' ')" = 69 ] && gho_has phase=detached; then
  pass "H5a a slow healthy detach (success on poll 70, past the old 60 s window): confirmed, ONE POST, 69 sleeps, phase=detached written"
else fail "H5a" "rc=$RC posts=$(npost) polls=$(nactions_get)"; fi
reset_world ACT_END=never; printf '22\n' > "$CUR/sleep_adv"; rec_for_detach; run_helper "$RW_TOK" detach --volume-id $PT
if [ "$RC" = 5 ] && verdict_is wipe_detach_not_confirmed && verdict_line_has wipe_detach_not_confirmed "reason=poll_exhausted polls=12" && [ "$(npost)" = 1 ] && [ "$(nactions_get)" = 12 ] && [ "$(ndelete)" = 0 ] \
   && [ "$(wc -l < "$CUR/sleeps.log" | tr -d ' ')" = 11 ] && ! grep -qxF phase=detached "$CUR/gho"; then
  pass "H5b a poll that never reaches success on a slow clock (22 s a cycle): the 240 s wall-clock cap ends it at 12 reads (11 sleeps) before the 90-read bound, still ONE POST"
else fail "H5b" "rc=$RC posts=$(npost) polls=$(nactions_get)"; fi
reset_world DETACH_POLLS=9; printf '22\n' > "$CUR/sleep_adv"; rec_for_detach; run_helper "$RW_TOK" detach --volume-id $PT
ok_run && out_has "polls=10" && [ "$(npost)" = 1 ] && pass "H5c a slow clock that still succeeds inside the cap (10 reads, 198 s) is confirmed: the cap does not cut a healthy detach" || fail "H5c" "rc=$RC polls=$(nactions_get)"
reset_world ACT_END=error; rec_for_detach; run_helper "$RW_TOK" detach --volume-id $PT
[ "$RC" = 5 ] && verdict_is wipe_detach_not_confirmed && verdict_line_has wipe_detach_not_confirmed reason=action_not_success && [ "$(npost)" = 1 ] && pass "H6 an action that ends in error: wipe_detach_not_confirmed, one POST" || fail "H6"
reset_world; rec_for_detach; fault POST '/actions/detach$' 500 '{"error":{"code":"x"}}'; run_helper "$RW_TOK" detach --volume-id $PT
[ "$RC" = 5 ] && verdict_is wipe_detach_not_confirmed && verdict_line_has wipe_detach_not_confirmed "reason=post_unconfirmed code=500" && [ "$(npost)" = 1 ] && [ "$(nactions_get)" = 0 ] && pass "H7 a 500 on the POST: wipe_detach_not_confirmed (the request may have landed), one POST, no retry" || fail "H7"
reset_world; rec_for_detach; fault POST '/actions/detach$' 000 '-'; run_helper "$RW_TOK" detach --volume-id $PT
[ "$RC" = 5 ] && verdict_is wipe_detach_not_confirmed && out_has "code=000" && [ "$(npost)" = 1 ] && pass "H8 a transport failure on the POST: wipe_detach_not_confirmed, one POST, no retry" || fail "H8"
reset_world PT_SERVER=null; rec_for_detach; run_helper "$RW_TOK" detach --volume-id $PT
[ "$RC" = 5 ] && verdict_is wipe_detach_rejected && verdict_line_has wipe_detach_rejected code=422 && [ "$(npost)" = 1 ] && pass "H9 a 4xx on the POST (already detached): wipe_detach_rejected code=422" || fail "H9"
reset_world; rec_for_detach; fault POST '/actions/detach$' 201 '{"action":{"status":"running"}}'; run_helper "$RW_TOK" detach --volume-id $PT
[ "$RC" = 5 ] && verdict_line_has wipe_detach_not_confirmed reason=no_action_id && [ "$(nactions_get)" = 0 ] && pass "H10 a 201 without an action id: wipe_detach_not_confirmed reason=no_action_id" || fail "H10"
reset_world; rec_for_detach; fault GET '^/actions/' 500 '-'; run_helper "$RW_TOK" detach --volume-id $PT
[ "$RC" = 5 ] && verdict_line_has wipe_detach_not_confirmed "reason=poll_unreadable code=500" && [ "$(npost)" = 1 ] && pass "H11 a 500 while polling: wipe_detach_not_confirmed, still one POST" || fail "H11"
reset_world; rec_for_detach; fault GET '^/actions/' 200 '<html>x</html>'; run_helper "$RW_TOK" detach --volume-id $PT
[ "$RC" = 5 ] && verdict_line_has wipe_detach_not_confirmed reason=poll_shape && [ "$(npost)" = 1 ] && pass "H12 an off-shape poll body: wipe_detach_not_confirmed reason=poll_shape" || fail "H12"
reset_world; rec_for_detach; fault GET '^/volumes/'"$PT"'$' 200 '{"volume":{"id":900000001,"server":800000001}}'; run_helper "$RW_TOK" detach --volume-id $PT
[ "$RC" = 5 ] && verdict_line_has wipe_detach_not_confirmed reason=still_attached && ! grep -qxF phase=detached "$CUR/gho" && pass "H13 the action says success but the volume still names a server: wipe_detach_not_confirmed reason=still_attached, no phase=detached" || fail "H13"
reset_world; rec_for_detach; fault GET '^/volumes/'"$PT"'$' 500 '-'; run_helper "$RW_TOK" detach --volume-id $PT
[ "$RC" = 5 ] && verdict_line_has wipe_detach_not_confirmed "reason=confirm_unreadable code=500" && pass "H14 the confirm read fails: wipe_detach_not_confirmed reason=confirm_unreadable" || fail "H14"
reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 121)) ""; run_helper "$RW_TOK" detach --volume-id $PT
refused wipe_assertion_stale && [ "$(ncalls)" = 0 ] && pass "H15 a stale W7 epoch: wipe_assertion_stale and the detach is NOT sent (zero requests)" || fail "H15"
reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 120)) ""; run_helper "$RW_TOK" detach --volume-id $PT
ok_run && pass "H16 boundary: exactly at the bound the detach proceeds" || fail "H16"
reset_world; run_helper "$RW_TOK" detach --volume-id $PT
refused wipe_record_absent && [ "$(ncalls)" = 0 ] && pass "H17 no verdict record: wipe_record_absent and zero requests" || fail "H17"
reset_world; mk_record $((CLOCK0 - 10)) "" ""; run_helper "$RW_TOK" detach --volume-id $PT
refused wipe_assertion_stale && [ "$(ncalls)" = 0 ] && pass "H18 W7 never stamped: the detach is refused, zero requests" || fail "H18"
reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) "" 123456789; run_helper "$RW_TOK" detach --volume-id $PT
refused wipe_record_volume_mismatch && [ "$(ncalls)" = 0 ] && pass "H19 the record binds another volume than the typed id: refused, zero requests" || fail "H19"
reset_world; rec_for_detach; chmod 644 "$CUR/rt/git-data-wipe-record"; run_helper "$RW_TOK" detach --volume-id $PT
refused wipe_record_invalid && [ "$(ncalls)" = 0 ] && pass "H20 a record that is not mode 0600: the detach is refused, zero requests" || fail "H20"
reset_world; rec_for_detach; run_helper "$RW_TOK" detach --volume-id $LUKS
refused wipe_record_volume_mismatch && [ "$(ncalls)" = 0 ] && pass "H21 the LUKS id typed to detach cannot match the plaintext record: refused, zero requests" || fail "H21"
reset_world PT_SERVER=gone; rec_for_detach; run_helper "$RW_TOK" detach --volume-id $PT
[ "$RC" = 5 ] && verdict_is wipe_detach_rejected && verdict_line_has wipe_detach_rejected code=404 && [ "$(npost)" = 1 ] && pass "H22 a 404 on the POST (the volume is gone): wipe_detach_rejected code=404" || fail "H22"

# =====================================================================================================
# I. delete
# =====================================================================================================
echo "-- I. delete --"
rec_for_delete() { mk_record $((CLOCK0 - 300)) $((CLOCK0 - 200)) $((CLOCK0 - 5)); }
reset_world PT_SERVER=null; rec_for_delete; run_helper "$RW_TOK" delete --volume-id $PT
if ok_run && out_has "delete ok http=204" && [ "$(ndelete)" = 1 ] && [ "$(ncalls)" = 1 ] && [ "$(classes)" = "RW " ] && gho_has phase=delete_sent && grep -qxF 'PT_SERVER=gone' "$CUR/state.env"; then
  pass "I1 happy path: ONE DELETE with the write token, 204, phase=delete_sent written, nothing else called"
else fail "I1" "rc=$RC"; fi
reset_world; rec_for_delete; run_helper "$RW_TOK" delete --volume-id $PT
[ "$RC" = 5 ] && verdict_is wipe_delete_rejected && verdict_line_has wipe_delete_rejected code=423 && [ "$(ndelete)" = 1 ] && ! grep -qxF phase=delete_sent "$CUR/gho" && pass "I2 DELETE on an attached volume: the API's 423 is wipe_delete_rejected, no phase=delete_sent" || fail "I2"
reset_world PT_SERVER=null; rec_for_delete; fault DELETE '^/volumes/' 404 "$(printf '%s' '{"error":{"code":"not_found"}}')"; run_helper "$RW_TOK" delete --volume-id $PT
[ "$RC" = 5 ] && verdict_is wipe_delete_not_found && [ "$(ndelete)" = 1 ] && pass "I3 DELETE 404: wipe_delete_not_found (read back before concluding anything)" || fail "I3"
reset_world PT_SERVER=null; rec_for_delete; fault DELETE '^/volumes/' 500 '-'; run_helper "$RW_TOK" delete --volume-id $PT
[ "$RC" = 5 ] && verdict_is wipe_delete_unconfirmed && verdict_line_has wipe_delete_unconfirmed code=500 && [ "$(ndelete)" = 1 ] && pass "I4 DELETE 500: wipe_delete_unconfirmed, one DELETE, no retry" || fail "I4"
reset_world PT_SERVER=null; rec_for_delete; fault DELETE '^/volumes/' 000 '-'; run_helper "$RW_TOK" delete --volume-id $PT
[ "$RC" = 5 ] && verdict_is wipe_delete_unconfirmed && verdict_line_has wipe_delete_unconfirmed code=000 && [ "$(ndelete)" = 1 ] && pass "I5 DELETE transport failure: wipe_delete_unconfirmed, one DELETE" || fail "I5"
reset_world PT_SERVER=null; rec_for_delete; fault DELETE '^/volumes/' 200 '{}'; run_helper "$RW_TOK" delete --volume-id $PT
[ "$RC" = 5 ] && verdict_is wipe_delete_unconfirmed && pass "I6 DELETE answering 200 (not the pinned 204): wipe_delete_unconfirmed" || fail "I6"
reset_world PT_SERVER=null; mk_record $((CLOCK0 - 300)) $((CLOCK0 - 200)) $((CLOCK0 - 61)); run_helper "$RW_TOK" delete --volume-id $PT
refused wipe_assertion_stale && [ "$(ncalls)" = 0 ] && pass "I7 61 s after the W10b stamp: stale, the DELETE is NOT sent (zero requests)" || fail "I7"
reset_world PT_SERVER=null; mk_record $((CLOCK0 - 300)) $((CLOCK0 - 200)) $((CLOCK0 - 60)); run_helper "$RW_TOK" delete --volume-id $PT
ok_run && pass "I8 boundary: exactly 60 s after the W10b stamp the DELETE proceeds" || fail "I8"
reset_world PT_SERVER=null; mk_record $((CLOCK0 - 300)) $((CLOCK0 - 200)) ""; run_helper "$RW_TOK" delete --volume-id $PT
refused wipe_assertion_stale && [ "$(ncalls)" = 0 ] && pass "I9 W10b never stamped: refused, zero requests" || fail "I9"
reset_world PT_SERVER=null; mk_record $((CLOCK0 - 300)) "" $((CLOCK0 - 5)); run_helper "$RW_TOK" delete --volume-id $PT
refused wipe_assertion_stale && [ "$(ncalls)" = 0 ] && pass "I10 W7 never stamped (no host look this run): refused, zero requests" || fail "I10"
reset_world PT_SERVER=null; run_helper "$RW_TOK" delete --volume-id $PT
refused wipe_record_absent && [ "$(ncalls)" = 0 ] && pass "I11 no record at all: refused, zero requests" || fail "I11"
reset_world PT_SERVER=null; rec_for_delete; run_helper "$RW_TOK" delete --volume-id $LUKS
refused wipe_record_volume_mismatch && [ "$(ncalls)" = 0 ] && pass "I12 the LUKS id typed to delete: refused by the record binding, zero requests" || fail "I12"
reset_world PT_SERVER=null; mk_record $((CLOCK0 - 300)) $((CLOCK0 - 200)) $((CLOCK0 - 5)) 123456789; run_helper "$RW_TOK" delete --volume-id $PT
refused wipe_record_volume_mismatch && [ "$(ncalls)" = 0 ] && pass "I13 the record binds another volume: refused, zero requests" || fail "I13"

# =====================================================================================================
# J. readback
# =====================================================================================================
echo "-- J. readback --"
reset_world PT_SERVER=gone; run_helper "$RO_TOK" readback --volume-id $PT
if ok_run && out_has "readback ok volume_state=absent plaintext_volumes=0 luks_state=attached servers=1" && gho_has phase=deleted && gho_has volume_state=absent && [ "$(nmut)" = 0 ] && [ "$(classes)" = "RO " ] && [ "$(ncalls)" = 4 ]; then
  pass "J1 read-back (also the absent-volume path): 404 + empty name list + the LUKS volume still the one attached; four reads, read-only token, no mutating call, phase=deleted"
else fail "J1" "rc=$RC calls=$(ncalls)"; fi
reset_world; run_helper "$RO_TOK" readback --volume-id $PT
refused wipe_readback_still_exists && pass "J2 the id still answers 200: wipe_readback_still_exists" || fail "J2"
reset_world PT_SERVER=gone; fault GET '^/volumes\?name=soleur-git-data-store$' 200 '{"volumes":[{"id":900000077,"name":"soleur-git-data-store"}]}'; run_helper "$RO_TOK" readback --volume-id $PT
refused wipe_readback_name_still_listed && verdict_line_has wipe_readback_name_still_listed count=1 && pass "J3 404 on the id but the name is still listed (the typed id was wrong): wipe_readback_name_still_listed" || fail "J3"
reset_world PT_SERVER=gone; fault GET '^/volumes/'"$PT"'$' 404 '<html>x</html>'; run_helper "$RO_TOK" readback --volume-id $PT
refused wipe_readback_unreadable && verdict_line_has wipe_readback_unreadable reason=not_found_shape && pass "J4 a 404 that is not Hetzner's not_found JSON proves nothing: wipe_readback_unreadable" || fail "J4"
reset_world PT_SERVER=gone; fault GET '^/volumes/'"$PT"'$' 500 '-'; run_helper "$RO_TOK" readback --volume-id $PT
refused wipe_readback_unreadable && pass "J5 a 500 on the id read: wipe_readback_unreadable" || fail "J5"
reset_world PT_SERVER=gone; fault GET '^/volumes\?name=soleur-git-data-store$' 500 '-'; run_helper "$RO_TOK" readback --volume-id $PT
refused wipe_readback_unreadable && pass "J6 the name read fails: wipe_readback_unreadable" || fail "J6"
reset_world PT_SERVER=gone LUKS_N=0; run_helper "$RO_TOK" readback --volume-id $PT
refused wipe_readback_luks_missing && verdict_line_has wipe_readback_luks_missing count=0 && pass "J7 the LUKS volume is not listed: wipe_readback_luks_missing (a 404 from a token that cannot see it proves nothing)" || fail "J7"
reset_world PT_SERVER=gone LUKS_N=2; run_helper "$RO_TOK" readback --volume-id $PT
refused wipe_readback_luks_missing && pass "J8 two LUKS volumes: wipe_readback_luks_missing" || fail "J8"
reset_world PT_SERVER=gone LUKS_SERVER=null; run_helper "$RO_TOK" readback --volume-id $PT
refused wipe_readback_luks_detached && pass "J9 the LUKS volume is detached: wipe_readback_luks_detached" || fail "J9"
reset_world PT_SERVER=gone LUKS_SERVER=777; run_helper "$RO_TOK" readback --volume-id $PT
refused wipe_readback_luks_detached && pass "J10 the LUKS volume is attached to another server: wipe_readback_luks_detached" || fail "J10"
reset_world PT_SERVER=gone SRV_N=0; run_helper "$RO_TOK" readback --volume-id $PT
refused wipe_server_count && pass "J11 the token cannot see the server: refused (the presence proof fails)" || fail "J11"
reset_world PT_SERVER=gone; fault GET '^/volumes\?name=soleur-git-data-luks-store$' 500 '-'; run_helper "$RO_TOK" readback --volume-id $PT
refused wipe_readback_unreadable && pass "J12 the LUKS read fails: wipe_readback_unreadable" || fail "J12"

# =====================================================================================================
# K. the whole sequence against one state machine
# =====================================================================================================
echo "-- K. sequence --"
reset_world
: > "$T/seq.rcs"
run_helper "$RO_TOK" identity --expect attached --volume-id $PT --record write; echo "$RC" >> "$T/seq.rcs"
run_helper "" stamp --epoch w7; echo "$RC" >> "$T/seq.rcs"
run_helper "$RW_TOK" detach --volume-id $PT; echo "$RC" >> "$T/seq.rcs"
run_helper "$RO_TOK" identity --expect detached --volume-id $PT --record check; echo "$RC" >> "$T/seq.rcs"
run_helper "$RW_TOK" delete --volume-id $PT; echo "$RC" >> "$T/seq.rcs"
run_helper "$RO_TOK" readback --volume-id $PT; echo "$RC" >> "$T/seq.rcs"
[ "$(tr '\n' ' ' < "$T/seq.rcs")" = "0 0 0 0 0 0 " ] && unexpected && pass "K1 identity(write) -> stamp w7 -> detach -> identity(check) -> delete -> readback: all exit 0 against the state machine" || fail "K1" "$(tr '\n' ' ' < "$T/seq.rcs")"
[ "$(npost)" = 1 ] && [ "$(ndelete)" = 1 ] && pass "K2 across the whole sequence: exactly one detach POST and one DELETE" || fail "K2" "posts=$(npost) deletes=$(ndelete)"
ipost="$(grep -nE ' POST ' "$CUR/calls.log" | head -1 | cut -d: -f1)"; idel="$(grep -nE ' DELETE ' "$CUR/calls.log" | head -1 | cut -d: -f1)"
[ -n "$ipost" ] && [ -n "$idel" ] && [ "$ipost" -lt "$idel" ] && pass "K3 the detach precedes the delete in the request log" || fail "K3"
if grep -nE ' (GET) /volumes\?name=soleur-git-data-store' "$CUR/calls.log" | tail -1 | cut -d: -f1 > "$T/lastpt"; then
  [ "$(cat "$T/lastpt")" -gt "$idel" ] && pass "K4 the last read of the name list is after the DELETE (the read-back)" || fail "K4"
fi
awk '$2=="POST"||$2=="DELETE"{print $4}' "$CUR/calls.log" | sort -u | tr '\n' ' ' > "$T/mutclasses"
[ "$(cat "$T/mutclasses")" = "RW " ] && pass "K5 every mutating request carries the write token; every read carries the read-only token" || fail "K5" "$(cat "$T/mutclasses")"
awk '$2=="GET" && $3 !~ /^\/actions\// {print $4}' "$CUR/calls.log" | sort -u | tr '\n' ' ' > "$T/roclasses"
[ "$(cat "$T/roclasses")" = "RO RW " ] && pass "K6 reads by verb: identity/readback use RO; the detach verb's own confirm reads use RW (never mixed within a verb)" || fail "K6" "$(cat "$T/roclasses")"
! grep -qF -e "$RO_TOK" -e "$RW_TOK" "$CUR/rt/git-data-wipe-record" && [ "$(stat -c %a "$CUR/rt/git-data-wipe-record")" = 600 ] && pass "K7 the record stays mode 0600 and token-free after the whole sequence" || fail "K7"
reset_world PT_SERVER=null; mk_record $((CLOCK0 - 300)) $((CLOCK0 - 200)) $((CLOCK0 - 5)); run_helper "$RW_TOK" delete --volume-id $PT; run_helper "$RW_TOK" delete --volume-id $PT
[ "$RC" = 5 ] && verdict_is wipe_delete_not_found && [ "$(ndelete)" = 2 ] && pass "K8 a second DELETE after the first succeeded answers 404: wipe_delete_not_found (a re-dispatch cannot double-delete)" || fail "K8"
reset_world PT_SERVER=null; rec_for_detach; run_helper "$RW_TOK" detach --volume-id $PT
[ "$RC" = 5 ] && [ "$(npost)" = 1 ] && pass "K9 detaching an already-detached volume is rejected by the API and reported (one POST, no phase)" || fail "K9"

# =====================================================================================================
# L. hygiene over every run above
# =====================================================================================================
echo "-- L. hygiene --"
n_argv="$(find "$T/w" -name '*.argv' | wc -l | tr -d ' ')"
bad_argv=0
while IFS= read -r f; do grep -qaF -e "$RO_TOK" -e "$RW_TOK" -e "$OTHER_TOK" "$f" && bad_argv=1; done < <(find "$T/w" -name '*.argv')
[ "$bad_argv" = 0 ] && [ "$n_argv" -ge 300 ] && pass "L1 no synthesized token appears on any of the $n_argv recorded curl argvs (floor 300)" || fail "L1" "bad=$bad_argv n=$n_argv"
mkdir -p "$T/ctl"; assert_fixture_dir "$T/ctl"; printf 'curl\n-H\nAuthorization: Bearer %s\n' "$RO_TOK" > "$T/ctl/1.argv"
ctl_hit=0; grep -qaF -e "$RO_TOK" "$T/ctl/1.argv" && ctl_hit=1
[ "$ctl_hit" = 1 ] && pass "L2 control: the argv scan sees a planted token on an argv (it is not blind)" || fail "L2 the argv scan is blind"
: > "$T/corpus"; while IFS= read -r d; do cat "$d/stdout" "$d/stderr" "$d/gho" >> "$T/corpus" 2>/dev/null; [ -f "$d/rt/git-data-wipe-record" ] && cat "$d/rt/git-data-wipe-record" >> "$T/corpus"; done < <(find "$T/w" -mindepth 1 -maxdepth 1 -type d)
n_corpus="$(wc -c < "$T/corpus" | tr -d ' ')"
grep -qaF -e "$RO_TOK" -e "$RW_TOK" -e "$OTHER_TOK" "$T/corpus" && fail "L3 a token reached stdout, stderr, GITHUB_OUTPUT or a record" || { [ "$n_corpus" -ge 20000 ] && pass "L3 no token in $n_corpus bytes of stdout/stderr/GITHUB_OUTPUT/record across all runs (floor 20000)" || fail "L3 corpus below its floor" "$n_corpus"; }
printf 'leak %s\n' "$RW_TOK" >> "$T/ctl/corpus"; grep -qaF -e "$RW_TOK" "$T/ctl/corpus" && pass "L4 control: the corpus scan sees a planted token" || fail "L4 corpus scan is blind"
grep -qE 'volumes/|servers/' "$T/corpus" && fail "L5 an API path was printed" || pass "L5 no API path or URL is ever printed by the helper"
fnames="$(cat "$T/w"/*/stdout "$T/w"/*/stderr 2>/dev/null | grep -ciE 'erased|wiped|secure|no copies|snapshot' || true)"
[ "$fnames" = 0 ] && pass "L6 no forbidden over-claiming word on any output stream across all runs" || fail "L6" "$fnames"
cat "$T/w"/*/unexpected.log 2>/dev/null > "$T/unexpected.all" || true
[ ! -s "$T/unexpected.all" ] && pass "L7 the shim saw no request outside its contract in any run (no stray method/path)" || fail "L7" "$(head -3 "$T/unexpected.all")"
n_bad_host="$(cat "$T/w"/*/calls.log | grep -c BADHOST || true)"
[ "$n_bad_host" = 0 ] && pass "L8 every request went to https://api.hetzner.cloud/v1 (no other host, no http)" || fail "L8" "$n_bad_host"
tok_in_env=0
grep -qE 'export[[:space:]]+(HCLOUD_TOKEN|HCLOUD_TOKEN_READONLY)|declare -x' "$HELPER_PRISTINE" && tok_in_env=1
[ "$tok_in_env" = 0 ] && pass "L9 the helper never exports a token name (the value is an unexported shell variable read by name)" || fail "L9"

# =====================================================================================================
# M. every verdict word the helper can print was printed by a row above
# =====================================================================================================
echo "-- M. coverage --"
SRC_WORDS="$(grep -oE 'wipe_[a-z0-9_]+' <<<"$SRC_NOCOMMENT" | grep -vE '^wipe_(usage)$' | sort -u)"
SEEN_WORDS="$(sed 's/^verdict=//' "$T/seen/words" | sort -u)"
missing=""; for w in $SRC_WORDS; do grep -qxF -- "$w" <<<"$SEEN_WORDS" || missing+=" $w"; done
n_words="$(grep -c . <<<"$SRC_WORDS" || true)"
[ -z "$missing" ] && [ "$n_words" -ge 40 ] && pass "M1 all $n_words verdict words the helper text can print were observed (floor 40)" || fail "M1 verdict words never driven: $missing (n=$n_words)"
grep -qxF wipe_usage <<<"$SEEN_WORDS" && pass "M2 wipe_usage observed (stderr, exit 2)" || fail "M2"
for w in wipe_target_is_luks wipe_volume_id_mismatch wipe_not_attached_to_current_host wipe_volume_already_detached wipe_delete_protected wipe_detach_not_confirmed wipe_assertion_stale wipe_readback_name_still_listed wipe_volume_count wipe_label_mismatch; do
  grep -qxF -- "$w" <<<"$SEEN_WORDS" || fail "M3 the design 3.1/3.4 verdict $w was never driven"
done
pass "M3 the design 3.1/3.4 verdict words are all in the observed set"

# =====================================================================================================
# N. mutants: each scenario must go RED against a copy with one guard removed
# =====================================================================================================
echo "-- N. mutation rows --"
mutate() { # <name> <expected-diff-lines> <sed -E program | -e prog -e prog ...>
  local name="$1" want="$2" got
  shift 2
  local -a sedargs=("$@")
  [ "${sedargs[0]}" = -e ] || sedargs=(-e "${sedargs[0]}")
  MUTANT="$T/mut/$name.git-data-wipe.sh"
  cp "$HELPER_PRISTINE" "$MUTANT" || { printf 'FAIL SETUP: mutation copy %s\n' "$name" >&2; exit 1; }
  if ! sed -E -i "${sedargs[@]}" "$MUTANT" 2> "$T/mut/$name.err"; then fail "M-$name: mutation sed failed" "$(head -1 "$T/mut/$name.err")"; return 1; fi
  got="$(diff "$HELPER_PRISTINE" "$MUTANT" | grep -cE '^[<>]' || true)"
  if [ "$got" != "$want" ]; then fail "M-$name: mutation landed on $got diff line(s), expected $want" "[${sedargs[*]}]"; return 1; fi
  if ! bash -n "$MUTANT" 2>/dev/null; then fail "M-$name: the mutant does not parse (bash -n)"; return 1; fi
  MUTANTS_RUN=$((MUTANTS_RUN + 1))
  pass "M-$name: mutation landed on exactly $want diff line(s) of a pristine copy"
}
mutant_red() { # <name> <scenario-function>
  local name="$1" scn="$2" save="$HELPER"
  HELPER="$MUTANT"
  if "$scn"; then HELPER="$save"; fail "M-$name: the named scenario stayed GREEN against the mutant"; else HELPER="$save"; pass "M-$name: the named scenario goes RED against the mutant"; fi
}

sc_stale_detach() { reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 400)) ""; run_helper "$RW_TOK" detach --volume-id $PT; refused wipe_assertion_stale && [ "$(ncalls)" = 0 ]; }
sc_stale_delete() { reset_world PT_SERVER=null; mk_record $((CLOCK0 - 300)) $((CLOCK0 - 200)) $((CLOCK0 - 120)); run_helper "$RW_TOK" delete --volume-id $PT; refused wipe_assertion_stale && [ "$(ncalls)" = 0 ]; }
sc_norecord_delete() { reset_world PT_SERVER=null; run_helper "$RW_TOK" delete --volume-id $PT; refused wipe_record_absent && [ "$(ncalls)" = 0 ]; }
sc_luks_typed() { reset_world; run_helper "$RO_TOK" identity --expect attached --volume-id $LUKS; refused wipe_target_is_luks; }
sc_id_mismatch() { reset_world; run_helper "$RO_TOK" identity --expect attached --volume-id 123456789; refused wipe_volume_id_mismatch; }
sc_protect() { reset_world PT_PROT=true; run_helper "$RO_TOK" identity --expect attached --volume-id $PT; refused wipe_delete_protected; }
sc_readback_luks() { reset_world PT_SERVER=gone LUKS_SERVER=null; run_helper "$RO_TOK" readback --volume-id $PT; refused wipe_readback_luks_detached; }
sc_readback_name() { reset_world PT_SERVER=gone; fault GET '^/volumes\?name=soleur-git-data-store$' 200 '{"volumes":[{"id":900000077}]}'; run_helper "$RO_TOK" readback --volume-id $PT; refused wipe_readback_name_still_listed; }
sc_nofallback() { reset_world; EXTRA_ENV=("HCLOUD_TOKEN=$RW_TOK"); run_helper "" state; EXTRA_ENV=(); refused wipe_readonly_token_absent && [ "$(ncalls)" = 0 ]; }
sc_poll_bound() { reset_world ACT_END=never; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) ""; run_helper "$RW_TOK" detach --volume-id $PT; [ "$RC" = 5 ] && [ "$(npost)" = 1 ] && [ "$(nactions_get)" = 90 ]; }
sc_poll_slow() { reset_world DETACH_POLLS=69; rec_for_detach; run_helper "$RW_TOK" detach --volume-id $PT; ok_run && out_has "polls=70" && [ "$(npost)" = 1 ]; }
sc_poll_wall() { reset_world ACT_END=never; printf '22\n' > "$CUR/sleep_adv"; rec_for_detach; run_helper "$RW_TOK" detach --volume-id $PT; [ "$RC" = 5 ] && [ "$(npost)" = 1 ] && [ "$(nactions_get)" = 12 ]; }
sc_record_bind() { reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) "" 123456789; run_helper "$RW_TOK" detach --volume-id $PT; refused wipe_record_volume_mismatch && [ "$(ncalls)" = 0 ]; }
sc_confirm_detach() { reset_world; mk_record $((CLOCK0 - 10)) $((CLOCK0 - 30)) ""; fault GET '^/volumes/'"$PT"'$' 200 '{"volume":{"id":900000001,"server":800000001}}'; run_helper "$RW_TOK" detach --volume-id $PT; [ "$RC" = 5 ] && verdict_is wipe_detach_not_confirmed; }
sc_identity_no_phase() { reset_world PT_SERVER=null; run_helper "$RO_TOK" identity --expect detached --volume-id $PT --record write; ok_run && ! grep -q '^phase=' "$CUR/gho"; }
sc_check_binding() { reset_world PT_SERVER=null LUKS_ID=900000055; mk_record $((CLOCK0 - 90)) $((CLOCK0 - 80)) ""; run_helper "$RO_TOK" identity --expect detached --volume-id $PT --record check; refused wipe_target_changed; }

mutate no-w7-record-check-in-detach 2 's/^  record_verify w7 "\$VID"$/  :/'
mutant_red no-w7-record-check-in-detach sc_stale_detach
mutate no-w10b-record-check-in-delete 2 's/^  record_verify w10b "\$VID"$/  :/'
mutant_red no-w10b-record-check-in-delete sc_stale_delete
mutant_red no-w10b-record-check-in-delete sc_norecord_delete
mutate w10b-bound-widened 2 's/^readonly WIPE_W10B_BOUND_SECONDS=60$/readonly WIPE_W10B_BOUND_SECONDS=600/'
mutant_red w10b-bound-widened sc_stale_delete
mutate luks-id-guard-removed 2 's/^  \[\[ "\$VID" != "\$luks_id" \]\] \|\| refuse wipe_target_is_luks$/  :/'
mutant_red luks-id-guard-removed sc_luks_typed
mutate id-equality-removed 2 's/^  \[\[ "\$ptid" == "\$VID" \]\] \|\| refuse wipe_volume_id_mismatch$/  :/'
mutant_red id-equality-removed sc_id_mismatch
mutate protection-check-removed 2 's/^  \[\[ "\$V_PROT" == false \]\] \|\| refuse wipe_delete_protected$/  :/'
mutant_red protection-check-removed sc_protect
mutate readback-luks-presence-removed 2 's/^  \[\[ "\$luks_cls" == attached && "\$V_SERVER" == "\$srv" \]\] \|\| refuse wipe_readback_luks_detached$/  :/'
mutant_red readback-luks-presence-removed sc_readback_luks
mutate readback-name-list-removed 2 's/^  \[\[ "\$JV" == 0 \]\] \|\| refuse wipe_readback_name_still_listed "count=\$JV"$/  :/'
mutant_red readback-name-list-removed sc_readback_name
mutate token-fallback-added 4 -e 's/^  unset HCLOUD_TOKEN HCLOUD_TOKEN_READONLY$/  :/' -e 's/^(  IFS= read -r -t 10 _line \|\| true)$/\1; _line="${_line:-${HCLOUD_TOKEN-}}"/'
mutant_red token-fallback-added sc_nofallback
mutate poll-bound-widened 2 's/^readonly WIPE_POLL_MAX_ATTEMPTS=90$/readonly WIPE_POLL_MAX_ATTEMPTS=91/'
mutant_red poll-bound-widened sc_poll_bound
mutate poll-bound-narrowed-to-old-window 2 's/^readonly WIPE_POLL_MAX_ATTEMPTS=90$/readonly WIPE_POLL_MAX_ATTEMPTS=30/'
mutant_red poll-bound-narrowed-to-old-window sc_poll_slow
mutate poll-wall-cap-removed 2 's/^          \(\( NOW - poll_t0 < WIPE_POLL_WALL_CAP_SECONDS \)\) \|\| break$/          :/'
mutant_red poll-wall-cap-removed sc_poll_wall
mutate poll-wall-cap-widened 2 's/^readonly WIPE_POLL_WALL_CAP_SECONDS=240$/readonly WIPE_POLL_WALL_CAP_SECONDS=2400/'
mutant_red poll-wall-cap-widened sc_poll_wall
mutate poll-clock-not-refreshed 2 's/^          now_epoch$/          :/'
mutant_red poll-clock-not-refreshed sc_poll_wall
mutate poll-origin-not-taken 2 's/^  poll_t0="\$NOW"$/  poll_t0=0/'
mutant_red poll-origin-not-taken sc_poll_wall
mutate record-volume-binding-removed 2 's/^  if \[\[ -n "\$\{2-\}" && "\$2" != "\$R_plaintext_id" \]\]; then refuse wipe_record_volume_mismatch; fi$/  :/'
mutant_red record-volume-binding-removed sc_record_bind
mutate detach-confirm-removed 4 -e 's/^  jget .\.volume \| must\(type=="object" and \.id==\$v and \.server==null\) \| "ok". --argjson v "\$VID" \|\| refuse wipe_detach_not_confirmed reason=still_attached$/  :/' -e 's/^  \[\[ "\$JV" == ok \]\] \|\| refuse wipe_detach_not_confirmed reason=still_attached$/  :/'
mutant_red detach-confirm-removed sc_confirm_detach
mutate record-binding-check-removed 2 's/^      \[\[ "\$R_luks_id" == "\$luks_id" \]\] \|\| refuse wipe_target_changed reason=luks_volume$/      :/'
mutant_red record-binding-check-removed sc_check_binding
mutate identity-phase-written 1 's/^  local ids=""$/  if [[ "$EXPECT" == detached \&\& "$RECORD_MODE" == write ]]; then gho phase detached; fi\n  local ids=""/'
mutant_red identity-phase-written sc_identity_no_phase
mutate inflight-report-check-removed 2 's/^    \[\[ "\$JV" == yes \]\] && refuse wipe_detach_in_flight$/    :/'
mutant_red inflight-report-check-removed sc_inflight_report
mutate attach-after-since-removed 2 's/^          elif any\(\$a\[\]; \.command=="attach_volume" and .*$/          elif false then "attach_after"/'
mutant_red attach-after-since-removed sc_dad
mutate phases-dispatch-after-library 2 's/^if \[\[ "\$\{1-\}" == phases \]\]; then shift; do_phases "\$@"; exit 0; fi$/:/'
mutant_red phases-dispatch-after-library sc_phases_bare
mutate w4-octal-guard-removed 2 's/NOW - 10#\$R_w4_epoch > WIPE_W4_OUTER_BOUND_SECONDS/NOW - R_w4_epoch > WIPE_W4_OUTER_BOUND_SECONDS/'
mutant_red w4-octal-guard-removed sc_octal_w4
mutate w7-octal-guard-removed 2 's/age=\$\(\( NOW - 10#\$e \)\)/age=$(( NOW - e ))/'
mutant_red w7-octal-guard-removed sc_octal_w7
[ "$MUTANTS_RUN" -ge 24 ] && pass "N-floor: $MUTANTS_RUN mutants were applied and each was run against its named scenario (floor 24)" || fail "N-floor: only $MUTANTS_RUN mutants ran (floor 24)"
# control: the pristine helper is GREEN on every named scenario (a scenario that is always RED would make the mutant rows vacuous)
ctl_bad=""
for s in sc_stale_detach sc_stale_delete sc_norecord_delete sc_luks_typed sc_id_mismatch sc_protect sc_readback_luks sc_readback_name sc_nofallback sc_poll_bound sc_poll_slow sc_poll_wall sc_record_bind sc_confirm_detach sc_check_binding sc_identity_no_phase sc_dad sc_inflight_report sc_phases_bare sc_octal_w4 sc_octal_w7; do
  "$s" || ctl_bad+=" $s"
done
[ -z "$ctl_bad" ] && pass "N-control: every named scenario is GREEN against the pristine helper" || fail "N-control: scenario(s) red against the pristine helper:$ctl_bad"

# =====================================================================================================
_REACHED_VERDICT=1
printf '\n=== %d passed, %d failed (%d mutants) ===\n' "$passes" "$fails" "$MUTANTS_RUN"
if [ "$fails" -gt 0 ]; then
  printf 'FAILED:\n'; printf '  - %s\n' "${FAILURES[@]}"
  exit 1
fi
[ "$passes" -ge 318 ] || { printf 'FAIL: only %d rows executed (floor 318)\n' "$passes"; exit 1; }
exit 0
