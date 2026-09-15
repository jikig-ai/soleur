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
#
# (#7898 §6) THE STUB HOST IS NOW VENDOR-SHAPED, and that is not cosmetic. betterstack-query.sh
# refuses any BETTERSTACK_QUERY_HOST outside `*.betterstackdata.com` before it will attach the
# Basic-auth credential, so the previous `stub` value would now exit 2 at the host check and
# every SQL-shape row below would assert on an empty string. `stub.betterstackdata.com` is
# synthetic and is never dialled — `curl` is shadowed as a shell function in every arm — so no
# packet leaves the machine (precedent: tests/scripts/test-betterstack-ingest-probe.sh, which
# satisfies the sibling allowlist with a zeroed-source-id vendor host and no seam at all).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="${SCRIPT_DIR}/scripts/betterstack-query.sh"
[[ -r "$TARGET" ]] || { echo "FAIL: cannot read $TARGET" >&2; exit 1; }

# Synthetic, allowlist-satisfying stub destination. Never resolved, never dialled.
STUB_HOST="stub.betterstackdata.com"
# The live production query host, from Doppler soleur/prd_terraform (read-only, 2026-09-09).
# Used ONLY as a must-PASS fixture value for the allowlist rows; still never dialled.
LIVE_HOST="eu-central-1a-connect.betterstackdata.com"

BS_TMP="$(mktemp -d -t bsqarch.XXXXXXXX)" || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$BS_TMP"' EXIT

pass=0 fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n     %s\n' "$1" "${2:-}" >&2; fail=$((fail + 1)); }

# INSTRUMENT SELF-TEST (#7898 review). Measured: rewriting `bad()` to call `ok()`
# left this suite at "30 passed, 0 failed", exit 0, WITH a real defect present --
# the verdict helpers are the dispatch layer, and no row that perturbs the SUT can
# observe them. Drive both helpers once and require both counters to move, then
# unwind. Reported with printf + exit, never through the helpers under test.
_st_p="$pass" _st_f="$fail"
ok "instrument self-test (this row is the control)" >/dev/null
bad "instrument self-test (expected; not a real failure)" "" 2>/dev/null
if (( pass != _st_p + 1 || fail != _st_f + 1 )); then
  printf '[FATAL] instrument self-test: ok()/bad() did not both move their counters (pass %d->%d, fail %d->%d). The verdict helpers are disarmed; every row below is meaningless.\n' \
    "$_st_p" "$pass" "$_st_f" "$fail" >&2
  exit 1
fi
pass="$_st_p" fail="$_st_f"
unset _st_p _st_f

# Run the script with `curl` stubbed to print the SQL it would POST, instead of issuing it.
# Intercepting at the curl layer (not run_sql) is deliberate: the script DEFINES run_sql, so
# sourcing it would overwrite any run_sql stub. curl is the real egress boundary — stubbing
# it also proves no request escapes. Creds are faked to clear the guard; they are never sent.
capture_sql() {
  BETTERSTACK_QUERY_HOST="$STUB_HOST" \
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
  BETTERSTACK_QUERY_HOST="$STUB_HOST" \
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
out_rc="$(BETTERSTACK_QUERY_HOST="$STUB_HOST" BETTERSTACK_QUERY_USERNAME=stub BETTERSTACK_QUERY_PASSWORD=stub \
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

# --- 9. Guard 2: the destination pin (#7898 §6) -------------------------------------------
#
# PROPERTY: betterstack-query.sh never sends BETTERSTACK_QUERY_{USERNAME,PASSWORD} to a host
# outside `*.betterstackdata.com`. `run_sql()` is the sole site that attaches the credential
# (`-u`) and the sole curl in the file, so a request that escapes is observable as a shim
# invocation — which is what makes these rows non-vacuous.
#
# WHY A COUNTING SHIM AND NOT capture_sql()'s: capture_sql's stub prints the `-d` argument and
# returns 0. It counts nothing and never sees the destination URL, so it cannot tell "refused
# before curl" from "sent, and the output happened to be empty". Every refusal row below would
# pass against a script with no host check at all. This shim appends one line per invocation,
# carrying the URL, so "zero invocations" is an assertion rather than an inference.
CURL_LOG="${BS_TMP}/curl-invocations.log"
: > "$CURL_LOG"

# Runs the real script with a counting `curl` shim. Echoes the exit code; the refusal text
# lands in $ERR_LOG and the invocations in $CURL_LOG (both truncated per call). Both are FILES,
# not variables: run_pinned is called inside `$( )`, so anything it assigns dies with that
# subshell — a refusal-text assertion against a variable would read empty and pass on nothing.
ERR_LOG="${BS_TMP}/stderr.log"
: > "$ERR_LOG"
run_pinned() {  # $1 = BETTERSTACK_QUERY_HOST value; remaining args go to the script
  local host="$1"; shift
  : > "$CURL_LOG"
  local rc=0
  # Synthetic credentials are LOAD-BEARING, not decoration: without them the script exits 3 at
  # the credential-presence guard, which sits ABOVE the host check, so "exited non-zero" would
  # tick while the allowlist was never reached — a vacuous pass (AC7).
  BETTERSTACK_QUERY_HOST="$host" \
  BETTERSTACK_QUERY_USERNAME=synthetic-user-not-a-credential \
  BETTERSTACK_QUERY_PASSWORD=synthetic-pass-not-a-credential \
  CURL_LOG="$CURL_LOG" \
  bash -c '
    curl() {
      # Record the destination so a reviewer can see WHERE the credential would have gone.
      local a url="<no-url-arg>"
      for a in "$@"; do case "$a" in http://*|https://*) url="$a" ;; esac; done
      printf "%s\n" "$url" >> "$CURL_LOG"
      return 0
    }
    source "$1" "${@:2}"
  ' _ "$TARGET" "$@" >/dev/null 2>"$ERR_LOG" || rc=$?
  printf '%s' "$rc"
}
curl_calls() { wc -l < "$CURL_LOG" | tr -d ' '; }
last_err()   { head -c 300 "$ERR_LOG"; }

# G2.1 — a BARE host outside the apex. It passes EVERY arm of the pre-existing shape check
# (no control chars, no @, no /, no ?, no #, one colon at most, non-empty), which is exactly
# why the shape check was never a destination pin.
rc="$(run_pinned attacker.example --since 1h)"
calls="$(curl_calls)"
if [[ "$rc" == "2" && "$calls" == "0" && "$(cat "$ERR_LOG")" == *"*.betterstackdata.com"* ]]; then
  ok "a substituted bare host (attacker.example) is refused with exit 2, zero curl invocations"
else
  bad "a substituted bare host (attacker.example) is refused with exit 2, zero curl invocations" \
      "rc=$rc curl_invocations=$calls err=$(last_err)"
fi

# G2.2 — the vendor apex as a PREFIX of an attacker domain. This is the value that
# discriminates authority-extraction-plus-suffix-match from a whole-value `*betterstackdata.com*`
# glob. The obvious candidate does NOT work: `evil.com/?x=.betterstackdata.com` is already
# refused by the shape arm (which rejects `/` and `?`), never reaches the allowlist, and so
# discriminates nothing.
rc="$(run_pinned betterstackdata.com.attacker.example --since 1h)"
calls="$(curl_calls)"
if [[ "$rc" == "2" && "$calls" == "0" ]]; then
  ok "the apex is anchored as a SUFFIX (betterstackdata.com.attacker.example refused)"
else
  bad "the apex is anchored as a SUFFIX (betterstackdata.com.attacker.example refused)" \
      "rc=$rc curl_invocations=$calls err=$(last_err)"
fi

# G2.5 — a registrable lookalike that matches only if the pattern lost its leading dot.
rc="$(run_pinned notbetterstackdata.com --since 1h)"
calls="$(curl_calls)"
if [[ "$rc" == "2" && "$calls" == "0" ]]; then
  ok "the leading dot is present (notbetterstackdata.com refused)"
else
  bad "the leading dot is present (notbetterstackdata.com refused)" \
      "rc=$rc curl_invocations=$calls err=$(last_err)"
fi

# The pre-existing shape family still refuses — the allowlist is an ADDITION, not a swap.
# `real.host@evil.example` resolves to evil.example; the userinfo arm catches it first.
rc="$(run_pinned 'x.betterstackdata.com@evil.example' --since 1h)"
calls="$(curl_calls)"
if [[ "$rc" == "2" && "$calls" == "0" ]]; then
  ok "userinfo is still refused (vendor-looking string left of an @)"
else
  bad "userinfo is still refused (vendor-looking string left of an @)" \
      "rc=$rc curl_invocations=$calls err=$(last_err)"
fi

# H2 — must-PASS, non-canonical. The live production host, and the same host with an explicit
# port: the port strip and the apex are both permitted BY CONTRACT, so a pin that refuses
# either breaks every consumer at once. Exactly one curl invocation, at the pinned host, is
# also what makes H1 (remove the shim) fail closed rather than silently begin dialling.
for h in "$LIVE_HOST" "${LIVE_HOST}:443"; do
  rc="$(run_pinned "$h" --since 1h)"
  calls="$(curl_calls)"
  if [[ "$rc" == "0" && "$calls" == "1" && "$(cat "$CURL_LOG")" == "https://${h}?"* ]]; then
    ok "the live vendor host is admitted and reached exactly once (${h})"
  else
    bad "the live vendor host is admitted and reached exactly once (${h})" \
        "rc=$rc curl_invocations=$calls url=$(head -c 120 "$CURL_LOG") err=$(last_err)"
  fi
done

# Case folding. DNS is case-insensitive; a bash `case` glob is not, and LC_ALL does not change
# that. This exact value works today, so a pin that refuses it is a regression, not a tightening.
rc="$(run_pinned "$(printf '%s' "$LIVE_HOST" | tr '[:lower:]' '[:upper:]')" --since 1h)"
calls="$(curl_calls)"
if [[ "$rc" == "0" && "$calls" == "1" ]]; then
  ok "an UPPERCASE vendor host is admitted (DNS is case-insensitive; a case glob is not)"
else
  bad "an UPPERCASE vendor host is admitted (DNS is case-insensitive; a case glob is not)" \
      "rc=$rc curl_invocations=$calls err=$(last_err)"
fi

# One trailing dot. `host.` is a valid absolute FQDN, passes every shape arm, and resolves.
rc="$(run_pinned "${LIVE_HOST}." --since 1h)"
calls="$(curl_calls)"
if [[ "$rc" == "0" && "$calls" == "1" ]]; then
  ok "a trailing-dot FQDN is admitted (one dot stripped before matching)"
else
  bad "a trailing-dot FQDN is admitted (one dot stripped before matching)" \
      "rc=$rc curl_invocations=$calls err=$(last_err)"
fi

# --- 10. the OTHER destination-shaped inputs in the same request (#7898 §6, step 1.1b) -----
# BS_TABLE / BS_TABLE_S3 interpolate unquoted into remote(...) and s3Cluster(primary, ...),
# whose leading argument positions are an ADDRESS expression and a URL. They are env-settable
# AND flag-settable by the same actor the host pin defends against, and the flag loop runs
# BELOW the host check, so nothing validated them at any point.
# The fixture must END IN `_logs`, or the pre-existing archive-derivation guard refuses it
# with 64 for an unrelated reason and the row passes without exercising any validation.
EVIL_TABLE="s3('http://evil.example/x')_logs"
rc="$(BS_TABLE="$EVIL_TABLE" run_pinned "$STUB_HOST" --since 1h)"
calls="$(curl_calls)"
if [[ "$rc" != "0" && "$calls" == "0" ]]; then
  ok "a non-identifier BS_TABLE is refused before any request"
else
  bad "a non-identifier BS_TABLE is refused before any request" "rc=$rc curl_invocations=$calls"
fi

rc="$(run_pinned "$STUB_HOST" --since 1h --table "$EVIL_TABLE")"
calls="$(curl_calls)"
if [[ "$rc" != "0" && "$calls" == "0" ]]; then
  ok "a non-identifier --table is refused before any request"
else
  bad "a non-identifier --table is refused before any request" "rc=$rc curl_invocations=$calls"
fi

rc="$(run_pinned "$STUB_HOST" --since 1h --table-s3 "http://evil.example/x")"
calls="$(curl_calls)"
if [[ "$rc" != "0" && "$calls" == "0" ]]; then
  ok "a non-identifier --table-s3 is refused before any request"
else
  bad "a non-identifier --table-s3 is refused before any request" "rc=$rc curl_invocations=$calls"
fi

# --limit interpolates raw into `LIMIT ${LIMIT}`.
rc="$(run_pinned "$STUB_HOST" --since 1h --limit "1 UNION ALL SELECT 1")"
if [[ "$rc" == "64" ]]; then
  ok "a non-numeric --limit is a usage error (64), not raw SQL"
else
  bad "a non-numeric --limit is a usage error (64), not raw SQL" "rc=$rc"
fi

# --since / --until interpolate into single-quoted SQL literals; --grep was the only input
# that got quote-escaping. Same treatment, same reason.
sql_q="$(capture_sql --since "2026-01-01' OR '1'='1" --no-archive)"
case "$sql_q" in
  *"dt >= '2026-01-01'' OR ''1''=''1'"*) ok "--since single quotes are SQL-escaped" ;;
  *) bad "--since single quotes are SQL-escaped" "got: ${sql_q:0:200}" ;;
esac
sql_q="$(capture_sql --since 1h --until "2026-01-01' OR '1'='1" --no-archive)"
case "$sql_q" in
  *"dt <= '2026-01-01'' OR ''1''=''1'"*) ok "--until single quotes are SQL-escaped" ;;
  *) bad "--until single quotes are SQL-escaped" "got: ${sql_q:0:200}" ;;
esac

# --- 11. Guard 5: a --table flag is never silently discarded in MODE 1 (#8043 FR13) --------
#
# THE DEFECT: mode 1 (raw SQL) ran `run_sql` and `exit $?` BEFORE the mode-2 flag loop, so
# `--table` / `--table-s3` passed alongside raw SQL were parsed by nothing and DISCARDED. The
# query then read the DEFAULT source (the shared inngest table). Against a git-data host that
# is a plausible EMPTY result — "the boot was dark" — with exit 0 and no hint that the flag
# never took. The script's own headline bug (asks for X, gets Y, exit 0), at the dispatch layer.
#
# PROPERTY: in every mode a --table* flag is either HONOURED or REFUSED LOUDLY. The rows below
# pin HONOURED: the captured SQL names the table the flag gave.
#
# WHY NOT capture_sql: it discards stderr and its exit code, and the script exits 3 on missing
# creds and 2 on the identifier check, so a row asserting "non-zero" would tick for the wrong
# reason. This runner mirrors run_pinned — same synthetic creds, same stub host, stderr to a
# FILE — and additionally records the `-d` body so the SQL can be asserted, and echoes the rc.
SQL_LOG="${BS_TMP}/sql-body.log"
run_raw() {  # args go to the script verbatim; echoes rc; SQL body in $SQL_LOG, stderr in $ERR_LOG
  : > "$SQL_LOG"; : > "$ERR_LOG"
  local rc=0
  BETTERSTACK_QUERY_HOST="$STUB_HOST" \
  BETTERSTACK_QUERY_USERNAME=synthetic-user-not-a-credential \
  BETTERSTACK_QUERY_PASSWORD=synthetic-pass-not-a-credential \
  SQL_LOG="$SQL_LOG" \
  bash -c '
    curl() {
      while [[ $# -gt 0 ]]; do
        [[ "$1" == "-d" ]] && { printf "%s" "$2" >> "$SQL_LOG"; return 0; }
        shift
      done
      return 0
    }
    source "$1" "${@:2}"
  ' _ "$TARGET" "$@" >/dev/null 2>"$ERR_LOG" || rc=$?
  printf '%s' "$rc"
}
RAW_BOTH='SELECT dt FROM remote($BS_TABLE) UNION ALL SELECT dt FROM s3Cluster(primary, $BS_TABLE_S3) FORMAT JSONEachRow'
DEFAULT_TABLE="t520508_soleur_inngest_vector_prd_3_logs"

# G5.1 — the headline. The label below is the plan's discoverability anchor; keep it verbatim.
rc="$(run_raw "$RAW_BOTH" --table t1_foo_logs)"
sql_g5="$(cat "$SQL_LOG")"
if [[ "$rc" == "0" && "$sql_g5" == *"remote(t1_foo_logs)"* && "$sql_g5" != *"$DEFAULT_TABLE"* ]]; then
  ok "mode 1: a --table flag is never silently discarded"
else
  bad "mode 1: a --table flag is never silently discarded" \
      "rc=$rc sql=${sql_g5:0:160} err=$(last_err)"
fi

# G5.2 — --table-s3 alongside raw SQL is honoured the same way (the archive arm is the one a
# soak query reads, so dropping THIS flag is the same silent wrong-source read one level down).
rc="$(run_raw "$RAW_BOTH" --table-s3 t9_explicit_s3)"
sql_g5="$(cat "$SQL_LOG")"
if [[ "$rc" == "0" && "$sql_g5" == *"s3Cluster(primary, t9_explicit_s3)"* ]]; then
  ok "mode 1: a --table-s3 flag is never silently discarded"
else
  bad "mode 1: a --table-s3 flag is never silently discarded" \
      "rc=$rc sql=${sql_g5:0:160} err=$(last_err)"
fi

# G5.3 — --table alone derives the archive name in mode 1 exactly as mode 2 does, so a raw
# UNION written with both tokens stays on ONE source by construction.
rc="$(run_raw "$RAW_BOTH" --table t1_foo_logs)"
sql_g5="$(cat "$SQL_LOG")"
if [[ "$rc" == "0" && "$sql_g5" == *"s3Cluster(primary, t1_foo_s3)"* ]]; then
  ok "mode 1: --table derives <name>_logs -> <name>_s3 for \$BS_TABLE_S3"
else
  bad "mode 1: --table derives <name>_logs -> <name>_s3 for \$BS_TABLE_S3" \
      "rc=$rc sql=${sql_g5:0:160} err=$(last_err)"
fi

# G5.4 — flag BEFORE the SQL positional. Pre-fix this was a loud 64 (`unknown flag: SELECT…`),
# not a silent discard, so it is pinned as honoured now rather than as a regression.
rc="$(run_raw --table t1_foo_logs "$RAW_BOTH")"
sql_g5="$(cat "$SQL_LOG")"
if [[ "$rc" == "0" && "$sql_g5" == *"remote(t1_foo_logs)"* ]]; then
  ok "mode 1: --table is honoured whether it precedes or follows the SQL"
else
  bad "mode 1: --table is honoured whether it precedes or follows the SQL" \
      "rc=$rc sql=${sql_g5:0:160} err=$(last_err)"
fi

# G5.5 — MUST-PASS: the canonical git-data read. scripts/followthroughs/git-data-rung2-
# evidence-capture.sh EXPORTS BS_TABLE and passes no flag; the pre-scan must not disturb that.
rc="$(BS_TABLE=t520508_soleur_git_data_prd_logs run_raw "$RAW_BOTH")"
sql_g5="$(cat "$SQL_LOG")"
if [[ "$rc" == "0" && "$sql_g5" == *"remote(t520508_soleur_git_data_prd_logs)"* \
      && "$sql_g5" == *"s3Cluster(primary, t520508_soleur_git_data_prd_s3)"* ]]; then
  ok "mode 1: an exported BS_TABLE with no flag still substitutes (evidence-capture path)"
else
  bad "mode 1: an exported BS_TABLE with no flag still substitutes (evidence-capture path)" \
      "rc=$rc sql=${sql_g5:0:160} err=$(last_err)"
fi

# G5.6 (#8052 review) — the pre-scan STEPS OVER a valued flag's value. `--grep --table` is a grep
# for the literal text "--table" (a mode-2 shape: raw SQL takes no --grep); a pre-scan that
# inspected the value would lift the NEXT `--table t1_x_logs` from under it and the query would
# go to the default table. The only row that exercises the value-stepping arm — without it the
# arm is one edit from a silent revert.
rc="$(run_raw --grep --table --table t1_stepped_logs)"
sql_g5="$(cat "$SQL_LOG")"
if [[ "$rc" == "0" && "$sql_g5" == *"remote(t1_stepped_logs)"* && "$sql_g5" == *"--table"* ]]; then
  ok "mode 2: the pre-scan steps over a --grep value spelled '--table' (the real flag is still honoured)"
else
  bad "mode 2: the pre-scan steps over a --grep value spelled '--table' (the real flag is still honoured)" \
      "rc=$rc sql=${sql_g5:0:160} err=$(last_err)"
fi

# G5.7 (#8052 review) — the raw-SQL refusal for an UNDERIVABLE archive has a row. A `--table`
# that is not `<name>_logs` with a query spelling `$BS_TABLE_S3` and no `--table-s3` must
# refuse (rc 64, named) rather than send `s3Cluster(primary, )` to the server.
rc="$(run_raw "$RAW_BOTH" --table t1_notlogs)"
sql_g5="$(cat "$SQL_LOG")"
if [[ "$rc" == "64" && -z "$sql_g5" && "$(cat "$ERR_LOG")" == *"cannot derive an archive table"* ]]; then
  ok "mode 1: an underivable archive with \$BS_TABLE_S3 in the query refuses (rc 64), sends nothing"
else
  bad "mode 1: an underivable archive with \$BS_TABLE_S3 in the query refuses (rc 64), sends nothing" \
      "rc=$rc sql=${sql_g5:0:160} err=$(last_err)"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$pass" "$fail"
# ANTI-VACUITY FLOOR (Guard 2 row 4). Without it this suite exits 0 on ZERO cases, so a
# mutation that made every arm unreachable — or an early `exit` inserted above — would read as
# a clean pass. The count is reported on the line above; this makes it load-bearing.
# A floor of ONE is not a floor. Measured (#7898 review): deleting the entire
# "Guard 2: the destination pin" section -- every allowlist, table-identifier and
# SQL-escape row this change adds -- left this suite at "16 passed, 0 failed",
# exit 0. Set to the measured green count so a dropped section is caught. A FLOOR,
# not an equality: adding rows must not red the suite, so raise it when you add one.
# Re-derived 2026-09-11 (#8043 Guard 5): the floor was 30 = the measured green count before
# section 11; section 11 adds exactly five rows (G5.1–G5.5), so 30 + 5 = 35. Then 37 at the
# #8052 review (G5.6 value-stepping, G5.7 underivable-archive refusal).
readonly MIN_ASSERTIONS=37
if (( pass + fail < MIN_ASSERTIONS )); then
  printf '%s: FAIL — only %d assertions ran; floor is %d. A suite that ran fewer cases than it declares cannot pass.\n' \
    "$(basename "$0")" "$((pass + fail))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$fail" -eq 0 ]]
