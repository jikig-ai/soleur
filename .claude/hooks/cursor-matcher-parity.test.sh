#!/usr/bin/env bash
# Cursor hook-matcher parity — issue #9608 slice 2.
#
# The 2026-10-07 capture exited at authentication before any hook ran.
# This suite pins that fail-closed record:
#   1. The shape note quotes the support bar and does not claim it was met.
#   2. Every ledger row is unmeasured. already-fires and dead are refused
#      until the shape note contains a loaded: line for that source.
#   3. hooks-empty.json stays an empty hooks object. No repo .cursor/hooks.json.
#   4. detectHarness and emit-decision.sh do not read CURSOR_INVOKED_AS or
#      CURSOR_AGENT. Neither name survived the CLI-versus-non-CLI test.
#
# Run: bash .claude/hooks/cursor-matcher-parity.test.sh

set -uo pipefail

. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

HOOKS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$HOOKS_DIR/../.." && pwd -P)"
SHAPE="$REPO_ROOT/plugins/soleur/cursor/2026-10-07-cli-hook-shape.md"
LEDGER="$HOOKS_DIR/cursor-dispositions.tsv"
EMPTY="$REPO_ROOT/plugins/soleur/cursor/hooks-empty.json"
HARNESS="$REPO_ROOT/plugins/soleur/lib/harness.ts"
EMIT="$REPO_ROOT/plugins/soleur/scripts/emit-decision.sh"

PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

if [ -f "$SHAPE" ]; then
  pass "shape note exists"
else
  fail "shape note missing at plugins/soleur/cursor/2026-10-07-cli-hook-shape.md"
fi

if [ -f "$SHAPE" ] && grep -q 'session-exited-at-auth' "$SHAPE"; then
  pass "shape note records the auth exit"
else
  fail "shape note does not record session-exited-at-auth"
fi

if [ -f "$SHAPE" ] && grep -q 'The plugin is called supported only when a Cursor CLI session shows' "$SHAPE"; then
  pass "shape note quotes the support bar"
else
  fail "shape note does not quote the support bar"
fi

if [ -f "$SHAPE" ] && grep -q 'The plugin is not supported' "$SHAPE"; then
  pass "shape note does not call the plugin supported"
else
  fail "shape note calls the plugin supported or omits the refusal"
fi

if [ -f "$SHAPE" ] && grep -q '^loaded:' "$SHAPE"; then
  fail "shape note has a loaded: line; this capture's ledger must be revisited"
else
  pass "shape note has no loaded: line"
fi

if [ -f "$SHAPE" ] && grep -q 'Closes #9608' "$SHAPE"; then
  fail "shape note contains Closes #9608"
else
  pass "shape note does not close #9608"
fi

# user_email may be named only as a field that was not stored.
if [ -f "$SHAPE" ] && grep -E -q 'user_email[[:space:]]*[:=][[:space:]]*[^[:space:]]+@' "$SHAPE"; then
  fail "shape note stores an email"
else
  pass "shape note does not store an email"
fi

rows=0
if [ -f "$LEDGER" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ""|\#*) continue ;;
    esac
    rows=$((rows + 1))
    # shellcheck disable=SC2086
    set -- $line
    # Tab fields: do not word-split. Count tabs.
    tabs=$(printf '%s' "$line" | awk -F '\t' '{ print NF }')
    if [ "$tabs" -ne 7 ]; then
      fail "ledger row does not have 7 fields: $line"
      continue
    fi
    disp=$(printf '%s' "$line" | awk -F '\t' '{ print $5 }')
    reason=$(printf '%s' "$line" | awk -F '\t' '{ print $6 }')
    case "$disp" in
      unmeasured)
        if [ "$reason" = "auth-exit-before-hook-load" ]; then
          pass "unmeasured row $(printf '%s' "$line" | awk -F '\t' '{ print $1 }')"
        else
          fail "unmeasured row has unexpected reason: $reason"
        fi
        ;;
      already-fires|dead)
        fail "disposition $disp is not backed by a loaded: line"
        ;;
      *)
        fail "unknown disposition $disp"
        ;;
    esac
  done < "$LEDGER"
else
  fail "ledger missing"
fi

if [ "$rows" -ge 8 ]; then
  pass "ledger has the eight named sources ($rows)"
else
  fail "ledger row count is $rows, want at least 8"
fi

if [ -f "$EMPTY" ] && grep -q '"hooks"[[:space:]]*:[[:space:]]*{[[:space:]]*}' "$EMPTY"; then
  pass "hooks-empty.json hooks object is empty"
else
  fail "hooks-empty.json is not an empty hooks object"
fi

if [ -e "$REPO_ROOT/.cursor/hooks.json" ]; then
  fail "repo-level .cursor/hooks.json exists"
else
  pass "no repo-level .cursor/hooks.json"
fi

if grep -q 'CURSOR_INVOKED_AS\|CURSOR_AGENT' "$HARNESS"; then
  fail "harness.ts reads a Cursor marker this capture did not adopt"
else
  pass "harness.ts does not read CURSOR_INVOKED_AS or CURSOR_AGENT"
fi

if grep -q 'CURSOR_' "$EMIT"; then
  fail "emit-decision.sh reads a CURSOR_ marker"
else
  pass "emit-decision.sh does not read a CURSOR_ marker"
fi

# Anti-vacuity floor. pass() and fail() are the assertion machinery. Neutering
# them leaves PASS and FAIL at 0, and this bound exits 1 without calling fail().
# 20 is the measured count for this capture: twelve fixed checks plus one pass
# for each of the eight ledger sources.
ASSERTED=$((PASS + FAIL))
if [ "$ASSERTED" -lt 20 ]; then
  printf '[FATAL] assertion floor: only %s assertion(s) ran\n' "$ASSERTED" >&2
  exit 1
fi

echo "cursor-matcher-parity: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
