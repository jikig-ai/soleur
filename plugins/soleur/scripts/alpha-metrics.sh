#!/usr/bin/env bash
#
# alpha-metrics.sh -- print the aggregate a tester pastes back at checkpoint.
#
# Usage: run inside the project repo:  bash plugins/soleur/scripts/alpha-metrics.sh
#
# Reads .soleur/decisions.jsonl (and the rotated .1) at the git root and prints
# aggregate counts ONLY: total lines, per-skill / per-agent_domain / per-harness
# breakdowns, first/last timestamps. Metadata is already allowlisted at write
# time, but this script still prints counts and fields only — never raw lines.
#
# Missing or empty output is a SIGNAL, not a zero:
#   SOLEUR_EMIT_ABSENT -- no log exists (stale install / emit never ran)
#   SOLEUR_EMIT_EMPTY  -- log exists with zero records (kill-switch set,
#                         unwritable dir, or a brand-new install)
# Neither means "the tester did nothing". Never report absence as zero usage.
#
# Portability: awk/grep/sed/wc/sort/head only — stock macOS bash 3.2-safe.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=plugins/soleur/scripts/resolve-git-root.sh
. "$DIR/resolve-git-root.sh" 2>/dev/null || {
  echo "SOLEUR_EMIT_ABSENT — not inside a git repository"
  exit 0
}

LOG_DIR="$GIT_ROOT/.soleur"
LOG="$LOG_DIR/decisions.jsonl"
ROT="$LOG.1"

if [ ! -f "$LOG" ] && [ ! -f "$ROT" ]; then
  echo "SOLEUR_EMIT_ABSENT — no decision log at .soleur/decisions.jsonl"
  echo "(a stale plugin install or emit has never fired; this is NOT proof of zero usage)"
  exit 0
fi

if [ ! -s "$LOG" ] && [ ! -s "$ROT" ]; then
  echo "SOLEUR_EMIT_EMPTY — the log exists but holds no records"
  echo "(kill-switch SOLEUR_DISABLE_DECISION_LOG, an unwritable .soleur, or a brand-new install)"
  exit 0
fi

# Merge current + rotated; each line is one allowlisted JSON object.
INPUT="$(cat "$LOG" "$ROT" 2>/dev/null)"

total="$(printf '%s\n' "$INPUT" | grep -c '^{"v":' )"
lines="$(printf '%s\n' "$INPUT" | grep -c .)"
malformed=$((lines - total))
first="$(printf '%s\n' "$INPUT" | sed -n 's/.*"ts":"\([^"]*\)".*/\1/p' | sort | head -1)"
last="$(printf '%s\n' "$INPUT" | sed -n 's/.*"ts":"\([^"]*\)".*/\1/p' | sort | tail -1)"

echo "=== .soleur/decisions.jsonl aggregate ==="
echo "records:  $total"
[ "$malformed" -gt 0 ] && echo "malformed: $malformed line(s) skipped (corrupt log — not counted)"
echo "first:    ${first:-unknown}"
echo "last:     ${last:-unknown}"
echo

count_field() { # $1 = json field name
  printf '%s\n' "$INPUT" \
    | sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" \
    | grep -v '^$' \
    | sort | uniq -c | sort -rn \
    | awk '{printf "  %-6s %s\n", $1, $2}'
}

echo "by event:";        count_field event
echo "by label:";        count_field label
echo "by skill:";        count_field skill
echo "by agent_domain:"; count_field agent_domain
echo "by harness:";      count_field harness

echo
echo "Knowledge-base growth (run in this repo):"
echo "  git log --since=<onboard-date> --name-only -- knowledge-base/ | grep -c '^knowledge-base/'"
exit 0
