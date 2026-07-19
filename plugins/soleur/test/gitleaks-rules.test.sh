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
# Same split-literal reason as above: this file is NOT in the
# database-url-with-password path allowlist, so a contiguous credential-shaped
# DSN literal here trips our own rule. Only the angle-bracket placeholder form
# `postgres://<user>:<pw>@host` is safe to write out in full.
# BOTH schemes are assembled at runtime. Interpolating a shell variable into the
# password position does NOT make a line safe: `$`, `{` and `}` all sit inside the
# rule's password class `[^@/\s]+`, so a scheme+user+$VAR+@host line still matches.
# Keep every DSN in this file either fully assembled at runtime or in the
# angle-bracket placeholder form.
PG="postgres"
PGQL="${PG}ql://"
PG="${PG}://"

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

echo "T6: documentation placeholder shapes stay allowlisted (#6706)"
# The shapes the rule is MEANT to permit. This is the pre-existing allowlist —
# #6706 deliberately does NOT widen it (see T7's note).
for ph in "user:password" "USER:PASSWORD" "postgres:secret" "<user>:<pw>" "user:***"; do
  rules=$(scan_rules "${PG}${ph}@db.example.com")
  if grep -qx 'database-url-with-password' <<<"$rules"; then
    fail "placeholder ${ph} must stay allowlisted (rule fired)"
  else
    pass "placeholder ${ph} quiet"
  fi
done

echo "T7: real credentials still fire — one VARIED dimension per row (#6706)"
# T7 is also T6's POSITIVE CONTROL. T6 is a pure must-not-fire block, so it
# passes vacuously whenever the scanner is degraded (e.g. `jq` missing =>
# scan_rules returns empty for every input, so every T6 row "passes"). T7 is the
# must-fire half that goes loud in exactly that case. Do not delete or skip T7
# without replacing that control, or T6 silently becomes a permanent no-op.
#
# Each row holds every dimension at a known-good value and varies exactly ONE.
# Sampling a single point per dimension is what makes a guard like this vacuous:
# with all rows sharing one host/scheme/user, mutating the rule's host class,
# dropping `postgresql://`, or adding a password length floor each leave the
# suite fully green while real credentials go undetected.
REALPW="Xk9tR2m"          # split so no contiguous credential literal lives here
REALPW="${REALPW}Qw7vLp4Zc"
for row in \
  "USER-side|${PG}postgres:${REALPW}@db.example.com" \
  "host|${PG}user:${REALPW}@prod.internal.corp" \
  "scheme-ql|${PGQL}user:${REALPW}@db.example.com" \
  "short-password|${PG}user:pw2@db.example.com" \
  "placeholder-prefix-only|${PG}user:pass-but-longer@db.example.com" \
  ; do
  label="${row%%|*}"
  fixture="${row#*|}"
  rules=$(scan_rules "$fixture")
  if grep -qx 'database-url-with-password' <<<"$rules"; then
    pass "real credential still fires (${label})"
  else
    fail "real credential MUST fire (${label}) — rule regex or allowlist over-matches"
  fi
done

echo "T8: the placeholder allowlist stays a SINGLE entry"
# Arity guard. Every behavioural row above tests the SHAPE of one regex; none can
# see a SECOND array element being appended. That is the cheapest real escape:
# generalising the Supabase-CLI loopback carve-out into a broad
# `postgres://postgres:<anything>@` branch silences production credentials while
# T6/T7 stay entirely green. Block-scoped with an explicit `[[rules]]` terminator
# so a sibling rule's `regexes` line cannot be swallowed into the count.
db_block=$(awk '/^id = "database-url-with-password"/{f=1; next} f && /^\[\[rules\]\]/{exit} f{print}' "$CONFIG")
regexes_line=$(grep '^  regexes = ' <<<"$db_block" || true)
regexes_count=$(grep -c '^  regexes = ' <<<"$db_block" || true)
# 2 triple-quote runs == exactly one '''...''' element.
quote_runs=$(grep -o "'''" <<<"$regexes_line" | wc -l | tr -d ' ')
if [[ "$regexes_count" == "1" && "$quote_runs" == "2" ]]; then
  pass "database-url-with-password carries exactly one regexes entry"
else
  fail "expected 1 regexes line holding 1 entry; got lines=${regexes_count} quote_runs=${quote_runs} (2 == one entry)"
fi

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
