#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2086  # stub bodies are single-quoted on purpose; RUN_ENV/RUN_FLAGS are deliberately word-split
# Suite for scripts/legal-acceptance-counts.sh (#12429, ADR-319 amendment 2026-11-08): the credential-free pre-flag aggregate
# helper. PROPERTY UNDER TEST: it prints exactly one line, `ok_to_flag=<bool> total=<n> measured=production-table-only`, and
# nothing else, ONLY when the endpoint answered 200 with the documented shape; every other outcome exits non-zero with NO
# `ok_to_flag=` line and one status line on stderr; it validates the key before building the URL, uses the hardcoded host,
# refuses under xtrace, never echoes the response body or the token.
# THE SEAM: `doppler` and `curl` are PATH stubs on a hermetic PATH that holds neither a real curl nor a real doppler. No
# network, no real secret store, no production call. The token below is a synthetic fixture.
# ARMS: control, status matrix, malformed bodies, key validation, host, xtrace, token hygiene, mutations.

set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -P "$SCRIPT_DIR/.." && pwd -P)"
SUT="$SCRIPT_DIR/legal-acceptance-counts.sh"
LIB="$REPO_ROOT/plugins/soleur/scripts/lib/bearer-fetch.sh"
BASH_BIN="$(command -v bash)"

TMP="$(mktemp -d -t lac-suite.XXXXXXXX)" || { echo "FATAL: no scratch dir" >&2; exit 2; }

# Canonical fixture-dir guard (copied byte-for-byte from plugins/soleur/test/test-helpers.sh; fixture-dir-operand-assert.test.sh pins every copy).
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
assert_fixture_dir "$TMP"
trap 'rm -rf -- "$TMP"' EXIT

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); }
bad() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }
check() { # <label> <command...>: pass when the command succeeds
  local label="$1"; shift
  if "$@"; then ok; else bad "$label"; fi
}
check_not() { # <label> <command...>: pass when the command fails
  local label="$1"; shift
  if "$@"; then bad "$label"; else ok; fi
}

[[ -f "$SUT" ]] || { echo "FATAL: SUT missing: $SUT" >&2; exit 2; }
[[ -f "$LIB" ]] || { echo "FATAL: helper library missing: $LIB" >&2; exit 2; }

TOKEN='SYNTHtoken'"$(printf 'b%.0s' $(seq 1 40))" # synthetic, 50 chars
HASH_A="$(printf 'a%.0s' $(seq 1 64))"
HASH_B="$(printf 'b%.0s' $(seq 1 64))"

# --- the hermetic PATH: symlinks to the usual tools plus jq, and NO curl, NO doppler -------------------
BIN="$TMP/bin"; assert_fixture_dir "$BIN"; mkdir -p "$BIN"
for t in bash cat env grep head tr sed awk cut wc rm mkdir mktemp dirname basename find ls id sleep timeout gtimeout stat touch date cmp sort true false jq; do
  p="$(command -v "$t" 2>/dev/null)"; [[ "$p" == /* && -x "$p" ]] && ln -sf "$p" "$BIN/$t"
done
cat > "$BIN/doppler" <<'STUB'
#!/usr/bin/env bash
d="${STUB_DIR:?}"
echo "doppler $*" >> "$d/doppler-argv.log"
[ "$*" = "secrets get LEGAL_ACCEPTANCE_VERIFY_TOKEN --plain --project soleur --config prd" ] \
  || { echo "STUB-MISS $*" >> "$d/doppler-argv.log"; exit 64; }
[ ! -f "$d/doppler-fail" ] || { echo "Doppler Error" >&2; exit 1; }
cat "$d/doppler-token"
STUB
chmod +x "$BIN/doppler"
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
d="${STUB_DIR:?}"
echo "curl" >> "$d/curl-calls.log"
args=("$@"); url="${args[${#args[@]}-1]}"; out=""; cfg=""
for ((i = 0; i < ${#args[@]}; i++)); do
  [ "${args[$i]}" = "-o" ] && out="${args[$((i + 1))]}"
  [ "${args[$i]}" = "--config" ] && cfg="${args[$((i + 1))]}"
done
echo "$url" >> "$d/curl-url.log"
rc=0; [ ! -f "$d/curl-rc" ] || rc="$(cat "$d/curl-rc")"
[ "$rc" = 0 ] || { printf '000'; exit "$rc"; }
st=200; [ ! -f "$d/curl-status" ] || st="$(cat "$d/curl-status")"
[ "$(cat "$cfg")" = "header = \"Authorization: Bearer $(cat "$d/doppler-token")\"" ] || st=401
: > "$out"
[ ! -f "$d/curl-body" ] || cat "$d/curl-body" > "$out"
printf '%s' "$st"
STUB
chmod +x "$BIN/curl"

SC=0
scn() { # new scenario dir with the default 200 / ok body
  SC=$((SC + 1)); STUB_DIR="$TMP/scn$SC"; assert_fixture_dir "$STUB_DIR"; rm -rf -- "$STUB_DIR"; mkdir -p "$STUB_DIR"; export STUB_DIR
  printf '%s\n' "$TOKEN" > "$STUB_DIR/doppler-token"
  body 'some-key' true 0
}
# body <key> <ok> <total> [by_hash json]: write the endpoint's JSON
body() {
  local key="$1" ok="$2" total="$3" by="${4:-[]}"
  printf '{"key":"%s","registry_hash":"%s","total":%s,"by_hash":%s,"ok_to_flag":%s}' "$key" "$HASH_A" "$total" "$by" "$ok" > "$STUB_DIR/curl-body"
}
# mk_body <key> <ok> <total> <by_hash json>: the same JSON as body(), on stdout (for mal rows)
mk_body() { printf '{"key":"%s","registry_hash":"%s","total":%s,"by_hash":%s,"ok_to_flag":%s}' "$1" "$HASH_A" "$3" "$4" "$2"; }
# mk_body_r <key> <registry_hash> <ok> <total> <by_hash json>: the same JSON with an explicit registry_hash (length / anchor probes)
mk_body_r() { printf '{"key":"%s","registry_hash":"%s","total":%s,"by_hash":%s,"ok_to_flag":%s}' "$1" "$2" "$4" "$5" "$3"; }
# run <script> <args...>: hermetic env, captured streams
run() {
  local script="$1"; shift
  ( cd "$TMP" && env -i HOME="$TMP" PATH="$BIN" STUB_DIR="$STUB_DIR" ${RUN_ENV:-} "$BASH_BIN" ${RUN_FLAGS:-} "$script" "$@" ) >"$TMP/run.out" 2>"$TMP/run.err"
  RC=$?
}
OUT() { cat "$TMP/run.out"; }
ERR() { cat "$TMP/run.err"; }
out_is() { [ "$(OUT)" = "$1" ]; }
out_empty() { [ ! -s "$TMP/run.out" ]; }
err_is() { [ "$(ERR)" = "$1" ]; }
no_flag_line() { ! grep -q 'ok_to_flag=' "$TMP/run.out" "$TMP/run.err"; }
rc_is() { [ "$RC" -eq "$1" ]; }
rc_nonzero() { [ "$RC" -ne 0 ]; }
curl_calls() { { cat "$STUB_DIR/curl-calls.log" 2>/dev/null || true; } | grep -c curl || true; }
no_token_anywhere() {
  { cat "$TMP/run.out" "$TMP/run.err" "$STUB_DIR"/curl-url.log "$STUB_DIR"/doppler-argv.log 2>/dev/null || true; } > "$TMP/.hay"
  ! grep -qF -- "$TOKEN" "$TMP/.hay"
}

KEY="some-key"
URL="https://app.soleur.ai/api/internal/legal-acceptance/$KEY/counts"

# --- harness self-tests: the assertion helpers can fail ------------------------------------------------
scn; run "$SUT" "$KEY"
check_not "H1 the harness can fail: out_is rejects a wrong line" out_is "nope"
check_not "H2 the harness can fail: no_flag_line sees a flag line on the control run" no_flag_line
( cd "$TMP" && env -i PATH="$BIN" STUB_DIR="$STUB_DIR" "$BASH_BIN" -c 'curl --bogus' ) >/dev/null 2>&1
check "H3 the curl stub is reachable on the hermetic PATH" test "$?" -ne 127
( cd "$TMP" && env -i PATH="$BIN" "$BASH_BIN" -c 'command -v doppler >/dev/null && command -v curl >/dev/null' ) >/dev/null 2>&1
check "H4 the hermetic PATH resolves only the stubs for curl and doppler" test "$(readlink -f "$BIN/curl")" = "$BIN/curl"

echo "=== Control: ok_to_flag true at total 0 ==="
scn; run "$SUT" "$KEY"
check "C1 exit 0" rc_is 0
check "C2 stdout is exactly the one documented line" out_is "ok_to_flag=true total=0 measured=production-table-only"
check "C3 stderr is empty" err_is ""
check "C4 exactly one GET, to the hardcoded host and path" test "$(cat "$STUB_DIR/curl-url.log")" = "$URL"
check "C5 the token is in no output and no argv log" no_token_anywhere

echo "=== ok_to_flag false is a successful measurement (exit 0) ==="
scn; body "$KEY" false 2 "[{\"text_hash\":\"$HASH_A\",\"count\":1},{\"text_hash\":\"$HASH_B\",\"count\":1}]"; run "$SUT" "$KEY"
check "F1 exit 0" rc_is 0
check "F2 prints false and the total, and nothing else (no hash, no by_hash)" out_is "ok_to_flag=false total=2 measured=production-table-only"
check "F3 stderr empty" err_is ""
scn; body "$KEY" true 1 "[{\"text_hash\":\"$HASH_A\",\"count\":1}]"; run "$SUT" "$KEY"
check "F4 one row under the registry hash prints true total=1" out_is "ok_to_flag=true total=1 measured=production-table-only"

echo "=== Every HTTP failure: non-zero, no ok_to_flag line, one status line, body not echoed ==="
for pair in "401 unauthorized" "404 not_found" "502 bad_gateway" "503 store_failed"; do
  st="${pair%% *}"; cls="${pair#* }"
  scn; echo "$st" > "$STUB_DIR/curl-status"; printf '{"error":"BODY-SENTINEL ok_to_flag=true"}' > "$STUB_DIR/curl-body"; run "$SUT" "$KEY"
  check "S$st exit non-zero" rc_nonzero
  check "S$st stdout empty" out_empty
  check "S$st no ok_to_flag line anywhere" no_flag_line
  check "S$st one status line: counts: HTTP $st $cls" err_is "counts: HTTP $st $cls"
  check "S$st the body is not echoed" test "$(grep -c BODY-SENTINEL "$TMP/run.err" "$TMP/run.out" | grep -vc ':0$' || true)" = "0"
done
for st in 500 400 301 204; do
  scn; echo "$st" > "$STUB_DIR/curl-status"; run "$SUT" "$KEY"
  check "S$st (unexpected status) non-zero, no flag line" bash -c "[ $RC -ne 0 ] && ! grep -q ok_to_flag= '$TMP/run.out' '$TMP/run.err'"
done
echo "=== Transport failure and unreadable token ==="
scn; echo 6 > "$STUB_DIR/curl-rc"; run "$SUT" "$KEY"
check "T1 curl failure: non-zero, no flag line" rc_nonzero; check "T1b no flag line" no_flag_line; check "T1c stdout empty" out_empty
scn; : > "$STUB_DIR/doppler-fail"; run "$SUT" "$KEY"
check "T2 unreadable token: non-zero" rc_nonzero; check "T2b no flag line" no_flag_line; check "T2c curl never called" test "$(curl_calls)" = "0"
scn; printf 'short\n' > "$STUB_DIR/doppler-token"; run "$SUT" "$KEY"
check "T3 a malformed token is refused before any request" rc_nonzero; check "T3b curl never called" test "$(curl_calls)" = "0"; check "T3c the refused token is not printed" bash -c "! grep -q short '$TMP/run.out' '$TMP/run.err'"

echo "=== Malformed bodies: never default to true ==="
mal() { # <label> <raw body>
  scn; printf '%s' "$2" > "$STUB_DIR/curl-body"; run "$SUT" "$KEY"
  check "M $1: non-zero" rc_nonzero; check "M $1: no flag line" no_flag_line; check "M $1: stdout empty" out_empty
}
mal "empty body" ""
mal "not JSON" "<html>502</html>"
mal "an array" "[]"
mal "ok_to_flag missing" "{\"key\":\"$KEY\",\"registry_hash\":\"$HASH_A\",\"total\":0,\"by_hash\":[]}"
mal "ok_to_flag a string" "{\"key\":\"$KEY\",\"registry_hash\":\"$HASH_A\",\"total\":0,\"by_hash\":[],\"ok_to_flag\":\"true\"}"
mal "ok_to_flag null" "{\"key\":\"$KEY\",\"registry_hash\":\"$HASH_A\",\"total\":0,\"by_hash\":[],\"ok_to_flag\":null}"
mal "total missing" "{\"key\":\"$KEY\",\"registry_hash\":\"$HASH_A\",\"by_hash\":[],\"ok_to_flag\":true}"
mal "total negative" "{\"key\":\"$KEY\",\"registry_hash\":\"$HASH_A\",\"total\":-1,\"by_hash\":[],\"ok_to_flag\":true}"
mal "total fractional" "{\"key\":\"$KEY\",\"registry_hash\":\"$HASH_A\",\"total\":0.5,\"by_hash\":[],\"ok_to_flag\":true}"
mal "total a string" "{\"key\":\"$KEY\",\"registry_hash\":\"$HASH_A\",\"total\":\"0\",\"by_hash\":[],\"ok_to_flag\":true}"
mal "counts do not sum to total" "{\"key\":\"$KEY\",\"registry_hash\":\"$HASH_A\",\"total\":5,\"by_hash\":[{\"text_hash\":\"$HASH_A\",\"count\":1}],\"ok_to_flag\":true}"
mal "answer is about another key" "{\"key\":\"other-key\",\"registry_hash\":\"$HASH_A\",\"total\":0,\"by_hash\":[],\"ok_to_flag\":true}"
mal "registry_hash malformed" "{\"key\":\"$KEY\",\"registry_hash\":\"zz\",\"total\":0,\"by_hash\":[],\"ok_to_flag\":true}"
mal "total null" "{\"key\":\"$KEY\",\"registry_hash\":\"$HASH_A\",\"total\":null,\"by_hash\":[],\"ok_to_flag\":true}"
mal "total 1.5 (fractional, by_hash empty)" "{\"key\":\"$KEY\",\"registry_hash\":\"$HASH_A\",\"total\":1.5,\"by_hash\":[],\"ok_to_flag\":true}"
mal "total 3 with fractional counts 1.5+1.5" "$(mk_body "$KEY" true 3 "[{\"text_hash\":\"$HASH_A\",\"count\":1.5},{\"text_hash\":\"$HASH_A\",\"count\":1.5}]")"
mal "a foreign hash with ok_to_flag true (the route's verdict is not trusted)" "$(mk_body "$KEY" true 1 "[{\"text_hash\":\"$HASH_B\",\"count\":1}]")"
mal "the registry hash plus a foreign hash with ok_to_flag true" "$(mk_body "$KEY" true 2 "[{\"text_hash\":\"$HASH_A\",\"count\":1},{\"text_hash\":\"$HASH_B\",\"count\":1}]")"
mal "only the registry hash but ok_to_flag false" "$(mk_body "$KEY" false 1 "[{\"text_hash\":\"$HASH_A\",\"count\":1}]")"
mal "zero rows but ok_to_flag false (vacuously true)" "$(mk_body "$KEY" false 0 "[]")"
mal "a count of zero" "$(mk_body "$KEY" true 0 "[{\"text_hash\":\"$HASH_A\",\"count\":0}]")"
mal "a negative count" "$(mk_body "$KEY" true 0 "[{\"text_hash\":\"$HASH_A\",\"count\":-1},{\"text_hash\":\"$HASH_A\",\"count\":1}]")"
mal "a count that is a string" "$(mk_body "$KEY" true 1 "[{\"text_hash\":\"$HASH_A\",\"count\":\"1\"}]")"
mal "a count that is missing" "$(mk_body "$KEY" true 0 "[{\"text_hash\":\"$HASH_A\"}]")"
mal "an entry that is not an object" "$(mk_body "$KEY" true 1 "[1]")"
mal "a text_hash that is not hex (foreign, ok_to_flag false)" "$(mk_body "$KEY" false 1 "[{\"text_hash\":\"zz\",\"count\":1}]")"
mal "an uppercase text_hash (foreign, ok_to_flag false)" "$(mk_body "$KEY" false 1 "[{\"text_hash\":\"$(printf 'A%.0s' $(seq 1 64))\",\"count\":1}]")"
mal "a text_hash that is missing" "$(mk_body "$KEY" false 1 "[{\"count\":1}]")"
mal "a text_hash that is a number" "$(mk_body "$KEY" false 1 "[{\"text_hash\":7,\"count\":1}]")"
H63="$(printf 'a%.0s' $(seq 1 63))"; H65="$(printf 'a%.0s' $(seq 1 65))"
mal "a 63-char text_hash (foreign, ok_to_flag false)" "$(mk_body "$KEY" false 1 "[{\"text_hash\":\"$H63\",\"count\":1}]")"
mal "a 65-char text_hash (foreign, ok_to_flag false)" "$(mk_body "$KEY" false 1 "[{\"text_hash\":\"$H65\",\"count\":1}]")"
mal "a 63-char registry_hash" "$(mk_body_r "$KEY" "$H63" true 0 "[]")"
mal "a 65-char registry_hash" "$(mk_body_r "$KEY" "$H65" true 0 "[]")"
mal "by_hash not an array" "{\"key\":\"$KEY\",\"registry_hash\":\"$HASH_A\",\"total\":0,\"by_hash\":{},\"ok_to_flag\":true}"

echo "=== Key validation: before any request ==="
badkey() { # <label> <key>
  scn; run "$SUT" "$2"
  check "K $1: exit 64" rc_is 64; check "K $1: no flag line" no_flag_line; check "K $1: curl never called" test "$(curl_calls)" = "0"; check "K $1: doppler never called" test ! -s "$STUB_DIR/doppler-argv.log"
}
badkey "uppercase" "Bad"
badkey "leading hyphen" "-bad"
badkey "slash" "a/b"
badkey "dot dot" "../x"
badkey "space" "a b"
badkey "query injection" "a?x=1"
badkey "64 chars" "$(printf 'k%.0s' $(seq 1 64))"
badkey "empty" ""
badkey "newline" $'a\nb'
badkey "trailing newline" $'abc\n'
scn; body "$(printf 'k%.0s' $(seq 1 63))" true 0; run "$SUT" "$(printf 'k%.0s' $(seq 1 63))"
check "K 63 chars accepted" rc_is 0
scn; run "$SUT"; check "K no argument: exit 64" rc_is 64; check "K no argument: curl never called" test "$(curl_calls)" = "0"
scn; run "$SUT" a b; check "K two arguments: exit 64" rc_is 64

echo "=== Host is hardcoded: no environment override ==="
scn; RUN_ENV="APP_URL=http://evil.example HOST=http://evil.example BASE_URL=http://evil.example SOLEUR_URL=http://evil.example COUNTS_HOST=http://evil.example" run "$SUT" "$KEY"
check "U1 exit 0" rc_is 0
check "U2 the request still went to https://app.soleur.ai" test "$(cat "$STUB_DIR/curl-url.log")" = "$URL"

echo "=== Refuses under xtrace ==="
scn; RUN_FLAGS="-x" run "$SUT" "$KEY"
check "X1 exit 78" rc_is 78; check "X2 no flag line" no_flag_line; check "X3 the secret store was never read" test ! -s "$STUB_DIR/doppler-argv.log"; check "X4 curl never called" test "$(curl_calls)" = "0"
check "X5 the message says so" bash -c "grep -q 'refusing to run under xtrace' '$TMP/run.err'"
scn; RUN_ENV="SHELLOPTS=xtrace" run "$SUT" "$KEY"
check "X6 SHELLOPTS=xtrace is refused too" rc_nonzero; check "X6b the token is not printed" no_token_anywhere

echo "=== MUTATIONS: each weakening of the script must be caught by a probe ==="
MUT="$TMP/mut"; assert_fixture_dir "$MUT"; rm -rf -- "$MUT"; mkdir -p "$MUT/scripts" "$MUT/plugins/soleur/scripts/lib"
cp "$LIB" "$MUT/plugins/soleur/scripts/lib/bearer-fetch.sh"
DEFINED=() # every mutant() call appends its name: the loop below must name exactly this set
mutant() { # <name> <sed expression>: write the mutated script to $MUT/scripts/<name>.sh and fail the suite if the sed did not land
  DEFINED+=("$1")
  cp "$SUT" "$MUT/scripts/$1.sh"
  sed -i -E "$2" "$MUT/scripts/$1.sh"
  if cmp -s "$SUT" "$MUT/scripts/$1.sh"; then bad "mutation $1 did not land"; fi
}
VIOL=""
pv() { VIOL="$VIOL $1"; } # record the NAME of a violated probe
pristine_ok() { # the probe set: a pristine run satisfies every probe; a caught mutant violates NAMED probes (VIOL)
  local script="$1" b i
  VIOL=""
  scn; run "$script" "$KEY"; out_is "ok_to_flag=true total=0 measured=production-table-only" || pv control
  scn; printf '{"key":"%s"}' "$KEY" > "$STUB_DIR/curl-body"; run "$script" "$KEY"; { rc_nonzero && no_flag_line; } || pv shape-missing
  scn; echo 503 > "$STUB_DIR/curl-status"; run "$script" "$KEY"; { rc_nonzero && no_flag_line; } || pv s503
  scn; echo 404 > "$STUB_DIR/curl-status"; run "$script" "$KEY"; { rc_nonzero && no_flag_line; } || pv s404
  scn; run "$script" 'a?x=1'; { rc_nonzero && [ "$(curl_calls)" = "0" ]; } || pv key-inject
  scn; RUN_FLAGS="-x" run "$script" "$KEY"; { rc_nonzero && [ ! -s "$STUB_DIR/doppler-argv.log" ] && grep -q '^counts: refusing to run under xtrace' "$TMP/run.err"; } || pv xtrace
  scn; body "$KEY" true 3 "[{\"text_hash\":\"$HASH_A\",\"count\":1}]"; run "$script" "$KEY"; { rc_nonzero && no_flag_line; } || pv sum
  scn; : > "$STUB_DIR/doppler-fail"; run "$script" "$KEY"; { rc_nonzero && no_flag_line && grep -q '^counts: token unreadable' "$TMP/run.err"; } || pv token
  scn; RUN_ENV="APP_URL=http://evil.example" run "$script" "$KEY"; [ "$(cat "$STUB_DIR/curl-url.log" 2>/dev/null)" = "$URL" ] || pv host
  for i in "${!PROBE_BODIES[@]}"; do
    b="${PROBE_BODIES[$i]}"
    scn; printf '%s' "$b" > "$STUB_DIR/curl-body"; run "$script" "$KEY"; { rc_nonzero && no_flag_line && out_empty; } || pv "body:${PROBE_LABELS[$i]}"
  done
  # ...and accepts the two honest answers (a verdict recomputed to the wrong value would refuse these).
  scn; body "$KEY" false 2 "[{\"text_hash\":\"$HASH_A\",\"count\":1},{\"text_hash\":\"$HASH_B\",\"count\":1}]"; run "$script" "$KEY"
  out_is "ok_to_flag=false total=2 measured=production-table-only" || pv honest-false
  scn; body "$KEY" true 3 "[{\"text_hash\":\"$HASH_A\",\"count\":3}]"; run "$script" "$KEY"
  out_is "ok_to_flag=true total=3 measured=production-table-only" || pv honest-true
  [ -z "$VIOL" ]
}
# Bodies a pristine helper must REFUSE (one per jq clause / regex axis of the shape check; each is killed by the mutant that drops that clause).
# PROBE_LABELS is parallel: a mutant must violate ITS OWN named probe, so a mutant that merely crashes the script is not "caught".
PROBE_BODIES=(); PROBE_LABELS=()
probe_body() { PROBE_LABELS+=("$1"); PROBE_BODIES+=("$2"); }
HEX_A_UP="$(printf 'A%.0s' $(seq 1 64))"
probe_body count-floor  "$(mk_body "$KEY" true 3 "[{\"text_hash\":\"$HASH_A\",\"count\":1.5},{\"text_hash\":\"$HASH_A\",\"count\":1.5}]")"
probe_body count-ge1    "$(mk_body "$KEY" true 0 "[{\"text_hash\":\"$HASH_A\",\"count\":0}]")"
probe_body count-type   "$(mk_body "$KEY" true 1 "[{\"text_hash\":\"$HASH_A\",\"count\":\"1\"}]")" # a string count: floor errors, so the refusal is jq's error
probe_body hash-hex     "$(mk_body "$KEY" false 1 "[{\"text_hash\":\"zz\",\"count\":1}]")"
probe_body hash-lower   "$(mk_body "$KEY" false 1 "[{\"text_hash\":\"$HEX_A_UP\",\"count\":1}]")"
probe_body hash-present "$(mk_body "$KEY" false 1 "[{\"count\":1}]")"
probe_body hash-len63   "$(mk_body "$KEY" false 1 "[{\"text_hash\":\"$H63\",\"count\":1}]")"                  # {1,64} instead of {64}
probe_body hash-len65   "$(mk_body "$KEY" false 1 "[{\"text_hash\":\"$H65\",\"count\":1}]")"                  # {64,} / a dropped anchor
probe_body hash-prefix  "$(mk_body "$KEY" false 1 "[{\"text_hash\":\"zz$HASH_A\",\"count\":1}]")"             # the ^ anchor
probe_body hash-suffix  "$(mk_body "$KEY" false 1 "[{\"text_hash\":\"${HASH_A}zz\",\"count\":1}]")"           # the $ anchor
probe_body reg-len63    "$(mk_body_r "$KEY" "$H63" true 0 "[]")"                                              # registry_hash {1,64}
probe_body reg-len65    "$(mk_body_r "$KEY" "$H65" true 0 "[]")"
probe_body reg-prefix   "$(mk_body_r "$KEY" "zz$HASH_A" true 0 "[]")"                                         # registry_hash ^ anchor
probe_body reg-suffix   "$(mk_body_r "$KEY" "${HASH_A}zz" true 0 "[]")"                                       # registry_hash $ anchor
probe_body ok-foreign   "$(mk_body "$KEY" true 1 "[{\"text_hash\":\"$HASH_B\",\"count\":1}]")"                # ok_to_flag recomputed: foreign only
probe_body ok-mixed     "$(mk_body "$KEY" true 2 "[{\"text_hash\":\"$HASH_A\",\"count\":1},{\"text_hash\":\"$HASH_B\",\"count\":1}]")"
probe_body ok-all-false "$(mk_body "$KEY" false 1 "[{\"text_hash\":\"$HASH_A\",\"count\":1}]")"                # all-registry but false
probe_body ok-vacuous   "$(mk_body "$KEY" false 0 "[]")"                                                      # zero rows, false: vacuous true
probe_body total-frac   "$(mk_body "$KEY" true 1.5 "[]")"
probe_body total-neg    "$(mk_body "$KEY" true -1 "[]")"
probe_body total-str    "$(mk_body "$KEY" true '"1"' "[]")"
probe_body total-null   "$(mk_body "$KEY" true null "[]")"
probe_body total-16dig  "$(mk_body "$KEY" true 1000000000000000 "[{\"text_hash\":\"$HASH_A\",\"count\":1000000000000000}]")" # the {1,15} digit cap
probe_body by-type      "$(mk_body "$KEY" true 0 "{}")"
check "MP the probe bodies and their labels are parallel arrays" test "${#PROBE_BODIES[@]}" -eq "${#PROBE_LABELS[@]}"
check "MC control: the pristine script satisfies every probe" pristine_ok "$SUT"
mutant m1 's/^\[\[ "\$KEY" =~ \$KEY_RE \]\].*$/true/'
mutant m2 's/^case "\$-" in$/case "none" in/'
mutant m3 's#^  503\) fail.*$#  503) ;;#'
mutant m4 's#^  404\) fail.*$#  404) ;;#'
mutant m5 's#^jq -e --arg k "\$KEY" '"'"'$#jq -e --arg k "$KEY" '"'"'true or#'
mutant m6 's#^HOST="https://app\.soleur\.ai"#HOST="${APP_URL:-https://app.soleur.ai}"#'
mutant m7 's#^bc_read_token (.*) \|\| fail .*$#bc_read_token \1 || true#'
mutant m8 's#and \(\[\.by_hash\[\] \| \.count\] \| add // 0\) == \.total#and true#'
# m9: each clause of the by_hash / verdict check, dropped or weakened on its own line.
mutant m9a 's#^  and \(\.by_hash \| all\(\.count .*$#  and true#'
mutant m9b 's#all\(\.count \| \. == floor and \. >= 1\)#all(.count | . >= 1)#'
mutant m9c 's#and \. >= 1\)\)$#and . >= 0))#'
mutant m9e 's#^  and \(\.by_hash \| all\(\.text_hash .*$#  and true#'
mutant m9f 's#all\(\.text_hash \| type == "string" and test\(.*$#all(.text_hash | type == "string")) #'
mutant m9g 's#(all\(\.text_hash .*)\[0-9a-f\]#\1[0-9a-fA-F]#'
mutant m9h 's#^  and \.ok_to_flag == .*$#  and true#'
mutant m9i 's#\| all\)$#| any)#'
mutant m9j 's#\[\.by_hash\[\] \| \.text_hash == \$r\]#[.by_hash[0] | .text_hash == $r]#'
# m9k..m9r: the LENGTH and ANCHOR halves of the two hash regexes (the text_hash line and the registry_hash line are addressed by their own head)
mutant m9k 's#(\.text_hash \| type == "string" and test\("\^\[0-9a-f\])\{64\}#\1{1,64}#'
mutant m9l 's#(\.registry_hash \| type == "string" and test\("\^\[0-9a-f\])\{64\}#\1{1,64}#'
mutant m9m 's#(\.text_hash \| type == "string" and test\(")\^#\1#'
mutant m9n 's#(\.text_hash \| type == "string" and test\("\^\[0-9a-f\]\{64\})\$"#\1"#'
mutant m9o 's#(\.registry_hash \| type == "string" and test\(")\^#\1#'
mutant m9p 's#(\.registry_hash \| type == "string" and test\("\^\[0-9a-f\]\{64\})\$"#\1"#'
mutant m9q 's#\^\[0-9\]\{1,15\}\$#^[0-9]+$#'
# crash control: a mutant that merely BREAKS the script must not count as caught (it does not parse)
mutant mX 's#^set -uo pipefail#set -uo pipefail; this is not bash )(#'
# <mutant> <the probe it must violate>. A mutant is caught only when it violates ITS OWN named probe (see caught_by for what a crash can and cannot fake).
EXPECT=(
  "m1 key-inject" "m2 xtrace" "m3 s503" "m4 s404" "m5 sum" "m6 host" "m7 token" "m8 sum"
  "m9a body:count-floor" "m9b body:count-floor" "m9c body:count-ge1" "m9e body:hash-hex" "m9f body:hash-hex" "m9g body:hash-lower"
  "m9h body:ok-foreign" "m9i body:ok-mixed" "m9j body:ok-mixed"
  "m9k body:hash-len63" "m9l body:reg-len63" "m9m body:hash-prefix" "m9n body:hash-suffix" "m9o body:reg-prefix" "m9p body:reg-suffix" "m9q body:total-16dig"
)
caught_by() { # <mutant> <probe name>
  local m="$1" want="$2" w
  if [ ! -f "$MUT/scripts/$m.sh" ]; then bad "M-$m is named in the expectation list but was never defined"; return; fi
  if ! "$BASH_BIN" -n "$MUT/scripts/$m.sh" 2>/dev/null; then bad "M-$m does not parse: a mutant that crashes the script is not a caught weakening"; return; fi
  pristine_ok "$MUT/scripts/$m.sh" || true
  # A REFUSAL probe (body:*, s503, s404, key-inject, sum) is violated only when the mutant ACCEPTS what it must refuse, which a script that
  # fails for any other reason never does. xtrace / host / token are violated by a script that merely prints nothing, so for those the
  # mutant must also still pass the honest probes (a jq-syntax or runtime crash fails them).
  case "$want" in
    xtrace|host|token)
      for w in control honest-false honest-true; do
        case " $VIOL " in *" $w "*) bad "M-$m broke the script (it violates the honest probe '$w'), which is a crash, not a caught weakening"; return ;; esac
      done ;;
  esac
  case " $VIOL " in *" $want "*) ok ;; *) bad "M-$m survived: it does not violate its own probe '$want' (violated:${VIOL:- none})" ;; esac
}
# the expectation list and the defined mutants must be the same set (a name with no definition, or a definition with no expectation, is a FAIL)
want_names=" "; for e in "${EXPECT[@]}"; do want_names="$want_names${e%% *} "; done
for m in "${DEFINED[@]}"; do
  [ "$m" = mX ] && continue
  case "$want_names" in *" $m "*) ;; *) bad "mutant $m is defined but has no expected probe in EXPECT" ;; esac
done
for e in "${EXPECT[@]}"; do caught_by "${e%% *}" "${e#* }"; done
# the crash control itself: mX must be refused as a script that does not parse, so it can never be counted as caught
if "$BASH_BIN" -n "$MUT/scripts/mX.sh" 2>/dev/null; then bad "MX the crash mutant parses (the crash guard is vacuous)"; else ok; fi

echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
# FLOOR is EXACTLY the green run's assertion count (228): every assertion runs through ok()/bad() and the count has no
# data-dependent branch, so there is no slack to hide a deleted row in; adding or removing an assertion means moving this number.
FLOOR=228
if [ "$TOTAL" -lt "$FLOOR" ]; then
  echo "assertion floor tripped: only $TOTAL assertions ran, expected at least $FLOOR."
  exit 1
fi
if [ "$FAIL" -gt 0 ]; then echo "SOME TESTS FAILED"; exit 1; fi
echo "ALL TESTS PASSED"
