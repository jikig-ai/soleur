#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2329  # A && B || C is the assertion idiom; stub bodies are single-quoted on purpose; setup functions are dispatched indirectly
# Suite for plugins/soleur/scripts/lib/bearer-curl.sh (the sourced helper that reads one read-only bearer token from the
# secret store and sends ONE hardened GET). Consumer: skills/ship/scripts/hold-gate-eval.sh (web-acceptance gate).
#
# THE SEAM: `doppler` and `curl` are PATH stubs that answer only the exact argv shapes the helper is expected to use and
# refuse every other argv with exit 64 (logging STUB-MISS), so a flag that is dropped or added is a visible failure. The
# curl stub reads the 0600 config the helper wrote, compares its bearer line with the token the doppler stub serves
# (a mismatch answers 401), and records argv and the TLS-related environment it saw. No network, no real secret store:
# the PATH is a hermetic directory of symlinks that holds NEITHER a real curl NOR a real doppler.
#
# PROPERTY UNDER TEST: the token is read with a fixed project and config, passes a shape guard (48 to 256 characters, CTO ruling D3), reaches curl only through
# a 0600 config file (never argv, never output), curl is hardened (no rc file, no proxy, https only, no redirect, bounded
# time and size, no retry, TLS environment variables hidden), the helper refuses to run under xtrace, and every failure
# is a distinct non-zero return that never prints the token.
#
# ARMS: control, token read, shape guard, xtrace, curl argv, config file, environment, status capture, mutations.

set -uo pipefail
export LC_ALL=C

TMP="$(mktemp -d -t bc-suite.XXXXXXXX)"
trap 'rm -rf "$TMP"' EXIT

SUITE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./test-helpers.sh
source "$SUITE_DIR/test-helpers.sh"
set +e
assert_fixture_dir "$TMP"

REPO_ROOT="$(cd -P "$SUITE_DIR/../../.." && pwd -P)"
LIB_REAL="$REPO_ROOT/plugins/soleur/scripts/lib/bearer-curl.sh"
BASH_BIN="$(command -v bash)"

( assert_eq a b "control" >/dev/null; [[ $FAIL -eq 1 ]] ) \
  || { printf 'FATAL: assert_eq cannot fail -- dispatch is neutered\n' >&2; exit 2; }
[[ -f "$LIB_REAL" ]] || { echo "  FAIL: helper missing: $LIB_REAL"; FAIL=$((FAIL + 1)); print_results 1; exit 1; }

TOKEN='SYNTHtok0123456789abcdefghijklmnopqrstuvwxyzQ9x3'

# --- the hermetic PATH: symlinks to the usual tools, and NO curl, NO doppler -------------------------
mkbin() { # <dir> <tools to leave out...>
  local d="$1" t o p; shift; assert_fixture_dir "$d"; rm -rf "$d"; mkdir -p "$d"
  for t in bash cat env grep head tr sed awk cut wc rm mkdir mktemp dirname basename find ls id sleep timeout gtimeout stat touch tee date cmp sort true false; do
    for o in "$@"; do [[ "$t" == "$o" ]] && continue 2; done
    p="$(command -v "$t" 2>/dev/null)"; [[ "$p" == /* && -x "$p" ]] && ln -sf "$p" "$d/$t"
  done
}
BASE="$TMP/base"; mkbin "$BASE"
BIN="$TMP/bin"; mkbin "$BIN"
cat > "$BIN/doppler" <<'STUB'
#!/usr/bin/env bash
d="${STUB_DIR:?}"
echo "doppler $*" >> "$d/doppler-argv.log"
if [ -f "$d/eat-stdin" ]; then n="$(cat | wc -c | tr -d ' ')"; echo "$n" >> "$d/stdin-bytes"; fi
[ "$*" = "secrets get ${DOPPLER_STUB_NAME:-LEGAL_ACCEPTANCE_VERIFY_TOKEN} --plain --project soleur --config prd" ] \
  || { echo "STUB-MISS $*" >> "$d/doppler-argv.log"; echo "doppler stub: unsupported argv" >&2; exit 64; }
[ ! -f "$d/doppler-fail" ] || { echo "Doppler Error: could not read the secret" >&2; exit 1; }
cat "$d/doppler-token"
STUB
chmod +x "$BIN/doppler"
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
d="${STUB_DIR:?}"
{ printf 'curl'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; } >> "$d/curl-argv.log"
tls="${SSLKEYLOGFILE+x}${CURL_CA_BUNDLE+x}${SSL_CERT_FILE+x}${SSL_CERT_DIR+x}${CURL_HOME+x}${HOSTALIASES+x}${LOCALDOMAIN+x}${RES_OPTIONS+x}${OPENSSL_CONF+x}${OPENSSL_MODULES+x}${LD_PRELOAD+x}${LD_AUDIT+x}${LD_LIBRARY_PATH+x}"
echo "tls=$tls" >> "$d/curl-env.log"
if [ -f "$d/eat-stdin" ]; then n="$(cat | wc -c | tr -d ' ')"; echo "$n" >> "$d/stdin-bytes"; fi
miss() { echo "STUB-MISS $*" >> "$d/curl-argv.log"; echo "curl stub: unsupported argv: $1" >&2; exit 64; }
[ -z "$tls" ] || miss "tls environment visible"
[ "$#" -eq 21 ] || miss "count"
[ "$1" = "--disable" ] && [ "$2" = "--noproxy" ] && [ "$3" = "*" ] && [ "$4" = "--proto" ] && [ "$5" = "=https" ] \
  && [ "$6" = "--max-redirs" ] && [ "$7" = "0" ] && [ "${8}" = "--connect-timeout" ] && [ "${9}" = "5" ] \
  && [ "${10}" = "--max-time" ] && [ "${11}" = "15" ] && [ "${12}" = "--max-filesize" ] && [ "${13}" = "4096" ] \
  && [ "${14}" = "-sS" ] && [ "${15}" = "-o" ] && [ "${17}" = "-w" ] && [ "${18}" = '%{http_code}' ] && [ "${19}" = "--config" ] || miss "flags"
out="${16}"; cfg="${20}"; url="${21}"
if [ -f "$d/url-strict" ]; then
  [[ "$url" =~ ^https://app\.soleur\.ai/api/internal/legal-acceptance/[a-z0-9][a-z0-9-]{0,62}\?hash=[0-9a-f]{64}$ ]] || miss "url"
fi
echo "$url" >> "$d/curl-url.log"
[ -f "$cfg" ] || miss "no config"
[ -n "$(find "$cfg" -perm 600 -print 2>/dev/null)" ] || miss "config mode"
echo "cfg-mode-600" >> "$d/curl-env.log"
rc=0; [ ! -f "$d/curl-rc" ] || rc="$(cat "$d/curl-rc")"
[ "$rc" = 0 ] || { printf '000'; exit "$rc"; }
st=200; [ ! -f "$d/curl-status" ] || st="$(cat "$d/curl-status")"
want="header = \"Authorization: Bearer $(cat "$d/doppler-token")\""
[ "$(cat "$cfg")" = "$want" ] || st=401
: > "$out"
if [ "$st" != 401 ] || [ -f "$d/curl-body-on-401" ]; then [ ! -f "$d/curl-body" ] || cat "$d/curl-body" > "$out"; fi
printf '%s' "$st"
STUB
chmod +x "$BIN/curl"

SC=0
scn() { SC=$((SC + 1)); STUB_DIR="$TMP/scn$SC"; rm -rf "$STUB_DIR"; mkdir -p "$STUB_DIR"; export STUB_DIR; printf '%s\n' "$TOKEN" > "$STUB_DIR/doppler-token"; DRV_PATH="$BIN"; DRV_ENV=""; }

# drive <lib> <body...>: run a snippet that sources <lib> under the stub PATH; stdout/stderr captured; rc in $DRC
drive() {
  local lib="$1" body="$2"
  ( cd "$TMP" && env -i HOME="$TMP" PATH="${DRV_PATH:-$BIN}" STUB_DIR="$STUB_DIR" ${DRV_ENV:-} "$BASH_BIN" -c ". \"$lib\" || exit \$?; $body" ) >"$TMP/drv.out" 2>"$TMP/drv.err"
  DRC=$?
}
outs() { cat "$TMP/drv.out" "$TMP/drv.err" 2>/dev/null; }
# the group ends in `|| true`: under pipefail a log that does not exist (curl never ran) would otherwise make the whole pipeline "fail" and the leak check "pass"
no_token_anywhere() { ! { outs; cat "$STUB_DIR"/curl-argv.log "$STUB_DIR"/curl-url.log "$STUB_DIR"/doppler-argv.log 2>/dev/null || true; } | grep -qF -- "$TOKEN"; }
have() { [[ -s "$STUB_DIR/$1" ]]; }
# T2: the leak detector is under a control. A token placed in each place it reads MUST be flagged, or every "the token is in no output" row proves nothing.
mkdir -p "$TMP/ctl-leak"
for leak in drv.out drv.err curl-argv.log curl-url.log doppler-argv.log; do
  ( STUB_DIR="$TMP/ctl-leak"; TMP="$TMP/ctl-leak"; rm -f "$TMP"/* ; : > "$TMP/drv.out"; : > "$TMP/drv.err"; no_token_anywhere ) \
    || { printf 'FATAL: no_token_anywhere flags a clean run\n' >&2; exit 2; }
  ( STUB_DIR="$TMP/ctl-leak"; TMP="$TMP/ctl-leak"; rm -f "$TMP"/* ; : > "$TMP/drv.out"; : > "$TMP/drv.err"; printf 'x %s y\n' "$TOKEN" > "$TMP/$leak"; ! no_token_anywhere ) \
    || { printf 'FATAL: no_token_anywhere cannot see a token in %s\n' "$leak" >&2; exit 2; }
done
calls_of() { { cat "$STUB_DIR/$1" 2>/dev/null || true; } | grep -c -e "$2" || true; }

( DRV_PATH="$BIN"; assert_fixture_dir "$TMP"; ( cd "$TMP" && env -i PATH="$BIN" STUB_DIR="$TMP" "$BASH_BIN" -c 'doppler bogus' ) >/dev/null 2>&1; [[ $? -eq 64 ]] ) \
  || { printf 'FATAL: the doppler stub does not refuse an unknown argv\n' >&2; exit 2; }
( cd "$TMP" && env -i PATH="$BIN" STUB_DIR="$TMP" "$BASH_BIN" -c 'curl --bogus' ) >/dev/null 2>&1; h2=$?
assert_eq "64" "$h2" "H1: the curl stub refuses an argv it does not know (exit 64)"
( cd "$TMP" && env -i PATH="$BASE" "$BASH_BIN" -c 'command -v curl; command -v doppler' ) >"$TMP/hp.out" 2>&1
assert_eq "0" "$(wc -c < "$TMP/hp.out" | tr -d ' ')" "H2: the hermetic PATH holds no real curl and no real doppler"

URL1="https://app.soleur.ai/api/internal/legal-acceptance/some-key?hash=$(printf 'a%.0s' $(seq 1 64))"

echo "=== Control: token read, one GET, status captured, nothing printed ==="
scn; echo '{"ok":true}' > "$STUB_DIR/curl-body"
drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN || exit 11; bc_get "$STUB_DIR" "'"$URL1"'" || exit 12; echo "status=$BC_STATUS rc=$BC_RC"; cat "$BC_BODY"; bc_clear'
assert_eq "0" "$DRC" "C1: read + get succeed"
assert_eq "1" "$(grep -c '^status=200 rc=0$' "$TMP/drv.out")" "C2: the status is captured"
assert_eq "1" "$(grep -c '^{"ok":true}$' "$TMP/drv.out")" "C3: the body is available at BC_BODY"
no_token_anywhere && { echo "  PASS: C4: the token is in no output, no argv log"; PASS=$((PASS + 1)); } || { echo "  FAIL: C4: the token leaked"; FAIL=$((FAIL + 1)); }
assert_eq "1" "$(calls_of doppler-argv.log '^doppler secrets get LEGAL_ACCEPTANCE_VERIFY_TOKEN --plain --project soleur --config prd$')" "C5: one doppler call with the fixed project and config"
assert_eq "0" "$(calls_of doppler-argv.log 'STUB-MISS')" "C6: no doppler stub miss"
assert_eq "0" "$(calls_of curl-argv.log 'STUB-MISS')" "C7: no curl stub miss"
assert_eq "1" "$(calls_of curl-env.log 'cfg-mode-600')" "C8: the config file was mode 0600 when curl read it"
assert_eq "0" "$([[ -e "$STUB_DIR/bc.cfg" ]] && echo 1 || echo 0)" "C9: the config file (which holds the token) is removed after the call"

echo "=== Arm 1: the token read ==="
scn; drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; echo "rc=$?"; [ -n "$BC_TOKEN" ] && echo set'
assert_eq "1" "$(grep -c '^rc=0$' "$TMP/drv.out")" "T1: a valid token is accepted"
scn; : > "$STUB_DIR/doppler-fail"; drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; echo "rc=$?"; echo "tok=[$BC_TOKEN]"'
assert_eq "1" "$(grep -c '^rc=1$' "$TMP/drv.out")" "T2: a failing secret read is refused"
assert_eq "1" "$(grep -c '^tok=\[\]$' "$TMP/drv.out")" "T2b: and leaves no token behind"
assert_eq "0" "$(outs | grep -c 'Doppler Error')" "T2c: the secret store's own error text is not surfaced"
scn; DRV_PATH="$BASE" drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; echo "rc=$?"'
assert_eq "1" "$(grep -c '^rc=1$' "$TMP/drv.out")" "T3: no doppler on PATH is refused"
scn; printf '' > "$STUB_DIR/doppler-token"; drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; echo "rc=$?"'
assert_eq "1" "$(grep -c '^rc=1$' "$TMP/drv.out")" "T4: an empty secret is refused"
scn; drive "$LIB_REAL" 'bc_read_token "lower;case"; echo "rc=$?"'
assert_eq "1" "$(grep -c '^rc=1$' "$TMP/drv.out")" "T5: a secret name that is not UPPER_SNAKE is refused"
assert_eq "0" "$(calls_of doppler-argv.log 'doppler')" "T5b: and doppler was never called for it"
scn; drive "$LIB_REAL" 'bc_read_token OTHER_SECRET; echo "rc=$?"'
assert_eq "1" "$(grep -c '^rc=1$' "$TMP/drv.out")" "T6: an unexpected argv shape reaches the stub and is refused (exit 64 is a failure, not a token)"
assert_eq "1" "$(calls_of doppler-argv.log 'STUB-MISS')" "T6b: the stub saw the name and refused it"
echo "--- environment cannot redirect the read: DOPPLER_PROJECT/DOPPLER_CONFIG do not change the argv ---"
scn; DRV_ENV="DOPPLER_PROJECT=other DOPPLER_CONFIG=dev DOPPLER_TOKEN=x" drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; echo "rc=$?"'
assert_eq "1" "$(grep -c '^rc=0$' "$TMP/drv.out")" "T7: the explicit --project soleur --config prd argv is used whatever the environment says"
scn; : > "$STUB_DIR/eat-stdin"; drive "$LIB_REAL" 'echo drained-by-nobody | bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; echo "rc=$?"'
assert_eq "0" "$(grep -vcx 0 "$STUB_DIR/stdin-bytes")" "T8: the doppler call sees an empty stdin"

echo "=== Arm 2: the token-shape guard (a quote or newline would inject a curl config directive) ==="
for bad in 'a"b' 'a b' 'a;b' 'a$b' 'a`b' "a'b" 'a\b' 'a#b' 'a,b'; do
  scn; printf '%s\n' "$bad" > "$STUB_DIR/doppler-token"
  drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; echo "rc=$?"'
  assert_eq "1" "$(grep -c '^rc=1$' "$TMP/drv.out")" "S: the token shape '$bad' is refused"
done
scn; printf 'abc\ndef\n' > "$STUB_DIR/doppler-token"; drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; echo "rc=$?"'
assert_eq "1" "$(grep -c '^rc=1$' "$TMP/drv.out")" "S2: a two-line token is refused"
scn; printf '%0600d\n' 0 > "$STUB_DIR/doppler-token"; drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; echo "rc=$?"'
assert_eq "1" "$(grep -c '^rc=1$' "$TMP/drv.out")" "S3: an over-long token is refused"
scn; printf 'Ab9._~+/=-xyzAb9._~+/=-xyzAb9._~+/=-xyzAb9._~+/=-xyz\n' > "$STUB_DIR/doppler-token"; drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; echo "rc=$?"'
assert_eq "1" "$(grep -c '^rc=0$' "$TMP/drv.out")" "S4: every allowed character is accepted"
echo "--- the length bounds are 48 to 256 (CTO ruling D3): both edges, one step either side ---"
for n in 1 32 47 48 49 255 256 257 512 513; do
  scn; printf '%*s\n' "$n" '' | tr ' ' 'a' > "$STUB_DIR/doppler-token"
  drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; echo "rc=$?"'
  if [[ "$n" -ge 48 && "$n" -le 256 ]]; then want=0; else want=1; fi
  assert_eq "1" "$(grep -c "^rc=$want\$" "$TMP/drv.out")" "S6: a token of $n characters is $([[ $want = 0 ]] && echo accepted || echo refused)"
done
scn; printf 'bad"tok\n' > "$STUB_DIR/doppler-token"
drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; bc_get "$STUB_DIR" "'"$URL1"'"; echo "rc=$?"'
assert_eq "0" "$(calls_of curl-argv.log 'curl')" "S5: a refused token means zero curl calls"

echo "=== Arm 3: xtrace ==="
scn; drive "$LIB_REAL" 'true'
assert_eq "0" "$DRC" "X0: control: sourcing without xtrace is fine"
scn; ( cd "$TMP" && env -i HOME="$TMP" PATH="$BIN" STUB_DIR="$STUB_DIR" "$BASH_BIN" -x -c ". \"$LIB_REAL\"; echo \"src-rc=\$?\"" ) >"$TMP/drv.out" 2>"$TMP/drv.err"
assert_eq "1" "$(outs | grep -c '^bearer-curl: refusing to run under xtrace')" "X1: sourcing under xtrace says it refuses (and never reads a token)"
assert_eq "0" "$(calls_of doppler-argv.log 'doppler')" "X1b: no secret was read"
scn; ( cd "$TMP" && env -i HOME="$TMP" PATH="$BIN" STUB_DIR="$STUB_DIR" "$BASH_BIN" -c ". \"$LIB_REAL\"; set -x; bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; echo \"rc=\$?\"; set +x" ) >"$TMP/drv.out" 2>"$TMP/drv.err"
assert_eq "1" "$(grep -c '^rc=1$' "$TMP/drv.out")" "X2: xtrace turned on after sourcing refuses the token read"
assert_eq "0" "$(calls_of doppler-argv.log 'doppler')" "X2b: and doppler was not called"
no_token_anywhere && { echo "  PASS: X2c: nothing traced carries the token"; PASS=$((PASS + 1)); } || { echo "  FAIL: X2c: the token leaked under xtrace"; FAIL=$((FAIL + 1)); }
scn; ( cd "$TMP" && env -i HOME="$TMP" PATH="$BIN" STUB_DIR="$STUB_DIR" "$BASH_BIN" -c ". \"$LIB_REAL\"; bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; set -x; bc_get \"\$STUB_DIR\" \"$URL1\"; echo \"rc=\$?\"; set +x" ) >"$TMP/drv.out" 2>"$TMP/drv.err"
assert_eq "1" "$(grep -c '^rc=1$' "$TMP/drv.out")" "X3: xtrace turned on before the request refuses it"
assert_eq "0" "$(calls_of curl-argv.log 'curl')" "X3b: and curl was not called"
no_token_anywhere && { echo "  PASS: X3c: nothing traced carries the token"; PASS=$((PASS + 1)); } || { echo "  FAIL: X3c: the token leaked under xtrace"; FAIL=$((FAIL + 1)); }

echo "=== Arm 4: the request ==="
scn; drive "$LIB_REAL" 'bc_get "$STUB_DIR" "'"$URL1"'"; echo "rc=$?"'
assert_eq "1" "$(grep -c '^rc=1$' "$TMP/drv.out")" "R1: a request with no token loaded is refused"
assert_eq "0" "$(calls_of curl-argv.log 'curl')" "R1b: and curl was not called"
scn; drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; bc_get "$STUB_DIR" "http://app.soleur.ai/x"; echo "rc=$?"'
assert_eq "1" "$(grep -c '^rc=1$' "$TMP/drv.out")" "R2: a plain-http URL is refused before curl"
assert_eq "0" "$(calls_of curl-argv.log 'curl')" "R2b: and curl was not called"
scn; drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; bc_get "$STUB_DIR/no-such-dir" "'"$URL1"'"; echo "rc=$?"'
assert_eq "1" "$(grep -c '^rc=1$' "$TMP/drv.out")" "R3: a scratch dir that does not exist is refused"
for st in 200 401 404 503 307 500; do
  scn; echo "$st" > "$STUB_DIR/curl-status"
  drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; bc_get "$STUB_DIR" "'"$URL1"'"; echo "rc=$? status=$BC_STATUS"'
  assert_eq "1" "$(grep -c "^rc=0 status=$st\$" "$TMP/drv.out")" "R4: HTTP $st is returned as a status, the call itself succeeded"
  no_token_anywhere && { echo "  PASS: R4b: HTTP $st: the token is in no output and no log"; PASS=$((PASS + 1)); } || { echo "  FAIL: R4b: HTTP $st: the token leaked"; FAIL=$((FAIL + 1)); }
done
for crc in 28 6 7 63 35; do
  scn; echo "$crc" > "$STUB_DIR/curl-rc"
  drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; bc_get "$STUB_DIR" "'"$URL1"'"; echo "rc=$? status=$BC_STATUS curlrc=$BC_RC"'
  assert_eq "1" "$(grep -c "^rc=1 status=000 curlrc=$crc\$" "$TMP/drv.out")" "R5: curl exit $crc is a failed call with status 000"
  no_token_anywhere && { echo "  PASS: R5b: curl exit $crc: the token is in no output and no log"; PASS=$((PASS + 1)); } || { echo "  FAIL: R5b: curl exit $crc: the token leaked"; FAIL=$((FAIL + 1)); }
done
scn; drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; bc_get "$STUB_DIR" "'"$URL1"'"'
assert_eq "0" "$(wc -c < "$TMP/drv.out" | tr -d ' ')" "R5c: bc_get prints nothing on stdout (the helper's functions are silent)"
assert_eq "0" "$(wc -c < "$TMP/drv.err" | tr -d ' ')" "R5d: and nothing on stderr"
scn; echo 28 > "$STUB_DIR/curl-rc"; drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; bc_get "$STUB_DIR" "'"$URL1"'"'
assert_eq "0" "$(wc -c < "$TMP/drv.out" | tr -d ' ')" "R5e: a failed bc_get prints nothing on stdout either"
assert_eq "0" "$(wc -c < "$TMP/drv.err" | tr -d ' ')" "R5f: and nothing on stderr"
scn; printf '%s\n' "OTHERtoken0123456789012345678901234567890123456789" > "$STUB_DIR/doppler-token"
drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; bc_get "$STUB_DIR" "'"$URL1"'"; echo "rc=$? status=$BC_STATUS"'
assert_eq "1" "$(grep -c '^rc=0 status=200$' "$TMP/drv.out")" "R6: instrument: the stub accepts the config it was meant to receive"
scn; drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; printf "%s\n" "DIFFERENTtoken0123456789012345678901234567890123456789" > "$STUB_DIR/doppler-token"; bc_get "$STUB_DIR" "'"$URL1"'"; echo "status=$BC_STATUS"'
assert_eq "1" "$(grep -c '^status=401$' "$TMP/drv.out")" "R7: instrument: the stub can tell a config carrying the wrong bearer (401)"
scn; : > "$STUB_DIR/eat-stdin"; drive "$LIB_REAL" 'echo not-for-curl | { bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; bc_get "$STUB_DIR" "'"$URL1"'"; }; echo done'
assert_eq "0" "$(grep -vcx 0 "$STUB_DIR/stdin-bytes")" "R8: neither doppler nor curl saw the caller's stdin"
assert_eq "2" "$(wc -l < "$STUB_DIR/stdin-bytes" | tr -d ' ')" "R8b: and both were called to see it"

echo "=== Arm 5: the curl argv is exactly the hardened shape; no token on it ==="
scn; drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; bc_get "$STUB_DIR" "'"$URL1"'"'
a="$(head -1 "$STUB_DIR/curl-argv.log")"
flags='[--disable] [--noproxy] [*] [--proto] [=https] [--max-redirs] [0] [--connect-timeout] [5] [--max-time] [15] [--max-filesize] [4096]'
assert_eq "1" "$(printf '%s\n' "$a" | grep -cF -- "curl $flags [-sS] [-o] ")" "A1: the flags are the hardened shape, in order, --disable first"
assert_eq "0" "$(printf '%s\n' "$a" | grep -c -e '-L\]\|--location\|--retry\|--insecure\|\[-k\]\|-H\]\|--header\|Authorization\|--data\|-d\]\|-X\]')" "A2: no redirect-following, retry, TLS bypass, header or body flag on argv"
assert_eq "0" "$(printf '%s\n' "$a" | grep -cF -- "$TOKEN")" "A3: the token is not on argv"
assert_eq "1" "$(printf '%s\n' "$a" | grep -c '\[--config\] \[[^]]*bc.cfg\] \[https://')" "A4: the bearer reaches curl through a config file"
assert_eq "1" "$(printf '%s\n' "$a" | grep -c '^curl \[--disable\]')" "A5: --disable is the FIRST argument (it must precede everything)"
scn; DRV_ENV="SSLKEYLOGFILE=/x CURL_CA_BUNDLE=/x SSL_CERT_FILE=/x SSL_CERT_DIR=/x CURL_HOME=/x HOSTALIASES=/x LOCALDOMAIN=x RES_OPTIONS=x" drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; bc_get "$STUB_DIR" "'"$URL1"'"; echo "rc=$?"'
assert_eq "1" "$(grep -c '^rc=0$' "$TMP/drv.out")" "E0: the call works with the hostile environment set"
assert_eq "1" "$(grep -c '^tls=$' "$STUB_DIR/curl-env.log")" "E1: curl saw none of the TLS and resolver variables"
for hv in OPENSSL_CONF OPENSSL_MODULES LD_PRELOAD LD_AUDIT LD_LIBRARY_PATH; do
  scn; DRV_ENV="$hv=/nonexistent/x" drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; bc_get "$STUB_DIR" "'"$URL1"'"; echo "rc=$?"'
  assert_eq "1" "$(grep -c '^rc=0$' "$TMP/drv.out")" "E3: the call works with $hv set"
  assert_eq "1" "$(grep -c '^tls=$' "$STUB_DIR/curl-env.log")" "E3b: curl saw no $hv"
done
scn; DRV_ENV="SSLKEYLOGFILE=/x" drive "$LIB_REAL" 'bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; bc_get "$STUB_DIR" "'"$URL1"'"; echo "caller-still-has=${SSLKEYLOGFILE-unset}"'
assert_eq "1" "$(grep -c '^caller-still-has=/x$' "$TMP/drv.out")" "E2: the caller's own environment is not mutated (the variables are hidden from curl only)"

echo "=== Arm 6: mutations (each marked line is edited; the targeted check must go RED) ==="
LIBP="$TMP/pristine/bearer-curl.sh"; mkdir -p "$TMP/pristine" "$TMP/mutants"; cp "$LIB_REAL" "$LIBP"
mlib() { # <name> <sed -E expr>: a mutant copy of the helper; prove the mutation LANDED and the mutant still parses
  local d="$TMP/mutants/$1"; mkdir -p "$d"; sed -E "$2" "$LIBP" > "$d/bearer-curl.sh"
  if cmp -s "$LIBP" "$d/bearer-curl.sh"; then echo "  FAIL: mutation $1 did not land"; FAIL=$((FAIL + 1)); return 1; fi
  bash -n "$d/bearer-curl.sh" 2>/dev/null || { echo "  FAIL: mutation $1 does not parse"; FAIL=$((FAIL + 1)); return 1; }
  echo "  PASS: mutation $1 landed"; PASS=$((PASS + 1))
}
# kill_mut <name> <setup-fn> <snippet> <pinned>: the pristine helper gives <pinned>, the mutant must not
kill_mut() {
  local name="$1" setup="$2" snippet="$3" pinned="$4" got
  "$setup"; drive "$LIBP" "$snippet"; got="$(tr '\n' ' ' < "$TMP/drv.out")"
  if [[ "$got" != "$pinned" ]]; then echo "  FAIL: $name: the pristine helper gives '$got', not the pinned '$pinned'"; FAIL=$((FAIL + 1)); return; fi
  "$setup"; drive "$TMP/mutants/$name/bearer-curl.sh" "$snippet"; got="$(tr '\n' ' ' < "$TMP/drv.out")"
  if grep -qE 'command not found|syntax error|unbound variable' "$TMP/drv.err"; then echo "  FAIL: mutant $name CRASHED; a crash is not a kill"; FAIL=$((FAIL + 1))
  elif [[ "$got" != "$pinned" ]]; then echo "  PASS: mutant $name killed ('$got')"; PASS=$((PASS + 1))
  else echo "  FAIL: mutant $name SURVIVED ('$got')"; FAIL=$((FAIL + 1)); fi
}
S_ok() { scn; }
S_short() { scn; printf '%47s\n' '' | tr ' ' 'a' > "$STUB_DIR/doppler-token"; }
S_long() { scn; printf '%257s\n' '' | tr ' ' 'a' > "$STUB_DIR/doppler-token"; }
S_bad() { scn; printf 'bad"tok\n' > "$STUB_DIR/doppler-token"; }
Q_get='bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; bc_get "$STUB_DIR" "'"$URL1"'"; echo "rc=$? status=$BC_STATUS"'
Q_read='bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; echo "rc=$?"'
Q_http='bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; bc_get "$STUB_DIR" "http://app.soleur.ai/x"; echo "rc=$?"'
Q_xt='set -x; bc_read_token LEGAL_ACCEPTANCE_VERIFY_TOKEN; echo "rc=$?"; set +x'
mkdir -p "$TMP/mutants/ctrl"; cp "$LIBP" "$TMP/mutants/ctrl/bearer-curl.sh"
( b=$FAIL; kill_mut ctrl S_ok "$Q_get" "never " >/dev/null; [[ $FAIL -gt $b ]] ) || { printf 'FATAL: kill cannot report a pristine that differs from its pin\n' >&2; exit 2; }
( b=$FAIL; kill_mut ctrl S_ok "$Q_get" "rc=0 status=200 " >/dev/null; [[ $FAIL -gt $b ]] ) || { printf 'FATAL: kill cannot report a survivor\n' >&2; exit 2; }
( b=$FAIL; mlib ctrl2 's/zz-no-such-text-zz/y/' >/dev/null; [[ $FAIL -gt $b ]] ) || { printf 'FATAL: mlib cannot report a mutation that did not land\n' >&2; exit 2; }
mlib shape 's/^(.*)# mut:shape$/ : # mut:shape/' && kill_mut shape S_bad "$Q_read" "rc=1 "
mlib cfg-mode 's/umask 077/umask 022/' && kill_mut cfg-mode S_ok "$Q_get" "rc=0 status=200 "
mlib disable 's/curl --disable --noproxy/curl --noproxy/' && kill_mut disable S_ok "$Q_get" "rc=0 status=200 "
mlib noproxy "s/ --noproxy '\*'//" && kill_mut noproxy S_ok "$Q_get" "rc=0 status=200 "
mlib proto 's/ --proto =https//' && kill_mut proto S_ok "$Q_get" "rc=0 status=200 "
mlib redirs 's/ --max-redirs 0//' && kill_mut redirs S_ok "$Q_get" "rc=0 status=200 "
mlib timeouts 's/ --connect-timeout 5 --max-time 15//' && kill_mut timeouts S_ok "$Q_get" "rc=0 status=200 "
mlib filesize 's/ --max-filesize 4096//' && kill_mut filesize S_ok "$Q_get" "rc=0 status=200 "
mlib scheme 's/^(.*)# mut:scheme$/ : # mut:scheme/' && kill_mut scheme S_ok "$Q_http" "rc=1 "
src_x() { scn; ( cd "$TMP" && env -i HOME="$TMP" PATH="$BIN" STUB_DIR="$STUB_DIR" "$BASH_BIN" -x -c ". \"$1\"; echo \"src-rc=\$?\"" ) 2>&1 | grep -c '^src-rc=78$'; }
mlib xtrace-source 's/^(.*)# mut:xtrace-source$/ : # mut:xtrace-source/' && {
  if [[ "$(src_x "$LIBP")" != 1 ]]; then echo "  FAIL: xtrace-source: the pristine helper does not refuse to be sourced under xtrace"; FAIL=$((FAIL + 1))
  elif [[ "$(src_x "$TMP/mutants/xtrace-source/bearer-curl.sh")" != 1 ]]; then echo "  PASS: mutant xtrace-source killed"; PASS=$((PASS + 1))
  else echo "  FAIL: mutant xtrace-source SURVIVED"; FAIL=$((FAIL + 1)); fi; }
mlib xtrace-read 's/^(.*)# mut:xtrace-read$/ : # mut:xtrace-read/' && kill_mut xtrace-read S_ok "$Q_xt" "rc=1 "
S_tls() { scn; DRV_ENV="SSLKEYLOGFILE=/x CURL_CA_BUNDLE=/x SSL_CERT_FILE=/x"; }
mlib tls-env 's/-u SSLKEYLOGFILE /-u SSLKEYLOGFILE_X /' && kill_mut tls-env S_tls "$Q_get" "rc=0 status=200 "
for hv in OPENSSL_CONF OPENSSL_MODULES LD_PRELOAD LD_AUDIT LD_LIBRARY_PATH; do
  mlib "env-$hv" "s/ -u $hv / /" && eval "S_env_$hv() { scn; DRV_ENV=\"$hv=/nonexistent/x\"; }" && kill_mut "env-$hv" "S_env_$hv" "$Q_get" "rc=0 status=200 "
done
mlib shape-min 's/\[ "\$\{#1\}" -ge 48 \] \|\| return 1/ : /' && kill_mut shape-min S_short "$Q_read" "rc=1 "
mlib shape-max 's/\[ "\$\{#1\}" -le 256 \] \|\| return 1/ : /' && kill_mut shape-max S_long "$Q_read" "rc=1 "
mlib argv-token 's/--config "\$cfg"/-H "Authorization: Bearer $BC_TOKEN"/' && kill_mut argv-token S_ok "$Q_get" "rc=0 status=200 "

print_results 145
