#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2015,SC2034  # `A && B || C` is the row idiom; the anchors below are single-quoted LITERAL hook text and are never expanded; a few globals are read by helpers in other functions
# Guard 1 of the W2 plan, mutation half (plan Phase 1.6; knowledge-base/project/plans/2026-10-06-feat-plugin-destructive-command-guard-w2-plan.md):
# the chokepoint rows M1-M8 of the destructive-command hook's mutation matrix, executed in CI against a COPY
# of the plugin tree. The other matrix rows (9-20) were run once at work time and are recorded in
# knowledge-base/project/specs/feat-agent-security-three-layers/phase-0-measurements.md (section 1.6).
#
# WALL-TIME BUDGET: 60 s total for this file when the machine is quiet (measured at work time and reported in the PR;
# the hook suite alone takes 35 s quiet, ~110 s under load, so every mutant runs it in REDUCED mode: DCG_ROWS=<ERE>
# selects only the rows that kill that mutant, plus the always-on static, registration, lexer-contract and harness
# checks; the suite's own MIN_CASES floor does not apply to a selection and is replaced there by a selected-row count).
# Time is handled in two separate ways, and neither one scores a mutant:
#   * a whole-battery overrun of the 60 s figure is only a [WARN] (measured: 31-41 s on a quiet box, 136 s once with five
#     sibling worktrees running suites; a slow runner is not a defect);
#   * each reduced hook-suite run has its own timeout, 50 s scaled by (load average / cores) with a 50 s floor and a 200 s
#     cap (scaled_timeout below). A single run that still exceeds it is UNRESOLVED: the battery is INCONCLUSIVE (exit 3),
#     and that mutant is counted neither as killed nor as survived, because a killed run and a survived run both need a
#     summary the timed-out run never printed.
#
# PROPERTY. For each edit of the guard's chokepoints below, the hook suite turns RED on the row that is
# designed to catch it, and it is GREEN on the unedited copy first. A mutant that is not killed, did not
# land, or was killed by something other than its designed detector, is a finding.
#   M1   the hook stops scanning the second command of a list (only the first lexer record is judged)
#   M2   garbled, empty or truncated stdin, or a non-string command, exits 0 instead of asking
#   M3a  the lexer returns zero records and the hook reports "nothing to check" as an allow
#   M3b  a lexer parse failure (no OK frame) exits 0 instead of asking
#   M4a  the zero-spawn prefilter no longer sees a boundary character (\ ' " $ backtick)
#   M4b  the zero-spawn prefilter no longer sees the keyword `destroy`
#   M5a  a missing or unusable jq exits 0 unconditionally (the ADR-165 defect)
#   M5b  a missing or unusable perl exits 0 unconditionally
#   M6a  the kill-switch read moves below the dependency probes
#   M6b  the kill switch honours any non-empty value, not only 1
#   M7a  the hooks.json registration is removed
#   M7b  the hooks.json matcher no longer matches Bash
#   M8   the decision envelope loses hookEventName
#
# ASSEMBLY. The surface is the pipeline pristine copy -> content-anchored edit -> landing proof -> reduced
# hook-suite run -> kill verdict. Each stage has its own check:
#   * COPY. Only a copy of plugins/soleur/hooks and plugins/soleur/test/lib is edited, in a temp dir; the
#     hook suite is pointed at the copy with GUARD_REPO_ROOT (it reads the hook, the lexer, hooks.json and
#     its fixture library from that root). The working tree is never edited: the tracked-file status and a
#     checksum of every source file are compared before and after, and the suite fails on any difference.
#     Every mutant is restored from the pristine copy (cp), never with git.
#   * EDIT. Each edit replaces a literal CONTENT anchor (never a line number) that must occur exactly the
#     stated number of times, or the edit fails loudly.
#   * LANDING. Before a mutant runs, cmp must show its edited file differs from the pristine copy and a
#     recursive diff must show that file and no other differs, and the mutated hook must still parse
#     (bash -n) or the hooks.json must still be valid JSON: a mutation that did not land reports the
#     baseline and would read as a pass, and a mutant that no longer parses is killed by the parser, not by
#     the row that is designed to catch it. A no-op edit is driven through the same proof and must read as
#     "not landed".
#   * CONTROL. The unedited copy runs first, on the union of every selection, and must be GREEN with at
#     least the literal floor of selected rows; an empty or red control voids the battery (printf + exit 1).
#   * VERDICT. KILLED means: exit status exactly 1, at least one failed case, pass + fail == cases, at least
#     the literal floor of selected rows ran, no harness error, and a [FAIL] line that matches the mutant's
#     designed detector. The judge itself is driven once with a canned green and a canned red output.
#   Summaries are read from ANSI-stripped output. No exit status is taken through a pipe.
#
# Anti-vacuity: `CHECKED` moves at the call site (never in pass/fail), pass + fail must equal it, an
# instrument self-test drives both helpers, and the check floor is a literal directly above its `if`,
# reported by a direct printf + exit 1 and never through the helpers it backstops.
#
# Run: bash plugins/soleur/test/destructive-command-guard-mutation.test.sh
export TMPDIR="${TMPDIR:-/var/tmp}"
export LC_ALL=C
set -uo pipefail

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SUITE_DIR/$(basename "${BASH_SOURCE[0]}")"
REPO_ROOT="$(cd "$SUITE_DIR/../../.." && pwd)"
HOOK_SUITE="$SUITE_DIR/destructive-command-guard-hook.test.sh"
T0="$SECONDS"

PASS_COUNT=0
FAIL_COUNT=0
CHECKED=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "  [ok] $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  [FAIL] $1" >&2; }
# A verdict at the call site: the counter moves HERE, independent of pass()/fail().
chk() { # chk <label> <ok|anything else> [detail]
  CHECKED=$((CHECKED + 1))
  if [[ "$2" == ok ]]; then pass "$1"; else fail "$1${3:+ -- $3}"; fi
}

# Instrument self-test: both helpers must record before any row runs.
_iv_p="$PASS_COUNT"; _iv_f="$FAIL_COUNT"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$PASS_COUNT" -ne $((_iv_p + 1)) || "$FAIL_COUNT" -ne $((_iv_f + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
PASS_COUNT=0; FAIL_COUNT=0

harness_die() { printf 'HARNESS: %s\n' "$1" >&2; exit 2; }

JQ_BIN="$(command -v jq)" || harness_die "jq is required"
PERL_BIN="$(command -v perl)" || harness_die "perl is required"
TIMEOUT_BIN="$(command -v timeout)" || harness_die "timeout is required"
[[ -n "${BASH:-}" && -x "$BASH" ]] || harness_die "cannot resolve the running bash"
[[ -f "$HOOK_SUITE" ]] || harness_die "the hook suite is missing: $HOOK_SUITE"

# The body below is the CANONICAL copy, asserted byte-for-byte against every other copy by
# plugins/soleur/test/fixture-dir-operand-assert.test.sh. Do not reword it in one file only. #7652
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

WORK="$(mktemp -d "$TMPDIR/dcg-mut.XXXXXXXX")" || harness_die "mktemp failed"
assert_fixture_dir "$WORK"
trap 'rm -rf -- "$WORK"' EXIT
WORK="$(cd "$WORK" && pwd -P)"
assert_fixture_dir "$WORK"

# --- the real tree must come out of this suite exactly as it went in ---------------------------------
# The sources we copy from, by checksum, and the tracked-file status (read-only: --no-optional-locks, and
# every inherited GIT_* variable stripped by prefix so a lefthook-exported GIT_INDEX_FILE cannot redirect it).
SRC_FILES=(plugins/soleur/hooks/destructive-command-guard.sh plugins/soleur/hooks/lib/shell-argv.pl plugins/soleur/hooks/hooks.json plugins/soleur/test/destructive-command-guard-hook.test.sh)
GIT_UNSET=()
while IFS= read -r _v; do [[ -n "$_v" ]] && GIT_UNSET+=(-u "$_v"); done < <(compgen -e | grep '^GIT_' || true)
tracked_status() {
  env ${GIT_UNSET[@]+"${GIT_UNSET[@]}"} git --no-optional-locks -C "$REPO_ROOT" status --porcelain --untracked-files=no 2>/dev/null
}
sources_sum() {
  local f
  for f in "${SRC_FILES[@]}"; do cksum < "$REPO_ROOT/$f"; done
}
STATUS_BEFORE="$(tracked_status; printf 'rc=%s' "$?")"
SUM_BEFORE="$(sources_sum)"

# --- the pristine copy ---------------------------------------------------------------------------------
PRISTINE="$WORK/pristine"
SCRATCH="$WORK/scratch"
assert_fixture_dir "$PRISTINE"; assert_fixture_dir "$SCRATCH"
mkdir -p "$PRISTINE/plugins/soleur/test" "$SCRATCH" || harness_die "mkdir failed"
cp -R "$REPO_ROOT/plugins/soleur/hooks" "$PRISTINE/plugins/soleur/hooks" || harness_die "cannot copy the hooks"
cp -R "$REPO_ROOT/plugins/soleur/test/lib" "$PRISTINE/plugins/soleur/test/lib" || harness_die "cannot copy the test lib"
HOOK_REL=plugins/soleur/hooks/destructive-command-guard.sh
LEXER_REL=plugins/soleur/hooks/lib/shell-argv.pl
JSON_REL=plugins/soleur/hooks/hooks.json
for _f in "$HOOK_REL" "$LEXER_REL" "$JSON_REL"; do [[ -f "$PRISTINE/$_f" ]] || harness_die "the pristine copy lacks $_f"; done

# restore <dir>: a fresh copy of the pristine tree (never git).
restore() {
  assert_fixture_dir "$1"
  case "$1" in "$WORK"/*) : ;; *) harness_die "refusing to restore outside the scratch root: $1" ;; esac
  rm -rf -- "$1" && mkdir -p "$1" && cp -R "$PRISTINE/." "$1/" || harness_die "restore failed for $1"
}

# mut_replace <file> <literal anchor> <literal replacement> <expected occurrences>
# 0 on success; 3 unreadable; 4 the anchor does not occur exactly the expected number of times; 5 unwritable.
mut_replace() {
  ANCHOR="$2" REPL="$3" EXPECT="$4" "$PERL_BIN" -e '
    my $f = $ARGV[0];
    open(my $h, "<", $f) or exit 3;
    my $s = do { local $/; <$h> };
    close $h;
    my ($a, $r, $n) = ($ENV{ANCHOR}, $ENV{REPL}, $ENV{EXPECT});
    exit 4 if length($a) < 8;
    my ($c, $p) = (0, 0);
    while (($p = index($s, $a, $p)) >= 0) { $c++; $p += length $a }
    exit 4 if $c != $n;
    my ($o, $q) = ("", 0);
    $p = 0;
    while (($q = index($s, $a, $p)) >= 0) { $o .= substr($s, $p, $q - $p) . $r; $p = $q + length $a }
    $o .= substr($s, $p);
    open(my $w, ">", $f) or exit 5;
    print $w $o;
    close $w;
    exit 0;' "$1"
}

# landed <tree> <relative file>: 0 only when that file differs from the pristine copy AND it is the only
# file in the tree that does.
landed() {
  local tree="$1" rel="$2" n
  cmp -s "$PRISTINE/$rel" "$tree/$rel" && return 1
  n="$(diff -rq "$PRISTINE" "$tree" 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$n" == 1 ]]
}

# strip_ansi: stdin -> stdout.
strip_ansi() { LC_ALL=C sed $'s/\033\\[[0-9;?]*[A-Za-z]//g'; }

# run_suite <tree> <rows ERE>: the hook suite against that tree in reduced mode. Sets RS_OUT (ANSI-stripped,
# both streams), RS_RC, RS_CASES, RS_PASS, RS_FAILS, RS_SEL (empty when the summary line is missing).
RS_OUT=""; RS_RC=0; RS_CASES=""; RS_PASS=""; RS_FAILS=""; RS_SEL=""
parse_summary() { # reads RS_OUT
  local line sel
  line="$(printf '%s\n' "$RS_OUT" | grep -E '^cases=[0-9]+ passes=[0-9]+ fails=[0-9]+$' | tail -n 1)"
  sel="$(printf '%s\n' "$RS_OUT" | grep -E '^selected=[0-9]+$' | tail -n 1)"
  RS_CASES=""; RS_PASS=""; RS_FAILS=""; RS_SEL=""
  if [[ -n "$line" ]]; then
    RS_CASES="${line#cases=}"; RS_CASES="${RS_CASES%% *}"
    RS_PASS="${line#*passes=}"; RS_PASS="${RS_PASS%% *}"
    RS_FAILS="${line#*fails=}"
  fi
  [[ -n "$sel" ]] && RS_SEL="${sel#selected=}"
  return 0
}
# scaled_timeout <load average> <cores> -> seconds: 50 scaled by load/cores, floor 50, cap 200; 100 when either input is not a number.
scaled_timeout() {
  awk -v l="${1-}" -v c="${2-}" 'BEGIN {
    if (l !~ /^[0-9]+([.][0-9]+)?$/ || c !~ /^[0-9]+$/ || c + 0 < 1) { print 100; exit }
    r = l / c; if (r < 1) r = 1
    t = int(50 * r + 0.999); if (t < 50) t = 50; if (t > 200) t = 200
    print t
  }'
}
# The load average and the core count are read here and nowhere else. A sandbox COPY of this suite (DCG_MUT_META_COPY, set only by the
# self-test rows below) may point them at fixtures; the real run always reads /proc/loadavg and nproc.
LOADAVG_FILE=/proc/loadavg; CORES_FIXED=""
if [[ -n "${DCG_MUT_META_COPY:-}" ]]; then LOADAVG_FILE="${DCG_LOADAVG_FILE:-/proc/loadavg}"; CORES_FIXED="${DCG_CORES:-}"; fi
current_timeout() { # [loadavg file] [cores]: the timeout for a run started now
  local lf="${1:-$LOADAVG_FILE}" load cores
  load="$(cut -d' ' -f1 "$lf" 2>/dev/null)" || load=""
  cores="${2:-${CORES_FIXED:-$(nproc 2>/dev/null)}}"
  scaled_timeout "$load" "$cores"
}
RS_TIMEOUT=50
run_suite() {
  local raw
  RS_TIMEOUT="$(current_timeout)"
  raw="$(env -u GUARD_HOOK -u GUARD_FAST_COUNT -u GUARD_META_COPY -u SOLEUR_DISABLE_DESTRUCTIVE_GUARD \
    "GUARD_REPO_ROOT=$1" "DCG_ROWS=$2" "TMPDIR=$SCRATCH" \
    "$TIMEOUT_BIN" "$RS_TIMEOUT" "$BASH" "$HOOK_SUITE" 2>&1 </dev/null)"; RS_RC=$?
  RS_OUT="$(printf '%s' "$raw" | strip_ansi)"
  parse_summary
}
# is_unresolved: the run was cut off by its timeout (timeout(1) exits 124), so it says nothing about the mutant.
is_unresolved() { [[ "$RS_RC" -eq 124 ]]; }
UNRESOLVED_N=0; UNRESOLVED_WHO=""
note_unresolved() { # <what>
  UNRESOLVED_N=$((UNRESOLVED_N + 1)); UNRESOLVED_WHO="${UNRESOLVED_WHO:+$UNRESOLVED_WHO, }$1"
  printf '[UNRESOLVED] %s: the reduced run exceeded its %s s timeout (load %s over %s cores); it is neither killed nor survived. Re-run on a quieter machine.\n' "$1" "$RS_TIMEOUT" "$(cut -d' ' -f1 "$LOADAVG_FILE" 2>/dev/null || echo '?')" "${CORES_FIXED:-$(nproc 2>/dev/null || echo '?')}"
}

# is_green: the control's contract. <min selected rows>
is_green() {
  [[ "$RS_RC" -eq 0 && "$RS_FAILS" == 0 && -n "$RS_CASES" && "$RS_CASES" -eq $((RS_PASS + RS_FAILS)) \
    && -n "$RS_SEL" && "$RS_SEL" -ge "$1" ]] || return 1
  grep -qE '^  \[FAIL\]|^\[FATAL\]|^HARNESS:' <<<"$RS_OUT" && return 1
  return 0
}
# is_killed: the mutant contract. <min selected rows> <detector ERE over the [FAIL] lines>
is_killed() {
  [[ "$RS_RC" -eq 1 && -n "$RS_CASES" && -n "$RS_FAILS" && "$RS_FAILS" -ge 1 && "$RS_CASES" -eq $((RS_PASS + RS_FAILS)) \
    && -n "$RS_SEL" && "$RS_SEL" -ge "$1" ]] || return 1
  grep -qE '^\[FATAL\]|^HARNESS:' <<<"$RS_OUT" && return 1
  grep -E '^  \[FAIL\]' <<<"$RS_OUT" | grep -qE "$2"
}

# --- the judge is itself driven once: a canned green and a canned red ------------------------------------
_canned_green=$'  [ok] x\ncases=10 passes=10 fails=0\nselected=4'
_canned_red=$'  [ok] x\n  [FAIL] some designed detector -- want=ask got=none\ncases=10 passes=9 fails=1\nselected=4'
_canned_fatal=$'  [FAIL] some designed detector\n[FATAL] anti-vacuity: DCG_ROWS matched no row\ncases=10 passes=9 fails=1\nselected=4'
RS_OUT="$_canned_green"; RS_RC=0; parse_summary
is_green 4 && _g=ok || _g=bad; is_killed 4 'designed detector' && _k=bad || _k=ok
chk "judge: a canned green output is green and not killed" "$([[ $_g == ok && $_k == ok ]] && printf ok || printf bad)"
RS_OUT="$_canned_red"; RS_RC=1; parse_summary
is_killed 4 'designed detector' && _k=ok || _k=bad; is_green 4 && _g=bad || _g=ok
chk "judge: a canned red output is killed by its detector and not green" "$([[ $_g == ok && $_k == ok ]] && printf ok || printf bad)"
is_killed 4 'a different detector' && _k=bad || _k=ok
chk "judge: a red output whose [FAIL] lines do not match the designed detector is NOT a kill" "$_k"
is_killed 5 'designed detector' && _k=bad || _k=ok
chk "judge: a red output with fewer selected rows than the floor is NOT a kill" "$_k"
RS_OUT="$_canned_fatal"; RS_RC=1; parse_summary
is_killed 4 'designed detector' && _k=bad || _k=ok
chk "judge: a [FATAL] floor trip is NOT a kill" "$_k"
RS_OUT="$_canned_red"; RS_RC=2; parse_summary
is_killed 4 'designed detector' && _k=bad || _k=ok
chk "judge: a harness error (exit 2) is NOT a kill" "$_k"

RS_OUT=""; RS_RC=124; RS_CASES=""; RS_PASS=""; RS_FAILS=""; RS_SEL=""
is_unresolved && _u=ok || _u=bad; is_killed 4 'designed detector' && _k=bad || _k=ok; is_green 4 && _g=bad || _g=ok
chk "judge: a run cut off by its timeout (rc 124) is UNRESOLVED, and is neither killed nor green" "$([[ $_u == ok && $_k == ok && $_g == ok ]] && printf ok || printf bad)"
RS_OUT="$_canned_red"; RS_RC=1; parse_summary
is_unresolved && _u=bad || _u=ok
RS_OUT="$_canned_green"; RS_RC=0; parse_summary
is_unresolved && _u2=bad || _u2=ok
chk "judge: a red run and a green run are not UNRESOLVED" "$([[ $_u == ok && $_u2 == ok ]] && printf ok || printf bad)"
chk "timeout: scaled by load over cores with a 50 s floor and a 200 s cap (and 100 s when the inputs are unreadable)" \
  "$([[ "$(scaled_timeout 0.4 8)" == 50 && "$(scaled_timeout 8 8)" == 50 && "$(scaled_timeout 16 8)" == 100 && "$(scaled_timeout 30 8)" == 188 && "$(scaled_timeout 400 8)" == 200 && "$(scaled_timeout 3000 1)" == 200 && "$(scaled_timeout '' 8)" == 100 && "$(scaled_timeout abc 8)" == 100 && "$(scaled_timeout 5 0)" == 100 ]] && printf ok || printf bad)" \
  "got: $(scaled_timeout 0.4 8) $(scaled_timeout 8 8) $(scaled_timeout 16 8) $(scaled_timeout 30 8) $(scaled_timeout 400 8) $(scaled_timeout 3000 1) $(scaled_timeout '' 8) $(scaled_timeout abc 8) $(scaled_timeout 5 0)"

# --- a no-op edit must read as "not landed" --------------------------------------------------------------
NOOP="$WORK/noop"
restore "$NOOP"
mut_replace "$NOOP/$HOOK_REL" 'set -uo pipefail' 'set -uo pipefail' 1; _rc=$?
landed "$NOOP" "$HOOK_REL" && _x=bad || _x=ok
chk "landing proof: an edit that replaces an anchor with itself reads as NOT landed (rc=$_rc)" "$_x"
restore "$NOOP"
mut_replace "$NOOP/$HOOK_REL" 'set -uo pipefail' 'set -uo pipefail' 2; _rc=$?
chk "edit helper: an anchor that does not occur the stated number of times is refused (rc=$_rc)" "$([[ $_rc -eq 4 ]] && printf ok || printf bad)"

# --- the mutants -----------------------------------------------------------------------------------------
# Each mutant: id | rows ERE | detector ERE | selected-row floor | the edit (a function). The rows ERE is
# matched against hook-suite row LABELS; the unlabelled static, registration, lexer-contract and harness
# checks run in every reduced run and are what kills M7a, M7b and M3a's lexer-contract row.
HK="$HOOK_REL"
mut_M1()  { mut_replace "$1/$HK" 'NREC=${#REC_N[@]}' 'NREC=$(( ${#REC_N[@]} > 1 ? 1 : ${#REC_N[@]} ))' 1; }
mut_M2()  { mut_replace "$1/$HK" 'emit ask "envelope-unreadable:' 'exit 0; emit ask "envelope-unreadable:' 1; }
mut_M3a() { mut_replace "$1/$LEXER_REL" '    $out .= $rec;' '    $out .= q();' 1; }
mut_M3b() { mut_replace "$1/$HK" 'if [[ -n "$SAW_E" ]]; then ask_parse "lexer ${SAW_E}"; fi' 'if [[ -n "$SAW_E" ]]; then exit 0; fi' 1; }
# The prefilter's case line holds every quote kind, so its anchor is read from a quoted heredoc, not spelled in a string.
IFS= read -r -d '' M4A_ANCHOR <<'ANCHOR_EOF' || true
*'<<'*|*[\\\'\"\$\`]*) : ;;
ANCHOR_EOF
M4A_ANCHOR="${M4A_ANCHOR%$'\n'}"
mut_M4a() { mut_replace "$1/$HK" "$M4A_ANCHOR" "*'<<'*) : ;;" 1; }
mut_M4b() { mut_replace "$1/$HK" '*rm*|*destroy*|*push*' '*rm*|*push*' 1; }
mut_M5a() { mut_replace "$1/$HK" 'degrade_jq() {' $'degrade_jq() {\n  exit 0' 1; }
mut_M5b() { mut_replace "$1/$HK" 'if [[ "$PERL_PROBE" != ok || ! -r "$LEXER" ]]; then' $'if [[ "$PERL_PROBE" != ok || ! -r "$LEXER" ]]; then\n    exit 0' 1; }
mut_M6a() {
  local ks='[[ "${SOLEUR_DISABLE_DESTRUCTIVE_GUARD-}" == "1" ]] && exit 0'
  mut_replace "$1/$HK" "$ks"$'\n' '' 1 || return $?
  mut_replace "$1/$HK" '[[ "$FIELDS" == invalid ]] && ask_envelope "the envelope is not a JSON object"' "$ks"$'\n''[[ "$FIELDS" == invalid ]] && ask_envelope "the envelope is not a JSON object"' 1
}
mut_M6b() { mut_replace "$1/$HK" '[[ "${SOLEUR_DISABLE_DESTRUCTIVE_GUARD-}" == "1" ]] && exit 0' '[[ -n "${SOLEUR_DISABLE_DESTRUCTIVE_GUARD-}" ]] && exit 0' 1; }
json_edit() { # <tree> <jq filter>
  local f="$1/$JSON_REL"
  assert_fixture_dir "$f"
  "$JQ_BIN" "$2" "$f" > "$f.new" 2>/dev/null && mv -f "$f.new" "$f"
}
HOOK_SEL='.hooks | map(.command) | any(contains("destructive-command-guard.sh"))'
mut_M7a() { json_edit "$1" "del(.hooks.PreToolUse[] | select($HOOK_SEL))"; }
mut_M7b() { json_edit "$1" "(.hooks.PreToolUse[] | select($HOOK_SEL) | .matcher) |= \"^Edit\$\""; }
mut_M8()  {
  mut_replace "$1/$HK" 'hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d' 'hookSpecificOutput: {permissionDecision: $d' 1 || return $?
  mut_replace "$1/$HK" '{"hookSpecificOutput":{"hookEventName":"PreToolUse",' '{"hookSpecificOutput":{' 2
}

# id | edited file (relative) | well-formedness kind | rows ERE | selected floor | detector ERE
M_IDS="M1 M2 M3a M3b M4a M4b M5a M5b M6a M6b M7a M7b M8"
mdef() { # mdef <id> -> sets M_FILE M_KIND M_ROWS M_FLOOR M_DETECT
  case "$1" in
    M1)  M_FILE="$HK"; M_KIND="sh"; M_FLOOR=4
         M_ROWS='^(terraform plan; (terraform destroy|rm -rf ~)|ls && (terraform destroy|rm -rf ~))$'
         M_DETECT='terraform plan; (terraform destroy|rm -rf ~)|ls && (terraform destroy|rm -rf ~)' ;;
    M2)  M_FILE="$HK"; M_KIND="sh"; M_FLOOR=5
         M_ROWS='^(garbage stdin asks|a truncated envelope asks|empty stdin asks|an array command asks|a numeric command asks)'
         M_DETECT='garbage stdin asks|a truncated envelope asks|empty stdin asks|an array command asks|a numeric command asks' ;;
    M3a) M_FILE="$LEXER_REL"; M_KIND="none"; M_FLOOR=2
         M_ROWS='^(terraform destroy|rm -rf ~)$'
         M_DETECT='lexer: a known command yields at least one record|^  \[FAIL\] (terraform destroy|rm -rf ~) ' ;;
    M3b) M_FILE="$HK"; M_KIND="sh"; M_FLOOR=5
         M_ROWS='^(an unbalanced|an unterminated|a heredoc with no delimiter|a substitution nested past)'
         M_DETECT='an unbalanced|an unterminated|a heredoc with no delimiter|a substitution nested past' ;;
    M4a) M_FILE="$HK"; M_KIND="sh"; M_FLOOR=25
         M_ROWS='^(boundary|a (dollar sign|single quote|backslash|backtick|double quote) )'
         M_DETECT='boundary|a (dollar sign|single quote|backslash|backtick|double quote) ' ;;
    M4b) M_FILE="$HK"; M_KIND="sh"; M_FLOOR=3
         M_ROWS='^(terraform destroy|tofu destroy|a keyword only, no boundary character \(destroy\))$'
         M_DETECT='terraform destroy|tofu destroy|a keyword only, no boundary character \(destroy\)' ;;
    M5a) M_FILE="$HK"; M_KIND="sh"; M_FLOOR=10
         M_ROWS='^jq-less'
         M_DETECT='jq-less: (rm -f jq|terraform destroy|a destroy after|a force push)' ;;
    M5b) M_FILE="$HK"; M_KIND="sh"; M_FLOOR=7
         M_ROWS='^perl-less'
         M_DETECT='perl-less: (rm -rf|terraform destroy|a destroy after|a force push)' ;;
    M6a) M_FILE="$HK"; M_KIND="sh"; M_FLOOR=11
         M_ROWS='^SOLEUR_DISABLE_DESTRUCTIVE_GUARD'
         M_DETECT='SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1 exits 0 silently (on garbage stdin|with no jq)' ;;
    M6b) M_FILE="$HK"; M_KIND="sh"; M_FLOOR=11
         M_ROWS='^SOLEUR_DISABLE_DESTRUCTIVE_GUARD'
         M_DETECT='SOLEUR_DISABLE_DESTRUCTIVE_GUARD(=0|=true|=yes|=01|=. 1.) (still )?(keeps|denies)' ;;
    M7a) M_FILE="$JSON_REL"; M_KIND="json"; M_FLOOR=1
         M_ROWS='^SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1 exits 0 silently on a destroy$'
         M_DETECT='hooks.json carries a PreToolUse entry' ;;
    M7b) M_FILE="$JSON_REL"; M_KIND="json"; M_FLOOR=1
         M_ROWS='^SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1 exits 0 silently on a destroy$'
         M_DETECT="that entry's matcher matches Bash" ;;
    M8)  M_FILE="$HK"; M_KIND="sh"; M_FLOOR=6
         M_ROWS='\(M8\)|^(terraform destroy|rm -rf ~)$|^jq-less: (rm -f jq|the hand-built)'
         M_DETECT='\(M8\)|hand-built output|^  \[FAIL\] (terraform destroy|rm -rf ~) ' ;;
    *) harness_die "unknown mutant $1" ;;
  esac
}

# the union of every selection: the control runs it first
UNION=""
for _id in $M_IDS; do mdef "$_id"; UNION="${UNION:+$UNION|}($M_ROWS)"; done
UNION_FLOOR=73

# current_timeout reads its two inputs (the first field of the load-average file, the core count): driven with fixtures, so a wrong field,
# a wrong file or a constant is a red row, not a green one (only scaled_timeout's arithmetic was rowed before)
GT="$WORK/t9"; assert_fixture_dir "$GT"; mkdir -p "$GT" || harness_die "mkdir t9"
printf '30.00 2.00 1.00 3/700 12345\n' > "$GT/load30"; printf '4.00 90.00 90.00 1/700 1\n' > "$GT/load4"; printf 'garbage\n' > "$GT/loadbad"
_ct_got="$(current_timeout "$GT/load30" 8) $(current_timeout "$GT/load4" 8) $(current_timeout "$GT/loadbad" 8) $(current_timeout "$GT/absent" 8) $(current_timeout "$GT/load30" 2) $(current_timeout "$GT/load30" abc)"
chk "timeout: current_timeout reads the FIRST field of the load-average file and the core count it is given (load 30 on 8 cores 188 s; load 4 with a high 5- and 15-minute average 50 s; a garbage or missing file 100 s; load 30 on 2 cores the 200 s cap; a core count that is not a number 100 s)" \
  "$([[ "$_ct_got" == "188 50 100 100 200 100" ]] && printf ok || printf bad)" "got: $_ct_got"

# The unresolved wiring, driven through the REAL per-mutant loop: a sandbox COPY of this suite whose hook suite is a canned stub (the control's union
# selection answered green, every other selection cut off with exit 124, as timeout(1) does) must exit 3 with [UNRESOLVED] for every mutant and
# score none of them killed or survived; with a control that is itself cut off it must exit 3 before any mutant runs.
if [[ -z "${DCG_MUT_META_COPY:-}" ]]; then
  mk_t9_tree() { # <name> <stub body> -> T9_DIR: a tree that holds the hooks, the test lib, a copy of this suite and the stub hook suite
    T9_DIR="$WORK/t9/$1"; assert_fixture_dir "$T9_DIR"
    mkdir -p "$T9_DIR/plugins/soleur/test" || harness_die "mkdir $T9_DIR"
    cp -R "$REPO_ROOT/plugins/soleur/hooks" "$T9_DIR/plugins/soleur/hooks" && cp -R "$REPO_ROOT/plugins/soleur/test/lib" "$T9_DIR/plugins/soleur/test/lib" \
      && cp "$SELF" "$T9_DIR/plugins/soleur/test/destructive-command-guard-mutation.test.sh" || harness_die "cannot build the t9 tree"
    printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T9_DIR/plugins/soleur/test/destructive-command-guard-hook.test.sh"
    chmod +x "$T9_DIR/plugins/soleur/test/destructive-command-guard-hook.test.sh"
    env ${GIT_UNSET[@]+"${GIT_UNSET[@]}"} git -C "$T9_DIR" init -q >/dev/null 2>&1
  }
  t9_run() { # <tree dir> -> T9_OUT, T9_RC
    T9_OUT="$(env ${GIT_UNSET[@]+"${GIT_UNSET[@]}"} DCG_MUT_META_COPY=1 "DCG_LOADAVG_FILE=$GT/load30" DCG_CORES=8 "TMPDIR=$WORK/t9" "$BASH" "$1/plugins/soleur/test/destructive-command-guard-mutation.test.sh" 2>&1 </dev/null | strip_ansi)"; T9_RC=${PIPESTATUS[0]}
  }
  mkdir -p "$WORK/t9"
  mk_t9_tree cut "case \"\${DCG_ROWS:-}\" in \"(\"*) printf 'cases=100 passes=100 fails=0\\nselected=100\\n'; exit 0 ;; esac; exit 124"
  t9_run "$T9_DIR"
  _ids_missing=""; for _id in $M_IDS; do grep -q "^\[UNRESOLVED\] $_id: " <<<"$T9_OUT" || _ids_missing+=" $_id"; done
  chk "unresolved: a hook suite that is cut off on every mutant makes the battery exit 3 (INCONCLUSIVE), not 0 and not 1 (rc=$T9_RC)" \
    "$([[ "$T9_RC" -eq 3 ]] && grep -q 'INCONCLUSIVE (exit 3)' <<<"$T9_OUT" && printf ok || printf bad)" "tail: $(tail -n 3 <<<"$T9_OUT" | tr '\n' ' ')"
  chk "unresolved: every mutant is reported [UNRESOLVED] by name" "$([[ -z "$_ids_missing" ]] && printf ok || printf bad)" "not reported:$_ids_missing"
  chk "unresolved: no cut-off mutant is scored killed or survived (no 'turns RED on the designed detector' verdict at all)" \
    "$(grep -q 'turns RED on the designed detector' <<<"$T9_OUT" && printf bad || printf ok)" "$(grep -m2 'turns RED on the designed detector' <<<"$T9_OUT" | cut -c1-160 | tr '\n' '~')"
  chk "unresolved: the timeout a cut-off run reports is the one the load-average source gives (load 30 over 8 cores: 188 s)" \
    "$(grep -q '^\[UNRESOLVED\] M1: the reduced run exceeded its 188 s timeout (load 30.00 over 8 cores)' <<<"$T9_OUT" && printf ok || printf bad)" "$(grep -m1 '^\[UNRESOLVED\] M1' <<<"$T9_OUT" | cut -c1-200)"
  mk_t9_tree ctl "exit 124"
  t9_run "$T9_DIR"
  chk "unresolved: a control run that is itself cut off exits 3 before any mutant runs (rc=$T9_RC)" \
    "$([[ "$T9_RC" -eq 3 ]] && grep -q '^\[UNRESOLVED\] control: ' <<<"$T9_OUT" && ! grep -q '^== the mutants ==' <<<"$T9_OUT" && printf ok || printf bad)" "tail: $(tail -n 3 <<<"$T9_OUT" | tr '\n' ' ')"
else
  for _n in 1 2 3 4 5; do chk "unresolved: sandbox-copy row $_n (not run inside the meta copy)" ok; done
fi

echo "== control: the unedited copy must be GREEN before any mutant runs =="
CONTROL="$WORK/control"
restore "$CONTROL"
if [[ "$(diff -rq "$PRISTINE" "$CONTROL" 2>/dev/null | wc -l | tr -d ' ')" == 0 ]]; then _x=ok; else _x=bad; fi
chk "control: the control tree is byte-identical to the pristine copy" "$_x"
run_suite "$CONTROL" "$UNION"
CONTROL_WALL="$((SECONDS - T0))"
if is_unresolved; then
  note_unresolved "control"
  printf '[UNRESOLVED] the control run timed out: the battery is INCONCLUSIVE (exit 3), not void and not green.\n' >&2
  exit 3
fi
if is_green "$UNION_FLOOR"; then _x=ok; else _x=bad; fi
chk "control: the unedited copy is green on the union of the selections (cases=$RS_CASES fails=$RS_FAILS selected=$RS_SEL, floor $UNION_FLOOR)" "$_x"
if [[ "$_x" != ok ]]; then
  printf '[FATAL] the control (unedited copy) is not green: the battery is void. rc=%s cases=%s fails=%s selected=%s\n' "$RS_RC" "${RS_CASES:-?}" "${RS_FAILS:-?}" "${RS_SEL:-?}" >&2
  printf '%s\n' "$RS_OUT" | grep -E '^  \[FAIL\]|^\[FATAL\]|^HARNESS:' | head -n 12 >&2
  exit 1
fi

echo "== the mutants =="
for ID in $M_IDS; do
  mdef "$ID"
  MUT="$WORK/m-$ID"
  restore "$MUT"
  t_start="$SECONDS"
  "mut_$ID" "$MUT"; _rc=$?
  _land=bad; landed "$MUT" "$M_FILE" && _land=ok
  [[ "$_rc" -eq 0 ]] || _land=bad
  chk "$ID: the edit landed (anchor found, $M_FILE differs from the pristine copy, no other file differs; edit rc=$_rc, cksum $(cksum < "$PRISTINE/$M_FILE" | cut -d' ' -f1) -> $(cksum < "$MUT/$M_FILE" | cut -d' ' -f1))" "$_land"
  _wf=bad
  case "$M_KIND" in
    sh) "$BASH" -n "$MUT/$M_FILE" 2>/dev/null && _wf=ok ;;
    json) "$JQ_BIN" -e . "$MUT/$M_FILE" >/dev/null 2>&1 && _wf=ok ;;
    none) [[ -s "$MUT/$M_FILE" ]] && _wf=ok ;;
  esac
  chk "$ID: the mutant is well-formed (it would otherwise be killed by the parser, not by its designed detector)" "$_wf"
  if [[ "$_land" == ok && "$_wf" == ok ]]; then
    run_suite "$MUT" "$M_ROWS"
    if is_unresolved; then note_unresolved "$ID"; continue; fi
    if is_killed "$M_FLOOR" "$M_DETECT"; then _x=ok; else _x=bad; fi
    chk "$ID: the hook suite turns RED on the designed detector (rc=$RS_RC cases=${RS_CASES:-?} fails=${RS_FAILS:-?} selected=${RS_SEL:-?}, floor $M_FLOOR, $((SECONDS - t_start)) s)" "$_x" "a SURVIVING or wrongly-killed mutant: $(printf '%s\n' "$RS_OUT" | grep -E '^  \[FAIL\]|^\[FATAL\]|^HARNESS:' | head -n 3 | tr '\n' '~')"
  else
    chk "$ID: the hook suite turns RED on the designed detector (not run: the mutation did not land or is malformed)" bad
  fi
done

echo "== the real tree is unchanged =="
STATUS_AFTER="$(tracked_status; printf 'rc=%s' "$?")"
SUM_AFTER="$(sources_sum)"
chk "the tracked-file status is the same before and after (and git status itself ran: ${STATUS_AFTER##*rc=})" "$([[ "$STATUS_BEFORE" == "$STATUS_AFTER" && "$STATUS_AFTER" == *"rc=0" ]] && printf ok || printf bad)" "before: ${STATUS_BEFORE:0:200} after: ${STATUS_AFTER:0:200}"
chk "no source file under test changed (cksum of the hook, the lexer, hooks.json and the hook suite)" "$([[ "$SUM_BEFORE" == "$SUM_AFTER" && -n "$SUM_AFTER" ]] && printf ok || printf bad)"

# =====================================================================================================
echo "== summary =="
WALL="$((SECONDS - T0))"
echo "wall-time: ${WALL}s (control ${CONTROL_WALL}s; budget 60s)"
if [[ "$WALL" -gt 60 ]]; then echo "[WARN] wall time ${WALL}s is over the 60s budget"; fi
echo "cases=$CHECKED passes=$PASS_COUNT fails=$FAIL_COUNT"
if [[ "$UNRESOLVED_N" -gt 0 ]]; then
  printf '[UNRESOLVED] %s mutant run(s) timed out (%s): the battery is INCONCLUSIVE (exit 3): not green, and no mutant is scored as survived or killed on a run that never finished.\n' "$UNRESOLVED_N" "$UNRESOLVED_WHO" >&2
  exit 3
fi
if [[ $((PASS_COUNT + FAIL_COUNT)) -ne "$CHECKED" ]]; then
  printf '[FATAL] anti-vacuity: %s verdicts recorded for %s cases\n' "$((PASS_COUNT + FAIL_COUNT))" "$CHECKED" >&2; exit 1
fi
MIN_CASES=60
if [[ "$CHECKED" -lt "$MIN_CASES" ]]; then
  printf '[FATAL] anti-vacuity: only %s assertions ran, floor is %s\n' "$CHECKED" "$MIN_CASES" >&2
  exit 1
fi
[[ "$FAIL_COUNT" -eq 0 ]]
