#!/usr/bin/env bash
# HEADLESS_MODE boolean classification test for session-rules-loader.sh.
#
# Verifies sub-PR 3's additive HEADLESS_MODE export:
#   - </dev/null + CLAUDECODE=1 → HEADLESS_MODE=1
#   - TTY  + CLAUDECODE=1       → HEADLESS_MODE=0
#
# The 3-value enum (peek vs bg) was rejected by Simplicity review (no
# consumer reads HEADLESS_KIND). Boolean only.
#
# Run via:  bash .claude/hooks/session-rules-loader-headless.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/session-rules-loader.sh"

PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

# The hook is large and reads/writes a lot of state. The cheapest way to
# probe the env-classification fragment is to extract and source just the
# block we care about; the production hook will execute the same block at
# real startup. We assert the block exists and behaves correctly.

if ! grep -q 'export HEADLESS_MODE' "$HOOK"; then
  fail "T1: session-rules-loader.sh does not export HEADLESS_MODE"
fi

# Extract a small probe script that mimics the classifier block exactly.
PROBE=$(mktemp); trap 'rm -f "$PROBE"' EXIT
# shellcheck disable=SC2016
cat > "$PROBE" <<'EOF'
# Mirror the classifier expression from session-rules-loader.sh.
if [[ ! -t 0 ]] && [[ -n "${CLAUDECODE:-}" ]]; then
  export HEADLESS_MODE=1
else
  export HEADLESS_MODE=0
fi
echo "HEADLESS_MODE=$HEADLESS_MODE"
EOF

# Verify the production hook contains the same classifier shape (drift guard).
if ! grep -qE '\[\[ ! -t 0 \]\] && \[\[ -n "\$\{CLAUDECODE:-\}" \]\]' "$HOOK"; then
  fail "T2: classifier expression in hook does not match canonical form"
else
  pass "T2: classifier expression present"
fi

# T3: headless path classifies HEADLESS_MODE=1
echo "T3: stdin not TTY + CLAUDECODE=1 → HEADLESS_MODE=1"
OUT=$(CLAUDECODE=1 bash "$PROBE" </dev/null 2>&1)
if [[ "$OUT" == "HEADLESS_MODE=1" ]]; then
  pass "T3"
else
  fail "T3: expected HEADLESS_MODE=1, got: $OUT"
fi

# T4: foreground path classifies HEADLESS_MODE=0
echo "T4: TTY on stdin + CLAUDECODE=1 → HEADLESS_MODE=0"
if command -v script >/dev/null; then
  TYPESCRIPT=$(mktemp)
  script -q -c "CLAUDECODE=1 bash $PROBE" "$TYPESCRIPT" >/dev/null
  if grep -q "HEADLESS_MODE=0" "$TYPESCRIPT"; then
    pass "T4"
  else
    fail "T4: expected HEADLESS_MODE=0 in pty, got: $(cat "$TYPESCRIPT")"
  fi
  rm -f "$TYPESCRIPT"
else
  echo "  skip: script(1) missing"
fi

# T5: CLAUDECODE unset → HEADLESS_MODE=0 regardless of TTY
echo "T5: CLAUDECODE unset → HEADLESS_MODE=0"
OUT=$(unset CLAUDECODE; bash "$PROBE" </dev/null 2>&1)
if [[ "$OUT" == "HEADLESS_MODE=0" ]]; then
  pass "T5"
else
  fail "T5: expected HEADLESS_MODE=0 when CLAUDECODE unset, got: $OUT"
fi

echo
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
