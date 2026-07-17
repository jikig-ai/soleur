#!/usr/bin/env bash
# Tests for scripts/expenses-verify-by-check.sh (#6602).
#
# Exit-code harness (mirrors zot-soak-6122.test.sh / sweep-followthroughs.test.sh):
#   RED       — an expired marker → exit 1, offending row named on stdout.
#   GREEN     — a future-dated marker → exit 0.
#   ANOMALY   — bad date / missing owner / missing source / pipe in source → exit 2.
#   POSITIVE  — a ledger WITH markers parses >=1 (a broken parser that reads every
#               row as "no verify_by" must NOT read as a clean exit-0 all-clear);
#               and a candidate-marker line the parser cannot extract → exit 2.
#
# Fixtures are derived from the REAL expenses.md row shape (a pipe-delimited
# markdown table row whose Notes cell embeds the HTML-comment marker), not
# synthesized from nothing, per
# learnings/best-practices/2026-07-12-dry-run-fixture-must-derive-from-producer-source.
#
# Dates are computed relative to `date -u` so the suite stays valid in
# perpetuity (a hardcoded 2026 "future" date would flip to "past" and redden
# the suite for the next contributor — the git-show-main baseline-flip class).
#
# Run: bash scripts/expenses-verify-by-check.test.sh

set -euo pipefail

command -v date >/dev/null 2>&1 || { echo "SKIP: date missing"; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/expenses-verify-by-check.sh"

PAST=$(date -u -d '30 days ago' +%Y-%m-%d 2>/dev/null || date -u -v-30d +%Y-%m-%d)
FUTURE=$(date -u -d '365 days' +%Y-%m-%d 2>/dev/null || date -u -v+365d +%Y-%m-%d)

PASS=0
FAIL=0
TOTAL=0

TMPROOT=$(mktemp -d -t expenses-verify-by.XXXXXXXX)
trap 'rm -rf "$TMPROOT"' EXIT

# Write a minimal but real-shaped ledger; $1=file, $2..=Notes-cell markers (one row each).
make_ledger() {
  local file="$1"; shift
  {
    echo "# Expenses"
    echo ""
    echo "## Recurring"
    echo ""
    echo "| Service | Provider | Category | Amount | Status | Renewal Date | Notes |"
    echo "|---------|----------|----------|--------|--------|--------------|-------|"
    # A non-estimate row (verified, no marker) — must be ignored.
    echo "| Sentry Team | Sentry | observability | 71.22 | active | 2026-06-17 | live-verified, no marker |"
    local note
    for note in "$@"; do
      echo "| Resend | Resend | email | 20.00 | active | - | Pro upgrade estimate. $note |"
    done
  } > "$file"
}

run_sut() {
  # echoes: "<rc>\t<stdout+stderr>"
  local ledger="$1" out rc=0
  out=$(bash "$SUT" "$ledger" 2>&1) || rc=$?
  printf '%s\t%s' "$rc" "$out"
}

assert_rc() {
  local name="$1" expected_rc="$2" ledger="$3" needle="${4:-}"
  local res rc out
  res=$(run_sut "$ledger")
  rc="${res%%$'\t'*}"
  out="${res#*$'\t'}"
  local ok=1
  [[ "$rc" == "$expected_rc" ]] || ok=0
  if [[ -n "$needle" && "$out" != *"$needle"* ]]; then ok=0; fi
  if [[ "$ok" == "1" ]]; then
    echo "PASS: $name (rc=$rc)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  expected rc=$expected_rc${needle:+, output containing: $needle}"
    echo "  actual   rc=$rc"
    echo "  output: ${out:0:800}"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
}

# --- Scenario 1: RED — expired marker → exit 1, row named ---
L="$TMPROOT/red.md"
make_ledger "$L" "<!-- estimate verify_by=$PAST owner=cfo source=\"Resend Pro invoice email in ops@soleur.ai\" -->"
assert_rc "RED expired → exit 1" 1 "$L" "verify_by=$PAST"

# --- Scenario 2: GREEN — future marker → exit 0 ---
L="$TMPROOT/green.md"
make_ledger "$L" "<!-- estimate verify_by=$FUTURE owner=cfo source=\"Resend Pro invoice email in ops@soleur.ai\" -->"
assert_rc "GREEN future → exit 0" 0 "$L" "none past verify_by"

# --- Scenario 3: ANOMALY — bad date / missing owner / missing source / pipe ---
L="$TMPROOT/anomaly-date.md"
make_ledger "$L" "<!-- estimate verify_by=notadate owner=cfo source=\"x\" -->"
assert_rc "ANOMALY bad date → exit 2" 2 "$L" "bad verify_by"

L="$TMPROOT/anomaly-owner.md"
make_ledger "$L" "<!-- estimate verify_by=$FUTURE source=\"x\" -->"
assert_rc "ANOMALY missing owner → exit 2" 2 "$L" "missing owner"

L="$TMPROOT/anomaly-source.md"
make_ledger "$L" "<!-- estimate verify_by=$FUTURE owner=cfo -->"
assert_rc "ANOMALY missing source → exit 2" 2 "$L" "missing or empty source"

# Pipe in source: written raw (breaks the table cell) → anomaly. Build by hand
# so the pipe lands inside the marker's source= value.
L="$TMPROOT/anomaly-pipe.md"
{
  echo "| Service | Provider | Category | Amount | Status | Renewal Date | Notes |"
  echo "|---------|----------|----------|--------|--------|--------------|-------|"
  echo "| Resend | Resend | email | 20.00 | active | - | est <!-- estimate verify_by=$FUTURE owner=cfo source=\"a|b\" --> |"
} > "$L"
assert_rc "ANOMALY pipe in source → exit 2" 2 "$L" "pipe in marker"

# --- Scenario 4: POSITIVE-SAMPLE guard ---
# (a) A ledger WITH multiple well-formed future markers parses >=1 and is clean.
L="$TMPROOT/positive.md"
make_ledger "$L" \
  "<!-- estimate verify_by=$FUTURE owner=cfo source=\"Resend invoice\" -->" \
  "<!-- estimate verify_by=$FUTURE owner=cfo source=\"Hetzner invoice\" -->"
assert_rc "POSITIVE parses >=1 (not false all-clear)" 0 "$L" "parsed_ok=2"

# (b) A candidate marker line the parser cannot extract must NOT read as clean.
#     Simulate a broken/truncated marker: the `<!-- estimate ` token is present
#     but there is no closing `-->` on the line → unextractable → anomaly.
L="$TMPROOT/broken-parser.md"
{
  echo "| Service | Provider | Category | Amount | Status | Renewal Date | Notes |"
  echo "|---------|----------|----------|--------|--------|--------------|-------|"
  echo "| Resend | Resend | email | 20.00 | active | - | est <!-- estimate verify_by=$FUTURE owner=cfo source=\"x\" |"
} > "$L"
assert_rc "POSITIVE broken candidate → exit 2 (no false all-clear)" 2 "$L" "anomaly"

# --- Regression: a ledger with ZERO markers is an explicit clean-zero state ---
L="$TMPROOT/zero.md"
make_ledger "$L"  # no marker rows
assert_rc "ZERO markers → exit 0 (explicit zero state)" 0 "$L" "0 estimate markers"

echo ""
echo "expenses-verify-by-check.test.sh: $PASS/$TOTAL passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
