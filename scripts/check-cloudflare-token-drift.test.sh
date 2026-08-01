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
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
[[ -n "${MOCK_CURL_LOG:-}" ]] && printf '%s\n' "$*" >> "$MOCK_CURL_LOG"
_want_code=0
_outfile=""
for ((i=1; i<=$#; i++)); do
  case "${!i}" in
    -w) j=$((i+1)); [[ "${!j}" == *'%{http_code}'* ]] && _want_code=1 ;;
    -o) j=$((i+1)); _outfile="${!j}" ;;
  esac
done
# Body first (the API arm reads stdout when there is no -o; with -o it goes to the file).
_body="${MOCK_HTTP_BODY:-}"
if [[ -n "$_outfile" ]]; then
  printf '%s' "$_body" > "$_outfile" 2>/dev/null || true
else
  printf '%s' "$_body"
fi
# Only emit the status code when -w actually asked for it.
[[ "$_want_code" == 1 ]] && printf '%s' "${MOCK_HTTP_CODE:-200}"
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
  local label="$1" http_code="$2" secrets_body="$3" configs_body="${4:-prd}" only_arg="${5:-}"
  local cfgs="$TMP/$label.configs" secs="$TMP/$label.secrets"
  OUT="$TMP/$label.out"; CURL_LOG="$TMP/$label.curl"
  printf '%s\n' "$configs_body" > "$cfgs" || { echo "FATAL: fixture write failed"; exit 2; }
  printf '%s\n' "$secrets_body" > "$secs" || { echo "FATAL: fixture write failed"; exit 2; }
  : > "$CURL_LOG"
  # shellcheck disable=SC2086
  MOCK_CONFIGS="$cfgs" MOCK_SECRETS="$secs" \
  MOCK_HTTP_CODE="$http_code" MOCK_CURL_LOG="$CURL_LOG" \
  MOCK_HTTP_BODY="${MOCK_HTTP_BODY:-}" \
  APP_DOMAIN_BASE="soleur.ai" \
  PATH="$STUB_DIR:$PATH" \
    bash "$SUT" $only_arg > "$OUT" 2>&1
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
run_sut t9 403 "prd|REGISTRY_PUSH_ACCESS_TOKEN_ID|${FIX_ID}
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
run_sut t14 403 "$ACCESS_FIXTURE" prd "--json-file $JF"
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
# T15-T17 — the ssh:// ORIGIN arm.
#
# `access_hostname_for()` maps CI_SSH_ACCESS_TOKEN to ssh.<base>, whose Cloudflare Tunnel
# ingress is `ssh://<web-1-private-ip>:22` (apps/web-platform/infra/tunnel.tf). That origin
# does not speak HTTP: a request that Access ADMITS is handed to sshd, which answers with
# an SSH version banner, so cloudflared returns 5xx. HTTP 200 is therefore UNREACHABLE for
# a perfectly healthy pair, and the 200-only rule graded this token family DEAD forever —
# a permanent false positive that fired a twice-daily "[TOKEN DRIFT] rotation did not
# propagate" email and told the operator to rotate a credential the script never measured.
#
# The discrimination that IS sound for a non-HTTP origin: Access runs at the EDGE, before
# the origin is ever reached, so a 403 on this host can only come from Access (an ssh
# origin cannot emit an HTTP status at all). 403 => rejected. Any definite non-403 HTTP
# status => Access admitted, which is the only thing this probe can and should certify.
#
# The fail-closed principle is preserved, not traded away: a 000 (timeout / DNS / TLS
# failure) still means the script did not LEARN anything, and must render UNVERIFIABLE —
# never LIVE.
# ---------------------------------------------------------------------------
CI_SSH_FIXTURE="prd|CI_SSH_ACCESS_TOKEN_ID|${FIX_ID}
prd|CI_SSH_ACCESS_TOKEN_SECRET|${FIX_SECRET}"

echo "T15: 502 from an ssh:// origin -> LIVE (Access admitted; 200 is unreachable there)"
run_sut t15 502 "$CI_SSH_FIXTURE"
if [[ "$RC" == "0" ]] && grep -qE 'live entries: 1' "$OUT" && grep -qE 'dead entries: 0' "$OUT"; then
  pass "a healthy ssh-origin pair grades LIVE on 502"
else
  fail "502 from an ssh:// origin must grade LIVE — 200 cannot occur there, so the 200-only rule reports a healthy token DEAD forever (rc=$RC)"
fi

echo "T16: 403 from an ssh:// origin -> DEAD (only Access can emit 403 on that host)"
run_sut t16 403 "$CI_SSH_FIXTURE"
if [[ "$RC" == "1" ]] && grep -qE 'dead entries: 1' "$OUT"; then
  pass "403 still grades DEAD — the rejection signal is preserved"
else
  fail "403 on an ssh:// origin must remain DEAD; widening the arm must not blind it to a real rejection (rc=$RC)"
fi

echo "T17: 000 from an ssh:// origin -> UNVERIFIABLE, never LIVE (fail-closed preserved)"
run_sut t17 000 "$CI_SSH_FIXTURE"
_t17=1
grep -qE 'live entries: 0' "$OUT" || _t17=0
grep -qE 'unverifiable: 1' "$OUT" || _t17=0
[[ "$RC" == "1" ]] || _t17=0
if [[ "$_t17" == "1" ]]; then
  pass "a timeout renders UNVERIFIABLE and exits non-zero, not LIVE"
else
  fail "000 must render UNVERIFIABLE — 'did not learn' must never read as LIVE, and must not read as DEAD either (rc=$RC)"
fi

# T18-T19 — the FALSE-LIVE guard. LIVE must be a POSITIVE admission proof (5xx from the
# tunnel layer behind Access), never "did not look like a rejection".
#
# 403 is not Access's only rejection shape. Give this app an identity policy and an
# unauthenticated request answers 302 to the IdP login page; challenges (429) and 401s are
# rejections too. Under an absence-based rule every one of those grades LIVE — a DEAD
# credential certified healthy, which is worse than the DEAD-forever bug being fixed here,
# because it fails silently instead of loudly. These two cases pin the direction.
echo "T18: a 302 Access login redirect must NOT grade LIVE (false-LIVE guard)"
run_sut t18 302 "$CI_SSH_FIXTURE"
if [[ "$RC" != "0" ]] && ! grep -qE 'live entries: 1' "$OUT"; then
  pass "302 does not certify the pair — unrecognised answers render UNVERIFIABLE"
else
  fail "302 (an Access login redirect) graded LIVE — LIVE must be positive 5xx admission proof, not absence-of-403 (rc=$RC)"
fi

echo "T19: 530 (tunnel-layer error, behind Access) grades LIVE"
run_sut t19 530 "$CI_SSH_FIXTURE"
if [[ "$RC" == "0" ]] && grep -qE 'live entries: 1' "$OUT"; then
  pass "530 proves the request got past Access to the tunnel layer"
else
  fail "530 must grade LIVE — it is an origin/tunnel error, reachable only after Access admitted (rc=$RC)"
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
W10_STEP_START=$(awk '/^      - name: /{n=NR} /--label action-required/{print n; exit}' "$DRIFT_WF")
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
if [[ "$((PASS + FAIL))" -lt 31 ]]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran; expected >= 31. The suite did not execute what it claims to." >&2
  exit 1
fi
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
