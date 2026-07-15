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

# Same, but the curl stub exits non-zero — used to prove the failure propagates to the
# caller rather than being swallowed (the script runs under `set -uo pipefail`, NOT -e).
run_with_failing_curl() {
  BETTERSTACK_QUERY_HOST=stub \
  BETTERSTACK_QUERY_USERNAME=stub \
  BETTERSTACK_QUERY_PASSWORD=stub \
  bash -c '
    curl() { return 22; }
    source "$1" "${@:2}"
  ' _ "$TARGET" "$@" >/dev/null 2>&1
  printf '%s' "$?"
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

# LIMIT must apply to the COMBINED set, never inside an arm: a per-arm LIMIT truncates each
# half independently, so the merged result silently drops rows the caller matched. Pin it
# structurally — exactly one LIMIT, and nothing before the UNION ALL carries one. (Ordering
# itself is asserted precisely below, in the newest-N check.)
lim_count="$(grep -o 'LIMIT' <<<"$sql" | wc -l | tr -d ' ')"
arms_before_union="${sql%%UNION ALL*}"
if [[ "$lim_count" == "1" && "$arms_before_union" != *LIMIT* ]]; then
  ok "LIMIT applies once, to the combined set (not per-arm)"
else
  bad "LIMIT applies once, to the combined set (not per-arm)" "count=$lim_count hot_arm_has_limit=$([[ "$arms_before_union" == *LIMIT* ]] && echo yes || echo no)"
fi

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

# --- 5. BS_TABLE_S3 as an ENV VAR is honored in mode 2, not just as a flag ---
# Regression pin: the sentinel was originally set only by --table-s3, so the post-flag
# re-derivation clobbered an env-supplied BS_TABLE_S3. The caller then queried the DEFAULT
# archive and got rows from the wrong source with NO error (the derived name exists, so the
# query succeeds) — this script's own headline bug, one level down. BS_TABLE's env override
# already survived both modes; BS_TABLE_S3's must too.
sql_env="$(BS_TABLE_S3=my_custom_archive_s3 capture_sql --since 1h)"
case "$sql_env" in
  *"s3Cluster(primary, my_custom_archive_s3)"*) ok "BS_TABLE_S3 env override honored in mode 2" ;;
  *) bad "BS_TABLE_S3 env override honored in mode 2" "override dropped: ${sql_env:0:180}" ;;
esac

# --- 6. LIMIT takes the NEWEST rows, output stays chronological ---
# ASC+LIMIT was harmless while the window was structurally <=40min; against a real 24h it
# returns the OLDEST N ("recent costs" -> 48h-stale markers).
sql_lim="$(capture_sql --since 48h --limit 20)"
inner_desc=0 outer_asc=0
[[ "$sql_lim" == *"ORDER BY dt DESC LIMIT 20"* ]] && inner_desc=1
[[ "${sql_lim##*LIMIT 20}" == *"ORDER BY dt ASC"* ]] && outer_asc=1
if (( inner_desc && outer_asc )); then ok "LIMIT takes newest N (inner DESC), output re-sorted ASC"
else bad "LIMIT takes newest N (inner DESC), output re-sorted ASC" "inner_desc=$inner_desc outer_asc=$outer_asc :: ${sql_lim:0:220}"; fi

# --- 7. a non-_logs table refuses to guess an archive name ---
out_rc="$(BETTERSTACK_QUERY_HOST=stub BETTERSTACK_QUERY_USERNAME=stub BETTERSTACK_QUERY_PASSWORD=stub \
  bash "$TARGET" --since 1h --table t520508_foo_metrics >/dev/null 2>&1; printf '%s' "$?")"
if [[ "$out_rc" == "64" ]]; then ok "non-_logs table errors rather than inventing <name>_s3"
else bad "non-_logs table errors rather than inventing <name>_s3" "expected rc=64, got $out_rc"; fi

# ...but --no-archive on a non-_logs table is fine (nothing to derive).
sql_nl="$(capture_sql --since 1h --table t520508_foo_metrics --no-archive)"
case "$sql_nl" in
  *"remote(t520508_foo_metrics)"*) ok "--no-archive works on a non-_logs table" ;;
  *) bad "--no-archive works on a non-_logs table" "got: ${sql_nl:0:140}" ;;
esac

# --- 8. failure propagates (fail-loud is the PR's headline claim; pin it) ---
# Guards against a future run_sql refactor swallowing the status. No `set -e` here, so this
# is not self-evident from reading the script.
rc_u="$(run_with_failing_curl --since 1h)"
rc_n="$(run_with_failing_curl --since 1h --no-archive)"
if [[ "$rc_u" != "0" && "$rc_n" != "0" ]]; then ok "a failing query exits non-zero (both arms)"
else bad "a failing query exits non-zero (both arms)" "union rc=$rc_u no-archive rc=$rc_n"; fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$pass" "$fail"
[[ "$fail" -eq 0 ]]
