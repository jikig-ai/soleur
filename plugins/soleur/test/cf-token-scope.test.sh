#!/usr/bin/env bash
# Test for cf-token-scope.sh — the deterministic three-layer fail-closed
# retained-scope probe (ADR-130 four-probe set + #6755).
#
# Stubs curl + doppler on PATH via a scratch bin dir; keeps real jq. Asserts:
#   - status layer (403/000/5xx/empty = FAIL)
#   - body-shape layer (degraded 200 {"success":false,"result":null} = FAIL)
#   - per-scheme control layer (account 404 = FAIL; zone 404 trusted only under
#     an authorized zone control)
#   - --target-entrypoint verdict, --dry-run (token unexpanded, curl never run),
#     token never leaked to combined 2>&1, and source grep-guards.
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
# The URL is the last positional argument.
[[ -n "${MOCK_CURL_MARKER:-}" ]] && printf 'called\n' >>"$MOCK_CURL_MARKER"
url=""
for a in "$@"; do url="$a"; done
case "$url" in
  *http_config_settings*)          spec="${MOCK_CONFIG:-200:{\"success\":true,\"result\":[]}}" ;;
  *http_request_dynamic_redirect*) spec="${MOCK_DYNREDIR:-200:{\"success\":true,\"result\":[]}}" ;;
  *http_request_cache_settings*)   spec="${MOCK_CACHE:-200:{\"success\":true,\"result\":[]}}" ;;
  *http_request_transform*)        spec="${MOCK_TARGET:-200:{\"success\":true,\"result\":[]}}" ;;
  */rulesets)                      spec="${MOCK_ACCT:-200:{\"success\":true,\"result\":[]}}" ;;
  *)                               spec="${MOCK_OTHER:-200:{\"success\":true,\"result\":[]}}" ;;
esac
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
# refute a literal token in the SUT source (grep on a FILE, never a pipe).
src_lacks() { if grep -qE "$1" "$SUT"; then no "$2"; else ok "$2"; fi; }

# --- C1: all authorized + target authorized -> exit 0, both PASS lines ---
run "$MOCKPATH" --target-entrypoint http_request_transform
assert_rc 0 "C1 all-authorized + target -> exit 0"
has "PASS: no scope dropped" "C1 prints 'no scope dropped'"
has "PASS: target scope added" "C1 prints 'target scope added'"

# --- C2: a retained zone control at 403 -> exit 3, no pass line ---
MOCK_CACHE='403:{"success":false,"errors":[{"code":10000}]}' run "$MOCKPATH"
assert_rc 3 "C2 zone control 403 -> exit 3"
lacks "PASS: no scope dropped" "C2 omits 'no scope dropped'"

# --- C3: degraded 200 on a retained probe -> exit 3 (body-shape layer) ---
MOCK_CACHE='200:{"success":false,"result":null}' run "$MOCKPATH"
assert_rc 3 "C3 degraded 200 -> exit 3"
lacks "PASS: no scope dropped" "C3 omits 'no scope dropped'"

# --- C4: account-scheme 404 -> exit 3 (account list is its own control) ---
MOCK_ACCT='404:{"success":false}' run "$MOCKPATH"
assert_rc 3 "C4 account 404 -> exit 3"

# --- C5a: zone 404 under an authorized zone control -> PASS ---
MOCK_CONFIG='404:{"success":false,"errors":[]}' run "$MOCKPATH"
assert_rc 0 "C5a zone 404 under authorized control -> exit 0"
has "PASS: no scope dropped" "C5a prints 'no scope dropped'"

# --- C5b: zone 404 while the zone control is degraded -> exit 3 ---
MOCK_CONFIG='404:{"success":false}' MOCK_DYNREDIR='200:{"success":false,"result":null}' run "$MOCKPATH"
assert_rc 3 "C5b zone 404 + degraded control -> exit 3"

# --- C6: network 000 and a 500 both FAIL (status layer) ---
MOCK_CONFIG='000:' run "$MOCKPATH"
assert_rc 3 "C6a network 000 -> exit 3"
MOCK_CACHE='500:{}' run "$MOCKPATH"
assert_rc 3 "C6b http 500 -> exit 3"

# --- C7: --dry-run prints the recipe with the token unexpanded, runs no curl ---
MARKER="$WORK/curl-called"
MOCK_CURL_MARKER="$MARKER" run "$MOCKPATH" --dry-run
assert_rc 0 "C7 --dry-run -> exit 0"
# shellcheck disable=SC2016  # the literal, unexpanded '$TOK' is exactly the assertion
has 'Bearer $TOK' "C7 prints literal 'Bearer \$TOK' (unexpanded)"
lacks "fake-secret-abc123xyz" "C7 dry-run leaks no token value"
if [[ ! -e "$MARKER" ]]; then ok "C7 dry-run never invoked curl"; else no "C7 dry-run invoked curl"; fi

# --- C8: a real run never echoes the token value (combined 2>&1) ---
run "$MOCKPATH"
assert_rc 0 "C8 baseline authorized run -> exit 0"
lacks "fake-secret-abc123xyz" "C8 no Bearer token value in combined output"

# --- C9: source grep-guards (negatives enforced, not just prose) ---
src_lacks 'set +-x' "C9 no 'set -x' in source"
src_lacks 'doppler[[:space:]]+(secrets[[:space:]]+)?(set|upload|delete)\b' "C9 no Doppler write verb in source"
src_lacks '\bterraform\b' "C9 no 'terraform' in source"

# --- C10: missing Doppler secret -> exit 2 ---
MOCK_TOKEN='' run "$MOCKPATH"
assert_rc 2 "C10 empty token secret -> exit 2"

# --- C11: missing curl prereq -> exit 2 ---
run "$NOCURLBIN"
assert_rc 2 "C11 missing curl binary -> exit 2"

# --- C12: --help -> exit 0 ---
run "$MOCKPATH" --help
assert_rc 0 "C12 --help -> exit 0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
