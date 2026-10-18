#!/usr/bin/env bash
# inngest-tls-soak-10136.sh -- follow-through probe for the Inngest link TLS soak (#10136, plan Guard 2, act A4).
#
# WHAT IT DECIDES. After the flag flip every web caller should dial https://10.0.1.40:8443. The Inngest host
# emits a `tls-health` row every 5 minutes (stage `tls-health` through inngest-boot-phone-home.sh, Better Stack
# source 2457081) carrying two nftables packet counters: legacy_8288_packets (the verdict-less counting rule
# BEFORE the plaintext :8288 accept) and tls_8443_packets (the positive control on :8443). The soak passes only if,
# over the 48 h from T:
#   (1) the series is GAP-FREE: no stretch longer than MAX_GAP_SEC (400 s) without a row, from T to T+48h. The emitter
#       is a systemd timer (OnUnitActiveSec=5min, default AccuracySec=1min), so a legitimate stretch is 300 s plus up to a
#       minute of timer slack (360 s at worst); one MISSED emit is a stretch of 600 s or more;
#   (2) ONE boot_id: a reboot resets the nft counters and restarts the clock (re-anchor, below);
#   (3) legacy_8288 DELTA is exactly 0: every row at or after the baseline row carries the BASELINE value. The
#       counter is cumulative since boot and legitimately non-zero before the flip, so a flat non-zero counter
#       passes and any increase fails (one late plaintext call is enough);
#   (4) tls_8443 delta >= 90% of the expected probe cadence: a flat counter at zero traffic proves nothing, so a
#       flat-at-zero legacy counter next to a flat tls_8443 counter FAILS;
#   (5) neither counter DEcreases without a boot_id change (a reset anomaly, not a clean series);
#   (6) every row in the window parses (dt, boot_id, both counters): a row without counters is a HOLE in the
#       series, not a row to skip.
# The predicate runs over EVERY row in the window (a check on the last row alone is the defect Guard 2 names).
#
# THE ANCHOR (T and the baseline row) is read from comments on issue #10136 through scripts/lib/trusted-verdict.sh,
# never from this script, so editing the script cannot move the window, and only a comment by an author with
# admin/maintain/write permission counts (the repo is public; see the lib header). The executing session posts, as
# plain lines (not fenced) when the flip is complete and the old containers have drained:
#   S1-SOAK-T: <UTC ISO>                 T = last prod swap complete plus old-container drain
#   S1-SOAK-BASELINE: dt=<UTC ISO> boot_id=<8 chars> legacy_8288_packets=<n> tls_8443_packets=<n>
#                                         the first `tls-health` row at or after T (read it with
#                                         `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh
#                                         --since <T> --grep stage=tls-health --limit 3`)
# The LATEST trusted pair wins, which is how a reboot is handled: the clock restarts and the operator re-anchors by
# posting a new pair. The anchor lives on the epic (#10136), which stays open, rather than on the A4 tracker whose
# number does not exist at build time; the A4 tracker only carries the directive:
#   <!-- soleur:followthrough script=scripts/followthroughs/inngest-tls-soak-10136.sh earliest=<T+2d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD,GH_TOKEN -->
# (unfenced, at column 0). The sweeper runs this under `env -i` with only those names forwarded, so the probe calls
# scripts/betterstack-query.sh DIRECTLY (no `doppler run`); the three BETTERSTACK_QUERY_* secrets are already wired in
# .github/workflows/scheduled-followthrough-sweeper.yml.
#
# THE QUERY. scripts/betterstack-query.sh --since T --until T+48h --grep stage=tls-health --limit 2000. The default
# limit (100) would silently keep the newest ~8 hours of a 48 h window (576 rows at 5 minutes); --no-archive is never
# passed, because the hot window is ~40 minutes and would answer 48 h with 40. LIMIT-FILLING IS A READ FAILURE: the
# query keeps the NEWEST rows, so a result as long as the limit may have lost the oldest ones and would read as a gap
# that is not one (exit 3). Rows are FIELD-ISOLATED from the decoded `raw` column (marker SOLEUR_INNGEST_BOOT_STAGE and
# stage tls-health), because --grep is an unanchored LIKE that also matches any other row QUOTING the string (a webhook
# payload, the refusal marker's journald line).
#
# EXPECTED TLS CADENCE. After the flip web-1's consumer probe dials the TLS listener once a minute (60 connections an
# hour; inngest-consumer-probe.timer), and the app's sends add more. A TLS connection costs at least
# TLS_MIN_PKTS_PER_CONN client packets (SYN, ACK, ClientHello, Finished, request, FIN; a conservative floor), so the
# expected packet delta over 48 h is 60 * 48 * 4 = 11520 and 90% of it is 10368. This is a positive control, not a
# traffic SLO.
#
# Exit semantics (scripts/sweep-followthroughs.sh contract):
#   0 = PASS   1 = FAIL (a reason is printed per violated check)
#   2 = NOT YET / transient: no anchor yet, the 48 h window is not over, the query failed, or it returned no tls-health
#       rows (a dark emitter and a broken read look the same from here; the output says which reads were made)
#   3 = CANNOT ESTABLISH: a tool or secret is missing, the comment/permission read failed (a failed trust read is never
#       "no anchor"), the anchor is malformed, the query result may be truncated, or a local projection failed
#   78 = refused to run under xtrace while a credential is set (#7797)
#
# RETIREMENT: when the A4 tracker closes, delete this file, its .test.sh, the run_suite line in scripts/test-all.sh and
# the rows in scripts/suite-shard-legs.tsv and scripts/suite-durations.tsv.
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}${GITHUB_TOKEN:+x}${BETTERSTACK_QUERY_PASSWORD:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO="jikig-ai/soleur"
ANCHOR_ISSUE=10136
WINDOW_SEC=172800            # 48 h
MAX_GAP_SEC=400              # 300 s cadence + up to 60 s timer slack = 360 s widest legitimate stretch; one missed emit is >= 600 s
QUERY_LIMIT=2000             # 576 rows expected; >= 1000 always (the default 100 truncates)
TLS_PROBES_PER_HOUR=60
TLS_MIN_PKTS_PER_CONN=4
TLS_PCT=90
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# test seams (the sweeper runs this under env -i, so they are inert in production)
BQ="${SOAK_BQ_BIN:-$HERE/../betterstack-query.sh}"

for need in gh jq awk date sort grep sed tr tail head base64 mktemp rm dirname; do
  command -v "$need" >/dev/null 2>&1 || { echo "CANNOT ESTABLISH: $need is not installed"; exit 3; }
done
[ -n "${GH_TOKEN:-}" ] || { echo "CANNOT ESTABLISH: GH_TOKEN is not set (the tracker directive must declare secrets=GH_TOKEN)"; exit 3; }
for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  [ -n "${!v:-}" ] || { echo "CANNOT ESTABLISH: $v is not set (the tracker directive must declare it in secrets=)"; exit 3; }
done
[ -x "$BQ" ] || { echo "CANNOT ESTABLISH: betterstack-query.sh is not executable at $BQ"; exit 3; }
# shellcheck source=../lib/trusted-verdict.sh
if ! source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" 2>/dev/null && pwd)/trusted-verdict.sh" \
   || ! declare -F trusted_verdict_bodies >/dev/null; then
  echo "CANNOT ESTABLISH: trusted-verdict lib unavailable (missing, unsourceable, or without trusted_verdict_bodies)"; exit 3
fi

NOW="${SOAK_NOW_EPOCH:-$(date -u +%s)}"
[[ "$NOW" =~ ^[1-9][0-9]*$ ]] || { echo "CANNOT ESTABLISH: SOAK_NOW_EPOCH is not an epoch"; exit 3; }

fail_marker() { echo "CANNOT ESTABLISH: anchor marker read failed ($1)"; exit 3; }
bad_anchor() { echo "CANNOT ESTABLISH: malformed anchor on #$ANCHOR_ISSUE ($1)"; exit 3; }

# --- the anchor: trusted authors only -------------------------------------------------------------------------------
bodies="$(trusted_verdict_bodies "$ANCHOR_ISSUE" "$REPO")" \
  || { echo "CANNOT ESTABLISH: comment or permission read failed (#$ANCHOR_ISSUE, trusted-author resolution)"; exit 3; }
# Each marker read is a grep | tail chain, and a bare `x="$(chain)"` drops the status of every stage: a failing tail or a
# grep error (rc >= 2) would read as "no marker" and turn a malformed read into NOT YET. The whole status array is taken in
# ONE assignment and checked: grep rc 1 (no match) is an answer, every other non-zero status is CANNOT ESTABLISH.
marker_last() {   # <marker name>: sets MARKER_VAL to the text after "<name>: " on the LAST trusted line ("" = none)
  local name="$1" r st
  r="$(printf '%s\n' "$bodies" | tr -d '\r' | grep -E "^${name}: " | tail -n 1; printf '#%s' "${PIPESTATUS[*]}")"
  st="${r##*#}"; MARKER_VAL="${r%#*}"; MARKER_VAL="${MARKER_VAL%$'\n'}"
  case "$st" in "0 0 0 0"|"0 0 1 0") : ;; *) fail_marker "$name" ;; esac
  MARKER_VAL="${MARKER_VAL#"${name}": }"
}
marker_last S1-SOAK-T; t_raw="$MARKER_VAL"
marker_last S1-SOAK-BASELINE; base_raw="$MARKER_VAL"
if [ -z "$t_raw" ] || [ -z "$base_raw" ]; then
  echo "NOT YET: no trusted S1-SOAK-T / S1-SOAK-BASELINE anchor on #$ANCHOR_ISSUE (the flip has not been recorded, or the markers were posted by an author without write permission, or inside a fenced block)"
  exit 2
fi
ISO_RE='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'
[[ "$t_raw" =~ ^${ISO_RE}$ ]] || bad_anchor "S1-SOAK-T is not a UTC ISO time"
BASE_RE="^dt=(${ISO_RE}) boot_id=([0-9a-f-]{8,36}) legacy_8288_packets=([0-9]+) tls_8443_packets=([0-9]+)\$"
[[ "$base_raw" =~ $BASE_RE ]] || bad_anchor "S1-SOAK-BASELINE does not match 'dt=<ISO> boot_id=<id> legacy_8288_packets=<n> tls_8443_packets=<n>'"
base_dt="${BASH_REMATCH[1]}"; base_boot="${BASH_REMATCH[2]}"; base_leg="${BASH_REMATCH[3]}"; base_tls="${BASH_REMATCH[4]}"
[[ "$base_boot" =~ ^-+$ ]] && bad_anchor "S1-SOAK-BASELINE boot_id is dashes only"
t_epoch="$(date -u -d "$t_raw" +%s 2>/dev/null)" || bad_anchor "S1-SOAK-T time"
bdt_epoch="$(date -u -d "$base_dt" +%s 2>/dev/null)" || bad_anchor "S1-SOAK-BASELINE time"
# The baseline is the first row after the drain: at or after T, and within one cadence of it, otherwise the stretch between T
# and the baseline is an unmeasured hole inside the window.
if [ "$bdt_epoch" -lt "$t_epoch" ] || [ $((bdt_epoch - t_epoch)) -gt "$MAX_GAP_SEC" ]; then
  bad_anchor "the baseline row ($base_dt) must be the first tls-health row at or after T ($t_raw), within ${MAX_GAP_SEC} s"
fi
end_epoch=$((t_epoch + WINDOW_SEC))
end_iso="$(date -u -d "@$end_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || bad_anchor "window end"
if [ "$NOW" -lt "$end_epoch" ]; then
  echo "NOT YET: the 48 h soak window opened at $t_raw closes at $end_iso (about $(( (end_epoch - NOW) / 60 )) minutes from now); no verdict before then"
  exit 2
fi

# --- the series: the archive arm is IN (never --no-archive), the limit is >= 1000 ------------------------------------
raw="$("$BQ" --since "$t_raw" --until "$end_iso" --grep stage=tls-health --limit "$QUERY_LIMIT" 2>/dev/null)"; qrc=$?
if [ "$qrc" -ne 0 ]; then
  echo "NOT YET: the Better Stack query failed (rc=$qrc): a probe fault, not a verdict"
  exit 2
fi
nlines="$(printf '%s' "$raw" | awk 'END { print NR }')" || { echo "CANNOT ESTABLISH: row count failed"; exit 3; }
if [ "$nlines" -ge "$QUERY_LIMIT" ]; then
  echo "CANNOT ESTABLISH: the query returned $nlines rows, as many as --limit $QUERY_LIMIT: the oldest rows may have been truncated, and a truncated series reads as a gap that is not one"
  exit 3
fi
# Field isolation + projection: dt (epoch), boot_id, legacy_8288_packets, tls_8443_packets, tab-separated, "-" for a field that
# is absent. A row whose dt will not parse keeps "-" in column 1 so the awk reports it as unparseable instead of dropping it.
rows="$(printf '%s\n' "$raw" | jq -R -r '
  def kv($d; $k): (first($d | capture("(^|\\s)" + $k + "=(?<v>[^\\s]+)") | .v) // "-");
  fromjson? | objects | . as $o
  | ($o.raw? | strings | fromjson? | objects) as $r
  | select($r.marker == "SOLEUR_INNGEST_BOOT_STAGE" and $r.stage == "tls-health")
  | (($o.dt // "") | tostring | sub("T"; " ") | sub("Z$"; "") | sub("\\.[0-9]+$"; "")) as $d
  | (try ($d | strptime("%Y-%m-%d %H:%M:%S") | mktime) catch null) as $e
  | ($r.detail // "") as $det
  | [($e // "-"), kv($det; "boot_id"), kv($det; "legacy_8288_packets"), kv($det; "tls_8443_packets")] | @tsv')" \
  || { echo "CANNOT ESTABLISH: row projection failed (local jq)"; exit 3; }
if [ -z "$rows" ]; then
  echo "NOT YET: no tls-health rows between $t_raw and $end_iso ($nlines rows matched the query, none was a tls-health emit): the series is empty, which is a broken read or a dark emitter; read it with: doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since $t_raw --until $end_iso --grep stage=tls-health --limit 5"
  exit 2
fi
rows="$(printf '%s\n' "$rows" | sort -s -n -k1,1)" || { echo "CANNOT ESTABLISH: row sort failed"; exit 3; }

need_tls=$(( TLS_PROBES_PER_HOUR * (WINDOW_SEC / 3600) * TLS_MIN_PKTS_PER_CONN * TLS_PCT / 100 ))

# --- the predicate: ONE awk pass over every row. Each check is ONE line tagged `# CHECK-<NAME>`; the suite deletes
# one such line at a time from a copy and requires the targeted fixture to flip to PASS. mawk-safe (no interval
# expressions, no strftime): times are printed as hours after T.
# shellcheck disable=SC2016  # awk program text: the single quotes are intentional
AWK_PROG='
function hrs(e) { return sprintf("T+%.1fh", (e - T) / 3600) }
function addfail(tag, cap, msg) { nfail++; cnt[tag]++; if (cnt[tag] <= cap) print "REASON " tag " " msg }
BEGIN { prev = T; pboot = BOOT; pleg = BLEG; ptls = BTLS; last_tls = BTLS; maxgap = 0; nrow = 0; nfail = 0 }
{
  e = $1
  if (e ~ /^[0-9]+$/ && (e + 0 < T || e + 0 > WEND)) next
  boot = $2; leg = $3; tls = $4
  if (e !~ /^[0-9]+$/ || boot !~ /^[0-9a-f-]+$/ || boot ~ /^-+$/ || length(boot) < 8 || length(boot) > 36 || leg !~ /^[0-9]+$/ || tls !~ /^[0-9]+$/) { addfail("parse", 3, "unparseable tls-health row (dt, boot_id or a counter missing or malformed: dt=" e " boot_id=" boot " legacy_8288_packets=" leg " tls_8443_packets=" tls ")"); next }   # CHECK-PARSE
  e += 0; leg += 0; tls += 0
  nrow++
  gap = e - prev
  if (gap > maxgap) maxgap = gap
  if (gap > MAXGAP) addfail("gap", 3, "gap: no tls-health row for " gap " s after " hrs(prev) " (limit " MAXGAP " s; a missed 5-minute emit is >= 600 s)")   # CHECK-GAP
  prev = e
  if (boot != pboot) addfail("boot_id", 2, "boot_id changed from " pboot " to " boot " at " hrs(e) ": the host rebooted, the nft counters reset and the soak clock restarts; re-anchor with a new S1-SOAK-T / S1-SOAK-BASELINE pair")   # CHECK-BOOT
  if (e >= BDT) {
    if (boot == pboot && leg < pleg) addfail("decrease", 2, "legacy_8288 decreased from " pleg " to " leg " at " hrs(e) " without a boot_id change (reset anomaly)")   # CHECK-DECREASE
    if (boot == pboot && tls < ptls) addfail("decrease", 2, "tls_8443 decreased from " ptls " to " tls " at " hrs(e) " without a boot_id change (reset anomaly)")   # CHECK-TLSDECREASE
    if (leg > BLEG) addfail("legacy_8288", 1, "legacy_8288 delta " (leg - BLEG) " > 0 at " hrs(e) " (baseline " BLEG ", now " leg "): a plaintext caller still dials :8288")   # CHECK-LEGACY
    pleg = leg; ptls = tls; last_tls = tls
  }
  pboot = boot
}
END {
  if (WEND - prev > MAXGAP) addfail("gap", 3, "gap: no tls-health row for " (WEND - prev) " s before the window closed (last row " hrs(prev) ", limit " MAXGAP " s)")   # CHECK-GAP
  delta = last_tls - BTLS
  if (delta < NEED) addfail("tls_8443", 1, "tls_8443 delta " delta " < required " NEED " (" PCT "% of the expected probe cadence): the positive control saw too little TLS traffic, so a flat legacy counter proves nothing")   # CHECK-TLSDELTA
  print "STATS rows=" nrow " maxgap=" maxgap " tls_delta=" delta " legacy_last=" pleg
  print "VERDICT " (nfail > 0 ? "FAIL" : "PASS")
}'
verdict="$(printf '%s\n' "$rows" | awk -v T="$t_epoch" -v WEND="$end_epoch" -v BDT="$bdt_epoch" -v BOOT="$base_boot" \
            -v BLEG="$base_leg" -v BTLS="$base_tls" -v MAXGAP="$MAX_GAP_SEC" -v NEED="$need_tls" -v PCT="$TLS_PCT" "$AWK_PROG")" \
  || { echo "CANNOT ESTABLISH: the series predicate failed to run (local awk)"; exit 3; }

stats="$(printf '%s\n' "$verdict" | grep '^STATS ' | head -n 1)" || stats=""
final="$(printf '%s\n' "$verdict" | grep '^VERDICT ' | tail -n 1)" || final=""
case "$final" in
  "VERDICT PASS")
    echo "PASS: tls-health series gap-free for 48 h from $t_raw (${stats#STATS }), one boot_id ($base_boot), legacy_8288 delta 0 (flat at $base_leg), tls_8443 delta >= $need_tls"
    exit 0 ;;
  "VERDICT FAIL")
    echo "FAIL: the 48 h TLS soak from $t_raw did not hold (${stats#STATS }):"
    printf '%s\n' "$verdict" | grep '^REASON ' | sed 's/^REASON [a-z0-9_]* /  - /'
    exit 1 ;;
  *)
    echo "CANNOT ESTABLISH: the series predicate printed no verdict"
    exit 3 ;;
esac
