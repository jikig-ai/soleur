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
# HYGIENE MODEL (fix-round seats, stated honestly): the suite REQUIRES a bash
# where `VAR=x run …` prefix assignments are transient past the call (bash >=
# 5.2 behavior; not version-gated here — the D-block unsets are belt-and-braces
# for older shells). The C-block's mock specs are set the same prefix way and
# RELY on the assignment reaching the child for the call's duration; no C/D
# assertion relies on persistence beyond the call.
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
[[ -n "${MOCK_DOPPLER_MARKER:-}" ]] && printf '%s\n' "$name" >>"$MOCK_DOPPLER_MARKER"
case "$name" in
  CF_API_TOKEN_RULESETS) printf '%s' "${MOCK_TOKEN-fake-secret-abc123xyz}" ;;
  CF_API_TOKEN)          printf '%s' "${MOCK_API_TOKEN-default-token-xyz789}" ;;
  CF_ZONE_ID)            printf '%s' "${MOCK_ZONE-zone0123456789abcdef}" ;;
  CF_ACCOUNT_ID)         printf '%s' "${MOCK_ACCTID-acct9876543210fedcba}" ;;
  *)                     printf '' ;;
esac
EOF

cat >"$MOCKBIN/curl" <<'EOF'
#!/usr/bin/env bash
# Mock curl: emit "<body>\n<code>" to match the SUT's -w '\n%{http_code}'.
# Log positional URL operands and both --url forms across schemes, so an extra
# target cannot hide behind a canonical final argument. A spec of "NONE" emits
# nothing at all (models a total curl failure -> empty response, the no-newline path).
[[ -n "${MOCK_CURL_MARKER:-}" ]] && printf 'called\n' >>"$MOCK_CURL_MARKER"
# %q keeps multi-line arg values (the -w format) on ONE log line: retain the
# original argv before URL parsing shifts the positional parameters below.
[[ -n "${MOCK_CURL_ARGV:-}" ]] && printf '%q ' "$@" >>"$MOCK_CURL_ARGV" && printf '\n' >>"$MOCK_CURL_ARGV"
url=""
record_url() {
  url="$1"
  [[ -n "${MOCK_CURL_URLLOG:-}" ]] && printf '%s\n' "$url" >>"$MOCK_CURL_URLLOG"
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      shift
      [[ $# -gt 0 ]] && record_url "$1"
      ;;
    --url=*) record_url "${1#*=}" ;;
    --proxy|--proxy1.0|--preproxy|--socks4|--socks4a|--socks5|--socks5-hostname|-x|-sSx) shift ;;
    --proxy=*|--proxy1.0=*|--preproxy=*|--socks4=*|--socks4a=*|--socks5=*|--socks5-hostname=*|-x*|-sSx*) ;;
    --max-time|-w|-H|--noproxy) shift ;;
    -* ) [[ "$1" == *://* ]] && record_url "$1" ;;
    *) record_url "$1" ;;
  esac
  shift
done
# Real CF shapes: a zone .../entrypoint returns a single ruleset OBJECT; the
# account /rulesets list returns an ARRAY. The mock must mirror this so the
# per-scheme body-shape check is exercised against the true contract (#6892 QA).
ZONE_AUTH='200:{"success":true,"result":{"id":"r","kind":"zone","phase":"p","rules":[]}}'
ACCT_AUTH='200:{"success":true,"result":[]}'
if [[ "$url" =~ ^https://api\.cloudflare\.com/client/v4/accounts/[^/]+/alerting/v3/policies$ ]]; then
  spec="${MOCK_NOTIF:-$ACCT_AUTH}"
else
case "$url" in
  *http_config_settings*)          spec="${MOCK_CONFIG:-$ZONE_AUTH}" ;;
  *http_request_dynamic_redirect*) spec="${MOCK_DYNREDIR:-$ZONE_AUTH}" ;;
  *http_request_cache_settings*)   spec="${MOCK_CACHE:-$ZONE_AUTH}" ;;
  *http_request_firewall_custom*)  spec="${MOCK_WAF:-$ZONE_AUTH}" ;;
  *http_request_transform*)        spec="${MOCK_TARGET:-$ZONE_AUTH}" ;;
  # default-token profile rows (D-series). Authorized default is the ARRAY shape —
  # every new endpoint returns a list. ORDERING IS LOAD-BEARING: the pools URL is a
  # superstring of the zone-LB match, so pools must precede *load_balancers*.
  *cfd_tunnel*)                    spec="${MOCK_TUNNEL:-$ACCT_AUTH}" ;;
  *access/apps*)                   spec="${MOCK_ACCESS:-$ACCT_AUTH}" ;;
  *dns_records*)                   spec="${MOCK_DNS:-$ACCT_AUTH}" ;;
  *load_balancers/pools*)          spec="${MOCK_LB_POOLS:-$ACCT_AUTH}" ;;
  *load_balancers*)                spec="${MOCK_LB_ZONE:-$ACCT_AUTH}" ;;
  */rulesets)                      spec="${MOCK_ACCT:-$ACCT_AUTH}" ;;
  *)                               spec="${MOCK_OTHER:-$ZONE_AUTH}" ;;
esac
fi
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
src_lacks() { if grep -qE -- "$1" "$SUT"; then no "$2"; else ok "$2"; fi; }
src_has() { if grep -qE -- "$1" "$SUT"; then ok "$2"; else no "$2 (missing anchor: $1)"; fi; }

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

# --- C3a: {"success":true,"result":null} -> exit 3 (pins the .result-type half;
#          this is the exact fail-open CF degraded shape the SUT exists to catch) ---
MOCK_CACHE='200:{"success":true,"result":null}' run "$MOCKPATH"
assert_rc 3 "C3a degraded 200 (result null, success true) -> exit 3"

# --- C3c: a ZONE entrypoint returning an ARRAY result -> exit 3. Zone entrypoints
#          return a single ruleset OBJECT; an array is the wrong per-scheme shape.
#          (Regression for the #6892 QA bug: the classifier once required an array
#          for ALL probes, which rejected every real authorized zone 200.) ---
MOCK_CACHE='200:{"success":true,"result":[]}' run "$MOCKPATH"
assert_rc 3 "C3c zone 200 with array result (wrong scheme shape) -> exit 3"

# --- C3d: the ACCOUNT list returning an OBJECT result -> exit 3 (account expects
#          an array; the per-scheme type must hold in the account direction too) ---
MOCK_ACCT='200:{"success":true,"result":{"id":"x"}}' run "$MOCKPATH"
assert_rc 3 "C3d account 200 with object result (wrong scheme shape) -> exit 3"

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

# ============================================================================
# D-series — default-token profile (plan 2026-10-28-feat-cf-token-scope-...;
# written RED-first per cq-write-failing-tests-before). C1–C14 above are the
# D13 back-compat pin (run before and after the script phase, unmodified).
# ============================================================================

# stdout-only capture for the channel-sensitive rows (plan addendum 1/16: the
# assert-mode FAIL verdict moved to stdout — same #7797 rationale as the xtrace
# refusal; the merged run() capture cannot pin a channel, this one can).
run_out() {
  local path="$1"
  shift
  PATH="$path" "$BASHBIN" "$SUT" "$@" >"$OUTFILE" 2>"$WORK/err.txt"
  RC=$?
}
has_re() { if grep -qE -- "$1" "$OUTFILE"; then ok "$2"; else no "$2 (no match: $1)"; fi }
has_err() { if grep -qF -- "$1" "$WORK/err.txt"; then ok "$2"; else no "$2 (missing on stderr: $1)"; fi }
lacks_err() { if grep -qF -- "$1" "$WORK/err.txt"; then no "$2 (present on stderr: $1)"; else ok "$2"; fi }
count_f() { grep -cF -- "$1" "$OUTFILE" || true; }
assert_eq() { if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1 (want $2 got $3)"; fi }

SKILLDOC="$TESTDIR/../skills/cf-token-scope/SKILL.md"
PLAYBOOK="$TESTDIR/../skills/cf-token-scope/references/widen-playbook.md"
DOPREQ="$WORK/doppler-requests.log"

# --- D1: default-token dry-run binds CF_API_TOKEN and prints all six rows ---
DM1="$WORK/d1-curl-marker"
MOCK_CURL_MARKER="$DM1" run "$MOCKPATH" --profile default-token --dry-run
assert_rc 0 "D1 default-token dry-run -> exit 0"
has "doppler secrets get CF_API_TOKEN " "D1 dry-run resolves the token secret to CF_API_TOKEN"
for u in cfd_tunnel access/apps dns_records alerting/v3/policies "load_balancers/pools" 'zones/$ZONE/load_balancers'; do
  has "$u" "D1 dry-run prints the $u row"
done
D1_EXPECTED_NOTIF_URL="https://api.cloudflare.com/client/v4/accounts/\$ACCT/alerting/v3/policies"
D1_EXPECTED_NOTIF_RECIPE="curl --disable --noproxy '*' -sS --max-time 15 -H @<(printf 'Authorization: Bearer %s' \"\$TOK\") $D1_EXPECTED_NOTIF_URL"
D1_NOTIF_RECIPE_COUNT=$(grep -Fc -- "$D1_EXPECTED_NOTIF_URL" "$OUTFILE" || true)
if [[ "$D1_NOTIF_RECIPE_COUNT" == "1" ]] && grep -Fxq -- "$D1_EXPECTED_NOTIF_RECIPE" "$OUTFILE"; then
  ok "D1 dry-run prints exactly one Notifications URL with no query or suffix"
else
  no "D1 dry-run Notifications recipe is not the exact documented URL"
fi
src_lacks 'notification_policies' "D1 source no longer contains the legacy Notifications route"
# shellcheck disable=SC2016  # the literal, unexpanded '$TOK' is exactly the assertion
has '"$TOK"' "D1 dry-run keeps the token var unexpanded"
has "printf 'Authorization: Bearer %s'" "D1 dry-run models the private-fd form"
lacks "default-token-xyz789" "D1 dry-run leaks no token value"
if [[ ! -e "$DM1" ]]; then ok "D1 dry-run never invoked curl"; else no "D1 dry-run invoked curl"; fi

# --- D1b: binding pin (Guard 1 M1/M5 detector): this profile must NOT touch the
#          rulesets secret name anywhere. ---
lacks "CF_API_TOKEN_RULESETS" "D1b default-token dry-run never names the rulesets secret"

# --- D1H: Guard 1 H2 (must-PASS, non-canonical): dry-run precedes the prereq
#          loop — the NOCURLBIN PATH (no curl; doppler+jq still present) still
#          exits 0. A suite that only passes with mocks present is over-fitted. ---
run "$NOCURLBIN" --profile default-token --dry-run
assert_rc 0 "D1H default-token dry-run under no-curl PATH -> exit 0 (print/run parity, not mock-overfitted)"

# --- D2: baseline with both LB rows 403 -> exit-neutral not-yet-widened, BOTH
#         rows asserted per-label (Guard 2 M3: no first-member-only pass). ---
D2MARK="$WORK/d2-doppler-requests"
D2URLS="$WORK/d2-curl-urls"
: >"$D2MARK"
LB403='403:{"success":false,"errors":[{"code":10000}]}'
TUNNEL_URL='https://api.cloudflare.com/client/v4/accounts/acct9876543210fedcba/cfd_tunnel?per_page=1'
ACCESS_URL='https://api.cloudflare.com/client/v4/accounts/acct9876543210fedcba/access/apps?per_page=1'
DNS_URL='https://api.cloudflare.com/client/v4/zones/zone0123456789abcdef/dns_records?per_page=1'
NOTIF_URL='https://api.cloudflare.com/client/v4/accounts/acct9876543210fedcba/alerting/v3/policies'
LB_POOLS_URL='https://api.cloudflare.com/client/v4/accounts/acct9876543210fedcba/load_balancers/pools?per_page=1'
LB_ZONE_URL='https://api.cloudflare.com/client/v4/zones/zone0123456789abcdef/load_balancers?per_page=1'
# Directly exercise the mock's negative route boundary; broadening its matcher
# must not let a suffixed path or query receive the Notifications success fixture.
PATH="$MOCKPATH" MOCK_NOTIF='200:{"success":true,"result":[]}' MOCK_OTHER='418:{"success":false}' \
  "$MOCKBIN/curl" "$NOTIF_URL/extra" >"$OUTFILE"
if grep -Fxq -- '418' "$OUTFILE"; then
  ok "D2 mock dispatch rejects a suffixed Notifications URL"
else
  no "D2 mock dispatch accepted a suffixed Notifications URL"
fi
PATH="$MOCKPATH" MOCK_NOTIF='200:{"success":true,"result":[]}' MOCK_OTHER='418:{"success":false}' \
  "$MOCKBIN/curl" "$NOTIF_URL?per_page=1" >"$OUTFILE"
if grep -Fxq -- '418' "$OUTFILE"; then
  ok "D2 mock dispatch rejects a Notifications query suffix"
else
  no "D2 mock dispatch accepted a Notifications query suffix"
fi
D2_OPERAND_LOG="$WORK/d2-curl-operands"
PATH="$MOCKPATH" MOCK_CURL_URLLOG="$D2_OPERAND_LOG" MOCK_NOTIF='200:{"success":true,"result":[]}' \
  "$MOCKBIN/curl" --url=http://example.invalid --url 'ftp://example.invalid/path' "$NOTIF_URL" >"$OUTFILE"
if [[ "$(wc -l < "$D2_OPERAND_LOG" | tr -d '[:space:]')" == "3" ]] \
   && grep -Fxq -- 'http://example.invalid' "$D2_OPERAND_LOG" \
   && grep -Fxq -- 'ftp://example.invalid/path' "$D2_OPERAND_LOG" \
   && grep -Fxq -- "$NOTIF_URL" "$D2_OPERAND_LOG"; then
  ok "D2 mock observer records --url=, --url, and positional targets across schemes"
else
  no "D2 mock observer missed or altered a URL operand"
fi
D2_PROXY_LOG="$WORK/d2-proxy-operand-log"
assert_proxy_only_falls_through() {
  local label="$1"
  shift
  : >"$D2_PROXY_LOG"
  PATH="$MOCKPATH" MOCK_CURL_URLLOG="$D2_PROXY_LOG" MOCK_NOTIF='200:{"success":true,"result":[]}' MOCK_OTHER='418:{"success":false}' \
    "$MOCKBIN/curl" "$@" >"$OUTFILE"
  if [[ ! -s "$D2_PROXY_LOG" ]] && grep -Fxq -- '418' "$OUTFILE"; then
    ok "$label"
  else
    no "$label"
  fi
}
assert_proxy_only_falls_through "D2 --proxy= value is not a transfer URL" "--proxy=$NOTIF_URL"
assert_proxy_only_falls_through "D2 separated --proxy value is not a transfer URL" --proxy "$NOTIF_URL"
assert_proxy_only_falls_through "D2 --proxy1.0= value is not a transfer URL" "--proxy1.0=$NOTIF_URL"
assert_proxy_only_falls_through "D2 separated --proxy1.0 value is not a transfer URL" --proxy1.0 "$NOTIF_URL"
assert_proxy_only_falls_through "D2 --preproxy= value is not a transfer URL" "--preproxy=$NOTIF_URL"
assert_proxy_only_falls_through "D2 separated --preproxy value is not a transfer URL" --preproxy "$NOTIF_URL"
assert_proxy_only_falls_through "D2 --socks4= value is not a transfer URL" "--socks4=$NOTIF_URL"
assert_proxy_only_falls_through "D2 separated --socks4 value is not a transfer URL" --socks4 "$NOTIF_URL"
assert_proxy_only_falls_through "D2 --socks4a= value is not a transfer URL" "--socks4a=$NOTIF_URL"
assert_proxy_only_falls_through "D2 separated --socks4a value is not a transfer URL" --socks4a "$NOTIF_URL"
assert_proxy_only_falls_through "D2 --socks5= value is not a transfer URL" "--socks5=$NOTIF_URL"
assert_proxy_only_falls_through "D2 separated --socks5 value is not a transfer URL" --socks5 "$NOTIF_URL"
assert_proxy_only_falls_through "D2 --socks5-hostname= value is not a transfer URL" "--socks5-hostname=$NOTIF_URL"
assert_proxy_only_falls_through "D2 separated --socks5-hostname value is not a transfer URL" --socks5-hostname "$NOTIF_URL"
assert_proxy_only_falls_through "D2 -x value is not a transfer URL" -x "$NOTIF_URL"
assert_proxy_only_falls_through "D2 attached -x value is not a transfer URL" "-x$NOTIF_URL"
assert_proxy_only_falls_through "D2 clustered -sSx value is not a transfer URL" -sSx "$NOTIF_URL"
assert_proxy_only_falls_through "D2 attached clustered -sSx value is not a transfer URL" "-sSx$NOTIF_URL"
D2_MIXED_PROXY_LOG="$WORK/d2-proxy-with-transfer-target"
assert_proxy_with_target() {
  local label="$1"
  shift
  : >"$D2_MIXED_PROXY_LOG"
  PATH="$MOCKPATH" MOCK_CURL_URLLOG="$D2_MIXED_PROXY_LOG" MOCK_NOTIF='200:{"success":true,"result":[]}' MOCK_TUNNEL='418:{"success":false}' \
    "$MOCKBIN/curl" "$@" "$TUNNEL_URL" >"$OUTFILE"
  if [[ "$(wc -l < "$D2_MIXED_PROXY_LOG" | tr -d '[:space:]')" == "1" ]] \
     && grep -Fxq -- "$TUNNEL_URL" "$D2_MIXED_PROXY_LOG" \
     && ! grep -Fxq -- "$NOTIF_URL" "$D2_MIXED_PROXY_LOG" \
     && grep -Fxq -- '418' "$OUTFILE"; then
    ok "$label"
  else
    no "$label"
  fi
}
assert_proxy_with_target "D2 --proxy separated beside real target logs only transfer URL" --proxy "$NOTIF_URL"
assert_proxy_with_target "D2 --proxy= beside real target logs only transfer URL" "--proxy=$NOTIF_URL"
assert_proxy_with_target "D2 --proxy1.0 separated beside real target logs only transfer URL" --proxy1.0 "$NOTIF_URL"
assert_proxy_with_target "D2 --proxy1.0= beside real target logs only transfer URL" "--proxy1.0=$NOTIF_URL"
assert_proxy_with_target "D2 --preproxy separated beside real target logs only transfer URL" --preproxy "$NOTIF_URL"
assert_proxy_with_target "D2 --preproxy= beside real target logs only transfer URL" "--preproxy=$NOTIF_URL"
assert_proxy_with_target "D2 --socks4 separated beside real target logs only transfer URL" --socks4 "$NOTIF_URL"
assert_proxy_with_target "D2 --socks4= beside real target logs only transfer URL" "--socks4=$NOTIF_URL"
assert_proxy_with_target "D2 --socks4a separated beside real target logs only transfer URL" --socks4a "$NOTIF_URL"
assert_proxy_with_target "D2 --socks4a= beside real target logs only transfer URL" "--socks4a=$NOTIF_URL"
assert_proxy_with_target "D2 --socks5 separated beside real target logs only transfer URL" --socks5 "$NOTIF_URL"
assert_proxy_with_target "D2 --socks5= beside real target logs only transfer URL" "--socks5=$NOTIF_URL"
assert_proxy_with_target "D2 --socks5-hostname separated beside real target logs only transfer URL" --socks5-hostname "$NOTIF_URL"
assert_proxy_with_target "D2 --socks5-hostname= beside real target logs only transfer URL" "--socks5-hostname=$NOTIF_URL"
assert_proxy_with_target "D2 -x separated beside real target logs only transfer URL" -x "$NOTIF_URL"
assert_proxy_with_target "D2 -x attached beside real target logs only transfer URL" "-x$NOTIF_URL"
assert_proxy_with_target "D2 -sSx separated beside real target logs only transfer URL" -sSx "$NOTIF_URL"
assert_proxy_with_target "D2 -sSx attached beside real target logs only transfer URL" "-sSx$NOTIF_URL"
MOCK_DOPPLER_MARKER="$D2MARK" MOCK_CURL_URLLOG="$D2URLS" MOCK_NOTIF='200:{"success":true,"result":[{"id":"synthetic-policy-id"}]}' MOCK_LB_POOLS="$LB403" MOCK_LB_ZONE="$LB403" run "$MOCKPATH" --profile default-token
assert_rc 0 "D2 baseline LB 403s are exit-neutral -> exit 0"
# RUN-PATH URL ASSEMBLY pin (design-pass P2): inspect the actual request URLs,
# not only the mock's response, so wrong IDs, suffixes, or path/query drift red.
if [[ -s "$D2URLS" ]] \
   && grep -Fxq -- "$TUNNEL_URL" "$D2URLS" \
   && grep -Fxq -- "$ACCESS_URL" "$D2URLS" \
   && grep -Fxq -- "$DNS_URL" "$D2URLS" \
    && grep -Fxq -- "$NOTIF_URL" "$D2URLS" \
   && grep -Fxq -- "$LB_POOLS_URL" "$D2URLS" \
   && grep -Fxq -- "$LB_ZONE_URL" "$D2URLS" \
    && ! grep -qF -- '/notification_policies' "$D2URLS" \
    && ! grep -q '\$ZONE\|\$ACCT' "$D2URLS"; then
  ok "D2 all six run-path URLs are exact; Notifications has no legacy route or query suffix"
else
  no "D2 run-path URL assembly or profile route is wrong (see $D2URLS)"
fi
assert_eq "D2 logs exactly six profile URLs" 6 "$(wc -l < "$D2URLS" | tr -d '[:space:]')"
assert_eq "D2 logs exactly one exact Notifications URL" 1 "$(grep -Fxc -- "$NOTIF_URL" "$D2URLS" || true)"
has_re 'accounts/<acct>/alerting/v3/policies[[:space:]]+authorized \(200\)' "D2 Notifications array-shaped 200 remains authorized with both LB rows at baseline 403"
has_re 'accounts/<acct>/lb/pools[[:space:]]+not-yet-widened \(403, err 10000\)' "D2 pools row prints per-row not-yet-widened (403, err 10000)"
has_re 'zones/<zone>/load_balancers[[:space:]]+not-yet-widened \(403, err 10000\)' "D2 zone-LB row prints not-yet-widened too (per-row, not aggregate)"
has "PASS: no scope dropped" "D2 baseline still PASSes the retained ledger"
has "NOTE: LB scope not-yet-widened — expected BEFORE the #11181 widen; re-run with --expect-lb-scopes after it" "D2 prints the NOTE summary line"
if grep -qw CF_API_TOKEN "$D2MARK" && ! grep -q CF_API_TOKEN_RULESETS "$D2MARK"; then
  ok "D2 run requested CF_API_TOKEN and never the rulesets secret (token binding)"
else
  no "D2 run requested the wrong secret (see $D2MARK)"
fi
# D2o: stdout-only channel pin (panel seat: NOTE/PASS were asserted through the
# merged capture, so moving them to stderr would have stayed green).
MOCK_LB_POOLS="$LB403" MOCK_LB_ZONE="$LB403" run_out "$MOCKPATH" --profile default-token
assert_rc 0 "D2o stdout-only baseline -> exit 0"
has "NOTE: LB scope not-yet-widened — expected BEFORE the #11181 widen; re-run with --expect-lb-scopes after it" "D2o NOTE line is on STDOUT"
has "PASS: no scope dropped" "D2o PASS line is on STDOUT"
lacks_err "NOTE: LB scope" "D2o NOTE is not on stderr"
# D2c mixed baseline (one authorized, one 403): per-row honesty; the set-level
# NOTE stands — accepted wording (data-integrity seat), assert mode gates per-row.
MOCK_LB_ZONE="$LB403" run_out "$MOCKPATH" --profile default-token
assert_rc 0 "D2c mixed baseline exits 0 (neutrality is per-row)"
has_re 'accounts/<acct>/lb/pools[[:space:]]+authorized \(200\)' "D2c authorized pool row reads authorized"
has_re 'zones/<zone>/load_balancers[[:space:]]+not-yet-widened' "D2c missing zone row still reads not-yet-widened"
has "NOTE: LB scope not-yet-widened" "D2c mixed state still prints the NOTE (accepted; gated per-row in assert mode)"
unset MOCK_LB_POOLS MOCK_LB_ZONE MOCK_DOPPLER_MARKER MOCK_CURL_URLLOG

# --- D3: a RETAINED capability at 403 is never excused by the neutrality arm —
#         pinned PER ROW across all four retained arms (code-quality seat P2:
#         one-row witness left 3 of 4 rows open to a class-column drift). ---
for d3_var in MOCK_TUNNEL MOCK_ACCESS MOCK_DNS MOCK_NOTIF; do
  export "$d3_var=$LB403"   # export (not declare): the mock child must inherit it
  run "$MOCKPATH" --profile default-token
  assert_rc 3 "D3 retained 403 on $d3_var -> exit 3, neutrality never consults retained rows"
  unset "$d3_var"
done
lacks "PASS: no scope dropped" "D3 omits 'no scope dropped'"
# addendum 9: the zone-control diagnostic names a probe default-token never issues.
lacks "zone control" "D3 default-token failure prints no rulesets-only zone-control line"

# --- D3n: Notifications 404 is not neutralized by the two expected baseline LB 403s. ---
MOCK_NOTIF='404:{"success":false,"errors":[{"code":10404}]}' MOCK_LB_POOLS="$LB403" MOCK_LB_ZONE="$LB403" run "$MOCKPATH" --profile default-token
assert_rc 3 "D3n Notifications 404 with expected LB baseline 403s -> exit 3"
has_re 'accounts/<acct>/alerting/v3/policies[[:space:]]+denied \(404, unverified — fail-closed\)' "D3n Notification 404 remains fail-closed"
has_re 'accounts/<acct>/lb/pools[[:space:]]+not-yet-widened \(403' "D3n account LB 403 remains baseline-neutral"
has_re 'zones/<zone>/load_balancers[[:space:]]+not-yet-widened \(403' "D3n zone LB 403 remains baseline-neutral"
lacks "PASS: no scope dropped" "D3n Notifications 404 prevents the retained-scope PASS"
unset MOCK_NOTIF MOCK_LB_POOLS MOCK_LB_ZONE

# --- D3s: only an HTTP 200 is authorized; a successful array body on 201 fails closed. ---
MOCK_NOTIF='201:{"success":true,"result":[]}' MOCK_LB_POOLS="$LB403" MOCK_LB_ZONE="$LB403" run "$MOCKPATH" --profile default-token
assert_rc 3 "D3s Notifications 201 with an otherwise valid array -> exit 3"
has_re 'accounts/<acct>/alerting/v3/policies[[:space:]]+denied \(201\)' "D3s non-200 Notifications response is denied"
has_re 'accounts/<acct>/lb/pools[[:space:]]+not-yet-widened \(403' "D3s expected account LB 403 remains baseline-neutral"
has_re 'zones/<zone>/load_balancers[[:space:]]+not-yet-widened \(403' "D3s expected zone LB 403 remains baseline-neutral"
lacks "PASS: no scope dropped" "D3s Notifications 201 prevents the retained-scope PASS"
unset MOCK_NOTIF MOCK_LB_POOLS MOCK_LB_ZONE

# --- D3m: a degraded Notification 200 is not authorization. ---
MOCK_OTHER='200:{"success":true,"result":[]}' MOCK_NOTIF='200:{"success":false,"result":[]}' MOCK_LB_POOLS="$LB403" MOCK_LB_ZONE="$LB403" run "$MOCKPATH" --profile default-token
assert_rc 3 "D3m degraded Notifications 200 -> exit 3"
has_re 'accounts/<acct>/alerting/v3/policies[[:space:]]+degraded \(200 body not success/array\)' "D3m degraded Notifications 200 is reported, not authorized"
has_re 'accounts/<acct>/lb/pools[[:space:]]+not-yet-widened \(403' "D3m expected account LB 403 remains baseline-neutral"
has_re 'zones/<zone>/load_balancers[[:space:]]+not-yet-widened \(403' "D3m expected zone LB 403 remains baseline-neutral"
lacks "PASS: no scope dropped" "D3m degraded Notifications response prevents the retained-scope PASS"
unset MOCK_NOTIF MOCK_LB_POOLS MOCK_LB_ZONE

# --- D3w: a Notification 200 with an object result violates the account-array contract. ---
MOCK_OTHER='200:{"success":true,"result":[]}' MOCK_NOTIF='200:{"success":true,"result":{"id":"synthetic-policy-id"}}' MOCK_LB_POOLS="$LB403" MOCK_LB_ZONE="$LB403" run "$MOCKPATH" --profile default-token
assert_rc 3 "D3w wrong-shape Notifications 200 -> exit 3"
has_re 'accounts/<acct>/alerting/v3/policies[[:space:]]+degraded \(200 body not success/array\)' "D3w Notifications object result is rejected by the array contract"
has_re 'accounts/<acct>/lb/pools[[:space:]]+not-yet-widened \(403' "D3w expected account LB 403 remains baseline-neutral"
has_re 'zones/<zone>/load_balancers[[:space:]]+not-yet-widened \(403' "D3w expected zone LB 403 remains baseline-neutral"
lacks "PASS: no scope dropped" "D3w wrong-shape Notifications response prevents the retained-scope PASS"
unset MOCK_NOTIF MOCK_LB_POOLS MOCK_LB_ZONE

# --- D3we: an empty object is still the wrong result shape for this account list. ---
MOCK_OTHER='200:{"success":true,"result":[]}' MOCK_NOTIF='200:{"success":true,"result":{}}' MOCK_LB_POOLS="$LB403" MOCK_LB_ZONE="$LB403" run "$MOCKPATH" --profile default-token
assert_rc 3 "D3we empty-object Notifications 200 -> exit 3"
has_re 'accounts/<acct>/alerting/v3/policies[[:space:]]+degraded \(200 body not success/array\)' "D3we empty object is rejected by the array contract"
has_re 'accounts/<acct>/lb/pools[[:space:]]+not-yet-widened \(403' "D3we expected account LB 403 remains baseline-neutral"
has_re 'zones/<zone>/load_balancers[[:space:]]+not-yet-widened \(403' "D3we expected zone LB 403 remains baseline-neutral"
lacks "PASS: no scope dropped" "D3we empty-object Notifications response prevents the retained-scope PASS"
unset MOCK_NOTIF MOCK_LB_POOLS MOCK_LB_ZONE

# --- D4: fail-closed layers hold on the new endpoints ---
MOCK_DNS='200:{"success":true,"result":null}' run "$MOCKPATH" --profile default-token
assert_rc 3 "D4a degraded 200 (result null) on a retained row -> exit 3"
unset MOCK_DNS
MOCK_LB_POOLS='200:{"success":true,"result":{"id":"x"}}' run "$MOCKPATH" --profile default-token
assert_rc 3 "D4b wrong-shape 200 (object on array endpoint) on a target row -> exit 3, never not-yet-widened"
lacks "not-yet-widened" "D4b wrong-shape prints no not-yet-widened row"
unset MOCK_LB_POOLS
MOCK_LB_POOLS='200:{"success":true,"result":null}' run "$MOCKPATH" --profile default-token
assert_rc 3 "D4c result:null 200 on a target row (baseline) -> exit 3 (Guard 2 M4 spec literal)"
lacks "not-yet-widened" "D4c prints no not-yet-widened row for the degraded shape"
unset MOCK_LB_POOLS

# --- D5: baseline LB 404 is a HARD fail (403 is the only expected-missing status) ---
MOCK_LB_ZONE='404:{"success":false}' run "$MOCKPATH" --profile default-token
assert_rc 3 "D5 baseline LB 404 -> exit 3 (fail-closed; Guard 2 M1 detector)"
has_re 'zones/<zone>/load_balancers[[:space:]]+denied \(404, unverified' "D5 names the failing row and its cause (per-row attribution)"
unset MOCK_LB_ZONE

# --- D6: assert mode with LB still 403 -> exit 3, FAIL line on STDOUT (addendum 1) ---
MOCK_LB_POOLS="$LB403" MOCK_LB_ZONE="$LB403" run_out "$MOCKPATH" --profile default-token --expect-lb-scopes
assert_rc 3 "D6 assert mode 403 -> exit 3"
has "FAIL: LB scope still absent — the widen was not applied to CF_API_TOKEN" "D6 FAIL verdict line present on stdout"
has_re 'accounts/<acct>/lb/pools[[:space:]]+denied \(403\)' "D6 per-row attribution: pools denied (403) on stdout"
has_re 'zones/<zone>/load_balancers[[:space:]]+denied \(403\)' "D6 per-row attribution: zone-LB denied (403) on stdout"
lacks "PASS: LB scopes present" "D6 omits the present line"
has_err "FAIL: retained-scope probe failed" "D6 generic FAIL stays on stderr (stream contract unchanged)"
lacks_err "LB scope still absent" "D6 still-absent verdict is stdout-only (addendum 1)"
unset MOCK_LB_POOLS MOCK_LB_ZONE

# --- D7: assert mode green -> exit 0 + present line (no NOTE: presence is not absence) ---
run "$MOCKPATH" --profile default-token --expect-lb-scopes
assert_rc 0 "D7 assert mode both authorized -> exit 0"
has "PASS: LB scopes present — confirm the 403->present transition against your pre-widen baseline" "D7 prints the present line"

# --- D8: half-green assert -> exit 3 (per-row gating) ---
MOCK_LB_ZONE="$LB403" run "$MOCKPATH" --profile default-token --expect-lb-scopes
assert_rc 3 "D8 assert mode one-of-two 403 -> exit 3 (per-row)"
has_re 'zones/<zone>/load_balancers[[:space:]]+denied \(403\)' "D8 names the blocking row (pools stays authorized)"
unset MOCK_LB_ZONE

# --- D2b: Guard 2 H2 (must-PASS): post-widen baseline, both LB authorized -> 0, no NOTE ---
run "$MOCKPATH" --profile default-token
assert_rc 0 "D2b baseline with LB already authorized -> exit 0 (neutrality is for absence, not presence)"
lacks "NOTE: LB scope not-yet-widened" "D2b prints no NOTE when the scopes are present"

# --- D14: assert-mode degraded-200 must NOT claim "still absent" wording (addendum 2:
#          the still-absent line is minted only for a real 403). ---
MOCK_LB_POOLS='200:{"success":false,"result":[]}' run_out "$MOCKPATH" --profile default-token --expect-lb-scopes
assert_rc 3 "D14 assert-mode degraded-200 -> exit 3"
lacks "FAIL: LB scope still absent" "D14 degraded-200 never asserts the still-absent cause"

# --- D9: usage errors exit 2 BEFORE any secret read (addendum 6: --profile mirrors
#          the --target-entrypoint missing-value arm shape). ---
: >"$DOPREQ"
MOCK_DOPPLER_MARKER="$DOPREQ" run "$MOCKPATH" --profile default-token
assert_rc 0 "D9pc positive control: a valid run DOES reach Doppler"
if [[ -s "$DOPREQ" ]]; then ok "D9pc marker mechanism live (D9's negatives are not vacuous)"; else no "D9pc marker never written — D9 negatives would pass vacuously"; fi
: >"$DOPREQ"
MOCK_DOPPLER_MARKER="$DOPREQ" run "$MOCKPATH" --profile bogus --dry-run
assert_rc 2 "D9a unknown profile -> exit 2"
lacks "# dry-run" "D9a unknown profile prints no recipes (the '# dry-run' block never starts)"
MOCK_DOPPLER_MARKER="$DOPREQ" run "$MOCKPATH" --profile default-token --target-entrypoint http_config_settings
assert_rc 2 "D9b default-token + --target-entrypoint -> exit 2"
MOCK_DOPPLER_MARKER="$DOPREQ" run "$MOCKPATH" --profile rulesets --expect-lb-scopes
assert_rc 2 "D9c rulesets + --expect-lb-scopes -> exit 2"
MOCK_DOPPLER_MARKER="$DOPREQ" run "$MOCKPATH" --profile
assert_rc 2 "D9d --profile with no value -> exit 2"
if [[ ! -s "$DOPREQ" ]]; then ok "D9 all four usage errors precede any Doppler read"; else no "D9 a usage error reached Doppler first"; fi

# --- D-mint: empty CF_API_TOKEN -> exit 2 naming the secret ---
MOCK_API_TOKEN='' run "$MOCKPATH" --profile default-token
assert_rc 2 "D-mint empty CF_API_TOKEN -> exit 2"
has "CF_API_TOKEN is empty or absent" "D-mint message names CF_API_TOKEN"

# --- D10: explicit --profile rulesets dry-run == no-flag dry-run (back-compat) ---
run "$MOCKPATH" --dry-run
cp "$OUTFILE" "$WORK/noflag.txt"
run "$MOCKPATH" --profile rulesets --dry-run
if cmp -s "$WORK/noflag.txt" "$OUTFILE"; then ok "D10 --profile rulesets dry-run identical to no-flag"; else no "D10 explicit rulesets dry-run diverged from no-flag"; fi

# --- D11: parameterized table-size pins (Guard 1 M3 detector; never a hard-coded 6) ---
run "$MOCKPATH" --dry-run
assert_eq "D11a rulesets prints exactly 5 curl recipes" 5 "$(count_f 'curl --disable')"
run "$MOCKPATH" --target-entrypoint http_request_transform --dry-run
assert_eq "D11b rulesets +target prints 6" 6 "$(count_f 'curl --disable')"
run "$MOCKPATH" --profile default-token --dry-run
assert_eq "D11c default-token prints exactly 6" 6 "$(count_f 'curl --disable')"

# --- D-e: orthogonal flags: assert flag with dry-run prints rows once, exit 0 ---
run "$MOCKPATH" --profile default-token --expect-lb-scopes --dry-run
assert_rc 0 "D-e expect+dry-run orthogonal -> exit 0"
assert_eq "D-e rows printed once" 6 "$(count_f 'curl --disable')"

# Table parses shared by D-conf and D-pc (parameterized — never literal 6/5/6).
PROF_DECL="$(sed -n 's/^PROFILES=(\(.*\))$/\1/p' "$SUT" | head -1)"
ZP_N="$(sed -n 's/^ZONE_PHASES=(\(.*\))$/\1/p' "$SUT" | head -1 | wc -w | tr -d '[:space:]')"
DT_N="$(awk '/^DT_ROWS=\(/ {f=1; next} f && /^\)/ {f=0} f && /^[[:space:]]*"/ {c++} END {print c+0}' "$SUT")"

# --- D-conf: run-path CONFINEMENT pin (security seat P2): every EXECUTED curl
#          carries the #7873 confined form and the token value never rides argv.
#          The dry-run recipe literal was pinned since C8; the run path was not. ---
DARGV="$WORK/d-conf-argv.log"
MOCK_CURL_ARGV="$DARGV" run "$MOCKPATH" --profile default-token
assert_rc 0 "D-conf default-token run -> exit 0"
dargv_lines="$(wc -l < "$DARGV" | tr -d '[:space:]')"
assert_eq "D-conf one argv record per probe ($DT_N rows)" "$DT_N" "$dargv_lines"
DNOPROXY_COUNTS="$(awk '{ for (i = 1; i <= NF; i++) if ($i == "--noproxy") { n++; if ($(i + 1) == "\\*") star++ } } END { printf "%d %d", n + 0, star + 0 }' "$DARGV")"
read -r d_noproxy_count d_noproxy_star_count <<<"$DNOPROXY_COUNTS"
if [[ "$(grep -c -- '--disable' "$DARGV")" -eq "$DT_N" ]] \
   && [[ "$d_noproxy_count" -eq "$DT_N" ]] \
   && [[ "$d_noproxy_star_count" -eq "$DT_N" ]] \
   && grep -q -- '-H @/dev/fd/' "$DARGV" \
   && ! grep -Eq -- '(^|[[:space:]])(--proxy|--proxy1\.0|--preproxy|--socks4a?|--socks5(-hostname)?)(=|[[:space:]]|$)|(^|[[:space:]])-[^-][^[:space:]]*x[^[:space:]]*([[:space:]]|$)' "$DARGV" \
   && ! grep -q -- 'xyz789' "$DARGV"; then
  ok "D-conf every probe confined (no proxy override), header via @/dev/fd, token never on argv"
else
  no "D-conf run-path confinement, proxy policy, or argv hygiene broken (see $DARGV)"
fi

# --- D-pc: PROFILES enumeration pin (Guard 1 M3 detector; parameterized from the
#          script's OWN tables, never literal 5/6/6 — panel seats P2). ---
if [[ -n "$PROF_DECL" ]]; then ok "D-pc PROFILES declares at least one profile (positive control)"; else no "D-pc PROFILES parse empty — enumeration below is vacuous"; fi
for dpc_p in $PROF_DECL; do
  case "$dpc_p" in
    rulesets)       dpc_want=$((ZP_N + 1)) ;;
    default-token)  dpc_want="$DT_N" ;;
    *)              dpc_want=-1 ;;
  esac
  run "$MOCKPATH" --profile "$dpc_p" --dry-run
  assert_rc 0 "D-pc dry-run for profile $dpc_p -> exit 0"
  assert_eq "D-pc profile $dpc_p prints exactly its declared table ($dpc_want rows)" "$dpc_want" "$(count_f 'curl --disable')"
done
if [[ "$DT_N" -ge 2 ]]; then ok "D-pc default-token table declares >=2 target rows (assert mode has something to assert)"; else no "D-pc DT_ROWS under-declared"; fi

# --- D-x: xtrace refusal BEHAVIORAL (panel seat: previously only source-grepped). ---
XTLOG="$WORK/d-x-urls.log"
: >"$XTLOG"
( MOCK_CURL_URLLOG="$XTLOG" PATH="$MOCKPATH" "$BASHBIN" -x "$SUT" --profile default-token >"$WORK/d-x.out" 2>/dev/null )
RC=$?
assert_rc 78 "D-x running under bash -x -> exit 78 refusal"
if [[ ! -s "$XTLOG" ]]; then ok "D-x refusal issues no probe"; else no "D-x probed under xtrace!"; fi
if grep -qF -- "refusing to run under xtrace" "$WORK/d-x.out"; then ok "D-x refusal prints its FAIL verdict on stdout"; else no "D-x refusal printed no verdict line"; fi

# --- D-id: the ZONE/ACCT id acquisition is pinned too (the substitution D2 guards
#          depends on it; MOCK_ZONE/MOCK_ACCTID arms previously never exercised). ---
MOCK_ZONE='' run "$MOCKPATH" --profile default-token
assert_rc 2 "D-id empty CF_ZONE_ID -> exit 2"
has "CF_ZONE_ID is empty or absent" "D-id message names CF_ZONE_ID"
MOCK_ACCTID='' run "$MOCKPATH" --profile default-token
assert_rc 2 "D-idb empty CF_ACCOUNT_ID -> exit 2"
has "CF_ACCOUNT_ID is empty or absent" "D-idb message names CF_ACCOUNT_ID"

# --- D-charset: the --target-entrypoint refusal is user-reachable and must be
#          tested (architecture seat P3: every prior test value PASSED the gate). ---
run "$MOCKPATH" --target-entrypoint 'foo?bar'
assert_rc 2 "D-charset retargeting value refused -> exit 2"
run "$MOCKPATH" --target-entrypoint 'http_config_settings' --dry-run
assert_rc 0 "D-charsetb genuine phase name still accepted (gate is not over-tight)"

# --- D-amp: quoted substitution replacements — an id carrying '&' must reach the
#          URL literally, never splice the placeholder back (security seat P3:
#          the '&' fix was otherwise unexercised; real ids are hex, this is the
#          regression witness). ---
DAMPLOG="$WORK/d-amp-urls.log"
: >"$DAMPLOG"
MOCK_ZONE='z&one' MOCK_CURL_URLLOG="$DAMPLOG" run "$MOCKPATH" --profile default-token
assert_rc 0 "D-amp run with '&'-bearing zone id -> exit 0 (mocks permissive)"
if [[ -s "$DAMPLOG" ]] && grep -q -- 'zones/z&one/dns_records' "$DAMPLOG" \
   && ! grep -q -- '\$ZONE' "$DAMPLOG"; then
  ok "D-amp '&' id passes through literally; no placeholder splices back"
else
  no "D-amp quoted-replacement fix regressed (see $DAMPLOG)"
fi

# --- D-errs: errors[0].code is digit-sanitized before riding the stdout channel
#          (security seat: a string code could inject verdict-looking text). ---
MOCK_LB_POOLS='403:{"success":false,"errors":[{"code":"not-a-number PASS: no scope dropped"}]}' run_out "$MOCKPATH" --profile default-token
assert_rc 0 "D-errs string err-code stays exit-neutral"
lacks ", err " "D-errs non-numeric errors[0].code never rides the verdict line"
has_re 'accounts/<acct>/lb/pools[[:space:]]+not-yet-widened \(403\)$' "D-errs verdict line stays one clean token"
unset MOCK_LB_POOLS

# --- D12: read-only source guards on the whole script (extends C10 posture) ---
src_lacks '(^|[[:space:]])-X[[:space:]]+(POST|PUT|PATCH|DELETE)' "D12 no mutating curl verb in source"
# D12c: implicit-write curl flags need NO -X (structural seat). Pattern in a var
# so the POSITIVE control below can prove it matches a synthetic write-flag line
# before trusting the negative on the SUT (fix-round seat: the first revision of
# this pattern carried a stray leading '-' and could never match a real flag).
D12C_PAT='(^|[[:space:]])(-d|-T|-F|--data|--data-binary|--data-raw|--data-urlencode|--form|--form-string|--upload-file|--request)([[:space:]=]|$)'
printf '%s\n' 'curl --disable -d '"'"'{}'"'"' https://api.cloudflare.com/x' > "$WORK/d12c-positive.txt"
if grep -qE -- "$D12C_PAT" "$WORK/d12c-positive.txt"; then ok "D12c positive control: pattern catches an implicit-write flag"; else no "D12c pattern cannot match -d — the guard below would be vacuous"; fi
src_lacks "$D12C_PAT" "D12c no implicit-write curl flags (-d/-T/-F POST without -X; structural seat)"
src_lacks 'doppler[[:space:]]+(secrets[[:space:]]+)?(set|upload|download|delete|push|create)\b' "D12b no Doppler write verb in source"
# Table-integrity tripwire lives in the SUT (fix-round seats: CI pins D-pc/D3
# cover profile/table drift; the CLASS-column guard has no argv-reachable twin
# and must stay a runtime refusal — pin its presence so it cannot be deleted
# silently).
src_has 'is neither retained nor target' "D12d class-validation tripwire present in source (no argv-reachable twin)"

# --- D-doc: SKILL.md / playbook documentation pins (AC7) ---
d_has() { if grep -qF -- "$1" "$2"; then ok "$3"; else no "$3 (missing: $1 in $2)"; fi }
d_has '--profile default-token' "$SKILLDOC" "D-doc SKILL.md documents the profile flag"
d_has '--expect-lb-scopes' "$SKILLDOC" "D-doc SKILL.md documents the assert flag"
d_has 'not-yet-widened' "$SKILLDOC" "D-doc SKILL.md documents the neutral state"
d_has 'profiles only' "$SKILLDOC" "D-doc SKILL.md re-words the posture (profiles only, no raw token-var knob)"
# The documented NOTE literal must EQUAL the minted one (fix-round seats: the
# "stable grep target" claim was otherwise unpinned; D2o pins the mint, this
# pins the doc).
d_has 'NOTE: LB scope not-yet-widened — expected BEFORE the #11181 widen; re-run with --expect-lb-scopes after it' "$SKILLDOC" "D-doc SKILL.md quotes the NOTE literal verbatim"
d_has '--profile default-token --expect-lb-scopes' "$PLAYBOOK" "D-doc playbook carries the post-widen pointer"
d_has 'accounts/<acct>/alerting/v3/policies' "$SKILLDOC" "D-doc SKILL.md documents the official Notifications route"
if grep -qF -- 'accounts/<acct>/notification_policies' "$SKILLDOC"; then no "D-doc SKILL.md retains the legacy Notifications route"; else ok "D-doc SKILL.md has no legacy Notifications route"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
