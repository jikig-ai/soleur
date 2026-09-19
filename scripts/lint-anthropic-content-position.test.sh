#!/usr/bin/env bash
# Fixture suite for scripts/lint-anthropic-content-position.py (#8392).
# Twin registration (scripts/test-all.sh): this file pins the DETECTOR against
# synthesized inputs; the sibling `-live` row runs the detector over the repo.
# Registering only one of the two is what makes a lint decoration.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SCRIPT_DIR/lint-anthropic-content-position.py"

PASS=0; FAIL=0; TOTAL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); }

# Instrument self-test (ADR-193): drive both branches, require both counters to
# move, report with printf + exit — never through the helpers under test.
pass "self-test" >/dev/null
fail "self-test" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 || "$TOTAL" -ne 2 ]]; then
  printf 'FATAL: verdict helpers are not dispatching (PASS=%s FAIL=%s TOTAL=%s)\n' "$PASS" "$FAIL" "$TOTAL" >&2
  exit 2
fi
PASS=0; FAIL=0; TOTAL=0
MIN_ASSERTIONS=7

# $1 = case name, $2 = expected rc, $3 = file basename, $4 = file body
run_case() {
  local name="$1" want="$2" base="$3" body="$4" root rc=0
  root="$(mktemp -d)"
  git -C "$root" init -q 2>/dev/null || { echo "FATAL: git init failed" >&2; exit 2; }
  mkdir -p "$root/server"
  printf '%s\n' "$body" > "$root/server/$base"
  git -C "$root" add -A >/dev/null 2>&1
  python3 "$LINT" --root "$root" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq "$want" ]]; then pass "$name (rc=$rc)"; else fail "$name (want rc=$want, got $rc)"; fi
  rm -rf "$root"
}

# Known-POSITIVE: each forbidden spelling must be detected. Without these the
# regexes could match nothing and every clean verdict would be vacuous.
run_case "literal index is rejected"    1 r.ts 'const t = data.content[0].text; // api.anthropic.com'
run_case ".at(0) is rejected"           1 r.ts 'const t = data.content.at(0)?.text; // api.anthropic.com'
run_case "optional chain is rejected"   1 r.ts 'const t = data.content?.[0]?.text; // api.anthropic.com'
run_case "length-1 is rejected"         1 r.ts 'const t = data.content[data.content.length - 1]; // api.anthropic.com'
run_case "jq positional is rejected"    1 r.sh 'jq -r ".content[0].text" # api.anthropic.com'

# Known-NEGATIVE: the correct readers must pass, or the lint blocks the fix.
run_case "type selection passes"        0 r.ts 'const t = data.content.find((b) => b.type === "text")?.text; // api.anthropic.com'
run_case "jq type selection passes"     0 r.sh "jq -r 'first(.content[] | select(.type == \"text\") | .text)' # api.anthropic.com"

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: assertion floor breached (TOTAL=%s < %s)\n' "$TOTAL" "$MIN_ASSERTIONS" >&2
  exit 2
fi
[[ "$FAIL" -eq 0 ]] || exit 1
