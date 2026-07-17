#!/usr/bin/env bash
# expenses-verify-by-check — deterministic expiry gate for machine-readable
# `verify_by` estimate markers in the expense ledger (#6602).
#
# THE DEFECT THIS CATCHES (the #6589 class): an unverified estimate whose
# implied "verify on next invoice" window has silently passed. The Sentry row
# sat 78% wrong for five weeks because its prose TODO carried no date, no owner,
# and nothing fired when the estimate outlived its own verification window. This
# check parses the ledger, finds estimate rows whose `verify_by` has passed, and
# FAILS LOUD (exit 1, offending rows named). It is the complementary control to
# #6584's existence-based parity gate: parity checks whether a row is PRESENT;
# this checks whether a present row's amount has EXPIRED its verification date.
#
# Marker schema (in the Notes cell of knowledge-base/operations/expenses.md):
#   <!-- estimate verify_by=YYYY-MM-DD owner=<role> source="<named invoice/endpoint>" -->
#   - The marker IS the estimate flag: a row is an estimate iff it carries one.
#     Verifying a figure against a live source REMOVES the marker (the Sentry row
#     carries none). So verify_by/owner/source are the single source of truth.
#   - All three fields REQUIRED. No `|` anywhere in the marker (a pipe breaks the
#     markdown table cell). Missing field / bad date / pipe → anomaly (exit 2).
#
# Parsing strategy: grep the marker token position-independently (a leading `|`
# in a pipe-delimited table shifts awk column offsets — matching the marker
# directly sidesteps that trap entirely, per
# learnings/2026-05-26-awk-pipe-delimited-markdown-table-column-offset.md).
#
# Exit codes (consumed by scheduled-expenses-verify-by.yml):
#   0  clean  — no expired markers (an explicit "0 estimates in ledger" is clean)
#   1  expired — >=1 marker's verify_by has passed (offending rows named on stdout)
#   2  anomaly — malformed marker (missing owner/source, bad date, pipe in marker)
#               OR a broken-parser positive-sample failure (candidate marker lines
#               present but zero extracted). Never a silent skip.
#
# Usage: expenses-verify-by-check.sh [LEDGER_PATH]
#   LEDGER_PATH defaults to knowledge-base/operations/expenses.md (repo-relative).
#   The test harness passes fixture ledgers here.
#
# BASH_SOURCE-guarded so the test can source it without running main()
# (mirrors sweep-followthroughs.sh / zot-soak-6122.sh).

set -euo pipefail

DEFAULT_LEDGER="knowledge-base/operations/expenses.md"

# Extract the marker substring from a single ledger line, or empty if none.
# Greedy `.*-->` is correct for the one-marker-per-row invariant.
# `|| true` inside the substitution: grep exits 1 on no-match, and under `set -e`
# a non-zero command substitution aborts the WHOLE script before the caller can
# record the anomaly (AGENTS.md accumulate-then-exit foot-gun). An empty result
# is a legitimate "no marker" signal here, not a failure.
extract_marker() {
  { printf '%s' "$1" | grep -oE '<!--[[:space:]]*estimate[[:space:]].*-->' | head -1; } || true
}

# Field extractors. Each echoes the field value or empty (|| true, same reason).
marker_field() {
  # $1 = marker text, $2 = field name (verify_by|owner)
  { printf '%s' "$1" | grep -oE "$2=[^[:space:]]+" | head -1 | sed "s/^$2=//"; } || true
}
marker_source() {
  # source is quoted: source="..."
  { printf '%s' "$1" | grep -oE 'source="[^"]*"' | head -1 | sed -E 's/^source="//; s/"$//'; } || true
}

# Validate + classify a single marker. Echoes one of:
#   ok|<verify_by>|<owner>|<source>
#   anomaly|<reason>
classify_marker() {
  local marker="$1"

  # A pipe ANYWHERE in the marker breaks the table cell — hard anomaly.
  if [[ "$marker" == *"|"* ]]; then
    echo "anomaly|pipe in marker"
    return
  fi

  local vb owner src
  vb=$(marker_field "$marker" "verify_by")
  owner=$(marker_field "$marker" "owner")
  src=$(marker_source "$marker")

  [[ -z "$vb" ]]    && { echo "anomaly|missing verify_by"; return; }
  [[ -z "$owner" ]] && { echo "anomaly|missing owner"; return; }
  # source="" (present but empty) is allowed to be caught: require non-empty.
  if ! printf '%s' "$marker" | grep -qE 'source="[^"]+"'; then
    echo "anomaly|missing or empty source"
    return
  fi

  # Strict ISO date shape, then a real-calendar check via date(1).
  if [[ ! "$vb" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "anomaly|bad verify_by date '$vb'"
    return
  fi
  if ! date -u -d "$vb" +%s >/dev/null 2>&1; then
    echo "anomaly|bad verify_by date '$vb'"
    return
  fi

  echo "ok|$vb|$owner|$src"
}

# Best-effort service name for a ledger row (first pipe-delimited cell), for
# human-readable offender output. Column-offset-tolerant: trims the leading `|`.
row_service() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]*\|?[[:space:]]*//; s/[[:space:]]*\|.*$//'
}

main() {
  local ledger="${1:-$DEFAULT_LEDGER}"

  if [[ ! -f "$ledger" ]]; then
    echo "::error:: ledger not found: $ledger" >&2
    echo "anomaly: ledger file missing" >&2
    return 2
  fi

  local today today_epoch
  today=$(date -u +%Y-%m-%d)
  today_epoch=$(date -u -d "$today" +%s)

  # LOOSE candidate count: every line that looks like it carries a marker.
  # Positive-sample guard: each candidate MUST yield an extractable marker;
  # a candidate that doesn't extract is a broken-parser anomaly, not a skip.
  local candidates=0 parsed=0 expired=0 anomalies=0
  local -a expired_rows=() anomaly_rows=()

  while IFS= read -r line; do
    candidates=$((candidates + 1))
    local marker
    marker=$(extract_marker "$line")
    if [[ -z "$marker" ]]; then
      anomalies=$((anomalies + 1))
      anomaly_rows+=("$(row_service "$line") — candidate line but no extractable marker (parser/format anomaly)")
      continue
    fi

    local verdict
    verdict=$(classify_marker "$marker")
    if [[ "$verdict" == anomaly\|* ]]; then
      anomalies=$((anomalies + 1))
      anomaly_rows+=("$(row_service "$line") — ${verdict#anomaly|}")
      continue
    fi

    parsed=$((parsed + 1))
    # verdict = ok|<vb>|<owner>|<src>
    local vb owner src vb_epoch
    IFS='|' read -r _ vb owner src <<<"$verdict"
    vb_epoch=$(date -u -d "$vb" +%s)
    if (( today_epoch > vb_epoch )); then
      expired=$((expired + 1))
      expired_rows+=("$(row_service "$line") | verify_by=$vb | owner=$owner | source=\"$src\"")
    fi
  done < <(grep -nE '<!--[[:space:]]*estimate[[:space:]]' "$ledger" | sed -E 's/^[0-9]+://')

  echo "expenses-verify-by-check: ledger=$ledger today=$today (UTC)"
  echo "  markers: candidates=$candidates parsed_ok=$parsed expired=$expired anomalies=$anomalies"

  if (( anomalies > 0 )); then
    echo "ANOMALY: $anomalies malformed marker(s) — refusing to report clear:" >&2
    local r
    for r in "${anomaly_rows[@]}"; do echo "  - $r" >&2; done
    return 2
  fi

  if (( expired > 0 )); then
    echo "EXPIRED: $expired estimate row(s) past verify_by:"
    local r
    for r in "${expired_rows[@]}"; do echo "  - $r"; done
    return 1
  fi

  if (( candidates == 0 )); then
    echo "clean: 0 estimate markers in ledger (explicit zero state)."
  else
    echo "clean: $parsed estimate marker(s), none past verify_by."
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
