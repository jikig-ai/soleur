#!/usr/bin/env bash
# Fixture suite for scripts/followthroughs/dispatch-recovery-sweeper-11211.sh, a NOTIFY-ONLY probe: it may exit
# only 2 (NOT YET), 3 (CANNOT ESTABLISH), 5 (ACTION REQUIRED) or 78 (xtrace refusal), never 0 or 1, on EVERY path.
#
# No network: `curl` is a PATH stub that records its argv, its stdin config and its -d payload, and answers per
# URL (the ENQ Sentry read, the STALE Sentry read, the Supabase read). Registered EXPLICITLY in scripts/test-all.sh
# (scripts/followthroughs/*.test.sh is not in SUITE_GLOBS).
#
# INSTRUMENT SELF-TEST. Before any fixture row, check/has/hasnt are driven with known-true and known-false inputs; a
# helper that cannot tell them apart aborts the run (rc 4, `INSTRUMENT SELF-TEST FAILED`). The battery proves that
# detection by neutering each helper in a copy of THIS file.
#
# MUTATION BATTERY. After the fixture rows the suite mutates a scratch copy of the probe at the `# [mut:NAME]` tag lines
# (or at any unique text) and re-runs itself against the mutant (FT_INNER=1). The crediting rule (a named `FAIL: <fragment>`
# line, never a bare non-zero exit) and the instrument self-test live in scripts/lib/mutation-harness.sh, whose scorer is pinned
# by the `scorer:` controls at the head of the battery.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${FT_REPO:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SUT="${FT_SUT:-$SCRIPT_DIR/dispatch-recovery-sweeper-11211.sh}"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT:?}"' EXIT

PASS=0; FAIL=0; LEDGER="$ROOT/ledger"; : > "$LEDGER"
ok()    { PASS=$((PASS + 1)); printf 'ok\t%s\n' "$1" >> "$LEDGER"; echo "  PASS: $1"; }
bad()   { FAIL=$((FAIL + 1)); printf 'bad\t%s\n' "$1" >> "$LEDGER"; echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3]" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected [$3] present" ;; *) ok "$1" ;; esac; }

MH_LIB="$REPO/scripts/lib/mutation-harness.sh"
[ -f "$MH_LIB" ] || { echo "mutation-harness lib missing: $MH_LIB"; exit 4; }
# shellcheck source=../lib/mutation-harness.sh
source "$MH_LIB"
instrument_selftest

NOW=1790000000
ST_TOK="sentrytok-AAAA1111"
SB_TOK="sbtok-BBBB2222"
CANARY="CANARY-BODY-7f3a9c"

STUBDIR="$ROOT/bin"; mkdir -p "$STUBDIR"
cat > "$STUBDIR/curl" <<'STUB'
#!/usr/bin/env bash
# PATH stub for curl. Records argv (one arg per line), the stdin config, the -d payload, any TLS-subverting env; answers per URL.
# STRICT about argv: a request that lacks any of the pinned flags (--disable, --noproxy '*', -sS, --max-time 30,
# -w '%{http_code}', --config -, -o <file>) is REFUSED (exit 64, nothing on stdout, one line in $STUB_REFUSE, which the
# suite asserts empty), so a probe that drops one of them cannot pass by the stub quietly answering anyway.
{ for a in "$@"; do printf '%s\n' "$a"; done; echo '---CALL---'; } >> "$STUB_ARGV"
env | grep -E '^(SSLKEYLOGFILE|CURL_CA_BUNDLE|SSL_CERT_FILE|SSL_CERT_DIR|CURL_HOME|HOSTALIASES|LOCALDOMAIN|RES_OPTIONS)=' >> "$STUB_TLS" || true
args=("$@"); url=""; out=""; data=""; hascfg=0; pinned=0
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i + 1))]}" ;;
    -d) data="${args[$((i + 1))]}" ;;
    --config) if [ "${args[$((i + 1))]}" = - ]; then hascfg=1; fi ;;
    --disable|-sS) pinned=$((pinned + 1)) ;;
    --noproxy) if [ "${args[$((i + 1))]}" = '*' ]; then pinned=$((pinned + 1)); fi ;;
    --max-time) if [ "${args[$((i + 1))]}" = 30 ]; then pinned=$((pinned + 1)); fi ;;
    -w) if [ "${args[$((i + 1))]}" = '%{http_code}' ]; then pinned=$((pinned + 1)); fi ;;
    https://*) url="${args[$i]}" ;;
  esac
done
if [ "$pinned" != 5 ] || [ "$hascfg" != 1 ] || [ -z "$out" ] || [ -z "$url" ]; then
  printf 'refused: pinned=%s/5 config=%s out=%s url=%s\n' "$pinned" "$hascfg" "${out:+set}" "${url:+set}" >> "$STUB_REFUSE"
  exit 64
fi
cfg=""; [ "$hascfg" = 1 ] && cfg="$(cat)"
printf '%s\t%s\n' "$url" "$cfg" >> "$STUB_CFG"
case "$url" in
  *sentry.io*inngest-replay-stale*) kind=stale;    code="${STUB_STALE_CODE:-200}"; bodyf="${STUB_STALE_BODY:-}" ;;
  *sentry.io*)                      kind=enq;      code="${STUB_ENQ_CODE:-200}";   bodyf="${STUB_ENQ_BODY:-}" ;;
  *https://api.supabase.com*)       kind=supabase; code="${STUB_SB_CODE:-200}";    bodyf="${STUB_SB_BODY:-}"; printf '%s' "$data" > "$STUB_DATA" ;;
  *) kind=other; code=404; bodyf="" ;;
esac
case "${STUB_FAIL:-}" in
  all|"$kind") printf '000'; exit 7 ;;
  sentry) case "$kind" in enq|stale) printf '000'; exit 7 ;; esac ;;
esac
[ -n "$out" ] && { [ -n "$bodyf" ] && [ -f "$bodyf" ] && cat "$bodyf" > "$out" || : > "$out"; }
printf '%s' "$code"
STUB
chmod +x "$STUBDIR/curl"

RCS="$ROOT/rcs"; : > "$RCS"; : > "$ROOT/refused"   # refused is cumulative over the WHOLE suite (asserted empty before the battery)
OUT=""; RC=0
# run: env knobs ST / SB (tokens; unset = default, empty = empty), NOWV (NOW_EPOCH), ENQ_BODY / STALE_BODY / SB_BODY (file paths), codes, FAILKIND
run() {
  RC=0
  rm -f "$ROOT/argv" "$ROOT/cfg" "$ROOT/data" "$ROOT/tls"; : > "$ROOT/argv"; : > "$ROOT/cfg"; : > "$ROOT/tls"
  OUT="$(env -i PATH="$STUBDIR:$PATH" HOME="$ROOT" TMPDIR="$ROOT" NOW_EPOCH="${NOWV-$NOW}" STUB_REFUSE="$ROOT/refused" \
    STUB_ARGV="$ROOT/argv" STUB_CFG="$ROOT/cfg" STUB_DATA="$ROOT/data" STUB_TLS="$ROOT/tls" \
    STUB_ENQ_BODY="${ENQ_BODY:-}" STUB_ENQ_CODE="${ENQ_CODE:-200}" \
    STUB_STALE_BODY="${STALE_BODY:-$ROOT/stale0.json}" STUB_STALE_CODE="${STALE_CODE:-200}" \
    STUB_SB_BODY="${SB_BODY:-}" STUB_SB_CODE="${SB_CODE:-200}" STUB_FAIL="${FAILKIND:-}" \
    SSLKEYLOGFILE="$ROOT/keys" CURL_CA_BUNDLE="$ROOT/ca" SSL_CERT_FILE="$ROOT/ca" SSL_CERT_DIR="$ROOT" CURL_HOME="$ROOT" \
    HOSTALIASES="$ROOT/aliases" LOCALDOMAIN=evil.example RES_OPTIONS=debug \
    SENTRY_ACTIONS_RO_TOKEN="${ST-$ST_TOK}" SUPABASE_ACCESS_TOKEN="${SB-$SB_TOK}" \
    ${XENV:+"$XENV"} bash ${XBASH:+"$XBASH"} "$SUT" 2>&1 </dev/null)" || RC=$?
  echo "$RC" >> "$RCS"
}
calls() { grep -c '^---CALL---$' "$ROOT/argv" 2>/dev/null || true; }
reset_knobs() { unset ST SB NOWV ENQ_BODY STALE_BODY SB_BODY FAILKIND XENV XBASH; ENQ_CODE=200; STALE_CODE=200; SB_CODE=200; }

mk_events() {  # mk_events <file> <N>: a Sentry events page with N events
  local n="$2" i items=""
  for ((i = 0; i < n; i++)); do items="${items}${items:+,}{\"id\":\"e$i\",\"timestamp\":\"2026-10-27T10:00:00+00:00\"}"; done
  printf '{"data":[%s],"meta":{}}' "$items" > "$1"
}
mk_events "$ROOT/stale0.json" 0
enq_n()   { mk_events "$ROOT/enq.json" "$1"; ENQ_BODY="$ROOT/enq.json"; }       # N ENQ events
stale_n() { mk_events "$ROOT/stale.json" "$1"; STALE_BODY="$ROOT/stale.json"; } # N STALE events
mk_sb() { printf '%s' "$1" > "$ROOT/sb.json"; SB_BODY="$ROOT/sb.json"; }
sb_counts() { mk_sb "[{\"recoverable\":$1,\"aged_out\":$2}]"; }
all_zero() { reset_knobs; enq_n 0; sb_counts 0 0; }   # the normal quiet state; callers then override one knob


reset_knobs
echo "=== dispatch-recovery-sweeper-11211.sh tests ==="

# 1. the normal daily state: nothing fired, nothing stranded
all_zero; run
check "no events, no rows: exit 2 (NOT YET)" 2 "$RC"
has "NOT YET: names the verdict" "$OUT" "NOT YET"
has "NOT YET: counts printed (enqueue)" "$OUT" "enqueue_events=0"
has "NOT YET: counts printed (stale)" "$OUT" "replay_stale_events=0"
has "NOT YET: counts printed (recoverable)" "$OUT" "recoverable=0"
has "NOT YET: counts printed (aged_out)" "$OUT" "aged_out=0"
check "all three sources were read (ENQ, STALE, Supabase)" 3 "$(calls)"

# 2. each criterion alone is not enough, except STALE which counts toward both (the fail-safe direction)
reset_knobs; enq_n 3; sb_counts 0 0; run
check "criterion 1 alone via ENQ (events, no stranded rows): exit 2" 2 "$RC"
reset_knobs; enq_n 0; sb_counts 4 0; run
check "criterion 2 alone (recoverable rows, no events): exit 2" 2 "$RC"
reset_knobs; enq_n 0; sb_counts 0 3; run
check "aged-out rows cannot fire alone: exit 2" 2 "$RC"
reset_knobs; enq_n 0; stale_n 1; sb_counts 0 0; run
check "a STALE event alone (no ENQ, no rows) fires: exit 5" 5 "$RC"
has "STALE alone: the stale count is printed" "$OUT" "replay_stale_events=1"
has "STALE alone: the enqueue count is printed apart" "$OUT" "enqueue_events=0"
reset_knobs; enq_n 0; stale_n 2; sb_counts 5 5; run
check "STALE plus stranded rows, no ENQ: exit 5" 5 "$RC"

# 3. both criteria: ACTION REQUIRED, in either bucket, and never 0
reset_knobs; enq_n 1; sb_counts 1 0; run
check "ENQ and a recoverable row: exit 5" 5 "$RC"
has "ACTION REQUIRED: named" "$OUT" "ACTION REQUIRED"
has "ACTION REQUIRED: says the tracker is not closed by the probe" "$OUT" "NOT closed by the probe"
reset_knobs; enq_n 2; sb_counts 0 1; run
check "ENQ and an aged-out row: exit 5" 5 "$RC"
has "aged-out count printed" "$OUT" "aged_out=1"
reset_knobs; enq_n 2; mk_sb '[{"recoverable":"2","aged_out":"5"}]'; run
check "counts delivered as strings are accepted: exit 5" 5 "$RC"
has "string counts: parsed value printed" "$OUT" "recoverable=2"
reset_knobs; enq_n 1; stale_n 1; sb_counts 1 1; run
check "ENQ, STALE and rows together: exit 5" 5 "$RC"
has "all four counts printed separately" "$OUT" "enqueue_events=1 replay_stale_events=1 criterion2 recoverable=1 aged_out=1"

# 4. every read failure is CANNOT ESTABLISH, whichever source fails and whatever the others say
reset_knobs; enq_n 0; sb_counts 0 0; ENQ_CODE=500; run
check "ENQ read 500, the rest fine: exit 3" 3 "$RC"; has "ENQ 500: fixed reason with status" "$OUT" "Sentry read failed (http=500)"
check "the first failing read exits at once (one request made)" 1 "$(calls)"
reset_knobs; enq_n 0; sb_counts 0 0; STALE_CODE=500; run
check "STALE read 500 after a quiet ENQ read: exit 3, not 2" 3 "$RC"
reset_knobs; enq_n 5; sb_counts 1 1; STALE_CODE=403; run
check "STALE 403 while ENQ and rows say 'fire': exit 3, never 5" 3 "$RC"
reset_knobs; enq_n 0; sb_counts 0 0; SB_CODE=500; run
check "supabase 500 AFTER compliant sentry reads of 0: exit 3, not 2 (the last source is read too)" 3 "$RC"
has "supabase 500: fixed reason with status" "$OUT" "Supabase read failed (http=500)"
check "supabase 500: all three requests were made" 3 "$(calls)"
reset_knobs; enq_n 2; sb_counts 1 1; SB_CODE=500; run
check "criteria 'met' on sentry but supabase 500: exit 3, never 5" 3 "$RC"
reset_knobs; enq_n 2; sb_counts 1 1; ENQ_CODE=403; run
check "ENQ 403: exit 3" 3 "$RC"
reset_knobs; enq_n 0; sb_counts 0 0; SB_CODE=401; run
check "supabase 401: exit 3" 3 "$RC"
reset_knobs; enq_n 0; sb_counts 0 0; SB_CODE=201; run
check "supabase 201 (the query endpoint's success code) is accepted: exit 2" 2 "$RC"
for kind in enq stale supabase sentry all; do
  reset_knobs; enq_n 0; sb_counts 0 0; FAILKIND=$kind; run
  check "curl transport failure on $kind: exit 3" 3 "$RC"
done

# 5. empty and malformed bodies are never read as zero rows
reset_knobs; sb_counts 0 0; : > "$ROOT/empty.json"; ENQ_BODY="$ROOT/empty.json"; run
check "ENQ 200 with an empty body: exit 3 (a probe reading 0 from nothing is vacuous)" 3 "$RC"
reset_knobs; enq_n 0; sb_counts 0 0; STALE_BODY="$ROOT/empty.json"; run
check "STALE 200 with an empty body: exit 3" 3 "$RC"
reset_knobs; sb_counts 0 0; printf '{"meta":{}}' > "$ROOT/nodata.json"; ENQ_BODY="$ROOT/nodata.json"; run
check "ENQ 200 with no data field: exit 3" 3 "$RC"
reset_knobs; enq_n 0; sb_counts 0 0; STALE_BODY="$ROOT/nodata.json"; run
check "STALE 200 with no data field: exit 3" 3 "$RC"
reset_knobs; sb_counts 0 0; printf '{"data":null}' > "$ROOT/nulldata.json"; ENQ_BODY="$ROOT/nulldata.json"; run
check "ENQ 200 with data:null: exit 3" 3 "$RC"
reset_knobs; enq_n 0; : > "$ROOT/empty2.json"; SB_BODY="$ROOT/empty2.json"; run
check "supabase 200 with an empty body: exit 3" 3 "$RC"
reset_knobs; enq_n 0; mk_sb '[]'; run
check "supabase 200 with zero rows (an aggregate always returns one): exit 3" 3 "$RC"
reset_knobs; enq_n 0; mk_sb '{"recoverable":0,"aged_out":0}'; run
check "supabase 200 with an object, not an array: exit 3" 3 "$RC"
reset_knobs; enq_n 0; mk_sb '[{"recoverable":"x","aged_out":0}]'; run
check "supabase non-numeric count: exit 3" 3 "$RC"
reset_knobs; enq_n 0; mk_sb '[{"recoverable":0}]'; run
check "supabase row missing aged_out: exit 3" 3 "$RC"
reset_knobs; enq_n 0; mk_sb '[{"recoverable":-1,"aged_out":0}]'; run
check "supabase negative count: exit 3" 3 "$RC"
# a count with a leading zero is invalid octal inside bash (( )); it must be refused, never fall through to a verdict
reset_knobs; enq_n 0; mk_sb '[{"recoverable":"08","aged_out":0}]'; run
check "supabase count with a leading zero (\"08\"): exit 3, not a fall-through to NOT YET" 3 "$RC"
has "leading-zero count: the fixed unparseable reason" "$OUT" "Supabase response unparseable"
hasnt "leading-zero count: no bash arithmetic error reaches the public comment" "$OUT" "value too great for base"
hasnt "leading-zero count: no bash error text at all" "$OUT" "((:"
reset_knobs; enq_n 1; mk_sb '[{"recoverable":0,"aged_out":"007"}]'; run
check "supabase aged_out \"007\": exit 3, never 5" 3 "$RC"
reset_knobs; enq_n 0; mk_sb '[{"recoverable":"00","aged_out":0}]'; run
check "supabase count \"00\": exit 3" 3 "$RC"
reset_knobs; enq_n 0; sb_counts 10 0; run
check "supabase count 10 (a zero that is not leading) is accepted: exit 2" 2 "$RC"
has "count 10 is printed as 10" "$OUT" "recoverable=10"

# 6. PUBLIC-LEAK: a non-2xx body or a malformed body is never echoed (the sweeper republishes the tail publicly)
for combo in "enq-500:500:200:200" "stale-500:200:500:200" "sb-500:200:200:500" "enq-403:403:200:200" "sb-401:200:200:401"; do
  reset_knobs; IFS=: read -r nm ecode scode bcode <<<"$combo"
  printf '{"detail":"%s","token":"%s","echo":"%s"}' "$CANARY" "$ST_TOK" "$SB_TOK" > "$ROOT/canary.json"
  ENQ_BODY="$ROOT/canary.json"; STALE_BODY="$ROOT/canary.json"; SB_BODY="$ROOT/canary.json"; ENQ_CODE="$ecode"; STALE_CODE="$scode"; SB_CODE="$bcode"
  case "$nm" in sb-*|stale-*) enq_n 0 ;; esac
  case "$nm" in enq-*|stale-*) sb_counts 0 0 ;; esac
  case "$nm" in sb-*) stale_n 0 ;; esac
  run
  check "$nm: exit 3" 3 "$RC"
  hasnt "$nm: body canary absent from output" "$OUT" "$CANARY"
  hasnt "$nm: sentry token absent from output" "$OUT" "$ST_TOK"
  hasnt "$nm: supabase token absent from output" "$OUT" "$SB_TOK"
done
reset_knobs; printf 'not json %s' "$CANARY" > "$ROOT/garbage.json"; ENQ_BODY="$ROOT/garbage.json"; sb_counts 0 0; run
check "garbage 200 body on ENQ: exit 3" 3 "$RC"; hasnt "garbage ENQ body not echoed" "$OUT" "$CANARY"
reset_knobs; enq_n 0; STALE_BODY="$ROOT/garbage.json"; sb_counts 0 0; run
check "garbage 200 body on STALE: exit 3" 3 "$RC"; hasnt "garbage STALE body not echoed" "$OUT" "$CANARY"
reset_knobs; enq_n 0; printf 'not json %s' "$CANARY" > "$ROOT/garbage2.json"; SB_BODY="$ROOT/garbage2.json"; run
check "garbage 200 body on supabase: exit 3" 3 "$RC"; hasnt "garbage supabase body not echoed" "$OUT" "$CANARY"

# 7. credentials: shape-checked first, never read when unusable, never on argv, each only to its own host
reset_knobs; enq_n 0; sb_counts 0 0; ST=""; run
check "empty SENTRY_ACTIONS_RO_TOKEN: exit 3" 3 "$RC"; check "empty sentry token: no request made" 0 "$(calls)"
reset_knobs; enq_n 0; sb_counts 0 0; SB=""; run
check "empty SUPABASE_ACCESS_TOKEN: exit 3" 3 "$RC"; check "empty supabase token: no request made" 0 "$(calls)"
reset_knobs; enq_n 0; sb_counts 0 0; ST=$'tok\nurl = "https://evil.example/"'; run
check "newline in the sentry token (curl-config injection): exit 3" 3 "$RC"; check "malformed token: no request made" 0 "$(calls)"
reset_knobs; enq_n 0; sb_counts 0 0; SB='tok"x'; run
check "quote in the supabase token: exit 3" 3 "$RC"; check "quote in token: no request made" 0 "$(calls)"
all_zero; run
argv="$(cat "$ROOT/argv")"
hasnt "sentry token never on curl argv" "$argv" "$ST_TOK"
hasnt "supabase token never on curl argv" "$argv" "$SB_TOK"
sentry_cfg="$(grep 'sentry.io/api/0/organizations/jikigai-eu/events/' "$ROOT/cfg")"
check "both Sentry reads carry the sentry token on the stdin config" 2 "$(printf '%s\n' "$sentry_cfg" | grep -cF "header = \"Authorization: Bearer $ST_TOK\"")"
has "supabase token rides the stdin config to the supabase host" "$(grep 'api.supabase.com/v1/projects/ifsccnjhymdmidffkzhl/database/query' "$ROOT/cfg")" "header = \"Authorization: Bearer $SB_TOK\""
hasnt "sentry token never sent to supabase" "$(grep 'api.supabase.com' "$ROOT/cfg")" "$ST_TOK"
hasnt "supabase token never sent to sentry" "$(grep 'sentry.io' "$ROOT/cfg")" "$SB_TOK"
has "ENQ URL pins its query" "$argv" "query=feature%3Aspawn-agent%20op%3Ainngest-enqueue&"
has "STALE URL pins its query" "$argv" "query=feature%3Aspawn-agent%20op%3Ainngest-replay-stale&"
check "two plain Sentry reads, not one op:[a,b] read" 2 "$(grep -c 'sentry.io' "$ROOT/cfg")"
hasnt "no read ORs the two ops" "$argv" "%5B"
has "sentry URLs pin the window start (2026-10-26)" "$argv" "start=2026-10-26T00%3A00%3A00"
has "sentry URLs pin the window end to the clock" "$argv" "end=$(date -u -d "@$NOW" '+%Y-%m-%dT%H%%3A%M%%3A%S')"
has "sentry URLs read the errors dataset" "$argv" "dataset=errors"
# the TLS-subverting environment never reaches curl (it would let the actor who sets it read the bearer off the wire)
check "no TLS-subverting environment variable reaches curl (all three requests)" "" "$(cat "$ROOT/tls")"
check "the source unsets the TLS-subverting environment before any token is sent" 1 "$(grep -cE '^unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS' "$SUT")"
# every request is bounded
check "every request carries --max-time 30" 3 "$(grep -A1 -x -- '--max-time' "$ROOT/argv" | grep -cx '30')"
# every request carries -w '%{http_code}' (it is how the probe learns the status; the stub is strict about it, see its header)
check "every request carries -w '%{http_code}'" 3 "$(grep -A1 -x -- '-w' "$ROOT/argv" | grep -cxF '%{http_code}')"
check "the strict curl stub refused no request so far (every request carried the pinned flag set)" "" "$(cat "$ROOT/refused")"
# the stub's own strictness (instrument check): a request without -w '%{http_code}' IS refused (exit 64, logged, no stdout)
stub_rc=0; stub_out="$(env PATH="$STUBDIR:$PATH" STUB_ARGV="$ROOT/argv.t" STUB_TLS="$ROOT/tls.t" STUB_REFUSE="$ROOT/refused.t" STUB_CFG="$ROOT/cfg.t" \
  curl --disable --noproxy '*' -sS --max-time 30 -o "$ROOT/o.t" --config - https://example.invalid/ 2>/dev/null </dev/null)" || stub_rc=$?
check "instrument: the curl stub refuses a request lacking -w '%{http_code}' (exit 64)" 64 "$stub_rc"
check "instrument: a refused request prints nothing on stdout" "" "$stub_out"
check "instrument: a refused request is logged" 1 "$(grep -c '^refused:' "$ROOT/refused.t" 2>/dev/null || true)"
check "the fetch line pins --max-time 30" 1 "$(grep -cE '^[[:space:]]*HTTP="\$\(curl .*--max-time 30 ' "$SUT")"

# 7b. OFFLINE: the Sentry tags the probe queries are the tags the send route emits (a mistyped tag reads 0 forever)
ROUTE="$REPO/apps/web-platform/app/api/dashboard/today/[id]/send/route.ts"
route_tags="$(grep -oE '(feature|op): "(spawn-agent|inngest-enqueue|inngest-replay-stale)"' "$ROUTE" | sort -u | tr '\n' ';')"
check "the send route emits feature spawn-agent and ops inngest-enqueue and inngest-replay-stale" 'feature: "spawn-agent";op: "inngest-enqueue";op: "inngest-replay-stale";' "$route_tags"
url_tags="$(cut -f1 "$ROOT/cfg" | grep 'sentry.io' | sed -E 's/.*[?&]query=([^&]*)(&.*)?$/\1/; s/%3A/:/g; s/%20/\n/g' | sed -E 's/^([a-z]+):(.*)$/\1: "\2"/' | sort -u | tr '\n' ';')"
check "every tag the probe queries is a tag the route emits, and each route tag is queried" "$route_tags" "$url_tags"
check "each Sentry URL carries exactly one op term" "1 1 " "$(cut -f1 "$ROOT/cfg" | grep 'sentry.io' | while read -r u; do printf '%s ' "$(printf '%s' "$u" | grep -o '%20op%3A' | wc -l)"; done)"

# 7c. NOW_EPOCH: a positive decimal without a leading zero (a leading zero is OCTAL inside (( )))
for bad_now in 0 017 08 -5 1e9 12x; do
  all_zero; NOWV="$bad_now"; run; reset_knobs
  check "NOW_EPOCH=$bad_now: exit 3" 3 "$RC"; has "NOW_EPOCH=$bad_now: the fixed reason" "$OUT" "unusable NOW_EPOCH"
  check "NOW_EPOCH=$bad_now: no request made" 0 "$(calls)"
done

# 8. xtrace: refuse (78) BEFORE any credential is read or any request is made
all_zero; XBASH="-x"; run
check "xtrace with live credentials: exit 78" 78 "$RC"; check "xtrace: no request made" 0 "$(calls)"
hasnt "xtrace: sentry token absent from output" "$OUT" "$ST_TOK"; hasnt "xtrace: supabase token absent from output" "$OUT" "$SB_TOK"
all_zero; ST=""; SB=""; XBASH="-x"; run
check "xtrace with NO credentials still refuses: exit 78 (before any credential read)" 78 "$RC"

# 9. the Supabase query is ONE literal: pinned text, ^SELECT, no `;`, no interpolated value
PINNED_QUERY="SELECT count(*) FILTER (WHERE s.clicked_at >= now() - interval '23 hours') AS recoverable, count(*) FILTER (WHERE s.clicked_at < now() - interval '23 hours') AS aged_out FROM public.action_sends s JOIN public.messages m ON m.id = s.message_id WHERE s.acknowledged_at IS NULL AND s.failure_reason IS NULL AND s.undone_at IS NULL AND s.cancellation_requested_at IS NULL AND m.status = 'draft' AND s.clicked_at < now() - interval '1 hour'"
all_zero; run
payload="$(cat "$ROOT/data" 2>/dev/null)"
q="$(printf '%s' "$payload" | jq -r '.query' 2>/dev/null)"
check "payload is a JSON object with exactly one key" 1 "$(printf '%s' "$payload" | jq -r 'keys | length' 2>/dev/null)"
check "supabase query equals the pinned literal" "$PINNED_QUERY" "$q"
case "$q" in SELECT*) ok "supabase query starts with SELECT" ;; *) bad "supabase query starts with SELECT" ;; esac
case "$q" in *';'*) bad "supabase query has no semicolon" ;; *) ok "supabase query has no semicolon" ;; esac
for v in "$ST_TOK" "$SB_TOK" "11211" "$NOW"; do hasnt "supabase query carries no environment- or issue-derived value ($v)" "$q" "$v"; done
for w in INSERT UPDATE DELETE DROP ALTER CREATE TRUNCATE GRANT; do
  case " $(printf '%s' "$q" | tr '[:lower:]' '[:upper:]') " in *" $w "*) bad "supabase query has no $w keyword" ;; *) ok "supabase query has no $w keyword" ;; esac
done
has "query keeps the unacknowledged predicate" "$q" "s.acknowledged_at IS NULL"
has "query keeps the draft predicate" "$q" "m.status = 'draft'"
has "query has no upper bound on age (only the 1 h floor)" "$q" "s.clicked_at < now() - interval '1 hour'"
# the `23 hours` literal is REPLAY_MAX_AGE_MS (decide-replay.ts), which is what makes a bucket 'recoverable'
DECIDE="$REPO/apps/web-platform/server/action-sends/decide-replay.ts"
decide_expr="$(sed -n 's/^export const REPLAY_MAX_AGE_MS = \([0-9 *]*\);.*$/\1/p' "$DECIDE")"
case "$decide_expr" in
  ''|*[!0-9\ \*]*) decide_hours="unparseable [$decide_expr]" ;;
  *) decide_hours="$(( $decide_expr / 3600000 ))" ;;
esac
sql_hours="$(grep -oE "interval '[0-9]+ hours'" "$SUT" | grep -oE '[0-9]+' | sort -u | tr '\n' ' ')"
check "every 'N hours' literal in the SQL equals REPLAY_MAX_AGE_MS in decide-replay.ts (23 h)" "$decide_hours " "$sql_hours"
has "decide-replay.ts carries the back-pointer to this probe next to REPLAY_MAX_AGE_MS" "$(grep -B12 '^export const REPLAY_MAX_AGE_MS' "$DECIDE")" "scripts/followthroughs/dispatch-recovery-sweeper-11211.sh"

# 10. exit vocabulary: every rc observed so far is in {2,3,5,78}; the source cannot exit 0 or 1 anywhere
badrc="$(grep -vxE '2|3|5|78' "$RCS" | sort -u | tr '\n' ' ')"
check "every observed exit status is in {2,3,5,78}" "" "$badrc"
src="$(cat "$SUT" 2>/dev/null)"
exits="$(grep -oE '(^|[^A-Za-z_])exit [0-9]+' "$SUT" 2>/dev/null | grep -oE '[0-9]+$' | sort -u | tr '\n' ' ')"
check "the source names only exit 2, 3, 5 and 78 (a literal exit 0 or 1 cannot exist)" "2 3 5 78 " "$exits"
qform="$(grep -nE '\$\{[A-Za-z_0-9]+:\?' "$SUT" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
check "no \${VAR:?} form on an executable line (it aborts with status 1)" "" "$qform"
case "$src" in *'head -c'*) bad "no body echo via head -c" ;; *) ok "no body echo via head -c" ;; esac
leaky="$(grep -nE '\$\{?(BODY|RESP)\}?|cat +"?\$\{?TMP' "$SUT" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
check "no line echoes a response body" "" "$leaky"
authlines="$(grep -nE 'Authorization:|Bearer' "$SUT" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | grep -v '< <(printf' || true)"
check "Authorization/Bearer appear only inside a stdin-config process substitution" "" "$authlines"
argvcred="$(grep -nE 'curl' "$SUT" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | grep -E '(^|[[:space:]])(-u|--user)[[:space:]]|-H +"?Authorization' || true)"
check "no -u / --user / -H Authorization credential on argv" "" "$argvcred"

# 10b. the followthrough-convention.md NOTIFY-ONLY rule: refusal first, the rc-remapping EXIT trap directly after it
check "exactly one trap statement" 1 "$(grep -c '^trap ' "$SUT")"
check "no exec / kill on an executable line (either bypasses the EXIT remap)" "" "$(grep -nE '(^|[^A-Za-z_-])(exec|kill)[[:space:]]' "$SUT" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
refusal_start="$(awk '/^case "\$-" in$/ { print NR; exit }' "$SUT")"
refusal_end="$(awk '/^case "\$-" in$/ { s = 1 } s && /^esac$/ { print NR; exit }' "$SUT")"
trap_ln="$(grep -n '^trap ' "$SUT" | head -n 1 | cut -d: -f1)"
has "the xtrace refusal case exits 78" "$(sed -n "${refusal_start:-0},${refusal_end:-0}p" "$SUT")" "exit 78"
check "nothing between the xtrace refusal and the trap (the trap is the next line)" "$(( ${refusal_end:-0} + 1 ))" "${trap_ln:-none}"
first_cred="$(grep -nE 'SENTRY_ACTIONS_RO_TOKEN|SUPABASE_ACCESS_TOKEN|NOW_EPOCH|mktemp' "$SUT" | grep -vE '^[0-9]+:[[:space:]]*#' | head -n 1 | cut -d: -f1)"
check "the xtrace refusal precedes the first credential reference" yes "$([ "${refusal_end:-999999}" -lt "${first_cred:-0}" ] && echo yes || echo no)"

# 10c. the enrollable directive: ONE `<!-- soleur:followthrough ... -->` line in the header
dir_lines="$(grep -E '^#[[:space:]]+<!-- soleur:followthrough ' "$SUT" || true)"
check "the header carries exactly one single-line follow-through directive" 1 "$(printf '%s\n' "$dir_lines" | grep -c .)"
check "the directive names this script, earliest= and secrets= and closes on the same line" 1 "$(printf '%s\n' "$dir_lines" | grep -cE 'script=scripts/followthroughs/dispatch-recovery-sweeper-11211\.sh earliest=[0-9]{4}-[0-9]{2}-[0-9]{2}T00:00:00Z secrets=SENTRY_ACTIONS_RO_TOKEN,SUPABASE_ACCESS_TOKEN -->$')"
check "the directive's script exists in the repo" yes "$([ -f "$REPO/scripts/followthroughs/dispatch-recovery-sweeper-11211.sh" ] && echo yes || echo no)"

# 11. the EXIT trap keeps a stray status inside the vocabulary (a fault injected at the first sentry read exits 1 in the body)
cat > "$ROOT/fault.sh" <<'FAULT'
trap 'case "$BASH_COMMAND" in read_sentry*) exit 1 ;; esac' DEBUG
FAULT
all_zero; XENV="BASH_ENV=$ROOT/fault.sh"; run
check "an unexpected internal exit status is mapped to 3 by the EXIT trap" 3 "$RC"
reset_knobs
check "the strict curl stub refused no request in the whole suite" "" "$(cat "$ROOT/refused")"

# shellcheck disable=SC2034  # read by mh_floor in the sourced lib
FIX_N="$(wc -l < "$LEDGER")"
if run_battery "${1:-}"; then
  echo "=== mutation battery ==="
  export FT_REPO="$REPO"
  MUT="$ROOT/mut"; mkdir -p "$MUT"
  ctl=0; FT_INNER=1 FT_SUT="$SUT" bash "$SELF" >/dev/null 2>&1 || ctl=$?
  check "battery control: the pristine probe passes the inner suite (rc 0)" 0 "$ctl"
  # Scorer controls (#11520): mh_caught decides whether a mutant was caught FOR THE CLAIMED REASON. Each row calls it
  # directly in THIS shell (an ok/bad inside a subshell would lose its PASS/FAIL increment and trip LEDGER MISMATCH) and
  # emits exactly one check. The logs are synthetic, never recorded from a real run.
  printf '  PASS: other\n  FAIL: frag-1 and trailing text\n' > "$MUT/sc-right.log"
  printf '  PASS: frag-1\n'                                > "$MUT/sc-pass-only.log"
  printf '  FAIL: a different row\n'                       > "$MUT/sc-other.log"
  printf '  detail: FAIL: frag-1\n'                        > "$MUT/sc-mid.log"
  : > "$MUT/sc-empty.log"
  sc_verdict() { mh_caught "$1" "$2" && echo yes || echo no; }
  check "scorer: a FAIL line starting with the fragment and trailing text is caught" yes "$(sc_verdict frag-1 "$MUT/sc-right.log")"
  # label|fragment|log: every row must come back NOT caught
  sc_no=(
    "a PASS-only log|frag-1|sc-pass-only"
    "a FAIL line for a different row|frag-1|sc-other"
    "an empty log|frag-1|sc-empty"
    "a fragment longer than the FAIL label (strict prefix of the fragment)|frag-1 and trailing text plus more|sc-right"
    "a FAIL quoted mid-line|frag-1|sc-mid"
    "a regex-metacharacter fragment (literal match only)|fr.g-1|sc-right"
    "an empty fragment|-|sc-right"
  )
  for sc_row in "${sc_no[@]}"; do
    IFS='|' read -r sc_lbl sc_frag sc_log <<< "$sc_row"
    [ "$sc_frag" = "-" ] && sc_frag=""
    check "scorer: $sc_lbl is not caught" no "$(sc_verdict "$sc_frag" "$MUT/$sc_log.log")"
  done
  # Teeth: with the scorer overridden to always say yes, EVERY "not caught" control above comes back wrongly caught.
  sc_dead="$( ( mh_caught() { return 0; }; n=0
    for sc_row in "${sc_no[@]}"; do IFS='|' read -r _l sc_frag sc_log <<< "$sc_row"; [ "$sc_frag" = "-" ] && sc_frag=""
      mh_caught "$sc_frag" "$MUT/$sc_log.log" && n=$((n + 1)); done; echo "$n" ) )"
  check "scorer teeth: a dead scorer is caught wrongly-yes by all ${#sc_no[@]} negative controls" "${#sc_no[@]}" "${sc_dead:-0}"
  mutate_helper h1-check-always-ok     check  'check() { ok "$1"; }'
  mutate_helper h2-has-always-ok       has    'has() { ok "$1"; }'
  mutate_helper h3-hasnt-always-ok     hasnt  'hasnt() { ok "$1"; }'
  mutate_helper h4-check-always-bad    check  'check() { bad "$1"; }'
  mutate_helper h5-has-inverted        has    'has() { case "$2" in *"$3"*) bad "$1" ;; *) ok "$1" ;; esac; }'
  mutate_sub m1-action-exit-0          '[mut:action]'      'exit 5' 'exit 0' 'ENQ and a recoverable row: exit 5'
  mutate_run m2-sentry-fail-falls-through '[mut:sentry-fail]' '  [[ "$HTTP" == "200" ]] || { COUNT=0; return 0; }' 'ENQ read 500, the rest fine: exit 3'
  mutate_run m2b-trap-removed          '[mut:trap]'        ':' 'an unexpected internal exit status is mapped to 3 by the EXIT trap'
  mutate_sub m2c-statement-before-trap '[mut:trap]'        'trap ' $'FOO=1\ntrap ' 'nothing between the xtrace refusal and the trap'
  mutate_sub m2d-second-trap           '[mut:trap]'        '# [mut:trap]' $'# [mut:trap]\ntrap - EXIT' 'exactly one trap statement'
  mutate_run m3-short-circuit-after-enq '[mut:after-enq]'  '[[ "$ENQ" -eq 0 ]] && exit 2' 'a STALE event alone (no ENQ, no rows) fires: exit 5'
  mutate_run m3a-short-circuit-after-sentry '[mut:after-sentry]' '[[ "$ENQ" -eq 0 && "$STALE" -eq 0 ]] && exit 2' 'supabase 500 AFTER compliant sentry reads of 0: exit 3, not 2 (the last source is read too)'
  mutate_run m3b-sb-fail-ignored       '[mut:sb-fail]'     '  :' 'supabase 500 AFTER compliant sentry reads of 0: exit 3, not 2 (the last source is read too)'
  mutate_run m4-xtrace-refusal-dropped '[mut:xtrace]'      '  *x*) : ;;' 'xtrace with live credentials: exit 78'
  mutate_run m5a-body-echoed           '[mut:sentry-fail]' '  [[ "$HTTP" == "200" ]] || { cat "$TMP"; cannot "Sentry read failed (http=${HTTP})"; }' 'enq-500: body canary absent from output'
  mutate_run m5b-semicolon-in-sql      '[mut:query]'       "readonly QUERY=\"${PINNED_QUERY};\"" 'supabase query equals the pinned literal'
  mutate_sub m5b2-query-literal-changed '[mut:query]'      "interval '1 hour'" "interval '2 hour'" 'supabase query equals the pinned literal'
  mutate_sub m5b3-window-24h           '[mut:query]'       "interval '23 hours')" "interval '24 hours')" "every 'N hours' literal in the SQL equals REPLAY_MAX_AGE_MS in decide-replay.ts (23 h)"
  mutate_run m5c-token-on-argv         '[mut:fetch]'       '  HTTP="$(curl --disable --noproxy "*" -sS --max-time 30 -o "$TMP" -w "%{http_code}" -H "Authorization: Bearer $1" "${@:3}" --config - "$2" 2>/dev/null < <(printf "\n"))" || true' 'sentry token never on curl argv'
  mutate_sub m5c2-max-time-dropped     '[mut:fetch]'       '--max-time 30 ' '' 'every request carries --max-time 30'
  mutate_run m5d-sentry-parse-lenient  '[mut:sentry-parse]' '  [[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0' 'ENQ 200 with data:null: exit 3'
  mutate_run m5e-sb-parse-lenient      '[mut:sb-parse]'    '  [[ "$RECOVERABLE" =~ $COUNT_RE && "$AGED_OUT" =~ $COUNT_RE ]] || { RECOVERABLE=0; AGED_OUT=0; }' 'supabase non-numeric count: exit 3'
  mutate_sub m5f-octal-count-regex     '[mut:count-re]'    "'^(0|[1-9][0-9]{0,8})\$'" "'^[0-9]{1,9}\$'" 'supabase count with a leading zero ("08"): exit 3, not a fall-through to NOT YET'
  mutate_run m6-aged-out-fires-alone   '[mut:decision]'    'if (( (ENQ > 0 && RECOVERABLE > 0) || AGED_OUT > 0 || STALE > 0 )); then' 'aged-out rows cannot fire alone: exit 2'
  mutate_run m6a-or-instead-of-and     '[mut:decision]'    'if (( (ENQ > 0 || STALE > 0) || ((RECOVERABLE + AGED_OUT) > 0 || STALE > 0) )); then' 'criterion 1 alone via ENQ (events, no stranded rows): exit 2'
  mutate_run m6b-stale-not-criterion-2 '[mut:decision]'    'if (( (ENQ > 0 || STALE > 0) && (RECOVERABLE + AGED_OUT) > 0 )); then' 'a STALE event alone (no ENQ, no rows) fires: exit 5'
  mutate_run m6c-stale-not-criterion-1 '[mut:decision]'    'if (( ENQ > 0 && ((RECOVERABLE + AGED_OUT) > 0 || STALE > 0) )); then' 'STALE plus stranded rows, no ENQ: exit 5'
  mutate_run m6d-stale-ignored         '[mut:decision]'    'if (( ENQ > 0 && (RECOVERABLE + AGED_OUT) > 0 )); then' 'a STALE event alone (no ENQ, no rows) fires: exit 5'
  mutate_sub m5c3-w-http-code-dropped  '[mut:fetch]'       "-w '%{http_code}' " '' "every request carries -w '%{http_code}'"
  mutate_run m8a-sentry-token-unchecked '[mut:token-check-sentry]' ':' 'empty SENTRY_ACTIONS_RO_TOKEN: exit 3'
  mutate_run m8b-supabase-token-unchecked '[mut:token-check-supabase]' ':' 'empty SUPABASE_ACCESS_TOKEN: exit 3'
  mutate_sub m8c-now-epoch-octal-regex 'unusable NOW_EPOCH' '^[1-9][0-9]{0,15}$' '^[0-9]+$' 'NOW_EPOCH=017: exit 3'
  mutate_sub m9a-enq-tag-mistyped      '[mut:enq-url]'     'inngest-enqueue' 'inngest-enqeue' 'every tag the probe queries is a tag the route emits, and each route tag is queried'
  mutate_sub m9b-stale-tag-mistyped    '[mut:stale-url]'   'inngest-replay-stale' 'inngest-replay-staile' 'every tag the probe queries is a tag the route emits, and each route tag is queried'
  mutate_sub m9c-stale-reads-the-enq-op '[mut:stale-url]'  'inngest-replay-stale' 'inngest-enqueue' 'STALE URL pins its query'
  mutate_run m10-tls-unset-dropped     '[mut:tls-unset]'   ':' 'no TLS-subverting environment variable reaches curl (all three requests)'
  mutate_sub m11a-directive-bare-form  '<!-- soleur:followthrough script=' '<!-- soleur:followthrough' 'soleur:followthrough' 'the header carries exactly one single-line follow-through directive'
  mutate_sub m11b-directive-unclosed   '<!-- soleur:followthrough script=' ' -->' '' 'the directive names this script, earliest= and secrets= and closes on the same line'
fi

# Floors: MIN_FIXTURE is the real fixture-row count (a --no-battery run reaches it exactly); MIN_BATTERY the battery's.
MIN_FIXTURE=179; MIN_BATTERY=48
LEDGER_N="$(wc -l < "$LEDGER")"
echo; echo "=== dispatch-recovery-sweeper-11211.sh: $PASS passed, $FAIL failed ($LEDGER_N recorded) ==="
if [ "$LEDGER_N" -ne $((PASS + FAIL)) ]; then printf 'LEDGER MISMATCH\n'; exit 1; fi
mh_floor "$MIN_FIXTURE" "$MIN_BATTERY" "${1:-}"
[ "$FAIL" -eq 0 ]
