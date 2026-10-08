#!/usr/bin/env bash
# web2-luks-live-6931.test.sh — fixture harness for the #6931 soak-gated closure probe.
#
# The probe sources scripts/lib/web2-luks-rows.sh (the SAME query + parse the daily verify leg uses) and grades
# from Better Stack rows ALONE: it holds no Doppler credential and never reads the soak marker. A PATH-stubbed
# `curl` serves the Better Stack query (via the real scripts/betterstack-query.sh) and REFUSES any request it was
# not taught (exit 64). The stub HONOURS the SQL it receives: it applies the `INTERVAL n HOUR|DAY` window and the
# `LIMIT n` to the fixture and records the SQL, so a probe that narrows its window, drops the 504 h cap or shrinks
# the row limit sees different rows and different SQL, and a test can say so. It also refuses to run when any
# secret-shaped variable other than the three BETTERSTACK_QUERY_* values reached the query child.
# Every sweeper exit code is driven and each verdict is pinned by BOTH its exit code and its leading word.
# Every row is synthesized. The scenario ids are REGISTERED: deleting a scenario reds the suite by name.
#
# The probe's exit 0 closes the tracker, so the arms that matter are the ones that must NOT reach it: a young
# readiness row, too few distinct days, a non-green row in the window, a stale / non-LUKS newest row, an
# unanswered read. Fixture boundaries sit a minute either side of the second they test, never on it.
#
# Registered explicitly in scripts/test-all.sh (scripts/followthroughs/*.test.sh is not in SUITE_GLOBS).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
PROBE="$DIR/web2-luks-live-6931.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }
# Instrument self-test: drive no() and ok() once each and require that EACH moved its own counter.
no "self-test (expected)" 2>/dev/null; ok "self-test (expected)" >/dev/null
if [ "$fail" -ne 1 ] || [ "$pass" -ne 1 ]; then
  printf 'FATAL: the verdict helpers do not count (fail=%s pass=%s)\n' "$fail" "$pass" >&2
  exit 1
fi
pass=0; fail=0

# expect <label> <command...> — ONE scored command per claim (a compound `A && B` would let B's result vanish).
expect() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }

UA=11111111-2222-3333-4444-555555555555
UB=66666666-7777-8888-9999-aaaaaaaaaaaa
BIN="$WORK/bin"; mkdir -p "$BIN" "$WORK/fx"
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
# The ONE egress site (betterstack-query.sh run_sql). Refuses everything it was not taught.
url=""; data=""; user=""
while [ $# -gt 0 ]; do
  case "$1" in
    -d) data="$2"; shift 2 ;;
    # The Basic-auth pair rides curl's stdin config (`--config -`, one `user = "USER:PASS"` line), never argv (#9597).
    --config) if [ "$2" = - ]; then cfg="$(cat)"; user="${cfg#user = \"}"; user="${user%%\"*}"; fi; shift 2 ;;
    -u) echo "curl stub: the credential pair is on ARGV (-u); it must ride stdin (--config -)" >&2; exit 64 ;;
    https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
# Credential hygiene: nothing secret-shaped but the Better Stack password may be in the query child's environment.
leak="$(env | cut -d= -f1 | grep -E 'TOKEN|SECRET|PASSWORD|KEY|CREDENTIAL|AUTH|DOPPLER' | grep -vxE 'BETTERSTACK_QUERY_PASSWORD' || true)"
if [ -n "$leak" ]; then printf '%s\n' "$leak" >> "$LEAK"; echo "curl stub: secret-shaped variable(s) in the query child: $leak" >&2; exit 64; fi
case "$url" in "https://fixture-connect.betterstackdata.com?"*) : ;; *) echo "curl stub: REFUSED destination $url" >&2; exit 64 ;; esac
[ "$user" = fixture-user:fixture-pass ] || { echo "curl stub: REFUSED credentials" >&2; exit 64; }
case "$data" in
  *"'luks-monitor'"*) kind=probe ;;
  *SOLEUR_FRESH_BOOT_READY*) kind=ready ;;
  *) echo "curl stub: REFUSED query" >&2; exit 64 ;;
esac
printf '%s\n' "$kind" >> "$CALLS"
printf '%s:%s\n' "$kind" "$(printf '%s' "$data" | tr '\n' ' ')" >> "$SQLLOG"
if [ -f "$FX/bs.mode.$kind" ]; then
  case "$(cat "$FX/bs.mode.$kind")" in 503) printf '{"error":"x"}'; exit 22 ;; timeout) exit 28 ;; esac
fi
# Apply the SQL window and limit to the fixture, newest first (what ORDER BY dt DESC LIMIT n returns).
n="$(printf '%s' "$data" | sed -nE 's/.*INTERVAL ([0-9]+) (HOUR|DAY).*/\1/p' | head -1)"
u="$(printf '%s' "$data" | sed -nE 's/.*INTERVAL ([0-9]+) (HOUR|DAY).*/\2/p' | head -1)"
lim="$(printf '%s' "$data" | sed -nE 's/^ORDER BY dt DESC LIMIT ([0-9]+)$/\1/p' | head -1)"
[ -n "$n" ] && [ -n "$u" ] && [ -n "$lim" ] || { echo "curl stub: no window/limit in the SQL" >&2; exit 64; }
mult=3600; [ "$u" = DAY ] && mult=86400
if jq -e -s 'all(.[]; type == "object")' "$FX/$kind" >/dev/null 2>&1; then
  jq -c -s --argjson w "$((n * mult))" --argjson l "$lim" \
    'map(select((.age_s | tonumber) < $w)) | sort_by(.age_s | tonumber) | .[:$l][]' "$FX/$kind"
else
  cat "$FX/$kind"
fi
exit 0
STUB
chmod +x "$BIN/curl"

H=3600; D=86400; SOAK=$((3 * D))
# row <age_s> <message>  — a probe row as the real query returns it (JSONEachRow, age_s server-computed)
row() { jq -cn --arg age "$1" --arg m "$2" '{ts: "2026-10-01 04:41:00", age_s: $age, message: $m, host_name: "soleur-web-2", ident: "luks-monitor", unit: "luks-monitor.service"}'; }
okmsg() { printf 'OK: /mnt/data is LUKS-backed (device_type=%s mount_source=/dev/mapper/workspaces escrow=%s header=readable boot_id=%s)' "${1:-crypto_LUKS}" "${2:-ok}" "${3:-$UB}"; }
failmsg() { printf 'FAIL (device_not_luks): device_type=ext4 mount_source=/dev/sdb mapper_present=no'; }
# rdy <age_s> [key=value ...]  — a readiness row; overrides replace the default field in place
rdy() {
  local age="$1" m k v; shift
  declare -A f=([ready]=1 [stage]=cloud_init_complete [token]=1 [vector]=1 [volume]=1 [luks]=1 [luks_arm]=formatted [escrow]=ok [boot_id]=$UA [host]=soleur-web-2 [reason]=none [boot_window_s]=900)
  for kv in "$@"; do f[${kv%%=*}]="${kv#*=}"; done
  m="SOLEUR_FRESH_BOOT_READY"
  for k in ready stage token vector volume luks luks_arm escrow boot_id host reason boot_window_s; do m="$m $k=${f[$k]}"; done
  jq -cn --arg age "$age" --arg m "$m" '{ts: "2026-09-28 04:00:00", age_s: $age, message: $m}'
}
# iso_ago <seconds>: GNU date applies "ago" to the LAST unit only, so a compound "4 days 1 minute ago" is in the
# future; seconds are unambiguous.
iso_ago() { date -u -d "$1 seconds ago" +%Y-%m-%dT%H:%M:%SZ; }

reset_fx() { rm -rf "$WORK/fx"; mkdir -p "$WORK/fx"; : > "$WORK/calls"; : > "$WORK/sql"; : > "$WORK/leak"; : > "$WORK/fx/probe"; : > "$WORK/fx/ready"; }
ready() { cat > "$WORK/fx/ready"; }
probe() { cat > "$WORK/fx/probe"; }
# soak_probes <ready_age_s> — one GREEN probe row a day (the second journal copy on the first), newest 1 h old,
# every row younger than the readiness row.
soak_probes() { local a=$((H)); row "$a" "$(okmsg)"; row "$((a + 1))" "[luks-monitor] $(okmsg)"; a=$((a + D)); while [ "$a" -lt "$1" ]; do row "$a" "$(okmsg)"; a=$((a + D)); done; }
# a window that is OPEN (earliest was a day ago; it closes at earliest + 4 d) vs CLOSED (a minute past)
E_OPEN="$(iso_ago $D)"

IDS=()
# run <want-rc> <want-word> <label: "Tnn text"> [ENV=VAL ...]
run() {
  local want_rc="$1" want_word="$2" label="$3" out rc=0; shift 3
  IDS+=("${label%% *}")
  out="$(env -i PATH="$BIN:/usr/bin:/bin" HOME="$WORK" FX="$WORK/fx" CALLS="$WORK/calls" SQLLOG="$WORK/sql" LEAK="$WORK/leak" \
    SENTRY_ACTIONS_RO_TOKEN=decoy-sentry GH_TOKEN=decoy-gh DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER=decoy-marker \
    BETTERSTACK_QUERY_HOST=fixture-connect.betterstackdata.com BETTERSTACK_QUERY_USERNAME=fixture-user \
    BETTERSTACK_QUERY_PASSWORD=fixture-pass SOLEUR_FT_EARLIEST="$E_OPEN" "$@" \
    bash "${PROBE_UNDER_TEST:-$PROBE}" 2>&1)" || rc=$?
  LAST_OUT="$out"
  # The verdict word starts a line; the helper's own diagnostics (stderr, merged here) may precede it.
  if [ "$rc" = "$want_rc" ] && grep -q "^$want_word" <<<"$out"; then ok "$label → exit $want_rc ($want_word)"
  else no "$label: want exit $want_rc + '$want_word', got exit $rc: $(tr '\n' ' ' <<<"$out" | head -c 260)"; fi
  if grep -q 'decoy-' <<<"$out"; then no "$label: a decoy credential reached the probe's output"; fi
  if [ -s "$WORK/leak" ]; then no "$label: a secret-shaped variable reached the Better Stack query child: $(tr '\n' ' ' < "$WORK/leak")"; fi
}
# say <label> <needle>: the last run's output names the REASON, not just the verdict word
said() { local label="$1" needle="$2"; if grep -qF -- "$needle" <<<"$LAST_OUT"; then ok "$label"; else no "$label (output lacked '$needle': $(head -c 200 <<<"$LAST_OUT"))"; fi; }

# --- the PASS arms ------------------------------------------------------------------------------------------
reset_fx; rdy $((4 * D)) | ready; soak_probes $((4 * D)) | probe
run 0 PASS "T01 readiness 4d old, a GREEN probe row every day since, none red"
said "T01 the PASS line names the newest row's age" 'age_s=3600'
expect "T01 exactly one readiness read and one probe read, nothing else" test "$(tr '\n' ' ' < "$WORK/calls")" = "ready probe "
expect "T01 the probe read asks for the readiness age + 2 h (98 h) and 2000 rows" grep -q "^probe:.*INTERVAL 98 HOUR.*LIMIT 2000" "$WORK/sql"
expect "T01 the readiness read asks for the 90-day lookback and 20 rows" grep -q "^ready:.*INTERVAL 90 DAY.*LIMIT 20" "$WORK/sql"
expect "T01 the probe read pins the emitting unit as well as the identifier" grep -qF "JSONExtractString(raw,'_SYSTEMD_UNIT') = 'luks-monitor.service'" "$WORK/sql"
expect "T01 the readiness read anchors the marker with startsWith and carries no LIKE wildcard" bash -c "grep '^ready:' '$WORK/sql' | grep -qF \"startsWith(JSONExtractString(raw,'message'), 'SOLEUR_FRESH_BOOT_READY ')\" && ! grep '^ready:' '$WORK/sql' | grep -q LIKE"

reset_fx; rdy $((4 * D)) | ready; { soak_probes $((4 * D)); row $((6 * D)) "$(failmsg)"; } | probe
run 0 PASS "T02 a FAIL row from BEFORE the readiness row does not count (the rebirth superseded it)"

reset_fx; rdy $((SOAK + 60)) | ready; soak_probes $((SOAK + 60)) | probe
run 0 PASS "T03 readiness one minute past 72 h with three daily buckets: the soak is met"

# No reboot is required (owner decision 2026-10-07, ADR-263 addendum 2026-10-08): the soak is met on the instance's readiness row
# (luks_arm formatted|opened) plus three GREEN days, whatever boot_id the probe rows carry. The five cases below used to
# need a boot_id that differed from the readiness row's; they now pass, and T04f-T04h pin the arm that replaced it.
reset_fx; rdy $((4 * D)) "boot_id=unknown" | ready; { row $H "$(okmsg crypto_LUKS ok unknown)"; row $((H + D)) "$(okmsg crypto_LUKS ok unknown)"; row $((H + 2 * D)) "$(okmsg crypto_LUKS ok $UB)"; } | probe
run 0 PASS "T04 an unknown readiness boot_id no longer blocks the soak (a reboot is not required)"
reset_fx; rdy $((4 * D)) | ready; { row $H "$(okmsg crypto_LUKS ok $UA)"; row $((H + D)) "$(okmsg crypto_LUKS ok $UA)"; row $((H + 2 * D)) "$(okmsg crypto_LUKS ok $UA)"; } | probe
run 0 PASS "T04b every probe row carries the readiness row's boot_id: three GREEN days on the one boot are enough"
reset_fx; rdy $((4 * D)) | ready; { row $H "$(okmsg crypto_LUKS ok unknown)"; row $((H + D)) "$(okmsg crypto_LUKS ok $UB)"; row $((H + 2 * D)) "$(okmsg crypto_LUKS ok $UB)"; } | probe
run 0 PASS "T04c the NEWEST probe row reports an unknown boot_id: the boot is not part of the rule"
reset_fx; rdy $((4 * D)) "boot_id=unknown" | ready; { row $H "$(okmsg crypto_LUKS ok $UB)"; row $((H + D)) "$(okmsg crypto_LUKS ok $UB)"; row $((H + 2 * D)) "$(okmsg crypto_LUKS ok $UB)"; } | probe
run 0 PASS "T04e the READINESS row reports an unknown boot_id while every probe row carries a known one: still met"
reset_fx; rdy $((4 * D)) | ready; { row $H "$(okmsg crypto_LUKS ok $UB)"; row $((H + D)) "$(okmsg crypto_LUKS ok $UA)"; row $((H + 2 * D)) "$(okmsg crypto_LUKS ok $UA)"; } | probe
run 0 PASS "T04d the newest probe row is from a new boot (older rows may predate the reboot)"
# The arm that replaced the reboot proof: the NEWEST readiness row must say the boot formatted or opened the volume.
reset_fx; { rdy $((5 * D)); rdy $((4 * D)) "luks_arm=noop"; } | ready; soak_probes $((4 * D)) | probe
run 2 "NOT YET" "T04f an older formatted row and a NEWER noop row: noop is not formatted|opened, so the soak is not met"
said "T04f the reason names the arm" 'luks_arm=noop'
reset_fx; rdy $((4 * D)) "luks_arm=opened" | ready; soak_probes $((4 * D)) | probe
run 0 PASS "T04g luks_arm=opened (a fresh host that opened the existing volume) meets the soak"
reset_fx; { rdy $((5 * D)) "luks_arm=noop"; rdy $((4 * D)); } | ready; soak_probes $((4 * D)) | probe
run 0 PASS "T04h an older noop row and a NEWER formatted row: the newest readiness row decides"

reset_fx; rdy $((30 * D)) | ready; soak_probes $((30 * D)) | probe
run 0 PASS "T05 a readiness row 30 days old: the probe lookback is capped at 504 h and the soak is still graded"
expect "T05 the capped read asks for exactly 504 hours" grep -q "^probe:.*INTERVAL 504 HOUR" "$WORK/sql"

# --- the arms that must NOT reach exit 0 -----------------------------------------------------------------------
reset_fx; rdy $((SOAK - 60)) | ready; soak_probes $((SOAK - 60)) | probe
run 2 "NOT YET" "T06 readiness one minute short of 72 h: the soak is still running"
reset_fx; rdy $((4 * D)) | ready; { row $H "$(okmsg)"; row $((H + D)) "$(okmsg)"; } | probe
run 2 "NOT YET" "T07 only two distinct days of GREEN probe rows"
said "T07 the output says how many days it saw" '2 of 3 distinct days'
reset_fx; rdy $((4 * D)) | ready; { row $H "$(okmsg)"; row $((H + 1)) "[luks-monitor] $(okmsg)"; row $((2 * H)) "$(okmsg)"; } | probe
run 2 "NOT YET" "T08 three rows inside ONE 24 h bucket are one day, not three"
reset_fx; rdy $((4 * D)) "escrow=missing" | ready; soak_probes $((4 * D)) | probe
run 2 "NOT YET" "T09 a readiness row with escrow=missing does not open the soak"
said "T09 the reason is named" 'ready_escrow'
reset_fx; rdy $((4 * D)) "luks=0" | ready; soak_probes $((4 * D)) | probe
run 2 "NOT YET" "T10 a readiness row with luks=0 does not open the soak"
reset_fx; rdy $((4 * D)) "ready=0" | ready; soak_probes $((4 * D)) | probe
run 2 "NOT YET" "T11 a readiness row with ready=0 does not open the soak"
reset_fx; rdy $((4 * D)) "host=soleur-web-1" | ready; soak_probes $((4 * D)) | probe
run 2 "NOT YET" "T12 a readiness row naming another host does not open the soak"
reset_fx; soak_probes $((4 * D)) | probe
run 2 "NOT YET" "T13 no readiness row at all (never reborn, or aged out of the 90-day lookback): nothing opens the soak"
said "T13 the reason is named" 'no_ready_row'

reset_fx; rdy $((4 * D)) | ready; { soak_probes $((4 * D)); row $((D + H)) "$(failmsg)"; } | probe
run 1 FAIL "T14 a FAIL row after the readiness row spoils the soak at once, even with the window open"
reset_fx; rdy $((4 * D)) | ready; { soak_probes $((4 * D)); row $((D + H)) "OK: /mnt/data is LUKS-backed (device_type=crypto_LUKS mount_source=/dev/mapper/workspaces escrow=ok header=readable boot_id=$UA escrow=ok)"; } | probe
run 1 FAIL "T15 a MALFORMED verdict row (duplicate key) after the readiness row is red too"
reset_fx; rdy $((4 * D)) | ready; { soak_probes $((4 * D)); row $((D + H)) "$(okmsg ext4)"; } | probe
run 1 FAIL "T16 an OK line that does not report crypto_LUKS is red too"

reset_fx; rdy $((4 * D)) | ready; { row $((27 * H)) "$(okmsg)"; row $((27 * H + D)) "$(okmsg)"; row $((27 * H + 2 * D)) "$(okmsg)"; } | probe
run 2 "NOT YET" "T17 three GREEN days but the NEWEST probe row is 27 h old: the probe is dark, not a pass"
reset_fx; rdy $((4 * D)) | ready; { row $((27 * H)) "$(okmsg)"; row $((27 * H + D)) "$(okmsg)"; row $((27 * H + 2 * D)) "$(okmsg)"; } | probe
run 1 FAIL "T18 the same dark probe once the soak window has closed" SOLEUR_FT_EARLIEST="$(iso_ago $((4 * D + 60)))"
reset_fx; rdy $((4 * D)) | ready; row $((2 * H)) "$(okmsg ext4)" | probe
run 1 FAIL "T19 the newest probe row is not crypto_LUKS (an OK-shaped line on the wrong backing)"

# --- the soak window: a dead probe from birth must not sit at NOT YET forever -----------------------------------
reset_fx; rdy $((4 * D)) | ready
run 2 "NOT YET" "T20 a GREEN readiness row and zero probe rows, window open"
run 2 "NOT YET" "T21 the same, one minute BEFORE the window closes (earliest + 4 d)" SOLEUR_FT_EARLIEST="$(iso_ago $((4 * D - 60)))"
run 1 FAIL "T22 the same, one minute AFTER the window closes: a dead probe is a FAIL" SOLEUR_FT_EARLIEST="$(iso_ago $((4 * D + 60)))"
run 2 "NOT YET" "T23 no clock (empty SOLEUR_FT_EARLIEST): nothing ever FAILs on the window" SOLEUR_FT_EARLIEST=
run 2 "NOT YET" "T24 an unparseable SOLEUR_FT_EARLIEST is no clock either" SOLEUR_FT_EARLIEST=not-a-date
reset_fx; soak_probes $((4 * D)) | probe
run 1 FAIL "T25 no readiness row and the window closed: FAIL" SOLEUR_FT_EARLIEST="$(iso_ago $((4 * D + 60)))"
reset_fx; rdy $((4 * D)) "escrow=missing" | ready; soak_probes $((4 * D)) | probe
run 1 FAIL "T26 an unqualified readiness row and the window closed: FAIL" SOLEUR_FT_EARLIEST="$(iso_ago $((4 * D + 60)))"

# --- unanswered reads are NOT YET, never a verdict (and never a FAIL, even past the window) -----------------------
reset_fx; rdy $((4 * D)) | ready; soak_probes $((4 * D)) | probe; echo 503 > "$WORK/fx/bs.mode.ready"
run 2 "NOT YET" "T27 Better Stack 503 on the readiness read: a read fault is not a verdict"
echo timeout > "$WORK/fx/bs.mode.ready"
run 2 "NOT YET" "T28 Better Stack timeout on the readiness read"
rm -f "$WORK/fx/bs.mode.ready"; echo 503 > "$WORK/fx/bs.mode.probe"
run 2 "NOT YET" "T29 Better Stack 503 on the probe read"
run 2 "NOT YET" "T30 the same past the window: a read fault never FAILs" SOLEUR_FT_EARLIEST="$(iso_ago $((4 * D + 60)))"
rm -f "$WORK/fx/bs.mode.probe"; echo '<html>502</html>' | probe
run 2 "NOT YET" "T31 an unparseable probe body is a read fault, not a PASS and not a FAIL"
reset_fx; rdy $((4 * D)) | ready; echo '<html>502</html>' | probe
run 2 "NOT YET" "T32 the same past the window: a read fault still never FAILs" SOLEUR_FT_EARLIEST="$(iso_ago $((4 * D + 60)))"

# --- credentials -------------------------------------------------------------------------------------------------
reset_fx; rdy $((4 * D)) | ready; soak_probes $((4 * D)) | probe
for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  run 3 "CANNOT ESTABLISH" "T33 $v empty" "$v="
done
expect "T33 a credential fault makes no request at all" test ! -s "$WORK/calls"
out="$(env -i PATH="$BIN:/usr/bin:/bin" HOME="$WORK" FX="$WORK/fx" CALLS="$WORK/calls" SQLLOG="$WORK/sql" LEAK="$WORK/leak" BETTERSTACK_QUERY_HOST=fixture-connect.betterstackdata.com \
  BETTERSTACK_QUERY_USERNAME=fixture-user BETTERSTACK_QUERY_PASSWORD=fixture-pass bash -x "$PROBE" 2>&1)"; rc=$?
IDS+=(T34)
expect "T34 a traced run with live credentials is refused (rc 78)" test "$rc" = 78
expect "T34 the credential is not echoed by the refused trace" bash -c '! grep -q fixture-pass <<<"$1"' _ "$out"
IDS+=(T35)
out="$(env -i PATH="$BIN:/usr/bin:/bin" HOME="$WORK" FX="$WORK/fx" CALLS="$WORK/calls" SQLLOG="$WORK/sql" LEAK="$WORK/leak" bash "$PROBE" 2>&1)"; rc=$?
expect "T35 with no credential injected at all the probe says CANNOT ESTABLISH (rc 3)" test "$rc" = 3

# --- structural: the probe uses the SHARED helper, never its own copy of the query or the parse; it holds no marker access
code="$(grep -vE '^[[:space:]]*#' "$PROBE")"
IDS+=(T36 T37 T38 T39)
expect "T36 the probe loads scripts/lib/web2-luks-rows.sh and calls its fetch + judge + scan functions" \
  bash -c 'c="$1"; grep -q "source \"\$_w2l_lib\"" <<<"$c" && grep -q w2l_fetch_ready <<<"$c" && grep -q w2l_fetch_probe <<<"$c" && grep -q w2l_ready_verdict <<<"$c" && grep -q w2l_soak_scan <<<"$c"' _ "$code"
expect "T36 and carries no query or parse of its own" bash -c '! grep -qE "betterstack-query\.sh|remote\(|s3Cluster|SYSLOG_IDENTIFIER|JSONExtract" <<<"$1"' _ "$code"
expect "T37 the probe holds no Doppler credential and makes no marker access (no API host, no curl, no CLI, no token name)" \
  bash -c '! grep -qiE "doppler|curl|WORKSPACES_LUKS_CUTOVER_AT|W2L_MARKER" <<<"$1"' _ "$code"
expect "T38 the probe carries no write verb" bash -c '! grep -qE "(-X[[:space:]]*(POST|PUT|PATCH|DELETE)|secrets (set|delete))" <<<"$1"' _ "$code"
SWEEPER="$ROOT/.github/workflows/scheduled-followthrough-sweeper.yml"
expect "T39 the sweeper no longer binds the marker write token (comment-stripped)" \
  bash -c '! grep -vE "^[[:space:]]*#" "$1" | grep -q DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER' _ "$SWEEPER"
IDS+=(T40)
expect "T40 the enrollment directive in the probe header declares exactly the three Better Stack names" \
  bash -c 'grep -E "^#   <!-- soleur:followthrough .*web2-luks-live-6931\.sh" "$1" | grep -qF "secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->"' _ "$PROBE"

# --- lib: the query child gets nothing it does not need (exercised on the real helper, not through the probe) ----------
IDS+=(T41)
reset_fx; row $H "$(okmsg)" | probe
leak_out="$(env -i PATH="$BIN:/usr/bin:/bin" HOME="$WORK" FX="$WORK/fx" CALLS="$WORK/calls" SQLLOG="$WORK/sql" LEAK="$WORK/leak" \
  BETTERSTACK_QUERY_HOST=fixture-connect.betterstackdata.com BETTERSTACK_QUERY_USERNAME=fixture-user BETTERSTACK_QUERY_PASSWORD=fixture-pass \
  DOPPLER_TOKEN=decoy-d DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER=decoy-m GITHUB_TOKEN=decoy-g SOME_API_KEY=decoy-k WEBHOOK_DEPLOY_SECRET=decoy-s CF_ACCESS_CLIENT_ID=decoy-c SSH_AUTH_SOCK=decoy-a \
  bash -c 'source "$1/scripts/lib/web2-luks-rows.sh"; w2l_fetch_probe "$2" 48 5; echo "rc=$?"' _ "$ROOT" "$WORK/q.jsonl" 2>&1)"
expect "T41 w2l_query withholds every secret-shaped variable but the three Better Stack values (the stub refuses on any)" test "$leak_out" = "rc=0"

# --- the scenario set is REGISTERED: deleting one reds the suite by name ------------------------------------------
EXPECTED_IDS="T01 T02 T03 T04 T04b T04c T04d T04e T04f T04g T04h T05 T06 T07 T08 T09 T10 T11 T12 T13 T14 T15 T16 T17 T18 T19 T20 T21 T22 T23 T24 T25 T26 T27 T28 T29 T30 T31 T32 T33 T34 T35 T36 T37 T38 T39 T40 T41"
got_ids="$(printf '%s\n' "${IDS[@]}" | sort -u | tr '\n' ' ')"
want_ids="$(tr ' ' '\n' <<<"$EXPECTED_IDS" | sort -u | tr '\n' ' ')"
if [ "$got_ids" = "$want_ids" ]; then ok "the registered scenario set ran exactly (48 ids)"; else no "the scenario set drifted: ran [$got_ids] expected [$want_ids]"; fi

# --- mutation proofs: each mutant must turn at least one replayed arm RED. A mutant that lands nothing is a failure. ----
# The mutant runs from a sandbox tree (the probe finds its helper relative to its own path), so the repo is never
# written to.
MUT="$WORK/mut"
mutant() { # <label> <probe|lib> <old> <new>
  local label="$1" target="$2" old="$3" new="$4" file
  rm -rf "$MUT"; mkdir -p "$MUT/scripts/followthroughs" "$MUT/scripts/lib"
  cp "$ROOT/scripts/betterstack-query.sh" "$MUT/scripts/"
  cp "$ROOT/scripts/lib/web2-luks-rows.sh" "$ROOT/scripts/lib/betterstack-read-classify.sh" "$MUT/scripts/lib/"
  cp "$PROBE" "$MUT/scripts/followthroughs/probe.sh"
  case "$target" in probe) file="$MUT/scripts/followthroughs/probe.sh" ;; lib) file="$MUT/scripts/lib/web2-luks-rows.sh" ;; esac
  if ! python3 - "$file" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if s.count(old) != 1:
    sys.exit(1)
open(p, "w").write(s.replace(old, new))
PY
  then no "mutation $label: the edit did not land exactly once (a mutant that lands nothing proves nothing)"; return; fi
  if ! bash -n "$file" 2>/dev/null; then no "mutation $label: the mutant does not parse (a dead mutant is not a catch)"; return; fi
  run_arms_quiet "$MUT/scripts/followthroughs/probe.sh"
  if [ "$MUTANT_RED" -gt 0 ]; then ok "mutation $label → RED ($MUTANT_RED arm(s) disagree with the shipped verdict)"; else no "mutation $label stayed GREEN: no arm can see this defect"; fi
}
# the arms that guard exit 0 and the window, replayed against a mutant copy; counts the ones that now disagree
run_arms_quiet() {
  MUTANT_RED=0
  local probe_file="$1" rc out
  arm() { # <want-rc> <setup-fn> [ENV=VAL ...]
    local want="$1" setup="$2"; shift 2
    reset_fx; "$setup"
    rc=0
    out="$(env -i PATH="$BIN:/usr/bin:/bin" HOME="$WORK" FX="$WORK/fx" CALLS="$WORK/calls" SQLLOG="$WORK/sql" LEAK="$WORK/leak" \
      SENTRY_ACTIONS_RO_TOKEN=decoy-sentry GH_TOKEN=decoy-gh DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER=decoy-marker \
      BETTERSTACK_QUERY_HOST=fixture-connect.betterstackdata.com BETTERSTACK_QUERY_USERNAME=fixture-user BETTERSTACK_QUERY_PASSWORD=fixture-pass \
      SOLEUR_FT_EARLIEST="$E_OPEN" "$@" bash "$probe_file" 2>&1)" || rc=$?
    [ "$rc" = "$want" ] || MUTANT_RED=$((MUTANT_RED + 1))
    [ ! -s "$WORK/leak" ] || MUTANT_RED=$((MUTANT_RED + 1))
  }
  a_pass() { rdy $((4 * D)) | ready; soak_probes $((4 * D)) | probe; }
  a_young() { rdy $((SOAK - 60)) | ready; soak_probes $((SOAK - 60)) | probe; }
  a_two_days() { rdy $((4 * D)) | ready; { row $H "$(okmsg)"; row $((H + D)) "$(okmsg)"; } | probe; }
  a_one_bucket() { rdy $((4 * D)) | ready; { row $H "$(okmsg)"; row $((H + 1)) "$(okmsg)"; row $((2 * H)) "$(okmsg)"; } | probe; }
  a_red() { rdy $((4 * D)) | ready; { soak_probes $((4 * D)); row $((D + H)) "$(failmsg)"; } | probe; }
  a_ext4_in_window() { rdy $((4 * D)) | ready; { soak_probes $((4 * D)); row $((D + H)) "$(okmsg ext4)"; } | probe; }
  a_stale_newest() { rdy $((4 * D)) | ready; { row $((27 * H)) "$(okmsg)"; row $((27 * H + D)) "$(okmsg)"; row $((27 * H + 2 * D)) "$(okmsg)"; } | probe; }
  a_dead() { rdy $((4 * D)) | ready; }
  a_unready() { rdy $((4 * D)) "escrow=missing" | ready; soak_probes $((4 * D)) | probe; }
  a_cap() { rdy $((30 * D)) | ready; soak_probes $((30 * D)) | probe; }
  arm 0 a_pass; arm 2 a_young; arm 2 a_two_days; arm 2 a_one_bucket; arm 1 a_red; arm 1 a_ext4_in_window; arm 2 a_stale_newest
  # the NAMED reason matters here: the readiness-arm check also exits 2, so the exit code alone cannot tell the two checks apart
  [[ "$out" == *"not a fresh LUKS-backed OK row"* ]] || MUTANT_RED=$((MUTANT_RED + 1))
  arm 2 a_dead; arm 1 a_dead SOLEUR_FT_EARLIEST="$(iso_ago $((4 * D + 60)))"; arm 2 a_dead SOLEUR_FT_EARLIEST="$(iso_ago $((4 * D - 60)))"
  arm 1 a_unready SOLEUR_FT_EARLIEST="$(iso_ago $((4 * D + 60)))"
  # the SQL the probe sent: window, limit, 504 h cap and the emitting unit
  arm 0 a_pass
  grep -q "^probe:.*INTERVAL 98 HOUR.*LIMIT 2000" "$WORK/sql" || MUTANT_RED=$((MUTANT_RED + 1))
  grep -qF "JSONExtractString(raw,'_SYSTEMD_UNIT') = 'luks-monitor.service'" "$WORK/sql" || MUTANT_RED=$((MUTANT_RED + 1))
  arm 0 a_cap
  grep -q "^probe:.*INTERVAL 504 HOUR" "$WORK/sql" || MUTANT_RED=$((MUTANT_RED + 1))
  # the arm that replaced it: noop is neither formatted nor opened, and the REASON must be named
  a_noop() { rdy $((4 * D)) "luks_arm=noop" | ready; soak_probes $((4 * D)) | probe; }
  arm 2 a_noop
  [[ "$out" == *"luks_arm=noop"* ]] || MUTANT_RED=$((MUTANT_RED + 1))
}
# control: the UNMUTATED probe agrees with every arm (otherwise "RED" below would just mean the arms are wrong)
run_arms_quiet "$PROBE"
IDS=()
if [ "$MUTANT_RED" -eq 0 ]; then ok "mutation control: the shipped probe satisfies every replayed arm"; else no "mutation control: the shipped probe disagrees with $MUTANT_RED replayed arm(s)"; fi
mutant "soak shortened to 0 days (a young soak passes)" probe 'SOAK_DAYS=3' 'SOAK_DAYS=0'
mutant "the red-row check is skipped" probe 'if (( reds > 0 )); then' 'if false; then'
mutant "the distinct-days check is skipped" probe 'if (( green_days < SOAK_DAYS )); then' 'if false; then'
mutant "the newest-probe verdict is ignored" probe 'if [[ "$verdict" != GREEN* ]]; then' 'if false; then'
mutant "the readiness-age check is skipped" probe 'if (( ready_age < SOAK_S )); then' 'if false; then'
mutant "the readiness verdict is ignored" probe 'if [[ "$rverdict" != GREEN* ]]; then' 'if false; then'
mutant "the 504 h cap is removed" probe '(( hours > 504 )) && hours=504' ':'
mutant "the probe lookback shrinks to one hour" probe 'hours=$(( ready_age / 3600 + 2 ))' 'hours=1'
mutant "the probe row limit shrinks to one" probe 'w2l_fetch_probe "$tmp/probe.jsonl" "$hours" 2000' 'w2l_fetch_probe "$tmp/probe.jsonl" "$hours" 1'
mutant "the readiness luks_arm check is skipped (noop would pass)" probe 'if ! rarm="$(w2l_ready_arm "$tmp/ready.jsonl")"; then' 'if false; then'
mutant "the shared helper accepts noop as an arm" lib '[[ "$arm" == formatted || "$arm" == opened ]]' '[[ "$arm" == formatted || "$arm" == opened || "$arm" == noop ]]'
mutant "the soak window is zero (no row counts)" probe 'w2l_soak_scan "$tmp/probe.jsonl" "$ready_age"' 'w2l_soak_scan "$tmp/probe.jsonl" 0'
mutant "the closed-window FAIL is removed (a dead probe stays NOT YET forever)" probe 'if [[ "$earliest_epoch" =~ ^[0-9]+$ ]] && (( now_epoch >= earliest_epoch + (SOAK_DAYS + 1) * 86400 )); then' 'if false; then'
mutant "the window closes a day late" probe 'earliest_epoch + (SOAK_DAYS + 1) * 86400' 'earliest_epoch + (SOAK_DAYS + 2) * 86400'
mutant "the window closes a day early" probe 'earliest_epoch + (SOAK_DAYS + 1) * 86400' 'earliest_epoch + SOAK_DAYS * 86400'
mutant "rows in one bucket count once each (distinct days become distinct rows)" lib '((($win - .age) / 86400) | floor)' '.age'
mutant "an OK line that is not LUKS is not counted as red" lib 'select(row_green | not)' 'select(.kind != "ok")'
mutant "the query child keeps its secrets" lib 'env ${unset_args[@]+"${unset_args[@]}"} timeout' 'env timeout'
mutant "the probe SQL drops the emitting-unit predicate" lib "  AND JSONExtractString(raw,'_SYSTEMD_UNIT') = '\${W2L_PROBE_UNIT}'
" ''
# a HARMLESS variant must stay GREEN (a harness that reds on everything proves nothing)
rm -rf "$MUT"; mkdir -p "$MUT/scripts/followthroughs" "$MUT/scripts/lib"
cp "$ROOT/scripts/betterstack-query.sh" "$MUT/scripts/"; cp "$ROOT/scripts/lib/web2-luks-rows.sh" "$ROOT/scripts/lib/betterstack-read-classify.sh" "$MUT/scripts/lib/"
sed 's/^SOAK_DAYS=3$/SOAK_DAYS=3 # harmless/' "$PROBE" > "$MUT/scripts/followthroughs/probe.sh"
run_arms_quiet "$MUT/scripts/followthroughs/probe.sh"
if [ "$MUTANT_RED" -eq 0 ]; then ok "mutation harmless variant (a trailing comment) stays GREEN"; else no "mutation harmless variant went RED ($MUTANT_RED): the replay is not discriminating"; fi

echo
echo "web2-luks-live-6931.test.sh: $pass passed, $fail failed"
# Non-degeneracy floor: EXACT (the green count of this suite; deleting an arm or a mutation row must red it).
FLOOR=86
[ "$((pass + fail))" -ge "$FLOOR" ] || { echo "FAIL: only $((pass + fail)) assertions ran (<$FLOOR) — the harness did not execute fully" >&2; exit 1; }
[ "$fail" -eq 0 ]
