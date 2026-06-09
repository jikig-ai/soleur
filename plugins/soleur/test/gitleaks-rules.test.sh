#!/usr/bin/env bash
# Pins the custom gitleaks rules in .gitleaks.toml against synthesized
# fixtures (#5079). Two non-obvious decisions are asserted:
#   1. The custom Slack rule is named `soleur-slack-webhook-url` so it ADDS to
#      the default-pack `slack-webhook-url` rule instead of shadowing it —
#      same-id child rules REPLACE default rules under [extend] useDefault,
#      which would silently drop /workflows/ webhook detection and apply our
#      per-rule allowlists to the default rule.
#   2. The second path segment is [A-Z0-9]+ (not hardcoded /B) — Slack does
#      not contractually guarantee a B prefix across webhook generations.
# All fixture URLs are synthesized (cq-test-fixtures-synthesized-only).
# Run via:  bash plugins/soleur/test/gitleaks-rules.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CONFIG="$REPO_ROOT/.gitleaks.toml"

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "SKIP: gitleaks not installed (CI secret-scan job runs the pinned binary)"
  exit 0
fi

PASS=0
FAIL=0
fail() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}
pass() {
  echo "  pass: $1"
  PASS=$((PASS + 1))
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Fixture URLs are assembled from parts at runtime so no contiguous
# secret-shaped literal exists in this source file (GitHub push protection
# and the repo's own gitleaks scan would both flag it otherwise).
SLACK_BASE="https://hooks.slack"
SLACK_BASE="${SLACK_BASE}.com"
FAKE_TOKEN="aaaabbbbccccdddd"
FAKE_TOKEN="${FAKE_TOKEN}eeeeffff"
DC_BASE="https://discord"
DC_BASE="${DC_BASE}.com/api/webhooks"
# 64 synthesized chars built by repetition — no >16-char contiguous literal.
DC_TOKEN="SYNTH$(printf 'aBc9%.0s' {1..14})xyz"

# scan_rules <fixture-line> -> newline-separated RuleIDs that fired
scan_rules() {
  local fixture_dir="$TMP/scan.$RANDOM"
  mkdir -p "$fixture_dir"
  printf '%s\n' "$1" > "$fixture_dir/fixture.txt"
  gitleaks dir "$fixture_dir" --config "$CONFIG" --no-banner \
    --report-format json --report-path "$fixture_dir/report.json" >/dev/null 2>&1
  jq -r '.[].RuleID' "$fixture_dir/report.json" 2>/dev/null | sort -u
}

echo "=== gitleaks custom-rule fixture tests ==="
echo ""

echo "T1: canonical /services/ Slack webhook fires BOTH rules (no default shadowing)"
rules=$(scan_rules "${SLACK_BASE}/services/T0000FAKE/B0000FAKE/${FAKE_TOKEN}")
if grep -qx 'soleur-slack-webhook-url' <<<"$rules"; then
  pass "soleur-slack-webhook-url fires"
else
  fail "soleur-slack-webhook-url must fire (got: ${rules:-<none>})"
fi
if grep -qx 'slack-webhook-url' <<<"$rules"; then
  pass "default-pack slack-webhook-url still live (rename did not shadow it)"
else
  fail "default-pack slack-webhook-url must also fire (got: ${rules:-<none>})"
fi

echo "T2: non-B second segment still detected by the custom rule"
rules=$(scan_rules "${SLACK_BASE}/services/T0000FAKE/XQ99ZZ11Y/${FAKE_TOKEN}")
if grep -qx 'soleur-slack-webhook-url' <<<"$rules"; then
  pass "non-B segment fires soleur-slack-webhook-url"
else
  fail "non-B segment must fire soleur-slack-webhook-url (got: ${rules:-<none>})"
fi

echo "T3: /workflows/ webhook covered by the unshadowed default rule"
rules=$(scan_rules "${SLACK_BASE}/workflows/T0000FAKE/A0000FAKE/11111111/${FAKE_TOKEN}")
if grep -qx 'slack-webhook-url' <<<"$rules"; then
  pass "/workflows/ URL fires default slack-webhook-url"
else
  fail "/workflows/ URL must fire the default rule (got: ${rules:-<none>})"
fi

echo "T4: Discord webhook rule still fires"
rules=$(scan_rules "${DC_BASE}/000000000000000001/${DC_TOKEN}")
if grep -qx 'discord-webhook-url' <<<"$rules"; then
  pass "discord-webhook-url fires"
else
  fail "discord-webhook-url must fire (got: ${rules:-<none>})"
fi

echo "T5: benign content fires nothing"
rules=$(scan_rules 'release notes link: https://github.com/jikig-ai/soleur/releases/tag/v1.0.0')
if [[ -z "$rules" ]]; then
  pass "no rule fires on benign content"
else
  fail "benign content must not fire (got: $rules)"
fi

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
