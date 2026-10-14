#!/usr/bin/env bash
# Suite for scripts/lib/bearer-curl.sh (argv-bearer sweep S3, tracker #9597).
#
# PROPERTY. A credential handed to bc_curl reaches the transfer on its STDIN config only: never
# in curl's argument list. A value that is empty, unset, or outside [A-Za-z0-9._~+/=-] produces ZERO
# requests, one value-free marker line and rc 2. bc_hmac_sha256_hex never signs with an empty key.
#
# INSTRUMENT. Rows run the library under a PATH-shim `curl` that records each call (argv NUL-
# delimited, stdin verbatim) and models the one thing the property needs from real curl: stdin is read
# only for `--config -`. The shim is CALIBRATED against the real tool (`curl --libcurl`): exactly one
# header append for a compliant config, a second CURLOPT_URL for an injected one. End-to-end rows then
# run the REAL curl against a loopback server. Every credential is SYNTHESIZED; no value is ever
# printed: comparisons go through [[ == ]] / cmp and report verdicts only.
#
# The config writer's stderr is silenced INSIDE the library's process substitution, so a runner that
# ignores SIGPIPE (`trap '' PIPE`) prints no broken-pipe line; a row below runs that case.
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/bearer-curl.sh"
cd "$REPO_ROOT" || { echo "FATAL: cannot cd to $REPO_ROOT" >&2; exit 2; }

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1" >&2; }

# INSTRUMENT SELF-TEST: drive both helpers once; refuse to continue unless both counters moved.
pass "instrument self-test (pass)"
fail "instrument self-test (fail) — EXPECTED, subtracted below"
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf '[FATAL] INSTRUMENT BROKEN: self-test left PASS=%d FAIL=%d, expected 1/1.\n' "$PASS" "$FAIL" >&2
  exit 2
fi
SELFTEST_FAILS=1    # proven by the check immediately above (PASS==1 and FAIL==1 there)
FAIL=$(( FAIL - SELFTEST_FAILS ))

[[ -f "$LIB" ]] || { printf '[FATAL] library not found: scripts/lib/bearer-curl.sh\n' >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { printf '[FATAL] python3 is required (HMAC rows, loopback server)\n' >&2; exit 2; }
command -v openssl >/dev/null 2>&1 || { printf '[FATAL] openssl is required (HMAC oracle)\n' >&2; exit 2; }
REAL_CURL="$(type -P curl || true)"
[[ -n "$REAL_CURL" ]] || { printf '[FATAL] no real curl (calibration and end-to-end rows)\n' >&2; exit 2; }

TMPD="$(mktemp -d -t bearer-curl-test.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
SERVER_PID=""
cleanup() {
  [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null
  rm -rf "$TMPD"
}
trap cleanup EXIT

# Canonical assert_fixture_dir — byte-identical copy (fixture-scan.py requires the verbatim body).
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
assert_fixture_dir "$TMPD"
SHIMDIR="$TMPD/shim"; CALLS="$TMPD/calls"; OUT="$TMPD/out"
for d in "$SHIMDIR" "$CALLS" "$OUT"; do assert_fixture_dir "$d"; mkdir -p "$d"; done

# The shim. Records every call; reads stdin ONLY for `--config -` (as real curl does); flags any config
# line that is not exactly one `header = "..."` directive as INJECTED.
cat > "$SHIMDIR/curl" <<'SHIM'
#!/usr/bin/env bash
n=$(( $(find "$CALLS_DIR" -name '*.argv' | wc -l) + 1 ))
printf '%s\0' "$@" > "$CALLS_DIR/$n.argv"
printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s' "${SSLKEYLOGFILE-U}" "${CURL_CA_BUNDLE-U}" "${SSL_CERT_FILE-U}" "${SSL_CERT_DIR-U}" "${CURL_HOME-U}" "${OPENSSL_CONF-U}" "${LD_PRELOAD-U}" "${LD_LIBRARY_PATH-U}" "${HOSTALIASES-U}" "${RES_OPTIONS-U}" > "$CALLS_DIR/$n.env"
has_cfg=0; prev=""
for a in "$@"; do
  [[ "$prev" == "--config" && "$a" == "-" ]] && has_cfg=1
  prev="$a"
done
if [[ "$has_cfg" -eq 1 ]]; then
  cat > "$CALLS_DIR/$n.stdin"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^header\ =\ \"[^\"\\]*\"$ ]] || echo INJECTED >> "$CALLS_DIR/$n.injected"
  done < "$CALLS_DIR/$n.stdin"
fi
exit "${SHIM_RC:-0}"
SHIM
chmod +x "$SHIMDIR/curl"
export CALLS_DIR="$CALLS"

reset_calls() { rm -f "$CALLS"/*; }
ncalls() { find "$CALLS" -name '*.argv' | wc -l | tr -d ' '; }

# Run a snippet with the library sourced and the shim first on PATH; stdout+stderr -> $OUT/last;
# prints the snippet's rc. The snippet may use $LIB-sourced functions.
run() {
  PATH="$SHIMDIR:$PATH" bash -c "source '$LIB' && $1" > "$OUT/last" 2>&1
  echo $?
}

# ---------------------------------------------------------------------------------------------------
# C3 — calibration: the shim's INJECTED model matches what REAL curl does with a config on stdin.
# nothing listens on 127.0.0.1:9; --libcurl records the options curl would set.
# ---------------------------------------------------------------------------------------------------
lc_urls() { # $1 = config text; prints the number of CURLOPT_URL lines in the generated C
  local c="$OUT/lc.c"
  printf '%b' "$1" | "$REAL_CURL" --disable -s --max-time 2 --libcurl "$c" --config - http://127.0.0.1:9/ >/dev/null 2>&1
  grep -c 'CURLOPT_URL' "$c" 2>/dev/null || true
}
GOOD_N="$(lc_urls 'header = "X-A: tok"\n')"
BAD_N="$(lc_urls 'header = "X-A: t"\nurl = "http://evil.invalid/"\n')"
if [[ "$GOOD_N" == "1" && "$BAD_N" == "2" ]]; then
  pass "C3 calibration: real curl sets one CURLOPT_URL for a compliant config and a second for an injected line"
else
  printf '[FATAL] C3 calibration failed (good=%s bad=%s): the shim model is not the real tool\n' "$GOOD_N" "$BAD_N" >&2
  exit 2
fi

# ---------------------------------------------------------------------------------------------------
# Compliant call: credential on stdin only.
# ---------------------------------------------------------------------------------------------------
TOK="synthA1b2C3.d4e5-F6_g7~h8+i9/j0=="
reset_calls
rc="$(TOKEN="$TOK" run 'bc_curl demo "Authorization:Bearer :TOKEN" -- -sS --max-time 5 -o /dev/null http://127.0.0.1:9/x')"
[[ "$rc" == "0" ]] && pass "bc_curl well-formed call returns the transfer's rc (0)" || fail "bc_curl well-formed call rc=$rc"
[[ "$(ncalls)" == "1" ]] && pass "bc_curl makes exactly one transfer" || fail "bc_curl call count $(ncalls), expected 1"
if grep -qF -- "$TOK" "$CALLS/1.argv" 2>/dev/null; then fail "credential found in the recorded argv"; else pass "credential is absent from the recorded argv"; fi
EXPECT_CFG="$(printf 'header = "Authorization: Bearer %s"\n' "$TOK")"
if [[ "$(cat "$CALLS/1.stdin" 2>/dev/null)" == "$EXPECT_CFG" ]]; then pass "credential header arrives on stdin as one config directive"; else fail "stdin config differs from the expected single header directive"; fi
[[ ! -e "$CALLS/1.injected" ]] && pass "stdin config holds no directive other than header" || fail "stdin config flagged INJECTED"
first="$(tr '\0' '\n' < "$CALLS/1.argv" | sed -n 1p)"
[[ "$first" == "--disable" ]] && pass "--disable is the first operand (aborts .curlrc parsing)" || fail "first operand is '$first', expected --disable"
grep -qx -- '--noproxy' < <(tr '\0' '\n' < "$CALLS/1.argv") && pass "--noproxy is passed" || fail "--noproxy missing"
if grep -q -- '--max-time' < <(tr '\0' '\n' < "$CALLS/1.argv"); then
  pass "caller-supplied --max-time is passed through"
else fail "--max-time not passed through"; fi
if tr '\0' '\n' < "$CALLS/1.argv" | awk 'BEGIN{n=0} $0=="--max-time"{n++} END{exit !(n==1)}'; then
  pass "no default timeout is added (exactly the caller's one --max-time)"
else fail "library injected or dropped a --max-time"; fi
[[ "$(grep -c . "$OUT/last")" == "0" ]] && pass "a successful call prints nothing of its own" || fail "a successful call printed library output"

# ---------------------------------------------------------------------------------------------------
# Header shapes: API key (empty prefix) and the deploy-webhook triple (three specs).
# ---------------------------------------------------------------------------------------------------
reset_calls
APIKEY="k-synth""_0123-ABC"   # split literal: no contiguous token-shaped string in the source
rc="$(KEY="$APIKEY" run 'bc_curl demo "x-api-key::KEY" -- -sS http://127.0.0.1:9/')"
[[ "$(cat "$CALLS/1.stdin" 2>/dev/null)" == "header = \"x-api-key: ${APIKEY}\"" ]] && pass "empty-prefix spec renders 'name: value'" || fail "empty-prefix spec rendered wrongly"

reset_calls
SIG="$(printf 'x' | HMAC_KEY=k python3 -I -c 'import hashlib,hmac,os,sys;sys.stdout.write(hmac.new(os.environb.get(b"HMAC_KEY"),sys.stdin.buffer.read(),hashlib.sha256).hexdigest())')"
rc="$(SIG="$SIG" CFID="idv.access" CFSEC="secv0123" run 'bc_curl demo "X-Signature-256:sha256=:SIG" "CF-Access-Client-Id::CFID" "CF-Access-Client-Secret::CFSEC" -- -sS http://127.0.0.1:9/')"
if [[ "$(wc -l < "$CALLS/1.stdin" | tr -d ' ')" == "3" && ! -e "$CALLS/1.injected" ]]; then pass "webhook triple renders three header directives"; else fail "webhook triple did not render three clean directives"; fi
grep -qF -- 'header = "CF-Access-Client-Id: idv.access"' "$CALLS/1.stdin" && pass "webhook triple carries the Cloudflare Access id verbatim" || fail "CF Access id line wrong"
if grep -qF -e "$SIG" -e secv0123 -e idv.access < <(tr '\0' '\n' < "$CALLS/1.argv"); then fail "a triple value reached the recorded argv"; else pass "no triple value reaches the recorded argv"; fi

# ---------------------------------------------------------------------------------------------------
# Refusals: hostile / empty / unset values at EVERY spec position -> zero calls, one marker, rc 2.
# ---------------------------------------------------------------------------------------------------
CANARY="CANARYsecret0123"
hostile_values=(
  "${CANARY}\"x"                          # quote
  "${CANARY}"$'\n'"url = \"http://evil.invalid/\""   # newline + injected directive
  "${CANARY}\\"                            # backslash
  "${CANARY} sp"                           # space
  "${CANARY}"$'\t'"tab"                    # tab
  "${CANARY}"$'\r'"cr"                     # CR
  ""                                       # empty
)
refused_rows=0
for pos in 0 1 2; do
  for hv in "${hostile_values[@]}"; do
    reset_calls
    A="aaa111"; B="bbb222"; C="ccc333"
    case "$pos" in 0) A="$hv" ;; 1) B="$hv" ;; 2) C="$hv" ;; esac
    rc="$(A="$A" B="$B" C="$C" run 'bc_curl demo "X-One::A" "X-Two::B" "X-Three::C" -- -sS http://127.0.0.1:9/')"
    refused_rows=$((refused_rows + 1))
    markers="$(grep -c '^SOLEUR_CREDENTIAL_REFUSED script=demo reason=' "$OUT/last")"
    if [[ "$rc" == "2" && "$(ncalls)" == "0" && "$markers" == "1" ]]; then :; else
      fail "refusal at spec position $pos: rc=$rc calls=$(ncalls) markers=$markers (expected 2/0/1)"
      continue
    fi
    if grep -qF -- "$CANARY" "$OUT/last"; then fail "negative canary: a hostile value leaked into the refusal output (position $pos)"; fi
  done
done
[[ "$refused_rows" == "21" ]] && pass "refusal matrix: 3 spec positions x 7 hostile/empty values all return 2 with zero calls and one marker, canary absent" || fail "refusal matrix ran $refused_rows rows, expected 21"

reset_calls
rc="$(run 'unset NOSUCH; bc_curl demo "Authorization:Bearer :NOSUCH" -- -sS http://127.0.0.1:9/')"
[[ "$rc" == "2" && "$(ncalls)" == "0" ]] && pass "an UNSET variable is refused (rc 2, zero calls)" || fail "unset variable: rc=$rc calls=$(ncalls)"
rc="$(run 'set -u; unset NOSUCH; bc_curl demo "Authorization:Bearer :NOSUCH" -- -sS http://127.0.0.1:9/')"
[[ "$rc" == "2" ]] && pass "an UNSET variable is refused under set -u (no unbound-variable abort)" || fail "unset variable under set -u: rc=$rc"

# reason classification
rc="$(T=$'a\nb' run 'bc_curl demo "Authorization:Bearer :T" -- -sS http://x/')"
grep -qx 'SOLEUR_CREDENTIAL_REFUSED script=demo reason=control_char' "$OUT/last" && pass "a control byte is classified reason=control_char" || fail "control byte not classified control_char"
rc="$(T='a"b' run 'bc_curl demo "Authorization:Bearer :T" -- -sS http://x/')"
grep -qx 'SOLEUR_CREDENTIAL_REFUSED script=demo reason=token_shape' "$OUT/last" && pass "a quote is classified reason=token_shape" || fail "quote not classified token_shape"
rc="$(T='a"b' run 'bc_curl "bad name" "Authorization:Bearer :T" -- -sS http://x/')"
grep -qx 'SOLEUR_CREDENTIAL_REFUSED script=unknown reason=token_shape' "$OUT/last" && pass "a malformed script name degrades to script=unknown (marker stays parseable)" || fail "script name not sanitized"

# ---------------------------------------------------------------------------------------------------
# 0x01-0x7f byte sweep: the accepted set is EXACTLY [A-Za-z0-9._~+/=-]; compared with an independent
# expectation, one call per accepted byte and none per rejected byte.
# ---------------------------------------------------------------------------------------------------
sweep_bad=0; sweep_acc=0; sweep_rej=0
for i in $(seq 1 127); do
  hex="$(printf '%02x' "$i")"
  printf -v ch "\\x$hex"
  reset_calls
  v="a${ch}b"
  [[ "${#v}" -eq 3 ]] || { fail "sweep fixture for 0x$hex is not three characters"; continue; }
  rc="$(V="$v" run 'bc_curl sweep "X-A::V" -- -sS http://127.0.0.1:9/')"
  if [[ "$ch" =~ [A-Za-z0-9._~+/=-] ]]; then want_rc=0; want_calls=1; sweep_acc=$((sweep_acc + 1)); else want_rc=2; want_calls=0; sweep_rej=$((sweep_rej + 1)); fi
  if [[ "$rc" != "$want_rc" || "$(ncalls)" != "$want_calls" ]]; then sweep_bad=$((sweep_bad + 1)); fi
done
if [[ "$sweep_bad" == "0" && $((sweep_acc + sweep_rej)) -eq 127 && "$sweep_acc" -gt 50 && "$sweep_rej" -gt 50 ]]; then pass "byte sweep 0x01-0x7f: accepted set equals the token alphabet ($sweep_acc accepted, $sweep_rej refused)"; else fail "byte sweep: $sweep_bad mismatches (accepted=$sweep_acc rejected=$sweep_rej)"; fi

# Must-PASS realistic shapes: a guard that rejects everything cannot pass.
shape_ok=0
for v in "sk-ant""-api03-AbC_dEf-123" "re""_AbCdEf123_4567" "sntrys""_eyJhbGciOiJIUzI1NiJ9.payload.sig" "eyJhbGciOi.eyJzdWIi.abc-_" "0123456789abcdef.access" "hcloud0123ABCDEF"; do
  reset_calls
  rc="$(V="$v" run 'bc_curl shapes "X-A::V" -- -sS http://127.0.0.1:9/')"
  [[ "$rc" == "0" && "$(ncalls)" == "1" ]] && shape_ok=$((shape_ok + 1))
done
[[ "$shape_ok" == "6" ]] && pass "realistic vendor token shapes (api key, re_, sntrys_, JWT, .access id, hex) are accepted" || fail "only $shape_ok of 6 realistic shapes were accepted"

# ---------------------------------------------------------------------------------------------------
# Call-shape errors: rc 64 and zero calls.
# ---------------------------------------------------------------------------------------------------
shape_bad=0
for snippet in \
  'bc_curl demo "Authorization:Bearer :T" http://x/' \
  'bc_curl demo -- http://x/' \
  'bc_curl demo "noColons" -- http://x/' \
  'bc_curl demo "Bad Name:Bearer :T" -- http://x/' \
  'bc_curl demo "Authorization:Be;arer :T" -- http://x/' \
  'bc_curl demo "Authorization:Bearer :T;id" -- http://x/' ; do
  reset_calls
  rc="$(T=ok run "$snippet")"
  [[ "$rc" == "64" && "$(ncalls)" == "0" ]] || { shape_bad=$((shape_bad + 1)); fail "call shape '$snippet' gave rc=$rc calls=$(ncalls), expected 64/0"; }
done
[[ "$shape_bad" == "0" ]] && pass "malformed calls (no --, no spec, bad name/prefix/variable) return 64 with zero calls"

# ---------------------------------------------------------------------------------------------------
# Ordering + refusal under errexit / pipefail callers.
# ---------------------------------------------------------------------------------------------------
reset_calls
rc="$(T='a"b' run 'set -euo pipefail; CODE="$(bc_curl demo "Authorization:Bearer :T" -- -sS http://x/ 2>/dev/null)" || CODE=refused; printf "%s\n" "$CODE"')"
if [[ "$rc" == "0" && "$(cat "$OUT/last")" == "refused" && "$(ncalls)" == "0" ]]; then pass "under set -euo pipefail a refusal reaches the caller's '|| VAR=' arm (no mute abort)"; else fail "errexit caller: rc=$rc out=$(cat "$OUT/last")"; fi

# ---------------------------------------------------------------------------------------------------
# Tracing: each credential-binding function refuses under xtrace (78) and prints no value.
# ---------------------------------------------------------------------------------------------------
reset_calls
rc="$(CANARY_TOK="${CANARY}ok" run 'set -x; bc_curl demo "Authorization:Bearer :CANARY_TOK" -- -sS http://127.0.0.1:9/')"
if [[ "$rc" == "78" && "$(ncalls)" == "0" ]] && ! grep -qF -- "${CANARY}ok" "$OUT/last"; then pass "bc_curl refuses under xtrace (78), makes no call and the trace holds no value"; else fail "bc_curl under xtrace: rc=$rc calls=$(ncalls)"; fi
rc="$(CANARY_TOK="${CANARY}ok" run 'set -x; printf "" | bc_hmac_sha256_hex CANARY_TOK')"
if [[ "$rc" == "78" ]] && ! grep -qF -- "${CANARY}ok" "$OUT/last"; then pass "bc_hmac_sha256_hex refuses under xtrace (78) and the trace holds no value"; else fail "bc_hmac_sha256_hex under xtrace: rc=$rc"; fi

# ---------------------------------------------------------------------------------------------------
# bc_refuse: the pre-guard announcement (same line + marker as the chokepoint; classifies; never leaks).
# ---------------------------------------------------------------------------------------------------
rc="$(PGV="${CANARY}"$'\n'"x" run 'bc_refuse presite PGV')"
if [[ "$rc" == "2" ]] && grep -qx 'SOLEUR_CREDENTIAL_REFUSED script=presite reason=control_char' "$OUT/last" && ! grep -qF -- "$CANARY" "$OUT/last"; then
  pass "bc_refuse: returns 2, prints one marker (control_char) and leaks nothing"
else fail "bc_refuse control-char row: rc=$rc"; fi
rc="$(PGV='a"b' run 'bc_refuse presite PGV')"
grep -qx 'SOLEUR_CREDENTIAL_REFUSED script=presite reason=token_shape' "$OUT/last" && pass "bc_refuse: a quote is classified token_shape" || fail "bc_refuse token_shape row"
rc="$(PGV="${CANARY}ok" run 'set -x; bc_refuse presite PGV')"
if [[ "$rc" == "78" ]] && ! grep -qF -- "${CANARY}ok" "$OUT/last"; then pass "bc_refuse refuses under xtrace (78) and the trace holds no value"; else fail "bc_refuse under xtrace: rc=$rc"; fi

# ---------------------------------------------------------------------------------------------------
# Chokepoint census: `curl` is invoked in exactly one place, and the value check precedes it.
# ---------------------------------------------------------------------------------------------------
NONCOMMENT="$OUT/lib.nocomment"
grep -v '^[[:space:]]*#' "$LIB" > "$NONCOMMENT"
CURL_RE='(^|[^A-Za-z0-9_-])curl([^A-Za-z0-9_-]|$)'   # a bare, path-qualified, quoted or substituted `curl`; not bc_curl
curl_lines="$(grep -cE "$CURL_RE" "$NONCOMMENT")"
body_start="$(grep -n '^_bc_send()' "$NONCOMMENT" | cut -d: -f1)"
body_end="$(awk -v s="$body_start" 'NR>s && /^}/ {print NR; exit}' "$NONCOMMENT")"
in_send="$(awk -v s="$body_start" -v e="$body_end" 'NR>=s && NR<=e && /(^|[^A-Za-z0-9_-])curl([^A-Za-z0-9_-]|$)/' "$NONCOMMENT" | wc -l | tr -d ' ')"
ok_line="$(awk -v s="$body_start" -v e="$body_end" 'NR>=s && NR<=e && /bc_ok "/ {print NR; exit}' "$NONCOMMENT")"
curl_line="$(awk -v s="$body_start" -v e="$body_end" 'NR>=s && NR<=e && /(^|[^A-Za-z0-9_-])curl([^A-Za-z0-9_-]|$)/ {print NR; exit}' "$NONCOMMENT")"
if [[ "$curl_lines" == "1" && "$in_send" == "1" && -n "$ok_line" && -n "$curl_line" && "$ok_line" -lt "$curl_line" ]]; then
  pass "chokepoint census: curl appears once, inside _bc_send, after the per-value bc_ok check"
else
  fail "chokepoint census: curl lines=$curl_lines inside _bc_send=$in_send ok_line=$ok_line curl_line=$curl_line"
fi
if grep -nE '^[[:space:]]*exit([[:space:]]|$)' "$NONCOMMENT" >/dev/null 2>&1; then fail "the library calls exit (a sourced library must return)"; else pass "the library never calls exit"; fi
if grep -qE -- '--max-time|-m [0-9]' "$NONCOMMENT"; then fail "the library adds a timeout (must stay byte-neutral)"; else pass "the library adds no default timeout"; fi

# ---------------------------------------------------------------------------------------------------
# Mutation-style rows on a COPY of the library: the guard rows must go red when the guard is removed.
# ---------------------------------------------------------------------------------------------------
mut_lib="$OUT/mut.sh"
sed 's/bc_ok "\$_bc_val" || {/true || {/' "$LIB" > "$mut_lib"
if cmp -s "$mut_lib" "$LIB"; then
  fail "mutation did not land (guard removal)"
else
  reset_calls
  PATH="$SHIMDIR:$PATH" T='a"b' bash -c "source '$mut_lib' && bc_curl demo 'Authorization:Bearer :T' -- -sS http://x/" >/dev/null 2>&1
  [[ "$(ncalls)" == "1" ]] && pass "mutant with the value check removed sends the hostile value (the refusal rows would go red)" || fail "guard-removal mutant did not change behaviour: calls=$(ncalls)"
fi

# ---------------------------------------------------------------------------------------------------
# Trailing whitespace (a secret pasted with a newline) is trimmed; whitespace INSIDE a value still refuses.
# ---------------------------------------------------------------------------------------------------
reset_calls
rc="$(V=$'tok-A1b2\n' run 'bc_curl ws "X-A::V" -- -sS http://127.0.0.1:9/')"
if [[ "$rc" == "0" && "$(cat "$CALLS/1.stdin" 2>/dev/null)" == 'header = "X-A: tok-A1b2"' ]]; then pass "a trailing newline is trimmed: the wire carries the clean value, one directive"; else fail "trailing newline: rc=$rc"; fi
reset_calls
rc="$(V="tok-A1b2 "$'\t'" " run 'bc_curl ws "X-A::V" -- -sS http://127.0.0.1:9/')"
[[ "$rc" == "0" && "$(cat "$CALLS/1.stdin" 2>/dev/null)" == 'header = "X-A: tok-A1b2"' ]] && pass "trailing spaces and tabs are trimmed too" || fail "trailing blanks: rc=$rc"
reset_calls
rc="$(V=$' \n' run 'bc_curl ws "X-A::V" -- -sS http://127.0.0.1:9/')"
[[ "$rc" == "2" && "$(ncalls)" == "0" ]] && pass "a value that is only whitespace is refused (empty after the trim)" || fail "whitespace-only value: rc=$rc"
rc="$(run "bc_ok \$'abc\\n'")"
[[ "$rc" == "0" ]] && pass "bc_ok judges the value after trimming (a real trailing newline byte is accepted)" || fail "bc_ok trim: rc=$rc"
rc="$(run "bc_ok \$'ab\\nc'")"
[[ "$rc" == "1" ]] && pass "bc_ok still refuses a newline INSIDE the value" || fail "bc_ok interior newline: rc=$rc"

# ---------------------------------------------------------------------------------------------------
# bc_ok_var: by NAME, never traced.
# ---------------------------------------------------------------------------------------------------
rc="$(GOODV=abc.def run 'bc_ok_var GOODV')"; [[ "$rc" == "0" ]] && pass "bc_ok_var accepts a usable value by name" || fail "bc_ok_var good: rc=$rc"
rc="$(BADV='a"b' run 'bc_ok_var BADV')"; [[ "$rc" == "1" ]] && pass "bc_ok_var rejects an unusable value by name" || fail "bc_ok_var bad: rc=$rc"
rc="$(run 'unset NOSUCH; bc_ok_var NOSUCH')"; [[ "$rc" == "1" ]] && pass "bc_ok_var rejects an unset variable" || fail "bc_ok_var unset: rc=$rc"
rc="$(CANARY_TOK="${CANARY}ok" run 'set -x; bc_ok_var CANARY_TOK')"
if [[ "$rc" == "78" ]] && ! grep -qF -- "${CANARY}ok" "$OUT/last"; then pass "bc_ok_var refuses under xtrace (78) and the trace holds no value"; else fail "bc_ok_var under xtrace: rc=$rc"; fi
# The name is validated before the indirect expansion: a subscript would otherwise be EVALUATED by `${!name}`.
rc="$(run "bc_ok_var 'a[\$(echo SUBSCRIPT_RAN)]'")"
if [[ "$rc" == "64" ]] && ! grep -q SUBSCRIPT_RAN "$OUT/last"; then pass "bc_ok_var refuses a malformed name (64) without evaluating a subscript in it"; else fail "bc_ok_var malformed name: rc=$rc"; fi
rc="$(run 'bc_ok_var _bc_val')"; [[ "$rc" == "64" ]] && pass "bc_ok_var refuses a name that would alias the library's own locals (_bc_*)" || fail "bc_ok_var _bc_ alias: rc=$rc"

# ---------------------------------------------------------------------------------------------------
# Arguments after `--` may not undo the property (verbose, redirects, second config, credential flags,
# stdin body); benign arguments pass. Zero requests are made for a refused call.
# ---------------------------------------------------------------------------------------------------
tail_bad=0; tail_n=0
tail_cases=(
  "-v" "--verbose" "--trace-ascii -" "--trace x" "--trace-config" "--trace-time" "--trace-ids" "-sSv"
  "-L" "--location" "-sSL" "--location-trusted"
  "-K x" "-K/dev/stdin" "--config x" "--config=x" "--next" "-:" "--disable" "-q"
  "-u a:b" "-uA:B" "--user a:b" "--oauth2-bearer x" "-b c=d" "-bc=d" "--cookie c=d" "--proxy-user a:b"
  "-H Private-Token:x" "-H x-api-key:x" "-H api-key:x" "-H apikey:x" "-H X-Auth-Token:x" "-H X-Vault-Token:x"
  "--header Authorization:x" "--header=authorization:x" "-HAuthorization:x" "-sSH Authorization:x" "-H Cookie:x"
  "-H Proxy-Authorization:x" "-H X-Signature-256:x" "-H X-Hub-Signature:x" "-H X-Hub-Signature-256:x"
  "-H CF-Access-Client-Id:x" "-H CF-Access-Client-Secret:x" "-H X-Soleur-Kb-Drift-Signature:x"
  "-d @-" "-d@-" "-sSd @-" "--data @-" "--data=@-" "--data-binary @-" "--data-raw @-" "--data-ascii @-" "--data-urlencode x@-"
  "--json @-" "-F f=@-" "-T -" "--upload-file=-" "--data @/dev/stdin"
  "--libcurl x" "-k" "--insecure" "--cacert x" "--capath x" "--proxy http://p" "-x http://p" "--preproxy http://p"
  "--noproxy x" "--resolve a:1:2" "--connect-to a:1:b:2" "--proxy-header x:y" "--proxy-insecure" "--proxy-anyauth" "--proxytunnel" "--proxy1.0 h" "--trace-envelope" "--netrc-x" "--location-x"
  "-H X-Gitlab-Token:x" "-H X-Access-Token:x" "-H X-Amz-Security-Token:x" "-H X-Github-Token:x" "-H Authentication:x" "-H X-Signature:x"
  "-H @f" "-H @-" "--form-string a=@-" "--url-query @-" "--data @/dev/fd/0" "--data @/proc/self/fd/0" "--data @/dev/./stdin"
  "-F 'a=<-'" "-F 'a=@-;type=text/plain'" "--form='a=@-;filename=f'" "--expand-data @-" "--expand-json @-" "--expand-form a=@-" "--variable x@-"
  "-E x:y" "-U a:b" "-n" "--netrc" "--unix-socket x" "--socks5 h" "--cert x" "--interface x" "--doh-url x" "--dns-servers x"
  "--verb" "--locat" "--trace-a" "--heade Authorization:x" "--da @-" "--data-bin @-" "--varia x@-" "--prox http://p" "--sock h"
  "--"
)
for bad in "${tail_cases[@]}"; do
  tail_n=$((tail_n + 1))
  reset_calls
  # shellcheck disable=SC2086  # word splitting of the fixture is the point
  rc="$(GOODV=abc run "bc_curl tail 'X-A::GOODV' -- -sS $bad http://127.0.0.1:9/")"
  # "refused" is in every guard message and in none of the other 64 causes (malformed spec, missing --, no spec).
  if [[ "$rc" != "64" || "$(ncalls)" != "0" ]] || ! grep -q 'refused' "$OUT/last"; then tail_bad=$((tail_bad + 1)); fail "forbidden argument '$bad' was not refused by the guard (rc=$rc calls=$(ncalls))"; fi
done
[[ "$tail_bad" == "0" ]] && pass "tail-argument guard: all $tail_n forbidden spellings (separate, attached, clustered, =-joined; every deny-list alternative) return 64 with a guard message and zero requests"
reset_calls
rc="$(GOODV=abc run "bc_curl tail 'X-A::GOODV' -- -sS http://127.0.0.1:9/ -H")"
[[ "$rc" == "64" && "$(ncalls)" == "0" ]] && grep -q 'refused' "$OUT/last" && pass "tail-argument guard: a value-taking option left without its value at the end is refused" || fail "dangling -H: rc=$rc calls=$(ncalls)"
# A value that LOOKS like an option is the value of the option before it (curl's own parsing), never judged as an option.
cons_bad=0
for c in A c C D e m o P Q r w X y Y z t H d T F; do
  reset_calls
  rc="$(GOODV=abc run "bc_curl tail 'X-A::GOODV' -- -sS -$c -v http://127.0.0.1:9/")"
  if [[ "$rc" != "0" || "$(ncalls)" != "1" ]]; then cons_bad=$((cons_bad + 1)); fail "'-$c -v': the value of -$c was judged as an option (rc=$rc calls=$(ncalls))"; fi
done
[[ "$cons_bad" == "0" ]] && pass "tail-argument guard: the next token of every value-taking short option is consumed as its value (-w -L, -o -v, -X -K ...)"
reset_calls
rc="$(GOODV=abc run "bc_curl tail 'X-A::GOODV' -- -sS -H ' Authorization: x' http://127.0.0.1:9/")"
[[ "$rc" == "64" && "$(ncalls)" == "0" ]] && pass "tail-argument guard: a header with leading whitespace is judged after the whitespace is dropped" || fail "leading-space credential header: rc=$rc calls=$(ncalls)"
reset_calls
rc="$(GOODV=abc run "bc_curl tail 'X-A::GOODV' -- -sSf -I -g --proto '=https' -m 30 --connect-timeout 5 -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H 'Accept: x' -d '{}' -D - --data-raw '[]' -XPUT -m30 -o/dev/null -HAccept:y -sSfo /dev/null -d@file --data-urlencode a=b -F f=@file http://127.0.0.1:9/")"
[[ "$rc" == "0" && "$(ncalls)" == "1" ]] && pass "tail-argument guard: the benign argument shapes the converted sites use all pass" || fail "benign tail shapes refused: rc=$rc calls=$(ncalls)"

# ---------------------------------------------------------------------------------------------------
# The library's own argument set is pinned exactly, and the TLS-subverting environment is unset.
# ---------------------------------------------------------------------------------------------------
reset_calls
rc="$(GOODV=abc SSLKEYLOGFILE=/tmp/k CURL_CA_BUNDLE=/tmp/ca SSL_CERT_FILE=/tmp/c SSL_CERT_DIR=/tmp/d CURL_HOME=/tmp/h OPENSSL_CONF=/tmp/o LD_PRELOAD='' LD_LIBRARY_PATH=/tmp/l HOSTALIASES=/tmp/ha RES_OPTIONS=x run 'bc_curl pin "X-A::GOODV" -- -sS --max-time 5 http://127.0.0.1:9/x')"
want_argv=$'--disable\n--noproxy\n*\n-sS\n--max-time\n5\nhttp://127.0.0.1:9/x\n--config\n-'
[[ "$(tr '\0' '\n' < "$CALLS/1.argv")" == "$want_argv" ]] && pass "argv pin: exactly --disable --noproxy '*' <caller args> --config - (nothing added, nothing reordered)" || fail "library argv differs from the pinned shape"
[[ "$(cat "$CALLS/1.env")" == "U|U|U|U|U|U|U|U|U|U" ]] && pass "the TLS key-log, CA-bundle, cert, curl-home, OpenSSL-config, loader and resolver environment is unset for the transfer" || fail "TLS-subverting environment reached curl: $(cat "$CALLS/1.env")"

# ---------------------------------------------------------------------------------------------------
# A runner that ignores SIGPIPE prints no broken-pipe line, even when curl exits before reading its config.
# ---------------------------------------------------------------------------------------------------
big="$(head -c 100000 /dev/zero | tr '\0' 'a')"   # one env string is capped at 128 KiB: larger fails to exec and tests nothing
# --no-such-option-xyz passes the guard and real curl exits 2 BEFORE it reads the config, so the writer sees a closed pipe.
out_pipe="$( (trap '' PIPE; BIGV="$big" PATH="$PATH" bash -c "source '$LIB' && bc_curl pipe 'X-A::BIGV' -- -sS --no-such-option-xyz http://127.0.0.1:9/; echo REACHED_RC=\$?" ) 2>&1 )"
if ! grep -q 'REACHED_RC=2' <<<"$out_pipe" || ! grep -qi 'unknown' <<<"$out_pipe"; then
  fail "SIGPIPE row did not reach the library and an early-exiting curl (positive control): $(head -c 160 <<<"$out_pipe")"
elif grep -qiE 'broken pipe|write error|printf:' <<<"$out_pipe"; then fail "SIGPIPE-ignoring runner printed a pipe error: $(head -c 120 <<<"$out_pipe")"
else pass "under trap '' PIPE with a 100 KB value and a curl that exits before reading its config, no broken-pipe line is printed (the run reached curl's own error)"; fi
# The row can fail: with the writer's stderr redirect removed from the library the pipe error reappears.
mut_pipe="$OUT/mut-pipe.sh"
sed 's# 2>/dev/null)$#)#' "$LIB" > "$mut_pipe"
if diff -q "$LIB" "$mut_pipe" >/dev/null; then fail "SIGPIPE mutant did not land (the writer's 2>/dev/null was not found)"; else
  out_pipe_m="$( (trap '' PIPE; BIGV="$big" PATH="$PATH" bash -c "source '$mut_pipe' && bc_curl pipe 'X-A::BIGV' -- -sS --no-such-option-xyz http://127.0.0.1:9/" ) 2>&1 )"
  grep -qiE 'broken pipe|write error|printf:' <<<"$out_pipe_m" && pass "mutant without the writer's stderr redirect prints the broken-pipe line (the SIGPIPE row above is not vacuous)" || fail "SIGPIPE mutant stayed silent: $(head -c 160 <<<"$out_pipe_m")"
fi

mut2="$OUT/mut2.sh"
sed 's/_bc_tail_ok "\$@" || return 64/true/' "$LIB" > "$mut2"
if cmp -s "$mut2" "$LIB"; then
  fail "mutation did not land (tail-guard removal)"
else
  reset_calls
  GOODV=abc PATH="$SHIMDIR:$PATH" bash -c "source '$mut2' && bc_curl demo 'X-A::GOODV' -- -sS -v http://x/" >/dev/null 2>&1
  [[ "$(ncalls)" == "1" ]] && pass "mutant with the tail-argument guard removed lets -v through (the tail rows would go red)" || fail "tail-guard-removal mutant did not change behaviour: calls=$(ncalls)"
fi

# ---------------------------------------------------------------------------------------------------
# Real curl, end to end, against a loopback server that records the request headers.
# ---------------------------------------------------------------------------------------------------
SRV="$OUT/server.py"
cat > "$SRV" <<'PY'
import http.server, sys
out = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(out, "w") as f:
            for k, v in self.headers.items():
                f.write("%s: %s\n" % (k, v))
        self.send_response(204)
        self.end_headers()
    def log_message(self, *a):
        pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
srv.timeout = 15   # a failed earlier row must not leave this blocked in accept
with open(out + ".port", "w") as f:
    f.write(str(srv.server_address[1]))
srv.handle_request()
PY
HDRS="$OUT/headers"
python3 "$SRV" "$HDRS" >/dev/null 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 50); do [[ -s "$HDRS.port" ]] && break; sleep 0.1; done
PORT="$(cat "$HDRS.port" 2>/dev/null || true)"
if [[ "$PORT" =~ ^[0-9]+$ ]]; then
  CODE="$(TOKEN="$TOK" PATH="$PATH" bash -c "source '$LIB' && bc_curl e2e 'Authorization:Bearer :TOKEN' -- -sS -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1:$PORT/x" 2>/dev/null)"
  [[ "$CODE" == "204" ]] && pass "real curl end to end: the request completes (204) through the stdin config" || fail "real curl end to end returned '$CODE'"
  if grep -qixF -- "authorization: Bearer $TOK" "$HDRS"; then pass "real curl end to end: the server received the credential header byte-for-byte"; else fail "server did not receive the expected Authorization header"; fi
else
  fail "loopback server did not start"; fail "loopback server did not start (header row)"
fi
[[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null
SERVER_PID=""

# Real curl against a closed port: the transport failure is curl's, not a refusal.
rc="$(TOKEN="$TOK" PATH="$PATH" bash -c "source '$LIB' && bc_curl e2e 'Authorization:Bearer :TOKEN' -- -sS --max-time 3 -o /dev/null http://127.0.0.1:9/" >/dev/null 2>&1; echo $?)"
[[ "$rc" == "7" ]] && pass "real curl, closed port: curl's own transport rc (7) passes through" || fail "closed-port rc=$rc, expected curl's 7"
# A hostile value through REAL curl never opens a second URL.
rc="$(TOKEN=$'x"\nurl = "http://evil.invalid/' PATH="$PATH" bash -c "source '$LIB' && bc_curl e2e 'Authorization:Bearer :TOKEN' -- -sS --max-time 3 -o /dev/null http://127.0.0.1:9/" >/dev/null 2>&1; echo $?)"
[[ "$rc" == "2" ]] && pass "real curl, injection attempt: refused (2) before any transfer" || fail "injection attempt rc=$rc, expected 2"

# ---------------------------------------------------------------------------------------------------
# bc_hmac_sha256_hex oracle.
# ---------------------------------------------------------------------------------------------------
hm() { # $1 keyvar, stdin message
  PATH="$PATH" bash -c "source '$LIB' && bc_hmac_sha256_hex $1" 2>/dev/null
}
KEYV="synthetic-hmac-key-0123"
want="$(printf '' | openssl dgst -sha256 -hmac "$KEYV" | sed 's/.*= //')"
got="$(printf '' | KEYV="$KEYV" hm KEYV; echo " rc=$?")"
[[ "$got" == "$want rc=0" ]] && pass "HMAC oracle: empty body matches openssl dgst -hmac" || fail "HMAC empty-body mismatch"
BODY='{"command":"deploy","tag":"v1.2.3"}'
want="$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$KEYV" | sed 's/.*= //')"
got="$(printf '%s' "$BODY" | KEYV="$KEYV" hm KEYV)"
[[ "$got" == "$want" ]] && pass "HMAC oracle: JSON body matches openssl dgst -hmac" || fail "HMAC JSON-body mismatch"
# RFC 4231 test case 2 (key 'Jefe').
got="$(printf 'what do ya want for nothing?' | K=Jefe hm K)"
[[ "$got" == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843" ]] && pass "HMAC oracle: RFC 4231 test case 2" || fail "HMAC RFC 4231 case 2 mismatch"
# RFC 4231 test case 1 (key = 20 x 0x0b).
k1="$(printf '\x0b%.0s' $(seq 1 20))"
got="$(printf 'Hi There' | K="$k1" hm K)"
[[ "$got" == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7" ]] && pass "HMAC oracle: RFC 4231 test case 1" || fail "HMAC RFC 4231 case 1 mismatch"
# Empty / unset key: rc 1, no output (never signs with b"").
out="$(printf 'x' | K="" hm K; echo "rc=$?")"
[[ "$out" == "rc=1" ]] && pass "HMAC: an empty key returns 1 and prints nothing" || fail "HMAC empty key: '$out'"
out="$(printf 'x' | hm NOSUCHVAR; echo "rc=$?")"
[[ "$out" == "rc=1" ]] && pass "HMAC: an unset key returns 1 and prints nothing" || fail "HMAC unset key: '$out'"
# python3 absent: rc 1.
NOPY="$OUT/nopy"; assert_fixture_dir "$NOPY"; mkdir -p "$NOPY"
for t in bash cat sed tr; do ln -sf "$(type -P $t)" "$NOPY/$t"; done
out="$(printf 'x' | K=abc PATH="$NOPY" "$NOPY/bash" -c "source '$LIB' && bc_hmac_sha256_hex K" 2>/dev/null; echo " rc=$?")"
[[ "$out" == " rc=1" ]] && pass "HMAC: python3 absent returns 1 and prints nothing" || fail "HMAC python3-absent: '$out'"
# The key never reaches argv: the python child carries it in its environment only.
got="$(printf 'x' | K="${CANARY}hmac" PATH="$PATH" bash -c "source '$LIB' && bc_hmac_sha256_hex K" 2>&1)"
grep -qF -- "${CANARY}hmac" <<<"$got" && fail "negative canary: the HMAC key appeared in the function's output" || pass "negative canary: the HMAC key does not appear in the function's output"
if grep -nE -- 'python3 -I -c .*\$\{?!?_bc_keyvar|hmac.*"\$\{!' "$NONCOMMENT" >/dev/null 2>&1; then fail "the key variable is expanded into a python argument"; else pass "the key is handed to python by environment prefix, not by argument"; fi
grep -qF 'HMAC_KEY="${!_bc_keyvar:-}" python3 -I -c' "$LIB" && pass "the HMAC snippet is the canonical S2 form (per-command env prefix, python3 -I)" || fail "the HMAC call differs from the canonical form"

# ---------------------------------------------------------------------------------------------------
# Verdicts, with the floor in the form guard-vacuity-floor.test.sh can mutate.
# ---------------------------------------------------------------------------------------------------
printf '\nbearer-curl.test.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
# SELFTEST_PASSES is a literal ADJACENT to its use: the meta-guard slices the floor block into a mutant
# with every counter zeroed, and a subtrahend bound far away is unbound there. The self-test above
# asserts PASS==1 at that point, which proves the literal.
SELFTEST_PASSES=1
REAL=$(( PASS - SELFTEST_PASSES ))
MIN_ASSERTIONS=69
if [[ "$REAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity assertion floor: only %d real assertion(s) ran (PASS=%d minus %d self-test), expected >= %d.\n' \
    "$REAL" "$PASS" "$SELFTEST_PASSES" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
