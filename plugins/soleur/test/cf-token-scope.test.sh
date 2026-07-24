#!/usr/bin/env bash
# Test for cf-token-scope.sh — the deterministic three-layer fail-closed
# retained-scope probe (ADR-130 four-probe set + #6755/#6892).
#
# Stubs curl + doppler on PATH via a scratch bin dir; keeps real jq. Asserts:
#   - status layer (403/000/5xx/empty/no-newline/non-numeric = FAIL)
#   - body-shape layer: BOTH halves independently pinned —
#       {"success":true,"result":null}  = FAIL (null result)
#       {"success":false,"result":[]}   = FAIL (success false)
#   - per-scheme control layer (account 404 = FAIL; zone 404 trusted ONLY for the
#     verified phase http_config_settings, and only under an authorized control)
#   - --target-entrypoint: present-not-added, and the success line is gated on the
#     target probe actually passing (a denied/404 target => exit 3, no PASS line)
#   - --dry-run (token unexpanded, private-fd form, curl never run), token never
#     leaked to combined 2>&1, and source grep-guards with a positive anchor.
#
# Accumulate-then-exit style. All greps run against FILES (never a pipe) to avoid
# the pipefail + `grep -q` early-match SIGPIPE flake.
set -uo pipefail

TESTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$TESTDIR/../skills/cf-token-scope/scripts/cf-token-scope.sh"
BASHBIN="$(command -v bash)"
JQBIN="$(command -v jq)"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

WORK="$(mktemp -d -t cf-token-scope-test.XXXXXXXX)"
trap 'rm -rf "$WORK"' EXIT
OUTFILE="$WORK/out.txt"

# --- mock bin (curl + doppler + real jq); a second bin omits curl ---
MOCKBIN="$WORK/bin"
NOCURLBIN="$WORK/bin-nocurl"
mkdir -p "$MOCKBIN" "$NOCURLBIN"

cat >"$MOCKBIN/doppler" <<'EOF'
#!/usr/bin/env bash
# doppler secrets get <NAME> -p soleur -c prd_terraform --plain
name="$3"
case "$name" in
  CF_API_TOKEN_RULESETS) printf '%s' "${MOCK_TOKEN-fake-secret-abc123xyz}" ;;
  CF_ZONE_ID)            printf '%s' "${MOCK_ZONE-zone0123456789abcdef}" ;;
  CF_ACCOUNT_ID)         printf '%s' "${MOCK_ACCTID-acct9876543210fedcba}" ;;
  *)                     printf '' ;;
esac
EOF

cat >"$MOCKBIN/curl" <<'EOF'
#!/usr/bin/env bash
# Mock curl: emit "<body>\n<code>" to match the SUT's -w '\n%{http_code}'.
# The URL is the last positional argument. A spec of "NONE" emits nothing at all
# (models a total curl failure -> empty response, the no-newline path).
[[ -n "${MOCK_CURL_MARKER:-}" ]] && printf 'called\n' >>"$MOCK_CURL_MARKER"
url=""
for a in "$@"; do url="$a"; done
AUTH='200:{"success":true,"result":[]}'
case "$url" in
  *http_config_settings*)          spec="${MOCK_CONFIG:-$AUTH}" ;;
  *http_request_dynamic_redirect*) spec="${MOCK_DYNREDIR:-$AUTH}" ;;
  *http_request_cache_settings*)   spec="${MOCK_CACHE:-$AUTH}" ;;
  *http_request_firewall_custom*)  spec="${MOCK_WAF:-$AUTH}" ;;
  *http_request_transform*)        spec="${MOCK_TARGET:-$AUTH}" ;;
  */rulesets)                      spec="${MOCK_ACCT:-$AUTH}" ;;
  *)                               spec="${MOCK_OTHER:-$AUTH}" ;;
esac
[[ "$spec" == "NONE" ]] && exit 0   # no output at all
code="${spec%%:*}"
body="${spec#*:}"
printf '%s\n%s' "$body" "$code"
EOF

chmod +x "$MOCKBIN/doppler" "$MOCKBIN/curl"
ln -sf "$JQBIN" "$MOCKBIN/jq"
# no-curl bin: doppler + jq only (to exercise the missing-prereq path). Nothing
# external runs before the prereq check, so this bare PATH is sufficient.
cp "$MOCKBIN/doppler" "$NOCURLBIN/doppler"
ln -sf "$JQBIN" "$NOCURLBIN/jq"

# Mock dir FIRST (shadows real curl/doppler), then system bins so the SUT's `cat`
# (usage) and the mock shebangs (/usr/bin/env bash) still resolve.
MOCKPATH="$MOCKBIN:/usr/bin:/bin"

# run <PATH> <args...> ; sets RC and writes combined output to OUTFILE.
run() {
  local path="$1"
  shift
  PATH="$path" "$BASHBIN" "$SUT" "$@" >"$OUTFILE" 2>&1
  RC=$?
}

assert_rc() { if [[ "$RC" == "$1" ]]; then ok "$2"; else no "$2 (want rc=$1 got $RC)"; fi; }
has() { if grep -qF -- "$1" "$OUTFILE"; then ok "$2"; else no "$2 (missing: $1)"; fi; }
lacks() { if grep -qF -- "$1" "$OUTFILE"; then no "$2 (present: $1)"; else ok "$2"; fi; }
# refute / require a literal in the SUT source (grep on a FILE, never a pipe).
src_lacks() { if grep -qE "$1" "$SUT"; then no "$2"; else ok "$2"; fi; }
src_has() { if grep -qE "$1" "$SUT"; then ok "$2"; else no "$2 (missing anchor: $1)"; fi; }

# --- C1: all authorized + target authorized -> exit 0, "present" line ---
run "$MOCKPATH" --target-entrypoint http_request_transform
assert_rc 0 "C1 all-authorized + target -> exit 0"
has "PASS: no scope dropped" "C1 prints 'no scope dropped'"
has "PASS: target scope present" "C1 prints 'target scope present'"

# --- C2: a retained zone phase (cache) at 403 -> exit 3, no pass line ---
MOCK_CACHE='403:{"success":false,"errors":[{"code":10000}]}' run "$MOCKPATH"
assert_rc 3 "C2 retained phase 403 -> exit 3"
lacks "PASS: no scope dropped" "C2 omits 'no scope dropped'"

# --- C2b: the newly-probed Zone WAF phase at 403 -> exit 3 (drop detected) ---
MOCK_WAF='403:{"success":false}' run "$MOCKPATH"
assert_rc 3 "C2b Zone WAF (firewall_custom) 403 -> exit 3"

# --- C3: degraded 200 {"success":false,"result":null} -> exit 3 ---
MOCK_CACHE='200:{"success":false,"result":null}' run "$MOCKPATH"
assert_rc 3 "C3 degraded 200 (both false) -> exit 3"
lacks "PASS: no scope dropped" "C3 omits 'no scope dropped'"

# --- C3a: {"success":true,"result":null} -> exit 3 (pins the .result-array half;
#          this is the exact fail-open CF degraded shape the SUT exists to catch) ---
MOCK_CACHE='200:{"success":true,"result":null}' run "$MOCKPATH"
assert_rc 3 "C3a degraded 200 (result null, success true) -> exit 3"

# --- C3b: {"success":false,"result":[]} -> exit 3 (pins the success==true half) ---
MOCK_CACHE='200:{"success":false,"result":[]}' run "$MOCKPATH"
assert_rc 3 "C3b degraded 200 (success false, result array) -> exit 3"

# --- C4: account-scheme 404 -> exit 3 (account list is its own control) ---
MOCK_ACCT='404:{"success":false}' run "$MOCKPATH"
assert_rc 3 "C4 account 404 -> exit 3"

# --- C5a: a 404 on the VERIFIED phase (http_config_settings) under an authorized
#          control -> PASS (ADR-130: 403-on-missing verified there) ---
MOCK_CONFIG='404:{"success":false,"errors":[]}' run "$MOCKPATH"
assert_rc 0 "C5a verified-phase 404 under authorized control -> exit 0"
has "PASS: no scope dropped" "C5a prints 'no scope dropped'"

# --- C5c: a 404 on an UNVERIFIED retained phase (cache) under an authorized
#          control -> FAIL (fail-closed; 403-on-missing unverified there) ---
MOCK_CACHE='404:{"success":false}' run "$MOCKPATH"
assert_rc 3 "C5c unverified-phase 404 under authorized control -> exit 3 (fail-closed)"

# --- C5b: verified-phase 404 while the zone control is degraded -> exit 3 ---
MOCK_CONFIG='404:{"success":false}' MOCK_DYNREDIR='200:{"success":false,"result":null}' run "$MOCKPATH"
assert_rc 3 "C5b verified 404 + degraded control -> exit 3"

# --- C6: status-layer failures ---
MOCK_CONFIG='000:' run "$MOCKPATH"
assert_rc 3 "C6a network 000 -> exit 3"
MOCK_CACHE='500:{}' run "$MOCKPATH"
assert_rc 3 "C6b http 500 -> exit 3"
MOCK_CONFIG='NONE' run "$MOCKPATH"
assert_rc 3 "C6c empty/no-newline response -> exit 3"
MOCK_CONFIG='xyz:{}' run "$MOCKPATH"
assert_rc 3 "C6d non-numeric status code -> exit 3"

# --- C7: negative target — a denied target must exit 3 AND omit the PASS line
#          (the success line is gated on the target probe actually passing) ---
MOCK_TARGET='403:{"success":false}' run "$MOCKPATH" --target-entrypoint http_request_transform
assert_rc 3 "C7 denied target -> exit 3"
lacks "PASS: target scope present" "C7 denied target omits 'target scope present'"

# --- C7a: a target 404 on an UNVERIFIED phase -> exit 3 (cannot confirm the add) ---
MOCK_TARGET='404:{"success":false}' run "$MOCKPATH" --target-entrypoint http_request_transform
assert_rc 3 "C7a unverified target 404 -> exit 3"

# --- C7b: a target 404 on the VERIFIED phase http_config_settings -> exit 0
#          (a fresh widen may leave the phase empty; 404 is trusted there) ---
MOCK_CONFIG='404:{"success":false}' run "$MOCKPATH" --target-entrypoint http_config_settings
assert_rc 0 "C7b verified target 404 -> exit 0"
has "PASS: target scope present (http_config_settings)" "C7b verified target 404 prints present"

# --- C8: --dry-run prints the private-fd recipe with token unexpanded, no curl ---
MARKER="$WORK/curl-called"
MOCK_CURL_MARKER="$MARKER" run "$MOCKPATH" --dry-run
assert_rc 0 "C8 --dry-run -> exit 0"
# shellcheck disable=SC2016  # the literal, unexpanded '$TOK' is exactly the assertion
has '"$TOK"' "C8 dry-run keeps the token var unexpanded"
has "printf 'Authorization: Bearer %s'" "C8 dry-run models the private-fd form, not inline -H"
lacks "fake-secret-abc123xyz" "C8 dry-run leaks no token value"
if [[ ! -e "$MARKER" ]]; then ok "C8 dry-run never invoked curl"; else no "C8 dry-run invoked curl"; fi

# --- C9: a real run never echoes the token value (combined 2>&1) ---
run "$MOCKPATH"
assert_rc 0 "C9 baseline authorized run -> exit 0"
lacks "fake-secret-abc123xyz" "C9 no Bearer token value in combined output"

# --- C10: source grep-guards (negatives enforced) + a positive anchor so the
#          guards cannot pass vacuously on a missing/empty SUT ---
src_has 'set -euo pipefail' "C10 positive anchor present (non-vacuous guards)"
src_lacks 'set +(-x|.*xtrace)' "C10 no shell trace (set -x / xtrace) in source"
src_lacks 'doppler[[:space:]]+(secrets[[:space:]]+)?(set|upload|download|delete)\b' "C10 no Doppler write verb in source"
src_lacks '\bterraform\b' "C10 no 'terraform' in source"

# --- C11: missing Doppler secret -> exit 2 ---
MOCK_TOKEN='' run "$MOCKPATH"
assert_rc 2 "C11 empty token secret -> exit 2"

# --- C12: missing curl prereq -> exit 2 ---
run "$NOCURLBIN"
assert_rc 2 "C12 missing curl binary -> exit 2"

# --- C13: --target-entrypoint with no value -> exit 2 (usage error) ---
run "$MOCKPATH" --target-entrypoint
assert_rc 2 "C13 --target-entrypoint missing value -> exit 2"

# --- C14: --help -> exit 0 ---
run "$MOCKPATH" --help
assert_rc 0 "C14 --help -> exit 0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
