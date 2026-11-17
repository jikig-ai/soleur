#!/usr/bin/env bash
# Unit suite for plugins/soleur/scripts/required-set-report.sh (#11544, inline half).
#
# The resolver (`ci-head-verdict.sh required`) is a STUB that replays the REAL contract (hints first, the marker as the LAST stdout line,
# exit 0 for decided states, 3 for state=error, 2 and no marker for usage); a stub that echoed what the script expects would grade the
# script against itself. No `gh` is called and no `git` is spawned. Every row runs with a private TMPDIR that must be empty afterwards
# (no leaked temp file is a property of every row, not a row of its own). All scratch lives under ONE root owned by ONE EXIT trap.
# shellcheck disable=SC2012,SC2016,SC2094  # ls -A emptiness probes, literal $ in single-quoted fixtures, one-way byte compare
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
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

# chk() decides every assertion below, so it gets its own control: status 0 must move passes, non-zero must move fails, and the case
# counter must move by one per call (a chk that always passes, or that routes by the wrong status, is caught here).
_p=$passes; _f=$fails; _fl=${#FAILED[@]}; _c=$CASES_RUN
chk 0 "selftest-ok" "" >/dev/null; _p1=$passes; _f1=$fails
chk 1 "selftest-bad" "" >/dev/null 2>&1
if [[ "$_p1" -eq $((_p + 1)) && "$_f1" -eq "$_f" && "$passes" -eq $((_p + 1)) && "$fails" -eq $((_f + 1)) && "$CASES_RUN" -eq $((_c + 2)) ]]; then
  _v=0
else
  _v=1
fi
passes=$_p; fails=$_f; FAILED=("${FAILED[@]:0:$_fl}"); CASES_RUN=$_c
# The verdict on chk() must NOT be delivered through chk() (a chk that always passes would pass its own check): count the case and call
# pass/fail directly.
CASES_RUN=$((CASES_RUN + 1))
if [[ "$_v" -eq 0 ]]; then pass "INSTRUMENT: chk() routes status 0 to pass, non-zero to fail, one case per call"
else fail "INSTRUMENT: chk() does not discriminate on its status; every assertion below is decorative"; fi

# ONE root, ONE owning EXIT trap (ADR-129). The reaper also runs there, so an aborted row cannot leave a detached holder behind.
assert_fixture_dir() {  # refuse an empty, relative, root-ish or synthetic-fs scratch dir before anything is armed to rm -rf it
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
ROOT="$(mktemp -d)"; assert_fixture_dir "$ROOT"
HOLDER_PIDS="$ROOT/pids"; : > "$HOLDER_PIDS"
reap() {  # kill every pid the stubs recorded (the detached holder, the trapping stub's sleep)
  local p
  while read -r p; do [[ "$p" =~ ^[0-9]+$ ]] && kill -KILL "$p" 2>/dev/null; done < "$HOLDER_PIDS"
  : > "$HOLDER_PIDS"
}
trap 'reap; rm -rf "$ROOT"' EXIT
gone() {  # 0 once the pid is gone (polls $2 times, default 20); a killed orphan may linger as a zombie for a moment (read -t is the sleep-free wait)
  local n
  for n in $(seq 1 "${2:-20}"); do
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
# Positive controls for the helpers that decide many verdicts: each must answer BOTH ways once, or a helper that always says "fine" is invisible.
printf 'clean text\n' > "$ROOT/ctl-clean"; printf 'esc\033[0m\n' > "$ROOT/ctl-esc"
no_ctrl "$ROOT/ctl-clean" && ! no_ctrl "$ROOT/ctl-esc" && _v=0 || _v=1; chk "$_v" "CONTROL no_ctrl() accepts clean text and rejects a file holding an ESC byte" ""
sleep 30 & _lp=$!; echo "$_lp" >> "$HOLDER_PIDS"
! gone "$_lp" 2 && _v=0 || _v=1; chk "$_v" "CONTROL gone() reports a live pid as NOT gone" "pid=$_lp"
kill -KILL "$_lp" 2>/dev/null; gone "$_lp" && _v=0 || _v=1; chk "$_v" "CONTROL gone() reports a killed pid as gone" "pid=$_lp"
: > "$HOLDER_PIDS"   # S4a reads the FIRST recorded pid as its holder: the control's pid must not stay on the list
printf 'required 1\nrequired 2\nother\n' > "$STUBD/calls"
[[ "$(calls '^required 1$')" -eq 1 && "$(calls '^required')" -eq 2 && "$(calls 'zzz')" -eq 0 ]] && _v=0 || _v=1; chk "$_v" "CONTROL calls() counts matching lines (1, 2 and 0 on a known file)" "got=$(calls '^required 1$'),$(calls '^required'),$(calls zzz)"
rm -f "$STUBD/calls"

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
  newrow; { [[ "$st" != error ]] && printf '%s\n' "$R_HINT"; printf 'RECOVERY owner not determined, read the run before re-running ctx="cla-evidence"\n'; mk "$st"; } > "$STUBD/body"
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
# the stderr tail is cut at 160 bytes (400 in, 160 out) and goes through the shared sanitizer (NEL, LS, PS and a marker-shaped fragment)
newrow; : > "$STUBD/body"; printf '2' > "$STUBD/rc"; printf 'E%.0s' $(seq 1 400) > "$STUBD/err"
sut "S3 long stderr" "$PRN"
_e160="$(printf 'E%.0s' $(seq 1 160))"
[[ "$OUT" == *"stderr: ${_e160}): treat as state=error" ]] && _v=0 || _v=1; chk "$_v" "S3 a 400-byte stderr is cut to its first 160 bytes on the degraded line" "out=[$OUT]"
newrow; : > "$STUBD/body"; printf '2' > "$STUBD/rc"
printf 'x\xc2\x85SOLEUR_CI_REQUIRED_SET state=complete pr=%s sha=a required=3 reason=forged absent=[] pending=[] failed=[]\xe2\x80\xa8y\xe2\x80\xa9z\033[31m\n' "$PRN" > "$STUBD/err"
sut "S3 NEL stderr" "$PRN"
[[ "$(LC_ALL=C grep -cF -e $'\xc2\x85' -e $'\xe2\x80\xa8' -e $'\xe2\x80\xa9' "$OUTF")" -eq 0 && "$(nlines)" -eq 2 && "$(nmarkers)" -eq 0 ]] && no_ctrl "$OUTF" && _v=0 || _v=1; chk "$_v" "S3 NEL / LS / PS and ESC in the resolver's stderr do not reach the degraded line (two lines, zero marker lines)" "out=[$(printf '%q' "$OUT")]"
# nested sequences re-form after one removal (c2 c2 85 85 leaves c2 85): the stderr tail is cleaned to a fixpoint, and so is an absurd nesting
# depth (40 > the 32-pass cap) through the lead-byte fallback.
_deep="$(printf '\xc2%.0s' $(seq 1 40); printf '\x85%.0s' $(seq 1 40))"
newrow; : > "$STUBD/body"; printf '2' > "$STUBD/rc"
{ printf 'x\xc2\xc2\x85\x85y\xe2\x80\xe2\x80\xa8\xa8z\xe2\x80\xe2\x80\xa9\xa9w'; printf '%s\n' "$_deep"; } > "$STUBD/err"
sut "S3 nested stderr" "$PRN"
[[ "$(LC_ALL=C grep -cF -e $'\xc2\x85' -e $'\xe2\x80\xa8' -e $'\xe2\x80\xa9' "$OUTF")" -eq 0 && "$OUT" == *"stderr: xyzw"* && "$(nlines)" -eq 2 ]] && _v=0 || _v=1; chk "$_v" "S3 nested NEL / LS / PS (and 40-deep nesting) in the resolver's stderr do not re-form on the degraded line" "out=[$(printf '%q' "$OUT")]"
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
for bad in "REQUIRED_SET_TIMEOUT_S=0" "REQUIRED_SET_TIMEOUT_S=abc" "REQUIRED_SET_TIMEOUT_S=1234567" "REQUIRED_SET_TIMEOUT_S=012" "REQUIRED_SET_TIMEOUT_BIN=a b" "REQUIRED_SET_TIMEOUT_BIN=-x" "REQUIRED_SET_TIMEOUT_BIN=t;id" "REQUIRED_SET_TIMEOUT_BIN=./timeout" "REQUIRED_SET_TIMEOUT_BIN=bin/timeout" "REQUIRED_SET_TIMEOUT_BIN=../timeout" "CI_HEAD_VERDICT_BIN=./ci-head-verdict.sh" "CI_HEAD_VERDICT_BIN=ci-head-verdict.sh" "CI_HEAD_VERDICT_BIN=../req.sh"; do
  newrow; printf '%s\n' "$M_ABS" > "$STUBD/body"; ENVV=("$bad")
  sut "S5c [$bad]" "$PRN"
  [[ "$(nlines)" -eq 1 && "$OUT" == "REQUIRED-SET READ — no marker (usage"* && ! -e "$STUBD/calls" ]] && _v=0 || _v=1; chk "$_v" "S5c bad seam [$bad]: one degraded line, the resolver is never called" "out=[$OUT]"
done

# The timeout is clamped to the fence's 120 s ceiling: 99999 and 121 become 120, 120 and 100 pass through (the seam cannot lengthen the
# "up to ~125s" the fence announces). The running line and the argv both carry the clamped value.
for pair in "99999:120" "121:120" "120:120" "100:100"; do
  tv="${pair%%:*}"; want="${pair##*:}"
  newrow; printf '%s\n' "$M_ABS" > "$STUBD/body"; ENVV=(REQUIRED_SET_TIMEOUT_BIN="$STUBD/tbin" REQUIRED_SET_TIMEOUT_S="$tv")
  sut "S5d [$tv]" "$PRN"
  [[ "$(cat "$STUBD/targv" 2>/dev/null)" == "-k 5 $want bash $STUBD/req.sh required 4387" && "$(sed -n 1p "$OUTF")" == "REQUIRED-SET READ — running (up to $((want + 5))s):"* ]] && _v=0 || _v=1; chk "$_v" "S5d REQUIRED_SET_TIMEOUT_S=$tv runs as timeout -k 5 $want (clamped to at most 120) and announces $((want + 5))s" "argv=[$(cat "$STUBD/targv" 2>/dev/null)] out=[$OUT]"
done
# A bare name and an absolute path both stay valid (the relative-path refusal above must not eat them).
newrow; printf '%s\n' "$M_ABS" > "$STUBD/body"; ENVV=(REQUIRED_SET_TIMEOUT_BIN="$STUBD/tbin")
sut "S5e abs" "$PRN"
[[ "$(last_line)" == "$M_ABS" ]] && _v=0 || _v=1; chk "$_v" "S5e an absolute REQUIRED_SET_TIMEOUT_BIN path is accepted" "out=[$OUT]"
# Non-ASCII digits: [0-9] matches them in some UTF-8 locales. Discover a locale where it really does (a row run under a locale the host lacks
# makes bash print setlocale warnings and goes red for a reason that has nothing to do with the script). With none, the nine assertions
# are skipped placeholders so the count stays exact, and on a CI host the missing locale is itself a FAILURE (the rows would be vacuous).
_wideloc=""
for _l in en_US.UTF-8 en_US.utf8 C.UTF-8 C.utf8; do
  if LC_ALL=$_l bash -c '[[ "٣" =~ ^[0-9]+$ ]]' 2>/dev/null; then _wideloc="$_l"; break; fi
done
if [[ -n "$_wideloc" ]]; then
  chk 0 "S5f control: [0-9] accepts an Arabic-Indic digit under the discovered locale (the rows below can tell it from the explicit class)" "locale=$_wideloc"
  newrow; printf '%s\n' "$M_ABS" > "$STUBD/body"; ENVV=(LC_ALL="$_wideloc")
  sut "S5f pr" "٣"
  [[ "$(nlines)" -eq 1 && "$OUT" == "REQUIRED-SET READ — no marker (usage"* && ! -e "$STUBD/calls" ]] && _v=0 || _v=1; chk "$_v" "S5f a non-ASCII digit PR argument is a usage line, the resolver is not called" "out=[$OUT]"
  newrow; printf '%s\n' "$M_ABS" > "$STUBD/body"; ENVV=(LC_ALL="$_wideloc" REQUIRED_SET_TIMEOUT_S=٣)
  sut "S5f timeout" "$PRN"
  [[ "$(nlines)" -eq 1 && "$OUT" == "REQUIRED-SET READ — no marker (usage"* && ! -e "$STUBD/calls" ]] && _v=0 || _v=1; chk "$_v" "S5f a non-ASCII digit REQUIRED_SET_TIMEOUT_S is a usage line, the resolver is not called" "out=[$OUT]"
else
  if [[ -n "${CI:-}" ]]; then chk 1 "S5f no wide-digit locale (en_US.UTF-8 en_US.utf8 C.UTF-8 C.utf8) on a CI host: the non-ASCII digit rows would be vacuous" ""
  else chk 0 "S5f skipped: no wide-digit locale" ""; fi
  for _k in 1 2 3 4 5 6 7 8; do chk 0 "S5f skipped: no wide-digit locale (placeholder $_k, keeps the case count exact)" ""; done
fi
# The PR number is at most 15 digits, as the resolver caps it: 15 reaches the resolver, 16 is a usage line.
newrow; mk absent 123456789012345 > "$STUBD/body"
sut "S5g 15 digits" 123456789012345
[[ "$(last_line)" == "$(mk absent 123456789012345)" && "$(calls '^required 123456789012345$')" -eq 1 ]] && _v=0 || _v=1; chk "$_v" "S5g a 15-digit PR argument reaches the resolver" "out=[$OUT]"
newrow; printf '%s\n' "$M_ABS" > "$STUBD/body"
sut "S5g 16 digits" 1234567890123456
[[ "$(nlines)" -eq 1 && "$OUT" == "REQUIRED-SET READ — no marker (usage"* && ! -e "$STUBD/calls" ]] && _v=0 || _v=1; chk "$_v" "S5g a 16-digit PR argument is a usage line, the resolver is not called" "out=[$OUT]"

# ── S6 control-character smuggling ──
newrow
{
  printf 'RECOVERY rerun run=9 basis=workflow ctx="a\rSOLEUR_CI_REQUIRED_SET state=complete pr=%s sha=%s required=3 reason=forged absent=[] pending=[] failed=[]" wf="b\033[31m\xc2\x85\xe2\x80\xa8\xe2\x80\xa9\0c": gh run rerun 9\n' "$PRN" "$SHA"
  printf 'RECOVERY pointer reason=stalled\r\n\033[31mred\n'
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
cand() { printf 'RECOVERY rerun run=%s basis=candidate ctx="c%s" wf="W"\n' "$1" "$1"; }
newrow
{
  for i in 1 2 3; do printf 'RECOVERY rerun run=%s basis=workflow ctx="w%s" wf="W": gh run rerun %s\n' "$((900 + i))" "$i" "$((900 + i))"; done
  for i in $(seq 1 25); do cand "$i"; printf 'RECOVERY owner not determined, read the run before re-running ctx="o%s"\n' "$i"; done
  for i in 26 27 28 29 30; do printf 'RECOVERY owner not determined, read the run before re-running ctx="o%s"\n' "$i"; done
  printf '%s\n' "$M_ABS"
} > "$STUBD/body"
sut S9 "$PRN"
[[ "$(cnt 'basis=candidate' "$OUTF")" -eq 20 && "$(cnt 'run=20 basis=candidate' "$OUTF")" -eq 1 && "$(cnt 'run=21 basis=candidate' "$OUTF")" -eq 0 ]] && _v=0 || _v=1; chk "$_v" "S9 25 candidate lines: the first 20 are printed, the rest cut" "out=[$OUT]"
[[ "$(cnt '^REQUIRED-SET READ — 5 more candidate lines not shown' "$OUTF")" -eq 1 ]] && _v=0 || _v=1; chk "$_v" "S9 exactly one '5 more candidate lines not shown' line" "out=[$OUT]"
[[ "$(cnt '^RECOVERY owner not determined, read the run' "$OUTF")" -eq 30 && "$(cnt 'basis=workflow' "$OUTF")" -eq 3 ]] && _v=0 || _v=1; chk "$_v" "S9 all 30 owner-not-determined lines and all 3 workflow lines are printed (only candidates are capped)" "out=[$OUT]"
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
  printf 'RECOVERY rerun run=2 basis=workflow ctx="$(touch %s)" wf="`touch %s`": gh run rerun 2\n' "$SENT" "$SENT"
  printf 'RECOVERY rerun run=3 basis=candidate ctx="a;touch %s" wf="W; bash -c \\"touch %s\\"; gh run rerun 3"\n' "$SENT2" "$SENT2"
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
printf 'RECOVERY no cancelled run at this head ctx="\r\033\007\177\0001"\n'
printf 'SOLEUR_CI_REQUIRED_SET state=absent pr=%s sha=%s required=3 reason=context-absent absent=["cla-evidence"] pending=[] failed=[]\n' "\$2" "$SHA"
EOF
ROWN=$((ROWN + 1)); ROWTMP="$ROOT/row$ROWN"; mkdir -p "$ROWTMP"
env -u CI_HEAD_VERDICT_BIN -u REQUIRED_SET_TIMEOUT_S -u REQUIRED_SET_TIMEOUT_BIN TMPDIR="$ROWTMP" bash "$P/required-set-report.sh" 4387 > "$ROOT/s11.out" 2>"$ROOT/s11.err"; RC=$?
[[ "$(cat "$P/calls" 2>/dev/null)" == "required 4387" ]] && _v=0 || _v=1; chk "$_v" "S11 seam unset: the stub beside the script receives 'required 4387' and nothing else" "calls=[$(cat "$P/calls" 2>/dev/null)]"
[[ "$RC" -eq 0 && "$(tail -n 1 "$ROOT/s11.out")" == "$(mk absent)" && ! -s "$ROOT/s11.err" ]] && _v=0 || _v=1; chk "$_v" "S11 the copied script prints the marker last, exit 0, silent stderr" "rc=$RC out=[$(cat "$ROOT/s11.out")]"
[[ -z "$(ls -A "$ROWTMP")" ]] && _v=0 || _v=1; chk "$_v" "S11 no temp file left in the private TMPDIR" "left=[$(ls -A "$ROWTMP")]"
no_ctrl "$ROOT/s11.out" && [[ "$(cnt '^RECOVERY no cancelled run at this head ctx="1"$' "$ROOT/s11.out")" -eq 1 ]] && _v=0 || _v=1; chk "$_v" "S11 without lib/context-sanitize.sh beside it the fallback sanitiser still drops CR, ESC, BEL, DEL and NUL" "out=[$(printf '%q' "$(cat "$ROOT/s11.out")")]"

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
{ printf 'RECOVERY no cancelled run at this head ctx="early"\n'; head -c 300000 /dev/zero | tr '\0' 'x'; printf '\nRECOVERY no cancelled run at this head ctx="late"\n'; printf '%s\n' "$M_ABS"; } > "$STUBD/body"
[[ "$(wc -c < "$STUBD/body")" -gt 262144 ]] && _v=0 || _v=1; chk "$_v" "S13 control: the body is larger than 262144 bytes" "size=$(wc -c < "$STUBD/body")"
sut S13 "$PRN"
[[ "$(last_line)" == "$M_ABS" && "$(nmarkers)" -eq 1 && "$(cnt '^RECOVERY no cancelled run at this head ctx="late"$' "$OUTF")" -eq 1 && "$(cnt 'ctx="early"' "$OUTF")" -eq 0 && "$(nlines)" -eq 4 ]] && _v=0 || _v=1; chk "$_v" "S13 only the tail is read: the marker is last and the late hint survives; the early hint (before the 262144-byte window) and the padding do not" "lines=$(nlines) last=[$(last_line)]"

# ── S14 two markers for this PR in the resolver output: the LAST one is the answer, and only it is printed ──
newrow; { printf '%s\n' "$R_HINT"; mk complete; mk absent; } > "$STUBD/body"
sut S14 "$PRN"
[[ "$(nmarkers)" -eq 1 && "$(last_line)" == "$M_ABS" ]] && _v=0 || _v=1; chk "$_v" "S14 two matching markers in the body: exactly one marker is printed and it is the LAST one (state=absent)" "out=[$OUT]"
[[ "$OUT" != *"NOT that the PR is mergeable"* ]] && _v=0 || _v=1; chk "$_v" "S14 the earlier complete marker contributes nothing (no 'mergeable' note)" "out=[$OUT]"

P_UNDO='see skills/ship/references/ready-run-wait.md (confirm in the Actions tab that no ready run is still in flight, the undo cancels it; then gh pr ready --undo, then gh pr ready, with a user token)'
P_APPR='see skills/ship/references/ready-run-wait.md (a maintainer must approve the fork workflow run)'
# ── S15 RECOVERY lines must match the resolver's CLOSED grammar; the rest is counted, not printed ──
# Positive control first: one line of each of the ten lines the resolver prints (ci-head-verdict.sh recover_required), all shown.
newrow
{
  printf 'RECOVERY rerun run=7 basis=workflow ctx="a" wf="W": gh run rerun 7\n'
  printf 'RECOVERY rerun run=8 basis=candidate ctx="a" wf="W"\n'
  printf 'RECOVERY owner not determined (read failed) ctx="a"\n'
  printf 'RECOVERY owner not determined, read the run before re-running ctx="a"\n'
  printf 'RECOVERY no cancelled run at this head ctx="a"\n'
  printf 'RECOVERY pointer reason=stale-row ctx="test": %s\n' "$P_UNDO"
  printf 'RECOVERY pointer reason=awaiting-approval ctx="test": %s\n' "$P_APPR"
  printf 'RECOVERY pointer reason=stalled ctx="test": %s\n' "$P_UNDO"
  printf 'RECOVERY pointer failed=["x","y z"]: read the failing checks with gh pr checks 4387\n'
  printf 'RECOVERY pointer pending=[]: wait, then read the checks with gh pr checks 4387\n'
  printf 'RECOVERY rerun run=123456789012345 basis=workflow ctx="a" wf="W": gh run rerun 123456789012345\n'
  printf '%s\n' "$M_ABS"
} > "$STUBD/body"
sut S15a "$PRN"
[[ "$(cnt '^RECOVERY ' "$OUTF")" -eq 11 && "$OUT" != *"outside the resolver grammar"* && "$(last_line)" == "$M_ABS" ]] && _v=0 || _v=1; chk "$_v" "S15a every line the resolver prints (ten printf lines, three pointer reasons, a 15-digit run id) is shown, no 'outside the grammar' line" "out=[$OUT]"
# Negative rows: each line below is outside the grammar and must be dropped and counted.
newrow
{
  printf 'RECOVERY rerun run=2 basis=workflow ctx="x" wf="y": gh run rerun 2 $(touch %s)\n' "$ROOT/S15"      # trailing command text
  printf 'RECOVERY rerun run=3 basis=workflow ctx="x" wf="y": gh run rerun 4\n'                              # id differs from run=
  printf 'RECOVERY rerun run=1234567890123456 basis=workflow ctx="x" wf="y": gh run rerun 1234567890123456\n'  # 16 digits
  printf 'RECOVERY rerun run=5 basis=candidate ctx="x" wf="y": bash -c id\n'                                  # candidate with a tail
  printf 'RECOVERY rerun run=6 basis=guess ctx="x" wf="y"\n'                                                  # unknown basis
  printf 'RECOVERY rerun run=7 basis=candidate ctx=x wf="y"\n'                                                # ctx not a JSON string
  printf 'RECOVERY no cancelled run at this head ctx="x" and more\n'                                          # trailing text on a closer
  printf 'RECOVERY run this: rm -rf /\n'                                                                       # an unknown shape
  printf 'RECOVERY pointer reason=bogus ctx="x"\n'                                                            # unknown pointer reason
  printf 'RECOVERY pointer pending=: wait, then read the checks with gh pr checks 4387\n'                    # empty array
  printf 'RECOVERY pointer failed=["a"]: read the failing checks with gh pr checks 4387 && id\n'             # different tail
  printf 'RECOVERY pointer failed=["a"]: read the failing checks with gh pr checks 9999\n'                   # another PR
  printf 'RECOVERY rerun run=3 basis=guess ctx="x" wf="y": gh run rerun 3\n'                                 # unknown basis with the command tail
  printf 'RECOVERY owner not determined, read the run before re-running now ctx="x"\n'                       # text before ctx=
  printf 'RECOVERY rerun run=%s basis=candidate ctx="x" wf="y"\n' 123456789012345678901234567890            # 30-digit candidate id
  printf 'RECOVERY rerun run=4 basis=candidate ctx="a" wf="b" wf="c"\n'                                      # unescaped embedded " wf="
  printf 'RECOVERY\n'                                                                                         # bare keyword
  printf 'RECOVERY pointer reason=stale-row ctx="test": do something else entirely\n'                         # fixed-reason pointer, other tail
  printf 'RECOVERY pointer reason=stalled ctx="x": %s and then more\n' "$P_UNDO"                              # stalled pointer, extra tail
  printf 'RECOVERY pointer reason=awaiting-approval ctx="test": %s && x\n' "$P_APPR"                          # awaiting-approval, command tail
  printf 'RECOVERY pointer reason=awaiting-approval ctx="test": %s and more\n' "$P_APPR"                      # awaiting-approval, longer tail
  printf 'RECOVERY pointer reason=stale-row ctx="test": %s and more\n' "$P_UNDO"                              # stale-row, longer tail
  printf 'RECOVERY pointer pending=["a"]: wait, then read the checks with gh pr checks 4387 && id\n'           # pending, command tail
  printf 'RECOVERY pointer pending=["a"]: wait, then read the checks with gh pr checks 9999\n'                  # pending, another PR
  printf 'RECOVERY pointer failed=[a b]: read the failing checks with gh pr checks 4387\n'                     # unquoted array element
  printf '%s\n' "$M_ABS"
} > "$STUBD/body"
sut S15b "$PRN"
[[ "$(cnt '^RECOVERY ' "$OUTF")" -eq 0 && "$(cnt "^REQUIRED-SET READ — 25 RECOVERY line(s) outside the resolver grammar not shown (run the read by hand: ready-run-wait.md, 'A green verdict that never enqueues')\$" "$OUTF")" -eq 1 && "$(last_line)" == "$M_ABS" ]] && _v=0 || _v=1; chk "$_v" "S15b twenty-five lines outside the grammar (command tails, id mismatch, 16- and 30-digit ids, bad bases, unquoted ctx, trailing text, unknown shape and pointer reason, empty array, other PR, embedded wf=, bare keyword): none printed, one count line with the by-hand pointer, marker last" "out=[$OUT]"
[[ "$(wc -l < "$STUBD/calls")" -eq 1 && ! -e "$ROOT/S15" ]] && _v=0 || _v=1; chk "$_v" "S15b nothing was executed (no sentinel) and the resolver was called once" "calls=$(cat "$STUBD/calls")"
newrow
{ printf 'RECOVERY rerun run=2 basis=workflow ctx="x" wf="y": gh run rerun 9\n'; printf 'RECOVERY no cancelled run at this head ctx="ok"\n'; mk error; } > "$STUBD/body"; printf '3' > "$STUBD/rc"
sut S15c "$PRN"
[[ "$(cnt '^RECOVERY ' "$OUTF")" -eq 0 && "$OUT" != *"outside the resolver grammar"* ]] && _v=0 || _v=1; chk "$_v" "S15c state=error prints neither hints nor a grammar count line" "out=[$OUT]"

# ── S15d nested sequences inside wf= on a RECOVERY line that IS printed. The real resolver cleans wf= (its `clean` filter) and rejects a ctx
# with such code points (amr_arr_ok); it does NOT clean its stderr, and a substituted resolver cleans nothing, so the script itself must clean
# to a fixpoint ──
newrow
{
  printf 'RECOVERY rerun run=9 basis=workflow ctx="c" wf="a\xc2\xc2\x85\x85b\xe2\x80\xe2\x80\xa8\xa8c\xe2\x80\xe2\x80\xa9\xa9d": gh run rerun 9\n'
  printf 'RECOVERY rerun run=10 basis=candidate ctx="c" wf="%s"\n' "$_deep"
  printf '%s\n' "$M_ABS"
} > "$STUBD/body"
sut S15d "$PRN"
[[ "$(LC_ALL=C grep -cF -e $'\xc2\x85' -e $'\xe2\x80\xa8' -e $'\xe2\x80\xa9' "$OUTF")" -eq 0 && "$(cnt '^RECOVERY rerun run=9 basis=workflow ctx="c" wf="abcd": gh run rerun 9$' "$OUTF")" -eq 1 && "$(cnt '^RECOVERY rerun run=10 basis=candidate' "$OUTF")" -eq 1 ]] && _v=0 || _v=1; chk "$_v" "S15d nested NEL / LS / PS inside wf= (and 40-deep nesting) do not re-form; both lines are still printed" "out=[$(printf '%q' "$OUT")]"

# ── S15e ordinary non-ASCII text survives untouched (the fixpoint must converge on it, not take the lead-byte fallback), and a non-canonical PR ──
newrow; { printf 'RECOVERY no cancelled run at this head ctx="a\xc2\xa9b\xe2\x80\x94c"\n'; printf '%s\n' "$M_ABS"; } > "$STUBD/body"
sut S15e "$PRN"
[[ "$(cnt "^RECOVERY no cancelled run at this head ctx=\"a"$'\xc2\xa9'"b"$'\xe2\x80\x94'"c\"\$" "$OUTF")" -eq 1 ]] && _v=0 || _v=1; chk "$_v" "S15e a ctx with a copyright sign and an em dash is printed UNCHANGED (the fixpoint converges instead of dropping 0xC2/0xE2)" "out=[$(printf '%q' "$OUT")]"
newrow; { printf 'RECOVERY pointer failed=["x"]: read the failing checks with gh pr checks 7\n'; printf 'RECOVERY pointer pending=["x"]: wait, then read the checks with gh pr checks 007\n'; mk absent 7; } > "$STUBD/body"
sut S15f 007
[[ "$(cnt '^RECOVERY pointer ' "$OUTF")" -eq 2 && "$OUT" != *"outside the resolver grammar"* && "$(last_line)" == "$(mk absent 7)" ]] && _v=0 || _v=1; chk "$_v" "S15f PR argument 007: pointers ending 'checks 7' (normalised) and 'checks 007' (as given) are both printed, no count line" "out=[$OUT]"
# _fix runs in byte semantics (a 240 KB line took 6-32 s per read in a UTF-8 locale and 1-2 s in C, identical output). A wall-clock bound is not stable
# across hosts, so the property is pinned on the source: the function declares LC_ALL=C for itself.
grep -qF 'local t u n=0 LC_ALL=C' "$SUT" && _v=0 || _v=1; chk "$_v" "S15g _fix declares LC_ALL=C for itself (byte semantics, a UTF-8 locale made it 6-13x slower)" ""

# ── S18 the grammar is tied to the resolver's SOURCE: every `printf 'RECOVERY` line of ci-head-verdict.sh, instantiated, is accepted ──
# A resolver edit that adds or rewords a RECOVERY line fails here instead of silently dropping the hint in production. The count (10) is the
# number of lines S15a covers; the positive control is that those ten instantiated lines all come out.
mapfile -t _fmts < <(grep -vE '^[[:space:]]*#' "$DIR/ci-head-verdict.sh" | grep -o "printf 'RECOVERY[^']*'" | sed -e "s/^printf '//" -e "s/'\$//" \
  -e 's/failed=%s/failed=["a"]/' -e 's/pending=%s/pending=["a"]/' -e 's/run=%s/run=12345/' -e 's/ctx=%s/ctx="c"/' -e 's/wf=%s/wf="w"/' \
  -e 's/gh run rerun %s/gh run rerun 12345/' -e 's/gh pr checks %s/gh pr checks 4387/' -e 's/\\n$//')
_left=0; for _f in "${_fmts[@]}"; do [[ "$_f" == *%* ]] && _left=$((_left + 1)); done
[[ "${#_fmts[@]}" -eq 10 && "$_left" -eq 0 ]] && _v=0 || _v=1; chk "$_v" "S18 ci-head-verdict.sh has exactly 10 (non-comment) printf 'RECOVERY lines and every %s in them is one this suite knows how to fill" "lines=${#_fmts[@]} unfilled=$_left"
# Any OTHER non-comment line that mentions `RECOVERY ` is an emitter the extraction above cannot see (an echo, a double-quoted printf, a heredoc). The one
# allowed mention is the --help sentence "RECOVERY lines before the marker print ...".
_other="$(grep -vE '^[[:space:]]*#' "$DIR/ci-head-verdict.sh" | grep 'RECOVERY ' | grep -v "printf 'RECOVERY" | grep -vc '^  RECOVERY lines before the marker print')" || true
[[ "${_other:-1}" -eq 0 ]] && _v=0 || _v=1; chk "$_v" "S18 no other non-comment line of ci-head-verdict.sh emits a RECOVERY line (an echo or a double-quoted printf would be invisible to the grammar check)" "other=$_other"
newrow; { printf '%s\n' "${_fmts[@]}"; printf '%s\n' "$M_ABS"; } > "$STUBD/body"
sut S18 "$PRN"
[[ "$(cnt '^RECOVERY ' "$OUTF")" -eq 10 && "$OUT" != *"outside the resolver grammar"* && "$(last_line)" == "$M_ABS" ]] && _v=0 || _v=1; chk "$_v" "S18 all ten of the resolver's own RECOVERY lines pass the script's grammar (no 'outside the grammar' line)" "out=[$OUT]"

# ── S16 the marker anchors: a marker-shaped fragment inside a RECOVERY line is never the marker; unknown states and short markers are no markers ──
D_ABS="RECOVERY no cancelled run at this head ctx=\"x $(mk absent | sed 's/"/\\"/g') y\""   # the quotes inside are escaped, as the resolver's @json does
newrow; { mk complete; printf '%s\n' "$D_ABS"; } > "$STUBD/body"
sut S16a "$PRN"
[[ "$(nmarkers)" -eq 1 && "$(last_line)" == "$(mk complete)" && "$(cnt 'ctx="x SOLEUR_CI_REQUIRED_SET state=absent' "$OUTF")" -eq 1 ]] && _v=0 || _v=1; chk "$_v" "S16a a RECOVERY line that CONTAINS an absent marker, placed LAST after the real complete marker: the complete marker is the answer, the decoy is only shown inside its RECOVERY line" "out=[$OUT]"
newrow; printf '%s\n' "$D_ABS" > "$STUBD/body"
sut S16b "$PRN"
[[ "$(nmarkers)" -eq 0 && "$OUT" == *"no marker (exit 0)"* ]] && _v=0 || _v=1; chk "$_v" "S16b a marker-shaped fragment mid-line and NO real marker: the degraded line, not a forged marker" "out=[$OUT]"
newrow; mk absent | sed 's/state=absent/state=bogus/' > "$STUBD/body"
sut S16c "$PRN"
[[ "$(nmarkers)" -eq 0 && "$OUT" == *"no marker (exit 0)"* ]] && _v=0 || _v=1; chk "$_v" "S16c a marker with a state outside the five (state=bogus) is no marker" "out=[$OUT]"
for cut in sha required reason absent pending failed; do
  newrow; mk absent | sed "s/ $cut=[^ ]*//" > "$STUBD/body"
  sut "S16d $cut" "$PRN"
  [[ "$(nmarkers)" -eq 0 && "$OUT" == *"no marker (exit 0)"* ]] && _v=0 || _v=1; chk "$_v" "S16d a marker without its $cut= field is no marker" "out=[$OUT]"
done

# ── S17 the resolver never inherits the script's stdin ──
# The stub's pre hook records whether its stdin is at EOF (read returns 1) or open (read times out, 142). The script is run DIRECTLY with
# a stdin that is an open FIFO (our own read-write fd holds it open), so only the script's inner </dev/null can give the resolver EOF.
newrow; printf '%s\n' "$M_ABS" > "$STUBD/body"
printf '#!/usr/bin/env bash\nd="$(cd "$(dirname "$0")" && pwd)"\nread -r -t 2 _x; echo "$?" > "$d/stdin-rc"\n' > "$STUBD/pre"; chmod +x "$STUBD/pre"
mkfifo "$ROOT/fifo"; exec {_ffd}<>"$ROOT/fifo"
ROWN=$((ROWN + 1)); ROWTMP="$ROOT/row$ROWN"; mkdir -p "$ROWTMP"
env CI_HEAD_VERDICT_BIN="$STUBD/req.sh" TMPDIR="$ROWTMP" "$REAL_BASH" "$SUT" "$PRN" >"$ROOT/s17.out" 2>/dev/null <&"$_ffd"
exec {_ffd}<&-
[[ "$(cat "$STUBD/stdin-rc" 2>/dev/null)" == 1 && "$(tail -n 1 "$ROOT/s17.out")" == "$M_ABS" ]] && _v=0 || _v=1; chk "$_v" "S17 the resolver's stdin is at EOF though the script's own stdin is an open pipe (read rc 1, not a 2 s timeout)" "stdin-rc=$(cat "$STUBD/stdin-rc" 2>/dev/null)"
rm -f "$STUBD/stdin-rc"

# ── totals and the assertion floor ──
echo ""
echo "cases_run=$CASES_RUN passes=$passes fails=$fails ledger=${#FAILED[@]}"
_min_cases=368
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
