#!/usr/bin/env bash
# Tests for scripts/web2-rebirth-emptiness.sh (#9372): every verdict arm, a transport failure that is NOT a verdict,
# and a mutation battery that removes each rule from a COPY and requires the battery to go red.
#
# SCOPE. The verdict fixtures below are AGGREGATE rows (what the query returns); they cannot notice a wrong RAW path in the
# SQL, which is exactly how the gate shipped reading paths no stored row has. So the SQL's own JSON paths are also resolved
# against REAL-SHAPE stored rows (the bare Vector metric, synthesized values). That check certifies path resolution and
# predicate text only, not ClickHouse semantics (the live read-only control is the anchor for those). Everything outside the
# WHERE conjuncts (the SELECT aggregates and their aliases, both FROM arms, the window, GROUP BY, HAVING, FORMAT) is pinned by
# EXACT TEXT, because the verdict fixtures are hand-written aggregate rows and cannot see an edit to the SQL that produces
# them. The SQL and these fixtures are edited together, so the suite alone proves consistency, not integrity; what sits
# outside it is the runbook betterstack-log-query.md.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${DIR}/web2-rebirth-emptiness.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

row() { # <metric> <hours> <vmin> <vmax> <age>
  printf '{"metric_name":"%s","n":"2000","hours":"%s","vmin":%s,"vmax":%s,"newest_age_s":"%s"}\n' "$1" "$2" "$3" "$4" "$5"
}
good_used="$(row filesystem_used_bytes 168 28000000 28500000 240)"
good_total="$(row filesystem_total_bytes 168 20000000000 20000000000 240)"

# ---- real-shape stored rows (synthesized values): the bare Vector host_metrics event, as Better Stack keeps it in `raw` ----
real_used='{"name":"filesystem_used_bytes","namespace":"host","tags":{"collector":"filesystem","device":"/dev/sdb","filesystem":"ext4","host":"soleur-web-2","mountpoint":"/mnt/data"},"timestamp":"2026-01-01T00:00:00.000000000Z","kind":"absolute","gauge":{"value":16000000.0}}'
real_total='{"name":"filesystem_total_bytes","namespace":"host","tags":{"collector":"filesystem","device":"/dev/sdb","filesystem":"ext4","host":"soleur-web-2","mountpoint":"/mnt/data"},"timestamp":"2026-01-01T00:00:00.000000000Z","kind":"absolute","gauge":{"value":20000000000.0}}'
# non-canonical but valid: other values, extra tag keys, permuted key order
real_used2='{"gauge":{"value":15900000.0},"kind":"absolute","tags":{"mountpoint":"/mnt/data","host":"soleur-web-2","extra":"x","filesystem":"ext4","device":"/dev/sdb","collector":"filesystem"},"namespace":"host","name":"filesystem_used_bytes","timestamp":"2026-01-02T00:00:00.000000000Z"}'
# the shape the gate USED to read: flat fields no stored row carries
legacy_row='{"host_name":"soleur-web-2","source_kind":"host_metrics","metric":{"name":"filesystem_used_bytes","value":16000000.0},"mountpoint":"/mnt/data"}'
decoy_host='{"name":"filesystem_used_bytes","namespace":"host","tags":{"collector":"filesystem","device":"/dev/sdb","filesystem":"ext4","host":"soleur-web-platform","mountpoint":"/mnt/data"},"kind":"absolute","gauge":{"value":16000000.0}}'
decoy_scalar_tags='{"name":"filesystem_used_bytes","namespace":"host","tags":"soleur-web-2","kind":"absolute","gauge":{"value":16000000.0}}'
decoy_mount="${real_used/\"mountpoint\":\"\/mnt\/data\"/\"mountpoint\":\"\/\"}"
decoy_ns="${real_used/\"namespace\":\"host\"/\"namespace\":\"process\"}"
decoy_name="${real_used/filesystem_used_bytes/filesystem_free_bytes}"
decoy_no_gauge='{"name":"filesystem_used_bytes","namespace":"host","tags":{"collector":"filesystem","device":"/dev/sdb","filesystem":"ext4","host":"soleur-web-2","mountpoint":"/mnt/data"},"kind":"absolute"}'

# w2r_sql_paths <sql-text> -- resolve the SQL's own JSON paths under a STRICT grammar. Prints, one per line:
#   COND<TAB><a,b><TAB><v1|v2>   each conjunct of the outer WHERE block (the line starting `WHERE`, to the line starting `GROUP BY`)
#   FLOAT<TAB><a,b>              each JSONExtractFloat path
#   SELNAME<TAB><a,b>            the path aliased AS metric_name
# Any WHERE line that is not the dt window, `JSONExtractString(raw,..) = '<lit>'` or `... IN ('<lit>',..)` prints FAILED and returns 1
# (an `OR`, `!=`, `LIKE` or two conjuncts on one line must fail, never be skipped). Zero conjuncts is `parsed 0` and returns 1.
w2r_sql_paths() {
  local sql="$1" line state=0 seen=0 rc=0 p v floats f sel
  local re_win="^WHERE dt > now\(\) - INTERVAL [0-9]+ DAY$"
  local re_eq="^  AND JSONExtractString\(raw,('[a-z_]+'(,'[a-z_]+')?)\) = '([^']*)'$"
  local re_in="^  AND JSONExtractString\(raw,('[a-z_]+'(,'[a-z_]+')?)\) IN \(('[^']*'(,'[^']*')*)\)$"
  while IFS= read -r line; do
    if [[ "$state" -eq 0 ]]; then
      [[ "$line" == WHERE* ]] || continue
      if [[ "$line" =~ $re_win ]]; then state=1; else printf 'FAILED WHERE window line has an unrecognised shape: %s\n' "$line"; rc=1; state=1; fi
      continue
    fi
    [[ "$line" == "GROUP BY"* ]] && { state=2; break; }
    if [[ "$line" =~ $re_eq ]]; then
      p="${BASH_REMATCH[1]//\'/}"; v="${BASH_REMATCH[3]}"; seen=$((seen + 1)); printf 'COND\t%s\t%s\n' "$p" "$v"
    elif [[ "$line" =~ $re_in ]]; then
      # IN lists are a SET: sort the members so a harmless reorder is not a false RED
      p="${BASH_REMATCH[1]//\'/}"; v="${BASH_REMATCH[3]//\'/}"; seen=$((seen + 1))
      v="$(tr ',' '\n' <<<"$v" | LC_ALL=C sort | paste -sd'|')"; printf 'COND\t%s\t%s\n' "$p" "$v"
    else
      printf 'FAILED WHERE conjunct has an unrecognised shape: %s\n' "$line"; rc=1
    fi
  done <<<"$sql"
  if [[ "$seen" -eq 0 ]]; then printf 'FAILED w2r_sql_paths parsed 0 conjuncts from the WHERE block\n'; rc=1; fi
  floats="$(grep -oE "JSONExtractFloat\(raw,[^)]*\)" <<<"$sql" || true)"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    f="${f#JSONExtractFloat(raw,}"; f="${f%)}"; printf 'FLOAT\t%s\n' "${f//\'/}"
  done <<<"$floats"
  sel="$(grep -oE "JSONExtractString\(raw,[^)]*\) AS metric_name" <<<"$sql" || true)"
  if [[ -n "$sel" ]]; then sel="${sel#JSONExtractString(raw,}"; sel="${sel%) AS metric_name}"; printf 'SELNAME\t%s\n' "${sel//\'/}"; fi
  return "$rc"
}

# row_satisfies <row-json> <conds-text> -- every COND holds on the row. A path that does not resolve (or a scalar where an object is
# expected) is the empty string, never an error: `try getpath` keeps a malformed decoy from crashing the evaluator into a false green.
row_satisfies() {
  local row="$1" conds="$2" tag p vals pa
  [[ -n "$conds" ]] || return 1   # no conjuncts is "parsed nothing", never "every conjunct holds"
  while IFS=$'\t' read -r tag p vals; do
    [[ "$tag" == COND ]] || continue
    pa="$(jq -nc --arg p "$p" '$p | split(",")')"
    jq -e --argjson p "$pa" --arg vals "$vals" '((try getpath($p) catch null) // "") as $v | any(($vals | split("|"))[]; . == $v)' <<<"$row" >/dev/null 2>&1 || return 1
  done <<<"$conds"
  return 0
}
# float_nonzero <row-json> <a,b> -- the aggregate's value path resolves to a number above zero on the row.
# shellcheck disable=SC2329  # invoked through chk_cmd's "$@"
float_nonzero() {
  local pa; pa="$(jq -nc --arg p "$2" '$p | split(",")')"
  jq -e --argjson p "$pa" '(try getpath($p) catch null) as $x | ($x | type) == "number" and $x > 0' <<<"$1" >/dev/null 2>&1
}
# has_device <row-json> -- tags.device is a non-empty string (an empty one would make the one-device HAVING inert).
# shellcheck disable=SC2329  # invoked through chk_cmd's "$@"
has_device() { jq -e '((try .tags.device catch null) // "") | (type == "string" and length > 0)' <<<"$1" >/dev/null 2>&1; }
# the SQL as it was BEFORE the fix (flat paths no stored row carries): the harness's own negative control.
legacy_sql() {
  printf '%s' "SELECT JSONExtractString(raw,'metric','name') AS metric_name, count() AS n, min(JSONExtractFloat(raw,'metric','value')) AS vmin, max(JSONExtractFloat(raw,'metric','value')) AS vmax
FROM (SELECT dt, raw FROM remote(\$BS_TABLE))
WHERE dt > now() - INTERVAL 7 DAY
  AND JSONExtractString(raw,'host_name') = 'soleur-web-2'
  AND JSONExtractString(raw,'source_kind') = 'host_metrics'
  AND JSONExtractString(raw,'tags','mountpoint') = '/mnt/data'
  AND JSONExtractString(raw,'metric','name') IN ('filesystem_used_bytes','filesystem_total_bytes')
GROUP BY metric_name
FORMAT JSONEachRow"
}

battery() {
  local script="$1" n=0 got
  # shellcheck disable=SC1090
  source "$script"
  chk() { # <name> <want-prefix> <body>
    n=$((n + 1)); printf '%b' "$3" > "$TMP/b.jsonl"
    got="$(w2r_emptiness_verdict "$TMP/b.jsonl")"
    [[ "$got" == "$2"* ]] || printf 'FAILED %s (got: %s)\n' "$1" "$got"
  }
  chk "PASS: complete, fresh, small, right-sized series" "PASS" "${good_used}\n${good_total}\n"
  chk "RED: empty body (zero rows)" "RED reason=used_bytes_absent_or_host_dark" ""
  chk "RED: only the total metric present" "RED reason=used_bytes_absent_or_host_dark" "${good_total}\n"
  chk "RED: coverage gap (159 hours)" "RED reason=coverage_gap" "$(row filesystem_used_bytes 159 28000000 28500000 240)\n${good_total}\n"
  chk "PASS: exactly 160 hours" "PASS" "$(row filesystem_used_bytes 160 28000000 28500000 240)\n${good_total}\n"
  chk "RED: stale newest row" "RED reason=stale" "$(row filesystem_used_bytes 168 28000000 28500000 1801)\n${good_total}\n"
  chk "PASS: newest row exactly at the bound" "PASS" "$(row filesystem_used_bytes 168 28000000 28500000 1800)\n${good_total}\n"
  chk "RED: maximum over the 1 GiB ceiling" "RED reason=not_empty" "$(row filesystem_used_bytes 168 1050000000 1073741825 240)\n${good_total}\n"
  chk "PASS: maximum exactly at the ceiling (with a small spread)" "PASS" "$(row filesystem_used_bytes 168 1060000000 1073741824 240)\n${good_total}\n"
  chk "RED: a minimum of zero is a missing value path, not an empty volume" "RED reason=used_bytes_zero_or_missing" "$(row filesystem_used_bytes 168 0 28500000 240)\n${good_total}\n"
  chk "RED: all-zero series (every sample read as 0)" "RED reason=used_bytes_zero_or_missing" "$(row filesystem_used_bytes 168 0 0 240)\n${good_total}\n"
  chk "RED: a series that moved by more than 64 MiB (a volume that took writes)" "RED reason=not_flat" "$(row filesystem_used_bytes 168 28000000 200000000 240)\n${good_total}\n"
  chk "PASS: a spread of exactly 64 MiB" "PASS" "$(row filesystem_used_bytes 168 28000000 95108864 240)\n${good_total}\n"
  chk "RED: a spread of 64 MiB + 1 byte" "RED reason=not_flat" "$(row filesystem_used_bytes 168 28000000 95108865 240)\n${good_total}\n"
  chk "PASS: 400 MB that sat flat is accepted under the coarse 1 GiB ceiling (the printed min and max are what the owner reads)" "PASS" "$(row filesystem_used_bytes 168 400000000 400000000 240)\n${good_total}\n"
  W2R_DETACHED=1 chk "DETACHED: a stale newest row is accepted (a detached device stops reporting)" "PASS" "$(row filesystem_used_bytes 30 28000000 28500000 90000)\n${good_total}\n"
  W2R_DETACHED=1 chk "DETACHED: coverage below 24 hours is still RED" "RED reason=coverage_gap" "$(row filesystem_used_bytes 23 28000000 28500000 90000)\n${good_total}\n"
  W2R_DETACHED=1 chk "DETACHED: the ceiling still applies" "RED reason=not_empty" "$(row filesystem_used_bytes 30 1050000000 1073741825 90000)\n${good_total}\n"
  W2R_DETACHED=1 chk "DETACHED: the zero floor still applies" "RED reason=used_bytes_zero_or_missing" "$(row filesystem_used_bytes 30 0 28500000 90000)\n${good_total}\n"
  chk "RED: without W2R_DETACHED a stale series is still RED (the relaxation is opt-in)" "RED reason=stale" "$(row filesystem_used_bytes 168 28000000 28500000 90000)\n${good_total}\n"
  chk "RED: total metric absent" "RED reason=total_bytes_absent" "${good_used}\n"
  chk "RED: total below the volume range (root-disk-like small mount)" "RED reason=not_the_20gb_volume" "${good_used}\n$(row filesystem_total_bytes 168 1000000000 1000000000 240)\n"
  chk "RED: total above the volume range (root-disk-like large mount)" "RED reason=not_the_20gb_volume" "${good_used}\n$(row filesystem_total_bytes 168 20000000000 80000000000 240)\n"
  chk "RED: malformed used row" "RED reason=used_bytes_malformed" "{\"metric_name\":\"filesystem_used_bytes\"}\n${good_total}\n"
  chk "RED: a used row without newest_age_s is malformed, never a freshness bypass" "RED reason=used_bytes_malformed" '{"metric_name":"filesystem_used_bytes","hours":"168","vmin":28000000,"vmax":28500000}\n'"${good_total}"'\n'
  chk "RED: a used row without vmax is malformed" "RED reason=used_bytes_malformed" '{"metric_name":"filesystem_used_bytes","hours":"168","vmin":28000000,"newest_age_s":"5"}\n'"${good_total}"'\n'
  chk "RED: a total row without vmax is malformed" "RED reason=total_bytes_malformed" "${good_used}"'\n{"metric_name":"filesystem_total_bytes","vmin":20000000000}\n'
  chk "RED: a total row without vmin is malformed" "RED reason=total_bytes_malformed" "${good_used}"'\n{"metric_name":"filesystem_total_bytes","vmax":20000000000}\n'
  chk "PASS: total exactly at the lower volume bound" "PASS" "${good_used}\n$(row filesystem_total_bytes 168 15000000000 15000000000 240)\n"
  chk "RED: total one byte under the lower volume bound" "RED reason=not_the_20gb_volume" "${good_used}\n$(row filesystem_total_bytes 168 14999999999 14999999999 240)\n"
  chk "PASS: total exactly at the upper volume bound" "PASS" "${good_used}\n$(row filesystem_total_bytes 168 21500000000 21500000000 240)\n"
  chk "RED: total one byte over the upper volume bound" "RED reason=not_the_20gb_volume" "${good_used}\n$(row filesystem_total_bytes 168 21500000001 21500000001 240)\n"
  W2R_DETACHED=1 chk "DETACHED: exactly 24 hours of coverage is accepted" "PASS" "$(row filesystem_used_bytes 24 28000000 28500000 90000)\n${good_total}\n"
  chk "RED: a metric_name that is not a string makes the judge ERROR, which must be RED (never PASS)" "RED reason=emptiness_judge_error" '{"metric_name":["a"],"hours":"168","vmin":1,"vmax":2,"newest_age_s":"5"}\n'
  W2R_DETACHED=0 chk "RED: W2R_DETACHED=0 does not relax freshness (only 1 does)" "RED reason=stale" "$(row filesystem_used_bytes 168 28000000 28500000 90000)\n${good_total}\n"
  chk "RED: unparseable body (HTML error page)" "RED reason=emptiness_body_unparseable" "<html>502</html>\n"
  chk "PASS: ClickHouse quoted 64-bit integers are accepted" "PASS" '{"metric_name":"filesystem_used_bytes","n":"9","hours":"168","vmin":"1","vmax":"2","newest_age_s":"5"}\n{"metric_name":"filesystem_total_bytes","n":"9","hours":"168","vmin":"20000000000","vmax":"20000000000","newest_age_s":"5"}\n'
  # ---- the SQL's own paths, resolved against real-shape stored rows ----
  # chk_cmd <name> <command...>: the command is the assertion; a non-zero status prints a FAILED line (every assertion counts toward n).
  chk_cmd() { local name="$1"; shift; n=$((n + 1)); "$@" || printf 'FAILED %s\n' "$name"; }
  # shellcheck disable=SC2329  # invoked through chk_cmd's "$@"
  not() { ! "$@"; }
  local sql paths prc conds floats selname c nc_out nc_rc lc fpath rest expected_rest
  # controls for the helpers every later assertion rides on: not() must invert both ways and chk_cmd must report a failing command
  chk_cmd "control: not() inverts true and false" test "$(not true; echo $?)$(not false; echo $?)" = "10"
  chk_cmd "control: chk_cmd prints a FAILED line for a failing command" test "$(chk_cmd ctl false)" = "FAILED ctl"
  sql="$(w2r_sql_emptiness)"
  paths="$(w2r_sql_paths "$sql")"; prc=$?
  chk_cmd "SQL paths parse under the strict grammar (rc ${prc}; ${paths//$'\n'/ | })" test "$prc" -eq 0
  conds="$(grep -E $'^COND\t' <<<"$paths" | sort || true)"
  floats="$(grep -E $'^FLOAT\t' <<<"$paths" || true)"; selname="$(grep -E $'^SELNAME\t' <<<"$paths" || true)"
  c="$(printf 'COND\tname\tfilesystem_total_bytes|filesystem_used_bytes\nCOND\tnamespace\thost\nCOND\ttags,host\t%s\nCOND\ttags,mountpoint\t/mnt/data' "$W2L_HOST_NAME")"
  chk_cmd "WHERE conjunct set is exactly host / namespace / mountpoint / metric names (got: ${conds//$'\n'/ ; })" test "$conds" = "$c"
  chk_cmd "exactly two JSONExtractFloat paths, both gauge,value (got: ${floats//$'\n'/ ; })" test "$floats" = "$(printf 'FLOAT\tgauge,value\nFLOAT\tgauge,value')"
  chk_cmd "SELECT name path equals the IN-predicate name path (got: ${selname})" test "$selname" = "$(printf 'SELNAME\tname')"
  for r in "$real_used" "$real_used2" "$real_total"; do
    chk_cmd "a real-shape row satisfies every conjunct: ${r:0:60}" row_satisfies "$r" "$conds"
  done
  fpath="$(awk -F'\t' '$1=="FLOAT"{print $2; exit}' <<<"$paths")"
  chk_cmd "the aggregate value path (${fpath}) resolves to a non-zero number on a real used row" float_nonzero "$real_used" "$fpath"
  chk_cmd "the aggregate value path resolves to a non-zero number on the non-canonical row" float_nonzero "$real_used2" "$fpath"
  for r in "$real_used" "$real_used2" "$real_total"; do
    chk_cmd "a real-shape row carries a non-empty tags.device: ${r:0:50}" has_device "$r"
  done
  for r in "$legacy_row" "$decoy_host" "$decoy_scalar_tags" "$decoy_mount" "$decoy_ns" "$decoy_name"; do
    chk_cmd "a legacy / other-host / scalar-tags / other-mount / other-namespace / other-name row VIOLATES a conjunct: ${r:0:60}" not row_satisfies "$r" "$conds"
  done
  chk_cmd "decoy without gauge still satisfies the conjuncts (only the value path can reject it)" row_satisfies "$decoy_no_gauge" "$conds"
  chk_cmd "an absent gauge does not resolve to a non-zero number" not float_nonzero "$decoy_no_gauge" "$fpath"
  # negative controls on the checker itself
  nc_out="$(w2r_sql_paths "$(printf 'SELECT 1\nFROM t\nWHERE dt > now() - INTERVAL 7 DAY\nGROUP BY x')")"; nc_rc=$?
  chk_cmd "negative control: an empty WHERE block is reported as parsed 0 and fails (rc ${nc_rc})" test "$nc_rc" -ne 0 -a "${nc_out#*parsed 0}" != "$nc_out"
  lc="$(w2r_sql_paths "$(legacy_sql)" | grep -E $'^COND\t' | sort || true)"
  chk_cmd "negative control: the legacy-path SQL yields conjuncts a real-shape row VIOLATES (the pre-fix defect is caught)" test -n "$lc" -a "$(row_satisfies "$real_used" "$lc" && echo yes || echo no)" = no
  nc_out="$(w2r_sql_paths "$(printf '%s\n  OR 1 = 1\nGROUP BY metric_name' "${sql%%GROUP BY*}")")"; nc_rc=$?
  chk_cmd "negative control: an unrecognised conjunct (OR 1 = 1) fails the strict grammar (rc ${nc_rc})" test "$nc_rc" -ne 0 -a "${nc_out#*FAILED}" != "$nc_out"
  # Everything outside the WHERE conjuncts, pinned by EXACT TEXT: the aggregates and their aliases, both FROM arms, the window,
  # GROUP BY, HAVING and FORMAT. (The conjunct lines are covered by the strict grammar and the set comparison above.)
  rest="$(grep -vE "^  AND JSONExtractString\(raw," <<<"$sql")"
  expected_rest="$(cat <<'EOF'
SELECT JSONExtractString(raw,'name') AS metric_name, count() AS n, countDistinct(toStartOfHour(dt)) AS hours, min(JSONExtractFloat(raw,'gauge','value')) AS vmin, max(JSONExtractFloat(raw,'gauge','value')) AS vmax, min(dateDiff('second', dt, now())) AS newest_age_s
FROM (SELECT dt, raw FROM remote($BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1)
WHERE dt > now() - INTERVAL 7 DAY
GROUP BY metric_name
HAVING uniqExact(JSONExtractString(raw,'tags','device')) = 1 AND min(length(JSONExtractString(raw,'tags','device'))) > 0
FORMAT JSONEachRow
EOF
)"
  chk_cmd "the SQL outside the WHERE conjuncts equals its pinned text (aggregates, aliases, both arms, window, GROUP BY, HAVING, FORMAT)" test "$rest" = "$expected_rest"
  printf 'RAN %s\n' "$n"
}

# parse_report <report-text> [quiet]: the ONE parser of the battery's FAILED / RAN lines, used for the real run, every mutant
# and the control below, so a neutered counter cannot hide behind a second one.
parse_report() {
  P_FAILS=0; P_RAN=0; local line
  while IFS= read -r line; do
    case "$line" in
      FAILED*) P_FAILS=$((P_FAILS + 1)); [[ "${2:-}" == quiet ]] || printf '  FAIL %s\n' "${line#FAILED }" ;;
      RAN*) P_RAN="${line#RAN }" ;;
      *) [[ -z "$line" || "${2:-}" == quiet ]] || printf '       %s\n' "$line" ;;
    esac
  done <<<"$1"
}
fails=0; ran=0
parse_report "$(battery "$SCRIPT" 2>&1)"
fails=$P_FAILS; ran=$P_RAN
printf 'real script: %s assertions, %s failed\n' "$ran" "$fails"
[[ "$ran" -ge 63 ]] || { echo "  FAIL assertion floor: ran ${ran} < 63"; fails=$((fails + 1)); }
parse_report $'FAILED c1\nRAN 3\nnoise' quiet
if [[ "$P_FAILS" -eq 1 && "$P_RAN" -eq 3 ]]; then echo "  ok   report parser control (1 failed, 3 ran)"; else echo "  FAIL report parser control (got ${P_FAILS} failed, ${P_RAN} ran)"; fails=$((fails + 1)); fi

# A transport failure is NOT a verdict: shim `curl` so the query script fails, run the main path, and require rc 2.
mkdir -p "$TMP/bin"; printf '#!/usr/bin/env bash\nexit 7\n' > "$TMP/bin/curl"; chmod +x "$TMP/bin/curl"
BETTERSTACK_QUERY_HOST=fixture-connect.betterstackdata.com BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p PATH="$TMP/bin:$PATH" bash "$SCRIPT" >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 2 ]]; then echo "  ok   transport failure exits 2 (not a verdict)"; else echo "  FAIL transport failure exited ${rc}, want 2"; fails=$((fails + 1)); fi

# The verdict is consumed: main exits 1 on RED and 0 on PASS (shim curl to answer a body).
printf '%s\n' "$good_used" "$good_total" > "$TMP/pass.body"; : > "$TMP/red.body"
for spec in "pass:0" "red:1"; do
  nm="${spec%%:*}"; want="${spec##*:}"
  printf '#!/usr/bin/env bash\ncat "%s/%s.body"\n' "$TMP" "$nm" > "$TMP/bin/curl"; chmod +x "$TMP/bin/curl"
  BETTERSTACK_QUERY_HOST=fixture-connect.betterstackdata.com BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p PATH="$TMP/bin:$PATH" bash "$SCRIPT" >/dev/null 2>&1; rc=$?
  if [[ "$rc" -eq "$want" ]]; then echo "  ok   main exits ${want} on a ${nm} body"; else echo "  FAIL main exited ${rc} on a ${nm} body, want ${want}"; fails=$((fails + 1)); fi
done

# A red BASELINE makes every mutation look killed, so the kill-counting only runs against a green one.
BASE_RED="$fails"; MUT_N=0; MUT_KILLED=0
# run_mutant <sed-script>: apply the edit to a COPY of the script and run the battery on it. Sets M_LANDED (the copy differs from the
# real script) and M_AFTER (FAILED lines the battery printed on the copy).
run_mutant() {
  local copy="$TMP/mut/web2-rebirth-emptiness.sh"
  mkdir -p "$TMP/mut/lib"; cp "$SCRIPT" "$copy"; cp "${DIR}/lib/"*.sh "$TMP/mut/lib/"; cp "${DIR}/betterstack-query.sh" "$TMP/mut/" 2>/dev/null
  sed -i -E "$1" "$copy"
  if cmp -s "$SCRIPT" "$copy"; then M_LANDED=0; M_AFTER=0; return; fi
  M_LANDED=1; parse_report "$(battery "$copy" 2>&1)" quiet; M_AFTER=$P_FAILS
}
mutate() { # <name> <sed-script>
  MUT_N=$((MUT_N + 1))
  [[ "$BASE_RED" -eq 0 ]] || { echo "  skip mutation '$1': the baseline is red, so a kill count would be void"; return; }
  run_mutant "$2"
  if [[ "$M_LANDED" -eq 0 ]]; then echo "  FAIL mutation '$1' did not change the script"; fails=$((fails + 1)); return; fi
  if [[ "$M_AFTER" -gt 0 ]]; then MUT_KILLED=$((MUT_KILLED + 1)); echo "  ok   mutation killed: $1 (${M_AFTER} red)"; else echo "  FAIL mutation SURVIVED: $1"; fails=$((fails + 1)); fi
}
mutate "coverage rule removed"  's/elif \(\$u\.hours \| num\) < \$minh then/elif false then/'
mutate "staleness rule removed" 's/elif \(\$detached \| not\) and \(\$u\.newest_age_s \| num\) > \$maxage then/elif false then/'
mutate "a judge error reads as PASS" 's/out="RED reason=emptiness_judge_error"/out="PASS"/'
mutate "detached relaxation made unconditional" 's/elif \(\$detached \| not\) and/elif false and/'
mutate "zero floor removed" 's/elif \(\$u\.vmin \| num\) == null or \(\$u\.vmin \| num\) <= 0 then/elif false then/'
mutate "spread rule removed" 's/elif \(\(\$u\.vmax \| num\) - \(\$u\.vmin \| num\)\) > \$maxspread then/elif false then/'
mutate "ceiling rule removed"   's/elif \(\$u\.vmax \| num\) > \$maxused then/elif false then/'
mutate "volume-size rule removed" 's/elif \(\$t\.vmin \| num\) < \$tmin or \(\$t\.vmax \| num\) > \$tmax then/elif false then/'
mutate "zero-row arm removed"   's/if \$u == null then "RED reason=used_bytes_absent_or_host_dark"/if false then "x"/'
# the SQL side: each edit puts the gate back on a path no stored row has, or widens/narrows the row set
mutate "host path reverted to the flat host_name" "s/JSONExtractString\(raw,'tags','host'\) = /JSONExtractString(raw,'host_name') = /"
mutate "vmin value path reverted (vmin only)" "s/(min\(JSONExtractFloat\(raw,)'gauge','value'/\1'metric','value'/"
mutate "vmax value path reverted (vmax only)" "s/(max\(JSONExtractFloat\(raw,)'gauge','value'/\1'metric','value'/"
mutate "name path reverted in the SELECT only" "s/JSONExtractString\(raw,'name'\) AS metric_name/JSONExtractString(raw,'metric','name') AS metric_name/"
mutate "name path reverted in the IN predicate only" "s/JSONExtractString\(raw,'name'\) IN/JSONExtractString(raw,'metric','name') IN/"
mutate "host predicate removed" "/AND JSONExtractString\(raw,'tags','host'\)/d"
mutate "mountpoint predicate removed" "/AND JSONExtractString\(raw,'tags','mountpoint'\)/d"
mutate "namespace predicate removed" "/AND JSONExtractString\(raw,'namespace'\)/d"
mutate "one-device HAVING removed" "/^HAVING uniqExact/d"
mutate "archive arm removed" 's/ UNION ALL SELECT dt, raw FROM s3Cluster\(primary, \\\$BS_TABLE_S3\) WHERE _row_type = 1//'
mutate "an unrecognised conjunct appended to the WHERE block" 's/^GROUP BY metric_name/  OR 1 = 1\nGROUP BY metric_name/'
# the aggregation side (pinned by exact text): each edit weakens a rule while every verdict fixture stays green
mutate "vmin aggregate turned into a maximum" "s/min\(JSONExtractFloat/max(JSONExtractFloat/"
mutate "distinct-hour count turned into a row count" "s/countDistinct\(toStartOfHour\(dt\)\)/count()/"
mutate "newest-age direction flipped" "s/dateDiff\('second', dt, now\(\)\)/dateDiff('second', now(), dt)/"
mutate "archive-arm selector changed" "s/_row_type = 1/_row_type = 2/"
mutate "one-device clause widened with OR 1 = 1" "s/^(HAVING .*) > 0\$/\1 > 0 OR 1 = 1/"
mutate "non-empty device guard removed" "s/ AND min\(length\(JSONExtractString\(raw,'tags','device'\)\)\) > 0\$//"
mutate "GROUP BY widened to one row per count" "s/^GROUP BY metric_name\$/GROUP BY metric_name, n/"
mutate "hot arm pointed at another table" 's/remote\(\\\$BS_TABLE\)/remote(\\$BS_TABLE_OTHER)/'
# the harness itself: an edit that changes only a comment must SURVIVE, or the battery cannot tell a harmless edit from a kill
if [[ "$BASE_RED" -eq 0 ]]; then
  run_mutant 's/^# Exit: 0 PASS.*$/# Exit: 0 PASS (comment-only control edit)/'
  if [[ "$M_LANDED" -eq 1 && "$M_AFTER" -eq 0 ]]; then echo "  ok   control: a comment-only edit survives (the battery discriminates)"; else echo "  FAIL control: a comment-only edit was landed=${M_LANDED} red=${M_AFTER}, want landed=1 red=0"; fails=$((fails + 1)); fi
  if [[ "$MUT_KILLED" -ne "$MUT_N" ]]; then echo "  FAIL mutation accounting: ${MUT_KILLED} killed of ${MUT_N} launched"; fails=$((fails + 1)); fi
fi
[[ "$MUT_N" -ge 28 ]] || { echo "  FAIL mutation floor: ${MUT_N} mutate rows < 28"; fails=$((fails + 1)); }

[[ "$fails" -eq 0 ]] && { echo "web2-rebirth-emptiness: all assertions and mutations passed"; exit 0; }
echo "web2-rebirth-emptiness: ${fails} FAILED"; exit 1
