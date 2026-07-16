#!/usr/bin/env bash
# AC7 + AC7b harness for scripts/supabase-advisor-scan.sh.
#
# WHAT THIS PROVES, AND WHY IT EXISTS
# ===================================
# The scan this script replaces was FAIL-OPEN. Verified live 2026-07-16 against
# the real Management API: an expired PAT returns HTTP 401 with the body
#   {"message":"JWT could not be decoded"}
# and the pre-existing parse idiom `[.lints[]? | select(...)] | length` turns
# that into the integer 0 — byte-identical to a clean scan. A gate that asserts
# "count == 0" on that parse is PERMANENTLY GREEN on a dead token while
# reporting that it is watching the database. That is strictly worse than no
# gate, because it retires the human vigilance currently substituting for it.
#
# So the single most important property of this script is NOT that it detects a
# violation — it is that it CANNOT SILENTLY PASS. Every case below that is not
# the genuine-clean case MUST exit non-zero with a specific fail_mode.
#
# AC7  (parse path)      : 401 / empty / HTML-502 / .lints-renamed / clean /
#                          violation / wrong-.name identity.
# AC7b (decision path)   : the advisor x catalog quadrant matrix. AC7 exercises
#                          only parsing and structurally CANNOT catch a
#                          fail-open in the DECISION logic — hence AC7b.
#
# Fixtures are SYNTHESIZED, never captured live (cq-test-fixtures-synthesized-only).
# The token below is a non-credential literal that never authenticated anything.
#
# The seam: we stub `curl` on PATH. We deliberately do NOT make the API host
# overridable via env — an overridable host is a PAT-exfil-via-redirect seam in
# production. Stubbing the BINARY gives testability with no production seam,
# which is why the host stays pinned in the script under test.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/supabase-advisor-scan.sh"

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; fails=$((fails + 1)); }

if [[ ! -f "$SCRIPT" ]]; then
  printf 'FATAL: %s does not exist\n' "$SCRIPT" >&2
  exit 1
fi

STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT

# ---------------------------------------------------------------------------
# The curl stub. Dispatches on the request shape and echoes fixture bodies from
# env. Mirrors real curl's `-w '\n%{http_code}'` contract: body, newline, code.
#
# Routing:
#   .../advisors/security          -> advisor
#   .../database/query + 'rls_off' -> catalog (the unconditional assertion)
#   .../database/query (otherwise) -> object-scoped lookup (the 3.3 carve-out)
#   .../projects/{ref}             -> identity preflight
# ---------------------------------------------------------------------------
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
# Synthetic curl stub — emits fixture bodies, never touches the network.
#
# Every STUB_* var is exported unconditionally by reset_stub, so this stub uses
# them bare. It deliberately does NOT apply `${VAR:-default}` fallbacks: `:-`
# also fires on an EMPTY value, which would silently substitute a well-formed
# body for the empty-body fixture and make that test vacuous.
args="$*"
data=""
prev=""
for a in "$@"; do
  case "$prev" in --data|-d) data="$a" ;; esac
  prev="$a"
done

emit() { printf '%s\n%s' "$1" "$2"; }

case "$args" in
  *"/advisors/security"*)
    emit "$STUB_ADV_BODY" "$STUB_ADV_CODE" ;;
  *"/database/query"*)
    # The catalog assertion is the only query carrying the rls_off alias; every
    # other query is a Phase-3.3 object-scoped lookup.
    case "$data" in
      *rls_off*) emit "$STUB_CAT_BODY" "$STUB_CAT_CODE" ;;
      *)         emit "$STUB_OBJ_BODY" "$STUB_OBJ_CODE" ;;
    esac ;;
  *)
    emit "$STUB_ID_BODY" "$STUB_ID_CODE" ;;
esac
exit 0
STUB
chmod +x "$STUB_DIR/curl"

# Run the script under test with the stub ahead of real curl on PATH.
# Returns: sets RC and OUT.
run_scan() {
  OUT=$(PATH="$STUB_DIR:$PATH" \
    REF=mlwiodleouzwniehynfz \
    PROJECT_NAME=soleur-dev \
    SUPABASE_ACCESS_TOKEN='sbp_synthetic0000000000000000000000000000' \
    bash "$SCRIPT" 2>&1)
  RC=$?
}

# Assert the scan failed AND named the expected fail_mode. Both halves matter:
# a non-zero exit with the WRONG mode routes the operator to the wrong issue
# class (an expired token paging as a data-exposure incident).
expect_fail_mode() {
  local label="$1" want="$2"
  if [[ "$RC" -eq 0 ]]; then
    fail "$label" "expected non-zero exit, got 0 — THIS IS THE FAIL-OPEN CLASS. out: $(printf '%s' "$OUT" | tr '\n' ' ' | head -c 200)"
    return
  fi
  if ! printf '%s' "$OUT" | grep -qF "fail_mode=$want"; then
    fail "$label" "expected fail_mode=$want; got: $(printf '%s' "$OUT" | grep -F 'fail_mode=' || echo '(none emitted)')"
    return
  fi
  pass "$label"
}

expect_clean() {
  local label="$1"
  if [[ "$RC" -ne 0 ]]; then
    fail "$label" "expected exit 0, got $RC. out: $(printf '%s' "$OUT" | tr '\n' ' ' | head -c 200)"
    return
  fi
  pass "$label"
}

reset_stub() {
  unset STUB_ID_CODE STUB_ID_BODY STUB_ADV_CODE STUB_ADV_BODY \
        STUB_CAT_CODE STUB_CAT_BODY STUB_OBJ_CODE STUB_OBJ_BODY
  export STUB_ID_CODE=200 STUB_ID_BODY='{"name":"soleur-dev"}'
  export STUB_ADV_CODE=200 STUB_ADV_BODY='{"lints":[]}'
  export STUB_CAT_CODE=201 STUB_CAT_BODY='[{"rls_off":0}]'
  export STUB_OBJ_CODE=201 STUB_OBJ_BODY='[]'
}

# A lint object in the REAL shape, pinned live 2026-07-16 from a non-zero
# sibling lint (rls_enabled_no_policy on soleur-dev). Table identity lives at
# .metadata.schema + .metadata.name. Phase 3.3 depends on this shape.
advisor_fires() {
  export STUB_ADV_BODY='{"lints":[{"name":"rls_disabled_in_public","level":"ERROR","categories":["SECURITY"],"detail":"Table public.leaky has RLS disabled","metadata":{"name":"leaky","type":"table","schema":"public"},"cache_key":"rls_disabled_in_public_public_leaky"}]}'
}

echo "== AC7: parse path (the fail-open negative control) =="

# THE headline case. This is the exact body the live API returned for an
# expired PAT on 2026-07-16, and the exact input the old parse scored as 0.
reset_stub
export STUB_ADV_CODE=401 STUB_ADV_BODY='{"message":"JWT could not be decoded"}'
run_scan
expect_fail_mode "401 expired PAT fails loud (does NOT parse to a clean 0)" advisor_unreachable

reset_stub
export STUB_ADV_CODE=200 STUB_ADV_BODY=''
run_scan
expect_fail_mode "empty 200 body fails loud" advisor_malformed

reset_stub
export STUB_ADV_CODE=502 STUB_ADV_BODY='<html><head><title>502 Bad Gateway</title></head></html>'
run_scan
expect_fail_mode "HTML 502 fails loud" advisor_unreachable

reset_stub
export STUB_ADV_BODY='{"findings":[]}'
run_scan
expect_fail_mode "API contract drift (.lints renamed) fails loud" advisor_malformed

reset_stub
export STUB_ADV_BODY='{"lints":"not-an-array"}'
run_scan
expect_fail_mode ".lints present but wrong type fails loud" advisor_malformed

reset_stub
export STUB_ID_CODE=401 STUB_ID_BODY='{"message":"Unauthorized"}'
run_scan
expect_fail_mode "identity preflight non-200 fails loud" identity_unreachable

reset_stub
export STUB_ID_BODY='{"name":"soleur-web-platform"}'
run_scan
expect_fail_mode "ref resolving to the WRONG project fails loud (ref<->name pairing)" identity_mismatch

reset_stub
export STUB_CAT_CODE=500 STUB_CAT_BODY='{"message":"boom"}'
run_scan
expect_fail_mode "catalog query non-201 fails loud" catalog_unreachable

reset_stub
export STUB_CAT_BODY='{"message":"JWT could not be decoded"}'
run_scan
expect_fail_mode "catalog query returning an object (not a row array) fails loud" catalog_malformed

reset_stub
run_scan
expect_clean "genuine clean scan passes"

echo "== AC7b: decision quadrants (fail-open in the DECISION logic) =="

# Quadrant: advisor clean, catalog clean -> PASS
reset_stub
run_scan
expect_clean "advisor clean + catalog clean -> pass"

# Quadrant: advisor CLEAN (stale), catalog DIRTY -> MUST FAIL.
# This is the false-green the v1 design missed entirely: a design that consults
# the catalog only when the advisor fires never runs this check. The advisor is
# documented as servable-stale right after a DDL change, so a cached 0 over a
# live violation is exactly the case a nightly gate exists to catch.
reset_stub
export STUB_CAT_BODY='[{"rls_off":3}]'
run_scan
expect_fail_mode "advisor CLEAN but catalog DIRTY -> FAIL (a stale advisor cannot hide a real violation)" violation_confirmed

# Quadrant: advisor fires, catalog clean, named table is NOW RLS-on -> WARN+pass.
# The benign <=1h self-heal window. Failing here would make the gate cry wolf,
# and a nightly security gate that cries wolf gets ignored — which is precisely
# how #3366 rotted for 71 days.
reset_stub
advisor_fires
export STUB_OBJ_BODY='[{"relrowsecurity":true}]'
run_scan
expect_clean "advisor fires + catalog clean + named table now RLS-on -> WARN, pass (benign self-heal)"
if [[ "$RC" -eq 0 ]] && printf '%s' "$OUT" | grep -qF 'stale_advisor'; then
  pass "  ...and the WARN is actually emitted as stale_advisor"
else
  fail "stale_advisor WARN emitted" "expected a stale_advisor warning in output"
fi

# Quadrant: advisor fires, catalog clean, named table genuinely RLS-off -> FAIL.
reset_stub
advisor_fires
export STUB_OBJ_BODY='[{"relrowsecurity":false}]'
run_scan
expect_fail_mode "advisor fires + named table actually RLS-off -> FAIL" confirm_indeterminate

# Quadrant: advisor fires, catalog clean, named table resolves to NO ROW -> FAIL.
# Count-vs-count confirmation would swallow this as lag. Object-scoping means an
# unexplained disagreement fails instead of WARN-passing forever.
reset_stub
advisor_fires
export STUB_OBJ_BODY='[]'
run_scan
expect_fail_mode "advisor fires + named table resolves to NO ROW -> FAIL (not swallowed as lag)" confirm_indeterminate

# Quadrant: advisor fires + catalog dirty -> FAIL.
reset_stub
advisor_fires
export STUB_CAT_BODY='[{"rls_off":2}]'
run_scan
expect_fail_mode "advisor fires + catalog dirty -> FAIL" violation_confirmed

echo "== Non-vacuity: the harness must be able to SEE a fail-open =="
# Mutation self-check. If the script were reverted to the fail-open parse, the
# 401 case would exit 0. Prove the harness distinguishes the two by running a
# deliberately fail-open stand-in and asserting it would be CAUGHT. Without this
# the suite could be green because it never actually exercises the assertion.
MUT="$STUB_DIR/failopen.sh"
cat > "$MUT" <<'MUTEOF'
#!/usr/bin/env bash
# Deliberately fail-open: the pre-existing idiom this PR removes.
body=$(curl -sS -w '\n%{http_code}' "https://api.supabase.com/v1/projects/$REF/advisors/security" 2>/dev/null | sed '$d')
n=$(printf '%s' "$body" | jq '[.lints[]? | select(.name=="rls_disabled_in_public")] | length' 2>/dev/null)
[[ "${n:-0}" -eq 0 ]] && exit 0
exit 1
MUTEOF
chmod +x "$MUT"
reset_stub
export STUB_ADV_CODE=401 STUB_ADV_BODY='{"message":"JWT could not be decoded"}'
if PATH="$STUB_DIR:$PATH" REF=x bash "$MUT" >/dev/null 2>&1; then
  pass "the fail-open idiom DOES exit 0 on a 401 (bug reproduced -> the 401 assertion above is non-vacuous)"
else
  fail "fail-open reproduction" "the fail-open stand-in did NOT exit 0 on a 401 — the 401 test above may be passing vacuously"
fi

echo ""
if [[ "$fails" -gt 0 ]]; then
  printf '%d check(s) FAILED\n' "$fails"
  exit 1
fi
echo "all checks passed"
