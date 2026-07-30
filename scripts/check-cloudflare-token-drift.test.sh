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
cat > "$STUB_DIR/doppler" <<'STUB'
#!/usr/bin/env bash
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
      _v=$(grep -F "${_cfg}|${_key}|" "$MOCK_SECRETS" 2>/dev/null | head -1 | cut -d'|' -f3-)
      [[ -n "$_v" ]] && printf '%s\n' "$_v"
      exit 0
    fi
    _cfg=""
    for ((i=1; i<=$#; i++)); do
      [[ "${!i}" == "-c" ]] && { j=$((i+1)); _cfg="${!j}"; }
    done
    grep -F "${_cfg}|" "$MOCK_SECRETS" 2>/dev/null | cut -d'|' -f2
    ;;
esac
exit 0
STUB
chmod +x "$STUB_DIR/doppler"

# `curl` stub. Records every invocation's full argv to $MOCK_CURL_LOG so the tests can
# assert HOW the token was presented, not merely what verdict came back — a verdict-only
# assertion would pass against an implementation that kept using the wrong endpoint and
# happened to get the right answer. $MOCK_HTTP_CODE drives the response.
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
[[ -n "${MOCK_CURL_LOG:-}" ]] && printf '%s\n' "$*" >> "$MOCK_CURL_LOG"
printf '%s' "${MOCK_HTTP_CODE:-200}"
exit 0
STUB
chmod +x "$STUB_DIR/curl"

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
run_sut() {
  local label="$1" http_code="$2" secrets_body="$3" configs_body="${4:-prd}"
  local cfgs="$TMP/$label.configs" secs="$TMP/$label.secrets"
  OUT="$TMP/$label.out"; CURL_LOG="$TMP/$label.curl"
  printf '%s\n' "$configs_body" > "$cfgs" || { echo "FATAL: fixture write failed"; exit 2; }
  printf '%s\n' "$secrets_body" > "$secs" || { echo "FATAL: fixture write failed"; exit 2; }
  : > "$CURL_LOG"
  MOCK_CONFIGS="$cfgs" MOCK_SECRETS="$secs" \
  MOCK_HTTP_CODE="$http_code" MOCK_CURL_LOG="$CURL_LOG" \
  APP_DOMAIN_BASE="soleur.ai" \
  PATH="$STUB_DIR:$PATH" \
    bash "$SUT" > "$OUT" 2>&1
  RC=$?
}

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
run_sut t3 403 "$ACCESS_FIXTURE"
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
echo "T5: a 000/5xx response is NOT treated as live (fail closed)"
run_sut t5 000 "$ACCESS_FIXTURE"
if [[ "$RC" == "1" ]] && grep -qE 'dead entries: [1-9]' "$OUT"; then
  pass "unreachable -> DEAD, exit 1 (never silently LIVE)"
else
  fail "an unreachable probe must fail closed, got rc=$RC"
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
if [[ "$RC" == "1" ]] && grep -qF 'no hostname mapping' "$OUT"; then
  pass "unmappable token surfaced as a coverage gap, exit 1"
else
  fail "an unmappable Access token must fail closed and say why (rc=$RC)"
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

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
