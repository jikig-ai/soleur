#!/usr/bin/env bash
# One coverage line from a reader stdout temp.
# Does not print the path, a log line, rows=, or a decoded body.
# The incident marker is printed by the skill, not by this script.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: pull-card.sh <betterstack|sentry|supabase> <exit-code> <stdout-path>" >&2
  exit 1
fi

source_name="$1"
exit_code="$2"
stdout_path="$3"

case "$source_name" in
  betterstack|sentry|supabase) ;;
  *)
    echo "usage: source must be betterstack, sentry, or supabase" >&2
    exit 1
    ;;
esac

if ! [[ "$exit_code" =~ ^[0-9]+$ ]]; then
  echo "usage: exit code must be numeric" >&2
  exit 1
fi

case "$source_name" in
  betterstack)
    table="t520508_soleur_inngest_vector_prd_3_logs"
    if [[ "$exit_code" -eq 0 ]]; then
      if [[ ! -s "$stdout_path" ]]; then
        printf 'betterstack table=%s limit=100 exit=0 stdout-empty\n' "$table"
      else
        count="$(grep -c '"raw"' "$stdout_path" 2>/dev/null || true)"
        count="${count:-0}"
        if [[ "$count" -eq 100 ]]; then
          printf 'betterstack table=%s limit=100 exit=0 raw=%s truncated=true\n' "$table" "$count"
        else
          printf 'betterstack table=%s limit=100 exit=0 raw=%s\n' "$table" "$count"
        fi
      fi
    else
      printf 'betterstack table=%s limit=100 exit=%s\n' "$table" "$exit_code"
    fi
    ;;
  supabase)
    pair=""
    if [[ -r "$stdout_path" ]]; then
      # Human stdout is log lines, then one verdict line last. An earlier line can carry both tokens. Keep the last complete pair. Do not copy rows=.
      pair="$(awk '
        {
          v = ""
          r = ""
          for (i = 1; i <= NF; i++) {
            if ($i ~ /^verdict=/) v = $i
            if ($i ~ /^reason=/) r = $i
          }
          if (v != "" && r != "") {
            last_v = v
            last_r = r
          }
        }
        END {
          if (last_v != "" && last_r != "") print last_v, last_r
        }
      ' "$stdout_path" 2>/dev/null || true)"
    fi
    if [[ -n "$pair" ]]; then
      printf 'supabase %s\n' "$pair"
    else
      printf 'supabase exit=%s\n' "$exit_code"
    fi
    ;;
  sentry)
    printf 'sentry exit=%s window=n/a\n' "$exit_code"
    ;;
esac
