#!/usr/bin/env bash
# Offline fixture tests for check-client-pii-sentry.sh (#3703).
#
# The SUT is tree-scanning + offline (no gh/network), so unlike the density
# test we exercise the REAL script directly against synthetic fixtures.
set -uo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
SUT="$DIR/../check-client-pii-sentry.sh"

PASS=0
FAIL=0

# assert_exit <expected-rc> <description> <file...>
assert_exit() {
  local expect="$1"; shift
  local desc="$1"; shift
  bash "$SUT" "$@" >/dev/null 2>&1
  local rc=$?
  if [[ "$rc" -eq "$expect" ]]; then
    echo "  PASS: $desc (exit $rc)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected exit $expect, got $rc)"
    FAIL=$((FAIL + 1))
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# (1) same-line userId violation → exit 1
mkdir -p "$TMP/components"
cat > "$TMP/components/same-line.tsx" <<'EOF'
Sentry.captureException(err, { extra: { userId } });
EOF

# (2) multi-line userId violation → exit 1 (the load-bearing non-vacuity case)
cat > "$TMP/components/multi-line.tsx" <<'EOF'
Sentry.captureException(err, {
  extra: {
    userId,
  },
});
EOF

# (3) email violation → exit 1
cat > "$TMP/components/email.tsx" <<'EOF'
Sentry.captureMessage("boom", {
  extra: { email },
});
EOF

# (4) user_id snake-case → exit 1
cat > "$TMP/components/snake.tsx" <<'EOF'
Sentry.captureException(e, {
  extra: { user_id: row.user_id },
});
EOF

# (5) clean extra: { filename } → exit 0
cat > "$TMP/components/clean.tsx" <<'EOF'
Sentry.captureException(err, {
  extra: { filename },
});
EOF

# (6) tags-only sibling block with a userId-ish token after a clean extra → exit 0
cat > "$TMP/components/tags-sibling.tsx" <<'EOF'
Sentry.captureException(err, {
  extra: { filename },
  tags: { route: "userId-route" },
});
EOF

# (7) app/api/ path with a violation → exit 0 (excluded)
mkdir -p "$TMP/app/api/foo"
cat > "$TMP/app/api/foo/route.ts" <<'EOF'
Sentry.captureException(err, { extra: { userId } });
EOF

# (8) client-observability.ts with a violation → exit 0 (excluded, sanctioned helper)
mkdir -p "$TMP/lib"
cat > "$TMP/lib/client-observability.ts" <<'EOF'
Sentry.captureException(err, { extra: { userId } });
EOF

# (9) variable-form extra: someVar (mirrors observability-edge.ts) → exit 0
cat > "$TMP/components/var-form.tsx" <<'EOF'
Sentry.captureException(err, {
  extra: transformedExtra,
});
EOF

# (10) substring shadow currentUserIdentity → exit 0 (boundary correctness)
cat > "$TMP/components/shadow.tsx" <<'EOF'
Sentry.captureException(err, {
  extra: { currentUserIdentity },
});
EOF

echo "test-check-client-pii-sentry.sh"
assert_exit 1 "same-line userId violation"          "$TMP/components/same-line.tsx"
assert_exit 1 "multi-line userId violation"         "$TMP/components/multi-line.tsx"
assert_exit 1 "email violation"                     "$TMP/components/email.tsx"
assert_exit 1 "user_id snake-case violation"        "$TMP/components/snake.tsx"
assert_exit 0 "clean extra:{filename}"              "$TMP/components/clean.tsx"
assert_exit 0 "tags sibling with userId-ish token"  "$TMP/components/tags-sibling.tsx"
assert_exit 0 "app/api/ excluded"                   "$TMP/app/api/foo/route.ts"
assert_exit 0 "client-observability.ts excluded"    "$TMP/lib/client-observability.ts"
assert_exit 0 "variable-form extra: someVar"        "$TMP/components/var-form.tsx"
assert_exit 0 "substring shadow currentUserIdentity" "$TMP/components/shadow.tsx"

echo "  --- $PASS passed, $FAIL failed ---"
[[ "$FAIL" -eq 0 ]]
