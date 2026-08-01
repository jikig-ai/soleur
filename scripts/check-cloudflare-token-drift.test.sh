#!/usr/bin/env bash
# Tests the Cloudflare ACCESS SERVICE TOKEN arm of check-cloudflare-token-drift.sh.
#
# Background: the script's own header cites REGISTRY_PUSH_ACCESS_TOKEN_* as the first
# case that motivated it, but its enumeration regex was `CF_API_TOKEN[A-Z0-9_]*` — an
# anchored pattern that cannot match a key which does not begin with CF_API_TOKEN. So the
# script reported "0 dead" on a fleet where exactly that token had gone stale. A clean
# bill of health for a question that was never asked is worse than no script at all, and
# these tests exist to keep that specific shape from coming back.
#
# The verification arm was wrong too: an Access service token is a client-id/secret PAIR,
# and /user/tokens/verify with an `Authorization: Bearer` header is the API-TOKEN
# endpoint. It cannot say anything true about a pair.
#
# Method: `doppler` and `curl` are stubbed on PATH, so nothing here touches Cloudflare,
# Doppler, or the network. Every credential is SYNTHESIZED (cq-test-fixtures-synthesized-only)
# — the id/secret values below are structurally shaped like the real thing and are not,
# and have never been, valid anywhere.
#
# Run: bash scripts/check-cloudflare-token-drift.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$REPO_ROOT/scripts/check-cloudflare-token-drift.sh"

# /tmp is a machine-global 4 GiB tmpfs shared with every sibling worktree; a suite that
# builds sandboxes there has its verdicts turned into a function of another session's
# disk usage. Default to /var/tmp when invoked directly (test-all.sh already exports it).
export TMPDIR="${TMPDIR:-/var/tmp}"

PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d) || { echo "FATAL: could not create sandbox"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
STUB_DIR="$TMP/bin"
mkdir -p "$STUB_DIR" || { echo "FATAL: could not create stub dir"; exit 2; }

# ---------------------------------------------------------------------------
# Synthesized fixtures. Access service-token ids are <32 hex>.access, and secrets are
# 64 hex — the real shape, so a future format check would exercise the same path. These
# specific values are invented.
# ---------------------------------------------------------------------------
FIX_ID="0123456789abcdef0123456789abcdef.access"
FIX_SECRET="fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"

# `doppler` stub. Reads its fixture world from two files so each case can reshape it
# without rewriting the stub:
#   $MOCK_CONFIGS  — one config name per line
#   $MOCK_SECRETS  — "<config>|<KEY>|<value>" per line
# NOTE ON FIXTURE CARDINALITY (the axis a mutation battery cannot see):
# this script exists because "5 of 7 configs stale after a dashboard roll". A suite whose
# every fixture holds ONE config cannot observe that requirement at all — measured:
# rewriting `for cfg in "${CONFIGS[@]}"` to `"${CONFIGS[0]}"` at any of the three loops
# left an 8/8 green suite while destroying the script's entire purpose. T9 below is the
# two-config case that kills all three of those mutants.
cat > "$STUB_DIR/doppler" <<'STUB'
#!/usr/bin/env bash
[[ -n "${MOCK_DOPPLER_LOG:-}" ]] && printf '%s\n' "$*" >> "$MOCK_DOPPLER_LOG"
case "${1:-}" in
  configs)
    printf '['
    _first=1
    while read -r c; do
      [[ -z "$c" ]] && continue
      [[ "$_first" == 1 ]] || printf ','
      printf '{"name":"%s"}' "$c"
      _first=0
    done < "$MOCK_CONFIGS"
    printf ']\n'
    ;;
  secrets)
    # `doppler secrets get KEY -p P -c CFG --plain` vs `doppler secrets -p P -c CFG --only-names`
    if [[ "${2:-}" == "get" ]]; then
      _key="$3"; _cfg=""
      # Positional scan: the flag order is fixed by the caller, but scanning is robust to
      # it changing, which a positional index would not be.
      for ((i=1; i<=$#; i++)); do
        [[ "${!i}" == "-c" ]] && { j=$((i+1)); _cfg="${!j}"; }
      done
      _v=$(grep -E "^${_cfg}\|${_key}\|" "$MOCK_SECRETS" 2>/dev/null | head -1 | cut -d'|' -f3-)
      [[ -n "$_v" ]] && printf '%s\n' "$_v"
      exit 0
    fi
    _cfg=""
    for ((i=1; i<=$#; i++)); do
      [[ "${!i}" == "-c" ]] && { j=$((i+1)); _cfg="${!j}"; }
    done
    # Anchored: an unanchored `grep -F "prd|"` also matches `prd_terraform|…`, which would
    # silently bleed one config's keys into another the moment cardinality exceeds 1 —
    # exactly when the two-config cases below need it to be exact.
    grep -E "^${_cfg}\|" "$MOCK_SECRETS" 2>/dev/null | cut -d'|' -f2
    ;;
esac
exit 0
STUB
chmod +x "$STUB_DIR/doppler"

# `curl` stub. Records every invocation's full argv to $MOCK_CURL_LOG so the tests can
# assert HOW the token was presented, not merely what verdict came back — a verdict-only
# assertion would pass against an implementation that kept using the wrong endpoint and
# happened to get the right answer. $MOCK_HTTP_CODE drives the response.
# `curl` stub. Records argv to $MOCK_CURL_LOG so the tests can assert HOW a token was
# presented, not merely what verdict came back.
#
# It MODELS THE FLAGS, which the first version did not — and that omission was the
# suite's single largest blind spot. Measured: deleting `-o /dev/null -w '%{http_code}'`
# from the SUT left 8/8 green, while in production it makes `code` the response BODY,
# which for the tcp:// registry ingress is EMPTY — so `case "" in 200)` falls through and
# EVERY Access token reports DEAD on every release preflight. A stub whose correctness
# depends on a flag it ignores cannot see the flag being removed.
#
# Two response channels, because the two arms parse differently: the Access arm reads the
# `-w` status code, the API arm parses a JSON BODY. A stub that returned the status code
# as the body made the API arm's json.load() raise on every call, so it always printed
# DEAD — which meant a mutation forcing every API token to LIVE was invisible.
#
# It also MODELS THE ACCESS STAMP and `-D`, because the verdict is now drawn from the
# response HEADERS, not the status code. A stub that emitted no headers would make every
# response indistinguishable from an ungated one, so every case would grade `gate-absent`
# — the stub would decide the verdict instead of observing it.
#
# Shapes are the MEASURED ones (2026-08-01, real hosts):
#   uncredentialed -> 403 + cf-access-aud + cf-access-domain   (Access denial page)
#   admitted       -> 200, zero-byte body, NO cf-access-*       (edge answered)
# so the stub's defaults reproduce production rather than a convenient invention.
#
# And it MODELS curl's EXIT STATUS. The old stub ended `exit 0` unconditionally, which is
# how `code=$(curl ... || printf '000')` shipped: real curl prints its -w output AND exits
# non-zero on a transport failure, concatenating to `000000` / `200000`. A stub that
# cannot exit non-zero cannot see that.
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
[[ -n "${MOCK_CURL_LOG:-}" ]] && printf '%s\n' "$*" >> "$MOCK_CURL_LOG"
_want_code=0
_outfile=""
_hdrfile=""
_credentialed=0
_host=""
for ((i=1; i<=$#; i++)); do
  case "${!i}" in
    -w) j=$((i+1)); [[ "${!j}" == *'%{http_code}'* ]] && _want_code=1 ;;
    -o) j=$((i+1)); _outfile="${!j}" ;;
    -D) j=$((i+1)); _hdrfile="${!j}" ;;
    -H) j=$((i+1)); [[ "${!j}" == CF-Access-Client-Id:* ]] && _credentialed=1 ;;
    https://*) _host="${!i}"; _host="${_host#https://}"; _host="${_host%%/*}" ;;
  esac
done

# Per-host override file: "<host>|<control_code>|<control_stamped>|<cred_code>|<cred_stamped>".
# Without this a single MOCK_HTTP_CODE governs every host, which makes a fixture carrying
# two bases structurally unable to express "this host admits, that one rejects" — the axis
# the previous suite could not test at all.
# Field order: host|c_code|c_stamp|r_code|r_stamp|r_mitigated|c_access_redirect
# The last two model the two refusal shapes that carry NO cf-access-* header and are
# therefore invisible to the stamp alone: Cloudflare's own block/challenge (cf-mitigated)
# and an Access identity-policy redirect to the IdP login (Location).
_c_code=""; _c_stamp=""; _r_code=""; _r_stamp=""; _r_mitig=""; _c_redir=""
if [[ -n "${MOCK_HOSTS:-}" && -f "${MOCK_HOSTS}" && -n "$_host" ]]; then
  _line=$(grep -E "^${_host}\|" "$MOCK_HOSTS" 2>/dev/null | head -1)
  if [[ -n "$_line" ]]; then
    IFS='|' read -r _ _c_code _c_stamp _r_code _r_stamp _r_mitig _c_redir <<< "$_line"
  fi
fi
: "${_r_mitig:=0}"
: "${_c_redir:=0}"
: "${_c_code:=${MOCK_CONTROL_CODE:-403}}"
: "${_c_stamp:=${MOCK_CONTROL_STAMPED:-1}}"
: "${_r_code:=${MOCK_HTTP_CODE:-200}}"
# The credentialed stamp is NEVER inferred from the status code. It used to default
# `403 -> stamped, else -> unstamped`, and that inference made the suite tautological: a
# case setting only MOCK_HTTP_CODE produced the same verdict under a STAMP rule and under
# a STATUS rule, so six cases could not tell the two apart. Measured — inserting
# `elif [[ "$PROBE_CODE" == 200 ]]; then LIVE` ahead of the stamp test, i.e. restoring the
# exact instrument this PR exists to remove, passed 27/27.
#
# Default is now UNSTAMPED, and any case asserting a rejection must say so explicitly.
# That makes the stamp an INPUT the case controls rather than a shadow of the code.
: "${_r_stamp:=${MOCK_CRED_STAMPED:-0}}"

if [[ "$_credentialed" == 1 ]]; then _code="$_r_code"; _stamped="$_r_stamp"
else _code="$_c_code"; _stamped="$_c_stamp"
fi

# Per-CREDENTIAL override: "<client-id>|<code>|<stamped>". Without this the stub keys on
# HOST only, so every config in a fixture necessarily gets the same answer — and the suite
# was structurally unable to express the incident that motivated this script ("5 of 7
# configs stale after a dashboard roll"). Measured: dropping the id/secret from the memo
# cache key passed 27/27, while under a credential-aware fixture it turned
# `live: 1 dead: 1` into `live: 2 dead: 0` — a clean bill of health on the exact failure.
if [[ "$_credentialed" == 1 && -n "${MOCK_CREDS:-}" && -f "${MOCK_CREDS}" ]]; then
  _cid=""
  for ((i=1; i<=$#; i++)); do
    [[ "${!i}" == CF-Access-Client-Id:* ]] && _cid="${!i#CF-Access-Client-Id: }"
  done
  _cline=$(grep -F "${_cid}|" "$MOCK_CREDS" 2>/dev/null | head -1)
  if [[ -n "$_cline" ]]; then
    IFS='|' read -r _ _code _stamped <<< "$_cline"
  fi
fi

if [[ "$_credentialed" == 1 ]]; then _mitig="$_r_mitig"; _redir=0
else _mitig=0; _redir="$_c_redir"
fi

if [[ -n "$_hdrfile" ]]; then
  {
    printf 'HTTP/2 %s \r\n' "$_code"
    printf 'server: cloudflare\r\n'
    if [[ "$_stamped" == 1 ]]; then
      printf 'cf-access-domain: %s\r\n' "$_host"
      printf 'cf-access-aud: 0000000000000000000000000000000000000000000000000000000000000000\r\n'
    fi
    [[ "$_mitig" == 1 ]] && printf 'cf-mitigated: challenge\r\n'
    [[ "$_redir" == 1 ]] && printf 'location: https://example.cloudflareaccess.com/cdn-cgi/access/login/%s\r\n' "$_host"
    printf '\r\n'
  } > "$_hdrfile" 2>/dev/null || true
fi

_body="${MOCK_HTTP_BODY:-}"
if [[ -n "$_outfile" ]]; then
  printf '%s' "$_body" > "$_outfile" 2>/dev/null || true
else
  printf '%s' "$_body"
fi
[[ "$_want_code" == 1 ]] && printf '%s' "$_code"
# Transport failure: curl still emits -w, then exits non-zero. Both halves matter.
exit "${MOCK_CURL_EXIT:-0}"
STUB
chmod +x "$STUB_DIR/curl"

# `mktemp` stub. Only fails when a case asks it to, otherwise delegates to the real one.
# Without this the `detector-env` branch is UNREACHABLE from the suite, and mapping a
# local disk failure back onto "the host is unreachable" passed the whole battery.
cat > "$STUB_DIR/mktemp" <<'STUB'
#!/usr/bin/env bash
[[ "${MOCK_MKTEMP_FAIL:-0}" == 1 ]] && exit 1
exec /usr/bin/mktemp "$@"
STUB
chmod +x "$STUB_DIR/mktemp"

# Run the SUT against a fixture world.
#
# Called DIRECTLY, never as `rc=$(run_sut ...)`. Command substitution runs the function in
# a SUBSHELL, so every effect except stdout is discarded — the artifact paths this sets
# would come back empty in the parent and every assertion would grep a nonexistent file
# and "fail" for a reason that has nothing to do with the code under test. (Measured
# here: 0/8, with `grep: : No such file or directory` on every line.) A function that
# both returns a value AND sets caller-visible state cannot be called that way; this one
# sets globals and reports rc through $RC.
#
# Paths are derived from the case label rather than $RANDOM so a failing case's artifacts
# are findable by name after the run.
RC=""
OUT=""
CURL_LOG=""
DOPPLER_LOG=""
run_sut() {
  local label="$1" http_code="$2" secrets_body="$3" configs_body="${4:-prd}" only_arg="${5:-}"
  local cfgs="$TMP/$label.configs" secs="$TMP/$label.secrets"
  OUT="$TMP/$label.out"; CURL_LOG="$TMP/$label.curl"; DOPPLER_LOG="$TMP/$label.doppler"
  : > "$DOPPLER_LOG"
  printf '%s\n' "$configs_body" > "$cfgs" || { echo "FATAL: fixture write failed"; exit 2; }
  printf '%s\n' "$secrets_body" > "$secs" || { echo "FATAL: fixture write failed"; exit 2; }
  : > "$CURL_LOG"
  # shellcheck disable=SC2086
  MOCK_CONFIGS="$cfgs" MOCK_SECRETS="$secs" \
  MOCK_HTTP_CODE="$http_code" MOCK_CURL_LOG="$CURL_LOG" \
  MOCK_HTTP_BODY="${MOCK_HTTP_BODY:-}" \
  MOCK_CONTROL_CODE="${MOCK_CONTROL_CODE:-403}" \
  MOCK_CONTROL_STAMPED="${MOCK_CONTROL_STAMPED:-1}" \
  MOCK_CRED_STAMPED="${MOCK_CRED_STAMPED:-}" \
  MOCK_CURL_EXIT="${MOCK_CURL_EXIT:-0}" \
  MOCK_HOSTS="${MOCK_HOSTS:-}" \
  MOCK_CREDS="${MOCK_CREDS:-}" \
  MOCK_MKTEMP_FAIL="${MOCK_MKTEMP_FAIL:-0}" \
  MOCK_DOPPLER_LOG="$DOPPLER_LOG" \
  APP_DOMAIN_BASE="soleur.ai" \
  PATH="$STUB_DIR:$PATH" \
    bash "$SUT" $only_arg > "$OUT" 2>&1
  RC=$?
}

# Count credentialed vs control probes from the recorded argv. The cache promise ("verify
# each distinct pair once") had no instrument at all before this, which is why both memo
# caches could be dead code through every green run.
# `|| true`, NOT `|| printf '0'`: grep -c PRINTS 0 and EXITS 1 on no match, so the printf
# form concatenates to "00" and every `== "0"` comparison fails. That is the same
# print-and-fail shape as curl's `-w` output that this suite pins in the SUT (T20) —
# reproduced here in the helper written to measure it.
cred_probes()    { grep -c 'CF-Access-Client-Id' "$CURL_LOG" 2>/dev/null || true; }
# CONTROL probes are the ones WITHOUT credentials. The first version of this counted
# `grep -c 'https://'` — every probe of either kind — so it could not have measured what
# its name claimed even if a case had called it. It was also defined and never called.
control_probes() { grep -cv 'CF-Access-Client-Id' "$CURL_LOG" 2>/dev/null || true; }

echo "=== check-cloudflare-token-drift: Access service-token arm ==="
echo ""

ACCESS_FIXTURE="prd|REGISTRY_PUSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|REGISTRY_PUSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}"

# T1 — the regression that motivates the whole change. The key must be ENUMERATED at all.
# Asserted via the curl log rather than the verdict: if enumeration silently misses the
# key, the script reports 0 live / 0 dead and exits 0, which is indistinguishable from a
# healthy fleet by exit code alone. That indistinguishability IS the bug.
echo "T1: REGISTRY_PUSH_ACCESS_TOKEN_* is enumerated (the key the old regex could not match)"
run_sut t1 200 "$ACCESS_FIXTURE"
if grep -qF 'CF-Access-Client-Id' "$CURL_LOG"; then
  pass "the Access token was actually probed (old enumeration regex could not reach it)"
else
  fail "REGISTRY_PUSH_ACCESS_TOKEN_* was never probed — enumeration missed it (curl log empty)"
fi

# T2 — LIVE verdict: a 200 from the protected hostname means Access accepted the pair.
echo "T2: 200 from the Access-protected hostname -> LIVE, exit 0"
run_sut t2 200 "$ACCESS_FIXTURE"
if [[ "$RC" == "0" ]] && grep -qE 'live entries: [1-9]' "$OUT" && grep -qE 'dead entries: 0' "$OUT"; then
  pass "200 -> LIVE, exit 0"
else
  fail "200 should be LIVE with exit 0 (rc=$RC): $(grep -E 'live entries' "$OUT" || true)"
fi

# T3 — DEAD verdict: 403 is Access refusing the pair, which is the stale-rotation shape.
echo "T3: 403 from the Access-protected hostname -> DEAD, exit 1"
MOCK_CRED_STAMPED=1 run_sut t3 403 "$ACCESS_FIXTURE"
if [[ "$RC" == "1" ]] && grep -qE 'dead entries: [1-9]' "$OUT" && grep -qF 'REGISTRY_PUSH_ACCESS_TOKEN' "$OUT"; then
  pass "403 -> DEAD, exit 1, and the report names the key"
else
  fail "403 should be DEAD with exit 1 and name the key (rc=$RC)"
fi

# T4 — the pair is presented as Access headers, NOT as a Bearer API token. The original
# verify_value() used /user/tokens/verify with `Authorization: Bearer`, which is the
# API-token endpoint and cannot say anything true about a client-id/secret pair. Pinning
# the request SHAPE is what stops a future edit from quietly routing this family back
# through the wrong endpoint while the verdicts still look plausible.
echo "T4: the pair is presented as CF-Access-Client-Id/-Secret against the protected host"
run_sut t4 200 "$ACCESS_FIXTURE"
_t4=1
grep -qF "CF-Access-Client-Id: ${FIX_ID}" "$CURL_LOG" || _t4=0
grep -qF "CF-Access-Client-Secret: ${FIX_SECRET}" "$CURL_LOG" || _t4=0
grep -qF 'https://registry.soleur.ai/' "$CURL_LOG" || _t4=0
grep -qF 'user/tokens/verify' "$CURL_LOG" && _t4=0
if [[ "$_t4" == "1" ]]; then
  pass "presented as Access headers to the protected hostname; the Bearer API-token endpoint is not used for this family"
else
  fail "must present CF-Access-Client-Id/-Secret to https://registry.soleur.ai/ and NOT hit user/tokens/verify"
fi

# T5 — fail CLOSED on a non-200/403 response. A timeout or 5xx means this script did not
# LEARN the token is good, and "did not learn" must never render as LIVE. Every
# silent-green bug in this area has that same shape.
# T5 — fail-closed on a probe that measured nothing. The ASSERTION CHANGED with the
# Access-stamp rewrite and the change is the point: this used to require `dead entries:
# >= 1`, i.e. an unreachable host rendered the credential STALE. That is a cause nothing
# measured, and the DEAD section's remedy is "set the live value on the prd ROOT config"
# — so a DNS blip instructed the operator to overwrite a healthy credential across every
# config that inherits it. Fail-closed is preserved (exit 1, never LIVE); what changed is
# that it now fails closed to UNVERIFIABLE, which carries a "do NOT rotate" remedy.
echo "T5: a probe that got no answer is NOT live and NOT stale (fail closed, no false cause)"
MOCK_CURL_EXIT=7 run_sut t5 000 "$ACCESS_FIXTURE"
_t5=1
[[ "$RC" == "1" ]] || _t5=0
grep -qE 'live entries: 0' "$OUT" || _t5=0
grep -qE 'unverifiable: [1-9]' "$OUT" || _t5=0
grep -q 'STALE' "$OUT" && _t5=0
if [[ "$_t5" == "1" ]]; then
  pass "unreachable -> UNVERIFIABLE, exit 1, and never under the STALE heading"
else
  fail "an unreachable probe must fail closed WITHOUT claiming the credential is stale — the STALE remedy overwrites the ROOT config every branch inherits (rc=$RC)"
fi

# T6 — a half-propagated rotation. One half present authenticates as nothing, and is a
# distinct, worse state than the token being absent; it must be reported, not skipped.
echo "T6: only one half of the pair present -> reported DEAD"
run_sut t6 200 "prd|REGISTRY_PUSH_ACCESS_TOKEN_ID|${FIX_ID}"
if [[ "$RC" == "1" ]] && grep -qF 'only one half present' "$OUT"; then
  pass "half-present pair reported explicitly"
else
  fail "a pair with only one half present must be reported DEAD (rc=$RC)"
fi

# T7 — an enumerated token with no hostname mapping is UNVERIFIABLE, not LIVE. This is
# the fail-closed property for the script's own coverage: a newly-added Access token
# family is surfaced as a gap rather than silently counted healthy, which is exactly the
# failure mode being fixed, one level up.
echo "T7: an enumerated token with no hostname mapping fails closed, not silently LIVE"
run_sut t7 200 "prd|SOMETHING_NEW_ACCESS_TOKEN_ID|${FIX_ID}
prd|SOMETHING_NEW_ACCESS_TOKEN_SECRET|${FIX_SECRET}"
_t7=1
[[ "$RC" == "1" ]] || _t7=0
grep -qF 'UNVERIFIABLE' "$OUT" || _t7=0
grep -qF 'add a hostname mapping' "$OUT" || _t7=0
# The half with teeth: an unverifiable key must NOT be reported as a stale credential.
# Doing so sends an operator to rotate a healthy token — a different false claim, and the
# same name-an-unmeasured-cause defect this PR exists to drain. Measured before the fix:
# the row printed under "STALE — these configs hold a token value Cloudflare no longer
# accepts" with "set the live value on the prd ROOT config" as its remedy.
grep -qE 'STALE.*\n?.*SOMETHING_NEW' "$OUT" && _t7=0
awk '/^STALE/{s=1} /^UNVERIFIABLE/{s=0} s && /SOMETHING_NEW/{found=1} END{exit !found}' "$OUT" && _t7=0
if [[ "$_t7" == "1" ]]; then
  pass "unmappable token reported as UNVERIFIABLE with a detector-side remedy, never as STALE"
else
  fail "an unmappable Access token must exit 1, print under UNVERIFIABLE, and never appear under STALE (rc=$RC)"
fi

# T9 — the cardinality case. Every fixture above holds ONE config, which cannot observe
# the requirement this script exists for ("5 of 7 configs stale after a dashboard roll").
# Measured: with only single-config fixtures, rewriting any of the three `for cfg in
# "${CONFIGS[@]}"` loops to `"${CONFIGS[0]}"` left the suite 8/8 green.
echo "T9: a token stale in ONE config of TWO is found, and the report names that config"
MOCK_CRED_STAMPED=1 run_sut t9 403 "prd|REGISTRY_PUSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|REGISTRY_PUSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd_terraform|REGISTRY_PUSH_ACCESS_TOKEN_ID|${FIX_ID}
prd_terraform|REGISTRY_PUSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}" $'prd\nprd_terraform'
if [[ "$RC" == "1" ]] && grep -qE 'configs scanned: 2' "$OUT" && grep -qE 'dead entries: 2' "$OUT"; then
  pass "both configs scanned and both dead entries reported (single-config loops would report 1)"
else
  fail "a two-config fleet must be scanned in full (rc=$RC): $(grep -E 'configs scanned|dead entries' "$OUT" | tr '\n' ' ')"
fi

# T10 — the non-Cloudflare lookalike. This is the live defect: the enumeration matched
# X_ACCESS_TOKEN_SECRET (an X/Twitter OAuth secret in 11 of 13 real configs), derived base
# X_ACCESS_TOKEN, and rendered a FABRICATED X_ACCESS_TOKEN_ID/_SECRET row — a credential
# that has never existed — into a twice-daily ops email. The pair requirement is what
# discriminates: no `_ID` half anywhere in the fleet means it is not an Access pair.
echo "T10: a *_ACCESS_TOKEN_SECRET with no _ID half is NOT treated as a Cloudflare pair"
run_sut t10 200 "prd|X_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd|REGISTRY_PUSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|REGISTRY_PUSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}"
if [[ "$RC" == "0" ]] && ! grep -qF 'X_ACCESS_TOKEN' "$OUT"; then
  pass "secret-only vendor key ignored; no fabricated _ID/_SECRET row, exit 0"
else
  fail "a *_ACCESS_TOKEN_SECRET with no _ID must be ignored, not reported (rc=$RC): $(grep -F 'X_ACCESS_TOKEN' "$OUT" | head -1)"
fi

# T11 — `--only` is the release preflight's only argument and had zero coverage.
# A filter matching nothing must NOT exit 0: the caller prints "verified live" on 0, so a
# renamed key would produce a clean bill of health for a question never asked. This suite's
# own header calls that indistinguishability "the bug".
echo "T11: --only matching no key is a coverage gap (exit 2), not a clean bill of health"
run_sut t11 200 "prd|REGISTRY_PUSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|REGISTRY_PUSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}" prd "--only NOSUCHFAMILY"
if [[ "$RC" == "2" ]] && grep -qF 'COVERAGE GAP' "$OUT"; then
  pass "--only matching nothing exits 2 and says nothing was checked"
else
  fail "--only with no matches must exit 2, not report clean (rc=$RC)"
fi

# T12 — and the positive direction: --only must actually scope, not silently no-op.
echo "T12: --only scopes the scan to the named family"
run_sut t12 200 "prd|REGISTRY_PUSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|REGISTRY_PUSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd|CF_API_TOKEN_DNS_EDIT|synthetic-not-real" prd "--only REGISTRY_PUSH_ACCESS_TOKEN"
if grep -qF 'CF-Access-Client-Id' "$CURL_LOG" && ! grep -qF 'user/tokens/verify' "$CURL_LOG"; then
  pass "--only probed the Access pair and did NOT probe the excluded API token"
else
  fail "--only must scope the scan: expected the Access probe and no API-token probe"
fi

# T8 — the pre-existing API-token family still works. The Access arm is additive; a
# change that fixed one family by breaking the other would be a net loss.
echo "T8: the CF_API_TOKEN* family is unaffected (Bearer verify still used for it)"
run_sut t8 200 "prd|CF_API_TOKEN_DNS_EDIT|synthetic-api-token-value-not-real"
if grep -qF 'user/tokens/verify' "$CURL_LOG" && grep -qF 'Authorization: Bearer' "$CURL_LOG"; then
  pass "API tokens still verified as Bearer against /user/tokens/verify"
else
  fail "the CF_API_TOKEN* arm must still use the Bearer /user/tokens/verify endpoint"
fi

# T13 — the API-token family's VERDICT, not just its request shape. T8 asserts the Bearer
# endpoint is used; nothing asserted what the answer means. With the old stub returning the
# status code as the response BODY, the arm's json.load() raised on every call and always
# printed DEAD — so a mutation hardcoding LIVE for every Cloudflare API token was
# invisible, in the family the script already claimed to cover.
echo "T13: CF_API_TOKEN* verdict follows Cloudflare's answer (success true/false)"
MOCK_HTTP_BODY='{"success":true}' run_sut t13a 200 "prd|CF_API_TOKEN_DNS_EDIT|synthetic-not-real"
_t13=1
[[ "$RC" == "0" ]] || _t13=0
grep -qE 'live entries: 1' "$OUT" || _t13=0
MOCK_HTTP_BODY='{"success":false}' run_sut t13b 200 "prd|CF_API_TOKEN_DNS_EDIT|synthetic-not-real"
[[ "$RC" == "1" ]] || _t13=0
grep -qE 'dead entries: 1' "$OUT" || _t13=0
if [[ "$_t13" == "1" ]]; then
  pass "success:true -> LIVE exit 0; success:false -> DEAD exit 1"
else
  fail "the API-token verdict must track Cloudflare's success field in BOTH directions"
fi

# T14 — --json-file exists so ONE scan can serve two consumers: the run log needs the
# human report (which remediation applies), the caller needs counts it can branch an
# operator email on. The caller branches three ways on this file, and the wrong branch
# sends an operator to rotate a healthy credential — so the file's presence, its
# parseability, and the coexistence with stdout are all load-bearing.
echo "T14: --json-file writes the verdict AND still prints the human report"
JF="$TMP/t14.json"
MOCK_CRED_STAMPED=1 run_sut t14 403 "$ACCESS_FIXTURE" prd "--json-file $JF"
# The human report is what distinguishes --json-file from --json. Without this assertion,
# an implementation that silently behaved like --json (JSON on stdout, no report) would
# pass every other check here.
if grep -qF 'Cloudflare token drift check' "$OUT"; then
  pass "--json-file still prints the human report to stdout"
else
  fail "--json-file must NOT suppress the human report (that is what --json is for)"
fi
if [[ -s "$JF" ]] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d["dead"] >= 1 else 1)' "$JF"; then
  pass "--json-file wrote a parseable verdict carrying the DEAD count"
else
  fail "--json-file must write parseable JSON with the dead count (got: $(head -c 120 "$JF" 2>/dev/null || echo '<no file>'))"
fi
# Fail-closed on an unwritable path. A missing verdict file makes the caller take its
# could-not-determine arm, so a silent write failure would report a wrong cause rather
# than no cause — the defect class this script exists to prevent.
echo "T14b: --json-file on an unwritable path exits 2 rather than continuing silently"
run_sut t14b 200 "$ACCESS_FIXTURE" prd "--json-file $TMP/no-such-dir/x.json"
if [[ "$RC" == "2" ]]; then
  pass "unwritable --json-file path exits 2"
else
  fail "unwritable --json-file path must exit 2, got rc=$RC"
fi

# ---------------------------------------------------------------------------
# T15-T24 — the ACCESS-STAMP arm (replaces the status-code arm removed with #7127).
#
# What is being pinned: the verdict comes from whether Cloudflare Access's own denial
# stamp (cf-access-aud / cf-access-domain) is still on the response once credentials are
# attached — NOT from the status code.
#
# The predecessor graded 5xx as LIVE on the theory that an admitted request reaches
# cloudflared, which then fails to speak HTTP to sshd. MEASURED 2026-08-01 against
# registry.soleur.ai with a live credential: the admitted response is HTTP 200, zero-byte
# body, no cf-access-* header. tunnel.tf records that ssh:// and tcp:// are the same
# raw-TCP service type, so ssh.<base> answers the same way — the 5xx arm could never fire
# and 200 fell to the catch-all, trading DEAD-forever for UNVERIFIABLE-forever. T15 is
# that case, and it is the one the previous suite had no test for.
# ---------------------------------------------------------------------------
CI_SSH_FIXTURE="prd|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}"

echo "T15: admitted probe answers 200 with NO Access stamp -> LIVE"
run_sut t15 200 "$CI_SSH_FIXTURE"
if [[ "$RC" == "0" ]] && grep -qE 'live entries: 1' "$OUT" && grep -qE 'dead entries: 0' "$OUT"; then
  pass "an empty 200 with the stamp gone grades LIVE — the measured admitted shape"
else
  fail "the MEASURED admitted response (200, no cf-access-*) must grade LIVE; a rule that cannot accept it reports a healthy token unverifiable forever (rc=$RC)"
fi

echo "T16: credentials still met Access's denial page -> DEAD"
MOCK_CRED_STAMPED=1 run_sut t16 403 "$CI_SSH_FIXTURE"
if [[ "$RC" == "1" ]] && grep -qE 'dead entries: 1' "$OUT"; then
  pass "a stamped response with credentials attached grades DEAD"
else
  fail "a stamped 403 WITH credentials means Access refused them — must stay DEAD (rc=$RC)"
fi

echo "T17: an unstamped 403 (WAF/bot-fight in FRONT of Access) is NOT a stale credential"
MOCK_CRED_STAMPED=0 run_sut t17 403 "$CI_SSH_FIXTURE"
if [[ "$RC" != "0" ]] && ! grep -qE 'dead entries: 1' "$OUT"; then
  pass "a 403 without the Access stamp does not render as a stale credential"
else
  fail "an unstamped 403 comes from in FRONT of Access (WAF, bot-fight, IP rule); grading it DEAD sends the operator to overwrite a healthy secret (rc=$RC)"
fi

echo "T18: control probe unrefused -> gate-absent, never LIVE"
MOCK_CONTROL_STAMPED=0 MOCK_CONTROL_CODE=200 run_sut t18 200 "$CI_SSH_FIXTURE"
_t18=1
grep -qE 'live entries: 0' "$OUT" || _t18=0
grep -q 'gate-absent' "$OUT" || _t18=0
[[ "$RC" == "1" ]] || _t18=0
if [[ "$_t18" == "1" ]]; then
  pass "an ungated host renders gate-absent and never certifies the credential"
else
  fail "if an UNCREDENTIALED request is not refused, nothing is gating the host — grading the credential LIVE there is a false-LIVE on the one verdict that emails nobody (rc=$RC)"
fi

# The anchor here is `access_hostname_for`, NOT the sentence "add a hostname mapping":
# the report wraps that phrase across two echo lines, so a grep for it matches nothing on
# ANY output and the assertion passed for the wrong reason. Caught by mutation M8, which
# forced the no-probe-configured footer to print unconditionally and still left the suite
# 26/26. Anchor on a token that survives line-wrapping.
echo "T19: gate-absent names the GATE, not a hostname mapping"
MOCK_CONTROL_STAMPED=0 MOCK_CONTROL_CODE=200 run_sut t19 200 "$CI_SSH_FIXTURE"
if grep -q 'gate-absent' "$OUT" && ! grep -q 'access_hostname_for' "$OUT"; then
  pass "the gate-absent remedy does not tell the operator to add a mapping that exists"
else
  fail "gate-absent must not print the no-probe-configured remedy — CI_SSH_ACCESS_TOKEN already HAS a mapping, so 'add a hostname mapping' is unperformable and the state never clears"
fi

echo "T20: a transport failure renders UNVERIFIABLE and never fabricates a status"
MOCK_CURL_EXIT=7 run_sut t20 000 "$CI_SSH_FIXTURE"
_t20=1
grep -qE 'live entries: 0' "$OUT" || _t20=0
grep -qE 'unverifiable: 1' "$OUT" || _t20=0
grep -q '000000' "$OUT" && _t20=0
[[ "$RC" == "1" ]] || _t20=0
if [[ "$_t20" == "1" ]]; then
  pass "curl exiting non-zero yields UNVERIFIABLE with no concatenated status"
else
  fail "real curl prints its -w output AND exits non-zero; \`\$(curl ... || printf '000')\` concatenates to 000000/200000, and 'did not learn' must never read as LIVE (rc=$RC)"
fi

echo "T21: a transport failure must NOT print the mapping remedy either"
MOCK_CURL_EXIT=7 run_sut t21 000 "$CI_SSH_FIXTURE"
if ! grep -q 'add a hostname mapping' "$OUT" && grep -qE 'host-unreachable|probe-failed' "$OUT"; then
  pass "an unreachable host is reported as unreachable, not as a detector coverage gap"
else
  fail "a DNS/TLS blip must not email the operator 'add a hostname mapping to access_hostname_for()' for a key that has one — that is naming a cause nothing measured"
fi

echo "T22: the pair verdict is cached — N configs holding one pair cost ONE credentialed probe"
run_sut t22 200 "prd|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd_a|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd_a|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd_b|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd_b|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}" "prd
prd_a
prd_b"
_n=$(cred_probes)
if [[ "$_n" == "1" ]]; then
  pass "three configs, one identical pair, one credentialed probe"
else
  fail "expected 1 credentialed probe for 3 configs holding identical bytes, got $_n — the memo cache is dead (command substitution runs it in a subshell), so one transient blip grades the SAME BYTES live in two configs and dead in the third, and the DEAD remedy overwrites the ROOT config all three inherit"
fi

echo "T23: per-base dispatch — one admitting host and one rejecting host in ONE run"
printf 'ssh.soleur.ai|403|1|200|0\nregistry.soleur.ai|403|1|403|1\n' > "$TMP/t23.hosts"
MOCK_HOSTS="$TMP/t23.hosts" run_sut t23 200 "prd|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd|REGISTRY_PUSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|REGISTRY_PUSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}"
if grep -qE 'live entries: 1' "$OUT" && grep -qE 'dead entries: 1' "$OUT"; then
  pass "each base is graded against its OWN host's answer"
else
  fail "a fixture carrying two bases must grade each against its own host; every previous fixture held one base, so a sticky/first-base-wins dispatch was invisible (rc=$RC)"
fi

# Both halves are NAMED but hold no value — the shape a Doppler token scoped to read
# secret names but not values produces, and the shape of a read that fails mid-scan. Every
# `doppler secrets get` returns empty, every loop `continue`s, and nothing is measured.
echo "T24: a run that concludes NOTHING is not a clean fleet"
run_sut t24 200 "prd|CI_SSH_ACCESS_TOKEN_ID|
prd|CI_SSH_ACCESS_TOKEN_SECRET|"
_t24=1
[[ "$RC" == "2" ]] || _t24=0
grep -q 'PROBED ZERO' "$OUT" || _t24=0
if [[ "$_t24" == "1" ]]; then
  pass "zero probes exits 2 rather than reporting a clean fleet"
else
  fail "a Doppler token that reads NAMES but not VALUES makes every read empty and every loop continue; falling through to exit 0 reports 'clean' with nothing measured and the alarm goes dark (rc=$RC)"
fi

# T25 — the enumeration is read ONCE per config, and its exit status is checked.
#
# The file's own comment promised "ONE --only-names read per config", and the code did two:
# the second was `doppler ... 2>/dev/null || true`, the exact shape the comment three lines
# below it condemns as "how a scope-denied token renders as a clean fleet". Measured on the
# unfixed code with the second read failing: a genuinely stale credential reported
# `live entries: 1  dead entries: 0`, exit 0.
#
# Nothing pinned it — mutation M10 restored the second read and the suite stayed 26/26 —
# because no test had ever counted a Doppler call. This is that instrument.
echo "T25: secret NAMES are enumerated once per config, not twice"
run_sut t25 200 "prd|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd_a|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd_a|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}" "prd
prd_a"
_n=$(grep -c -- '--only-names' "$DOPPLER_LOG" 2>/dev/null || printf '0')
if [[ "$_n" == "2" ]]; then
  pass "two configs, two --only-names reads (one each)"
else
  fail "expected 2 --only-names reads for 2 configs, got $_n — a second read is a second chance to return empty silently, and an empty enumeration renders as a clean fleet"
fi

# ---------------------------------------------------------------------------
# T26-T36 — the mutants that survived the first battery. Each case below exists
# because a specific edit passed 27/27, and the pass-count is recorded with it.
# ---------------------------------------------------------------------------

echo "T26: a STAMPED 200 is not admission — the stamp decides, not the status"
MOCK_CRED_STAMPED=1 run_sut t26 200 "$CI_SSH_FIXTURE"
_t26=1
grep -qE 'live entries: 0' "$OUT" || _t26=0
grep -q 'stamped-non-refusal' "$OUT" || _t26=0
[[ "$RC" == "1" ]] || _t26=0
if [[ "$_t26" == "1" ]]; then
  pass "a stamped 200 does not grade LIVE, and is not called a rejection either"
else
  fail "this is THE case that separates a stamp rule from a status rule; without it, inserting \`elif [[ \$PROBE_CODE == 200 ]]; then LIVE\` ahead of the stamp test — restoring the instrument this PR removes — passed 27/27 (rc=$RC)"
fi

echo "T27: an unstamped 5xx is NOT certified — LIVE requires positive 2xx success"
run_sut t27 502 "$CI_SSH_FIXTURE"
_t27=1
grep -qE 'live entries: 0' "$OUT" || _t27=0
grep -q 'unexpected-status' "$OUT" || _t27=0
[[ "$RC" == "1" ]] || _t27=0
if [[ "$_t27" == "1" ]]; then
  pass "an unstamped 502 renders unexpected-status, never LIVE"
else
  fail "the first revision made LIVE the catch-all \`else\` and narrowed only 401/403 out of it — measured, a rate-limit 429, a challenge 503, an identity 302 and a tunnel 530 ALL graded LIVE at rc=0, on the one verdict that emails nobody (rc=$RC)"
fi

echo "T28: an unstamped 401 is a refusal, not admission"
run_sut t28 401 "$CI_SSH_FIXTURE"
if [[ "$RC" == "1" ]] && ! grep -qE 'live entries: 1' "$OUT"; then
  pass "401 unstamped does not certify the credential"
else
  fail "narrowing the refusal set from {401,403} to {403} left an unstamped 401 grading LIVE at 27/27 (rc=$RC)"
fi

echo "T29: a Cloudflare-mitigated answer (rate limit / challenge) is a refusal"
printf 'ssh.soleur.ai|403|1|429|0|1\n' > "$TMP/t29.hosts"
MOCK_HOSTS="$TMP/t29.hosts" run_sut t29 429 "$CI_SSH_FIXTURE"
_t29=1
grep -qE 'live entries: 0' "$OUT" || _t29=0
grep -q 'refused-unstamped' "$OUT" || _t29=0
if [[ "$_t29" == "1" ]]; then
  pass "cf-mitigated is read as Cloudflare's own block, not as admission"
else
  fail "a 429 rate-limit carries no cf-access-* stamp; without reading cf-mitigated it is indistinguishable from an admitted response and grades LIVE (rc=$RC)"
fi

echo "T30: refused-unstamped is labelled as ITSELF, not as an unreachable host"
printf 'ssh.soleur.ai|403|1|429|0|1\n' > "$TMP/t30.hosts"
MOCK_HOSTS="$TMP/t30.hosts" run_sut t30 429 "$CI_SSH_FIXTURE"
if grep -q '\[refused-unstamped\]' "$OUT" && ! grep -q 'host-unreachable' "$OUT"; then
  pass "the cause label names the WAF/challenge case specifically"
else
  fail "relabelling refused-unstamped to host-unreachable passed 27/27 — the two have opposite remedies ('check your WAF' vs 're-run, nothing was measured') and the workflow branches its email on this exact token"
fi

echo "T31: a credentialed probe that got no answer is UNVERIFIABLE, never LIVE"
printf 'ssh.soleur.ai|403|1|000|0|0\n' > "$TMP/t31.hosts"
MOCK_HOSTS="$TMP/t31.hosts" run_sut t31 000 "$CI_SSH_FIXTURE"
_t31=1
grep -qE 'live entries: 0' "$OUT" || _t31=0
grep -q 'probe-failed' "$OUT" || _t31=0
[[ "$RC" == "1" ]] || _t31=0
if [[ "$_t31" == "1" ]]; then
  pass "control succeeds, credentialed probe fails -> probe-failed"
else
  fail "this branch was UNREACHABLE in the suite: every 000 case failed the CONTROL probe too, so the credentialed arm was never entered and \`probe-failed -> LIVE\` passed 27/27 (rc=$RC)"
fi

echo "T32: an identity-policy redirect to the IdP is a GATE, not a missing gate"
printf 'ssh.soleur.ai|302|0|200|0|0|1\n' > "$TMP/t32.hosts"
MOCK_HOSTS="$TMP/t32.hosts" run_sut t32 200 "$CI_SSH_FIXTURE"
if grep -qE 'live entries: 1' "$OUT" && [[ "$RC" == "0" ]]; then
  pass "a 302 to the Access login page is recognised as Access answering, and the credential is then graded"
else
  fail "an Access app with an identity policy 302s anonymous requests and carries no cf-access-* header; calling that 'nothing is gating this host' puts a fabricated SECURITY claim in an operator email (rc=$RC)"
fi

echo "T33: gate-absent requires an anonymous request to actually SUCCEED"
printf 'ssh.soleur.ai|530|0|200|0|0|0\n' > "$TMP/t33.hosts"
MOCK_HOSTS="$TMP/t33.hosts" run_sut t33 200 "$CI_SSH_FIXTURE"
if grep -q 'gate-indeterminate' "$OUT" && ! grep -q 'gate-absent' "$OUT"; then
  pass "a 530 tunnel outage is not reported as a removed Access gate"
else
  fail "only a 2xx to an anonymous request is evidence nothing refused it; a 530/429/302 unstamped control graded gate-absent and emailed 'the host may be exposed' (rc=$RC)"
fi

echo "T34: a stale pair and a rotated pair in TWO configs are graded separately"
printf '%s|200|0\n%s|403|1\n' "$FIX_ID" "${FIX_ID%.access}.stale" > "$TMP/t34.creds"
MOCK_CREDS="$TMP/t34.creds" run_sut t34 200 "prd|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd_terraform|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID%.access}.stale
prd_terraform|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}" "prd
prd_terraform"
_t34=1
grep -qE 'live entries: 1' "$OUT" || _t34=0
grep -qE 'dead entries: 1' "$OUT" || _t34=0
grep -q 'prd_terraform' "$OUT" || _t34=0
if [[ "$_t34" == "1" ]]; then
  pass "one rotated, one stale -> 1 live 1 dead, and the report names the stale config"
else
  fail "this is the incident the script exists to catch ('5 of 7 configs stale after a dashboard roll'). Dropping the credential from the memo cache key passed 27/27 because EVERY fixture wrote identical bytes to every config; under this fixture it reports 'live: 2 dead: 0' — a clean bill of health on the real failure (rc=$RC)"
fi

echo "T35: the CONTROL probe is cached per host, not repeated per credential"
printf '%s|200|0\n%s|403|1\n' "$FIX_ID" "${FIX_ID%.access}.stale" > "$TMP/t35.creds"
MOCK_CREDS="$TMP/t35.creds" run_sut t35 200 "prd|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}
prd_terraform|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID%.access}.stale
prd_terraform|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}" "prd
prd_terraform"
_c=$(control_probes); _r=$(cred_probes)
if [[ "$_c" == "1" && "$_r" == "2" ]]; then
  pass "two distinct credentials on one host: 1 control probe, 2 credentialed"
else
  fail "expected 1 control + 2 credentialed, got control=$_c cred=$_r — the control probe doubles the request volume against the Access edge, which is what makes a rate-limit response reachable in the first place"
fi

echo "T36: the API-token memo cache is real too"
run_sut t36 200 "prd|CF_API_TOKEN_X|tokenvalue
prd_a|CF_API_TOKEN_X|tokenvalue
prd_b|CF_API_TOKEN_X|tokenvalue" "prd
prd_a
prd_b"
_n=$(grep -c 'tokens/verify' "$CURL_LOG" 2>/dev/null || printf '0')
if [[ "$_n" == "1" ]]; then
  pass "three configs, one identical API token, one verify call"
else
  fail "expected 1 /user/tokens/verify call for 3 configs holding one value, got $_n — the SUT comment says the subshell bug hit 'every memoised helper in this file', but only the Access cache had an instrument, so neutering this one passed 27/27"
fi

echo "T37: the probe does NOT follow redirects"
run_sut t37 200 "$CI_SSH_FIXTURE"
if ! grep -qE '(^| )(-L|--location)( |$)' "$CURL_LOG"; then
  pass "no -L: header blocks cannot come from a different response than %{http_code}"
else
  fail "curl APPENDS each response's headers into one -D file, so under -L the stamp grep (an OR over the whole file) can see an early block's stamp while %{http_code} reports the final response — an admitted-after-redirect would grade DEAD, the destructive direction"
fi

echo "T38: a STAMPED 401 is a refusal and must stay DEAD"
MOCK_CRED_STAMPED=1 run_sut t38 401 "$CI_SSH_FIXTURE"
if [[ "$RC" == "1" ]] && grep -qE 'dead entries: 1' "$OUT"; then
  pass "401 with the Access stamp grades DEAD, same as 403"
else
  fail "narrowing the DEAD refusal set from {401,403} to {403} passed 39/39 — a stamped 401 is Access refusing the credential and must not be downgraded to 'could not verify' (rc=$RC)"
fi

echo "T39: the report states how many network probes were actually made"
run_sut t39 200 "$CI_SSH_FIXTURE"
if grep -qE 'network probes: [1-9]' "$OUT"; then
  pass "the summary line carries a non-zero probe count"
else
  fail "deleting the probe counter's increment passed 39/39: the one number separating 'measured something' from 'concluded from Doppler reads alone' was computed and never reported"
fi

echo "T40: a local mktemp failure is NOT reported as an unreachable host"
MOCK_MKTEMP_FAIL=1 run_sut t40 200 "$CI_SSH_FIXTURE"
_t40=1
grep -q 'detector-env' "$OUT" || _t40=0
grep -q 'host-unreachable' "$OUT" && _t40=0
[[ "$(cred_probes)" == "0" ]] || _t40=0
if [[ "$_t40" == "1" ]]; then
  pass "a full/read-only TMPDIR renders detector-env, with zero requests sent"
else
  fail "mapping a local disk fault onto 'the host got no answer (timeout / DNS / TLS)' sends the operator to investigate Cloudflare while the runner disk is full — and zero requests were sent (rc=$RC)"
fi

# ===========================================================================
# W1-W9 — CONSUMER WIRING (#7095).
#
# The detector above is only half the story. During the 2026-07-29 outage it produced the
# right answer three times over three days — naming the credential, the symptom, and the
# remedy — and production stayed down, because nothing CONSUMED the verdict. The gap was
# never detection; it was that the verdict blocked nothing and reached no one.
#
# These cases pin the wiring, not the detector: the gate that must fail the SSH bridge on a
# dead credential, and the escalation that must reach a human. They are static assertions
# over `.github/**` because that is where the wiring lives; there is no runtime seam to
# drive without dispatching a real workflow against production.
#
# ANCHORING DISCIPLINE (cq-assert-anchor-not-bare-token): every grep below anchors on a
# construct a COMMENT cannot produce — a `uses:` key, a `-replace=` flag, an `if:` guard —
# never on a bare word that the surrounding prose also names. These files are dense with
# explanatory comments that mention every token in play, so a bare-token grep here is
# guaranteed to false-pass.
# ---------------------------------------------------------------------------
GH_DIR="$REPO_ROOT/.github"
BRIDGE_ACTION="$GH_DIR/actions/cf-tunnel-ssh-bridge/action.yml"
DRIFT_WF="$GH_DIR/workflows/scheduled-terraform-drift.yml"
INFRA_WF="$GH_DIR/workflows/apply-web-platform-infra.yml"

# Fixture-precondition self-check. If a path moves, every assertion below would report a
# clean PASS on a file that does not exist — the exact vacuity shape this suite exists to
# prevent. Fail as a FIXTURE error, loudly, rather than as a silent green.
for _f in "$BRIDGE_ACTION" "$DRIFT_WF" "$INFRA_WF"; do
  [[ -f "$_f" ]] || { echo "FATAL: fixture precondition failed — $_f does not exist" >&2; exit 2; }
done

echo "W1: the bridge's liveness gate is defined exactly once, inside the shared composite"
# AC5d. Anchored at COMMAND POSITION (`^\s*bash `), not on the substring. The first
# version grepped the bare invocation, which the header comment describing the gate also
# satisfies — so a doc-only edit reddened it and a code-only deletion did not.
W1_N=$(grep -Ec '^\s*bash scripts/check-cloudflare-token-drift\.sh --only CI_SSH_ACCESS_TOKEN' "$BRIDGE_ACTION" 2>/dev/null || true)
if [[ "$W1_N" == "1" ]]; then
  pass "one definition in the composite — six callers inherit it"
else
  fail "expected exactly 1 scoped invocation at command position in the composite, found $W1_N (0 = gate absent or line-wrapped out of grep's reach; >1 = redundant)"
fi

echo "W2: the scoped check is not duplicated per bridge caller"
# There are exactly two legitimate call sites repo-wide and they are different consumers:
#   1. the composite    — gates the SSH bridge before any terraform destroy
#   2. the replace arm  — the AC10 halt gate, asserting a freshly minted credential is
#                         admitted BEFORE the operator is told the re-mint worked
# A third is per-caller duplication, which R2 rejected.
W2_TOTAL=$(grep -rEc '^\s*bash scripts/check-cloudflare-token-drift\.sh --only CI_SSH_ACCESS_TOKEN' "$GH_DIR" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
W2_IN_INFRA=$(grep -Ec '^\s*bash scripts/check-cloudflare-token-drift\.sh --only CI_SSH_ACCESS_TOKEN' "$INFRA_WF" 2>/dev/null || true)
if [[ "$W2_TOTAL" == "2" && "$W2_IN_INFRA" == "1" ]]; then
  pass "two call sites: the shared composite gate + the re-mint halt gate"
else
  fail "expected exactly 2 scoped call sites across .github/ (composite + re-mint halt gate), found $W2_TOTAL with $W2_IN_INFRA in apply-web-platform-infra.yml — a third means a caller re-implemented the bridge gate"
fi

# W3-W5 anchor on `echo "::error::<enum>` — an EMISSION, which a comment cannot produce.
# MEASURED: the previous bare-token form (`grep -qE 'ci_ssh_access_denied'`) was satisfied
# by this action's own header comment, which lists all three enums. Deleting the entire
# gate step left the suite fully green. That is the exact class this file's preamble
# claims to avoid, committed by the assertions immediately below it.
echo "W3: a DEAD verdict fails the bridge with the terminal reason ci_ssh_access_denied"
if grep -qE '^\s*echo "::error::ci_ssh_access_denied' "$BRIDGE_ACTION"; then
  pass "dead credential emits a named terminal reason"
else
  fail "the gate must EMIT ci_ssh_access_denied (echo \"::error::…\") — a header comment naming the enum is not the gate"
fi

echo "W4: DEAD and UNVERIFIABLE do not collapse into one reason"
# The detector exits 1 for BOTH "Cloudflare rejected this" and "nothing answered". Their
# remedies are opposite — #7127 exists because conflating them sends an operator to
# overwrite a healthy secret. Both consumers must branch on the structured verdict.
W4_OK=1
for _f in "$BRIDGE_ACTION" "$INFRA_WF"; do
  grep -qE '^\s*echo "::error::ci_ssh_liveness_unverifiable' "$_f" || W4_OK=0
  grep -qE '^\s*bash scripts/check-cloudflare-token-drift\.sh --only CI_SSH_ACCESS_TOKEN --json-file' "$_f" || W4_OK=0
done
if [[ "$W4_OK" == "1" ]]; then
  pass "both consumers branch on --json-file; unverifiable gets its own reason"
else
  fail "EVERY consumer must branch on the JSON verdict (dead vs unverifiable), not the bare exit code — exit 1 covers both. Missing in the composite and/or the re-mint halt gate."
fi

echo "W5: an unmeasured scan cannot be reported as clean"
# The detector reaches exit 0 with live=dead=unverifiable=0 when the key NAMES enumerate
# but every value read comes back empty (that read's status is discarded upstream). A gate
# that only checks dead/unverifiable then certifies ZERO pairs and lets terraform destroy.
W5_OK=1
for _f in "$BRIDGE_ACTION" "$INFRA_WF"; do
  grep -qE '^\s*if \[\[ "\$live" -gt 0 ' "$_f" || W5_OK=0
done
if [[ "$W5_OK" == "1" ]]; then
  pass "both consumers require a positive live count before reporting clean"
else
  fail "a clean verdict must be asserted POSITIVELY on live>0 — reaching success by exhausting negative branches reports clean on a scan that measured nothing"
fi

echo "W6: the gate is the FINAL step of the composite"
# Position IS the contract: the composite is consumed as one `uses:` step and GitHub
# guarantees step order, so "last step" ⇒ "before every caller step that follows".
# The step-boundary regex must match steps with NO `name:` key — `name:` is optional in a
# composite, so a `- uses:`/`- shell:` step appended after the gate would otherwise be
# invisible and W6 would pass while a step ran after the gate. MEASURED: appending a bare
# `- shell: bash / run:` step passed the previous `^    - name: `-only form.
W6_GATE_LINE=$(grep -nE '^\s*bash scripts/check-cloudflare-token-drift\.sh --only CI_SSH_ACCESS_TOKEN --json-file' "$BRIDGE_ACTION" | head -1 | cut -d: -f1)
W6_LAST_STEP=$(grep -nE '^    - (name|uses|shell|run|id|if|with|env):' "$BRIDGE_ACTION" | tail -1 | cut -d: -f1)
W6_GATE_STEP=$(awk -v g="${W6_GATE_LINE:-0}" 'NR<=g && /^    - (name|uses|shell|run|id|if|with|env):/{n=NR} END{print n+0}' "$BRIDGE_ACTION")
if [[ -n "$W6_GATE_LINE" && "$W6_GATE_STEP" == "$W6_LAST_STEP" && "$W6_LAST_STEP" != "0" ]]; then
  pass "gate is the last step — the bridge cannot report ready without having gated"
else
  fail "the gate must be the composite's final step (gate step starts at line ${W6_GATE_STEP:-none}, last step starts at line ${W6_LAST_STEP:-none})"
fi

echo "W7: the six bridge call sites are the expected six, by NAME"
# MEMBERSHIP, not cardinality. A count is invariant under substitution: MEASURED, pointing
# one caller at a different action and adding a spare `uses:` elsewhere kept the total at 6
# while a workflow that SSHes to a host silently lost the gate — and the failure string
# would have described exactly that, having never printed. Deriving the sorted filename
# list also makes a legitimate NEW adopter produce a diff that names the file, instead of
# a count mismatch blaming duplication.
W7_ACTUAL=$(grep -rlE '^\s+uses: \./\.github/actions/cf-tunnel-ssh-bridge\s*$' "$GH_DIR/workflows" 2>/dev/null | xargs -r -n1 basename | sort -u | paste -sd, -)
W7_EXPECTED="apply-deploy-pipeline-fix.yml,apply-web-platform-infra.yml,git-data-cutover.yml,workspaces-luks-cutover.yml,workspaces-luks-verify.yml"
W7_N=$(grep -rEc '^\s+uses: \./\.github/actions/cf-tunnel-ssh-bridge\s*$' "$GH_DIR/workflows" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
if [[ "$W7_ACTUAL" == "$W7_EXPECTED" && "$W7_N" == "6" ]]; then
  pass "5 workflows / 6 call sites (workspaces-luks-cutover uses it twice)"
else
  fail "bridge callers drifted. Expected files [$W7_EXPECTED] with 6 call sites; got [$W7_ACTUAL] with $W7_N. If you ADDED a caller, add it to W7_EXPECTED and bump the count; if a file disappeared from the list, that workflow silently lost the liveness gate."
fi

echo "W8: no -replace target names the .deploy service token"
# AC3. `.deploy` is the ONLY other remote write path to web-1, and web-1 cannot be
# replaced (cx33 stock 0/6). Replacing it on any failure between destroy and Doppler
# republish strands the host with no reachable channel at all.
# `[= ]` because terraform's flag parser accepts `-replace ADDRESS` as well as `-replace=`.
W8_HITS=$(grep -rEn -- '-replace[= ]+["'"'"']?[^ ]*access_service_token\.deploy' "$GH_DIR" 2>/dev/null || true)
if [[ -z "$W8_HITS" ]]; then
  pass "the working .deploy token is never a replace target"
else
  fail "a -replace target names the .deploy service token — this can strand an unreplaceable host: $W8_HITS"
fi

echo "W9: the ci-ssh-token-replace arm exists, is typo-guarded, and replaces the token"
# Anchored on the SHELL COMPARISON, not the token string: the confirm literal also appears
# in the dispatch-input DESCRIPTION prose, so a bare grep passed with the entire typo-guard
# step deleted. Likewise `-replace=` is anchored at flag position — MEASURED, commenting
# out the real flag left the previous form green while the arm planned nothing.
W9_OK=1
grep -qE '^\s+- ci-ssh-token-replace\s*$' "$INFRA_WF" || W9_OK=0
grep -qE '^\s*-replace=cloudflare_zero_trust_access_service_token\.ci_ssh' "$INFRA_WF" || W9_OK=0
grep -qE '"\$CONFIRM_RAW" != "REPLACE-CI-SSH-TOKEN"' "$INFRA_WF" || W9_OK=0
if [[ "$W9_OK" == "1" ]]; then
  pass "enum option, flag-position -replace, and an enforced typo-guard"
else
  fail "apply-web-platform-infra.yml needs the ci-ssh-token-replace enum option, a -replace= at flag position on the ci_ssh token, and a CONFIRM_RAW comparison against REPLACE-CI-SSH-TOKEN"
fi

echo "W10: the DEAD verdict's escalation is bound to the DEAD verdict"
# Two independent file-wide greps do not make an assertion: MEASURED, retargeting the
# escalation step's `if:` to verdict == 'unverifiable' left the previous form green, which
# restores the literal 2026-07-29 failure (dead credential → email only → nobody acts).
# Extract the step that files the issue and require ITS OWN guard to name 'dead'.
# Target the DEAD filer BY NAME, not by "first step containing --label
# action-required". The first-match form was correct while that was the only
# action-required filer in the job; the coverage filer added alongside the
# `coverage` output is a second one, and it sorts ABOVE the DEAD step — so
# first-match silently retargeted this assertion onto the wrong step and reported
# the DEAD guard missing when it was intact. Naming the step keeps the assertion
# pinned to the thing it is about, however many filers the job grows.
W10_STEP_START=$(awk '/^      - name: Open or update an action-required issue \(token drift — DEAD credential\)/{print NR; exit}' "$DRIFT_WF")
W10_GUARD=$(awk -v s="${W10_STEP_START:-0}" 'NR>s && NR<=s+3 && /^        if: /{print; exit}' "$DRIFT_WF")
if [[ -n "$W10_STEP_START" ]] && grep -qE "verdict == 'dead'" <<<"$W10_GUARD" && grep -qE '^\s+--label priority/p0-critical' "$DRIFT_WF"; then
  pass "the action-required filer is guarded on verdict == 'dead' and carries a priority label"
else
  fail "the step filing the action-required issue must itself be guarded on verdict == 'dead' (found guard: '${W10_GUARD:-none}') and must carry --label priority/p0-critical (operator-digest sorts on priority and caps the list, so an unprioritised issue is filed and still unseen)"
fi
echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
# ANTI-VACUITY FLOOR. Without it, deleting every assertion call yields
# "0/0 passed, 0 failed" and exit 0 — measured — and test-all.sh reads only the exit code,
# so a suite that ran NOTHING is indistinguishable from one where everything passed. A
# FLOOR, not equality: adding a case must not require editing this line.
#
# Raised 13 -> 24 with the Access-stamp rewrite, then -> 40, then -> 50 with the #7095
# consumer-wiring block (W1-W10). 50 against 52 running keeps main's 2-assertion slack —
# derived from a green run, not chosen. At 13 against 26 running assertions the floor had
# 13 assertions of slack — measured: deleting T14 through T19, i.e. the ENTIRE arm the
# suite exists to cover, still reported "13/13 passed" and exit 0. A floor that far below
# the real count cannot distinguish "the feature's tests were removed" from "they passed".
# Still a floor, not equality, so adding a case does not require editing it — but it is now
# close enough to the count that deleting a feature's cases trips it.
if [[ "$((PASS + FAIL))" -lt 50 ]]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran; expected >= 50. The suite did not execute what it claims to." >&2
  exit 1
fi
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
