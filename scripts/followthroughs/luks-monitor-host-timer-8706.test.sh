#!/usr/bin/env bash
# Exit-code harness for luks-monitor-host-timer-8706.sh (#8706 Phase 3).
#
# The probe's exit code is its authorization artifact: sweep-followthroughs.sh closes #8706 on 0.
# The cardinal sin is an exit 0 before the host timer has fired on three consecutive UTC nights, or
# a FAIL/PASS while the log channel is dark. Every case pins one arm.
#
# SEAM: LUKS_HOST_TIMER_BQ names a betterstack-query.sh stand-in that records the SQL it was given
# and answers the positive-control query and the nights query from separate fixtures with separate
# exit codes, so each of the two queries can fail on its own. Runs under `env -i` like the sweeper.
# Fixtures are synthesized (cq-test-fixtures-synthesized-only); the credentials are fake.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/luks-monitor-host-timer-8706.sh"
passes=0
fails=0
ok() { passes=$((passes + 1)); printf '  PASS: %s\n' "$1"; }
no() { fails=$((fails + 1)); printf '  FAIL: %s\n' "$1" >&2; }

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { echo "FATAL: SUT not executable at $SUT (the sweeper execs it directly)" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
MOCK="$WORK/mock-bq.sh"
cat > "$MOCK" <<'MOCKEOF'
#!/usr/bin/env bash
# Records every SQL it receives; dispatches on the query shape.
printf '%s\n----\n' "$1" >> "$FX_DIR/calls.sql"
case "$1" in
  *"GROUP BY d"*)
    printf 'nights\n' >> "$FX_DIR/calls.kind"
    [[ -f "$FX_DIR/nights.json" ]] && cat "$FX_DIR/nights.json"
    exit "$(cat "$FX_DIR/nights.rc" 2>/dev/null || echo 0)" ;;
  *)
    printf 'control\n' >> "$FX_DIR/calls.kind"
    [[ -f "$FX_DIR/control.json" ]] && cat "$FX_DIR/control.json"
    exit "$(cat "$FX_DIR/control.rc" 2>/dev/null || echo 0)" ;;
esac
MOCKEOF
chmod 0755 "$MOCK"

# fixture <control-json> <control-rc> <nights-json> <nights-rc> — reset the fixture dir.
fixture() {
  rm -rf "$WORK/fx"; mkdir -p "$WORK/fx"
  printf '%s' "$1" > "$WORK/fx/control.json"; printf '%s' "$2" > "$WORK/fx/control.rc"
  printf '%s' "$3" > "$WORK/fx/nights.json";  printf '%s' "$4" > "$WORK/fx/nights.rc"
}

# run_sut — the sweeper's shape: env -i + the three secrets + PATH.
run_sut() {
  RC=0
  OUT="$(env -i PATH="$PATH" HOME="$WORK" FX_DIR="$WORK/fx" LUKS_HOST_TIMER_BQ="$MOCK" \
    BETTERSTACK_QUERY_HOST=bq.example.test BETTERSTACK_QUERY_USERNAME=fixture-user \
    BETTERSTACK_QUERY_PASSWORD=fixture-pass "$SUT" 2>&1)" || RC=$?
}
has()  { [[ "$OUT" == *"$1"* ]]; }
kinds() { cat "$WORK/fx/calls.kind" 2>/dev/null | tr '\n' ' '; }

CTRL='{"n":"12"}'
NIGHT1='{"d":"2026-09-28","n":"2"}'
NIGHT2='{"d":"2026-09-29","n":"2"}'
NIGHT3='{"d":"2026-09-30","n":"2"}'

# --- 1. two consecutive nights -> FAIL, no PASS marker -------------------------------------------
fixture "$CTRL" 0 "$NIGHT1"$'\n'"$NIGHT2" 0
run_sut
if [[ "$RC" -eq 1 ]] && ! has 'HOST_TIMER_PASS' && has 'FAIL: 2 consecutive host-timer night(s) of 3' \
   && has 'positive_control luks_monitor_rows=12' \
   && has 'host_timer_day=2026-09-28 rows=2' && has 'host_timer_day=2026-09-29 rows=2'; then
  ok "2 consecutive nights -> exit 1, FAIL line, no HOST_TIMER_PASS, control + per-day lines printed"
else
  no "2 consecutive nights wrong (rc=$RC): ${OUT:0:300}"
fi

# --- 2. three consecutive nights -> PASS --------------------------------------------------------
fixture "$CTRL" 0 "$NIGHT1"$'\n'"$NIGHT2"$'\n'"$NIGHT3" 0
run_sut
if [[ "$RC" -eq 0 ]] && has 'HOST_TIMER_PASS nights=3' && ! has 'FAIL'; then
  ok "3 consecutive nights -> HOST_TIMER_PASS nights=3, exit 0"
else
  no "3 consecutive nights wrong (rc=$RC): ${OUT:0:300}"
fi

# --- 3. three NON-consecutive nights -> FAIL ----------------------------------------------------
fixture "$CTRL" 0 '{"d":"2026-09-26","n":"2"}'$'\n''{"d":"2026-09-28","n":"2"}'$'\n''{"d":"2026-09-30","n":"2"}' 0
run_sut
if [[ "$RC" -eq 1 ]] && ! has 'HOST_TIMER_PASS' && has 'FAIL: 1 consecutive'; then
  ok "3 non-consecutive nights -> exit 1 (longest run 1), no PASS"
else
  no "3 non-consecutive nights wrong (rc=$RC): ${OUT:0:300}"
fi

# --- 4. positive control zero -> exit 2, never FAIL/PASS, nights query never asked ---------------
fixture '{"n":"0"}' 0 "$NIGHT1"$'\n'"$NIGHT2"$'\n'"$NIGHT3" 0
run_sut
if [[ "$RC" -eq 2 ]] && ! has 'HOST_TIMER_PASS' && ! has 'FAIL' && has 'positive_control luks_monitor_rows=0' \
   && [[ "$(kinds)" == "control " ]]; then
  ok "dark channel (control=0) -> exit 2, no FAIL/PASS, nights query not run"
else
  no "dark channel wrong (rc=$RC, queries=[$(kinds)]): ${OUT:0:300}"
fi

# --- 5. control query failure -> exit 2 ---------------------------------------------------------
# A VALID control body with a non-zero rc: the rc check alone must refuse it (an empty body would
# be refused by the parse arm too, and could not tell the two arms apart).
fixture "$CTRL" 1 "$NIGHT1"$'\n'"$NIGHT2"$'\n'"$NIGHT3" 0
run_sut
if [[ "$RC" -eq 2 ]] && ! has 'HOST_TIMER_PASS' && ! has 'FAIL:'; then
  ok "positive-control query failure -> exit 2"
else
  no "control query failure wrong (rc=$RC): ${OUT:0:300}"
fi

# --- 6. nights query failure (even with rows on stdout) -> exit 2, never PASS --------------------
fixture "$CTRL" 0 "$NIGHT1"$'\n'"$NIGHT2"$'\n'"$NIGHT3" 3
run_sut
if [[ "$RC" -eq 2 ]] && ! has 'HOST_TIMER_PASS' && ! has 'FAIL:'; then
  ok "nights query failure -> exit 2 (rc checked before the rows are read)"
else
  no "nights query failure wrong (rc=$RC): ${OUT:0:300}"
fi

# --- 7. EMPTY nights result with rc 0 -> FAIL (a real zero, not a query failure) -----------------
fixture "$CTRL" 0 '' 0
run_sut
if [[ "$RC" -eq 1 ]] && has 'FAIL: 0 consecutive' && ! has 'host_timer_day='; then
  ok "empty nights result (rc 0) -> exit 1 with 0 nights, distinct from a failed query"
else
  no "empty nights result wrong (rc=$RC): ${OUT:0:300}"
fi

# --- 8. malformed nights row -> exit 2 ----------------------------------------------------------
fixture "$CTRL" 0 "$NIGHT1"$'\n''Code: 60. DB::Exception: table missing'$'\n'"$NIGHT2"$'\n'"$NIGHT3" 0
run_sut
if [[ "$RC" -eq 2 ]] && ! has 'HOST_TIMER_PASS'; then
  ok "a non-row line in the nights output -> exit 2, never counted"
else
  no "malformed nights output wrong (rc=$RC): ${OUT:0:300}"
fi
fixture 'not json' 0 '' 0
run_sut
if [[ "$RC" -eq 2 ]]; then ok "unparseable control count -> exit 2"; else no "unparseable control count wrong (rc=$RC)"; fi

# --- 9. unquoted UInt64 counts parse too --------------------------------------------------------
fixture '{"n":7}' 0 '{"d":"2026-09-28","n":1}'$'\n''{"d":"2026-09-29","n":1}'$'\n''{"d":"2026-09-30","n":1}' 0
run_sut
if [[ "$RC" -eq 0 ]] && has 'positive_control luks_monitor_rows=7'; then
  ok "unquoted integer counts parse (JSONEachRow quoting setting does not matter)"
else
  no "unquoted counts wrong (rc=$RC): ${OUT:0:300}"
fi

# --- 10. credentials not injected -> exit 2 -----------------------------------------------------
fixture "$CTRL" 0 "$NIGHT1"$'\n'"$NIGHT2"$'\n'"$NIGHT3" 0
RC=0
OUT="$(env -i PATH="$PATH" HOME="$WORK" FX_DIR="$WORK/fx" LUKS_HOST_TIMER_BQ="$MOCK" "$SUT" 2>&1)" || RC=$?
if [[ "$RC" -eq 2 ]] && [[ ! -s "$WORK/fx/calls.kind" ]]; then
  ok "credentials not injected -> exit 2 before any query"
else
  no "missing credentials wrong (rc=$RC): ${OUT:0:200}"
fi

# --- 11. xtrace with a live credential -> refused (78), nothing traced ---------------------------
fixture "$CTRL" 0 "$NIGHT1"$'\n'"$NIGHT2"$'\n'"$NIGHT3" 0
RC=0
OUT="$(env -i PATH="$PATH" HOME="$WORK" FX_DIR="$WORK/fx" LUKS_HOST_TIMER_BQ="$MOCK" \
  BETTERSTACK_QUERY_HOST=bq.example.test BETTERSTACK_QUERY_USERNAME=fixture-user \
  BETTERSTACK_QUERY_PASSWORD=fixture-pass bash -x "$SUT" 2>&1)" || RC=$?
if [[ "$RC" -eq 78 ]] && [[ "$OUT" != *fixture-pass* ]]; then
  ok "xtrace with a live credential -> refused with 78, credential not printed"
else
  no "xtrace refusal wrong (rc=$RC): ${OUT:0:200}"
fi

# --- 12. the SQL carries the full predicate, the archive union and the UTC hour ------------------
fixture "$CTRL" 0 "$NIGHT1" 0
run_sut
SQL="$(cat "$WORK/fx/calls.sql")"
nights_sql="${SQL#*----}"
missing=""
# shellcheck disable=SC2016  # the literal $BS_TABLE tokens are what the probe must send
for needle in \
  "toDate(dt, 'UTC')" \
  'remote($BS_TABLE)' \
  's3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1' \
  'INTERVAL 5 DAY'; do
  [[ "$nights_sql" == *"$needle"* ]] || missing+=" [$needle]"
done
if [[ -z "$missing" ]]; then
  ok "nights SQL carries the per-UTC-date grouping, hot+archive union and 5-day window"
else
  no "nights SQL missing:$missing"
fi

# PREDICATE PARITY with the alert: the nights WHERE clause (after the source subquery) must be the
# alert local's conjuncts EXACTLY, plus the 00 UTC hour — a set comparison, so an OR, a NOT, a
# dropped or an added conjunct all red. Expected values come from betterstack-logs-alerts.tf, never
# from this probe, so a reworded needle in one file and not the other reds here.
ALERTS_TF="${LHT_ALERTS_TF:-$HERE/../../apps/web-platform/infra/betterstack-logs-alerts.tf}"
parity() { # <sql> -> prints OK or a diff line
  NIGHTS_SQL="$1" ALERTS_TF="$ALERTS_TF" python3 - <<'PYEOF'
import os, re
def norm(x):
    x = " ".join(x.split())
    return re.sub(r'\s*([(),=])\s*', r'\1', x)
def conj(where):
    parts = re.split(r'\s+AND\s+', where)
    out, skip = [], False
    for i, p in enumerate(parts):
        if skip: skip = False; continue
        if re.search(r'\bBETWEEN\s+\S+\s*$', p) and i + 1 < len(parts):
            out.append(p + " AND " + parts[i + 1]); skip = True
        else:
            out.append(p)
    return [norm(p) for p in out]
tf = open(os.environ["ALERTS_TF"]).read()
m = re.search(r'(?ms)^\s*luks_monitor_host_timer_sql\s*=\s*<<-SQL\n(.*?)\n\s*SQL\s*$', tf)
if not m:
    print("NO_ALERT_SQL"); raise SystemExit
alert = " ".join(m.group(1).split()).split(" WHERE ", 1)[1]
want = {c for c in conj(alert) if not c.startswith("dt BETWEEN")} | {norm("toHour(dt, 'UTC') = 0")}
sql = " ".join(os.environ["NIGHTS_SQL"].split())
# The OUTER WHERE: the last ") WHERE " before GROUP BY (the source subquery has its own WHEREs).
head = sql.split(" GROUP BY ", 1)[0]
if ") WHERE " not in head:
    print("NO_NIGHTS_WHERE"); raise SystemExit
where = head.rsplit(") WHERE ", 1)[1]
got = conj(where)
if len(got) == len(want) and set(got) == want and not re.search(r'\b(OR|NOT)\b', where):
    print("OK")
else:
    print("DIFF want=%s got=%s" % (sorted(want), sorted(got)))
PYEOF
}
p_real="$(parity "$nights_sql")"
if [[ "$p_real" == OK ]]; then
  ok "nights WHERE == the alert's conjuncts + the 00 UTC hour (extracted from betterstack-logs-alerts.tf)"
else
  no "nights predicate diverges from the alert: $p_real"
fi
# The checker must be able to refuse: the masking defect's two spellings, derived from the real SQL.
or_sql="${nights_sql/AND JSONExtractString(raw, \'_SYSTEMD_UNIT\')/OR JSONExtractString(raw, \'_SYSTEMD_UNIT\')}"
not_sql="${nights_sql/AND JSONExtractString(raw, \'_SYSTEMD_UNIT\')/AND NOT JSONExtractString(raw, \'_SYSTEMD_UNIT\')}"
if [[ "$or_sql" != "$nights_sql" && "$not_sql" != "$nights_sql" \
      && "$(parity "$or_sql")" != OK && "$(parity "$not_sql")" != OK ]]; then
  ok "the parity check refuses the unit conjunct joined with OR or negated"
else
  no "the parity check could not refuse an OR/NOT unit conjunct (or the derivation did not land)"
fi
control_sql="${SQL%%----*}"
# shellcheck disable=SC2016  # literal $BS_TABLE_S3 token
if [[ "$control_sql" == *"'luks-monitor'"* && "$control_sql" == *"'host_name') = 'soleur-web-platform'"* \
   && "$control_sql" == *"INTERVAL 36 HOUR"* && "$control_sql" != *"_SYSTEMD_UNIT"* && "$control_sql" != *"toHour"* \
   && "$control_sql" == *'$BS_TABLE_S3'* ]]; then
  ok "positive-control SQL counts ANY web-1 luks-monitor row in 36 h (no unit/hour conjunct) over hot+archive"
else
  no "positive-control SQL is narrowed, unscoped or hot-only: ${control_sql:0:300}"
fi
# Output rule: dates and counts only — never a message needle, credential or host.
if [[ "$OUT" != *"LUKS-backed"* && "$OUT" != *fixture-pass* && "$OUT" != *bq.example.test* ]]; then
  ok "output carries no message text, credential or query host"
else
  no "output leaked message/credential/host: ${OUT:0:300}"
fi

# --- 13. longest_consecutive_run, the pure function ---------------------------------------------
# shellcheck source=scripts/followthroughs/luks-monitor-host-timer-8706.sh disable=SC1091  # sourced for longest_consecutive_run; its main guard does not fire
. "$SUT"
lcr() { printf '%s' "$1" | longest_consecutive_run; }
lcr_case() { # <label> <input> <expected-output-or-RC1>
  local got rc=0
  got="$(lcr "$2")" || rc=$?
  if [[ "$3" == RC1 ]]; then
    if [[ "$rc" -eq 1 && -z "$got" ]]; then ok "longest_consecutive_run: $1 -> rc 1"; else no "longest_consecutive_run: $1 -> expected rc 1, got rc=$rc out=$got"; fi
  elif [[ "$rc" -eq 0 && "$got" == "$3" ]]; then ok "longest_consecutive_run: $1 -> $3"
  else no "longest_consecutive_run: $1 -> expected $3, got rc=$rc out=$got"; fi
}
lcr_case "no dates" "" 0
lcr_case "one date" $'2026-09-28\n' 1
lcr_case "three consecutive" $'2026-09-28\n2026-09-29\n2026-09-30\n' 3
lcr_case "unordered with a duplicate" $'2026-09-30\n2026-09-28\n2026-09-29\n2026-09-29\n' 3
lcr_case "across a month boundary" $'2026-09-30\n2026-10-01\n2026-10-02\n' 3
lcr_case "across a year boundary" $'2026-12-31\n2027-01-01\n' 2
lcr_case "gap splits the run" $'2026-09-25\n2026-09-26\n2026-09-28\n2026-09-29\n2026-09-30\n' 3
lcr_case "no trailing newline" $'2026-09-28\n2026-09-29' 2
lcr_case "impossible date" $'2026-02-30\n' RC1
lcr_case "garbage line" $'2026-09-28\nnot-a-date\n' RC1

echo ""
echo "=== luks-monitor-host-timer-8706.test.sh: ${passes} passed, ${fails} failed ==="
# Non-degeneracy floor: a suite that silently stopped running its cases must not report green.
if [[ "$passes" -lt 27 ]]; then
  echo "FAIL: only $passes assertions passed (floor 27) — a case block stopped running" >&2
  exit 1
fi
[[ "$fails" -eq 0 ]] || exit 1
