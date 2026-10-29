#!/usr/bin/env bash
# Fixture suite for scripts/followthroughs/inngest-luks-keeper-dark-11265.sh, a NOTIFY-ONLY probe: it may exit only
# 2 (NOT YET), 3 (CANNOT ESTABLISH), 5 (ACTION REQUIRED) or 78 (xtrace refusal), never 0 or 1, on EVERY path.
#
# No network: the Better Stack reader (scripts/betterstack-query.sh) is replaced through the probe's
# LUKS_KEEPER_QUERY_SCRIPT seam by a stub that RECORDS its argv and prints JSONEachRow rows shaped like the real
# reader's output (`raw` is a JSON STRING holding a JSON document whose `.message` is the marker line). Registered
# EXPLICITLY in scripts/test-all.sh (scripts/followthroughs/*.test.sh is not in SUITE_GLOBS).
#
# GUARD 3 BATTERY (plan Guard 3): after the fixture rows the suite mutates a scratch copy of the probe at the
# `# [mut:NAME]` tag lines and re-runs itself against the mutant (FT_INNER=1): rc 1 = caught, rc 0 = the mutant
# SURVIVED, rc >= 2 = the instrument broke. A pristine control must come back rc 0 first.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${FT_SUT:-$SCRIPT_DIR/inngest-luks-keeper-dark-11265.sh}"
SELF="$SCRIPT_DIR/inngest-luks-keeper-dark-11265.test.sh"
ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT:?}"' EXIT

PASS=0; FAIL=0; LEDGER="$ROOT/ledger"; : > "$LEDGER"
ok()    { PASS=$((PASS + 1)); printf 'ok\t%s\n' "$1" >> "$LEDGER"; echo "  PASS: $1"; }
bad()   { FAIL=$((FAIL + 1)); printf 'bad\t%s\n' "$1" >> "$LEDGER"; echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3]" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected [$3] present" ;; *) ok "$1" ;; esac; }

NOW=1790000000
DAY=86400
MARKER="SOLEUR_INNGEST_LUKS_KEY_PROBE"
dt_of() { date -u -d "@$1" '+%Y-%m-%d %H:%M:%S'; }

# row <epoch> <message> [fraction]: the REAL stored shape, raw = a JSON string holding {message, ...}
row() { jq -nc --arg dt "$(dt_of "$1")${3:-}" --arg m "$2" '{dt:$dt, raw:({message:$m, SYSLOG_IDENTIFIER:"inngest-cutover-flip"}|tojson)}'; }
mrow() { row "$1" "$MARKER token=$2 rc=0 at=tick"; }   # an anchored producer row

QUERY_STUB="$ROOT/query.sh"
cat > "$QUERY_STUB" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$STUB_ARGS"; echo CALL >> "$STUB_CALLS"
if [ -n "${STUB_RC:-}" ] && [ "$STUB_RC" != 0 ]; then echo "auth failure for user secret-user at host secret-host $STUB_CANARY" >&2; exit "$STUB_RC"; fi
cat "$STUB_ROWS"
STUB
chmod +x "$QUERY_STUB"

RCS="$ROOT/rcs"; : > "$RCS"
OUT=""; RC=0
run() {  # rows come from $ROOT/rows; knobs: QH QU QP (creds; unset = set), QSCRIPT, XBASH, XENV, STUB_RC
  RC=0
  rm -f "$ROOT/args" "$ROOT/calls"; : > "$ROOT/calls"
  OUT="$(env -i PATH="$PATH" HOME="$ROOT" TMPDIR="$ROOT" NOW_EPOCH="$NOW" STUB_ROWS="$ROOT/rows" STUB_ARGS="$ROOT/args" STUB_CALLS="$ROOT/calls" \
    STUB_RC="${STUB_RC:-0}" STUB_CANARY="CANARY-7f3a9c" LUKS_KEEPER_QUERY_SCRIPT="${QSCRIPT-$QUERY_STUB}" \
    BETTERSTACK_QUERY_HOST="${QH-h}" BETTERSTACK_QUERY_USERNAME="${QU-u}" BETTERSTACK_QUERY_PASSWORD="${QP-p}" \
    ${XENV:+"$XENV"} bash ${XBASH:+"$XBASH"} "$SUT" 2>&1 </dev/null)" || RC=$?
  echo "$RC" >> "$RCS"
}
calls() { grep -c '^CALL$' "$ROOT/calls" 2>/dev/null || true; }
reset_knobs() { unset QH QU QP QSCRIPT XBASH XENV STUB_RC; }
run_battery() { [ -z "${FT_INNER:-}" ] && [ "${1:-}" != "--no-battery" ]; }

reset_knobs
echo "=== inngest-luks-keeper-dark-11265.sh tests ==="

# 1. no rows of any kind: the normal state while the keeper is deferred
: > "$ROOT/rows"; run
check "no rows at all: exit 2 (NOT YET)" 2 "$RC"; has "no rows: NOT YET named" "$OUT" "NOT YET"
has "no rows: says the probe is inert until the first measured row" "$OUT" "inert"

# 2. echo isolation: a row that merely QUOTES the marker is not a producer row (anchored at message position 1)
{ row $((NOW - 40 * DAY)) "a PR body quoting $MARKER token=ok rc=0 at=tick verbatim"
  row $((NOW - 40 * DAY)) " $MARKER token=ok rc=0 at=tick"
  row $((NOW - 40 * DAY)) "x$MARKER token=fail_header rc=1 at=tick"; } > "$ROOT/rows"; run
check "quoting rows only (marker not at position 1): exit 2, not counted" 2 "$RC"
hasnt "quoting rows: no row count printed as a measurement" "$OUT" "measured=1"
jq -nc --arg dt "$(dt_of $((NOW - 40 * DAY)))" --arg m "$MARKER token=ok rc=0 at=tick" '{dt:$dt, raw:({message:"unrelated", note:$m}|tojson)}' > "$ROOT/rows"; run
check "marker in a field other than message is not a producer row: exit 2" 2 "$RC"

# 3. a measured row under 30 days old: NOT YET, whichever measured token it carries
for tok in ok fail_passphrase fail_header fail_key_absent fail_other; do
  mrow $((NOW - 5 * DAY)) "$tok" > "$ROOT/rows"; run
  check "newest measured row (token=$tok) 5 days old: exit 2" 2 "$RC"
done
mrow $((NOW - 5 * DAY)) ok > "$ROOT/rows"; run
has "NOT YET prints the counts" "$OUT" "rows=1 measured=1 indeterminate=0"

# 4. the 30-day boundary
mrow $((NOW - 30 * DAY + 1)) ok > "$ROOT/rows"; run
check "newest measured row 30 days minus one second old: exit 2" 2 "$RC"
mrow $((NOW - 30 * DAY)) ok > "$ROOT/rows"; run
check "newest measured row exactly 30 days old: exit 5 (30 days or older)" 5 "$RC"
mrow $((NOW - 30 * DAY - 1)) ok > "$ROOT/rows"; run
check "newest measured row 30 days plus one second old: exit 5" 5 "$RC"
has "ACTION REQUIRED named" "$OUT" "ACTION REQUIRED"
has "ACTION REQUIRED says the tracker is not closed by the probe" "$OUT" "NOT closed by the probe"
mrow $((NOW - 45 * DAY)) fail_passphrase > "$ROOT/rows"; run
check "a 45-day-old failed-verdict row is a measured row too: exit 5" 5 "$RC"

# 5. only the NEWEST measured row decides; indeterminate rows never count as health and never reset the window
{ mrow $((NOW - 40 * DAY)) ok; mrow $((NOW - 2 * DAY)) ok; } > "$ROOT/rows"; run
check "an old measured row plus a fresh measured row: exit 2" 2 "$RC"
{ mrow $((NOW - 40 * DAY)) ok; mrow $((NOW - 1 * DAY)) indeterminate; mrow $((NOW - 2 * DAY)) indeterminate; } > "$ROOT/rows"; run
check "old measured row plus fresh indeterminate rows: exit 5 (indeterminate never resets the window)" 5 "$RC"
has "mixed history: counts printed" "$OUT" "rows=3 measured=1 indeterminate=2"
{ mrow $((NOW - 2 * DAY)) ok; mrow $((NOW - 50 * DAY)) ok; } > "$ROOT/rows"; run
check "input order does not matter (newest measured row wins)" 2 "$RC"
{ mrow $((NOW - 2 * DAY)) ok; mrow $((NOW - 3 * DAY)) ok; } | tac > "$ROOT/rows"; run
check "reverse-ordered rows: exit 2" 2 "$RC"
row $((NOW - 5 * DAY)) "$MARKER token=ok rc=0 at=tick" ".123" > "$ROOT/rows"; run
check "a fractional-second dt is read: exit 2" 2 "$RC"
{ mrow $((NOW - 40 * DAY)) ok; mrow $((NOW - 40 * DAY)) ok; } > "$ROOT/rows"; run
check "the two shipping paths (journald and phone-home) land two rows at one instant: exit 5" 5 "$RC"
has "two shipping paths: both counted" "$OUT" "rows=2 measured=2"

# 6. indeterminate-only history: the probe could not measure; counts printed, exit 3 (never NOT YET forever)
{ mrow $((NOW - 1 * DAY)) indeterminate; mrow $((NOW - 2 * DAY)) indeterminate; mrow $((NOW - 3 * DAY)) indeterminate; } > "$ROOT/rows"; run
check "indeterminate-only history: exit 3" 3 "$RC"
has "indeterminate-only: prints rows=3 measured=0 indeterminate=3" "$OUT" "rows=3 measured=0 indeterminate=3"
has "indeterminate-only: CANNOT ESTABLISH" "$OUT" "CANNOT ESTABLISH"
mrow $((NOW - 200 * DAY)) indeterminate > "$ROOT/rows"; run
check "a single old indeterminate row: exit 3" 3 "$RC"

# 7. parse failures are CANNOT ESTABLISH, never a quiet verdict
mrow $((NOW - 5 * DAY)) weird_token > "$ROOT/rows"; run
check "an anchored row with an unrecognised token: exit 3" 3 "$RC"
row $((NOW - 5 * DAY)) "$MARKER no token here" > "$ROOT/rows"; run
check "an anchored row with no token: exit 3" 3 "$RC"
jq -nc --arg m "$MARKER token=ok rc=0 at=tick" '{dt:"not a date", raw:({message:$m}|tojson)}' > "$ROOT/rows"; run
check "a measured row with an unreadable timestamp: exit 3" 3 "$RC"
{ printf '%s\n' "garbage line mentioning $MARKER"; jq -nc --arg dt "$(dt_of $((NOW - 3 * DAY)))" '{dt:$dt, raw:"not json at all"}'; } > "$ROOT/rows"; run
check "lines that mention the marker but decode to nothing and no producer row: exit 3 (shape drift)" 3 "$RC"
has "shape drift is named" "$OUT" "SHAPE_DRIFT"
{ jq -nc --arg dt "$(dt_of $((NOW - 3 * DAY)))" '{dt:$dt, raw:"not json at all"}'; mrow $((NOW - 2 * DAY)) ok; } > "$ROOT/rows"; run
check "an undecodable line beside a valid producer row does not block the verdict: exit 2" 2 "$RC"

# 8. what the probe asks Better Stack for: hot window + archive arm, 60 days, NOT --raw-only (it drops journald rows)
: > "$ROOT/rows"; run
args="$(cat "$ROOT/args" 2>/dev/null)"
has "queries 60 days" "$args" "--since 60d"
has "greps the marker name" "$args" "--grep $MARKER"
has "bounded limit" "$args" "--limit 5000"
hasnt "never --raw-only (it excludes the journald rows)" "$args" "--raw-only"
hasnt "never --no-archive (the archive arm is what reaches 31 days back)" "$args" "--no-archive"
check "exactly one reader call" 1 "$(calls)"

# 9. read failure: CANNOT ESTABLISH, and the reader's credential-bearing stderr is withheld
mrow $((NOW - 5 * DAY)) ok > "$ROOT/rows"; STUB_RC=7 run; unset STUB_RC
check "reader exits 7: exit 3 (never a verdict from the rows it printed)" 3 "$RC"
hasnt "reader failure: user withheld" "$OUT" "secret-user"; hasnt "reader failure: host withheld" "$OUT" "secret-host"
hasnt "reader failure: canary withheld" "$OUT" "CANARY-7f3a9c"
has "reader failure: fixed reason with the exit code" "$OUT" "Better Stack read failed (exit 7)"
for rc in 1 2 3 64 78; do STUB_RC=$rc run; check "reader exits $rc: exit 3" 3 "$RC"; done; unset STUB_RC
: > "$ROOT/rows"; QSCRIPT="$ROOT/does-not-exist.sh" run; reset_knobs
check "reader script missing: exit 3" 3 "$RC"

# 10. credentials: missing in any position is CANNOT ESTABLISH with no reader call
for v in QH QU QP; do
  mrow $((NOW - 5 * DAY)) ok > "$ROOT/rows"; eval "$v=''"; run
  check "empty $v: exit 3" 3 "$RC"; check "empty $v: reader never called" 0 "$(calls)"; reset_knobs
done

# 11. xtrace refusal: 78 before any read, with or without credentials
mrow $((NOW - 5 * DAY)) ok > "$ROOT/rows"; XBASH="-x" run; reset_knobs
check "xtrace with credentials: exit 78" 78 "$RC"; check "xtrace: reader never called" 0 "$(calls)"
QP="" XBASH="-x" run; reset_knobs
check "xtrace with no credentials still refuses: exit 78" 78 "$RC"

# 12. exit vocabulary and public-leak hygiene of the source
badrc="$(grep -vxE '2|3|5|78' "$RCS" | sort -u | tr '\n' ' ')"
check "every observed exit status is in {2,3,5,78}" "" "$badrc"
exits="$(grep -oE '(^|[^A-Za-z_])exit [0-9]+' "$SUT" 2>/dev/null | grep -oE '[0-9]+$' | sort -u | tr '\n' ' ')"
check "the source names only exit 2, 3, 5 and 78 (a literal exit 0 or 1 cannot exist)" "2 3 5 78 " "$exits"
qform="$(grep -nE '\$\{[A-Za-z_0-9]+:\?' "$SUT" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
check "no \${VAR:?} form on an executable line (it aborts with status 1)" "" "$qform"
echoed="$(grep -nE 'echo[^|]*\$\{?OUT\}?|printf[^|]*\$\{?OUT\}?[^|]*>&2' "$SUT" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
check "no executable line echoes the reader output" "" "$echoed"
direct="$(grep -nE '(^|[^A-Za-z_])curl[[:space:]]|Authorization:|Bearer' "$SUT" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
check "no direct curl and no bearer: the only egress is the pinned reader" "" "$direct"
rawonly="$(grep -nE '^[^#]*--raw-only' "$SUT" 2>/dev/null || true)"
check "the source never passes --raw-only on an executable line" "" "$rawonly"

# 13. the EXIT trap keeps a stray status inside the vocabulary (a fault injected at the read exits 1 in the body)
cat > "$ROOT/fault.sh" <<'FAULT'
trap 'case "$BASH_COMMAND" in read_rows*) exit 1 ;; esac' DEBUG
FAULT
mrow $((NOW - 5 * DAY)) ok > "$ROOT/rows"; XENV="BASH_ENV=$ROOT/fault.sh" run; reset_knobs
check "an unexpected internal exit status is mapped to 3 by the EXIT trap" 3 "$RC"

if run_battery "${1:-}"; then
  echo "=== Guard 3 mutation battery ==="
  MUT="$ROOT/mut"; mkdir -p "$MUT"
  mutate_run() {  # $1 = name, $2 = tag, $3 = replacement line
    local name="$1" tag="$2" rep="$3" f="$MUT/$1.sh" rc=0
    if ! grep -qF "$tag" "$SUT"; then bad "mutation $name: tag $tag exists in the probe (instrument)"; return; fi
    REP="$rep" TAG="$tag" awk 'index($0, ENVIRON["TAG"]) { print ENVIRON["REP"]; next } { print }' "$SUT" > "$f"
    FT_INNER=1 FT_SUT="$f" bash "$SELF" >/dev/null 2>&1 || rc=$?
    if [ "$rc" = 1 ]; then ok "mutation $name: rc=$rc (caught)"
    elif [ "$rc" = 0 ]; then bad "mutation $name: SURVIVED (rc=0)"
    else bad "mutation $name: unresolved instrument rc=$rc"; fi
  }
  ctl=0; FT_INNER=1 FT_SUT="$SUT" bash "$SELF" >/dev/null 2>&1 || ctl=$?
  check "battery control: the pristine probe passes the inner suite (rc 0)" 0 "$ctl"
  mutate_run m1-action-exit-0       '[mut:action]'      '    exit 0'
  mutate_run m2-read-fail-falls-through '[mut:read-fail]' '  if (( RC != 0 )); then OUT=""; return 0; fi'
  mutate_run m2b-trap-removed       '[mut:trap]'        ':'
  mutate_run m4-xtrace-refusal-dropped '[mut:xtrace]'   '  *x*) : ;;'
  mutate_run m5a-reader-output-echoed '[mut:read-fail]' '  if (( RC != 0 )); then echo "$OUT"; cannot "Better Stack read failed (exit ${RC})"; fi'
  mutate_run m5b-anchor-dropped     '[mut:anchor]'      "ANCHOR='(\$d.message | contains(\$m))'"
  mutate_run m5c-indeterminate-counts-as-measured '[mut:classify]' "CLASSIFY='\$1==\"A\"{a++; if(\$3==\"ok\"||\$3==\"indeterminate\"||\$3 ~ /^fail_/){m++; if(\$2==\"-\"){be++} else if(\$2+0>n){n=\$2+0}} else {b++}} \$1==\"U\"{u++} END{printf \"%d %d %d %d %d %d %d\\n\", a,m,i,b,u,n,be}'"
  mutate_run m5d-threshold-off-by-one '[mut:threshold]' '  if (( age > DARK_SECS )); then'
  mutate_run m5e-indeterminate-only-is-not-yet '[mut:indet]' '  if (( INDET > 0 )); then echo "NOT YET: indeterminate only"; exit 2; fi'
  mutate_run m5f-shape-drift-ignored '[mut:drift]'      '  if false; then'
  mutate_run m5g-bad-token-ignored  '[mut:badtoken]'    ':'
  mutate_run m5h-missing-cred-still-reads '[mut:cred-check]' ':'
  mutate_run m5i-window-30-to-31-days '[mut:window]'    'readonly DARK_SECS=$((31 * 86400))'
fi

MIN_ASSERTS=70
LEDGER_N="$(wc -l < "$LEDGER")"
echo; echo "=== inngest-luks-keeper-dark-11265.sh: $PASS passed, $FAIL failed ($LEDGER_N recorded) ==="
if [ "$LEDGER_N" -ne $((PASS + FAIL)) ]; then printf 'LEDGER MISMATCH\n'; exit 1; fi
if [ -z "${FT_INNER:-}" ] && [ "$LEDGER_N" -lt "$MIN_ASSERTS" ]; then printf 'FLOOR: only %s assertions ran, expected at least %s\n' "$LEDGER_N" "$MIN_ASSERTS"; exit 1; fi
[ "$FAIL" -eq 0 ]
