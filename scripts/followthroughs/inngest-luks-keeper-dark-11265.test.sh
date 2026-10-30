#!/usr/bin/env bash
# Fixture suite for scripts/followthroughs/inngest-luks-keeper-dark-11265.sh, a NOTIFY-ONLY probe: it may exit only
# 2 (NOT YET), 3 (CANNOT ESTABLISH), 5 (ACTION REQUIRED) or 78 (xtrace refusal), never 0 or 1, on EVERY path.
#
# No network: the probe is COPIED into a temp tree `$ROOT/scripts/followthroughs/` whose sibling
# `$ROOT/scripts/betterstack-query.sh` is a stub, because the probe resolves its reader as
# `$SCRIPT_DIR/../betterstack-query.sh` and has no environment seam. The stub RECORDS its argv and prints JSONEachRow rows
# shaped like the real reader's output (`raw` is a JSON STRING holding a JSON document whose `.message` is the marker
# line); a call WITH `--grep` is the main read, a call without it is the archive-arm canary, and the stub honors the
# canary's `--since 24h` / `--until` by dropping canary rows outside that window (like the real reader). Registered EXPLICITLY
# in scripts/test-all.sh (scripts/followthroughs/*.test.sh is not in SUITE_GLOBS).
#
# INSTRUMENT SELF-TEST. Before any fixture row, check/has/hasnt are driven with known-true and known-false inputs; a
# helper that cannot tell them apart aborts the run (rc 4, `INSTRUMENT SELF-TEST FAILED`). The battery proves that
# detection by neutering each helper in a copy of THIS file.
#
# MUTATION BATTERY. After the fixture rows the suite mutates a scratch copy of the probe at the `# [mut:NAME]` tag lines
# (or at any unique text) and re-runs itself against the mutant (FT_INNER=1). The crediting rule (a named `FAIL: <fragment>`
# line, never a bare non-zero exit) and the instrument self-test live in scripts/lib/mutation-harness.sh, whose scorer is pinned
# by the `scorer:` controls at the head of the battery.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${FT_REPO:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SUT="${FT_SUT:-$SCRIPT_DIR/inngest-luks-keeper-dark-11265.sh}"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT:?}"' EXIT

PASS=0; FAIL=0; LEDGER="$ROOT/ledger"; : > "$LEDGER"
ok()    { PASS=$((PASS + 1)); printf 'ok\t%s\n' "$1" >> "$LEDGER"; echo "  PASS: $1"; }
bad()   { FAIL=$((FAIL + 1)); printf 'bad\t%s\n' "$1" >> "$LEDGER"; echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3]" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected [$3] present" ;; *) ok "$1" ;; esac; }

MH_LIB="$REPO/scripts/lib/mutation-harness.sh"
[ -f "$MH_LIB" ] || { echo "mutation-harness lib missing: $MH_LIB"; exit 4; }
# shellcheck source=../lib/mutation-harness.sh
source "$MH_LIB"
MH_CTL="$REPO/scripts/lib/mutation-harness-controls.sh"
[ -f "$MH_CTL" ] || { echo "mutation-harness controls missing: $MH_CTL"; exit 4; }
# shellcheck source=../lib/mutation-harness-controls.sh
source "$MH_CTL"
instrument_selftest

NOW=1790000000
DAY=86400
MARKER="SOLEUR_INNGEST_LUKS_KEY_PROBE"
CAN_STR="CANARY-7f3a9c"
dt_of() { date -u -d "@$1" '+%Y-%m-%d %H:%M:%S'; }

# row <epoch> <message> [fraction]: the REAL stored shape, raw = a JSON string holding {message, ...}
row() { jq -nc --arg dt "$(dt_of "$1")${3:-}" --arg m "$2" '{dt:$dt, raw:({message:$m, SYSLOG_IDENTIFIER:"inngest-cutover-flip"}|tojson)}'; }
mrow() { row "$1" "$MARKER token=$2 rc=0 at=tick"; }   # an anchored producer row
# any live Logs row (the canary's answer): an object, not a keeper row; live_row is ARCHIVE-aged (5 h), hot_row is 60 s old
live_row() { jq -nc --arg dt "$(dt_of $((NOW - 5 * 3600)))" '{dt:$dt, raw:({message:"unrelated host line", SYSLOG_IDENTIFIER:"sshd"}|tojson)}'; }
hot_row() { jq -nc --arg dt "$(dt_of $((NOW - 60)))" '{dt:$dt, raw:({message:"unrelated host line", SYSLOG_IDENTIFIER:"sshd"}|tojson)}'; }

# The temp tree: the probe under test sits at scripts/followthroughs/, the stub reader at scripts/betterstack-query.sh.
TREE="$ROOT/tree"; mkdir -p "$TREE/scripts/followthroughs"
PROBE="$TREE/scripts/followthroughs/inngest-luks-keeper-dark-11265.sh"
cp "$SUT" "$PROBE"
QUERY_STUB="$TREE/scripts/betterstack-query.sh"
cat > "$QUERY_STUB" <<'STUB'
#!/usr/bin/env bash
case " $* " in
  *" --grep "*)
    printf '%s\n' "$*" > "$STUB_ARGS"; echo MAIN >> "$STUB_CALLS"
    cat "$STUB_ROWS"
    if [ -n "${STUB_RC:-}" ] && [ "$STUB_RC" != 0 ]; then echo "auth failure for user secret-user at host secret-host $STUB_CANARY" >&2; exit "$STUB_RC"; fi ;;
  *)
    printf '%s\n' "$*" > "$STUB_CARGS"; echo CANARY >> "$STUB_CALLS"
    since_arg=""; until_arg=""; prev=""
    for a in "$@"; do case "$prev" in --since) since_arg="$a" ;; --until) until_arg="$a" ;; esac; prev="$a"; done
    lo=""; hi=""
    if [ "$since_arg" = 24h ]; then lo="$(date -u -d "@$((STUB_NOW - 86400))" '+%Y-%m-%d %H:%M:%S')"; fi
    if [ -n "$until_arg" ]; then hi="$(printf '%s' "$until_arg" | sed 's/T/ /; s/Z$//')"; fi
    awk -v lo="$lo" -v hi="$hi" '{ if (match($0, /"dt":"[0-9-]+ [0-9:]+/)) { d = substr($0, RSTART + 6, RLENGTH - 6); if ((lo != "" && d < lo) || (hi != "" && d > hi)) next } print }' "$STUB_CROWS"
    if [ -n "${STUB_CRC:-}" ] && [ "$STUB_CRC" != 0 ]; then echo "auth failure for user secret-user at host secret-host $STUB_CANARY" >&2; exit "$STUB_CRC"; fi ;;
esac
STUB
chmod +x "$QUERY_STUB"
EVIL="$ROOT/evil.sh"; printf '#!/usr/bin/env bash\necho EVIL >> "%s"\n' "$ROOT/evil-called" > "$EVIL"; chmod +x "$EVIL"
live_row > "$ROOT/crow"

RCS="$ROOT/rcs"; : > "$RCS"
OUT=""; RC=0
run() {  # rows come from $ROOT/rows, the canary answer from $CROWS (default: one archive-aged live row); knobs: QH QU QP, NOWV, XBASH, XENV, STUB_RC, STUB_CRC
  RC=0
  rm -f "$ROOT/args" "$ROOT/cargs" "$ROOT/calls" "$ROOT/evil-called"; : > "$ROOT/calls"
  OUT="$(env -i PATH="$PATH" HOME="$ROOT" TMPDIR="$ROOT" NOW_EPOCH="${NOWV-$NOW}" STUB_NOW="$NOW" STUB_ROWS="$ROOT/rows" STUB_CROWS="${CROWS:-$ROOT/crow}" \
    STUB_ARGS="$ROOT/args" STUB_CARGS="$ROOT/cargs" STUB_CALLS="$ROOT/calls" \
    STUB_RC="${STUB_RC:-0}" STUB_CRC="${STUB_CRC:-0}" STUB_CANARY="$CAN_STR" LUKS_KEEPER_QUERY_SCRIPT="$EVIL" \
    BETTERSTACK_QUERY_HOST="${QH-h}" BETTERSTACK_QUERY_USERNAME="${QU-u}" BETTERSTACK_QUERY_PASSWORD="${QP-p}" \
    ${XENV:+"$XENV"} bash ${XBASH:+"$XBASH"} "$PROBE" 2>&1 </dev/null)" || RC=$?
  echo "$RC" >> "$RCS"
}
calls()  { grep -c . "$ROOT/calls" 2>/dev/null || true; }
mcalls() { grep -c '^MAIN$' "$ROOT/calls" 2>/dev/null || true; }
ccalls() { grep -c '^CANARY$' "$ROOT/calls" 2>/dev/null || true; }
reset_knobs() { unset QH QU QP NOWV XBASH XENV STUB_RC STUB_CRC CROWS; }

reset_knobs
echo "=== inngest-luks-keeper-dark-11265.sh tests ==="

# 1. no rows of any kind and a LIVE source: the normal state while the keeper is deferred
: > "$ROOT/rows"; run
check "no rows, live source: exit 2 (NOT YET)" 2 "$RC"; has "no rows: NOT YET named" "$OUT" "NOT YET"
has "no rows: says the probe is inert until the first measured row" "$OUT" "inert"
check "no rows: the canary was read once" 1 "$(ccalls)"

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
check "anchored rows found: the canary is not read" 0 "$(ccalls)"

# 4. the 30-day boundary
mrow $((NOW - 30 * DAY + 1)) ok > "$ROOT/rows"; run
check "newest measured row 30 days minus one second old: exit 2" 2 "$RC"
mrow $((NOW - 30 * DAY)) ok > "$ROOT/rows"; run
check "newest measured row exactly 30 days old: exit 5 (30 days or older)" 5 "$RC"
mrow $((NOW - 30 * DAY - 1)) ok > "$ROOT/rows"; run
check "newest measured row 30 days plus one second old: exit 5" 5 "$RC"
has "ACTION REQUIRED named" "$OUT" "ACTION REQUIRED"
has "ACTION REQUIRED says the tracker is not closed by the probe" "$OUT" "NOT closed by the probe"
has "ACTION REQUIRED points at the owner decision, not a bare conversion" "$OUT" "Owner decision: see the ADR-282 addendum of 2026-10-29"
hasnt "ACTION REQUIRED does not claim the keeper exists and went dark" "$OUT" "the keeper has gone dark"
mrow $((NOW - 45 * DAY)) fail_passphrase > "$ROOT/rows"; run
check "a 45-day-old failed-verdict row is a measured row too: exit 5" 5 "$RC"

# 4b. the newest measured token CLASS is printed (fixed vocabulary), so a fail-then-dark composition is legible
mrow $((NOW - 31 * DAY)) fail_header > "$ROOT/rows"; run
has "fail-then-dark: the newest measured token class is fail" "$OUT" "newest_measured_token=fail"
mrow $((NOW - 31 * DAY)) ok > "$ROOT/rows"; run
has "ok-then-dark: the newest measured token class is ok" "$OUT" "newest_measured_token=ok"
{ mrow $((NOW - 2 * DAY)) ok; mrow $((NOW - 3 * DAY)) fail_passphrase; } > "$ROOT/rows"; run
has "the newest measured row decides the class (ok over an older fail)" "$OUT" "newest_measured_token=ok"
{ mrow $((NOW - 2 * DAY)) fail_other; mrow $((NOW - 3 * DAY)) ok; } > "$ROOT/rows"; run
has "the newest measured row decides the class (fail over an older ok)" "$OUT" "newest_measured_token=fail"
{ mrow $((NOW - 2 * DAY)) ok; mrow $((NOW - 2 * DAY)) fail_other; } > "$ROOT/rows"; run
has "two measured rows in the same second: the class is fail (conservative)" "$OUT" "newest_measured_token=fail"
{ mrow $((NOW - 2 * DAY)) fail_other; mrow $((NOW - 2 * DAY)) ok; } > "$ROOT/rows"; run
has "two measured rows in the same second, fail listed first: the class is fail" "$OUT" "newest_measured_token=fail"
# a NOT YET whose newest measured row is a failed verdict says a resolved page is not recovery
mrow $((NOW - 20 * DAY)) fail_passphrase > "$ROOT/rows"; run
check "a lone 20-day-old failed-verdict row: exit 2" 2 "$RC"
has "NOT YET after a fail row: a resolved page is not recovery" "$OUT" "a resolved page is not recovery"
mrow $((NOW - 20 * DAY)) ok > "$ROOT/rows"; run
hasnt "NOT YET after an ok row: no failed-verdict note" "$OUT" "a resolved page is not recovery"

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
mrow 0 ok > "$ROOT/rows"; run
check "a sole measured row dated at the epoch: exit 3, not a 20717-day age" 3 "$RC"
hasnt "epoch-dated row: no ACTION REQUIRED" "$OUT" "ACTION REQUIRED"
jq -nc --arg m "$MARKER token=ok rc=0 at=tick" '{dt:"not a date", raw:({message:$m}|tojson)}' > "$ROOT/rows"; run
check "a measured row with an unreadable timestamp: exit 3" 3 "$RC"
# shape drift: an OBJECT that mentions nothing decodable, ALONE (no anchored row, no other line)
jq -nc --arg dt "$(dt_of $((NOW - 3 * DAY)))" '{dt:$dt, raw:"not json at all"}' > "$ROOT/rows"; run
check "an object whose raw does not decode, and no producer row: exit 3 (shape drift)" 3 "$RC"
has "shape drift is named" "$OUT" "SHAPE_DRIFT"
# a bare garbage LINE, ALONE: not an object, so the read itself is untrustworthy (a different reason from shape drift)
printf '%s\n' "garbage line mentioning $MARKER" > "$ROOT/rows"; run
check "a lone garbage line that mentions the marker: exit 3 (untrustworthy read)" 3 "$RC"
has "a lone garbage line is named as a PARSE failure" "$OUT" "PARSE:"
hasnt "a lone garbage line is not reported as shape drift" "$OUT" "SHAPE_DRIFT"
{ jq -nc --arg dt "$(dt_of $((NOW - 3 * DAY)))" '{dt:$dt, raw:"not json at all"}'; mrow $((NOW - 2 * DAY)) ok; } > "$ROOT/rows"; run
check "an object with an undecodable raw beside a valid producer row does not block the verdict: exit 2" 2 "$RC"
# a mid-stream failure emitted AS A JSON OBJECT (no dt, no raw) is not a reader row: class X, never class U
{ mrow $((NOW - 40 * DAY)) ok; printf '{"exception":"Code: 395. DB::Exception: %s"}\n' "$CAN_STR"; } > "$ROOT/rows"; run
check "an old measured row plus an exception-object tail: exit 3, never a false ACTION REQUIRED" 3 "$RC"
has "exception-object tail: a PARSE failure is named" "$OUT" "PARSE:"
hasnt "exception-object tail: never echoed" "$OUT" "$CAN_STR"
{ mrow $((NOW - 2 * DAY)) ok; printf '{"dt":"%s"}\n' "$(dt_of $((NOW - DAY)))"; } > "$ROOT/rows"; run
check "an object with a dt but no raw beside a valid row: exit 3" 3 "$RC"
{ mrow $((NOW - 2 * DAY)) ok; printf '{"raw":"{}"}\n'; } > "$ROOT/rows"; run
check "an object with a raw but no dt beside a valid row: exit 3" 3 "$RC"

# 7b. an UNTRUSTWORTHY read (R1 i): any non-blank reader line that is not a JSON object is exit 3 before any verdict
printf '<html><head><title>502 Bad Gateway</title></head><body>%s</body></html>\n' "$CAN_STR" > "$ROOT/rows"; run
check "an HTML 502 body with exit 0: exit 3" 3 "$RC"
has "502 body: a PARSE failure is named" "$OUT" "PARSE:"
hasnt "502 body: the body is never echoed" "$OUT" "$CAN_STR"
{ mrow $((NOW - 2 * DAY)) ok; printf 'Code: 241. DB::Exception: Memory limit (for query) exceeded: %s\n' "$CAN_STR"; } > "$ROOT/rows"; run
check "valid rows then a ClickHouse 'Code: ... DB::Exception' line (truncated tail): exit 3, not a verdict" 3 "$RC"
hasnt "DB::Exception line: never echoed" "$OUT" "$CAN_STR"
{ mrow $((NOW - 40 * DAY)) ok; printf 'Code: 241. DB::Exception: Memory limit exceeded\n'; } > "$ROOT/rows"; run
check "an old measured row plus a DB::Exception line: exit 3, never a false ACTION REQUIRED" 3 "$RC"
{ printf 'Code: 241. DB::Exception: Memory limit exceeded\n'; mrow $((NOW - 2 * DAY)) ok; } > "$ROOT/rows"; run
check "a DB::Exception line BEFORE valid rows: exit 3" 3 "$RC"
for junk in '[1,2]' '"a string"' 'null' '42' 'true' '{"dt":"x"} trailing'; do
  { mrow $((NOW - 2 * DAY)) ok; printf '%s\n' "$junk"; } > "$ROOT/rows"; run
  check "valid row plus a non-object line ($junk): exit 3" 3 "$RC"
done
{ printf '\n'; mrow $((NOW - 2 * DAY)) ok; printf '   \n'; mrow $((NOW - 3 * DAY)) ok; printf '\n'; } > "$ROOT/rows"; run
check "blank and whitespace-only lines are ignored: exit 2" 2 "$RC"
has "blank lines: both rows counted" "$OUT" "rows=2 measured=2"

# 7c. the archive-arm canary (R1 ii as amended by the CTO ruling C1): zero anchored rows needs proof the ARCHIVE arm is live
: > "$ROOT/rows"; : > "$ROOT/crow-empty"; CROWS="$ROOT/crow-empty" run; reset_knobs
check "empty body and an EMPTY canary: exit 3 (a dead source is not 'no keeper rows')" 3 "$RC"
has "empty body and empty canary: the fixed reason" "$OUT" "reader archive arm not live"
: > "$ROOT/rows"; run
check "empty body and a LIVE canary: exit 2" 2 "$RC"
: > "$ROOT/rows"; STUB_CRC=7 run; reset_knobs
check "empty body and a canary that exits 7: exit 3" 3 "$RC"
has "canary exit 7: the fixed reason" "$OUT" "reader archive arm not live"
hasnt "canary failure: user withheld" "$OUT" "secret-user"; hasnt "canary failure: host withheld" "$OUT" "secret-host"
hasnt "canary failure: canary string withheld" "$OUT" "$CAN_STR"
printf '<html>%s</html>\n' "$CAN_STR" > "$ROOT/crow-html"; CROWS="$ROOT/crow-html" run; reset_knobs
check "empty body and an HTML canary: exit 3" 3 "$RC"; hasnt "HTML canary: never echoed" "$OUT" "$CAN_STR"
{ live_row; printf 'Code: 241. DB::Exception: x\n'; } > "$ROOT/crow-mixed"; CROWS="$ROOT/crow-mixed" run; reset_knobs
check "empty body and a canary with one object line and one non-object line: exit 3" 3 "$RC"
printf '  \n\n' > "$ROOT/crow-blank"; CROWS="$ROOT/crow-blank" run; reset_knobs
check "empty body and a whitespace-only canary: exit 3" 3 "$RC"
printf '[1]\n' > "$ROOT/crow-arr"; CROWS="$ROOT/crow-arr" run; reset_knobs
check "empty body and a canary that decodes to a JSON array, not an object: exit 3" 3 "$RC"
# the canary must be a {dt, raw} reader row: an exception emitted as a JSON object is not proof of life
printf '{"exception":"Code: 395. DB::Exception: %s"}\n' "$CAN_STR" > "$ROOT/crow-exc"; CROWS="$ROOT/crow-exc" run; reset_knobs
check "empty body and an exception-object-only canary: exit 3" 3 "$RC"; hasnt "exception-object canary: never echoed" "$OUT" "$CAN_STR"
printf '{"dt":"%s"}\n' "$(dt_of $((NOW - 5 * 3600)))" > "$ROOT/crow-nodt"; CROWS="$ROOT/crow-nodt" run; reset_knobs
check "empty body and a canary object with a dt but no raw: exit 3" 3 "$RC"
# the canary window excludes the hot window: a row 60 s old can only come from the hot arm, which cannot prove the archive
hot_row > "$ROOT/crow-hot"; CROWS="$ROOT/crow-hot" run; reset_knobs
check "empty body and a canary holding only a 60 s old (hot-window) row: exit 3" 3 "$RC"
has "hot-window-only canary: the fixed reason names the archive arm" "$OUT" "no rows 3-24h back; the hot window cannot answer this"
{ hot_row; live_row; } > "$ROOT/crow-both"; CROWS="$ROOT/crow-both" run; reset_knobs
check "empty body and a canary holding a hot row plus a 5 h old row: exit 2" 2 "$RC"
jq -nc --arg dt "$(dt_of $((NOW - 25 * 3600)))" '{dt:$dt, raw:({message:"too old"}|tojson)}' > "$ROOT/crow-old"; CROWS="$ROOT/crow-old" run; reset_knobs
check "empty body and a canary holding only a 25 h old row (outside --since 24h): exit 3" 3 "$RC"
# quoting rows only: no anchored row, so the canary is read too
{ row $((NOW - 40 * DAY)) "a PR body quoting $MARKER token=ok rc=0 at=tick"; } > "$ROOT/rows"; run
check "quoting rows only and a live canary: exit 2, canary read" 2 "$RC"; check "quoting rows only: canary read once" 1 "$(ccalls)"
CROWS="$ROOT/crow-empty" run; reset_knobs
check "quoting rows only and a dead canary: exit 3" 3 "$RC"
# a verdict from anchored rows never needs the canary, even when the canary would be dead
mrow $((NOW - 5 * DAY)) ok > "$ROOT/rows"; CROWS="$ROOT/crow-empty" run; reset_knobs
check "anchored measured row beside a dead canary: exit 2 (the canary is not consulted)" 2 "$RC"
{ mrow $((NOW - 1 * DAY)) indeterminate; } > "$ROOT/rows"; CROWS="$ROOT/crow-empty" run; reset_knobs
check "indeterminate-only beside a dead canary: still exit 3 for its own reason" 3 "$RC"; hasnt "indeterminate-only: not blamed on the source" "$OUT" "reader archive arm not live"
# the canary's shape
: > "$ROOT/rows"; run
cargs="$(cat "$ROOT/cargs" 2>/dev/null)"
until_exp="$(date -u -d "@$((NOW - 10800))" '+%Y-%m-%dT%H:%M:%SZ')"
check "the canary asks for the archive-only window (24 h back, ending 3 h ago), one row" "--since 24h --until $until_exp --limit 1" "$cargs"
hasnt "the canary never filters (--grep)" "$cargs" "--grep"
hasnt "the canary never reads the hot-only window (--since 6h)" "$cargs" "--since 6h"
hasnt "the canary never passes --raw-only" "$cargs" "--raw-only"
hasnt "the canary never passes --no-archive (default mode reads hot + archive)" "$cargs" "--no-archive"

# 7d. future-dated measured rows (R1 iii)
mrow $((NOW + 2 * 3600)) ok > "$ROOT/rows"; run
check "a measured row dated 2 h in the future: exit 3" 3 "$RC"; has "future-dated: the fixed reason" "$OUT" "PARSE: future-dated measured row"
mrow $((NOW + 3600 + 1)) ok > "$ROOT/rows"; run
check "a measured row dated 1 h + 1 s in the future: exit 3" 3 "$RC"
mrow $((NOW + 3600)) ok > "$ROOT/rows"; run
check "a measured row dated exactly 1 h in the future (skew): exit 2" 2 "$RC"; has "skew within 1 h counts as age 0" "$OUT" "newest_measured_age_days=0"
mrow $((NOW + 600)) fail_other > "$ROOT/rows"; run
check "a measured row 10 min in the future (skew): exit 2" 2 "$RC"
mrow $((NOW + 3 * 3600)) fail_header > "$ROOT/rows"; run
check "a future-dated FAIL row: exit 3" 3 "$RC"
{ mrow $((NOW - 40 * DAY)) ok; mrow $((NOW + 2 * 3600)) ok; } > "$ROOT/rows"; run
check "a future-dated row cannot mask a dark keeper (old row plus future row): exit 3, not 2" 3 "$RC"
mrow $((NOW + 2 * 3600)) indeterminate > "$ROOT/rows"; run
check "a future-dated INDETERMINATE row is not a measured row: exit 3 for its own reason" 3 "$RC"; hasnt "future indeterminate: not the future-dated reason" "$OUT" "future-dated"

# 8. what the probe asks Better Stack for: hot window + archive arm, 60 days, NOT --raw-only (it drops journald rows)
: > "$ROOT/rows"; run
args="$(cat "$ROOT/args" 2>/dev/null)"
has "queries 60 days" "$args" "--since 60d"
has "greps the marker name" "$args" "--grep $MARKER"
has "bounded limit" "$args" "--limit 5000"
hasnt "never --raw-only (it excludes the journald rows)" "$args" "--raw-only"
hasnt "never --no-archive (the archive arm is what reaches 31 days back)" "$args" "--no-archive"
check "exactly one main read" 1 "$(mcalls)"

# 8b. the reader is FIXED to the sibling script: no environment seam (R6)
: > "$ROOT/rows"; run
check "an exported LUKS_KEEPER_QUERY_SCRIPT is ignored: the evil script is never run" "" "$(cat "$ROOT/evil-called" 2>/dev/null)"
check "an exported LUKS_KEEPER_QUERY_SCRIPT is ignored: the sibling reader answered" 1 "$(mcalls)"
leftover="$(grep -n 'LUKS_KEEPER_QUERY_SCRIPT' "$SUT" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
check "the probe source has no LUKS_KEEPER_QUERY_SCRIPT seam" "" "$leftover"
check "the reader path is fixed to \$SCRIPT_DIR/../betterstack-query.sh" 1 "$(grep -cE '^QUERY="\$SCRIPT_DIR/\.\./betterstack-query\.sh"' "$SUT")"

# 9. read failure: CANNOT ESTABLISH, and the reader's credential-bearing stderr is withheld
mrow $((NOW - 5 * DAY)) ok > "$ROOT/rows"; STUB_RC=7 run; unset STUB_RC
check "reader exits 7: exit 3 (never a verdict from the rows it printed)" 3 "$RC"
hasnt "reader failure: user withheld" "$OUT" "secret-user"; hasnt "reader failure: host withheld" "$OUT" "secret-host"
hasnt "reader failure: canary withheld" "$OUT" "$CAN_STR"
has "reader failure: fixed reason with the exit code" "$OUT" "Better Stack read failed (exit 7)"
for rc in 1 2 3 64 78; do STUB_RC=$rc run; check "reader exits $rc: exit 3" 3 "$RC"; done; unset STUB_RC
: > "$ROOT/rows"; mv "$QUERY_STUB" "$QUERY_STUB.off"; run; mv "$QUERY_STUB.off" "$QUERY_STUB"; reset_knobs
check "reader script missing: exit 3" 3 "$RC"

# 10. credentials: missing in any position is CANNOT ESTABLISH with no reader call
for v in QH QU QP; do
  mrow $((NOW - 5 * DAY)) ok > "$ROOT/rows"; eval "$v=''"; run
  check "empty $v: exit 3" 3 "$RC"; check "empty $v: reader never called" 0 "$(calls)"; reset_knobs
done

# 10b. NOW_EPOCH: a positive decimal without a leading zero (a leading zero is OCTAL inside (( )))
mrow $((NOW - 5 * DAY)) ok > "$ROOT/rows"
for bad_now in 0 017 08 -5 1e9 12x; do
  NOWV="$bad_now" run; reset_knobs
  check "NOW_EPOCH=$bad_now: exit 3" 3 "$RC"; has "NOW_EPOCH=$bad_now: the fixed reason" "$OUT" "unusable NOW_EPOCH"
  check "NOW_EPOCH=$bad_now: reader never called" 0 "$(calls)"
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
echoed="$(grep -nE 'echo[^|]*\$\{?(OUT|CAN)\}?|printf[^|]*\$\{?(OUT|CAN)\}?[^|]*>&2' "$SUT" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
check "no executable line echoes the reader output" "" "$echoed"
direct="$(grep -nE '(^|[^A-Za-z_])curl[[:space:]]|Authorization:|Bearer' "$SUT" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
check "no direct curl and no bearer: the only egress is the pinned reader" "" "$direct"
rawonly="$(grep -nE '^[^#]*--raw-only' "$SUT" 2>/dev/null || true)"
check "the source never passes --raw-only on an executable line" "" "$rawonly"
check "the reader the probe calls bounds its request with --max-time" 1 "$(grep -cE 'curl .*--max-time [0-9]+' "$REPO/scripts/betterstack-query.sh")"

# 12b. the followthrough-convention.md NOTIFY-ONLY rule: refusal first, the rc-remapping EXIT trap directly after it
check "exactly one trap statement" 1 "$(grep -c '^trap ' "$SUT")"
check "no exec / kill on an executable line (either bypasses the EXIT remap)" "" "$(grep -nE '(^|[^A-Za-z_-])(exec|kill)[[:space:]]' "$SUT" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
refusal_start="$(awk '/^case "\$-" in$/ { print NR; exit }' "$SUT")"
refusal_end="$(awk '/^case "\$-" in$/ { s = 1 } s && /^esac$/ { print NR; exit }' "$SUT")"
trap_ln="$(grep -n '^trap ' "$SUT" | head -n 1 | cut -d: -f1)"
has "the xtrace refusal case exits 78" "$(sed -n "${refusal_start:-0},${refusal_end:-0}p" "$SUT")" "exit 78"
check "nothing between the xtrace refusal and the trap (the trap is the next line)" "$(( ${refusal_end:-0} + 1 ))" "${trap_ln:-none}"
first_cred="$(grep -nE 'BETTERSTACK_QUERY_|NOW_EPOCH|betterstack-query' "$SUT" | grep -vE '^[0-9]+:[[:space:]]*#' | head -n 1 | cut -d: -f1)"
check "the xtrace refusal precedes the first credential or reader reference" yes "$([ "${refusal_end:-999999}" -lt "${first_cred:-0}" ] && echo yes || echo no)"

# 12c. the enrollable directive: ONE `<!-- soleur:followthrough ... -->` line in the header
dir_lines="$(grep -E '^#[[:space:]]+<!-- soleur:followthrough ' "$SUT" || true)"
check "the header carries exactly one single-line follow-through directive" 1 "$(printf '%s\n' "$dir_lines" | grep -c .)"
check "the directive names this script, earliest= and secrets= and closes on the same line" 1 "$(printf '%s\n' "$dir_lines" | grep -cE 'script=scripts/followthroughs/inngest-luks-keeper-dark-11265\.sh earliest=[0-9]{4}-[0-9]{2}-[0-9]{2}T00:00:00Z secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->$')"
check "the directive's script exists in the repo" yes "$([ -f "$REPO/scripts/followthroughs/inngest-luks-keeper-dark-11265.sh" ] && echo yes || echo no)"

# 12d. parity with the producer: the marker and the token vocabulary equal the strings in the alert and the flip script
TF_SRC="$(cat "$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf")"
FLIP_SRC="$(cat "$REPO/apps/web-platform/infra/inngest-cutover-flip.sh")"
probe_marker="$(sed -n 's/^readonly MARKER="\(.*\)"  *# \[mut:marker\]$/\1/p' "$SUT")"
check "the probe MARKER is the 30-character producer marker" "$MARKER" "$probe_marker"
has "probe MARKER equals the paging alert's anchored marker in betterstack-logs-alerts.tf" "$TF_SRC" "position(JSONExtractString(raw, 'message'), '$probe_marker') = 1"
has "probe MARKER equals the marker the flip script emits (inngest-cutover-flip.sh)" "$FLIP_SRC" "\"$probe_marker \${row}\""
flip_tokens="$(grep -oE 'luks_probe_finish [a-z_]+ [0-9"$]' "$REPO/apps/web-platform/infra/inngest-cutover-flip.sh" | awk '{print $2}' | sort -u | tr '\n' ' ')"
tf_tokens="$(sed -n 's/^# token in {\(.*\)}, shipped twice.*$/\1/p' "$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf" | tr -d ' ' | tr ',' '\n' | sort -u | tr '\n' ' ')"
check "the flip script emits exactly the vocabulary {ok, fail_passphrase, fail_header, fail_key_absent, indeterminate}" "fail_header fail_key_absent fail_passphrase indeterminate ok " "$flip_tokens"
check "the alert file documents the same token vocabulary as the flip script" "$flip_tokens" "$tf_tokens"
for t in $flip_tokens; do
  mrow $((NOW - 5 * DAY)) "$t" > "$ROOT/rows"; run
  case "$t" in
    indeterminate) check "producer token $t is classified as unmeasured: exit 3, indeterminate=1" "3:yes" "$RC:$(case "$OUT" in *"indeterminate=1"*) echo yes ;; *) echo no ;; esac)" ;;
    *)             check "producer token $t is classified as measured: exit 2, measured=1" "2:yes" "$RC:$(case "$OUT" in *"measured=1 "*) echo yes ;; *) echo no ;; esac)" ;;
  esac
done

# 13. the EXIT trap keeps a stray status inside the vocabulary (a fault injected at the read exits 1 in the body)
cat > "$ROOT/fault.sh" <<'FAULT'
trap 'case "$BASH_COMMAND" in read_rows*) exit 1 ;; esac' DEBUG
FAULT
mrow $((NOW - 5 * DAY)) ok > "$ROOT/rows"; XENV="BASH_ENV=$ROOT/fault.sh" run; reset_knobs
check "an unexpected internal exit status is mapped to 3 by the EXIT trap" 3 "$RC"

# shellcheck disable=SC2034  # read by mh_floor in the sourced lib
FIX_N="$(wc -l < "$LEDGER")"
if run_battery "${1:-}"; then
  echo "=== mutation battery ==="
  export FT_REPO="$REPO"
  MUT="$ROOT/mut"; mkdir -p "$MUT"
  ctl=0; FT_INNER=1 FT_SUT="$SUT" bash "$SELF" >/dev/null 2>&1 || ctl=$?
  check "battery control: the pristine probe passes the inner suite (rc 0)" 0 "$ctl"
  # Scorer controls (#11520): mh_caught decides whether a mutant was caught FOR THE CLAIMED REASON. Each row calls it
  # directly in THIS shell (an ok/bad inside a subshell would lose its PASS/FAIL increment and trip LEDGER MISMATCH) and
  # emits exactly one check. The logs are synthetic, never recorded from a real run.
  printf '  PASS: other\n  FAIL: frag-1 and trailing text\n' > "$MUT/sc-right.log"
  printf '  PASS: frag-1\n'                                > "$MUT/sc-pass-only.log"
  printf '  FAIL: a different row\n'                       > "$MUT/sc-other.log"
  printf 'x  FAIL: frag-1\n'                              > "$MUT/sc-mid.log"
  printf '        FAIL: frag-1\n'                        > "$MUT/sc-indented.log"
  : > "$MUT/sc-empty.log"
  # A missing log would read as "not caught" and let a negative control pass vacuously, so it gets its own answer.
  sc_verdict() { [ -f "$2" ] || { echo missing; return; }; mh_caught "$1" "$2" && echo yes || echo no; }
  check "scorer: a FAIL line starting with the fragment and trailing text is caught" yes "$(sc_verdict frag-1 "$MUT/sc-right.log")"
  # label|fragment|log: every row must come back NOT caught
  sc_no=(
    "a PASS-only log|frag-1|sc-pass-only"
    "a FAIL line for a different row|frag-1|sc-other"
    "an empty log|frag-1|sc-empty"
    "a fragment longer than the FAIL label (strict prefix of the fragment)|frag-1 and trailing text plus more|sc-right"
    "a FAIL quoted mid-line (not at line start)|frag-1|sc-mid"
    "a FAIL on an indented detail line|frag-1|sc-indented"
    "a regex-metacharacter fragment (literal match only)|fr.g-1|sc-right"
    "an empty fragment|-|sc-right"
  )
  for sc_row in "${sc_no[@]}"; do
    IFS='|' read -r sc_lbl sc_frag sc_log <<< "$sc_row"
    [ "$sc_frag" = "-" ] && sc_frag=""
    check "scorer: $sc_lbl is not caught" no "$(sc_verdict "$sc_frag" "$MUT/$sc_log.log")"
  done
  # Teeth: with the scorer overridden to always say yes, EVERY "not caught" control above comes back wrongly caught.
  sc_dead="$( ( mh_caught() { return 0; }; n=0
    for sc_row in "${sc_no[@]}"; do IFS='|' read -r _l sc_frag sc_log <<< "$sc_row"; [ "$sc_frag" = "-" ] && sc_frag=""
      mh_caught "$sc_frag" "$MUT/$sc_log.log" && n=$((n + 1)); done; echo "$n" ) )"
  # The expected count is a literal on purpose: derived from the table it would shrink with it. Update it WITH the table.
  check "scorer teeth: a dead scorer is caught wrongly-yes by all 8 negative controls" 8 "${sc_dead:-0}"
  check "scorer: the negative-control table still has 8 rows" 8 "${#sc_no[@]}"
  # Controls for the lib's fragment-uniqueness scorer, exact mode, mh_selftest_caught and the mh_floor / assert_fixture_dir
  # refusal rows (#11572 items 8, 9, 11): ONE shared definition, scripts/lib/mutation-harness-controls.sh. Called after FIX_N is
  # taken, so every row counts toward MIN_BATTERY.
  mh_lib_controls
  mutate_helper h1-check-always-ok     check  'check() { ok "$1"; }'
  mutate_helper h2-has-always-ok       has    'has() { ok "$1"; }'
  mutate_helper h3-hasnt-always-ok     hasnt  'hasnt() { ok "$1"; }'
  mutate_helper h4-check-always-bad    check  'check() { bad "$1"; }'
  mutate_helper h5-has-inverted        has    'has() { case "$2" in *"$3"*) bad "$1" ;; *) ok "$1" ;; esac; }'
  mutate_sub m1-action-exit-0          '[mut:action]'      'exit 5'  'exit 0' 'newest measured row exactly 30 days old: exit 5'
  mutate_run m2-read-fail-falls-through '[mut:read-fail]'  '  if (( RC != 0 )); then OUT=""; return 0; fi' 'reader exits 7: exit 3'
  mutate_run m2b-trap-removed          '[mut:trap]'        ':' 'an unexpected internal exit status is mapped to 3 by the EXIT trap'
  mutate_sub m2c-statement-before-trap '[mut:trap]'        'trap ' $'FOO=1\ntrap ' 'nothing between the xtrace refusal and the trap'
  mutate_sub m2d-second-trap           '[mut:trap]'        '# [mut:trap]' $'# [mut:trap]\ntrap - EXIT' 'exactly one trap statement'
  mutate_run m4-xtrace-refusal-dropped '[mut:xtrace]'      '  *x*) : ;;' 'xtrace with credentials: exit 78'
  mutate_run m5a-reader-output-echoed  '[mut:read-fail]'   '  if (( RC != 0 )); then echo "$OUT"; cannot "Better Stack read failed (exit ${RC})"; fi' 'no executable line echoes the reader output'
  mutate_sub m5b-anchor-dropped        '[mut:anchor]'      'startswith' 'contains' 'quoting rows only (marker not at position 1): exit 2, not counted'
  mutate_sub m5c-indeterminate-counts-as-measured '[mut:classify]' '$3=="ok"||$3 ~' '$3=="ok"||$3=="indeterminate"||$3 ~' 'indeterminate-only history: exit 3'
  mutate_sub m5d-threshold-off-by-one  '[mut:threshold]'   '>= DARK_SECS' '> DARK_SECS' 'newest measured row exactly 30 days old: exit 5'
  mutate_run m5e-indeterminate-only-is-not-yet '[mut:indet]' '  { echo "NOT YET: indeterminate only"; exit 2; }' 'indeterminate-only history: exit 3'
  mutate_run m5f-shape-drift-ignored   '[mut:drift]'       'if false; then' 'an object whose raw does not decode, and no producer row: exit 3 (shape drift)'
  mutate_run m5g-bad-token-ignored     '[mut:badtoken]'    ':' 'an anchored row with an unrecognised token: exit 3'
  mutate_run m5h-missing-cred-still-reads '[mut:cred-check]' ':' 'empty QH: reader never called'
  mutate_sub m5i-window-30-to-31-days  '[mut:window]'      '30 * 86400' '31 * 86400' 'newest measured row exactly 30 days old: exit 5'
  mutate_run m6a-object-check-dropped  '[mut:object-check]' ':' 'an HTML 502 body with exit 0: exit 3'
  mutate_run m6b-future-check-dropped  '[mut:future]'      ':' 'a measured row dated 2 h in the future: exit 3'
  mutate_sub m6c-future-tolerance-off-by-one '[mut:classify]' 'now+3600' 'now+3599' 'a measured row dated exactly 1 h in the future (skew): exit 2'
  mutate_run m6d-canary-dropped        '[mut:canary]'      ':' 'empty body and an EMPTY canary: exit 3 (a dead source is not '"'"'no keeper rows'"'"')'
  mutate_run m6e-canary-rc-ignored     '[mut:canary-rc]'   ':' 'empty body and a canary that exits 7: exit 3'
  mutate_run m6f-canary-shape-ignored  '[mut:canary-shape]' ':' 'empty body and an HTML canary: exit 3'
  mutate_sub m6g-canary-filters        'CAN="$(bash "$QUERY"' '--limit 1' '--limit 1 --raw-only' 'the canary asks for the archive-only window (24 h back, ending 3 h ago), one row'
  mutate_sub m6g2-canary-until-dropped 'CAN="$(bash "$QUERY"' ' --until "$until_iso"' '' 'empty body and a canary holding only a 60 s old (hot-window) row: exit 3'
  mutate_sub m6g3-canary-hot-window    'CAN="$(bash "$QUERY"' '--since 24h' '--since 6h' 'the canary never reads the hot-only window (--since 6h)'
  mutate_sub m6k-canary-shape-object-only 'if type == "object" then ((.dt | type)' 'if type == "object" then ((.dt | type) == "string" and (.raw | type) == "string") else false end' 'type == "object"' 'empty body and an exception-object-only canary: exit 3'
  mutate_sub m6l-tie-rule-dropped      '[mut:classify]'    ' else if($2+0==n && k=="fail"){c="fail"}' '' 'two measured rows in the same second: the class is fail (conservative)'
  mutate_sub m6m-tie-last-row-wins     '[mut:classify]'    'else if($2+0==n && k=="fail"){c="fail"}' 'else if($2+0==n){c=k}' 'two measured rows in the same second, fail listed first: the class is fail'
  mutate_sub m6n-epoch-zero-accepted   '[mut:classify]'    '$2=="-" || $2+0<=0' '$2=="-"' 'a sole measured row dated at the epoch: exit 3, not a 20717-day age'
  mutate_sub m6o-object-shape-dropped  'then "X\t-\t-"'    ' or (($r.dt | type) != "string") or (($r.raw | type) != "string")' '' 'an old measured row plus an exception-object tail: exit 3, never a false ACTION REQUIRED'
  mutate_sub m6o2-dt-clause-dropped    'then "X\t-\t-"'    ' or (($r.dt | type) != "string")' '' 'an object with a raw but no dt beside a valid row: exit 3'
  mutate_sub m6o3-raw-clause-dropped   'then "X\t-\t-"'    ' or (($r.raw | type) != "string")' '' 'an object with a dt but no raw beside a valid row: exit 3'
  mutate_sub m6p-now-epoch-octal-regex 'unusable NOW_EPOCH' '^[1-9][0-9]{0,15}$' '^[0-9]+$' 'NOW_EPOCH=017: the fixed reason'
  mutate_sub m6q-fail-note-dropped     'The newest measured row is a FAILED verdict' 'a resolved page is not recovery' 'a note' 'NOT YET after a fail row: a resolved page is not recovery'
  mutate_sub m6h-token-class-hardcoded '[mut:tokclass]'    'newest_measured_token=${NEWCLS}' 'newest_measured_token=ok' 'fail-then-dark: the newest measured token class is fail'
  mutate_sub m6i-env-seam-reintroduced '[mut:query-path]'  'QUERY="$SCRIPT_DIR/../betterstack-query.sh"' 'QUERY="${LUKS_KEEPER_QUERY_SCRIPT:-$SCRIPT_DIR/../betterstack-query.sh}"' 'an exported LUKS_KEEPER_QUERY_SCRIPT is ignored: the evil script is never run'
  mutate_sub m6j-marker-typo           '[mut:marker]'      'KEY_PROBE' 'KEY_PR0BE' 'probe MARKER equals the paging alert'"'"'s anchored marker in betterstack-logs-alerts.tf'
  mutate_sub m7a-directive-bare-form   '<!-- soleur:followthrough script=' '<!-- soleur:followthrough' 'soleur:followthrough' 'the header carries exactly one single-line follow-through directive'
  mutate_sub m7b-directive-unclosed    '<!-- soleur:followthrough script=' ' -->' '' 'the directive names this script, earliest= and secrets= and closes on the same line'
fi

# Floors: MIN_FIXTURE is the real fixture-row count (an --no-battery run reaches it exactly); MIN_BATTERY the battery's.
MIN_FIXTURE=189; MIN_BATTERY=101
LEDGER_N="$(wc -l < "$LEDGER")"
echo; echo "=== inngest-luks-keeper-dark-11265.sh: $PASS passed, $FAIL failed ($LEDGER_N recorded) ==="
if [ "$LEDGER_N" -ne $((PASS + FAIL)) ]; then printf 'LEDGER MISMATCH\n'; exit 1; fi
mh_floor "$MIN_FIXTURE" "$MIN_BATTERY" "${1:-}"
[ "$FAIL" -eq 0 ]
