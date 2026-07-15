#!/usr/bin/env bash
# Pins scripts/betterstack-query.sh's hot+archive query shape (#6288).
#
# WHY THIS EXISTS: the script queried ONLY remote(<..._logs>) — the hot window, ~40
# MINUTES of rows on 2026-07-15. It never errored; it just answered `--since 24h` with 40
# minutes. That silent truncation is invisible at the call site, and it kept #6288 open
# from 2026-07-10: scripts/followthroughs/zot-restart-plateau-6288.sh needs
# ZOT_MIN_SOAK_SPAN_SEC=7200 (2h) of span, so it reported "TRANSIENT: soak not yet filled"
# forever against a window that could never contain 2h. A short answer that looks like a
# complete one is the failure mode being pinned here.
#
# HERMETIC: run_sql is redefined to capture the generated SQL instead of issuing it — no
# network, no BETTERSTACK_QUERY_* creds, no live rows (cq-test-fixtures-synthesized-only).
# We assert the SQL SHAPE, never live data, because availability and row counts are
# time-varying and must never be encoded in a test.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="${SCRIPT_DIR}/scripts/betterstack-query.sh"
[[ -r "$TARGET" ]] || { echo "FAIL: cannot read $TARGET" >&2; exit 1; }

pass=0 fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n     %s\n' "$1" "${2:-}" >&2; fail=$((fail + 1)); }

# Run the script with `curl` stubbed to print the SQL it would POST, instead of issuing it.
# Intercepting at the curl layer (not run_sql) is deliberate: the script DEFINES run_sql, so
# sourcing it would overwrite any run_sql stub. curl is the real egress boundary — stubbing
# it also proves no request escapes. Creds are faked to clear the guard; they are never sent.
capture_sql() {
  BETTERSTACK_QUERY_HOST=stub \
  BETTERSTACK_QUERY_USERNAME=stub \
  BETTERSTACK_QUERY_PASSWORD=stub \
  bash -c '
    curl() {
      # The SQL is the argument to -d. Print it and swallow the rest.
      while [[ $# -gt 0 ]]; do
        [[ "$1" == "-d" ]] && { printf "%s" "$2"; return 0; }
        shift
      done
      return 0
    }
    source "$1" "${@:2}"
  ' _ "$TARGET" "$@" 2>/dev/null
}

# --- 1. default (mode 2) unions hot + archive ---
sql="$(capture_sql --since 24h --grep MARKER)"
case "$sql" in
  *"UNION ALL"*) ok "default query UNION ALLs hot + archive" ;;
  *) bad "default query UNION ALLs hot + archive" "no UNION ALL in: ${sql:0:180}" ;;
esac
case "$sql" in
  *"remote(t520508_soleur_inngest_vector_prd_3_logs)"*) ok "hot arm queries remote(<..._logs>)" ;;
  *) bad "hot arm queries remote(<..._logs>)" "got: ${sql:0:180}" ;;
esac
case "$sql" in
  *"s3Cluster(primary, t520508_soleur_inngest_vector_prd_3_s3)"*) ok "archive arm queries s3Cluster(primary, <..._s3>)" ;;
  *) bad "archive arm queries s3Cluster(primary, <..._s3>)" "got: ${sql:0:180}" ;;
esac

# _row_type = 1 is REQUIRED on the s3 arm (runbook §Query mechanics). Without it the
# archive returns internal non-log rows and the caller silently over-counts.
case "$sql" in
  *"_row_type = 1"*) ok "archive arm filters _row_type = 1" ;;
  *) bad "archive arm filters _row_type = 1" "got: ${sql:0:180}" ;;
esac

# ORDER BY / LIMIT must apply to the COMBINED set, not inside either arm — otherwise each
# half is truncated independently and the merge interleaves wrongly.
outer="${sql##*)}"
case "$outer" in
  *"ORDER BY dt ASC"*"LIMIT"*) ok "ORDER BY + LIMIT apply to the combined set" ;;
  *) bad "ORDER BY + LIMIT apply to the combined set" "outer tail: ${outer:0:120}" ;;
esac

# The time predicate must reach BOTH arms — a hot-only WHERE would drag the whole archive.
hits="$(grep -o 'INTERVAL 24 HOUR' <<<"$sql" | wc -l | tr -d ' ')"
if [[ "$hits" == "2" ]]; then ok "--since predicate applied to both arms"
else bad "--since predicate applied to both arms" "expected 2 occurrences, got $hits"; fi

# --grep must reach both arms too.
ghits="$(grep -o "MARKER" <<<"$sql" | wc -l | tr -d ' ')"
if [[ "$ghits" == "2" ]]; then ok "--grep predicate applied to both arms"
else bad "--grep predicate applied to both arms" "expected 2 occurrences, got $ghits"; fi

# --- 2. --no-archive opts out (hot only) ---
sql_no="$(capture_sql --since 1h --no-archive)"
case "$sql_no" in
  *"s3Cluster"*) bad "--no-archive omits the archive arm" "s3Cluster present: ${sql_no:0:140}" ;;
  *"remote("*)   ok "--no-archive omits the archive arm (hot only)" ;;
  *) bad "--no-archive omits the archive arm" "unexpected: ${sql_no:0:140}" ;;
esac

# --- 3. --table derives the s3 name; --table-s3 wins in EITHER order ---
sql_t="$(capture_sql --since 1h --table t1_foo_logs)"
case "$sql_t" in
  *"s3Cluster(primary, t1_foo_s3)"*) ok "--table derives <name>_logs -> <name>_s3" ;;
  *) bad "--table derives <name>_logs -> <name>_s3" "got: ${sql_t:0:160}" ;;
esac

# Order-independence: --table AFTER --table-s3 must not clobber the explicit archive name.
sql_o1="$(capture_sql --since 1h --table-s3 t9_explicit_s3 --table t1_foo_logs)"
sql_o2="$(capture_sql --since 1h --table t1_foo_logs --table-s3 t9_explicit_s3)"
if [[ "$sql_o1" == *"t9_explicit_s3"* && "$sql_o2" == *"t9_explicit_s3"* ]]; then
  ok "--table-s3 wins regardless of flag order"
else
  bad "--table-s3 wins regardless of flag order" "before=${sql_o1:0:100} after=${sql_o2:0:100}"
fi

# --- 4. raw SQL (mode 1): $BS_TABLE_S3 substituted BEFORE $BS_TABLE ---
# $BS_TABLE is a strict prefix of $BS_TABLE_S3. Substituting the short token first rewrites
# `$BS_TABLE_S3` into `<hot_table>_S3` — a table that does not exist — surfacing as a
# confusing UNKNOWN_TABLE instead of the caller's archive rows.
raw="$(capture_sql 'SELECT dt FROM s3Cluster(primary, $BS_TABLE_S3) UNION ALL SELECT dt FROM remote($BS_TABLE)')"
case "$raw" in
  *"_logs_S3"*) bad "raw SQL substitutes \$BS_TABLE_S3 before \$BS_TABLE" "prefix collision produced _logs_S3: ${raw:0:160}" ;;
  *"s3Cluster(primary, t520508_soleur_inngest_vector_prd_3_s3)"*"remote(t520508_soleur_inngest_vector_prd_3_logs)"*)
    ok "raw SQL substitutes \$BS_TABLE_S3 before \$BS_TABLE" ;;
  *) bad "raw SQL substitutes \$BS_TABLE_S3 before \$BS_TABLE" "got: ${raw:0:160}" ;;
esac

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$pass" "$fail"
[[ "$fail" -eq 0 ]]
