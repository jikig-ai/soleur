#!/usr/bin/env bash
set -euo pipefail

# Runs every SQL file under apps/web-platform/supabase/verify/ against prod
# and fails if any check reports a non-zero `bad` count.
#
# Contract (enforced by this script): each verify file's SELECTs must emit
# two columns — `check_name TEXT` and `bad INT`. UNION ALL multiple checks
# into one file to bundle sentinels + idempotence probes per migration.
#
# Usage: doppler run -c prd -- bash run-verify.sh
# Requires: DATABASE_URL or DATABASE_URL_POOLER. Prefers DATABASE_URL_POOLER
#           for parity with run-migrations.sh (IPv4 path).
#
# Exit codes:
#   0  every verify file passed (or no verify files exist)
#   1  at least one check returned bad > 0, or psql failed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY_DIR="$SCRIPT_DIR/../supabase/verify"

command -v psql >/dev/null 2>&1 || { echo "::error::psql not found on PATH"; exit 1; }

DATABASE_URL="${DATABASE_URL_POOLER:-${DATABASE_URL:-}}"

if [[ -z "$DATABASE_URL" ]]; then
  echo "::error::Neither DATABASE_URL_POOLER nor DATABASE_URL is set. Ensure Doppler injects them."
  exit 1
fi

if [[ ! -d "$VERIFY_DIR" ]]; then
  echo "::notice::No verify directory at $VERIFY_DIR — nothing to check."
  exit 0
fi

shopt -s nullglob
verify_files=("$VERIFY_DIR"/*.sql)
shopt -u nullglob

if [[ "${#verify_files[@]}" -eq 0 ]]; then
  echo "::notice::No verify files present — nothing to check."
  exit 0
fi

failures=0
passed=0

for verify_file in "${verify_files[@]}"; do
  filename="$(basename "$verify_file")"
  echo "::group::verify $filename"

  # -F $'\t' emits tab-separated rows; -A strips aligned-table padding;
  # -t drops header/footer so we only see data rows; ON_ERROR_STOP=1 turns
  # SQL errors into psql exit 1 (tripping `set -e`).
  if ! output=$(psql "$DATABASE_URL" --no-psqlrc \
    --set ON_ERROR_STOP=1 \
    -tAF $'\t' \
    -f "$verify_file" 2>&1); then
    echo "::error::verify file failed to execute: $filename"
    echo "$output"
    failures=$((failures + 1))
    echo "::endgroup::"
    continue
  fi

  if [[ -z "$output" ]]; then
    echo "::error::$filename returned no rows — verify files must emit at least one (check_name, bad) row."
    failures=$((failures + 1))
    echo "::endgroup::"
    continue
  fi

  file_failed=0
  while IFS=$'\t' read -r check_name bad rest; do
    [[ -z "$check_name" ]] && continue
    if [[ -n "$rest" ]]; then
      echo "::error::$filename/$check_name: extra columns in row — contract is (check_name, bad) only."
      file_failed=1
      continue
    fi
    if ! [[ "$bad" =~ ^-?[0-9]+$ ]]; then
      echo "::error::$filename/$check_name: bad column is not an integer ('$bad')."
      file_failed=1
      continue
    fi
    if [[ "$bad" -gt 0 ]]; then
      echo "::error::$filename/$check_name: FAIL (bad=$bad)"
      file_failed=1
    else
      echo "ok $filename/$check_name (bad=$bad)"
    fi
  done <<< "$output"

  if [[ "$file_failed" -eq 1 ]]; then
    failures=$((failures + 1))
  else
    passed=$((passed + 1))
  fi
  echo "::endgroup::"
done

echo "Verify summary: $passed passed, $failures failed"

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
