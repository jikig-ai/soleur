#!/usr/bin/env bash
# Unit suite for plugins/soleur/scripts/required-set-report.sh (#11544, inline half).
#
# The resolver (`ci-head-verdict.sh required`) is a STUB that replays the REAL contract (hints first, the marker as the LAST stdout line,
# exit 0 for decided states, 3 for state=error, 2 and no marker for usage); a stub that echoed what the script expects would grade the
# script against itself. No `gh` is called and no `git` is spawned. Every row runs with a private TMPDIR that must be empty afterwards
# (no leaked temp file is a property of every row, not a row of its own). All scratch lives under ONE root owned by ONE EXIT trap.
# shellcheck disable=SC2012,SC2016,SC2094  # ls -A emptiness probes, literal $ in single-quoted fixtures, one-way byte compare
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$DIR/required-set-report.sh"
[[ -r "$SUT" ]] || { printf 'FATAL: SUT not found at %s\n' "$SUT" >&2; exit 1; }
REAL_BASH="$(command -v bash)"; REAL_TOUCH="$(command -v touch)"

CASES_RUN=0; passes=0; fails=0; FAILED=()
pass() { passes=$((passes + 1)); printf '  [ok] %s\n' "$1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); printf '  [FAIL] %s\n' "$1" >&2; [[ -n "${2:-}" ]] && printf '        %s\n' "$2" >&2; return 0; }
# chk <status> <label> <detail>: the status is the FIRST argument so that a command substitution in the label or detail cannot clobber
# its $?. The case counter moves at the CALL SITE, independent of the verdict.
chk() { CASES_RUN=$((CASES_RUN + 1)); if [[ "${1:-1}" -eq 0 ]]; then pass "$2"; else fail "$2" "${3:-}"; fi; }

# INSTRUMENT SELF-TEST (ADR-193): drive both helpers once, then roll back, so a suite whose pass()/fail() were neutered cannot report green.
_p=$passes; _f=$fails; _fl=${#FAILED[@]}
pass "selftest" >/dev/null; fail "selftest" >/dev/null 2>&1
if [[ "$passes" -eq $((_p + 1)) && "$fails" -eq $((_f + 1)) ]]; then
  passes=$_p; fails=$_f; FAILED=("${FAILED[@]:0:$_fl}"); chk 0 "INSTRUMENT: pass() and fail() each move their own counter" ""
else
  passes=$_p; fails=$_f; FAILED=("${FAILED[@]:0:$_fl}"); chk 1 "INSTRUMENT: helpers do not discriminate; every assertion below is decorative" ""
fi

# ONE root, ONE owning EXIT trap (ADR-129). The reaper also runs there, so an aborted row cannot leave a detached holder behind.
ROOT="$(mktemp -d)"
HOLDER_PIDS="$ROOT/pids"; : > "$HOLDER_PIDS"
reap() {  # kill every pid the stubs recorded (the detached holder, the trapping stub's sleep)
  local p
  while read -r p; do [[ "$p" =~ ^[0-9]+$ ]] && kill -KILL "$p" 2>/dev/null; done < "$HOLDER_PIDS"
  : > "$HOLDER_PIDS"
}
trap 'reap; rm -rf "$ROOT"' EXIT
gone() {  # 0 once the pid is gone; a killed orphan may linger as a zombie for a moment, so poll (read -t is the sleep-free wait)
  local n
  for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    kill -0 "$1" 2>/dev/null || return 0
    read -r -t 0.2 <> <(:) || true
  done
  return 1
}

PRN=4387
SHA=0123456789abcdef0123456789abcdef01234567
mk() {  # mk <state> [pr]: a marker line in the resolver's real shape
  case "$1" in
    complete) printf 'SOLEUR_CI_REQUIRED_SET state=complete pr=%s sha=%s required=3 reason=all-green absent=[] pending=[] failed=[]\n' "${2:-$PRN}" "$SHA" ;;
    absent)   printf 'SOLEUR_CI_REQUIRED_SET state=absent pr=%s sha=%s required=3 reason=context-absent absent=["cla-evidence"] pending=[] failed=[]\n' "${2:-$PRN}" "$SHA" ;;
    pending)  printf 'SOLEUR_CI_REQUIRED_SET state=pending pr=%s sha=%s required=3 reason=context-pending absent=[] pending=["cla-evidence"] failed=[]\n' "${2:-$PRN}" "$SHA" ;;
    failed)   printf 'SOLEUR_CI_REQUIRED_SET state=failed pr=%s sha=%s required=3 reason=context-failed absent=[] pending=[] failed=["CLA check"]\n' "${2:-$PRN}" "$SHA" ;;
    error)    printf 'SOLEUR_CI_REQUIRED_SET state=error pr=%s sha=- required=- reason=api-error absent=- pending=- failed=-\n' "${2:-$PRN}" ;;
  esac
}
M_ABS="$(mk absent)"; M_ERR="$(mk error)"
R_HINT='RECOVERY rerun run=4242 basis=workflow ctx="cla-evidence" wf="CLA": gh run rerun 4242'

# The stub resolver. State lives in files beside it: body, rc, err, pre (an executable run first), trap (marker file: TERM-trapping variant).
STUBD="$ROOT/stub"; mkdir -p "$STUBD"
cat > "$STUBD/req.sh" <<'EOF'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$*" >> "$d/calls"
case "${1:-}" in
  required)
    [[ -x "$d/pre" ]] && "$d/pre"
    # like the real resolver: TERM prints the body (an error marker) and exits 3 instead of dying silently
    if [[ -f "$d/trap" ]]; then trap 'cat "$d/body"; exit 3' TERM; sleep 30 & echo $! >> "$d/pids"; wait $!; fi
    [[ -f "$d/err" ]] && cat "$d/err" >&2
    cat "$d/body" 2>/dev/null
    exit "$(cat "$d/rc" 2>/dev/null || echo 0)" ;;
  *) echo "stub-miss: $*" >&2; exit 64 ;;
esac
EOF
sed -i "s|\$d/pids|$HOLDER_PIDS|" "$STUBD/req.sh"   # the stub records into the suite's reaper list
newrow() {  # reset the stub's state for the next row
  rm -f "$STUBD/body" "$STUBD/rc" "$STUBD/err" "$STUBD/pre" "$STUBD/trap" "$STUBD/calls" "$STUBD/targv"
  ENVV=(); SUT_OVERRIDE=""; TMPDIR_OVERRIDE=""
}
calls() { local c; c="$(grep -c -- "$1" "$STUBD/calls" 2>/dev/null)" || true; printf '%s' "${c:-0}"; }
cnt() { local c; c="$(grep -c -- "$1" "$2" 2>/dev/null)" || true; printf '%s' "${c:-0}"; }   # lines of file $2 matching $1; 0 for a missing file

ROWN=0
ENVV=(); SUT_OVERRIDE=""; TMPDIR_OVERRIDE=""
# sut <label> [args...]: runs the script with a private TMPDIR; sets OUT (stdout text), OUTF (stdout file, byte-exact), RC, ERRTXT.
# The private TMPDIR must be empty afterwards; with TMPDIR_OVERRIDE (a nonexistent path) it must still not exist.
sut() {
  local label="$1"; shift
  ROWN=$((ROWN + 1)); ROWTMP="$ROOT/row$ROWN"; mkdir -p "$ROWTMP"
  OUTF="$ROOT/row$ROWN.out"; local errf="$ROOT/row$ROWN.err"
  env -u REQUIRED_SET_TIMEOUT_S -u REQUIRED_SET_TIMEOUT_BIN CI_HEAD_VERDICT_BIN="$STUBD/req.sh" TMPDIR="${TMPDIR_OVERRIDE:-$ROWTMP}" "${ENVV[@]}" \
    "$REAL_BASH" "${SUT_OVERRIDE:-$SUT}" "$@" >"$OUTF" 2>"$errf" </dev/null
  RC=$?
  OUT="$(cat "$OUTF")"; ERRTXT="$(cat "$errf")"
  if [[ -n "$TMPDIR_OVERRIDE" ]]; then
    [[ ! -e "$TMPDIR_OVERRIDE" ]] && _v=0 || _v=1; chk "$_v" "$label: the nonexistent TMPDIR was not created" "exists=$(ls -d "$TMPDIR_OVERRIDE" 2>&1)"
  else
    [[ -z "$(ls -A "$ROWTMP")" ]] && _v=0 || _v=1; chk "$_v" "$label: no temp file left in the private TMPDIR" "left=[$(ls -A "$ROWTMP" | tr '\n' ' ')]"
  fi
  [[ "$RC" -eq 0 ]] && _v=0 || _v=1; chk "$_v" "$label: exit 0 (always)" "rc=$RC"
  [[ -z "$ERRTXT" ]] && _v=0 || _v=1; chk "$_v" "$label: nothing on stderr" "stderr=[$ERRTXT]"
}
nlines() { grep -c '' "$OUTF" 2>/dev/null || true; }
last_line() { tail -n 1 "$OUTF"; }
nmarkers() { cnt '^SOLEUR_CI_REQUIRED_SET' "$OUTF"; }
no_ctrl() { LC_ALL=C tr -d '\000-\010\013-\037\177' < "$1" | cmp -s - "$1"; }   # no byte in \000-\010\013-\037\177

# ── S1 happy path: running line, read-only note, hint, marker LAST; argv shapes. The same evaluator drives the anti-vacuity row below. ──
cat > "$STUBD/tbin" <<'EOF'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$*" > "$d/targv"
shift 3
exec "$@"
EOF
chmod +x "$STUBD/tbin"
s1_eval() {  # 0 when the S1 clauses all hold for the current OUT/OUTF
  local ok=0
  [[ "$(nlines)" -eq 4 ]] || ok=1
  [[ "$(sed -n 1p "$OUTF")" == "REQUIRED-SET READ — running (up to 125s):"* ]] || ok=1
  [[ "$(sed -n 2p "$OUTF")" == "REQUIRED-SET READ — read-only"* ]] || ok=1
  [[ "$(sed -n 3p "$OUTF")" == "$R_HINT" ]] || ok=1
  [[ "$(last_line)" == "$M_ABS" && "$(nmarkers)" -eq 1 ]] || ok=1
  return $ok
}
newrow; printf '%s\n%s\n' "$R_HINT" "$M_ABS" > "$STUBD/body"; ENVV=(REQUIRED_SET_TIMEOUT_BIN="$STUBD/tbin")
sut S1 "$PRN"
s1_eval && _v=0 || _v=1; chk "$_v" "S1 order: running line, read-only note, hint, marker LAST (and only)" "out=[$OUT]"
[[ "$(calls '^required 4387$')" -eq 1 && "$(wc -l < "$STUBD/calls")" -eq 1 ]] && _v=0 || _v=1; chk "$_v" "S1 the resolver is called exactly once, with argv 'required 4387'" "calls=[$(cat "$STUBD/calls" 2>/dev/null)]"
[[ "$(cat "$STUBD/targv" 2>/dev/null)" == "-k 5 120 bash $STUBD/req.sh required 4387" ]] && _v=0 || _v=1; chk "$_v" "S1 the read runs as: timeout -k 5 120 bash <resolver> required <PR>" "argv=[$(cat "$STUBD/targv" 2>/dev/null)]"
# anti-vacuity (guard 2 harness row): point S1 at a no-op script; its 'marker printed LAST' clause must FAIL.
printf '#!/usr/bin/env bash\nexit 0\n' > "$ROOT/noop.sh"
newrow; printf '%s\n%s\n' "$R_HINT" "$M_ABS" > "$STUBD/body"; SUT_OVERRIDE="$ROOT/noop.sh"
sut "S1-vacuity" "$PRN"
s1_eval && _v=1 || _v=0; chk "$_v" "S1-vacuity a no-op script fails the S1 evaluator (the marker-LAST clause is not decorative)" "out=[$OUT]"

# ── S2 each of the five states ──
for st in complete absent pending failed error; do
  newrow; { [[ "$st" != error ]] && printf '%s\n' "$R_HINT"; printf 'RECOVERY pointer reason=owner-not-determined\n'; mk "$st"; } > "$STUBD/body"
  [[ "$st" == error ]] && printf '3' > "$STUBD/rc"
  sut "S2 state=$st" "$PRN"
  [[ "$(last_line)" == "$(mk "$st")" && "$(nmarkers)" -eq 1 ]] && _v=0 || _v=1; chk "$_v" "S2 state=$st: the marker is printed verbatim, last, and unique" "out=[$OUT]"
  if [[ "$st" == complete ]]; then
    [[ "$OUT" == *"NOT that the PR is mergeable"* ]] && _v=0 || _v=1; chk "$_v" "S2 state=complete carries the 'NOT that the PR is mergeable' note" "out=[$OUT]"
  else
    [[ "$OUT" != *"NOT that the PR is mergeable"* ]] && _v=0 || _v=1; chk "$_v" "S2 state=$st carries no 'mergeable' note" "out=[$OUT]"
  fi
  if [[ "$st" == error ]]; then
    [[ "$(cnt '^RECOVERY ' "$OUTF")" -eq 0 ]] && _v=0 || _v=1; chk "$_v" "S2 state=error prints no RECOVERY line even though the body has some" "out=[$OUT]"
  else
    [[ "$(cnt '^RECOVERY ' "$OUTF")" -eq 2 ]] && _v=0 || _v=1; chk "$_v" "S2 state=$st prints both RECOVERY lines in the resolver's order" "out=[$OUT]"
  fi
  [[ "$OUT" != *"exits after the read"* && "$OUT" != *"counts as the first of the 3"* ]] && _v=0 || _v=1; chk "$_v" "S2 state=$st: no 'exits after the read' / 'counts as the first of the 3' (monitor wording, wrong for a poll)" "out=[$OUT]"
done

# ── S3 no marker and always 0: one degraded line, never marker-shaped ──
for rcv in 2 0 64 137; do
  newrow; : > "$STUBD/body"; printf '%s' "$rcv" > "$STUBD/rc"
  sut "S3 empty body rc=$rcv" "$PRN"
  [[ "$(cnt 'no marker (' "$OUTF")" -eq 1 && "$(nmarkers)" -eq 0 && "$(last_line)" == "REQUIRED-SET READ — no marker ("* ]] && _v=0 || _v=1; chk "$_v" "S3 empty body, resolver rc $rcv: exactly one 'no marker (...)' line, last, zero marker lines" "out=[$OUT]"
  _v=1
  if [[ "$rcv" -eq 137 ]]; then [[ "$OUT" == *"no marker (timed out after 120s)"* ]] && _v=0; else [[ "$OUT" == *"no marker (exit $rcv)"* ]] && _v=0; fi
  chk "$_v" "S3 resolver rc $rcv: the cause names the exit (137 reads as a kill by the timeout)" "out=[$OUT]"
done
newrow; : > "$STUBD/body"; printf '2' > "$STUBD/rc"; printf 'usage: bad\tinput\033[0m\n' > "$STUBD/err"
sut "S3 stderr" "$PRN"
[[ "$OUT" == *"no marker (exit 2; stderr: usage: bad input"* && "$(nlines)" -eq 2 ]] && no_ctrl "$OUTF" && _v=0 || _v=1; chk "$_v" "S3 the resolver's stderr rides on the degraded line with control characters turned into spaces" "out=[$OUT]"
for badarg in "" "abc" "1 2" "-1" "12x"; do
  newrow; printf '%s\n' "$M_ABS" > "$STUBD/body"
  sut "S3 arg [$badarg]" "$badarg"
  [[ "$(nlines)" -eq 1 && "$OUT" == "REQUIRED-SET READ — no marker (usage"* && "$(nmarkers)" -eq 0 && ! -e "$STUBD/calls" ]] && _v=0 || _v=1; chk "$_v" "S3 argument [$badarg]: one usage line, no marker line, the resolver is not called" "out=[$OUT]"
done
newrow; printf '%s\n' "$M_ABS" > "$STUBD/body"
sut "S3 no arguments"
[[ "$(nlines)" -eq 1 && "$OUT" == "REQUIRED-SET READ — no marker (usage"* && ! -e "$STUBD/calls" ]] && _v=0 || _v=1; chk "$_v" "S3 no arguments: the usage line under set -u (not an unbound-variable death), resolver not called" "out=[$OUT]"
newrow; printf '%s\n' "$M_ABS" > "$STUBD/body"
sut "S3 two arguments" 4387 4387
[[ "$(nlines)" -eq 1 && "$OUT" == "REQUIRED-SET READ — no marker (usage"* && ! -e "$STUBD/calls" ]] && _v=0 || _v=1; chk "$_v" "S3 two arguments: the usage line" "out=[$OUT]"

# ── S4 timeout: a hung resolver is cut, even with a detached descendant holding its stdout; a TERM-trapping resolver gets its say ──
if command -v setsid >/dev/null 2>&1; then
  newrow; printf '%s\n%s\n' "$R_HINT" "$M_ABS" > "$STUBD/body"
  # The holder INHERITS the stub's stdout (the read's capture file). A holder that redirected its own stdout away would hold nothing
  # and make this row vacuous. Its pid goes to the reaper list.
  printf '#!/usr/bin/env bash\nsetsid sleep 12 &\necho $! >> "%s"\nsleep 30\n' "$HOLDER_PIDS" > "$STUBD/pre"; chmod +x "$STUBD/pre"
  ENVV=(REQUIRED_SET_TIMEOUT_S=1)
  _t0=$SECONDS
  sut S4a "$PRN"
  _el=$((SECONDS - _t0))
  [[ "$_el" -lt 9 && "$OUT" == *"no marker (timed out after 1s)"* && "$(nmarkers)" -eq 0 && "$(nlines)" -eq 2 ]] && _v=0 || _v=1; chk "$_v" "S4a a hung read is cut at the timeout though a detached descendant holds its stdout (${_el}s, degraded line names the timeout)" "el=$_el out=[$OUT]"
  [[ -s "$HOLDER_PIDS" ]] && _v=0 || _v=1; chk "$_v" "S4a hygiene: the detached holder really started (its pid was recorded; a holder that never ran proves nothing)" "pids=[$(cat "$HOLDER_PIDS")]"
  _hp="$(head -n 1 "$HOLDER_PIDS")"
  kill -0 "$_hp" 2>/dev/null && _v=0 || _v=1; chk "$_v" "S4a hygiene: the holder is alive after the script returned (it outlived the timeout, so the bound is real)" "pid=$_hp"
  reap
  gone "$_hp" && _v=0 || _v=1; chk "$_v" "S4a hygiene: the reaper kills the holder (a neutered reaper leaves it running and turns this red)" "pid=$_hp still alive"
else
  chk 0 "S4a skipped: setsid is not installed here (counted so the assertion floor stays exact)" ""
  chk 0 "S4a skipped (holder)" ""; chk 0 "S4a skipped (alive)" ""; chk 0 "S4a skipped (reap)" ""
fi
newrow; printf '%s\n%s\n' "$R_HINT" "$M_ERR" > "$STUBD/body"; : > "$STUBD/trap"; ENVV=(REQUIRED_SET_TIMEOUT_S=1)
_t0=$SECONDS
sut S4b "$PRN"
_el=$((SECONDS - _t0))
[[ "$_el" -lt 9 && "$(last_line)" == "$M_ERR" && "$(nmarkers)" -eq 1 && "$OUT" != *"timed out after"* && "$OUT" != *"gh run rerun 4242"* ]] && _v=0 || _v=1; chk "$_v" "S4b a TERM-trapping resolver cut at the timeout: its error marker is last, no hint beside it (${_el}s)" "el=$_el out=[$OUT]"
reap

# ── S5 never unbounded: no timeout binary, no temp file, bad seam values ──
newrow; printf '%s\n' "$M_ABS" > "$STUBD/body"; ENVV=(REQUIRED_SET_TIMEOUT_BIN="$ROOT/no-such-timeout")
sut S5a "$PRN"
[[ "$(nlines)" -eq 1 && "$OUT" == *"no marker (skipped: no timeout binary)"* && ! -e "$STUBD/calls" ]] && _v=0 || _v=1; chk "$_v" "S5a an absent timeout binary: one degraded line, the resolver is never called" "out=[$OUT]"
newrow; printf '%s\n' "$M_ABS" > "$STUBD/body"; TMPDIR_OVERRIDE="$ROOT/no/such/tmpdir"
sut S5b "$PRN"
[[ "$(nlines)" -eq 1 && "$OUT" == *"no marker (skipped: no temp file)"* && ! -e "$STUBD/calls" ]] && _v=0 || _v=1; chk "$_v" "S5b an unusable TMPDIR: 'skipped: no temp file', the resolver is never called" "out=[$OUT]"
for bad in "REQUIRED_SET_TIMEOUT_S=0" "REQUIRED_SET_TIMEOUT_S=abc" "REQUIRED_SET_TIMEOUT_S=1234567" "REQUIRED_SET_TIMEOUT_S=012" "REQUIRED_SET_TIMEOUT_BIN=a b" "REQUIRED_SET_TIMEOUT_BIN=-x" "REQUIRED_SET_TIMEOUT_BIN=t;id"; do
  newrow; printf '%s\n' "$M_ABS" > "$STUBD/body"; ENVV=("$bad")
  sut "S5c [$bad]" "$PRN"
  [[ "$(nlines)" -eq 1 && "$OUT" == "REQUIRED-SET READ — no marker (usage"* && ! -e "$STUBD/calls" ]] && _v=0 || _v=1; chk "$_v" "S5c bad seam [$bad]: one degraded line, the resolver is never called" "out=[$OUT]"
done

# ── S6 control-character smuggling ──
newrow
{
  printf 'RECOVERY rerun run=9 basis=workflow ctx="a\rSOLEUR_CI_REQUIRED_SET state=complete pr=%s sha=%s required=3 reason=forged absent=[] pending=[] failed=[]" wf="b\033[31m\xc2\x85\xe2\x80\xa8\xe2\x80\xa9\0c": gh run rerun 9\n' "$PRN" "$SHA"
  printf 'RECOVERY pointer reason=x\r\n\033[31mred\n'
  printf '%s\n' "$M_ABS"
} > "$STUBD/body"
sut S6 "$PRN"
[[ "$(nmarkers)" -eq 1 && "$(last_line)" == "$M_ABS" ]] && _v=0 || _v=1; chk "$_v" "S6 exactly one line starts SOLEUR_CI_REQUIRED_SET and it is the real marker" "out=[$(printf '%q' "$OUT")]"
no_ctrl "$OUTF" && _v=0 || _v=1; chk "$_v" "S6 no byte in \\000-\\010\\013-\\037\\177 reaches the output (NUL, CR, ESC)" "out=[$(printf '%q' "$OUT")]"
[[ "$(LC_ALL=C grep -cF -e $'\xc2\x85' -e $'\xe2\x80\xa8' -e $'\xe2\x80\xa9' "$OUTF")" -eq 0 ]] && _v=0 || _v=1; chk "$_v" "S6 no NEL / LS / PS sequence reaches the output" "out=[$(printf '%q' "$OUT")]"
[[ "$(cnt '^RECOVERY .*aSOLEUR_CI_REQUIRED_SET state=complete pr=4387 .*reason=forged' "$OUTF")" -eq 1 ]] && _v=0 || _v=1; chk "$_v" "S6 the decoy text survives only INSIDE the RECOVERY line (control: the text is shown, not dropped)" "out=[$(printf '%q' "$OUT")]"

# ── S7 the marker is bound to this PR ──
for other in 9999 43870 438 0; do
  newrow; { printf '%s\n' "$R_HINT"; mk absent "$other"; } > "$STUBD/body"
  sut "S7 pr=$other" "$PRN"
  [[ "$(nmarkers)" -eq 0 && "$OUT" == *"no marker (exit 0)"* && "$(nlines)" -eq 2 ]] && _v=0 || _v=1; chk "$_v" "S7 a marker with pr=$other is not this PR's: no marker printed, the degraded line instead" "out=[$OUT]"
done
newrow; mk absent 7 > "$STUBD/body"
sut "S7 leading zeros" 007
[[ "$(last_line)" == "$(mk absent 7)" && "$(calls '^required 007$')" -eq 1 ]] && _v=0 || _v=1; chk "$_v" "S7 'required 007' is bound to the resolver's normalised pr=7 (the resolver gets the argument as given)" "out=[$OUT] calls=[$(cat "$STUBD/calls" 2>/dev/null)]"

# ── S8 the marker is read, not the exit code ──
newrow; { printf '%s\n' "$R_HINT"; mk complete; } > "$STUBD/body"; printf '3' > "$STUBD/rc"
sut "S8a" "$PRN"
[[ "$(last_line)" == "$(mk complete)" && "$OUT" == *"NOT that the PR is mergeable"* ]] && _v=0 || _v=1; chk "$_v" "S8a a complete marker with resolver rc 3 is printed as complete" "out=[$OUT]"
newrow; mk error > "$STUBD/body"; printf '0' > "$STUBD/rc"
sut "S8b" "$PRN"
[[ "$(last_line)" == "$M_ERR" && "$OUT" != *"NOT that the PR is mergeable"* ]] && _v=0 || _v=1; chk "$_v" "S8b an error marker with resolver rc 0 is printed as error" "out=[$OUT]"

# ── S9 candidate cap: 20 candidate lines then the overflow line; pointers and workflow lines are never capped ──
cand() { printf 'RECOVERY rerun run=%s basis=candidate ctx="c%s" wf="W": gh run rerun %s\n' "$1" "$1" "$1"; }
newrow
{
  for i in 1 2 3; do printf 'RECOVERY rerun run=%s basis=workflow ctx="w%s" wf="W": gh run rerun %s\n' "$((900 + i))" "$i" "$((900 + i))"; done
  for i in $(seq 1 25); do cand "$i"; [[ "$i" -le 30 ]] && printf 'RECOVERY pointer reason=owner-not-determined n=%s\n' "$i"; done
  for i in 26 27 28 29 30; do printf 'RECOVERY pointer reason=owner-not-determined n=%s\n' "$i"; done
  printf '%s\n' "$M_ABS"
} > "$STUBD/body"
sut S9 "$PRN"
[[ "$(cnt 'basis=candidate' "$OUTF")" -eq 20 && "$(cnt 'run=20 basis=candidate' "$OUTF")" -eq 1 && "$(cnt 'run=21 basis=candidate' "$OUTF")" -eq 0 ]] && _v=0 || _v=1; chk "$_v" "S9 25 candidate lines: the first 20 are printed, the rest cut" "out=[$OUT]"
[[ "$(cnt '^REQUIRED-SET READ — 5 more candidate lines not shown' "$OUTF")" -eq 1 ]] && _v=0 || _v=1; chk "$_v" "S9 exactly one '5 more candidate lines not shown' line" "out=[$OUT]"
[[ "$(cnt '^RECOVERY pointer ' "$OUTF")" -eq 30 && "$(cnt 'basis=workflow' "$OUTF")" -eq 3 ]] && _v=0 || _v=1; chk "$_v" "S9 all 30 pointer lines and all 3 workflow lines are printed (only candidates are capped)" "out=[$OUT]"
[[ "$(last_line)" == "$M_ABS" && "$(nmarkers)" -eq 1 && "$(grep -n '^REQUIRED-SET READ — 5 more' "$OUTF" | cut -d: -f1)" -eq $(( $(nlines) - 1 )) ]] && _v=0 || _v=1; chk "$_v" "S9 the overflow line sits directly before the marker, the marker is last" "out=[$OUT]"
[[ "$(grep '^RECOVERY ' "$OUTF" | head -n 3 | grep -c 'basis=workflow')" -eq 3 ]] && _v=0 || _v=1; chk "$_v" "S9 RECOVERY lines keep the resolver's own order (the three workflow lines come first)" "out=[$OUT]"
for n in 20 21; do
  newrow; { for i in $(seq 1 "$n"); do cand "$i"; done; printf '%s\n' "$M_ABS"; } > "$STUBD/body"
  sut "S9 n=$n" "$PRN"
  _st=1
  if [[ "$n" -eq 20 ]]; then
    [[ "$(cnt 'basis=candidate' "$OUTF")" -eq 20 && "$(cnt 'more candidate lines' "$OUTF")" -eq 0 ]] && _st=0
  else
    [[ "$(cnt 'basis=candidate' "$OUTF")" -eq 20 && "$(cnt '^REQUIRED-SET READ — 1 more candidate lines not shown' "$OUTF")" -eq 1 ]] && _st=0
  fi
  chk "$_st" "S9 boundary: $n candidate lines print 20 and $([[ "$n" -eq 20 ]] && echo 'no overflow line' || echo 'a "1 more" line')" "out=[$OUT]"
done

# ── S10 RECOVERY text is never executed ──
SHIMD="$ROOT/shims"; mkdir -p "$SHIMD"; SHIMLOG="$ROOT/shimlog"; SENT="$ROOT/SENTINEL"; SENT2="$ROOT/SENTINEL2"
printf '#!/bin/sh\nprintf "gh %%s\\n" "$*" >> "%s"\n' "$SHIMLOG" > "$SHIMD/gh"
printf '#!/bin/sh\nprintf "touch %%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$SHIMLOG" "$REAL_TOUCH" > "$SHIMD/touch"
# bash shim: the resolver call passes through (exec the real bash), anything else is logged — an eval/bash -c of hint text would land here.
printf '#!/bin/sh\ncase "$1" in "%s") exec "%s" "$@" ;; esac\nprintf "bash %%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$STUBD/req.sh" "$REAL_BASH" "$SHIMLOG" "$REAL_BASH" > "$SHIMD/bash"
chmod +x "$SHIMD/gh" "$SHIMD/touch" "$SHIMD/bash"
# positive control: the shims log when called (a shim that cannot log makes 'log is empty' vacuous)
: > "$SHIMLOG"; PATH="$SHIMD:$PATH" gh ping; PATH="$SHIMD:$PATH" bash -c 'true'; PATH="$SHIMD:$PATH" touch "$ROOT/ctl"
[[ "$(grep -c '' "$SHIMLOG")" -eq 3 ]] && _v=0 || _v=1; chk "$_v" "S10 control: the gh, bash and touch shims each log a call" "log=[$(cat "$SHIMLOG")]"
rm -f "$ROOT/ctl"; : > "$SHIMLOG"
newrow
{
  printf 'RECOVERY rerun run=1 basis=workflow ctx="x" wf="y": gh run rerun 1\n'
  printf 'RECOVERY rerun run=2 basis=workflow ctx="$(touch %s)" wf="`touch %s`": gh run rerun 2 $(touch %s)\n' "$SENT" "$SENT" "$SENT"
  printf 'RECOVERY rerun run=3 basis=candidate ctx="a;touch %s" wf="W": bash -c "touch %s"; gh run rerun 3\n' "$SENT2" "$SENT2"
  printf '%s\n' "$M_ABS"
} > "$STUBD/body"
ENVV=(PATH="$SHIMD:$PATH")
sut S10 "$PRN"
[[ "$(cnt '^RECOVERY ' "$OUTF")" -eq 3 && "$(last_line)" == "$M_ABS" ]] && _v=0 || _v=1; chk "$_v" "S10 control: the hostile RECOVERY lines were printed (not dropped), marker last" "out=[$OUT]"
[[ ! -s "$SHIMLOG" ]] && _v=0 || _v=1; chk "$_v" "S10 the gh / bash / touch shim log is empty after the run" "log=[$(cat "$SHIMLOG")]"
[[ ! -e "$SENT" && ! -e "$SENT2" ]] && _v=0 || _v=1; chk "$_v" "S10 no sentinel file was created by hint text" "sentinels=[$(ls "$SENT" "$SENT2" 2>&1 | tr '\n' ' ')]"

# ── S11 production default: the resolver beside the script, the seam unset ──
P="$ROOT/s11"; mkdir -p "$P"; cp "$SUT" "$P/required-set-report.sh"
cat > "$P/ci-head-verdict.sh" <<EOF
#!/usr/bin/env bash
d="\$(cd "\$(dirname "\$0")" && pwd)"
printf '%s\n' "\$*" >> "\$d/calls"
printf 'RECOVERY pointer r=\r1\n'
printf 'SOLEUR_CI_REQUIRED_SET state=absent pr=%s sha=%s required=3 reason=context-absent absent=["cla-evidence"] pending=[] failed=[]\n' "\$2" "$SHA"
EOF
ROWN=$((ROWN + 1)); ROWTMP="$ROOT/row$ROWN"; mkdir -p "$ROWTMP"
env -u CI_HEAD_VERDICT_BIN -u REQUIRED_SET_TIMEOUT_S -u REQUIRED_SET_TIMEOUT_BIN TMPDIR="$ROWTMP" bash "$P/required-set-report.sh" 4387 > "$ROOT/s11.out" 2>"$ROOT/s11.err"; RC=$?
[[ "$(cat "$P/calls" 2>/dev/null)" == "required 4387" ]] && _v=0 || _v=1; chk "$_v" "S11 seam unset: the stub beside the script receives 'required 4387' and nothing else" "calls=[$(cat "$P/calls" 2>/dev/null)]"
[[ "$RC" -eq 0 && "$(tail -n 1 "$ROOT/s11.out")" == "$(mk absent)" && ! -s "$ROOT/s11.err" ]] && _v=0 || _v=1; chk "$_v" "S11 the copied script prints the marker last, exit 0, silent stderr" "rc=$RC out=[$(cat "$ROOT/s11.out")]"
[[ -z "$(ls -A "$ROWTMP")" ]] && _v=0 || _v=1; chk "$_v" "S11 no temp file left in the private TMPDIR" "left=[$(ls -A "$ROWTMP")]"
no_ctrl "$ROOT/s11.out" && [[ "$(cnt '^RECOVERY pointer r=1$' "$ROOT/s11.out")" -eq 1 ]] && _v=0 || _v=1; chk "$_v" "S11 without lib/context-sanitize.sh beside it the fallback sanitiser still drops the CR" "out=[$(printf '%q' "$(cat "$ROOT/s11.out")")]"

# ── S12 non-canonical but valid input is printed and parsed ──
newrow
{
  printf 'RECOVERY rerun run=5 basis=workflow ctx="has \\"quotes\\" and ] bracket" wf="W [x]": gh run rerun 5\n'
  printf 'SOLEUR_CI_REQUIRED_SET state=absent pr=%s sha=%s required=3 reason=context-absent absent=["a b","c [d]"] pending=[] failed=[]\n' "$PRN" "$SHA"
} > "$STUBD/body"
sut S12 "$PRN"
[[ "$(cnt 'has \\"quotes\\" and \] bracket' "$OUTF")" -eq 1 && "$(last_line)" == *'absent=["a b","c [d]"] pending=[] failed=[]' && "$(nmarkers)" -eq 1 ]] && _v=0 || _v=1; chk "$_v" "S12 a marker with spaces and brackets inside its JSON, and a ctx= with quotes and ], are printed whole" "out=[$OUT]"

# ── S13 tail truncation: a body larger than 262144 bytes still ends in its marker ──
newrow
{ head -c 300000 /dev/zero | tr '\0' 'x'; printf '\nRECOVERY pointer reason=late\n'; printf '%s\n' "$M_ABS"; } > "$STUBD/body"
[[ "$(wc -c < "$STUBD/body")" -gt 262144 ]] && _v=0 || _v=1; chk "$_v" "S13 control: the body is larger than 262144 bytes" "size=$(wc -c < "$STUBD/body")"
sut S13 "$PRN"
[[ "$(last_line)" == "$M_ABS" && "$(nmarkers)" -eq 1 && "$(cnt '^RECOVERY pointer reason=late$' "$OUTF")" -eq 1 && "$(nlines)" -eq 4 ]] && _v=0 || _v=1; chk "$_v" "S13 the tail is kept: the marker is last and the late hint survives, the padding does not" "lines=$(nlines) last=[$(last_line)]"

# ── S14 two markers for this PR in the resolver output: the LAST one is the answer, and only it is printed ──
newrow; { printf '%s\n' "$R_HINT"; mk complete; mk absent; } > "$STUBD/body"
sut S14 "$PRN"
[[ "$(nmarkers)" -eq 1 && "$(last_line)" == "$M_ABS" ]] && _v=0 || _v=1; chk "$_v" "S14 two matching markers in the body: exactly one marker is printed and it is the LAST one (state=absent)" "out=[$OUT]"
[[ "$OUT" != *"NOT that the PR is mergeable"* ]] && _v=0 || _v=1; chk "$_v" "S14 the earlier complete marker contributes nothing (no 'mergeable' note)" "out=[$OUT]"

# ── totals and the assertion floor ──
echo ""
echo "cases_run=$CASES_RUN passes=$passes fails=$fails ledger=${#FAILED[@]}"
_min_cases=221
if [[ "$CASES_RUN" -lt "$_min_cases" ]]; then
  printf '[FATAL] assertion floor: only %s case(s) ran, floor is %s\n' "$CASES_RUN" "$_min_cases" >&2; exit 1
fi
if [[ $((passes + fails)) -ne "$CASES_RUN" ]]; then
  printf '[FATAL] %s verdicts for %s cases\n' "$((passes + fails))" "$CASES_RUN" >&2; exit 1
fi
if [[ "${#FAILED[@]}" -ne "$fails" ]]; then
  printf '[FATAL] ledger/counter disagree: %s vs %s\n' "${#FAILED[@]}" "$fails" >&2; exit 1
fi
if [[ "${#FAILED[@]}" -ne 0 ]]; then
  printf '[FATAL] %s failing assertion(s):\n' "${#FAILED[@]}" >&2
  printf '  - %s\n' "${FAILED[@]}" >&2; exit 1
fi
echo "required-set-report: all $passes assertions passed"
