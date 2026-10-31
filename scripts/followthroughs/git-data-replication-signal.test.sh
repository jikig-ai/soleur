#!/usr/bin/env bash
# Companion suite for scripts/followthroughs/git-data-replication-signal.sh (#11704 item 6, CTO ruling F6, Guard 4).
#
# Registered by the repo's shard manifest (scripts/followthroughs/ matches no SUITE_GLOBS entry, so an unregistered .test.sh is
# an orphan that gates nothing while looking exactly like coverage).
#
# OFFLINE BY CONSTRUCTION. The signal is copied into a synthesized tree beside a STUB scripts/betterstack-query.sh and the real
# scripts/lib/{betterstack-sources,betterstack-read-classify}.sh. No network, no Doppler, no real credential: the "credential"
# below is a synthetic string, and an output-hygiene row proves it (and every real host name) never reaches stdout or stderr.
#
# THE STUB IS STRICT (argv fidelity). It answers only the exact request the signal is modelled to send: exactly one argument, a
# SELECT, the control table pair in BS_TABLE / BS_TABLE_S3, the hot arm `remote($BS_TABLE)` and a FORMAT JSONEachRow tail. Anything
# else exits 64 (which the signal reads as READ_UNCLEAN, so a wrong request cannot masquerade as a verdict). The SQL itself is
# pinned literally (window, host lists, both closed grammars, archive arm, the web-host filter), because a stub that answers by
# query SHAPE cannot see a filter that was dropped.
#
# WHAT THIS PINS, in the order a reviewer would ask:
#   * one row per verdict, with the exit code table (only MARKERS_PRESENT exits 0; NO_SESSIONS exits 4);
#   * per-host masking (markers on one host never rescue a silent other host) and the worst-of precedence, READ_UNCLEAN first;
#   * a host with no reporter row is READ_UNCLEAN, never NO_SESSIONS (CTO F6), and a failed read is never a zero;
#   * the 10-minute settle boundary, and a newest row that still reads live;
#   * output hygiene: counts only, no host name, no row body, no credential;
#   * each guard is MUTATED in a copy (control first, landed-check, pristine restore) and its named row goes RED.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/git-data-replication-signal.sh"

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { echo "FATAL: SUT not executable at $SUT" >&2; exit 1; }
for _lib in betterstack-sources.sh betterstack-read-classify.sh; do
  [[ -f "$ROOT/scripts/lib/$_lib" ]] || { echo "FATAL: scripts/lib/$_lib missing" >&2; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required" >&2; exit 1; }

# Refuses an empty, relative, root or synthetic-fs fixture dir (byte-identical copy; the
# fixture-dir-operand-assert suite pins every tracked copy).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

# ---------------------------------------------------------------------------------------------------------------------
# Verdict machinery (ADR-193). The case counter `cases` is incremented at the CALL SITE (`cases=$((cases + 1)); eq ...`),
# never inside a helper or a command substitution; the helpers touch only the verdict counters, so passes + fails == cases
# is a real conservation check and not a tautology.
# ---------------------------------------------------------------------------------------------------------------------
cases=0
passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  PASS: %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL: %s\n' "$1" >&2; }
eq() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1 (want '$2' got '$3')"; fi
}
has() { # <name> <haystack> <needle>
  if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1 (missing '$3')"; fi
}
lacks() { # <name> <haystack> <needle>
  if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1 (found '$3')"; fi
}
ok() { # <name> <rc of the check>
  if [[ "$2" == 0 ]]; then pass "$1"; else fail "$1"; fi
}

# Instrument self-test: drive EVERY verdict-owning helper with a matching and a MISMATCHING case and require the verdict counters to
# move the right way (a helper whose body was disarmed to `pass` would leave fails flat). The counters are unwound afterwards so the
# accounting below stays exact; the result is reported with printf + exit, never through the helpers under test.
_p0=$passes; _f0=$fails; _inst_bad=""
probe() { # <name> <want passes delta> <want fails delta> <helper> args...
  local name="$1" wp="$2" wf="$3" p f; shift 3
  p=$passes; f=$fails
  "$@" >/dev/null 2>&1
  (( passes - p == wp && fails - f == wf )) || _inst_bad="$_inst_bad $name"
}
probe pass 1 0 pass i
probe fail 0 1 fail i
probe eq-match 1 0 eq i a a
probe eq-mismatch 0 1 eq i a b
probe has-match 1 0 has i abc b
probe has-mismatch 0 1 has i abc x
probe lacks-match 1 0 lacks i abc x
probe lacks-mismatch 0 1 lacks i abc b
probe ok-match 1 0 ok i 0
probe ok-mismatch 0 1 ok i 1
passes=$_p0; fails=$_f0
if [[ -n "$_inst_bad" ]]; then
  printf 'FATAL: instrument self-test -- helper(s) did not move the verdict counters as required:%s\n' "$_inst_bad" >&2; exit 1
fi

WORK="$(mktemp -d -t gdrs-signal.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT INT TERM HUP
FX="$WORK/fx"
TREE="$WORK/tree"
PRISTINE="$WORK/pristine.sh"
assert_fixture_dir "$FX"
assert_fixture_dir "$TREE"
mkdir -p "$FX" "$TREE/scripts/followthroughs" "$TREE/scripts/lib"

# --- the synthesized tree ---------------------------------------------------------------------------------------------
cp "$SUT" "$PRISTINE"
cp "$SUT" "$TREE/scripts/followthroughs/git-data-replication-signal.sh"
chmod +x "$TREE/scripts/followthroughs/git-data-replication-signal.sh"
for _lib in betterstack-sources.sh betterstack-read-classify.sh; do
  cp "$ROOT/scripts/lib/$_lib" "$TREE/scripts/lib/$_lib"
done
MUT="$TREE/scripts/followthroughs/git-data-replication-signal.sh"

# Synthetic credential: recognisable so a leak is unambiguous.
BS_PASS_SYN="synbspassword0123456789abcdef"

cat > "$TREE/scripts/betterstack-query.sh" <<'STUB'
#!/usr/bin/env bash
# Strict stub reader. Records the invocation, the single SQL argument and both pinned tables, then answers from $FX.
printf '%s\n' "$#" >> "$FX/bs.argc"
printf '%s|%s\n' "${BS_TABLE:-unset}" "${BS_TABLE_S3:-unset}" >> "$FX/bs.table"
printf '%s' "${1-}" > "$FX/bs.sql"
printf 'call\n' >> "$FX/bs.calls"
[[ $# -eq 1 ]] || exit 64
case "$1" in SELECT\ *) : ;; *) exit 64 ;; esac
[[ "${BS_TABLE:-}" == "t520508_soleur_inngest_vector_prd_3_logs" && "${BS_TABLE_S3:-}" == "t520508_soleur_inngest_vector_prd_3_s3" ]] || exit 64
case "$1" in *'remote($BS_TABLE)'*) : ;; *) exit 64 ;; esac
case "$1" in *'FORMAT JSONEachRow') : ;; *) exit 64 ;; esac
if [[ -n "${BS_STUB_RC:-}" ]]; then
  [[ -n "${BS_STUB_BODY:-}" ]] && printf '%s\n' "$BS_STUB_BODY"
  exit "$BS_STUB_RC"
fi
cat "$FX/bs.jsonl"
STUB
chmod +x "$TREE/scripts/betterstack-query.sh"

# --- fixture helpers --------------------------------------------------------------------------------------------------
# rowspec = leg:markers:reporter_rows:live_rows:newest_live:last_live_age_s
fx_rows() { # <rowspec>...  -> $FX/bs.jsonl (numbers, as the live reader returns them)
  assert_fixture_dir "$FX"
  : > "$FX/bs.jsonl"
  local spec leg m r l nl la
  for spec in "$@"; do
    IFS=: read -r leg m r l nl la <<<"$spec"
    printf '{"leg":"%s","markers":%s,"reporter_rows":%s,"live_rows":%s,"newest_live":%s,"last_live_age_s":%s}\n' \
      "$leg" "$m" "$r" "$l" "$nl" "$la" >> "$FX/bs.jsonl"
  done
}
SILENT_AGE=700   # last live row older than the 10-minute settle
FRESH_AGE=300    # last live row younger than the settle

ENVV=()
reset_env() {
  ENVV=("FX=$FX" "BETTERSTACK_QUERY_HOST=syn.betterstackdata.com" "BETTERSTACK_QUERY_USERNAME=synuser" "BETTERSTACK_QUERY_PASSWORD=$BS_PASS_SYN")
  assert_fixture_dir "$FX"
  rm -f "$FX/bs.argc" "$FX/bs.table" "$FX/bs.sql" "$FX/bs.calls"
}
reset_env
OUT="" ERR="" RC=0
run_sut() { # <script path> args...
  local script="$1"; shift
  RC=0
  OUT="$(timeout 60 env "${ENVV[@]}" bash "$script" "$@" 2>"$WORK/err.txt")" || RC=$?
  ERR="$(cat "$WORK/err.txt")"
}
sut() { reset_env; run_sut "$MUT" "$@"; }
overall_line() { printf '%s\n' "$OUT" | grep '^verdict=' | head -1; }
host_line() { printf '%s\n' "$OUT" | grep "^host=$1 " | head -1; }
reader_calls() { if [[ -f "$FX/bs.calls" ]]; then wc -l < "$FX/bs.calls" | tr -d ' '; else echo 0; fi; }

# ===== the verdict rows ===================================================================================================
echo "-- verdicts and exit codes"
# MARKERS_PRESENT: the only positive evidence.
fx_rows "web-1:3:30:2:0:$SILENT_AGE" "web-2:2:30:1:0:$SILENT_AGE"
sut --since 15m
cases=$((cases + 1)); eq "MARKERS_PRESENT: overall verdict and exit 0" "verdict=MARKERS_PRESENT exit=0 since=15m|0" "$(overall_line)|$RC"
cases=$((cases + 1)); has "MARKERS_PRESENT: per-host line carries the counts" "$(host_line web-1)" "host_verdict=MARKERS_PRESENT markers=3 reporter_rows=30 live_rows=2 newest_live=0 last_live_age_s=$SILENT_AGE"
cases=$((cases + 1)); eq "MARKERS_PRESENT: the reader ran exactly once (a script that never reads cannot pass)" "1" "$(reader_calls)"

# A must-PASS that differs from the canonical in host order: the verdict does not depend on row order.
fx_rows "web-2:2:30:1:0:$SILENT_AGE" "web-1:3:30:2:0:$SILENT_AGE"
sut --since 15m
cases=$((cases + 1)); eq "MARKERS_PRESENT: reader returns web-2 before web-1 (order-independent)" "verdict=MARKERS_PRESENT exit=0 since=15m|0" "$(overall_line)|$RC"

# Numeric strings (ClickHouse may quote 64-bit integers) are clean integers too.
printf '{"leg":"web-1","markers":"3","reporter_rows":"30","live_rows":"2","newest_live":"0","last_live_age_s":"%s"}\n{"leg":"web-2","markers":"2","reporter_rows":"30","live_rows":"1","newest_live":"0","last_live_age_s":"%s"}\n' "$SILENT_AGE" "$SILENT_AGE" > "$FX/bs.jsonl"
sut --since 15m
cases=$((cases + 1)); eq "MARKERS_PRESENT: quoted integers are accepted" "0" "$RC"

# NO_SESSIONS: inconclusive, never a pass.
fx_rows "web-1:0:30:0:0:0" "web-2:0:30:0:0:0"
sut --since 15m
cases=$((cases + 1)); eq "NO_SESSIONS: both hosts, exit 4 (never 0)" "verdict=NO_SESSIONS exit=4 since=15m|4" "$(overall_line)|$RC"
cases=$((cases + 1)); has "NO_SESSIONS: last_live_age_s reads none, not a number" "$(host_line web-1)" "last_live_age_s=none"

# PENDING: live row, zero markers, window not settled.
fx_rows "web-1:0:30:2:0:$FRESH_AGE" "web-2:3:30:1:0:$SILENT_AGE"
sut --since 15m
cases=$((cases + 1)); eq "PENDING: last live row 300 s old, newest row 0, exit 3" "verdict=PENDING exit=3 since=15m|3" "$(overall_line)|$RC"
fx_rows "web-1:0:30:2:0:599" "web-2:3:30:1:0:$SILENT_AGE"
sut --since 15m
cases=$((cases + 1)); eq "PENDING: the boundary, 599 s is still unsettled" "3" "$RC"
fx_rows "web-1:0:30:2:1:30" "web-2:3:30:1:0:$SILENT_AGE"
sut --since 15m
cases=$((cases + 1)); eq "PENDING: the newest reporter row still reads live" "3" "$RC"
fx_rows "web-1:0:30:2:1:900" "web-2:3:30:1:0:$SILENT_AGE"
sut --since 15m
cases=$((cases + 1)); eq "PENDING: newest row reads live even though it is old (cannot be called settled)" "3" "$RC"

# ZERO_MARKERS_WITH_SESSIONS: the alarm.
fx_rows "web-1:0:30:2:0:600" "web-2:3:30:1:0:$SILENT_AGE"
sut --since 15m
cases=$((cases + 1)); eq "ZERO_MARKERS_WITH_SESSIONS: the settle boundary, exactly 600 s alarms, exit 1" "verdict=ZERO_MARKERS_WITH_SESSIONS exit=1 since=15m|1" "$(overall_line)|$RC"
cases=$((cases + 1)); has "ZERO_MARKERS_WITH_SESSIONS: the per-host line names the silent host" "$(host_line web-1)" "host_verdict=ZERO_MARKERS_WITH_SESSIONS markers=0"
cases=$((cases + 1)); has "ZERO_MARKERS_WITH_SESSIONS: the healthy host keeps its own verdict" "$(host_line web-2)" "host_verdict=MARKERS_PRESENT"

# READ_UNCLEAN: a missing reporter row on either host, never NO_SESSIONS.
fx_rows "web-1:0:30:0:0:0"
sut --since 15m
cases=$((cases + 1)); eq "READ_UNCLEAN: no row at all for web-2 beside a quiet web-1 (never NO_SESSIONS), exit 2" "verdict=READ_UNCLEAN exit=2 since=15m|2" "$(overall_line)|$RC"
cases=$((cases + 1)); has "READ_UNCLEAN: the missing host line says so" "$(host_line web-2)" "host_verdict=READ_UNCLEAN markers=none reporter_rows=0"
fx_rows "web-2:0:30:0:0:0"
sut --since 15m
cases=$((cases + 1)); eq "READ_UNCLEAN: no row at all for web-1 (either host)" "2" "$RC"
: > "$FX/bs.jsonl"
sut --since 15m
cases=$((cases + 1)); eq "READ_UNCLEAN: an empty answer is not zero sessions" "2" "$RC"
fx_rows "web-1:3:0:0:0:0" "web-2:0:30:0:0:0"
sut --since 15m
cases=$((cases + 1)); eq "READ_UNCLEAN: a host with markers but zero reporter rows" "2" "$RC"

# ===== per-host masking and worst-of precedence ==========================================================================
echo "-- per-host masking and precedence"
fx_rows "web-1:0:30:2:0:$SILENT_AGE" "web-2:9:30:3:0:$SILENT_AGE"
sut --since 15m
cases=$((cases + 1)); eq "masking: markers on web-2 do not rescue a silent web-1" "1" "$RC"
fx_rows "web-1:9:30:3:0:$SILENT_AGE" "web-2:0:30:2:0:$SILENT_AGE"
sut --since 15m
cases=$((cases + 1)); eq "masking: markers on web-1 do not rescue a silent web-2 (mirror)" "1" "$RC"
fx_rows "web-1:3:30:2:0:$SILENT_AGE"
sut --since 15m
cases=$((cases + 1)); eq "precedence: READ_UNCLEAN beats MARKERS_PRESENT (web-2 unread)" "2" "$RC"
fx_rows "web-1:0:30:2:0:$SILENT_AGE" "web-2:0:30:2:0:$FRESH_AGE"
sut --since 15m
cases=$((cases + 1)); eq "precedence: ZERO_MARKERS_WITH_SESSIONS beats PENDING" "1" "$RC"
fx_rows "web-1:0:30:0:0:0" "web-2:0:30:2:0:$FRESH_AGE"
sut --since 15m
cases=$((cases + 1)); eq "precedence: PENDING beats NO_SESSIONS" "3" "$RC"
fx_rows "web-1:0:30:0:0:0" "web-2:4:30:2:0:$SILENT_AGE"
sut --since 15m
cases=$((cases + 1)); eq "a host with no live row and no marker is set aside beside a host with markers" "0" "$RC"
cases=$((cases + 1)); has "the set-aside host still reports NO_SESSIONS on its own line" "$(host_line web-1)" "host_verdict=NO_SESSIONS"
fx_rows "web-1:4:30:2:0:$SILENT_AGE" "web-2:0:30:0:0:0"
sut --since 15m
cases=$((cases + 1)); eq "set-aside is symmetric (web-2 idle beside web-1 markers)" "0" "$RC"

# Exactly one verdict exits 0.
echo "-- only MARKERS_PRESENT exits 0"
zero_exits=""
for fixture in \
  "web-1:3:30:2:0:$SILENT_AGE web-2:2:30:1:0:$SILENT_AGE" \
  "web-1:0:30:0:0:0 web-2:0:30:0:0:0" \
  "web-1:0:30:2:0:$FRESH_AGE web-2:0:30:2:0:$FRESH_AGE" \
  "web-1:0:30:2:0:$SILENT_AGE web-2:0:30:2:0:$SILENT_AGE" \
  "web-1:0:30:0:0:0"; do
  # shellcheck disable=SC2086  # the fixture string is split on purpose into rowspec words
  fx_rows $fixture
  sut --since 15m
  [[ "$RC" == 0 ]] && zero_exits="$zero_exits $(overall_line | cut -d' ' -f1)"
done
cases=$((cases + 1)); eq "across all five verdict fixtures, exit 0 belongs to MARKERS_PRESENT alone" " verdict=MARKERS_PRESENT" "$zero_exits"

# ===== reader failures: never a zero =====================================================================================
echo "-- reader failures"
fx_rows "web-1:3:30:2:0:$SILENT_AGE" "web-2:2:30:1:0:$SILENT_AGE"
for pair in "1:reader-exit-1" "3:credentials-absent" "6:transport" "124:transport" "78:reader-refusal" "99:other"; do
  rcv="${pair%%:*}"; cls="${pair#*:}"
  reset_env; ENVV+=("BS_STUB_RC=$rcv")
  run_sut "$MUT" --since 15m
  cases=$((cases + 1)); eq "reader rc $rcv is READ_UNCLEAN with class bs-$cls (never a zero or a pass)" "verdict=READ_UNCLEAN exit=2 since=15m read_class=bs-$cls|2" "$(overall_line)|$RC"
done
reset_env; ENVV+=("BS_STUB_RC=22" "BS_STUB_BODY=Code: 516. DB::Exception: Authentication failed: password is incorrect")
run_sut "$MUT" --since 15m
cases=$((cases + 1)); eq "reader rc 22 with an auth body classifies as credentials-rejected" "verdict=READ_UNCLEAN exit=2 since=15m read_class=bs-credentials-rejected|2" "$(overall_line)|$RC"
cases=$((cases + 1)); lacks "the reader's body is not echoed" "$OUT$ERR" "DB::Exception"
reset_env; ENVV+=("BS_STUB_RC=1")
run_sut "$MUT" --since 15m
cases=$((cases + 1)); lacks "a failed read prints no per-host line (no invented counts)" "$OUT" "host="

# Malformed answers.
echo "-- malformed answers"
bad() { # <name> <line-or-lines>
  printf '%s\n' "$2" > "$FX/bs.jsonl"
  sut --since 15m
  cases=$((cases + 1)); eq "$1" "verdict=READ_UNCLEAN exit=2 since=15m read_class=bs-response-shape|2" "$(overall_line)|$RC"
}
GOOD2='{"leg":"web-2","markers":1,"reporter_rows":30,"live_rows":1,"newest_live":0,"last_live_age_s":700}'
bad "shape: a non-integer count" '{"leg":"web-1","markers":"abc","reporter_rows":30,"live_rows":1,"newest_live":0,"last_live_age_s":700}
'"$GOOD2"
bad "shape: a negative age" '{"leg":"web-1","markers":1,"reporter_rows":30,"live_rows":1,"newest_live":0,"last_live_age_s":-4}
'"$GOOD2"
bad "shape: a fractional count" '{"leg":"web-1","markers":1.5,"reporter_rows":30,"live_rows":1,"newest_live":0,"last_live_age_s":700}
'"$GOOD2"
bad "shape: a missing field" '{"leg":"web-1","markers":1,"reporter_rows":30,"live_rows":1,"newest_live":0}
'"$GOOD2"
bad "shape: an unknown leg" '{"leg":"web-3","markers":1,"reporter_rows":30,"live_rows":1,"newest_live":0,"last_live_age_s":700}
'"$GOOD2"
bad "shape: a duplicated leg" "$GOOD2
$GOOD2"
bad "shape: not JSON at all" 'this is not json'
bad "shape: a JSON line that is not an object" '[1,2,3]'

# ===== the SQL the signal sends ==========================================================================================
echo "-- the SQL"
sql_pins() { # <interval literal expected in the SQL> -> 0 when every pin holds against the last recorded SQL
  local s expect="$1" rc=0
  s="$(cat "$FX/bs.sql" 2>/dev/null)"
  [[ "$s" == SELECT* ]] || rc=1
  [[ "$s" == *"INTERVAL ${expect}"* || "$expect" == "-" ]] || rc=1
  [[ "$s" == *"IN ('soleur-web-platform','soleur-inngest-prd')"* && "$s" == *"= 'soleur-web-2'"* ]] || rc=1
  [[ "$s" == *"match(raw,'git_data_replication_success=1 transient_retried=[01]')"* ]] || rc=1
  [[ "$s" == *"match(raw,'agent_sessions_live=[0-9]+ cc_queries=[0-9]+ legacy_sessions=[0-9]+ starting=[0-9]+ new_sessions_paused=[01] refused_since_last=[0-9]+')"* ]] || rc=1
  [[ "$s" == *'UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1'* ]] || rc=1
  [[ "$s" == *"WHERE leg != ''"* ]] || rc=1
  # Every select-list expression, literally (a stub that ignores the SQL cannot see a changed aggregate).
  [[ "$s" == *"countIf(is_marker) AS markers,"* ]] || rc=1
  [[ "$s" == *"countIf(is_reporter) AS reporter_rows,"* ]] || rc=1
  [[ "$s" == *"countIf(is_reporter AND live > 0) AS live_rows,"* ]] || rc=1
  [[ "$s" == *"argMaxIf(live, dt, is_reporter) AS newest_live,"* ]] || rc=1
  [[ "$s" == *"dateDiff('second', maxIf(dt, is_reporter AND live > 0), now()) AS last_live_age_s"* ]] || rc=1
  [[ "$s" == *"toUInt32OrZero(extract(raw,'agent_sessions_live=([0-9]+)')) AS live"* ]] || rc=1
  [[ "$s" == *"JSONExtractString(raw,'host_name') = 'soleur-web-2','web-2','') AS leg"* ]] || rc=1
  [[ "$s" == *"GROUP BY leg ORDER BY leg FORMAT JSONEachRow"* ]] || rc=1
  return "$rc"
}
pins() { PINS_RC=0; sql_pins "$1" || PINS_RC=$?; }
fx_rows "web-1:3:30:2:0:$SILENT_AGE" "web-2:2:30:1:0:$SILENT_AGE"
sut --since 15m
pins "15 MINUTE"; cases=$((cases + 1)); ok "SQL pins hold for --since 15m (window, host lists, both grammars, archive arm, web-host filter)" "$PINS_RC"
cases=$((cases + 1)); eq "the reader got exactly one argument" "1" "$(cat "$FX/bs.argc" 2>/dev/null | head -1)"
cases=$((cases + 1)); eq "the reader got the control table pair" "t520508_soleur_inngest_vector_prd_3_logs|t520508_soleur_inngest_vector_prd_3_s3" "$(head -1 "$FX/bs.table")"
sut --since 2h
pins "2 HOUR"; cases=$((cases + 1)); ok "--since 2h renders INTERVAL 2 HOUR" "$PINS_RC"
sut --since 3d
pins "3 DAY"; cases=$((cases + 1)); ok "--since 3d renders INTERVAL 3 DAY" "$PINS_RC"
sut --since 2026-10-31T10:00:00Z
pins "-"; cases=$((cases + 1)); ok "an absolute stamp keeps every pin" "$PINS_RC"
cases=$((cases + 1)); has "an absolute stamp is a UTC DateTime literal" "$(cat "$FX/bs.sql")" "dt >= toDateTime('2026-10-31 10:00:00', 'UTC')"
sut --since '2026-10-31 10:00:00'
cases=$((cases + 1)); has "the space-separated stamp form is accepted" "$(cat "$FX/bs.sql")" "toDateTime('2026-10-31 10:00:00', 'UTC')"
cases=$((cases + 1)); eq "the SQL is read-only (no write verb)" "0" "$(grep -ciE '\b(insert|alter|drop|delete|truncate|create|update|grant)\b' "$FX/bs.sql" | head -1)"
# The SQL pins are not vacuous: a pin run against a doctored SQL fails.
printf '%s' "SELECT 1 FORMAT JSONEachRow" > "$FX/bs.sql"
pins "15 MINUTE"; cases=$((cases + 1)); eq "the SQL pin function rejects a doctored query (positive control)" "1" "$PINS_RC"

# ===== usage, hygiene and credentials ===================================================================================
echo "-- usage, output hygiene, credentials"
for badargs in "" "--since" "--since 15" "--since 0m" "--since 15x" "--since 15m;x" "--since 12345m" "--since 2026-13-45T00:00:00Z" "--since 15m --extra 1" "15m" "--until 15m"; do
  fx_rows "web-1:3:30:2:0:$SILENT_AGE" "web-2:2:30:1:0:$SILENT_AGE"
  reset_env
  # shellcheck disable=SC2086  # the argument string is split on purpose
  run_sut "$MUT" $badargs
  cases=$((cases + 1)); eq "usage: '$badargs' exits 64 with no read" "64|0" "$RC|$(reader_calls)"
done
fx_rows "web-1:3:30:2:0:$SILENT_AGE" "web-2:0:30:2:0:$SILENT_AGE"
sut --since 15m
ALL_OUT="$OUT$ERR"
for forbidden in soleur-web-platform soleur-inngest-prd soleur-web-2 "$BS_PASS_SYN" synuser syn.betterstackdata.com '"raw"' 'agent_sessions_live=' 'git_data_replication_success='; do
  cases=$((cases + 1)); lacks "hygiene: output carries no '$forbidden'" "$ALL_OUT" "$forbidden"
done
# xtrace with a live credential is refused before any read.
reset_env
RC=0; OUT="$(timeout 60 env "${ENVV[@]}" bash -x "$MUT" --since 15m 2>"$WORK/err.txt")" || RC=$?
cases=$((cases + 1)); eq "xtrace with a live credential: exit 78 and no read" "78|0" "$RC|$(reader_calls)"
cases=$((cases + 1)); lacks "xtrace refusal does not echo the credential" "$OUT$(cat "$WORK/err.txt")" "$BS_PASS_SYN"
# Static credential rules for this file's SUT.
cases=$((cases + 1)); eq "SUT never enables xtrace (no 'set -x' / 'set -o xtrace')" "0" "$(grep -cE '^[[:space:]]*set[[:space:]]+(-[a-zA-Z]*x|-o[[:space:]]+xtrace)' "$SUT" | head -1)"
cases=$((cases + 1)); eq "SUT never reads Doppler itself (no DOPPLER_TOKEN, no doppler call)" "0" "$(grep -cE '(DOPPLER_TOKEN|^[[:space:]]*doppler[[:space:]])' "$SUT" | head -1)"
cases=$((cases + 1)); eq "SUT performs no 2>/dev/null on the reader call" "0" "$(grep -E 'betterstack-query|\$BSQ' "$SUT" | grep -c '2>/dev/null' | head -1)"

# ===== mutation matrix (Guard 4) ===========================================================================================
# For each guard: CONTROL first (the pristine copy gives the expected answer on the fixture), the edit LANDED (the copy differs from
# the pristine), and the mutated copy gives a DIFFERENT answer. The mutated file is always restored from the pristine copy.
echo "-- mutation matrix"
restore() { cp "$PRISTINE" "$MUT"; chmod +x "$MUT"; }
SNAP_RC=""
snapshot() { # -> "<overall>|<rc>|<host lines>" for the fixture already on disk
  reset_env; [[ -n "$SNAP_RC" ]] && ENVV+=("BS_STUB_RC=$SNAP_RC"); run_sut "$MUT" --since 15m
  printf '%s|%s|%s' "$(overall_line)" "$RC" "$(printf '%s\n' "$OUT" | grep -c '^host=')"
}
mutate_case() { # <name> <sed expr> <expected control verdict> <fixture rowspec>...  (control first; the mutated answer must differ)
  local name="$1" expr="$2" want="$3"; shift 3
  fx_rows "$@"
  restore
  local control mutated
  control="$(snapshot)"
  cases=$((cases + 1)); eq "mutant $name: CONTROL (pristine copy) reads $want" "$want" "$(printf '%s' "$control" | sed -E 's/^verdict=([A-Z_]+) .*/\1/')"
  sed -i "$expr" "$MUT"
  cases=$((cases + 1)); if cmp -s "$PRISTINE" "$MUT"; then fail "mutant $name: the edit did not land"; else pass "mutant $name: the edit landed"; fi
  mutated="$(snapshot)"
  cases=$((cases + 1)); if [[ "$control" != "$mutated" ]]; then pass "mutant $name: goes RED (control '${control%%|*}' vs mutated '${mutated%%|*}')"; else fail "mutant $name: NOT detected (both '$control')"; fi
  restore
}

# The control answers are asserted outright too, so a control that drifted cannot make a mutant look detected.
fx_rows "web-1:3:30:2:0:$SILENT_AGE"
restore; cases=$((cases + 1)); eq "control: pristine copy reads READ_UNCLEAN for a missing web-2" "2" "$(snapshot | cut -d'|' -f2)"

mutate_case "precedence swapped (READ_UNCLEAN sorted last, no longer outranks)" 's/"READ_UNCLEAN:2" //; s/"MARKERS_PRESENT:0"/"MARKERS_PRESENT:0" "READ_UNCLEAN:2"/' "READ_UNCLEAN" \
  "web-1:3:30:2:0:$SILENT_AGE"
mutate_case "settle rule dropped" 's/ || last_live_age < SETTLE_S//' "PENDING" \
  "web-1:0:30:2:0:$FRESH_AGE" "web-2:3:30:1:0:$SILENT_AGE"
mutate_case "settle window widened" 's/^readonly SETTLE_S=600$/readonly SETTLE_S=6000/' "ZERO_MARKERS_WITH_SESSIONS" \
  "web-1:0:30:2:0:$SILENT_AGE" "web-2:3:30:1:0:$SILENT_AGE"
mutate_case "newest-row-still-live check dropped" 's/(( newest_live > 0 || last_live_age < SETTLE_S ))/(( last_live_age < SETTLE_S ))/' "PENDING" \
  "web-1:0:30:2:1:900" "web-2:3:30:1:0:$SILENT_AGE"
mutate_case "aggregation looks at the first host only" 's/^for leg in web-1 web-2; do$/for leg in web-1; do/' "ZERO_MARKERS_WITH_SESSIONS" \
  "web-1:9:30:2:0:$SILENT_AGE" "web-2:0:30:2:0:$SILENT_AGE"
mutate_case "NO_SESSIONS exits 0" 's/"NO_SESSIONS:4"/"NO_SESSIONS:0"/' "NO_SESSIONS" \
  "web-1:0:30:0:0:0" "web-2:0:30:0:0:0"
mutate_case "a missing reporter row reads NO_SESSIONS" '/No row at all for this host/,/^  else/ s/hv="READ_UNCLEAN"/hv="NO_SESSIONS"/' "READ_UNCLEAN" \
  "web-1:0:30:0:0:0"
mutate_case "markers with zero reporter rows count as present" 's/if (( reporter == 0 )); then/if (( 0 )); then/' "READ_UNCLEAN" \
  "web-1:3:0:0:0:0" "web-2:0:30:0:0:0"
SNAP_RC=6
mutate_case "a failed read is not classified (class token lost)" 's/^if (( rc != 0 )); then$/if (( 0 )); then/' "READ_UNCLEAN" \
  "web-1:3:30:2:0:$SILENT_AGE" "web-2:2:30:1:0:$SILENT_AGE"
SNAP_RC=""
mutate_case "set-aside rule removed (idle host lowers a positive host)" 's/^if \[\[ "\$overall" == "NO_SESSIONS" \]\] && (( any_present )); then overall="MARKERS_PRESENT"; fi$/:/' "MARKERS_PRESENT" \
  "web-1:0:30:0:0:0" "web-2:4:30:2:0:$SILENT_AGE"

# SQL guards: the named pin goes RED when the clause is removed.
sql_mutant() { # <name> <sed expr>
  local name="$1" expr="$2"
  fx_rows "web-1:3:30:2:0:$SILENT_AGE" "web-2:2:30:1:0:$SILENT_AGE"
  restore
  reset_env; run_sut "$MUT" --since 15m
  pins "15 MINUTE"; cases=$((cases + 1)); ok "control for '$name': the pristine SQL passes every pin" "$PINS_RC"
  sed -i "$expr" "$MUT"
  cases=$((cases + 1)); if cmp -s "$PRISTINE" "$MUT"; then fail "SQL mutant $name: the edit did not land"; else pass "SQL mutant $name: the edit landed"; fi
  reset_env; run_sut "$MUT" --since 15m
  pins "15 MINUTE"; cases=$((cases + 1)); if [[ "$PINS_RC" != 0 ]]; then pass "SQL mutant $name: the pin goes RED"; else fail "SQL mutant $name: NOT detected"; fi
  restore
}
sql_mutant "web-host filter dropped" "s/^WHERE leg != ''\$/WHERE 1/"
sql_mutant "archive arm dropped" 's/^        UNION ALL SELECT dt, raw FROM s3Cluster.*$/        )/'
sql_mutant "marker grammar loosened" 's/transient_retried=\[01\]/transient_retried=/'
sql_mutant "reporter grammar loosened" 's/ refused_since_last=\[0-9\]+//'
sql_mutant "web-2 host dropped" "s/ = 'soleur-web-2'/ = 'soleur-web-9'/"
sql_mutant "newest_live takes argMax over every row (argMaxIf -> argMax)" 's/argMaxIf(live, dt, is_reporter)/argMax(live, dt)/'
sql_mutant "last live age ignores live > 0 (maxIf loses its condition)" 's/maxIf(dt, is_reporter AND live > 0)/maxIf(dt, is_reporter)/'
sql_mutant "live_rows counts every reporter row (countIf loses live > 0)" 's/countIf(is_reporter AND live > 0)/countIf(is_reporter)/'
sql_mutant "live read from cc_queries= instead of agent_sessions_live=" "s/extract(raw,'agent_sessions_live=/extract(raw,'cc_queries=/"
sql_mutant "last_live_age_s is a constant" 's/dateDiff(.second., maxIf(dt, is_reporter AND live > 0), now())/0/'
sql_mutant "markers counts reporter rows" 's/countIf(is_marker) AS markers/countIf(is_reporter) AS markers/'

# ===== accounting and the assertion floor (ADR-193) ===========================================================================
# Reported with printf + exit, never through fail(): a floor routed through the suspect cannot witness the suspect.
if (( passes + fails != cases )); then
  printf 'FATAL: accounting -- %d passes + %d fails != %d cases (a verdict was discarded or a call site lacks its increment)\n' "$passes" "$fails" "$cases" >&2
  exit 1
fi
FLOOR=144
if [[ "$cases" -lt "$FLOOR" ]]; then
  printf 'FATAL: assertion floor -- only %d assertions ran, want >= %d\n' "$cases" "$FLOOR" >&2
  exit 1
fi
printf '\n%d assertions, %d passed, %d failed\n' "$cases" "$passes" "$fails"
[[ "$fails" -eq 0 ]]
