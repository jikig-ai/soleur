#!/usr/bin/env bash
# Tests for sentry-monitors-audit.sh — Sentry Monitors/Alerts migration audit.
#
# Run via:  bash apps/web-platform/scripts/sentry-monitors-audit.test.sh
#
# Test environment isolation: each test runs the script in a tmpdir with
# SENTRY_FIXTURE_* env vars overriding the live API. Live API is NEVER called
# from this test.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/sentry-monitors-audit.sh"

if [[ ! -x "$SCRIPT" ]]; then
  echo "ERROR: $SCRIPT not found or not executable" >&2
  exit 1
fi

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

# ------------------------------------------------------------------------
# T1 — missing SENTRY_AUTH_TOKEN exits non-zero with clear message.
# ------------------------------------------------------------------------
echo "T1: missing SENTRY_AUTH_TOKEN"
set +e
out=$(env -i PATH="$PATH" HOME="$HOME" bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ "$rc" != "0" ]] && printf '%s' "$out" | grep -qi 'SENTRY_AUTH_TOKEN'; then
  pass "non-zero exit with token-name in stderr"
else
  fail "rc=$rc out=$out"
fi

# ------------------------------------------------------------------------
# T2 — region probe override: SENTRY_API_HOST short-circuits the probe.
# When SENTRY_API_HOST=de.sentry.io and fixtures are supplied, the script
# completes without any live network call and emits a report mentioning
# the EU host.
# ------------------------------------------------------------------------
echo "T2: region probe override (EU)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '[]' > "$TMP/monitors.json"
printf '[]' > "$TMP/rules.json"
set +e
out=$(SENTRY_AUTH_TOKEN=fake \
      SENTRY_ORG=jikigai \
      SENTRY_PROJECT=web-platform \
      SENTRY_API_HOST=de.sentry.io \
      SENTRY_FIXTURE_MONITORS="$TMP/monitors.json" \
      SENTRY_FIXTURE_RULES="$TMP/rules.json" \
      AUDIT_OUT_DIR="$TMP" \
      bash "$SCRIPT" 2>&1)
rc=$?
set -e
report=$(ls "$TMP"/sentry-migration-audit-*.md 2>/dev/null | head -1)
if [[ "$rc" == "0" ]] && [[ -f "$report" ]] && grep -q 'de.sentry.io' "$report"; then
  pass "EU host respected, report written"
else
  fail "rc=$rc report=$report"
fi

# ------------------------------------------------------------------------
# T3 — orphan join logic. Fixture: 2 monitors, 1 alert referencing slug A
# only. Expected: monitor B is orphan (no paired routing).
# ------------------------------------------------------------------------
echo "T3: orphan join — monitor without alert"
TMP3=$(mktemp -d)
cat > "$TMP3/monitors.json" <<'EOF'
[
  {"slug": "monitor-a", "name": "Monitor A", "type": "cron_job", "config": {"schedule": "0 * * * *"}},
  {"slug": "monitor-b", "name": "Monitor B", "type": "cron_job", "config": {"schedule": "0 0 * * *"}}
]
EOF
cat > "$TMP3/rules.json" <<'EOF'
[
  {"id": "1001", "name": "Alert for A", "conditions": [], "filters": [{"key":"monitor.slug","value":"monitor-a"}], "actions": []}
]
EOF
set +e
SENTRY_AUTH_TOKEN=fake \
  SENTRY_ORG=jikigai \
  SENTRY_PROJECT=web-platform \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP3/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP3/rules.json" \
  AUDIT_OUT_DIR="$TMP3" \
  bash "$SCRIPT" >/dev/null 2>&1
rc=$?
set -e
report=$(ls "$TMP3"/sentry-migration-audit-*.md 2>/dev/null | head -1)
if [[ "$rc" == "0" ]] && [[ -f "$report" ]] \
   && grep -qE '^\| monitor-b ' "$report" \
   && ! grep -qE '^\| monitor-a .* orphan' "$report"; then
  pass "monitor-b flagged as orphan, monitor-a not"
else
  fail "rc=$rc report contents:"
  [[ -f "$report" ]] && grep -A2 -E 'orphan|monitor-' "$report" >&2 || true
fi
rm -rf "$TMP3"

# ------------------------------------------------------------------------
# T4 — idempotency: same-day re-run overwrites prior report at the same
# path without corrupting it (no append, no double-render).
# ------------------------------------------------------------------------
echo "T4: same-day re-run overwrites cleanly"
TMP4=$(mktemp -d)
printf '[]' > "$TMP4/monitors.json"
printf '[]' > "$TMP4/rules.json"
for i in 1 2 3; do
  SENTRY_AUTH_TOKEN=fake \
    SENTRY_ORG=jikigai \
    SENTRY_PROJECT=web-platform \
    SENTRY_API_HOST=de.sentry.io \
    SENTRY_FIXTURE_MONITORS="$TMP4/monitors.json" \
    SENTRY_FIXTURE_RULES="$TMP4/rules.json" \
    AUDIT_OUT_DIR="$TMP4" \
    bash "$SCRIPT" >/dev/null 2>&1
done
n_reports=$(ls "$TMP4"/sentry-migration-audit-*.md 2>/dev/null | wc -l)
report=$(ls "$TMP4"/sentry-migration-audit-*.md 2>/dev/null | head -1)
n_headers=$(grep -c '^# Sentry Monitors/Alerts Migration Audit' "$report" 2>/dev/null || echo 99)
if [[ "$n_reports" == "1" ]] && [[ "$n_headers" == "1" ]]; then
  pass "exactly one report, exactly one header (no double-render)"
else
  fail "n_reports=$n_reports n_headers=$n_headers"
fi
rm -rf "$TMP4"

# ------------------------------------------------------------------------
# T5 — match-by-id: two monitors with the same name resolve as distinct
# entries (id is the discriminator, not name).
# ------------------------------------------------------------------------
echo "T5: duplicate-name monitors resolve by id"
TMP5=$(mktemp -d)
cat > "$TMP5/monitors.json" <<'EOF'
[
  {"slug": "dup-1", "name": "Same Name", "type": "cron_job", "config": {"schedule": "0 * * * *"}},
  {"slug": "dup-2", "name": "Same Name", "type": "cron_job", "config": {"schedule": "0 0 * * *"}}
]
EOF
printf '[]' > "$TMP5/rules.json"
SENTRY_AUTH_TOKEN=fake \
  SENTRY_ORG=jikigai \
  SENTRY_PROJECT=web-platform \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP5/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP5/rules.json" \
  AUDIT_OUT_DIR="$TMP5" \
  bash "$SCRIPT" >/dev/null 2>&1
report=$(ls "$TMP5"/sentry-migration-audit-*.md 2>/dev/null | head -1)
n_dup1=$(grep -cE '^\| dup-1 ' "$report" 2>/dev/null || echo 0)
n_dup2=$(grep -cE '^\| dup-2 ' "$report" 2>/dev/null || echo 0)
if [[ "$n_dup1" == "1" ]] && [[ "$n_dup2" == "1" ]]; then
  pass "both slugs present as distinct rows"
else
  fail "n_dup1=$n_dup1 n_dup2=$n_dup2"
fi
rm -rf "$TMP5"

# ------------------------------------------------------------------------
# T6 — machine-readable id JSON tail: report contains an HTML-comment
# manifest of rule ids (per plan Phase 2.1) so Phase 5 import can consume
# it without dashboard scraping.
# ------------------------------------------------------------------------
echo "T6: machine-readable id manifest"
TMP6=$(mktemp -d)
printf '[]' > "$TMP6/monitors.json"
cat > "$TMP6/rules.json" <<'EOF'
[
  {"id": "9001", "name": "auth-exchange-code-burst", "conditions": [], "filters": [], "actions": []},
  {"id": "9002", "name": "auth-signout-burst", "conditions": [], "filters": [], "actions": []}
]
EOF
SENTRY_AUTH_TOKEN=fake \
  SENTRY_ORG=jikigai \
  SENTRY_PROJECT=web-platform \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP6/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP6/rules.json" \
  AUDIT_OUT_DIR="$TMP6" \
  bash "$SCRIPT" >/dev/null 2>&1
report=$(ls "$TMP6"/sentry-migration-audit-*.md 2>/dev/null | head -1)
if grep -qE '<!-- ids: \[.*"9001".*"9002".*\] -->' "$report"; then
  pass "id manifest emitted with both ids"
else
  fail "manifest missing or malformed in $report"
fi
rm -rf "$TMP6"

# ------------------------------------------------------------------------
echo
echo "Results: $PASS passed, $FAIL failed"
exit $((FAIL > 0 ? 1 : 0))
