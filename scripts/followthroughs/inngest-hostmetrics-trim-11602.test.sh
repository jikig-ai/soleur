#!/usr/bin/env bash
# Fixture suite for scripts/followthroughs/inngest-hostmetrics-trim-11602.sh, the #11602
# measured-close probe: exit 0 PASS only when the trailing-window collector set over rows
# isolated on tags.host='soleur-inngest' is exactly {memory, filesystem}; every other state
# is exit 2 TRANSIENT with a named reason. FAIL is deliberately unreachable.
#
# No network: the probe is COPIED into a temp tree `$TREE/scripts/followthroughs/` whose
# sibling `$TREE/scripts/betterstack-query.sh` is a stub, because the probe resolves its
# reader as `$SCRIPT_DIR/../betterstack-query.sh` and has no environment seam. The probe
# reads via MODE-1 RAW SQL (the GROUP BY aggregation is server-side, so a 17.8k-row/day
# window can never be truncated by a --limit), so the stub (a) REFUSES any argv that is not
# a SELECT carrying the tags.host isolation + GROUP BY + JSONEachRow contract, and (b)
# serves the fixture aggregate rows `{c,n}` from $STUB_ROWS. Registered EXPLICITLY in
# scripts/test-all.sh (scripts/followthroughs/*.test.sh is not in SUITE_GLOBS).
#
# INSTRUMENT SELF-TEST. check/has/hasnt are driven with known-true and known-false inputs
# before any fixture row; a helper that cannot tell them apart aborts (rc 4).
#
# MUTATION BATTERY. After the fixture rows the suite mutates a scratch copy of the probe at
# the `# [mut:NAME]` tag lines and re-runs itself against the mutant (FT_INNER=1). A mutant
# is credited only when the inner run exits 1 AND prints its own named `FAIL: <fragment>`
# line; rc 0 = SURVIVED. A pristine control must come back rc 0 first.
#
# STUBBED-PROBE GUARD (Guard 2 battery row 6). SAW_PASS must end at 1: a probe that can
# never reach a verdict — e.g. a stub that always exits 2 — leaves SAW_PASS=0 and the
# suite goes RED. That is the row that proves a green suite is not a vacuous one.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${FT_REPO:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SUT="${FT_SUT:-$SCRIPT_DIR/inngest-hostmetrics-trim-11602.sh}"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT:?}"' EXIT

PASS=0; FAIL=0; LEDGER="$ROOT/ledger"; : > "$LEDGER"
ok()    { PASS=$((PASS + 1)); printf 'ok\t%s\n' "$1" >> "$LEDGER"; echo "  PASS: $1"; }
bad()   { FAIL=$((FAIL + 1)); printf 'bad\t%s\n' "$1" >> "$LEDGER"; echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3]" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected [$3] present" ;; *) ok "$1" ;; esac; }

instrument_selftest() {
  local p0=$PASS f0=$FAIL n0 p1 f1 p2 f2
  n0="$(wc -l < "$LEDGER")"
  { check st 1 2; has st abc z; hasnt st abc b; } >/dev/null
  p1=$((PASS - p0)); f1=$((FAIL - f0))
  { check st 1 1; has st abc b; hasnt st abc z; } >/dev/null
  p2=$((PASS - p0 - p1)); f2=$((FAIL - f0 - f1))
  PASS=$p0; FAIL=$f0
  head -n "$n0" "$LEDGER" > "$LEDGER.t" && mv "$LEDGER.t" "$LEDGER"
  if [ "$p1/$f1/$p2/$f2" != "0/3/3/0" ]; then
    echo "INSTRUMENT SELF-TEST FAILED: check/has/hasnt cannot tell true from false"
    exit 4
  fi
}
instrument_selftest

CAN_STR="CANARY-3d7b1e"

# The temp tree: probe under scripts/followthroughs/, stub reader at scripts/betterstack-query.sh.
TREE="$ROOT/tree"; mkdir -p "$TREE/scripts/followthroughs"
PROBE="$TREE/scripts/followthroughs/inngest-hostmetrics-trim-11602.sh"
cp "$SUT" "$PROBE"
QUERY_STUB="$TREE/scripts/betterstack-query.sh"
cat > "$QUERY_STUB" <<'STUB'
#!/usr/bin/env bash
# Mode-1 raw-SQL reader stub. REFUSES argv that is not the probe's GROUP BY read —
# a probe that dropped the tags.host isolation, the GROUP BY, the archive arm or the
# JSONEachRow contract gets an exit-64 refusal, not rows.
set -u
printf '%s\n' "$*" > "$STUB_ARGS"
case "$*" in
  SELECT*)
    for needle in "JSONExtractString(raw, 'tags', 'collector')" "JSONExtractString(raw, 'tags', 'host')" \
                  "'soleur-inngest'" "GROUP BY c" "INTERVAL" "FORMAT JSONEachRow" "remote(" "s3Cluster" "_row_type = 1"; do
      case "$*" in *"$needle"*) : ;; *) echo "REFUSED missing:$needle" >> "$STUB_CALLS"; exit 64 ;; esac
    done
    echo MAIN >> "$STUB_CALLS"
    cat "$STUB_ROWS" 2>/dev/null
    if [ "${STUB_RC:-0}" != 0 ]; then
      echo "auth failure for user secret-user at host secret-host $STUB_CANARY" >&2; exit "$STUB_RC"
    fi
    ;;
  *) echo "REFUSED unexpected-argv" >> "$STUB_CALLS"; exit 64 ;;
esac
STUB
chmod +x "$QUERY_STUB"
EVIL="$ROOT/evil.sh"; printf '#!/usr/bin/env bash\necho EVIL >> "%s"\n' "$ROOT/evil-called" > "$EVIL"; chmod +x "$EVIL"

RCS="$ROOT/rcs"; : > "$RCS"
OUT=""; RC=0; SAW_PASS=0
run() {  # knobs: QH QU QP XBASH XENV STUB_RC TRIMW
  RC=0
  rm -f "$ROOT/args" "$ROOT/calls" "$ROOT/evil-called"; : > "$ROOT/calls"
  OUT="$(env -i PATH="$PATH" HOME="$ROOT" TMPDIR="$ROOT" STUB_ARGS="$ROOT/args" STUB_CALLS="$ROOT/calls" \
    STUB_ROWS="$ROOT/rows" STUB_RC="${STUB_RC:-0}" STUB_CANARY="$CAN_STR" \
    TRIM_QUERY_BIN="$EVIL" ${TRIMW:+TRIM_WINDOW="$TRIMW"} \
    BETTERSTACK_QUERY_HOST="${QH-h}" BETTERSTACK_QUERY_USERNAME="${QU-u}" BETTERSTACK_QUERY_PASSWORD="${QP-p}" \
    ${XENV:+"$XENV"} bash ${XBASH:+"$XBASH"} "$PROBE" 2>&1 </dev/null)" || RC=$?
  echo "$RC" >> "$RCS"
  [ "$RC" = 0 ] && SAW_PASS=1
  return 0
}
calls()  { grep -c . "$ROOT/calls" 2>/dev/null || true; }
mcalls() { grep -c '^MAIN$' "$ROOT/calls" 2>/dev/null || true; }
reset_knobs() { unset QH QU QP XBASH XENV STUB_RC TRIMW; }
run_battery() { [ -z "${FT_INNER:-}" ] && [ "${1:-}" != "--no-battery" ]; }

agg() { printf '{"c":"%s","n":%s}\n' "$1" "$2"; }   # a GROUP BY aggregate row, JSONEachRow

reset_knobs
echo "=== inngest-hostmetrics-trim-11602.sh tests ==="

# 1. credentials: missing in any position is TRANSIENT with no reader call
for v in QH QU QP; do
  agg memory 5 > "$ROOT/rows"; eval "$v=''"; run
  check "empty $v: exit 2" 2 "$RC"; has "empty $v: credentials_unprovisioned" "$OUT" "credentials_unprovisioned"
  check "empty $v: reader never called" 0 "$(calls)"; reset_knobs
done

# 2. xtrace refusal: 78 before any read, creds or not
agg memory 5 > "$ROOT/rows"; XBASH="-x" run; reset_knobs
check "xtrace with credentials: exit 78" 78 "$RC"; check "xtrace: reader never called" 0 "$(calls)"
QP="" XBASH="-x" run; reset_knobs
check "xtrace with no credentials: exit 2 (the refusal exists to protect the credential, and none is in scope)" 2 "$RC"

# 3. reader failure is TRANSIENT query_failed, and credential-shaped stderr is withheld
agg memory 5 > "$ROOT/rows"; STUB_RC=7 run; reset_knobs
check "reader exits 7: exit 2 query_failed" 2 "$RC"
has "reader failure names query_failed" "$OUT" "query_failed"
hasnt "reader failure: user withheld" "$OUT" "secret-user"; hasnt "reader failure: host withheld" "$OUT" "secret-host"
hasnt "reader failure: canary withheld" "$OUT" "$CAN_STR"
agg memory 5 > "$ROOT/rows"; mv "$QUERY_STUB" "$QUERY_STUB.off"; run; mv "$QUERY_STUB.off" "$QUERY_STUB"; reset_knobs
check "reader script missing: exit 2" 2 "$RC"

# 4. the verdict matrix (Guard 2 rows 1-3)
: > "$ROOT/rows"; run
check "empty window: exit 2" 2 "$RC"; has "empty window: no_host_metrics" "$OUT" "no_host_metrics"
{ agg cpu 40; agg memory 30; agg disk 25; agg filesystem 9; agg load 15; } > "$ROOT/rows"; run
check "the live untrimmed set: exit 2" 2 "$RC"; has "untrimmed set: untrimmed named" "$OUT" "untrimmed"
has "untrimmed verdict names what it saw" "$OUT" "cpu"
agg memory 30 > "$ROOT/rows"; run
check "partial set (memory only): exit 2" 2 "$RC"; has "partial set: not a PASS" "$OUT" "untrimmed"
{ agg cpu 40; agg memory 30; agg filesystem 9; } > "$ROOT/rows"; run
check "superset (one extra collector): exit 2" 2 "$RC"
agg filesystem 9 > "$ROOT/rows"; run
check "partial set (filesystem only): exit 2" 2 "$RC"
{ agg memory 0; agg filesystem 9; } > "$ROOT/rows"; run
check "a zero-count memory row does not count as liveness: exit 2" 2 "$RC"

# 5. PASS on the exact set — the must-PASS non-canonical row carries unrelated-identifier
#    noise (an object that is not a {c,n} aggregate) and reversed order.
{ agg filesystem 9; agg memory 30; printf '%s\n' '{"dt":"2026-10-30 08:00:00","raw":"{\"SYSLOG_IDENTIFIER\":\"stunnel4\",\"message\":\"noise\"}"}'; } > "$ROOT/rows"; run
check "exact set plus unrelated-identifier noise: exit 0" 0 "$RC"
has "PASS names the collectors" "$OUT" "memory"; has "PASS names the collectors (2)" "$OUT" "filesystem"
has "PASS mentions the window" "$OUT" "24h"

# 6. an unreadable read is selector drift, never a verdict
{ agg memory 30; printf 'Code: 241. DB::Exception: truncated tail %s\n' "$CAN_STR"; } > "$ROOT/rows"; run
check "a non-JSON tail line beside a valid row: exit 2" 2 "$RC"
has "garbage line: selector_failed" "$OUT" "selector_failed"; hasnt "garbage line: canary withheld" "$OUT" "$CAN_STR"
{ printf '%s\n' '{"note":"foreign shape"}' '{"other":1}'; } > "$ROOT/rows"; run
check "only foreign-shaped objects: exit 2 (drift, not an empty window)" 2 "$RC"
has "all-foreign output: selector_failed, never no_host_metrics" "$OUT" "selector_failed"

# 7. the read itself: trailing-window GROUP BY, argv as the contract expects
agg memory 5 > "$ROOT/rows"; run
args="$(cat "$ROOT/args" 2>/dev/null)"
has "the SQL groups by collector" "$args" "GROUP BY c"
has "the SQL isolates tags.host" "$args" "'soleur-inngest'"
has "the SQL reads the trailing window" "$args" "INTERVAL 24 HOUR"
has "the SQL reads hot + archive" "$args" "s3Cluster"
check "exactly one read per run" 1 "$(mcalls)"
TRIMW="7d" run; reset_knobs
args="$(cat "$ROOT/args" 2>/dev/null)"
has "TRIM_WINDOW=7d maps to INTERVAL 7 DAY" "$args" "INTERVAL 7 DAY"
TRIMW="bogus" run; reset_knobs
check "an unparseable window: exit 2, never silently defaulted" 2 "$RC"
has "unparseable window: query_failed named" "$OUT" "query_failed"

# 8. no env seam can repoint the reader (the credential the probe carries rides this channel)
agg memory 5 > "$ROOT/rows"; run
check "an exported TRIM_QUERY_BIN is ignored: the evil script never ran" "" "$(cat "$ROOT/evil-called" 2>/dev/null)"
check "an exported TRIM_QUERY_BIN is ignored: the sibling reader answered" 1 "$(mcalls)"
leftover="$(grep -n 'TRIM_QUERY_BIN' "$SUT" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
check "the probe source has no TRIM_QUERY_BIN seam" "" "$leftover"
check "the reader path is fixed to \$SCRIPT_DIR/../betterstack-query.sh" 1 "$(grep -cE '^QUERY="\$SCRIPT_DIR/\.\./betterstack-query\.sh"' "$SUT")"

# 9. exit vocabulary, header contract and public-leak hygiene of the source
badrc="$(grep -vxE '0|2|78' "$RCS" | sort -u | tr '\n' ' ')"
check "every observed exit status is in {0,2,78} (FAIL unreachable)" "" "$badrc"
exits="$(grep -vE '^[[:space:]]*#' "$SUT" | grep -oE '(^|[^A-Za-z_])exit [0-9]+' 2>/dev/null | grep -oE '[0-9]+$' | sort -u | tr '\n' ' ')"
check "the source names only exit 0, 2 and 78 (FAIL unreachable)" "0 2 78 " "$exits"
qform="$(grep -nE '\$\{[A-Za-z_0-9]+:\?' "$SUT" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
check "no \${VAR:?} form on an executable line" "" "$qform"
check "the xtrace refusal precedes every credential reference" yes \
  "$([ "$(grep -n 'case "$-" in' "$SUT" | head -n1 | cut -d: -f1)" -lt "$(grep -n 'BETTERSTACK_QUERY_' "$SUT" | grep -v '^[0-9]*:[[:space:]]*#' | head -n1 | cut -d: -f1)" ] && echo yes || echo no)"
dir_lines="$(grep -E '^#[[:space:]]+<!-- soleur:followthrough ' "$SUT" || true)"
check "the header carries exactly one single-line follow-through directive" 1 "$(printf '%s\n' "$dir_lines" | grep -c .)"
check "the directive names this script, earliest= and secrets= on one line" 1 \
  "$(printf '%s\n' "$dir_lines" | grep -cE 'script=scripts/followthroughs/inngest-hostmetrics-trim-11602\.sh earliest=[0-9]{4}-[0-9]{2}-[0-9]{2}T00:00:00Z secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->$')"
has "the header names its tracker" "$(sed -n '1,50p' "$SUT")" "TRACKER: #11602"
has "the header carries a RETIREMENT census" "$(sed -n '1,80p' "$SUT")" "RETIREMENT:"
has "the RETIREMENT census names this suite" "$(sed -n '1,80p' "$SUT")" "inngest-hostmetrics-trim-11602.test.sh"
has "the RETIREMENT census names the directive on the tracker" "$(sed -n '1,80p' "$SUT")" "11602"

# 10. STUBBED-PROBE GUARD: the suite must go RED on a probe that can never reach a verdict
check "the probe reached PASS in at least one fixture run (a neutered probe reds here)" 1 "$SAW_PASS"

FIX_N="$(wc -l < "$LEDGER")"
if run_battery "${1:-}"; then
  echo "=== mutation battery ==="
  export FT_REPO="$REPO"
  MUT="$ROOT/mut"; mkdir -p "$MUT"
  mutate_run() { # <name> <tag-or-unique-text> <replacement line> <expected FAIL fragment>
    local name="$1" tag="$2" rep="$3" frag="$4" f="$MUT/$1.sh" o="$MUT/$1.out" rc=0
    if ! grep -qF -- "$tag" "$SUT"; then bad "mutation $name: tag $tag exists in the probe (instrument)"; return; fi
    REP="$rep" TAG="$tag" awk 'index($0, ENVIRON["TAG"]) { print ENVIRON["REP"]; next } { print }' "$SUT" > "$f"
    if cmp -s "$SUT" "$f"; then bad "mutation $name: the mutation did not land (instrument)"; return; fi
    if ! bash -n "$f" 2>/dev/null; then bad "mutation $name: the mutant does not parse (instrument)"; return; fi
    FT_INNER=1 FT_SUT="$f" bash "$SELF" > "$o" 2>&1 || rc=$?
    if [ "$rc" = 0 ]; then bad "mutation $name: SURVIVED (rc=0)"
    elif [ "$rc" != 1 ]; then bad "mutation $name: unresolved instrument rc=$rc"
    elif grep -qF -- "FAIL: $frag" "$o"; then ok "mutation $name: caught by its own FAIL line [$frag]"
    else bad "mutation $name: rc=1 but no FAIL line [$frag] (killed by something else)"; fi
  }
  mutate_sub() { # <name> <unique text> <from> <to> <expected FAIL fragment>
    local line new
    line="$(grep -F -- "$2" "$SUT" || true)"
    if [ -z "$line" ] || [ "$(printf '%s\n' "$line" | wc -l)" != 1 ]; then bad "mutation $1: the text [$2] matches exactly one line (instrument)"; return; fi
    new="${line/"$3"/"$4"}"
    if [ "$new" = "$line" ]; then bad "mutation $1: [$3] is present in the line (instrument)"; return; fi
    mutate_run "$1" "$2" "$new" "$5"
  }
  ctl=0; FT_INNER=1 FT_SUT="$SUT" bash "$SELF" >/dev/null 2>&1 || ctl=$?
  check "battery control: the pristine probe passes the inner suite (rc 0)" 0 "$ctl"
  mutate_run m1-xtrace-refusal-dropped '[mut:xtrace]' '  *zzz*)' 'xtrace with credentials: exit 78'
  mutate_run m2-cred-check-skipped    '[mut:cred]'    'if false; then' 'empty QH: credentials_unprovisioned'
  mutate_sub m3-set-equality-weakened '[mut:set]'    'filesystem memory' 'memory' 'exact set plus unrelated-identifier noise: exit 0'
  mutate_sub m4-host-isolation-dropped '[mut:host]'  'soleur-inngest' 'soleur-inngest-DRIFT' 'exact set plus unrelated-identifier noise: exit 0'
  mutate_sub m5-count-floor-dropped   '[mut:nfloor]'  '$2+0 >= 1' '$2+0 >= 0' 'a zero-count memory row does not count as liveness: exit 2'
  mutate_sub m6-window-default-moved  '[mut:window]'  '24h' '1h' 'the SQL reads the trailing window'
  mutate_sub m7-env-seam-reintroduced '[mut:query-path]' 'QUERY="$SCRIPT_DIR/../betterstack-query.sh"' 'QUERY="${TRIM_QUERY_BIN:-$SCRIPT_DIR/../betterstack-query.sh}"' 'an exported TRIM_QUERY_BIN is ignored: the evil script never ran'
fi

MIN_FIXTURE=50; MIN_BATTERY=8
LEDGER_N="$(wc -l < "$LEDGER")"
echo; echo "=== inngest-hostmetrics-trim-11602.sh: $PASS passed, $FAIL failed ($LEDGER_N recorded) ==="
if [ "$LEDGER_N" -ne $((PASS + FAIL)) ]; then printf 'LEDGER MISMATCH\n'; exit 1; fi
if [ -z "${FT_INNER:-}" ]; then
  if [ "$FIX_N" -lt "$MIN_FIXTURE" ]; then printf 'FLOOR: only %s fixture assertions ran, expected at least %s\n' "$FIX_N" "$MIN_FIXTURE"; exit 1; fi
  if run_battery "${1:-}" && [ $((LEDGER_N - FIX_N)) -lt "$MIN_BATTERY" ]; then printf 'FLOOR: only %s battery assertions ran, expected at least %s\n' "$((LEDGER_N - FIX_N))" "$MIN_BATTERY"; exit 1; fi
fi
[ "$FAIL" -eq 0 ]
