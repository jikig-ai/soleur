#!/usr/bin/env bash
# Tests for supabase-ref-resolver.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./supabase-ref-resolver.sh
source "$SCRIPT_DIR/supabase-ref-resolver.sh"

PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# T1 — canonical URL → ref extracted via fast path.
echo "T1: canonical *.supabase.co URL"
set +e
ref=$(resolve_supabase_ref "https://abcdefghijklmnopqrst.supabase.co" 2>/dev/null)
rc=$?
set -e
if [[ "$rc" == "0" ]] && [[ "$ref" == "abcdefghijklmnopqrst" ]]; then
  pass "canonical → ref=$ref"
else
  fail "rc=$rc ref=$ref"
fi

# T2 — canonical URL with trailing slash.
echo "T2: canonical with trailing slash"
set +e
ref=$(resolve_supabase_ref "https://abcdefghijklmnopqrst.supabase.co/" 2>/dev/null)
set -e
[[ "$ref" == "abcdefghijklmnopqrst" ]] && pass "trailing slash ok" || fail "ref=$ref"

# T3 — empty URL → rc 1 + diagnostic.
echo "T3: empty URL → rc 1"
set +e
out=$(resolve_supabase_ref "" 2>&1)
rc=$?
set -e
[[ "$rc" == "1" ]] && [[ "$out" == *"empty URL"* ]] && pass "empty rejected" || fail "rc=$rc out=$out"

# T4 — non-supabase URL with no CNAME fallback → rc 1.
echo "T4: non-supabase, no CNAME match"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/dig" <<'FAKE_DIG'
#!/usr/bin/env bash
# Empty output for any host (no CNAME found).
exit 0
FAKE_DIG
chmod +x "$TMP/dig"
set +e
out=$(PATH="$TMP:$PATH" resolve_supabase_ref "https://example.com" 2>&1)
rc=$?
set -e
[[ "$rc" == "1" ]] && pass "non-supabase rejected" || fail "rc=$rc out=$out"
rm -rf "$TMP"; trap - EXIT

# T5 — custom domain with valid CNAME → ref extracted via fallback.
echo "T5: custom domain CNAME fallback"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/dig" <<'FAKE_DIG'
#!/usr/bin/env bash
saw_cname=0
saw_host=0
for arg in "$@"; do
  case "$arg" in
    CNAME) saw_cname=1 ;;
    api.example.com) saw_host=1 ;;
  esac
done
[[ "$saw_cname" == "1" && "$saw_host" == "1" ]] && printf '%s\n' 'abcdefghijklmnopqrst.supabase.co.'
FAKE_DIG
chmod +x "$TMP/dig"
set +e
ref=$(PATH="$TMP:$PATH" resolve_supabase_ref "https://api.example.com" 2>/dev/null)
set -e
[[ "$ref" == "abcdefghijklmnopqrst" ]] && pass "custom domain → ref=$ref" || fail "ref=$ref"
rm -rf "$TMP"; trap - EXIT

# T6 — subdomain-bypass guard: CNAME points to <ref>.supabase.co.evil.com → rejected.
echo "T6: subdomain-bypass guard"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/dig" <<'FAKE_DIG'
#!/usr/bin/env bash
saw_cname=0
for arg in "$@"; do [[ "$arg" == "CNAME" ]] && saw_cname=1; done
[[ "$saw_cname" == "1" ]] && printf '%s\n' 'abcdefghijklmnopqrst.supabase.co.evil.com.'
FAKE_DIG
chmod +x "$TMP/dig"
set +e
out=$(PATH="$TMP:$PATH" resolve_supabase_ref "https://api.attacker.com" 2>&1)
rc=$?
set -e
[[ "$rc" == "1" ]] && pass "subdomain-bypass attempt rejected" || fail "rc=$rc out=$out"
rm -rf "$TMP"; trap - EXIT

# T7 — uppercase ref in URL → rejected by lowercase-anchored regex.
echo "T7: uppercase rejected"
set +e
out=$(resolve_supabase_ref "https://ABCDEFGHIJKLMNOPQRST.supabase.co" 2>&1)
rc=$?
set -e
[[ "$rc" == "1" ]] && pass "uppercase rejected" || fail "rc=$rc out=$out"

echo
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1
