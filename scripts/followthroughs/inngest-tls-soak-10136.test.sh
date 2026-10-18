#!/usr/bin/env bash
# inngest-tls-soak-10136.test.sh -- exit-code harness for inngest-tls-soak-10136.sh (#10136, Guard 2 of the
# Inngest link TLS plan). Drives the probe through a fake `gh` (the trusted-verdict lib's two reads) and a
# fake `betterstack-query.sh`, with a pinned clock, and pins:
#   0 PASS   1 FAIL   2 NOT YET (empty or failed query, window not over, no anchor)   3 CANNOT ESTABLISH
#   78 xtrace refusal.
#
# GUARD 2 MUTATION MATRIX, one fixture each (M1..M7), plus the two harness rows (H1, H2):
#   M1 legacy counter increases mid-window after the baseline row              -> FAIL
#   M2 all-zero series with a 3-hour gap                                       -> FAIL
#   M3 a second boot_id partway (reboot)                                       -> FAIL, names the clock restart
#   M4 zero rows / a transport error                                           -> exit 2, never PASS
#   M5 flat NON-zero legacy counter after the baseline + rising tls_8443       -> PASS (delta, not absolute)
#   M6 legacy flat AND tls_8443 flat (zero traffic proves nothing)             -> FAIL
#   M7 legacy counter DEcreases without a boot_id change                       -> FAIL (reset anomaly)
#   H1 the fixture builder can produce a gap (and a degenerate all-same-timestamp series is not a PASS)
#   H2 must-PASS non-canonical input: 5 min +/- 20 s jitter, exactly 48 h, legacy counter 0
# Then script-mutation rows: each predicate line is deleted from a COPY of the probe and the fixture that
# targets it must flip to PASS, which proves the fixture reaches that line (a fixture that passes under the
# deleted check was never testing it).
#
# FIXTURES ARE DOUBLE-ENCODED: betterstack-query.sh emits JSONEachRow whose `raw` column is a JSON-ENCODED
# STRING holding a JSON document, so the rows below are built with `raw` genuinely tostring-ed. A fixture that
# put `raw` above the decode would pass here and read zero rows in production (#7674).
# Values are synthesized (cq-test-fixtures-synthesized-only): hashes are runs of one hex digit, boot ids are
# made up, logins are `owner-op`/`none-op`; nothing real is written, and nothing is written outside a mktemp dir.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/followthroughs/inngest-tls-soak-10136.sh"
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 2; }
TMP="$(mktemp -d "$TMPDIR/tls-soak.XXXXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

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
assert_fixture_dir "$TMP"

[[ -f "$PROBE" ]] || { echo "FATAL: probe not found at $PROBE" >&2; exit 1; }

passes=0; fails=0; asserted=0
pass() { passes=$((passes + 1)); asserted=$((asserted + 1)); printf '  PASS: %s\n' "$1"; }
fail() { fails=$((fails + 1)); asserted=$((asserted + 1)); printf '  FAIL: %s\n' "$1" >&2; }

# instrument self-test: both helpers must move their own counter (rolled back afterwards)
_p0=$passes; _f0=$fails
pass "self-test" >/dev/null; fail "self-test" >/dev/null 2>&1
if [ "$passes" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ]; then
  echo "[FATAL] instrument self-test: pass()/fail() did not each record" >&2; exit 1
fi
passes=0; fails=0; asserted=0

T_ISO="2026-11-05T10:00:00Z"
T_EPOCH="$(date -u -d "$T_ISO" +%s)"
END_EPOCH=$((T_EPOCH + 172800))
BASE_EPOCH=$((T_EPOCH + 90))                                   # the baseline row: the first row after T
BASE_ISO="$(date -u -d "@$BASE_EPOCH" +%Y-%m-%dT%H:%M:%SZ)"
NOW_OK=$((END_EPOCH + 3600))                                   # one hour after the window closed

# --- fake gh: the trusted-verdict lib's two reads, argv-strict, every refusal LOGGED -------------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'FAKE'
#!/usr/bin/env bash
# a refused argv is logged before exit 64: the lib sends stderr to /dev/null and maps any failure to rc 2, so
# without the log a refused argv would surface as CANNOT ESTABLISH and an rc-3 row would pass for the wrong reason
refuse() { printf 'REFUSED %s\n' "$*" >> "$FX/refused.log"; exit 64; }
if [ "$1" = "issue" ]; then   # issue view <N> --repo <r> --json comments --jq <expr>
  [ "$2" = "view" ] && [ "$4" = "--repo" ] && [ "$6" = "--json" ] && [ "$7" = "comments" ] && [ "$8" = "--jq" ] || refuse "$@"
  printf 'issue view %s\n' "$3" >> "$FX/requests.log"
  [ -f "$FX/fail-comments" ] && { echo "gh: HTTP 403 Resource not accessible" >&2; exit 1; }
  f="$FX/comments-$3.json"; [ -f "$f" ] || exit 1
  jq -r "$9" "$f"
  exit 0
fi
[ "$1" = "api" ] || refuse "$@"
ep="$2"; jqx=""
[ "$3" = "--jq" ] && jqx="$4"
printf '%s\n' "$ep" >> "$FX/requests.log"
case "$ep" in
  repos/*/collaborators/*/permission)
    [ -n "$jqx" ] || refuse "$ep (no --jq)"
    l="${ep#*collaborators/}"; l="${l%%/*}"
    p="$(awk -F'\t' -v l="$l" '$1 == l { print $2; exit }' "$FX/perms.tsv")"
    case "$p" in
      "")  refuse "$ep (login not in perms.tsv)" ;;
      404) echo 'gh: Not Found (HTTP 404)' >&2; exit 1 ;;
      403) echo 'gh: Resource not accessible by integration (HTTP 403)' >&2; exit 1 ;;
      *)   printf '{"permission":"%s"}\n' "$p" | jq -r "$jqx"; exit 0 ;;
    esac ;;
  *) refuse "$ep" ;;
esac
FAKE
chmod +x "$TMP/bin/gh"

# --- fake betterstack-query.sh: ASSERTS ITS ARGV (a stub that answers anything cannot notice the probe
# querying the wrong thing) and records it ------------------------------------------------------------------
cat > "$TMP/bin/bq" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FX/bq-argv.log"
[[ "${STUB_RC:-0}" == "0" ]] || { echo "stub: transport failure" >&2; exit "${STUB_RC}"; }
argv=" $* "
[[ "$argv" == *" --since 2026-11-05T10:00:00Z "* ]] || { echo "stub: --since is not the anchor T (argv: $*)" >&2; exit 64; }
[[ "$argv" == *" --until "* ]] || { echo "stub: --until missing (argv: $*)" >&2; exit 64; }
[[ "$argv" == *" --grep stage=tls-health "* ]] || { echo "stub: --grep stage=tls-health missing (argv: $*)" >&2; exit 64; }
[[ "$argv" != *" --no-archive "* ]] || { echo "stub: --no-archive would answer 48 h with 40 minutes (argv: $*)" >&2; exit 64; }
lim="$(sed -n 's/.* --limit \([0-9][0-9]*\).*/\1/p' <<<"$argv")"
[[ -n "$lim" && "$lim" -ge 1000 ]] || { echo "stub: --limit < 1000 truncates 48 h at 5 min (argv: $*)" >&2; exit 64; }
cat "${STUB_ROWS:-/dev/null}"
STUB
chmod +x "$TMP/bin/bq"

# --- the series builder: ONE jq run per series ---------------------------------------------------------------
# build_series <out> [key=value ...]
#   leg=N        baseline legacy_8288 packets (default 0)        tls=N  baseline tls_8443 packets (default 1000)
#   tlsstep=N    tls_8443 packets added per row (default 30; 0 = flat)
#   jit=S        jitter amplitude in seconds (default 20; the emitter's stated jitter)
#   n=N          rows after the baseline (default: as many as fit before T+48h)
#   gapat=H gaplen=H  drop every row between H and H+gaplen hours after T        legbump=I  from row I on, legacy += 5
#   legdec=I     from row I on, legacy -= 1 (same boot)        reboot=I  from row I on, a new boot_id and reset counters
#   samets=1     degenerate builder: every row carries ONE timestamp (H1)       badrow=I  row I carries no counters
#   badboot=1    every row's boot_id is dashes only            pre=1  five pre-T rows with a HUGE legacy counter
#   decoy=1      two rows that QUOTE the series (another emitter / a refusal marker) with hostile counters
#   lateleg=I    legacy bump only on row I (a single late plaintext call)   post=1  five rows AFTER T+48h with a legacy bump
#   bootonly=I   from row I on only the boot_id label changes (counters continue)   tlsdec=I  from row I on, tls_8443 -= 100
#   onesided=1   timer-slack jitter: every other row is LATE by `jit` seconds, none early (systemd AccuracySec shape; with jit=60 the widest gap is 360 s)
build_series() {
  local out="$1"; shift
  local leg=0 tls=1000 tlsstep=30 jit=20 n=-1 gapat=-1 gaplen=0 legbump=-1 legdec=-1 reboot=-1 samets=0 badrow=-1 badboot=0 pre=0 decoy=0 lateleg=-1 post=0 bootonly=-1 tlsdec=-1 onesided=0 kv
  for kv in "$@"; do
    case "$kv" in
      leg=*) leg="${kv#*=}" ;; tls=*) tls="${kv#*=}" ;; tlsstep=*) tlsstep="${kv#*=}" ;; jit=*) jit="${kv#*=}" ;; n=*) n="${kv#*=}" ;;
      gapat=*) gapat="${kv#*=}" ;; gaplen=*) gaplen="${kv#*=}" ;; legbump=*) legbump="${kv#*=}" ;; legdec=*) legdec="${kv#*=}" ;;
      reboot=*) reboot="${kv#*=}" ;; samets=*) samets="${kv#*=}" ;; badrow=*) badrow="${kv#*=}" ;; badboot=*) badboot="${kv#*=}" ;;
      pre=*) pre="${kv#*=}" ;; decoy=*) decoy="${kv#*=}" ;; lateleg=*) lateleg="${kv#*=}" ;; post=*) post="${kv#*=}" ;; bootonly=*) bootonly="${kv#*=}" ;; tlsdec=*) tlsdec="${kv#*=}" ;; onesided=*) onesided="${kv#*=}" ;;
    esac
  done
  assert_fixture_dir "$out"
  jq -nc --argjson t0 "$T_EPOCH" --argjson base "$BASE_EPOCH" --argjson end "$END_EPOCH" \
    --argjson leg "$leg" --argjson tls "$tls" --argjson tlsstep "$tlsstep" --argjson jit "$jit" --argjson n "$n" \
    --argjson gapat "$gapat" --argjson gaplen "$gaplen" --argjson legbump "$legbump" --argjson legdec "$legdec" \
    --argjson reboot "$reboot" --argjson samets "$samets" --argjson badrow "$badrow" --argjson badboot "$badboot" \
    --argjson pre "$pre" --argjson decoy "$decoy" --argjson lateleg "$lateleg" --argjson post "$post" \
    --argjson bootonly "$bootonly" --argjson tlsdec "$tlsdec" --argjson onesided "$onesided" '
    def h: "a" * 64;
    def ts($e): ($e | strftime("%Y-%m-%d %H:%M:%S"));
    def detail($l; $t; $boot): "unit=active nrestarts=0 fetch_rc=0 bind=10.0.1.40:8443 listener=1 served_sha256=\(h) cert_sha256=\(h) notafter_days=3649 hs_fail_15m=0 legacy_8288_packets=\($l) tls_8443_packets=\($t) nft8443_sha256=\(h) nft_rules=9 boot_id=\($boot)";
    def row($e; $d): {dt: ts($e), raw: ({message: ("SOLEUR_INNGEST_BOOT_STAGE stage=tls-health " + $d), marker: "SOLEUR_INNGEST_BOOT_STAGE", stage: "tls-health", detail: $d, host: "soleur-inngest", dt: ($e | todate), shipper: "cloud-init-phone-home"} | tostring)};
    # deterministic jitter that visits both extremes: -j, +j, 0, +j, -j ... so consecutive gaps reach 300+2j
    def jitter($i): (if $onesided == 1 then ([0, 1] | .[$i % 2]) else ([-1, 1, 0, 1, -1, 0] | .[$i % 6]) end) * $jit;
    def epoch($i): (if $samets == 1 then ($base + 3600) else ($base + 300 * $i + (if $i == 0 then 0 else jitter($i) end)) end);
    ( [range(0; 1000)] | map(select(epoch(.) <= $end)) | length ) as $fit
    | (if $n >= 0 then $n else $fit end) as $cnt
    | ( if $pre > 0 then (range(0; 5) | row($t0 - 600 + (. * 100); detail(999999; 1; "00000000"))) else empty end ),
      ( range(0; $cnt) as $i
        | epoch($i) as $e
        | select(($gapat < 0) or ($e < $t0 + $gapat * 3600) or ($e >= $t0 + ($gapat + $gaplen) * 3600))
        | (if ($reboot >= 0 and $i >= $reboot) or ($bootonly >= 0 and $i >= $bootonly) then "cd56ef78" else (if $badboot == 1 then "--------" else "ab12cd34" end) end) as $boot
        | (if $reboot >= 0 and $i >= $reboot then ($i - $reboot) else $i end) as $k
        | (if $reboot >= 0 and $i >= $reboot then 0 else $leg end) as $lbase
        | ($lbase + (if $legbump >= 0 and $i >= $legbump then 5 else 0 end) + (if $lateleg >= 0 and $i == $lateleg then 5 else 0 end) - (if $legdec >= 0 and $i >= $legdec then 1 else 0 end)) as $l
        | (if $reboot >= 0 and $i >= $reboot then (10 + $k * $tlsstep) else ($tls + $i * $tlsstep - (if $tlsdec >= 0 and $i >= $tlsdec then 100 else 0 end)) end) as $t
        | if $i == $badrow then row($e; "unit=active listener=1 boot_id=ab12cd34") else row($e; detail($l; $t; $boot)) end ),
      ( if $decoy == 1 then
          ({dt: ts($base + 7200), raw: ({message: ("Measured on the host: SOLEUR_INNGEST_BOOT_STAGE stage=tls-health " + detail(777777; 1; "ab12cd34")), SYSLOG_IDENTIFIER: "doppler", host: "soleur-inngest"} | tostring)}),
          ({dt: ts($base + 7300), raw: ({message: "SOLEUR_INNGEST_TLS_REFUSED reason=listener-down legacy_8288_packets=888888 stage=tls-health", SYSLOG_IDENTIFIER: "inngest-tls-health", host: "soleur-inngest"} | tostring)})
        else empty end ),
      ( if $post > 0 then (range(0; 5) | row($end + 100 + (. * 100); detail(555555; 9; "ab12cd34"))) else empty end )
  ' > "$out"
}

# --- fixture dir for ONE case ------------------------------------------------------------------------------------
# build_fx <dir> [key=value ...]   (the comment thread of the anchor issue and the permission table)
#   noanchor: no anchor markers at all           untrusted: the anchor comment is by a login with NO repository permission
#   Tmark=<ISO>   override the T marker            base=<line>   override the BASELINE marker line
#   twoanchors: an older anchor (T 2026-10-01) followed by the real one     failcomments: the comment read fails (403)
#   permfail: the author's permission read is a 403    fenced: the markers sit inside a fenced block
build_fx() {
  local fx="$1"; shift
  assert_fixture_dir "$fx"; rm -rf "$fx"; mkdir -p "$fx"
  local noanchor=0 untrusted=0 tmark="$T_ISO" base="" twoanchors=0 fenced=0 kv author="owner-op" leg=0 tls=1000
  base="S1-SOAK-BASELINE: dt=$BASE_ISO boot_id=ab12cd34 legacy_8288_packets=$leg tls_8443_packets=$tls"
  for kv in "$@"; do
    case "$kv" in
      noanchor) noanchor=1 ;; untrusted) untrusted=1 ;; Tmark=*) tmark="${kv#*=}" ;; base=*) base="${kv#*=}" ;;
      twoanchors) twoanchors=1 ;; fenced) fenced=1 ;;
      failcomments) : > "$fx/fail-comments" ;; permfail) author="flaky-op" ;;
    esac
  done
  (( untrusted )) && author="none-op"
  printf 'owner-op\tadmin\nnone-op\t404\nflaky-op\t403\ngithub-actions\t404\n' > "$fx/perms.tsv"
  local body="Flip complete. T is the last prod swap plus drain.
S1-SOAK-T: $tmark
$base
done"
  (( fenced )) && body=$'```\n'"$body"$'\n```'
  if (( noanchor )); then body="nothing recorded yet"; fi
  local c='[]'
  c="$(jq -nc --arg a "$author" --arg b "$body" '[{author:{login:$a}, body:$b, createdAt:"2026-11-05T10:05:00Z"}]')"
  if (( twoanchors )); then
    c="$(jq -nc --arg a "$author" --arg b "$body" --arg o "S1-SOAK-T: 2026-10-01T00:00:00Z
S1-SOAK-BASELINE: dt=2026-10-01T00:01:00Z boot_id=00000000 legacy_8288_packets=1 tls_8443_packets=1" \
      '[{author:{login:$a}, body:$o, createdAt:"2026-10-01T00:05:00Z"}, {author:{login:$a}, body:$b, createdAt:"2026-11-05T10:05:00Z"}]')"
  fi
  # the unfiltered shape the lib reads: .comments[] -> [login, body, createdAt] as base64 -- the fake applies the lib's own --jq
  jq -nc --argjson c "$c" '{comments: $c}' > "$fx/comments-10136.json"
}

# run_probe <fx> <rows> [now-epoch]  -> OUT, RC
run_probe() {
  local fx="$1" rows="$2" now="${3:-$NOW_OK}"
  OUT="$(env -i PATH="$TMP/bin:/usr/local/bin:/usr/bin:/bin" HOME="$TMP" FX="$fx" STUB_ROWS="$rows" STUB_RC="${STUB_RC:-0}" \
          GH_TOKEN=fake-token BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
          SOAK_BQ_BIN="$TMP/bin/bq" SOAK_NOW_EPOCH="$now" bash "${PROBE_UNDER_TEST:-$PROBE}" 2>&1)"
  RC=$?
}

expect() { # expect <case> <want-rc> <want-substring>
  local name="$1" want_rc="$2" want_sub="$3"
  if [[ -n "${TLS_SOAK_TEST_VERBOSE:-}" ]]; then printf '%s\n' "$OUT" | sed 's/^/      | /'; fi
  if [[ "$RC" -ne "$want_rc" ]]; then
    fail "$name -- rc=$RC want=$want_rc :: $(printf '%s' "$OUT" | head -3 | tr '\n' '|')"
  elif [[ -n "$want_sub" ]] && ! grep -qF -- "$want_sub" <<<"$OUT"; then
    fail "$name -- rc ok but output lacks '$want_sub' :: $(printf '%s' "$OUT" | head -3 | tr '\n' '|')"
  else
    pass "$name"
  fi
}

echo "== inngest-tls-soak-10136.sh exit-code harness =="

# --- H0 the harness itself can FAIL ------------------------------------------------------------------------------
# A suite whose wrapper cannot go red certifies nothing. Drive a case that MUST fail, confirm the counter moved,
# roll it back. SELFTEST is reported with printf + exit directly: routing it through fail() would make the
# self-test that certifies the helpers depend on the helpers.
_h_f0=$fails; _h_p0=$passes; _h_a0=$asserted
RC=99; OUT="nothing like the expected text"
expect "SELFTEST (must fail)" 0 "this substring cannot appear" 2>/dev/null
if [[ "$fails" -eq $((_h_f0 + 1)) ]]; then
  fails=$_h_f0; passes=$_h_p0; asserted=$_h_a0; pass "INSTRUMENT: expect() reports a genuine mismatch as a failure"
else
  printf '  FAIL INSTRUMENT: expect() did NOT fail on a guaranteed mismatch -- every case below is decorative.\n' >&2
  exit 1
fi

# --- the canonical must-PASS fixture, built once ----------------------------------------------------------------
FXG="$TMP/fx-good"; build_fx "$FXG"
build_series "$TMP/good.jsonl"

# --- H2 must-PASS non-canonical input ---------------------------------------------------------------------------
# 5 min +/- 20 s jitter, a series that runs the FULL 48 h to the second, legacy counter 0: a suite that only accepts
# a perfectly regular cadence is vacuous in the other direction.
rows_n="$(wc -l < "$TMP/good.jsonl")"
if [[ "$rows_n" -ge 570 && "$rows_n" -le 580 ]]; then
  pass "H2 builder: the canonical series is $rows_n rows (5 min cadence over 48 h)"
else
  fail "H2 builder: the canonical series has $rows_n rows, expected about 576"
fi
run_probe "$FXG" "$TMP/good.jsonl"
expect "H2 5 min +/- 20 s jitter, exactly 48 h, legacy counter 0, tls_8443 rising => PASS" 0 "PASS:"

build_series "$TMP/onesided.jsonl" onesided=1 jit=60
run_probe "$FXG" "$TMP/onesided.jsonl"
expect "H2b timer-slack shape (every other emit up to 60 s late, widest gap 360 s) => PASS" 0 "PASS:"
run_probe "$FXG" "$TMP/good.jsonl"

# --- H1 the builder can produce a gap, and a degenerate series is not a PASS -----------------------------------------
build_series "$TMP/gap3h.jsonl" gapat=20 gaplen=3
max_gap="$(jq -r '.dt' "$TMP/gap3h.jsonl" | while IFS= read -r d; do date -u -d "$d UTC" +%s; done | sort -n | awk 'NR > 1 { g = $1 - p; if (g > m) m = g } { p = $1 } END { print m + 0 }')"
if [[ "$max_gap" -ge 10000 ]]; then
  pass "H1 builder: gapat/gaplen produces a $max_gap s hole (the builder can emit the gap M2 needs)"
else
  fail "H1 builder: a 3 h gap request produced a max spacing of only $max_gap s -- M2 would test nothing"
fi
build_series "$TMP/samets.jsonl" samets=1
distinct_ts="$(jq -r '.dt' "$TMP/samets.jsonl" | sort -u | wc -l)"
if [[ "$distinct_ts" -eq 1 ]]; then
  run_probe "$FXG" "$TMP/samets.jsonl"
  expect "H1 every row carries ONE timestamp (a builder that lost its time axis) => FAIL, the gap check still sees it" 1 "gap"
else
  fail "H1 builder: samets=1 produced $distinct_ts distinct timestamps"
fi

# --- M1..M7 -------------------------------------------------------------------------------------------------------------
build_series "$TMP/m1.jsonl" legbump=300
run_probe "$FXG" "$TMP/m1.jsonl"
expect "M1 legacy counter increases mid-window after the baseline => FAIL naming the legacy delta" 1 "legacy_8288"

run_probe "$FXG" "$TMP/gap3h.jsonl"
expect "M2 all-zero series with a 3-hour gap => FAIL naming the gap" 1 "gap"

build_series "$TMP/m3.jsonl" reboot=250
run_probe "$FXG" "$TMP/m3.jsonl"
expect "M3 a second boot_id partway (reboot) => FAIL naming the clock restart" 1 "boot_id"
if grep -qF 're-anchor' <<<"$OUT"; then pass "M3 the output says how to restart the clock (re-anchor with a new S1-SOAK-T)"; else fail "M3 the output does not say to re-anchor: $(printf '%s' "$OUT" | head -3 | tr '\n' '|')"; fi

: > "$TMP/empty.jsonl"
run_probe "$FXG" "$TMP/empty.jsonl"
expect "M4a zero rows => exit 2 (transient), never a PASS" 2 "no tls-health rows"
STUB_RC=7 run_probe "$FXG" "$TMP/good.jsonl"
expect "M4b a transport error from the query => exit 2 (transient), never a PASS" 2 "query failed"

build_series "$TMP/m5.jsonl" leg=4242
FX5="$TMP/fx-m5"; build_fx "$FX5" "base=S1-SOAK-BASELINE: dt=$BASE_ISO boot_id=ab12cd34 legacy_8288_packets=4242 tls_8443_packets=1000"
run_probe "$FX5" "$TMP/m5.jsonl"
expect "M5 flat NON-zero legacy counter after the baseline + rising tls_8443 => PASS (delta, not absolute)" 0 "PASS:"

build_series "$TMP/m6.jsonl" tlsstep=0
run_probe "$FXG" "$TMP/m6.jsonl"
expect "M6 legacy flat and tls_8443 flat (zero traffic) => FAIL naming the positive control" 1 "tls_8443"

build_series "$TMP/m7.jsonl" leg=50 legdec=200
FX7="$TMP/fx-m7"; build_fx "$FX7" "base=S1-SOAK-BASELINE: dt=$BASE_ISO boot_id=ab12cd34 legacy_8288_packets=50 tls_8443_packets=1000"
run_probe "$FX7" "$TMP/m7.jsonl"
expect "M7 legacy counter DEcreases without a boot_id change => FAIL as a reset anomaly" 1 "decreas"

# --- further rows on the predicate ----------------------------------------------------------------------------------
build_series "$TMP/late.jsonl" lateleg=400
run_probe "$FXG" "$TMP/late.jsonl"
expect "R1 a SINGLE late plaintext call (one row, then flat again) is a non-zero delta => FAIL" 1 "legacy_8288"

build_series "$TMP/pre.jsonl" pre=1
run_probe "$FXG" "$TMP/pre.jsonl"
expect "R2 pre-T rows with a huge legacy counter are outside the window => ignored, PASS" 0 "PASS:"

build_series "$TMP/post.jsonl" post=1
run_probe "$FXG" "$TMP/post.jsonl"
expect "R3 rows AFTER T+48h (a later reboot or legacy call) do not touch a closed window => PASS" 0 "PASS:"

build_series "$TMP/decoy.jsonl" decoy=1
run_probe "$FXG" "$TMP/decoy.jsonl"
expect "R4 another emitter / the refusal marker QUOTING the series is field-isolated out => PASS" 0 "PASS:"

build_series "$TMP/bad.jsonl" badrow=100
run_probe "$FXG" "$TMP/bad.jsonl"
expect "R5 a row with no counters is a hole in the series, not a skipped row => FAIL" 1 "unparseable"

build_series "$TMP/badboot.jsonl" badboot=1
run_probe "$FXG" "$TMP/badboot.jsonl"
expect "R6 a dashes-only boot_id cannot prove a single boot => FAIL" 1 "unparseable"

build_series "$TMP/tlsdec.jsonl" tlsdec=200
run_probe "$FXG" "$TMP/tlsdec.jsonl"
expect "R12 tls_8443 DEcreases without a boot_id change => FAIL as a reset anomaly" 1 "tls_8443 decreased"

build_series "$TMP/short.jsonl" n=300
run_probe "$FXG" "$TMP/short.jsonl"
expect "R7 a series that stops at hour 25 (emitter dead) => FAIL naming the gap" 1 "gap"

build_series "$TMP/tlslow.jsonl" tlsstep=5
run_probe "$FXG" "$TMP/tlslow.jsonl"
expect "R8 tls_8443 rising but under 90% of the expected probe cadence => FAIL" 1 "tls_8443"

run_probe "$FXG" "$TMP/good.jsonl" $((END_EPOCH - 600))
expect "R9 the clock is still inside the 48 h window => exit 2 NOT YET, no verdict" 2 "NOT YET"

# argv assertions: the stub rejects a probe that drops --until, --grep, shrinks --limit or opts out of the archive
run_probe "$FXG" "$TMP/good.jsonl"
if [[ -s "$FXG/bq-argv.log" ]] && ! grep -qF -- '--no-archive' "$FXG/bq-argv.log"; then
  pass "R10 the query asked for the archive arm (no --no-archive) and the stub accepted its argv"
else
  fail "R10 the query argv was rejected or opted out of the archive: $(cat "$FXG/bq-argv.log" 2>/dev/null | head -2)"
fi
# the truncation guard: a result that fills the limit cannot be proven complete
yes '{"dt":"2026-11-05 10:01:30","raw":"{}"}' 2>/dev/null | head -n 2000 > "$TMP/full.jsonl"
run_probe "$FXG" "$TMP/full.jsonl"
expect "R11 a result as long as --limit may have lost its oldest rows => exit 3, never a gap verdict" 3 "truncat"

# --- the anchor: read through the trusted-verdict lib --------------------------------------------------------------
FXN="$TMP/fx-noanchor"; build_fx "$FXN" noanchor
run_probe "$FXN" "$TMP/good.jsonl"
expect "A1 no anchor markers on the issue => exit 2 NOT YET (nothing to measure against)" 2 "NOT YET"

FXU="$TMP/fx-untrusted"; build_fx "$FXU" untrusted
run_probe "$FXU" "$TMP/good.jsonl"
expect "A2 anchor posted by a login with no repository permission (forged, public repo) => ignored, exit 2" 2 "NOT YET"

FXF="$TMP/fx-fenced"; build_fx "$FXF" fenced
run_probe "$FXF" "$TMP/good.jsonl"
expect "A3 anchor markers inside a fenced block (a quoted template) never count => exit 2" 2 "NOT YET"

FXC="$TMP/fx-failcomments"; build_fx "$FXC" failcomments
run_probe "$FXC" "$TMP/good.jsonl"
expect "A4 the comment read fails => exit 3 CANNOT ESTABLISH (a failed trust read is not 'no anchor')" 3 "CANNOT ESTABLISH"

FXP="$TMP/fx-permfail"; build_fx "$FXP" permfail
run_probe "$FXP" "$TMP/good.jsonl"
expect "A5 the author's permission read fails => exit 3 CANNOT ESTABLISH" 3 "CANNOT ESTABLISH"

FX2="$TMP/fx-two"; build_fx "$FX2" twoanchors
run_probe "$FX2" "$TMP/good.jsonl"
expect "A6 two anchors: the LATEST one (the re-anchor after a reboot) wins => PASS on the new window" 0 "PASS:"

FXB="$TMP/fx-badbase"; build_fx "$FXB" "base=S1-SOAK-BASELINE: dt=$BASE_ISO boot_id=ab12cd34 legacy_8288_packets=lots tls_8443_packets=1000"
run_probe "$FXB" "$TMP/good.jsonl"
expect "A7 a malformed baseline line => exit 3 (an unreadable anchor is not a verdict)" 3 "CANNOT ESTABLISH"

FXE="$TMP/fx-early"; build_fx "$FXE" "base=S1-SOAK-BASELINE: dt=2026-11-05T09:00:00Z boot_id=ab12cd34 legacy_8288_packets=0 tls_8443_packets=1000"
run_probe "$FXE" "$TMP/good.jsonl"
expect "A8 a baseline row dated BEFORE T is not a post-drain sample => exit 3" 3 "CANNOT ESTABLISH"

FXL="$TMP/fx-late"; build_fx "$FXL" "base=S1-SOAK-BASELINE: dt=2026-11-05T12:00:00Z boot_id=ab12cd34 legacy_8288_packets=0 tls_8443_packets=1000"
run_probe "$FXL" "$TMP/good.jsonl"
expect "A9 a baseline row more than one cadence AFTER T leaves an unmeasured hole => exit 3" 3 "CANNOT ESTABLISH"

FXD="$TMP/fx-baseboot"; build_fx "$FXD" "base=S1-SOAK-BASELINE: dt=$BASE_ISO boot_id=ee00ee00 legacy_8288_packets=0 tls_8443_packets=1000"
run_probe "$FXD" "$TMP/good.jsonl"
expect "A10 the baseline's boot_id differs from the series' => FAIL (the anchor is not this boot)" 1 "boot_id"

# --- xtrace refusal (#7797) ----------------------------------------------------------------------------------------------
OUT="$(env -i PATH="$TMP/bin:/usr/bin:/bin" HOME="$TMP" GH_TOKEN=fake-token bash -x "$PROBE" 2>&1)"; RC=$?
expect "X1 refuses to run under xtrace while a credential is set => exit 78" 78 "refusing to trace"

# --- script-mutation rows -------------------------------------------------------------------------------------------------
# Delete ONE predicate line (each ends in `# CHECK-<NAME>`) from a COPY of the probe, then the fixture that targets
# that line must flip to PASS. A fixture that stays red under the deletion was failing for another reason.
mutant() { # mutant <CHECK-NAME> -> path of the mutated copy (the probe's dir is mirrored so the lib resolves)
  local name="$1" d="$TMP/mut-$1"
  assert_fixture_dir "$d"; rm -rf "$d"; mkdir -p "$d/scripts/followthroughs" "$d/scripts/lib"
  cp "$REPO_ROOT/scripts/lib/trusted-verdict.sh" "$d/scripts/lib/trusted-verdict.sh"
  grep -v "# CHECK-$name\$" "$PROBE" > "$d/scripts/followthroughs/inngest-tls-soak-10136.sh"
  chmod +x "$d/scripts/followthroughs/inngest-tls-soak-10136.sh"
  if cmp -s "$PROBE" "$d/scripts/followthroughs/inngest-tls-soak-10136.sh"; then echo ""; else echo "$d/scripts/followthroughs/inngest-tls-soak-10136.sh"; fi
}
mut_row() { # mut_row <CHECK-NAME> <fx> <rows> <label>
  local name="$1" fx="$2" rows="$3" label="$4" m
  m="$(mutant "$name")"
  if [[ -z "$m" ]]; then fail "MUT-$name: the probe has no line tagged '# CHECK-$name' to delete"; return; fi
  PROBE_UNDER_TEST="$m" run_probe "$fx" "$rows"
  if [[ "$RC" -eq 0 ]]; then pass "MUT-$name: with the check deleted, $label now PASSES (the fixture reaches that line)"
  else fail "MUT-$name: $label still exits $RC with the check deleted -- it fails for another reason :: $(printf '%s' "$OUT" | head -2 | tr '\n' '|')"; fi
}
mut_row GAP        "$FXG" "$TMP/gap3h.jsonl" "the 3 h gap series (M2)"
build_series "$TMP/bootonly.jsonl" bootonly=250
run_probe "$FXG" "$TMP/bootonly.jsonl"
expect "M3b only the boot_id label changes at row 250 (counters continue) => FAIL" 1 "boot_id"
mut_row BOOT       "$FXG" "$TMP/bootonly.jsonl" "the boot_id-only change series (M3b)"
mut_row LEGACY     "$FXG" "$TMP/m1.jsonl"    "the legacy-increase series (M1)"
mut_row DECREASE   "$FX7"  "$TMP/m7.jsonl"   "the legacy-decrease series (M7)"
mut_row TLSDECREASE "$FXG" "$TMP/tlsdec.jsonl" "the tls-decrease series (R12)"
mut_row TLSDELTA   "$FXG" "$TMP/m6.jsonl"    "the flat-flat series (M6)"

# --- no case may have been answered by a REFUSED fake-gh argv (the lib maps any gh failure to rc 2/3, which would let an
# rc-2/rc-3 row pass for the wrong reason) ---
refused="$(cat "$TMP"/fx-*/refused.log 2>/dev/null | head -3)"
if [[ -z "$refused" ]]; then pass "the fake gh refused no argv in any case"; else fail "the fake gh refused an argv: $refused"; fi

# --- anti-vacuity floor -------------------------------------------------------------------------------------------------
# Equal to the count measured on the green run, so deleting any case reds the suite. Reported with printf + exit, never
# through the helpers it backstops (ADR-193): a floor dispatched through fail() is disarmed by the same one-line edit that
# disarms every assertion it protects.
FLOOR=46
if [[ "$passes" -lt "$FLOOR" ]]; then
  printf '  FAIL ANTI-VACUITY: only %s PASSES recorded, floor is %s -- cases were deleted, skipped, or a helper stopped counting.\n' "$passes" "$FLOOR" >&2
  exit 1
fi
if [[ "$((passes + fails))" -ne "$asserted" ]]; then
  printf '  FAIL INSTRUMENT: passes(%s) + fails(%s) != asserted(%s) -- a verdict helper is not counting.\n' "$passes" "$fails" "$asserted" >&2
  exit 1
fi

printf '\ninngest-tls-soak-10136: %s passed, %s failed\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]] || exit 1
