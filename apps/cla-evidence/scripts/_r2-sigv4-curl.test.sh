#!/usr/bin/env bash
# Tests for _r2-sigv4-curl.sh — the ONE curl that carries the R2 SigV4 key id and
# secret in apps/cla-evidence (#9756). RED-first per cq-write-failing-tests-before.
#
# THE PROPERTY: neither value of the pair ever appears on a curl argv; a malformed value
# makes ZERO requests and prints the value-free refusal marker; a request that does go
# out is pinned to a canonical R2 origin and carries only the arguments the two callers use.
#
# WHAT EVERY ROW READS: recorded wire data. The recording `curl` stub on PATH drains stdin
# unconditionally and records argv, stdin and its own environment (booleans only, never
# values); it exits 99 when stdin carries no `user = "` line or when it receives an argument
# or URL it was not scripted for, so a missing credential channel cannot be served a 200.
# One row (the real-curl wire row) sends the helper's request through the REAL curl to a
# loopback listener and reads what the listener received. python3 serves that one row only.
#
# Every fixture credential is synthesized at run time from /dev/urandom pieces: the id and
# the secret are DISTINCT, neither contains the other. Nothing here prints a value; every
# message carries labels, lengths and booleans only.
# shellcheck disable=SC2166  # `test a -a b` keeps each row one predicate; every operand is a quoted scalar
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/_r2-sigv4-curl.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

TMP_ROOT=$(mktemp -d -t r2sigv4test.XXXXXXXX) || { echo "FATAL: cannot create scratch root" >&2; exit 1; }
: "${TMP_ROOT:?}"
[[ "$TMP_ROOT" == /* && -d "$TMP_ROOT" && ! -L "$TMP_ROOT" ]] || { echo "FATAL: bad scratch root" >&2; exit 1; }
readonly TMP_ROOT
LISTENER_PID=""
trap '[[ -z "$LISTENER_PID" ]] || kill "$LISTENER_PID" 2>/dev/null; rm -rf -- "$TMP_ROOT"' EXIT INT TERM

# The canonical fixture-dir assertion, byte-equal to the definition in
# plugins/soleur/test/test-helpers.sh (comments stripped). Edit there, then re-sync here.
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
assert_fixture_dir "$TMP_ROOT"

fails=0
passes=0
pass() { echo "  PASS: $1"; passes=$((passes + 1)); }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); }

# Instrument self-test: drive both helpers before any real case, so a gutted helper
# cannot report a clean sweep. Reports with printf + exit, never through the helpers it guards.
pass "instrument self-test (pass path)"
fail "instrument self-test (fail path — expected, subtracted below)"
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf 'FATAL: assertion helpers are not dispatching (passes=%s fails=%s)\n' "$passes" "$fails" >&2
  exit 2
fi
fails=0

# t LABEL CMD... — pass when CMD succeeds. `_not` inverts a command.
t() { local label="$1"; shift; if "$@"; then pass "$label"; else fail "$label"; fi; }
_not() { ! "$@"; }

echo "_r2-sigv4-curl.test.sh"

if [[ ! -r "$HELPER" ]]; then
  echo "  FAIL: $HELPER does not exist (RED phase expected output)."
  echo "0 passed, 1 failed"
  exit 1
fi
for tool in curl python3 od tr env timeout; do
  command -v "$tool" >/dev/null 2>&1 || { echo "  FAIL: $tool not on PATH — a missing tool is a hard FAIL, not a skip"; exit 1; }
done

REAL_CURL="$(command -v curl)"
echo "  curl: $("$REAL_CURL" --version | head -n 1 | cut -d' ' -f1-2)"

# ── Synthesized fixtures ─────────────────────────────────────────────────────
rand_hex() { od -An -N"$(( $1 / 2 ))" -tx1 /dev/urandom | tr -d ' \n'; }
ID=""; SECRET=""
while :; do
  ID="$(rand_hex 32)"; SECRET="$(rand_hex 64)"
  [[ "${#ID}" -eq 32 && "${#SECRET}" -eq 64 ]] || continue
  [[ "$SECRET" != *"$ID"* && "$ID" != *"$SECRET"* ]] || continue
  [[ "$ID" != "$(printf '%32s' '' | tr ' ' "${ID:0:1}")" ]] || continue
  break
done
HOST32="$(rand_hex 32)"
URL="https://${HOST32}.r2.cloudflarestorage.com/soleur-cla-evidence/signatures/synth.json"

# shellcheck source=/dev/null
source "$HELPER"

BIN="$TMP_ROOT/bin"; LOGD="$TMP_ROOT/log"
assert_fixture_dir "$BIN"; assert_fixture_dir "$LOGD"
mkdir -p "$BIN" "$LOGD"

# The recording stub. Modes (env, read at run time):
#   record (default): print STUB_CODE (default 200) and exit 0.
#   wire:             exec the REAL curl against a loopback listener (URL host rewritten,
#                     `--proto =https` relaxed to `=http` for the plain-http listener);
#                     STUB_DROP_CONFIG=1 removes `--config -` (the discrimination control).
cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
log="${STUB_LOG:?}"
n=$(( $(wc -l < "$log/calls" 2>/dev/null || echo 0) + 1 ))
printf '%s\n' "$n" >> "$log/calls"
{ printf 'CALL %s\n' "$n"; printf '%s\n' "$@"; } >> "$log/argv"
for v in SSL_CERT_FILE CURL_CA_BUNDLE LD_PRELOAD SSLKEYLOGFILE R2_CLA_EVIDENCE_ACCESS_KEY_ID R2_CLA_EVIDENCE_SECRET R2_S3_ACCESS_KEY_ID R2_S3_SECRET_ACCESS_KEY; do
  if [[ -v $v ]]; then echo "$v=set"; else echo "$v=unset"; fi
done >> "$log/env"
stdin=$(cat; printf x); stdin=${stdin%x}
printf '%s' "$stdin" > "$log/stdin.$n"
[[ "$stdin" == *'user = "'* ]] || { echo "stub: stdin carries no user line" >&2; exit 99; }
args=("$@")
last="${args[$(( ${#args[@]} - 1 ))]}"
[[ "${args[0]}" == "--disable" ]] || { echo "stub: --disable is not first" >&2; exit 99; }
[[ "$last" == https://*.r2.cloudflarestorage.com/* ]] || { echo "stub: unscripted URL" >&2; exit 99; }
seen_noproxy=0; seen_sigv4=0; seen_cfg=0
for i in "${!args[@]}"; do
  case "${args[$i]}" in
    --noproxy) [[ "${args[$((i + 1))]:-}" == '*' ]] && seen_noproxy=1 ;;
    --aws-sigv4) [[ "${args[$((i + 1))]:-}" == 'aws:amz:auto:s3' ]] && seen_sigv4=1 ;;
    --config) [[ "${args[$((i + 1))]:-}" == '-' ]] && seen_cfg=1 ;;
  esac
done
[[ "$seen_noproxy$seen_sigv4$seen_cfg" == "111" ]] || { echo "stub: unmodelled argv shape" >&2; exit 99; }
if [[ "${STUB_MODE:-record}" == "wire" ]]; then
  new=()
  skip=0
  for i in "${!args[@]}"; do
    a="${args[$i]}"
    if [[ "$skip" -eq 1 ]]; then skip=0; continue; fi
    if [[ "${STUB_DROP_CONFIG:-0}" == "1" && "$a" == "--config" ]]; then skip=1; continue; fi
    if [[ "$i" -eq $(( ${#args[@]} - 1 )) ]]; then a="http://127.0.0.1:${STUB_PORT:?}/${a#https://*/}"; fi
    [[ "$a" == "=https" ]] && a="=http"
    new+=("$a")
  done
  if [[ "${STUB_DROP_CONFIG:-0}" == "1" ]]; then
    "${STUB_REAL_CURL:?}" "${new[@]}"
  else
    printf '%s' "$stdin" | "${STUB_REAL_CURL:?}" "${new[@]}"
  fi
  exit $?
fi
printf '%s\n' "${STUB_CODE:-200}"
exit 0
EOF
chmod +x "$BIN/curl"

export STUB_LOG="$LOGD" STUB_REAL_CURL="$REAL_CURL"
PATH="$BIN:$PATH"

reset_log() { rm -rf -- "$LOGD"; mkdir -p "$LOGD"; : > "$LOGD/calls"; : > "$LOGD/argv"; : > "$LOGD/env"; }
calls() { wc -l < "$LOGD/calls" | tr -d ' '; }
has_line() { grep -qxF -- "$1" <<<"$2"; }
count_prefix() { grep -c -- "^$1" <<<"$2" || true; }

FNAME=r2-sigv4-suite

# ── (1) the functions exist (an undefined function is rc 127, which must never read as a refusal) ──
t "1.1 helper defines _r2_cred_ok, r2_sigv4_judge and r2_sigv4_curl" declare -F _r2_cred_ok r2_sigv4_judge r2_sigv4_curl >/dev/null

# ── (2) judge: valid pair accepted; one swapped byte refused with the right reason ──
reset_log
rc=0; out=$(r2_sigv4_judge "$FNAME" "$ID" "$SECRET" 2>&1) || rc=$?
t "2.1 judge: the valid 32/64 lowercase-hex pair returns 0" test "$rc" -eq 0
t "2.2 judge: a valid pair prints nothing" test -z "$out"

refuse_row() { # NAME KIND VALUE REASON
  local which="$1" bad="$2" reason="$3" tag="$4" id="$ID" secret="$SECRET" varname
  if [[ "$which" == id ]]; then id="$bad"; varname=R2_CLA_EVIDENCE_ACCESS_KEY_ID; else secret="$bad"; varname=R2_CLA_EVIDENCE_SECRET; fi
  rc=0; out=$(r2_sigv4_judge "$FNAME" "$id" "$secret" 2>&1) || rc=$?
  t "2.$tag judge($which): returns exactly 2" test "$rc" -eq 2
  t "2.$tag judge($which): one ::error:: annotation naming $varname, no value" \
    test "$(count_prefix '::error::' "$out")" -eq 1 -a "$(grep -cF -- "$varname unusable" <<<"$out")" -eq 1
  t "2.$tag judge($which): one marker with reason=$reason" \
    test "$(count_prefix 'SOLEUR_CREDENTIAL_REFUSED ' "$out")" -eq 1 -a "$(grep -cxF -- "SOLEUR_CREDENTIAL_REFUSED script=$FNAME reason=$reason" <<<"$out")" -eq 1
  local pats=(-e "$ID" -e "$SECRET")
  [[ -z "$bad" ]] || pats+=(-e "$bad")
  t "2.$tag judge($which): neither the swapped value nor the valid pair is printed" \
    _not grep -qF "${pats[@]}" <<<"$out"
}

n=0
for spec in 'dq|"|token_shape' 'bs|\|token_shape' 'colon|:|token_shape' 'space| |token_shape' \
            'nl|NL|control_char' 'tab|TAB|control_char' 'del|DEL|control_char' 'hi|HI|token_shape'; do
  IFS='|' read -r tag ch reason <<<"$spec"
  case "$ch" in NL) ch=$'\n' ;; TAB) ch=$'\t' ;; DEL) ch=$'\x7f' ;; HI) ch=$'\xc3' ;; esac
  n=$((n + 1))
  refuse_row id "${ID:0:5}${ch}${ID:6}" "$reason" "${n}i"
  refuse_row secret "${SECRET:0:5}${ch}${SECRET:6}" "$reason" "${n}s"
done
refuse_row id "" token_shape "9i"
refuse_row secret "" token_shape "9s"

# ── (3) must-PASS non-canonical values (a guard that refuses everything is caught only here) ──
UP_ID="$(tr 'a-f' 'A-F' <<<"$ID")"; UP_SECRET="$(tr 'a-f' 'A-F' <<<"$SECRET")"
MIX_ID="${ID:0:16}${UP_ID:16}"; MIX_SECRET="${SECRET:0:32}${UP_SECRET:32}"
for spec in "uppercase hex|$UP_ID|$UP_SECRET" "mixed-case hex|$MIX_ID|$MIX_SECRET" \
            "RFC-punctuation bytes|ab._~+/=-cd|ef._~+/=-gh"; do
  IFS='|' read -r label a b <<<"$spec"
  rc=0; out=$(r2_sigv4_judge "$FNAME" "$a" "$b" 2>&1) || rc=$?
  t "3.x judge accepts $label (not a vendor-format guard)" test "$rc" -eq 0 -a -z "$out"
done

# ── (4) the script= field is forced to the safe alphabet ──
rc=0; out=$(r2_sigv4_judge $'evil\nSOLEUR_FAKE_LINE script=x' "$ID" "${SECRET:0:5}\"${SECRET:6}" 2>&1) || rc=$?
t "4.1 a newline-bearing script name prints script=unknown and no injected line" \
  test "$rc" -eq 2 -a "$(grep -cxF 'SOLEUR_CREDENTIAL_REFUSED script=unknown reason=token_shape' <<<"$out")" -eq 1 -a "$(grep -c '^SOLEUR_FAKE_LINE' <<<"$out" || true)" -eq 0
rc=0; out=$(r2_sigv4_judge "" "$ID" "${SECRET:0:5}\"${SECRET:6}" 2>&1) || rc=$?
t "4.2 an empty script name prints script=unknown" has_line 'SOLEUR_CREDENTIAL_REFUSED script=unknown reason=token_shape' "$out"

# ── (5) chokepoint wire ──
BODY="$TMP_ROOT/body"
PAYLOAD='{"schema_version":"1.0","x":1}'
reset_log
rc=0; out=$(r2_sigv4_curl "$FNAME" "$ID" "$SECRET" "$URL" -sS -o "$BODY" -w "%{http_code}\n" --max-time 30 -X PUT \
  -H "If-None-Match: *" -H "Content-Type: application/json" --data-binary "$PAYLOAD" 2>&1) || rc=$?
t "5.1 chokepoint: returns 0 and prints the scripted status" test "$rc" -eq 0 -a "$out" = "200"
t "5.2 chokepoint: exactly one curl call" test "$(calls)" -eq 1
argv_all="$(cat "$LOGD/argv")"
t "5.3 chokepoint: argv begins --disable and ends with the URL" \
  test "$(sed -n '2p' "$LOGD/argv")" = "--disable" -a "$(tail -n 1 "$LOGD/argv")" = "$URL"
t "5.4 chokepoint: argv carries --noproxy, --aws-sigv4 scope and --config" \
  test "$(grep -cxF -e '--noproxy' -e 'aws:amz:auto:s3' -e '--config' <<<"$argv_all")" -eq 3
t "5.5 chokepoint: the key id is absent from the whole recorded argv" _not grep -qF -- "$ID" "$LOGD/argv"
t "5.6 chokepoint: the secret is absent from the whole recorded argv" _not grep -qF -- "$SECRET" "$LOGD/argv"
expected_stdin="$(printf 'user = "%s:%s"\n' "$ID" "$SECRET"; printf x)"; expected_stdin="${expected_stdin%x}"
actual_stdin="$(cat "$LOGD/stdin.1"; printf x)"; actual_stdin="${actual_stdin%x}"
t "5.7 chokepoint: recorded stdin is exactly the user config line plus a newline" test "$actual_stdin" = "$expected_stdin"
t "5.8 chokepoint: --globoff and --proto =https are on the request" \
  test "$(grep -cxF -e '--globoff' -e '=https' <<<"$argv_all")" -eq 2

# ── (6) refused value at the chokepoint: zero calls, the marker, no value ──
CANARY="Zq9canary$(rand_hex 8)"
reset_log
rc=0; out=$(r2_sigv4_curl "$FNAME" "${ID:0:5}\"${CANARY}" "$SECRET" "$URL" -sS --max-time 30 2>&1) || rc=$?
t "6.1 chokepoint re-judges: a refused id returns 2 and starts zero curl calls" test "$rc" -eq 2 -a "$(calls)" -eq 0
t "6.2 chokepoint refusal prints the marker once" test "$(count_prefix 'SOLEUR_CREDENTIAL_REFUSED ' "$out")" -eq 1
t "6.3 negative canary: the refused value is in no captured stream" \
  _not grep -qF -e "$CANARY" -e "$SECRET" <<<"$out"
t "6.4 negative canary: the refused value is in no argv, stdin or env log" \
  _not grep -qF -e "$CANARY" "$LOGD/argv" "$LOGD/env"
reset_log
rc=0; out=$(r2_sigv4_curl "$FNAME" "$ID" "${SECRET:0:5}:${SECRET:6}" "$URL" -sS --max-time 30 2>&1) || rc=$?
t "6.5 chokepoint re-judges: a refused secret returns 2 and starts zero curl calls" test "$rc" -eq 2 -a "$(calls)" -eq 0
reset_log
rc=0; out=$(r2_sigv4_curl "$FNAME" "$ID" "$SECRET" 2>&1) || rc=$?
t "6.6 too few arguments returns 64 without exiting the sourcing shell" test "$rc" -eq 64 -a "$(calls)" -eq 0

# ── (7) argument allowlist: must-REFUSE (64, a ::error:: line, zero calls) ──
refuse_args() { # LABEL ARGS...
  local label="$1"; shift
  reset_log
  rc=0; out=$(r2_sigv4_curl "$FNAME" "$ID" "$SECRET" "$URL" "$@" 2>&1) || rc=$?
  t "7.x allowlist refuses: $label" test "$rc" -eq 64 -a "$(calls)" -eq 0 -a "$(count_prefix '::error::' "$out")" -ge 1
}
refuse_args "--user x:y" -sS --user x:y
refuse_args "--user=x:y" -sS --user=x:y
refuse_args "-u x" -sS -u x
refuse_args "-sSu x" -sSu x
refuse_args "--config f" -sS --config f
refuse_args "--config=f" -sS --config=f
refuse_args "-Kf" -sS -Kf
refuse_args "-sSK f" -sSK f
refuse_args "--next" -sS --next
refuse_args "--disable" -sS --disable
refuse_args "--url" -sS --url http://x.example/
refuse_args "a second positional URL" -sS "https://${HOST32}.r2.cloudflarestorage.com/other"
refuse_args "--connect-to" -sS --connect-to a:1:b:2
refuse_args "--resolve" -sS --resolve a:443:127.0.0.1
refuse_args "--unix-socket" -sS --unix-socket /x
refuse_args "-k" -sS -k
refuse_args "--cacert" -sS --cacert f
refuse_args "-L" -sS -L
refuse_args "-H @-" -sS -H @-
refuse_args "--data-binary @-" -sS --data-binary @-
refuse_args "-T -" -sS -T -
refuse_args "a bare -" -sS -
refuse_args "a trailing dangling -w" -sS -w
refuse_args "a trailing dangling --max-time" -sS --max-time
refuse_args "-w @-" -sS -w @-

# ── (8) argument allowlist: must-PASS (the two callers' real vectors; contributor text) ──
reset_log
rc=0; out=$(r2_sigv4_curl "$FNAME" "$ID" "$SECRET" "$URL" -sS -o "$BODY" -w "%{http_code}\n" --max-time 30 -X PUT \
  -H "If-None-Match: *" -H "Content-Type: application/json" --data-binary "$PAYLOAD" 2>&1) || rc=$?
t "8.1 the r2-conditional-put.sh argument vector is accepted" test "$rc" -eq 0 -a "$(calls)" -eq 1
reset_log
rc=0; out=$(r2_sigv4_curl bootstrap "$ID" "$SECRET" "$URL" -sS -o "$BODY" -w "%{http_code}" --max-time 30 -X PUT \
  -H "If-None-Match: *" -H "Content-Type: application/json" --data-binary '{"probe":"bootstrap"}' 2>&1) || rc=$?
t "8.2 the bootstrap.sh argument vector is accepted" test "$rc" -eq 0 -a "$(calls)" -eq 1
reset_log
EVIL='{"comment":"see /proc/self/environ and /dev/stdin and --user x:y and @file"}'
rc=0; out=$(r2_sigv4_curl "$FNAME" "$ID" "$SECRET" "$URL" -sS -o "$BODY" -w "%{http_code}\n" --max-time 30 -X PUT \
  --data-binary "$EVIL" 2>&1) || rc=$?
t "8.3 contributor text naming /proc/, /dev/stdin and --user in the payload is NOT refused" test "$rc" -eq 0 -a "$(calls)" -eq 1

# ── (9) environment: nothing that redirects TLS trust, libraries or the pair reaches curl ──
reset_log
rc=0
SSL_CERT_FILE=/nonexistent CURL_CA_BUNDLE=/nonexistent LD_PRELOAD=libc.so.6 SSLKEYLOGFILE=/nonexistent \
R2_CLA_EVIDENCE_ACCESS_KEY_ID="$ID" R2_CLA_EVIDENCE_SECRET="$SECRET" R2_S3_ACCESS_KEY_ID="$ID" R2_S3_SECRET_ACCESS_KEY="$SECRET" \
  r2_sigv4_curl "$FNAME" "$ID" "$SECRET" "$URL" -sS -o "$BODY" -w "%{http_code}\n" --max-time 30 >/dev/null 2>&1 || rc=$?
t "9.1 the environment row ran (one call recorded)" test "$rc" -eq 0 -a "$(calls)" -eq 1
t "9.2 curl's own environment holds none of the eight scrubbed variables" \
  test "$(grep -c '=set$' "$LOGD/env" || true)" -eq 0 -a "$(grep -c '=unset$' "$LOGD/env")" -eq 8

# ── (10) destination pin: 64, a ::error:: line, zero calls, and NOT the credential marker ──
refuse_url() { # LABEL URL
  local label="$1" u="$2"
  reset_log
  rc=0; out=$(r2_sigv4_curl "$FNAME" "$ID" "$SECRET" "$u" -sS --max-time 30 2>&1) || rc=$?
  t "10.x destination pin refuses: $label" \
    test "$rc" -eq 64 -a "$(calls)" -eq 0 -a "$(count_prefix '::error::' "$out")" -ge 1 -a "$(count_prefix 'SOLEUR_CREDENTIAL_REFUSED ' "$out")" -eq 0
}
refuse_url "a non-R2 host" "https://evil.example/soleur-cla-evidence/x"
refuse_url "an R2-lookalike suffix host" "https://${HOST32}.r2.cloudflarestorage.com.evil.test/x"
refuse_url "a jurisdiction host (.eu., intentionally refused like _r2-endpoint.sh)" "https://${HOST32}.eu.r2.cloudflarestorage.com/x"
refuse_url "plain http" "http://${HOST32}.r2.cloudflarestorage.com/x"
refuse_url "a short account id" "https://${HOST32:0:31}.r2.cloudflarestorage.com/x"
refuse_url "no path after the host" "https://${HOST32}.r2.cloudflarestorage.com"

# ── (11) source rows (non-comment lines only) ──
code_lines="$(grep -v '^[[:space:]]*#' "$HELPER")"
t "11.1 the helper feeds curl from a process substitution (< <(printf)" grep -qF '< <(printf' <<<"$code_lines"
t "11.2 no pipe feeds curl (no '| curl', '|curl' or '| env')" \
  _not grep -qE '\|[[:space:]]*(curl|env)\b' <<<"$code_lines"
t "11.3 the helper carries no exit (a sourced exit kills the caller)" _not grep -qE '(^|[;&|[:space:]])exit[[:space:]]' <<<"$code_lines"
t "11.4 the helper never uses a \${var:?} expansion (it exits the sourcing shell)" _not grep -qF ':?' <<<"$code_lines"
carriers="$(cd "$REPO_ROOT" && grep -rlE '^[^#]*--aws-sigv4' --include='*.sh' --exclude='*.test.sh' apps/cla-evidence 2>/dev/null | sort | tr '\n' ' ')"
t "11.5 the helper is the ONLY non-test shell file under apps/cla-evidence carrying --aws-sigv4" \
  test "$carriers" = "apps/cla-evidence/scripts/_r2-sigv4-curl.sh "
# A curl command spans several continuation lines, so join them (comments dropped) before matching.
joined_curl_user_hits() {
  local f
  while IFS= read -r f; do
    awk -v F="$f" '{ l = $0; sub(/^[[:space:]]*#.*/, "", l)
      if (l ~ /\\$/) { sub(/\\$/, "", l); buf = buf l; next }
      joined = buf l; buf = ""
      if (joined ~ /curl.*( -u |--user)/) print F ": a curl command line carries -u/--user" }' "$f"
  done < <(cd "$REPO_ROOT" && find apps/cla-evidence -name '*.sh' ! -name '*.test.sh' | sort)
}
t "11.6 no shell file under apps/cla-evidence passes the pair as -u/--user on a (joined) curl command" \
  test -z "$(cd "$REPO_ROOT" && joined_curl_user_hits)"

# ── (12) real-curl wire row: the request the helper builds, sent by REAL curl, read at a listener ──
LISTEN_PY="$TMP_ROOT/listener.py"
PORT_FILE="$TMP_ROOT/port"; REC_FILE="$TMP_ROOT/records"
assert_fixture_dir "$TMP_ROOT"
cat > "$LISTEN_PY" <<'EOF'
import http.server, sys
port_file, rec_file = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def do_PUT(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n)
        with open(rec_file, "ab") as f:
            f.write(b"REQ " + self.requestline.encode() + b"\n")
            f.write(str(self.headers).encode() + b"\n")
            f.write(body + b"\nEND\n")
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
with open(port_file, "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
EOF
: > "$REC_FILE"
timeout -k 2 120 python3 -I "$LISTEN_PY" "$PORT_FILE" "$REC_FILE" >/dev/null 2>&1 &
LISTENER_PID=$!
for _ in $(seq 1 100); do [[ -s "$PORT_FILE" ]] && break; sleep 0.1; done
t "12.0 the loopback listener is up (port file non-empty)" test -s "$PORT_FILE"
export STUB_PORT STUB_MODE
STUB_PORT="$(cat "$PORT_FILE" 2>/dev/null || echo 0)"
STUB_MODE=wire
reset_log
rc=0; out=$(r2_sigv4_curl "$FNAME" "$ID" "$SECRET" "$URL" -sS -o "$BODY" -w "%{http_code}\n" --max-time 30 -X PUT \
  -H "If-None-Match: *" -H "Content-Type: application/json" --data-binary "$PAYLOAD" 2>&1) || rc=$?
reqs="$(grep -c '^REQ ' "$REC_FILE" || true)"
t "12.1 real curl reached the listener (record count equals curl invocations)" test "$out" = "200" -a "$reqs" -eq "$(calls)" -a "$reqs" -eq 1
t "12.2 the Authorization header carries Credential=<id>/ and the auto/s3/aws4_request scope" \
  grep -q "Credential=${ID}/.*/auto/s3/aws4_request" "$REC_FILE"
t "12.3 the secret appears nowhere in the received request" _not grep -qF -- "$SECRET" "$REC_FILE"
t "12.4 the stub's recorded argv holds neither value (real wire, real curl)" _not grep -qF -e "$ID" -e "$SECRET" "$LOGD/argv"
: > "$REC_FILE"
reset_log
STUB_DROP_CONFIG=1 r2_sigv4_curl "$FNAME" "$ID" "$SECRET" "$URL" -sS -o "$BODY" -w "%{http_code}\n" --max-time 30 -X PUT \
  --data-binary "$PAYLOAD" >/dev/null 2>&1
t "12.5 control: without --config - the received request carries no Credential=<id>/ (the row can discriminate)" \
  _not grep -q "Credential=${ID}/" "$REC_FILE"
STUB_MODE=record

kill "$LISTENER_PID" 2>/dev/null; LISTENER_PID=""

# MIN_CASES counts PASSES. The literal SELFTEST_PASSES sits on the line directly above its use
# (guard-vacuity-floor.test.sh slices the floor plus its contiguous assignments; the self-test
# above asserts passes == 1, so the literal is proven, not chosen).
SELFTEST_PASSES=1
REAL_PASSES=$((passes - SELFTEST_PASSES))
MIN_CASES=142
if [[ "$fails" -eq 0 && "$REAL_PASSES" -lt "$MIN_CASES" ]]; then
  printf 'FATAL: anti-vacuity floor — %s real assertions passed, expected at least %s\n' \
    "$REAL_PASSES" "$MIN_CASES" >&2
  exit 1
fi

echo "$REAL_PASSES passed, $fails failed"
if [[ "$fails" -eq 0 ]]; then
  echo "ALL _r2-sigv4-curl.sh tests passed."
fi
[[ "$fails" -eq 0 ]] || exit 1
