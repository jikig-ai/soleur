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
# The URL is the last positional argument. A spec of "NONE" emits nothing at all
# (models a total curl failure -> empty response, the no-newline path).
[[ -n "${MOCK_CURL_MARKER:-}" ]] && printf 'called\n' >>"$MOCK_CURL_MARKER"
url=""
for a in "$@"; do url="$a"; done
# Real CF shapes: a zone .../entrypoint returns a single ruleset OBJECT; the
# account /rulesets list returns an ARRAY. The mock must mirror this so the
# per-scheme body-shape check is exercised against the true contract (#6892 QA).
ZONE_AUTH='200:{"success":true,"result":{"id":"r","kind":"zone","phase":"p","rules":[]}}'
ACCT_AUTH='200:{"success":true,"result":[]}'
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
  *notification_policies*)         spec="${MOCK_NOTIF:-$ACCT_AUTH}" ;;
  *load_balancers/pools*)          spec="${MOCK_LB_POOLS:-$ACCT_AUTH}" ;;
  *load_balancers*)                spec="${MOCK_LB_ZONE:-$ACCT_AUTH}" ;;
  */rulesets)                      spec="${MOCK_ACCT:-$ACCT_AUTH}" ;;
  *)                               spec="${MOCK_OTHER:-$ZONE_AUTH}" ;;
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
for u in cfd_tunnel access/apps dns_records notification_policies "load_balancers/pools" 'zones/$ZONE/load_balancers'; do
  has "$u" "D1 dry-run prints the $u row"
done
# shellcheck disable=SC2016  # the literal, unexpanded '$TOK' is exactly the assertion
has '"$TOK"' "D1 dry-run keeps the token var unexpanded"
has "printf 'Authorization: Bearer %s'" "D1 dry-run models the private-fd form"
lacks "default-token-xyz789" "D1 dry-run leaks no token value"
if [[ ! -e "$DM1" ]]; then ok "D1 dry-run never invoked curl"; else no "D1 dry-run invoked curl"; fi

# --- D1b: binding pin (Guard 1 M1/M5 detector): this profile must NOT touch the
#          rulesets secret name anywhere. ---
lacks "CF_API_TOKEN_RULESETS" "D1b default-token dry-run never names the rulesets secret"

# --- D1H: Guard 1 H2 (must-PASS, non-canonical): dry-run precedes the prereq
#          loop — no curl/doppler on PATH still exits 0. ---
run "$NOCURLBIN" --profile default-token --dry-run
assert_rc 0 "D1H default-token dry-run under no-curl PATH -> exit 0 (print/run parity, not mock-overfitted)"

# --- D2: baseline with both LB rows 403 -> exit-neutral not-yet-widened, BOTH
#         rows asserted per-label (Guard 2 M3: no first-member-only pass). ---
D2MARK="$WORK/d2-doppler-requests"
: >"$D2MARK"
LB403='403:{"success":false,"errors":[{"code":10000}]}'
MOCK_DOPPLER_MARKER="$D2MARK" MOCK_LB_POOLS="$LB403" MOCK_LB_ZONE="$LB403" run "$MOCKPATH" --profile default-token
assert_rc 0 "D2 baseline LB 403s are exit-neutral -> exit 0"
has_re 'accounts/<acct>/lb/pools[[:space:]]+not-yet-widened \(403, err 10000\)' "D2 pools row prints per-row not-yet-widened (403, err 10000)"
has_re 'zones/<zone>/load_balancers[[:space:]]+not-yet-widened \(403, err 10000\)' "D2 zone-LB row prints not-yet-widened too (per-row, not aggregate)"
has "PASS: no scope dropped" "D2 baseline still PASSes the retained ledger"
has "NOTE: LB scope not-yet-widened — expected BEFORE the #11181 widen; re-run with --expect-lb-scopes after it" "D2 prints the NOTE summary line"
if grep -qw CF_API_TOKEN "$D2MARK" && ! grep -q CF_API_TOKEN_RULESETS "$D2MARK"; then
  ok "D2 run requested CF_API_TOKEN and never the rulesets secret (token binding)"
else
  no "D2 run requested the wrong secret (see $D2MARK)"
fi

# --- D3: a RETAINED capability at 403 is never excused by the neutrality arm ---
MOCK_TUNNEL="$LB403" run "$MOCKPATH" --profile default-token
assert_rc 3 "D3 retained (tunnel) 403 -> exit 3, neutrality never consults retained rows"
lacks "PASS: no scope dropped" "D3 omits 'no scope dropped'"
unset MOCK_TUNNEL

# --- D4: fail-closed layers hold on the new endpoints ---
MOCK_DNS='200:{"success":true,"result":null}' run "$MOCKPATH" --profile default-token
assert_rc 3 "D4a degraded 200 (result null) on a retained row -> exit 3"
unset MOCK_DNS
MOCK_LB_POOLS='200:{"success":true,"result":{"id":"x"}}' run "$MOCKPATH" --profile default-token
assert_rc 3 "D4b wrong-shape 200 (object on array endpoint) on a target row -> exit 3, never not-yet-widened"
lacks "not-yet-widened" "D4b wrong-shape prints no not-yet-widened row"
unset MOCK_LB_POOLS

# --- D5: baseline LB 404 is a HARD fail (403 is the only expected-missing status) ---
MOCK_LB_ZONE='404:{"success":false}' run "$MOCKPATH" --profile default-token
assert_rc 3 "D5 baseline LB 404 -> exit 3 (fail-closed; Guard 2 M1 detector)"
unset MOCK_LB_ZONE

# --- D6: assert mode with LB still 403 -> exit 3, FAIL line on STDOUT (addendum 1) ---
MOCK_LB_POOLS="$LB403" MOCK_LB_ZONE="$LB403" run_out "$MOCKPATH" --profile default-token --expect-lb-scopes
assert_rc 3 "D6 assert mode 403 -> exit 3"
has "FAIL: LB scope still absent — the widen was not applied to CF_API_TOKEN" "D6 FAIL verdict line present on stdout"
lacks "PASS: LB scopes present" "D6 omits the present line"
unset MOCK_LB_POOLS MOCK_LB_ZONE

# --- D7: assert mode green -> exit 0 + present line (no NOTE: presence is not absence) ---
run "$MOCKPATH" --profile default-token --expect-lb-scopes
assert_rc 0 "D7 assert mode both authorized -> exit 0"
has "PASS: LB scopes present — confirm the 403->present transition against your pre-widen baseline" "D7 prints the present line"

# --- D8: half-green assert -> exit 3 (per-row gating) ---
MOCK_LB_ZONE="$LB403" run "$MOCKPATH" --profile default-token --expect-lb-scopes
assert_rc 3 "D8 assert mode one-of-two 403 -> exit 3 (per-row)"
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

# --- D12: read-only source guards on the whole script (extends C10 posture) ---
src_lacks '-X[[:space:]]+(POST|PUT|PATCH|DELETE)' "D12 no mutating curl verb in source"
src_lacks 'doppler[[:space:]]+(secrets[[:space:]]+)?(set|upload|download|delete)\b' "D12b no Doppler write verb in source"

# --- D-doc: SKILL.md / playbook documentation pins (AC7) ---
d_has() { if grep -qF -- "$1" "$2"; then ok "$3"; else no "$3 (missing: $1 in $2)"; fi }
d_has '--profile default-token' "$SKILLDOC" "D-doc SKILL.md documents the profile flag"
d_has '--expect-lb-scopes' "$SKILLDOC" "D-doc SKILL.md documents the assert flag"
d_has 'not-yet-widened' "$SKILLDOC" "D-doc SKILL.md documents the neutral state"
d_has 'profiles only' "$SKILLDOC" "D-doc SKILL.md re-words the posture (profiles only, no raw token-var knob)"
d_has '--profile default-token --expect-lb-scopes' "$PLAYBOOK" "D-doc playbook carries the post-widen pointer"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
