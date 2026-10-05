#!/usr/bin/env bash
# Tests for scripts/web2-rebirth-emptiness.sh (#9372): every verdict arm, a transport failure that is NOT a verdict,
# and a mutation battery that removes each rule from a COPY and requires the battery to go red.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${DIR}/web2-rebirth-emptiness.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

row() { # <metric> <hours> <vmin> <vmax> <age>
  printf '{"metric_name":"%s","n":"2000","hours":"%s","vmin":%s,"vmax":%s,"newest_age_s":"%s"}\n' "$1" "$2" "$3" "$4" "$5"
}
good_used="$(row filesystem_used_bytes 168 28000000 28500000 240)"
good_total="$(row filesystem_total_bytes 168 20000000000 20000000000 240)"

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
  chk "RED: maximum over the 1 GiB ceiling" "RED reason=not_empty" "$(row filesystem_used_bytes 168 28000000 1073741825 240)\n${good_total}\n"
  chk "PASS: maximum exactly at the ceiling" "PASS" "$(row filesystem_used_bytes 168 28000000 1073741824 240)\n${good_total}\n"
  chk "RED: total metric absent" "RED reason=total_bytes_absent" "${good_used}\n"
  chk "RED: total below the volume range (root-disk-like small mount)" "RED reason=not_the_20gb_volume" "${good_used}\n$(row filesystem_total_bytes 168 1000000000 1000000000 240)\n"
  chk "RED: total above the volume range (root-disk-like large mount)" "RED reason=not_the_20gb_volume" "${good_used}\n$(row filesystem_total_bytes 168 20000000000 80000000000 240)\n"
  chk "RED: malformed used row" "RED reason=used_bytes_malformed" "{\"metric_name\":\"filesystem_used_bytes\"}\n${good_total}\n"
  chk "RED: unparseable body (HTML error page)" "RED reason=emptiness_body_unparseable" "<html>502</html>\n"
  chk "PASS: ClickHouse quoted 64-bit integers are accepted" "PASS" '{"metric_name":"filesystem_used_bytes","n":"9","hours":"168","vmin":"1","vmax":"2","newest_age_s":"5"}\n{"metric_name":"filesystem_total_bytes","n":"9","hours":"168","vmin":"20000000000","vmax":"20000000000","newest_age_s":"5"}\n'
  # SQL shape
  n=$((n + 1)); sql="$(w2r_sql_emptiness)"
  for frag in "host_name') = 'soleur-web-2'" "'tags','mountpoint') = '/mnt/data'" 'remote($BS_TABLE)' 's3Cluster(primary, $BS_TABLE_S3)' "INTERVAL 7 DAY" "'filesystem_used_bytes','filesystem_total_bytes'"; do
    [[ "$sql" == *"$frag"* ]] || printf 'FAILED SQL lacks %s\n' "$frag"
  done
  printf 'RAN %s\n' "$n"
}

fails=0; ran=0
report="$(battery "$SCRIPT" 2>&1)"
while IFS= read -r line; do
  case "$line" in FAILED*) fails=$((fails + 1)); printf '  FAIL %s\n' "${line#FAILED }" ;; RAN*) ran="${line#RAN }" ;; *) [[ -z "$line" ]] || printf '       %s\n' "$line" ;; esac
done <<<"$report"
printf 'real script: %s assertions, %s failed\n' "$ran" "$fails"
[[ "$ran" -ge 16 ]] || { echo "  FAIL assertion floor: ran ${ran} < 16"; fails=$((fails + 1)); }

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

mutate() { # <name> <sed-script>
  local name="$1" copy="$TMP/mut/web2-rebirth-emptiness.sh" after
  mkdir -p "$TMP/mut/lib"; cp "$SCRIPT" "$copy"; cp "${DIR}/lib/"*.sh "$TMP/mut/lib/"; cp "${DIR}/betterstack-query.sh" "$TMP/mut/" 2>/dev/null
  sed -i -E "$2" "$copy"
  if cmp -s "$SCRIPT" "$copy"; then echo "  FAIL mutation '${name}' did not change the script"; fails=$((fails + 1)); return; fi
  after="$(battery "$copy" 2>&1 | grep -c '^FAILED')"
  if [[ "$after" -gt 0 ]]; then echo "  ok   mutation killed: ${name} (${after} red)"; else echo "  FAIL mutation SURVIVED: ${name}"; fails=$((fails + 1)); fi
}
mutate "coverage rule removed"  's/elif \(\$u\.hours \| num\) < \$minh then/elif false then/'
mutate "staleness rule removed" 's/elif \(\$u\.newest_age_s \| num\) > \$maxage then/elif false then/'
mutate "ceiling rule removed"   's/elif \(\$u\.vmax \| num\) > \$maxused then/elif false then/'
mutate "volume-size rule removed" 's/elif \(\$t\.vmin \| num\) < \$tmin or \(\$t\.vmax \| num\) > \$tmax then/elif false then/'
mutate "zero-row arm removed"   's/if \$u == null then "RED reason=used_bytes_absent_or_host_dark"/if false then "x"/'
mutate "host predicate removed" "s/AND JSONExtractString\(raw,'host_name'\) = '\\$\{W2L_HOST_NAME\}'//"
mutate "mountpoint predicate removed" "s#AND JSONExtractString\(raw,'tags','mountpoint'\) = '/mnt/data'##"
mutate "archive arm removed" 's/ UNION ALL SELECT dt, raw FROM s3Cluster\(primary, \\\$BS_TABLE_S3\) WHERE _row_type = 1//'

[[ "$fails" -eq 0 ]] && { echo "web2-rebirth-emptiness: all assertions and mutations passed"; exit 0; }
echo "web2-rebirth-emptiness: ${fails} FAILED"; exit 1
