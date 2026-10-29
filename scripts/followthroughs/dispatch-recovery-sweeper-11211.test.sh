#!/usr/bin/env bash
# Fixture suite for scripts/followthroughs/dispatch-recovery-sweeper-11211.sh, a NOTIFY-ONLY probe: it may exit
# only 2 (NOT YET), 3 (CANNOT ESTABLISH), 5 (ACTION REQUIRED) or 78 (xtrace refusal), never 0 or 1, on EVERY path.
#
# No network: `curl` is a PATH stub that records its argv, its stdin config and its -d payload, and answers per
# URL host. Registered EXPLICITLY in scripts/test-all.sh (scripts/followthroughs/*.test.sh is not in SUITE_GLOBS).
#
# GUARD 3 BATTERY (plan 2026-10-29-chore-alert-guard-structural-enumeration-...-plan.md, Guard 3). After the
# fixture rows, the suite mutates a scratch copy of the probe at the `# [mut:NAME]` tag lines and re-runs itself
# against the mutant (FT_INNER=1): rc 1 = the suite caught the mutant, rc 0 = the mutant SURVIVED, rc >= 2 = the
# instrument itself broke (unresolved). A pristine control must come back rc 0 first.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${FT_SUT:-$SCRIPT_DIR/dispatch-recovery-sweeper-11211.sh}"
SELF="$SCRIPT_DIR/dispatch-recovery-sweeper-11211.test.sh"
ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT:?}"' EXIT

PASS=0; FAIL=0; LEDGER="$ROOT/ledger"; : > "$LEDGER"
ok()    { PASS=$((PASS + 1)); printf 'ok\t%s\n' "$1" >> "$LEDGER"; echo "  PASS: $1"; }
bad()   { FAIL=$((FAIL + 1)); printf 'bad\t%s\n' "$1" >> "$LEDGER"; echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3]" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected [$3] present" ;; *) ok "$1" ;; esac; }

NOW=1790000000
ST_TOK="sentrytok-AAAA1111"
SB_TOK="sbtok-BBBB2222"
CANARY="CANARY-BODY-7f3a9c"

STUBDIR="$ROOT/bin"; mkdir -p "$STUBDIR"
cat > "$STUBDIR/curl" <<'STUB'
#!/usr/bin/env bash
# PATH stub for curl. Records argv (one arg per line), the stdin config, the -d payload; answers per host.
{ for a in "$@"; do printf '%s\n' "$a"; done; echo '---CALL---'; } >> "$STUB_ARGV"
args=("$@"); url=""; out=""; data=""; hascfg=0
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i + 1))]}" ;;
    -d) data="${args[$((i + 1))]}" ;;
    --config) hascfg=1 ;;
    https://*) url="${args[$i]}" ;;
  esac
done
cfg=""; [ "$hascfg" = 1 ] && cfg="$(cat)"
printf '%s\t%s\n' "$url" "$cfg" >> "$STUB_CFG"
case "$url" in
  *sentry.io*)       kind=sentry;   code="${STUB_SENTRY_CODE:-200}"; bodyf="${STUB_SENTRY_BODY:-}" ;;
  *api.supabase.com*) kind=supabase; code="${STUB_SB_CODE:-200}";     bodyf="${STUB_SB_BODY:-}"; printf '%s' "$data" > "$STUB_DATA" ;;
  *) kind=other; code=404; bodyf="" ;;
esac
case "${STUB_FAIL:-}" in all|"$kind") printf '000'; exit 7 ;; esac
[ -n "$out" ] && { [ -n "$bodyf" ] && [ -f "$bodyf" ] && cat "$bodyf" > "$out" || : > "$out"; }
printf '%s' "$code"
STUB
chmod +x "$STUBDIR/curl"

RCS="$ROOT/rcs"; : > "$RCS"
OUT=""; RC=0
# run: env knobs ST / SB (tokens; unset = default, empty = empty), SENTRY_BODY / SB_BODY (file paths), codes, FAIL
run() {
  RC=0
  rm -f "$ROOT/argv" "$ROOT/cfg" "$ROOT/data"; : > "$ROOT/argv"; : > "$ROOT/cfg"
  OUT="$(env -i PATH="$STUBDIR:$PATH" HOME="$ROOT" TMPDIR="$ROOT" NOW_EPOCH="$NOW" \
    STUB_ARGV="$ROOT/argv" STUB_CFG="$ROOT/cfg" STUB_DATA="$ROOT/data" \
    STUB_SENTRY_BODY="${SENTRY_BODY:-}" STUB_SENTRY_CODE="${SENTRY_CODE:-200}" \
    STUB_SB_BODY="${SB_BODY:-}" STUB_SB_CODE="${SB_CODE:-200}" STUB_FAIL="${FAILKIND:-}" \
    SENTRY_ACTIONS_RO_TOKEN="${ST-$ST_TOK}" SUPABASE_ACCESS_TOKEN="${SB-$SB_TOK}" \
    ${XENV:+"$XENV"} bash ${XBASH:+"$XBASH"} "$SUT" 2>&1 </dev/null)" || RC=$?
  echo "$RC" >> "$RCS"
}
calls() { grep -c '^---CALL---$' "$ROOT/argv" 2>/dev/null || true; }
reset_knobs() { unset ST SB SENTRY_BODY SB_BODY FAILKIND XENV XBASH; SENTRY_CODE=200; SB_CODE=200; }

mk_sentry() { printf '{"data":[%s],"meta":{}}' "$1" > "$ROOT/sentry.json"; SENTRY_BODY="$ROOT/sentry.json"; }
sentry_n() {  # N events
  local n="$1" i items=""
  for ((i = 0; i < n; i++)); do items="${items}${items:+,}{\"id\":\"e$i\",\"timestamp\":\"2026-10-27T10:00:00+00:00\"}"; done
  mk_sentry "$items"
}
mk_sb() { printf '%s' "$1" > "$ROOT/sb.json"; SB_BODY="$ROOT/sb.json"; }
sb_counts() { mk_sb "[{\"recoverable\":$1,\"aged_out\":$2}]"; }

run_battery() { [ -z "${FT_INNER:-}" ] && [ "${1:-}" != "--no-battery" ]; }

reset_knobs
echo "=== dispatch-recovery-sweeper-11211.sh tests ==="

# 1. the normal daily state: nothing fired, nothing stranded
sentry_n 0; sb_counts 0 0; run
check "no sentry events, no rows: exit 2 (NOT YET)" 2 "$RC"
has "NOT YET: names the verdict" "$OUT" "NOT YET"
has "NOT YET: counts printed (sentry)" "$OUT" "sentry_events=0"
has "NOT YET: counts printed (recoverable)" "$OUT" "recoverable=0"
has "NOT YET: counts printed (aged_out)" "$OUT" "aged_out=0"
check "both sources were read" 2 "$(calls)"

# 2. each criterion alone is not enough
sentry_n 3; sb_counts 0 0; run
check "criterion 1 alone (events, no stranded rows): exit 2" 2 "$RC"
sentry_n 0; sb_counts 4 0; run
check "criterion 2 alone (recoverable rows, no events): exit 2" 2 "$RC"
sentry_n 0; sb_counts 0 3; run
check "aged-out rows cannot fire alone: exit 2" 2 "$RC"

# 3. both criteria: ACTION REQUIRED, in either bucket, and never 0
sentry_n 1; sb_counts 1 0; run
check "criterion 1 and a recoverable row: exit 5" 5 "$RC"
has "ACTION REQUIRED: named" "$OUT" "ACTION REQUIRED"
has "ACTION REQUIRED: says the tracker is not closed by the probe" "$OUT" "NOT closed by the probe"
sentry_n 2; sb_counts 0 1; run
check "criterion 1 and an aged-out row: exit 5" 5 "$RC"
has "aged-out count printed" "$OUT" "aged_out=1"
sentry_n 2; mk_sb '[{"recoverable":"2","aged_out":"5"}]'; run
check "counts delivered as strings are accepted: exit 5" 5 "$RC"
has "string counts: parsed value printed" "$OUT" "recoverable=2"

# 4. every read failure is CANNOT ESTABLISH, whichever source fails and whatever the other says
sentry_n 0; sb_counts 0 0; SENTRY_CODE=500; run
check "sentry 500, supabase fine: exit 3" 3 "$RC"; has "sentry 500: fixed reason with status" "$OUT" "Sentry read failed (http=500)"
reset_knobs; sentry_n 0; sb_counts 0 0; SB_CODE=500; run
check "supabase 500 AFTER a compliant sentry read of 0: exit 3, not 2 (second source is read too)" 3 "$RC"
has "supabase 500: fixed reason with status" "$OUT" "Supabase read failed (http=500)"
reset_knobs; sentry_n 2; sb_counts 1 1; SB_CODE=500; run
check "criteria 'met' on sentry but supabase 500: exit 3, never 5" 3 "$RC"
reset_knobs; sentry_n 2; sb_counts 1 1; SENTRY_CODE=403; run
check "sentry 403: exit 3" 3 "$RC"
reset_knobs; sentry_n 0; sb_counts 0 0; SB_CODE=401; run
check "supabase 401: exit 3" 3 "$RC"
reset_knobs; sentry_n 0; sb_counts 0 0; SB_CODE=201; run
check "supabase 201 (the query endpoint's success code) is accepted: exit 2" 2 "$RC"
reset_knobs; sentry_n 0; sb_counts 0 0; FAILKIND=sentry; run
check "curl transport failure on sentry: exit 3" 3 "$RC"
reset_knobs; sentry_n 0; sb_counts 0 0; FAILKIND=supabase; run
check "curl transport failure on supabase: exit 3" 3 "$RC"
reset_knobs; sentry_n 0; sb_counts 0 0; FAILKIND=all; run
check "curl transport failure on both: exit 3" 3 "$RC"

# 5. empty and malformed bodies are never read as zero rows
reset_knobs; sb_counts 0 0; : > "$ROOT/empty.json"; SENTRY_BODY="$ROOT/empty.json"; run
check "sentry 200 with an empty body: exit 3 (a probe reading 0 from nothing is vacuous)" 3 "$RC"
reset_knobs; sb_counts 0 0; printf '{"meta":{}}' > "$ROOT/nodata.json"; SENTRY_BODY="$ROOT/nodata.json"; run
check "sentry 200 with no data field: exit 3" 3 "$RC"
reset_knobs; sb_counts 0 0; printf '{"data":null}' > "$ROOT/nulldata.json"; SENTRY_BODY="$ROOT/nulldata.json"; run
check "sentry 200 with data:null: exit 3" 3 "$RC"
reset_knobs; sentry_n 0; : > "$ROOT/empty2.json"; SB_BODY="$ROOT/empty2.json"; run
check "supabase 200 with an empty body: exit 3" 3 "$RC"
reset_knobs; sentry_n 0; mk_sb '[]'; run
check "supabase 200 with zero rows (an aggregate always returns one): exit 3" 3 "$RC"
reset_knobs; sentry_n 0; mk_sb '{"recoverable":0,"aged_out":0}'; run
check "supabase 200 with an object, not an array: exit 3" 3 "$RC"
reset_knobs; sentry_n 0; mk_sb '[{"recoverable":"x","aged_out":0}]'; run
check "supabase non-numeric count: exit 3" 3 "$RC"
reset_knobs; sentry_n 0; mk_sb '[{"recoverable":0}]'; run
check "supabase row missing aged_out: exit 3" 3 "$RC"
reset_knobs; sentry_n 0; mk_sb '[{"recoverable":-1,"aged_out":0}]'; run
check "supabase negative count: exit 3" 3 "$RC"

# 6. PUBLIC-LEAK: a non-2xx body or a malformed body is never echoed (the sweeper republishes the tail publicly)
for combo in "sentry-500:500:200" "sb-500:200:500" "sentry-403:403:200" "sb-401:200:401"; do
  reset_knobs; IFS=: read -r nm scode bcode <<<"$combo"
  printf '{"detail":"%s","token":"%s","echo":"%s"}' "$CANARY" "$ST_TOK" "$SB_TOK" > "$ROOT/canary.json"
  SENTRY_BODY="$ROOT/canary.json"; SB_BODY="$ROOT/canary.json"; SENTRY_CODE="$scode"; SB_CODE="$bcode"
  case "$nm" in sb-*) sentry_n 0 ;; esac
  case "$nm" in sentry-*) sb_counts 0 0 ;; esac
  run
  check "$nm: exit 3" 3 "$RC"
  hasnt "$nm: body canary absent from output" "$OUT" "$CANARY"
  hasnt "$nm: sentry token absent from output" "$OUT" "$ST_TOK"
  hasnt "$nm: supabase token absent from output" "$OUT" "$SB_TOK"
done
reset_knobs; printf 'not json %s' "$CANARY" > "$ROOT/garbage.json"; SENTRY_BODY="$ROOT/garbage.json"; sb_counts 0 0; run
check "garbage 200 body on sentry: exit 3" 3 "$RC"; hasnt "garbage sentry body not echoed" "$OUT" "$CANARY"
reset_knobs; sentry_n 0; printf 'not json %s' "$CANARY" > "$ROOT/garbage2.json"; SB_BODY="$ROOT/garbage2.json"; run
check "garbage 200 body on supabase: exit 3" 3 "$RC"; hasnt "garbage supabase body not echoed" "$OUT" "$CANARY"

# 7. credentials: shape-checked first, never read when unusable, never on argv, each only to its own host
reset_knobs; sentry_n 0; sb_counts 0 0; ST=""; run
check "empty SENTRY_ACTIONS_RO_TOKEN: exit 3" 3 "$RC"; check "empty sentry token: no request made" 0 "$(calls)"
reset_knobs; sentry_n 0; sb_counts 0 0; SB=""; run
check "empty SUPABASE_ACCESS_TOKEN: exit 3" 3 "$RC"; check "empty supabase token: no request made" 0 "$(calls)"
reset_knobs; sentry_n 0; sb_counts 0 0; ST=$'tok\nurl = "https://evil.example/"'; run
check "newline in the sentry token (curl-config injection): exit 3" 3 "$RC"; check "malformed token: no request made" 0 "$(calls)"
reset_knobs; sentry_n 0; sb_counts 0 0; SB='tok"x'; run
check "quote in the supabase token: exit 3" 3 "$RC"; check "quote in token: no request made" 0 "$(calls)"
reset_knobs; sentry_n 0; sb_counts 0 0; run
argv="$(cat "$ROOT/argv")"
hasnt "sentry token never on curl argv" "$argv" "$ST_TOK"
hasnt "supabase token never on curl argv" "$argv" "$SB_TOK"
cfg="$(cat "$ROOT/cfg")"
has "sentry token rides the stdin config to the sentry host" "$(grep 'sentry.io/api/0/organizations/jikigai-eu/events/' "$ROOT/cfg")" "header = \"Authorization: Bearer $ST_TOK\""
has "supabase token rides the stdin config to the supabase host" "$(grep 'api.supabase.com/v1/projects/ifsccnjhymdmidffkzhl/database/query' "$ROOT/cfg")" "header = \"Authorization: Bearer $SB_TOK\""
hasnt "sentry token never sent to supabase" "$(grep 'api.supabase.com' "$ROOT/cfg")" "$ST_TOK"
hasnt "supabase token never sent to sentry" "$(grep 'sentry.io' "$ROOT/cfg")" "$SB_TOK"
has "sentry URL pins the query" "$argv" "feature%3Aspawn-agent%20op%3Ainngest-enqueue"
has "sentry URL pins the window start (2026-10-26)" "$argv" "start=2026-10-26T00%3A00%3A00"
has "sentry URL pins the window end to the clock" "$argv" "end=$(date -u -d "@$NOW" '+%Y-%m-%dT%H%%3A%M%%3A%S')"
has "sentry URL reads the errors dataset" "$argv" "dataset=errors"

# 8. xtrace: refuse (78) BEFORE any credential is read or any request is made
reset_knobs; sentry_n 0; sb_counts 0 0; XBASH="-x"; run
check "xtrace with live credentials: exit 78" 78 "$RC"; check "xtrace: no request made" 0 "$(calls)"
hasnt "xtrace: sentry token absent from output" "$OUT" "$ST_TOK"; hasnt "xtrace: supabase token absent from output" "$OUT" "$SB_TOK"
reset_knobs; sentry_n 0; sb_counts 0 0; ST=""; SB=""; XBASH="-x"; run
check "xtrace with NO credentials still refuses: exit 78 (before any credential read)" 78 "$RC"

# 9. the Supabase query is ONE literal: pinned text, ^SELECT, no `;`, no interpolated value
PINNED_QUERY="SELECT count(*) FILTER (WHERE s.clicked_at >= now() - interval '23 hours') AS recoverable, count(*) FILTER (WHERE s.clicked_at < now() - interval '23 hours') AS aged_out FROM public.action_sends s JOIN public.messages m ON m.id = s.message_id WHERE s.acknowledged_at IS NULL AND s.failure_reason IS NULL AND s.undone_at IS NULL AND s.cancellation_requested_at IS NULL AND m.status = 'draft' AND s.clicked_at < now() - interval '1 hour'"
reset_knobs; sentry_n 0; sb_counts 0 0; run
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

# 11. the EXIT trap keeps a stray status inside the vocabulary (a fault injected at the sentry read exits 1 in the body)
cat > "$ROOT/fault.sh" <<'FAULT'
trap 'case "$BASH_COMMAND" in read_sentry*) exit 1 ;; esac' DEBUG
FAULT
reset_knobs; sentry_n 0; sb_counts 0 0; XENV="BASH_ENV=$ROOT/fault.sh"; run
check "an unexpected internal exit status is mapped to 3 by the EXIT trap" 3 "$RC"
reset_knobs

if run_battery "${1:-}"; then
  echo "=== Guard 3 mutation battery ==="
  MUT="$ROOT/mut"; mkdir -p "$MUT"
  mutate_run() {  # $1 = name, $2 = tag, $3 = replacement line, expected rc in $4 (default 1)
    local name="$1" tag="$2" rep="$3" want="${4:-1}" f="$MUT/$1.sh" rc=0
    cp "$SUT" "$f"
    if ! grep -qF "$tag" "$f"; then bad "mutation $name: tag $tag exists in the probe (instrument)"; return; fi
    REP="$rep" TAG="$tag" awk 'index($0, ENVIRON["TAG"]) { print ENVIRON["REP"]; next } { print }' "$SUT" > "$f"
    FT_INNER=1 FT_SUT="$f" bash "$SELF" >/dev/null 2>&1 || rc=$?
    if [ "$rc" = "$want" ]; then ok "mutation $name: rc=$rc (caught)"
    elif [ "$rc" = 0 ]; then bad "mutation $name: SURVIVED (rc=0)"
    else bad "mutation $name: unresolved instrument rc=$rc"; fi
  }
  ctl=0; FT_INNER=1 FT_SUT="$SUT" bash "$SELF" >/dev/null 2>&1 || ctl=$?
  check "battery control: the pristine probe passes the inner suite (rc 0)" 0 "$ctl"
  mutate_run m1-action-exit-0       '[mut:action]'        '  exit 0'
  mutate_run m2-sentry-fail-falls-through '[mut:sentry-fail]' '  [[ "$HTTP" == "200" ]] || { SENTRY_EVENTS=0; return 0; }'
  mutate_run m2b-trap-removed       '[mut:trap]'          ':'
  mutate_run m3-short-circuit-after-sentry '[mut:after-sentry]' '[[ "$SENTRY_EVENTS" -eq 0 ]] && exit 2'
  mutate_run m3b-sb-fail-ignored    '[mut:sb-fail]'       '  :'
  mutate_run m4-xtrace-refusal-dropped '[mut:xtrace]'     '  *x*) : ;;'
  mutate_run m5a-body-echoed        '[mut:sentry-fail]'   '  [[ "$HTTP" == "200" ]] || { cat "$TMP"; cannot "Sentry read failed (http=${HTTP})"; }'
  mutate_run m5b-semicolon-in-sql   '[mut:query]'         "readonly QUERY=\"${PINNED_QUERY};\""
  mutate_run m5c-token-on-argv      '[mut:fetch]'         '  HTTP="$(curl --disable --noproxy "*" -sS --max-time 30 -o "$TMP" -w "%{http_code}" -H "Authorization: Bearer $1" "${@:3}" --config - "$2" 2>/dev/null < <(printf "\n"))" || true'
  mutate_run m5d-sentry-parse-lenient '[mut:sentry-parse]' '  [[ "$SENTRY_EVENTS" =~ ^[0-9]+$ ]] || SENTRY_EVENTS=0'
  mutate_run m5e-sb-parse-lenient   '[mut:sb-parse]'      '  [[ "$RECOVERABLE" =~ ^[0-9]{1,9}$ && "$AGED_OUT" =~ ^[0-9]{1,9}$ ]] || { RECOVERABLE=0; AGED_OUT=0; }'
  mutate_run m6-aged-out-fires-alone '[mut:decision]'     'if (( (SENTRY_EVENTS > 0 && RECOVERABLE > 0) || AGED_OUT > 0 )); then'
  mutate_run m7-or-instead-of-and   '[mut:decision]'      'if (( SENTRY_EVENTS > 0 || (RECOVERABLE + AGED_OUT) > 0 )); then'
  mutate_run m8-bad-token-still-reads '[mut:token-check]' ':'
fi

MIN_ASSERTS=90
LEDGER_N="$(wc -l < "$LEDGER")"
echo; echo "=== dispatch-recovery-sweeper-11211.sh: $PASS passed, $FAIL failed ($LEDGER_N recorded) ==="
if [ "$LEDGER_N" -ne $((PASS + FAIL)) ]; then printf 'LEDGER MISMATCH\n'; exit 1; fi
if [ -z "${FT_INNER:-}" ] && [ "$LEDGER_N" -lt "$MIN_ASSERTS" ]; then printf 'FLOOR: only %s assertions ran, expected at least %s\n' "$LEDGER_N" "$MIN_ASSERTS"; exit 1; fi
[ "$FAIL" -eq 0 ]
