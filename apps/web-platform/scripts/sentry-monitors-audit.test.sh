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
   && grep -qE 'monitor-b.*orphan: not referenced' "$report" \
   && ! grep -qE 'monitor-a.*orphan: not referenced' "$report"; then
  pass "monitor-b flagged as Class A orphan, monitor-a not"
else
  fail "rc=$rc"
  if [[ -f "$report" ]]; then
    echo "    --- ## Orphans section dump ---" >&2
    sed -n '/^## Orphans/,/^## /{p}' "$report" | head -30 >&2
  fi
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
# Pin AUDIT_DATE_OVERRIDE so the three invocations cannot straddle midnight
# UTC and produce two dated reports under heavy CI scheduling.
for i in 1 2 3; do
  SENTRY_AUTH_TOKEN=fake \
    SENTRY_ORG=jikigai \
    SENTRY_PROJECT=web-platform \
    SENTRY_API_HOST=de.sentry.io \
    SENTRY_FIXTURE_MONITORS="$TMP4/monitors.json" \
    SENTRY_FIXTURE_RULES="$TMP4/rules.json" \
    AUDIT_OUT_DIR="$TMP4" \
    AUDIT_DATE_OVERRIDE="2026-05-15" \
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
# Parse the manifest as JSON rather than byte-regexp — decouples test from
# quoting/spacing quirks of jq's compact form.
manifest_line=$(grep -oE '<!-- ids: .* -->' "$report" 2>/dev/null | head -1)
manifest_json=$(printf '%s' "$manifest_line" | sed -E 's/^<!-- ids: //;s/ -->$//')
if [[ -n "$manifest_json" ]] && \
   printf '%s' "$manifest_json" | jq -e 'type == "array" and (index("9001")) and (index("9002"))' >/dev/null 2>&1; then
  pass "id manifest parses as JSON array containing both ids"
else
  fail "manifest parse failed"
  echo "    --- last 3 lines of report ---" >&2
  tail -3 "$report" >&2 2>/dev/null || true
fi
rm -rf "$TMP6"

# ------------------------------------------------------------------------
# T7 — Manifest ↔ README import-procedure handshake. Pipe the script's
# emitted manifest through the same `grep|sed|tr|tr` pipeline the README's
# import runbook uses, and assert the resulting whitespace-separated id
# list matches the rules fixture. Catches drift in either direction.
# ------------------------------------------------------------------------
echo "T7: manifest survives README's extraction pipeline"
TMP7=$(mktemp -d)
printf '[]' > "$TMP7/monitors.json"
cat > "$TMP7/rules.json" <<'EOF'
[
  {"id": "1234", "name": "auth-exchange-code-burst", "conditions": [], "filters": [], "actions": [{"id":"NotifyEmailAction"}]},
  {"id": "5678", "name": "auth-callback-no-code-burst", "conditions": [], "filters": [], "actions": [{"id":"NotifyEmailAction"}]}
]
EOF
SENTRY_AUTH_TOKEN=fake \
  SENTRY_ORG=jikigai \
  SENTRY_PROJECT=web-platform \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP7/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP7/rules.json" \
  AUDIT_OUT_DIR="$TMP7" \
  bash "$SCRIPT" >/dev/null 2>&1
report=$(ls "$TMP7"/sentry-migration-audit-*.md 2>/dev/null | head -1)
# Mirror README import-procedure extraction byte-for-byte:
ids=$(grep -oE '<!-- ids: \[(.*)\] -->' "$report" | head -1 | \
      sed -E 's/.*\[//;s/\].*//' | tr -d '"' | tr ',' ' ')
ids_sorted=$(printf '%s\n' $ids | sort | tr '\n' ' ' | sed 's/ $//')
if [[ "$ids_sorted" == "1234 5678" ]]; then
  pass "README extraction yields exactly the fixture's rule ids"
else
  fail "extraction yielded: '$ids_sorted' (expected '1234 5678')"
  echo "    --- manifest line ---" >&2
  grep '<!-- ids:' "$report" >&2 2>/dev/null || true
fi
rm -rf "$TMP7"

# ------------------------------------------------------------------------
# T8 — Class B orphan detection (alert references missing monitor).
# Plan §2.1.5 enumerated three classes; the script previously only emitted
# Class A. Class B is required for the runbook to be load-bearing.
# ------------------------------------------------------------------------
echo "T8: Class B orphan — alert references missing monitor"
TMP8=$(mktemp -d)
cat > "$TMP8/monitors.json" <<'EOF'
[
  {"slug": "live-monitor", "name": "Live", "type": "cron_job", "config": {"schedule": "0 * * * *"}}
]
EOF
cat > "$TMP8/rules.json" <<'EOF'
[
  {"id": "9100", "name": "Alert for ghost", "conditions": [], "filters": [{"key":"monitor.slug","value":"ghost-monitor"}], "actions": [{"id":"NotifyEmailAction"}]}
]
EOF
SENTRY_AUTH_TOKEN=fake \
  SENTRY_ORG=jikigai \
  SENTRY_PROJECT=web-platform \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP8/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP8/rules.json" \
  AUDIT_OUT_DIR="$TMP8" \
  bash "$SCRIPT" >/dev/null 2>&1
report=$(ls "$TMP8"/sentry-migration-audit-*.md 2>/dev/null | head -1)
if grep -qE 'Class B' "$report" && grep -qE '`ghost-monitor`' "$report"; then
  pass "Class B orphan 'ghost-monitor' detected"
else
  fail "Class B section missing or ghost-monitor not flagged"
  sed -n '/^## Orphans/,/^## /p' "$report" >&2 2>/dev/null || true
fi
rm -rf "$TMP8"

# ------------------------------------------------------------------------
# T9 — Class C orphan detection (alert with empty actions[]).
# Covers the UI-side regression where an operator removes the action target
# from a Sentry alert and Terraform's lifecycle.ignore_changes hides the
# drift.
# ------------------------------------------------------------------------
echo "T9: Class C orphan — alert with empty actions[]"
TMP9=$(mktemp -d)
printf '[]' > "$TMP9/monitors.json"
cat > "$TMP9/rules.json" <<'EOF'
[
  {"id": "7777", "name": "auth-exchange-code-burst", "conditions": [], "filters": [], "actions": []},
  {"id": "7778", "name": "auth-signout-burst",     "conditions": [], "filters": [], "actions": [{"id":"NotifyEmailAction"}]}
]
EOF
SENTRY_AUTH_TOKEN=fake \
  SENTRY_ORG=jikigai \
  SENTRY_PROJECT=web-platform \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP9/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP9/rules.json" \
  AUDIT_OUT_DIR="$TMP9" \
  bash "$SCRIPT" >/dev/null 2>&1
report=$(ls "$TMP9"/sentry-migration-audit-*.md 2>/dev/null | head -1)
if grep -qE 'Class C' "$report" && grep -qE 'rule id `7777`' "$report" && ! grep -qE 'rule id `7778`' "$report"; then
  pass "Class C flagged 7777 (empty actions), not 7778 (has action)"
else
  fail "Class C detection mis-fired"
  sed -n '/^## Orphans/,/^## /p' "$report" >&2 2>/dev/null || true
fi
rm -rf "$TMP9"

# ------------------------------------------------------------------------
# T10 — Non-numeric rule ids are filtered from the manifest. Defense-in-
# depth against a compromised Sentry response shipping shell metacharacters.
# ------------------------------------------------------------------------
echo "T10: non-numeric rule ids filtered from manifest"
TMP10=$(mktemp -d)
printf '[]' > "$TMP10/monitors.json"
cat > "$TMP10/rules.json" <<'EOF'
[
  {"id": "1234", "name": "good", "conditions": [], "filters": [], "actions": [{"id":"NotifyEmailAction"}]},
  {"id": "1; rm -rf .", "name": "evil", "conditions": [], "filters": [], "actions": [{"id":"NotifyEmailAction"}]},
  {"id": "abc", "name": "stringy", "conditions": [], "filters": [], "actions": [{"id":"NotifyEmailAction"}]}
]
EOF
SENTRY_AUTH_TOKEN=fake \
  SENTRY_ORG=jikigai \
  SENTRY_PROJECT=web-platform \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP10/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP10/rules.json" \
  AUDIT_OUT_DIR="$TMP10" \
  bash "$SCRIPT" >/dev/null 2>&1
report=$(ls "$TMP10"/sentry-migration-audit-*.md 2>/dev/null | head -1)
manifest_json=$(grep -oE '<!-- ids: .* -->' "$report" | head -1 | sed -E 's/^<!-- ids: //;s/ -->$//')
if printf '%s' "$manifest_json" | jq -e '. == ["1234"]' >/dev/null 2>&1; then
  pass "manifest contains only the numeric id"
else
  fail "manifest = $manifest_json (expected exactly [\"1234\"])"
fi
rm -rf "$TMP10"

# ------------------------------------------------------------------------
# T11 — Class B narrow extraction: a `TaggedEventFilter`-shaped rule
# whose `key` is NOT `monitor.slug` must NOT produce a Class B orphan,
# even if its `value` happens to be kebab-shaped (matches the regex used
# by the existing slug-shape guard). Mirrors the production rule shape
# emitted by `apps/web-platform/scripts/configure-sentry-alerts.sh`
# (filters carry `{"key":"feature","value":"auth"}` etc.).
# ------------------------------------------------------------------------
echo "T11: Class B narrow extraction — generic TaggedEventFilter does not false-flag"
TMP11=$(mktemp -d)
cat > "$TMP11/monitors.json" <<'EOF'
[
  {"slug": "scheduled-daily-triage", "name": "Daily triage", "type": "cron_job", "config": {"schedule": "0 4 * * *"}}
]
EOF
cat > "$TMP11/rules.json" <<'EOF'
[
  {
    "id": "9200",
    "name": "auth-exchange-code-burst",
    "conditions": [{"id":"sentry.rules.conditions.event_frequency.EventFrequencyCondition","value":50}],
    "filters": [
      {"id":"sentry.rules.filters.tagged_event.TaggedEventFilter","key":"feature","match":"eq","value":"auth"},
      {"id":"sentry.rules.filters.tagged_event.TaggedEventFilter","key":"action","match":"eq","value":"exchangeCodeForSession"}
    ],
    "actions": [{"id":"NotifyEmailAction"}]
  }
]
EOF
SENTRY_AUTH_TOKEN=fake \
  SENTRY_ORG=jikigai \
  SENTRY_PROJECT=web-platform \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP11/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP11/rules.json" \
  AUDIT_OUT_DIR="$TMP11" \
  bash "$SCRIPT" >/dev/null 2>&1
report=$(ls "$TMP11"/sentry-migration-audit-*.md 2>/dev/null | head -1)
# `auth` is a tag-filter value, NOT a monitor.slug binding. The narrow
# extraction must skip it. Anything containing "Class B" or a backtick-
# wrapped `auth` orphan ref is a false-positive regression.
if [[ -f "$report" ]] \
   && ! grep -qE 'Class B' "$report" \
   && ! grep -qE '`auth`' "$report"; then
  pass "tag-filter value 'auth' did not flag as Class B orphan"
else
  fail "tag-filter value false-flagged as Class B"
  sed -n '/^## Orphans/,/^## /p' "$report" >&2 2>/dev/null || true
fi
rm -rf "$TMP11"

# ------------------------------------------------------------------------
# T12 — Class C shape-branch: Metric Alerts store routing under
# `.triggers[].actions[]`, not top-level `.actions[]`. A Metric Alert with
# non-empty `triggers[].actions[]` must NOT flag as Class C; a Metric
# Alert whose triggers all have empty actions[] (paging unpaired by 2026
# auto-migration) MUST flag. Without the shape branch every Metric Alert
# false-positives because `.actions // []` is `[]`.
# ------------------------------------------------------------------------
echo "T12: Class C alert-shape branch — Metric Alert routing handled"
TMP12=$(mktemp -d)
printf '[]' > "$TMP12/monitors.json"
cat > "$TMP12/rules.json" <<'EOF'
[
  {
    "id": "8001",
    "name": "metric-alert-with-routing",
    "triggers": [
      {"label": "critical", "actions": [{"id":"sentry.integrations.slack","targetIdentifier":"#alerts"}]}
    ]
  },
  {
    "id": "8002",
    "name": "metric-alert-orphan-routing",
    "triggers": [
      {"label": "critical", "actions": []}
    ]
  },
  {
    "id": "8003",
    "name": "issue-alert-has-routing",
    "conditions": [],
    "filters": [],
    "actions": [{"id":"NotifyEmailAction"}]
  }
]
EOF
SENTRY_AUTH_TOKEN=fake \
  SENTRY_ORG=jikigai \
  SENTRY_PROJECT=web-platform \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP12/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP12/rules.json" \
  AUDIT_OUT_DIR="$TMP12" \
  bash "$SCRIPT" >/dev/null 2>&1
report=$(ls "$TMP12"/sentry-migration-audit-*.md 2>/dev/null | head -1)
# 8002 has the unpaired routing → MUST flag. 8001 has routing → MUST NOT
# flag. 8003 is an Issue Alert WITH routing → MUST NOT flag (regression
# guard for the existing T9 contract).
if grep -qE 'rule id `8002`' "$report" \
   && ! grep -qE 'rule id `8001`' "$report" \
   && ! grep -qE 'rule id `8003`' "$report"; then
  pass "8002 (unpaired Metric Alert) flagged; 8001/8003 (paired) not flagged"
else
  fail "Class C shape branch mis-fired"
  sed -n '/^## Orphans/,/^## /p' "$report" >&2 2>/dev/null || true
fi
rm -rf "$TMP12"

# ------------------------------------------------------------------------
echo
echo "Results: $PASS passed, $FAIL failed"
exit $((FAIL > 0 ? 1 : 0))
