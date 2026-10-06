#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2030,SC2031  # `A && B || C` is the row idiom; perl/awk programs are single-quoted on purpose; the floor-zero rows deliberately override the floors in a subshell
# Guard 2 of the W2 plan (knowledge-base/project/plans/2026-10-06-feat-plugin-destructive-command-guard-w2-plan.md):
# the plugin's shell lexer and the repo's filing lexer share their lexer code, so a lexing fix in one
# cannot silently leave the other behind.
#
#   plugins/soleur/hooks/lib/shell-argv.pl   (ships to customers; the destructive-command guard's lexer)
#   .claude/hooks/lib/filing-shape.pl        (repo-local; the guardrails filing gate's lexer, ADR-256)
#
# Each file carries EXACTLY THREE marker-delimited spans (the markers are full-line comments named
# SHARED-LEXER, one BEGIN and one END per span). The three spans are not one region because the
# filing logic is interleaved with the lexer in the original. This suite:
#   A. extracts the spans from both files, requires exactly three well-formed spans per file, each at
#      least a stated minimum size (a span the markers wrapped around nothing proves nothing), and
#      byte identity of EVERY span (all three are compared, never just the first);
#   B. runs a grammar corpus through both lexers' `--trace` output and compares the argv lines, with a
#      literal expectation per row so two lexers that are wrong in the same way cannot agree silently;
#      the bound/error framing (`E\0<cause>\0`, exit 2 and 3) is compared byte for byte;
#   C. drives the checker itself: synthetic fixtures it must accept and must reject (a floor lowered to
#      zero is caught here), and in-suite mutations of COPIES of the two real files (Guard 2 rows 1-4
#      and harness rows (a) and (b)). The live tree is never mutated.
#
# MINIMUM SPAN SIZES were measured on the tree that introduced them (span 1: 269 bytes, span 2: 751,
# span 3: 13456; marker lines excluded) and set about a quarter below that. A legitimate edit that
# shrinks a span under its floor is a loud signal to re-measure, not a flake.
#
# Anti-vacuity: the case counter is moved at the call site (never by pass/fail), pass+fail must equal
# the case count, an instrument self-test drives both helpers, and the row-count floor is a literal
# directly above its `if`, reported by a direct printf + exit 1 and never through fail().
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PLUGIN_PL="$REPO_ROOT/plugins/soleur/hooks/lib/shell-argv.pl"
ORIG_PL="$REPO_ROOT/.claude/hooks/lib/filing-shape.pl"

passes=0; fails=0; CASES=0
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); echo "  FAIL: $1" >&2; }
# A verdict at the call site: the counter moves HERE, independent of pass()/fail().
row() { # row <desc> <cond: ok|anything else>
  CASES=$((CASES + 1))
  if [[ "$2" == ok ]]; then pass "$1"; else fail "$1${3:+ -- $3}"; fi
}

_iv_p="$passes"; _iv_f="$fails"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0

command -v perl >/dev/null 2>&1 || { echo "[FATAL] perl required" >&2; exit 1; }
command -v awk >/dev/null 2>&1 || { echo "[FATAL] awk required" >&2; exit 1; }
command -v cmp >/dev/null 2>&1 || { echo "[FATAL] cmp required" >&2; exit 1; }

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

WORK="$(mktemp -d "$TMPDIR/shellargv-parity.XXXXXXXX")" || { echo "[FATAL] no scratch root" >&2; exit 2; }
assert_fixture_dir "$WORK"
trap 'rm -rf -- "$WORK"' EXIT

# A fresh scratch directory, set in the CALLING shell (an exit inside $( ) would only end the subshell).
NEWDIR=""
new_dir() {
  NEWDIR="$(mktemp -d "$WORK/d.XXXXXXXX")" || { echo "[FATAL] mktemp failed" >&2; exit 2; }
  assert_fixture_dir "$NEWDIR"
}

# ---------------------------------------------------------------------------------------------
# The checker under test
# ---------------------------------------------------------------------------------------------
WANT_SPANS=3
MIN_SPAN_1=200
MIN_SPAN_2=600
MIN_SPAN_3=10000
BEGIN_RE='^# BEGIN SHARED-LEXER$'
END_RE='^# END SHARED-LEXER$'

# span_extract <file> <dir>: writes <dir>/span.1..N (the lines strictly between a BEGIN and its END),
# sets SPAN_N. Returns 1 with SPAN_ERR for a missing file, a nested BEGIN, a stray END or an unterminated BEGIN.
SPAN_N=0; SPAN_ERR=""
span_extract() {
  local f="$1" d="$2" out rc
  SPAN_N=0; SPAN_ERR=""
  [[ -f "$f" ]] || { SPAN_ERR="missing file"; return 1; }
  out="$(awk -v d="$d" '
    /^# BEGIN SHARED-LEXER$/ { if (inspan) { bad = "nested BEGIN at line " NR; exit } inspan = 1; n++; out = d "/span." n; printf "" > out; next }
    /^# END SHARED-LEXER$/   { if (!inspan) { bad = "END without BEGIN at line " NR; exit } inspan = 0; close(out); next }
    inspan { print > out }
    END { if (bad == "" && inspan) bad = "unterminated BEGIN"; if (bad != "") { print "BAD:" bad; exit 1 } print "SPANS:" n + 0 }
  ' "$f")"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then SPAN_ERR="${out#BAD:}"; return 1; fi
  SPAN_N="${out#SPANS:}"
  return 0
}

# span_verdict <file> -> OK | RED:<reasons>   (call as $(...))
span_verdict() {
  local f="$1" d i sz min reasons=""
  new_dir; d="$NEWDIR"
  if ! span_extract "$f" "$d"; then printf 'RED:%s\n' "$SPAN_ERR"; return 0; fi
  if [[ "$SPAN_N" -ne "$WANT_SPANS" ]]; then printf 'RED:%s spans, want exactly %s\n' "$SPAN_N" "$WANT_SPANS"; return 0; fi
  for i in 1 2 3; do
    case "$i" in 1) min="$MIN_SPAN_1" ;; 2) min="$MIN_SPAN_2" ;; *) min="$MIN_SPAN_3" ;; esac
    sz="$(wc -c < "$d/span.$i" | tr -d ' ')"
    [[ "$sz" -ge "$min" ]] || reasons="$reasons span $i is $sz bytes (minimum $min);"
  done
  if [[ -n "$reasons" ]]; then printf 'RED:%s\n' "$reasons"; else printf 'OK\n'; fi
}

# parity_verdict <original> <plugin> -> OK | RED:<reasons>. Every span is compared; no early exit.
parity_verdict() {
  local a="$1" b="$2" va vb da db i diffs=""
  va="$(span_verdict "$a")"; vb="$(span_verdict "$b")"
  [[ "$va" == OK ]] || { printf 'RED:original: %s\n' "${va#RED:}"; return 0; }
  [[ "$vb" == OK ]] || { printf 'RED:plugin: %s\n' "${vb#RED:}"; return 0; }
  new_dir; da="$NEWDIR"; new_dir; db="$NEWDIR"
  span_extract "$a" "$da"; span_extract "$b" "$db"
  for i in 1 2 3; do cmp -s "$da/span.$i" "$db/span.$i" || diffs="$diffs $i"; done
  if [[ -z "$diffs" ]]; then printf 'OK\n'; else printf 'RED:spans differ:%s\n' "$diffs"; fi
}

# ---------------------------------------------------------------------------------------------
# C1. The checker against synthetic fixtures (no dependence on the real files)
# ---------------------------------------------------------------------------------------------
echo "C1. checker discrimination (synthetic fixtures)"
filler() { local n="$1"; if [[ "$n" -gt 0 ]]; then head -c "$n" /dev/zero | tr '\0' 'x'; printf '\n'; fi; return 0; }
new_dir; SY="$NEWDIR"
synth() { # synth <name> <size>... : writes $SY/<name>, one marker pair per size argument, filler of that many bytes inside
  local name="$1" n; shift
  : > "$SY/$name"
  for n in "$@"; do
    { echo '# BEGIN SHARED-LEXER'; filler "$n"; echo '# END SHARED-LEXER'; echo 'my $between = 1;'; } >> "$SY/$name"
  done
}
synth good "$MIN_SPAN_1" "$MIN_SPAN_2" "$MIN_SPAN_3"
v="$(span_verdict "$SY/good")"; row "synthetic spans at their floors are accepted" "$([[ "$v" == OK ]] && echo ok)" "$v"
synth shrunk $((MIN_SPAN_1 / 2)) $((MIN_SPAN_2 / 2)) $((MIN_SPAN_3 / 2))
v="$(span_verdict "$SY/shrunk")"; row "spans at half their floors are rejected" "$([[ "$v" == RED:* ]] && echo ok)" "$v"
v="$( MIN_SPAN_1=0; MIN_SPAN_2=0; MIN_SPAN_3=0; span_verdict "$SY/shrunk" )"
row "HARNESS (a): with the floors at zero the shrunk fixture is accepted, so only the floors catch it" "$([[ "$v" == OK ]] && echo ok)" "$v"
synth empty 0 0 0
v="$(span_verdict "$SY/empty")"; row "three marker pairs around nothing are rejected" "$([[ "$v" == RED:* ]] && echo ok)" "$v"
v="$( MIN_SPAN_1=0; MIN_SPAN_2=0; MIN_SPAN_3=0; span_verdict "$SY/empty" )"
row "HARNESS (a): with the floors at zero three empty spans are accepted" "$([[ "$v" == OK ]] && echo ok)" "$v"
: > "$SY/none"; echo 'my $x = 1;' >> "$SY/none"
v="$(span_verdict "$SY/none")"; row "a file with no markers is rejected" "$([[ "$v" == RED:* ]] && echo ok)" "$v"
synth two "$MIN_SPAN_1" "$MIN_SPAN_3"
v="$(span_verdict "$SY/two")"; row "two spans are rejected" "$([[ "$v" == RED:* ]] && echo ok)" "$v"
synth four "$MIN_SPAN_1" "$MIN_SPAN_2" "$MIN_SPAN_3" "$MIN_SPAN_3"
v="$(span_verdict "$SY/four")"; row "four spans are rejected" "$([[ "$v" == RED:* ]] && echo ok)" "$v"
{ echo '# BEGIN SHARED-LEXER'; filler "$MIN_SPAN_3"; } > "$SY/unterminated"
v="$(span_verdict "$SY/unterminated")"; row "an unterminated BEGIN is rejected" "$([[ "$v" == RED:* ]] && echo ok)" "$v"
{ filler "$MIN_SPAN_3"; echo '# END SHARED-LEXER'; } > "$SY/strayend"
v="$(span_verdict "$SY/strayend")"; row "an END without a BEGIN is rejected" "$([[ "$v" == RED:* ]] && echo ok)" "$v"
{ echo '# BEGIN SHARED-LEXER'; echo '# BEGIN SHARED-LEXER'; filler "$MIN_SPAN_3"; echo '# END SHARED-LEXER'; echo '# END SHARED-LEXER'; } > "$SY/nested"
v="$(span_verdict "$SY/nested")"; row "a nested BEGIN is rejected" "$([[ "$v" == RED:* ]] && echo ok)" "$v"
{ echo '#BEGIN SHARED-LEXER'; filler "$MIN_SPAN_3"; echo '# END SHARED-LEXER'; } > "$SY/nearmiss"
v="$(span_verdict "$SY/nearmiss")"; row "a near-miss marker (no space after #) is not a marker" "$([[ "$v" == RED:* ]] && echo ok)" "$v"
cp "$SY/good" "$SY/good2"
v="$(parity_verdict "$SY/good" "$SY/good2")"; row "an identical synthetic pair compares equal" "$([[ "$v" == OK ]] && echo ok)" "$v"
# differ in the LAST span only, after two matching spans
awk '
  /^# BEGIN SHARED-LEXER$/ { n++ }
  n == 3 && /^x+$/ && !done { sub(/^x/, "y"); done = 1 }
  { print }
' "$SY/good" > "$SY/good3"
v="$(parity_verdict "$SY/good" "$SY/good3")"
row "a divergence in the last span only (first two match) is caught" "$([[ "$v" == "RED:spans differ: 3" ]] && echo ok)" "$v"

# ---------------------------------------------------------------------------------------------
# A. The real files
# ---------------------------------------------------------------------------------------------
echo "A. marked spans of the two real lexers"
row "original lexer exists" "$([[ -f "$ORIG_PL" ]] && echo ok)" "missing: $ORIG_PL"
row "plugin lexer exists" "$([[ -f "$PLUGIN_PL" ]] && echo ok)" "missing: $PLUGIN_PL"
for pair in "original:$ORIG_PL" "plugin:$PLUGIN_PL"; do
  tag="${pair%%:*}"; file="${pair#*:}"
  nb="$(grep -c "$BEGIN_RE" "$file" 2>/dev/null || true)"
  ne="$(grep -c "$END_RE" "$file" 2>/dev/null || true)"
  nl="$(grep -c 'BEGIN SHARED-LEXER' "$file" 2>/dev/null || true)"
  row "$tag: exactly $WANT_SPANS BEGIN marker lines" "$([[ "${nb:-0}" -eq "$WANT_SPANS" ]] && echo ok)" "found ${nb:-0}"
  row "$tag: exactly $WANT_SPANS END marker lines" "$([[ "${ne:-0}" -eq "$WANT_SPANS" ]] && echo ok)" "found ${ne:-0}"
  row "$tag: no near-miss BEGIN spelling (every mention is a marker line)" "$([[ "${nl:-0}" -eq "${nb:-0}" ]] && echo ok)" "loose ${nl:-0} vs exact ${nb:-0}"
  v="$(span_verdict "$file")"
  row "$tag: $WANT_SPANS well-formed spans, each at least its minimum size" "$([[ "$v" == OK ]] && echo ok)" "$v"
done
v="$(parity_verdict "$ORIG_PL" "$PLUGIN_PL")"
row "every span is byte-identical between the two lexers" "$([[ "$v" == OK ]] && echo ok)" "$v"
new_dir; DA="$NEWDIR"; new_dir; DB="$NEWDIR"
span_extract "$ORIG_PL" "$DA" >/dev/null 2>&1; span_extract "$PLUGIN_PL" "$DB" >/dev/null 2>&1
for i in 1 2 3; do
  if [[ -s "$DA/span.$i" && -s "$DB/span.$i" ]] && cmp -s "$DA/span.$i" "$DB/span.$i"; then ok=ok; else ok=no; fi
  row "span $i: non-empty and byte-identical" "$ok" "$(wc -c < "$DA/span.$i" 2>/dev/null || echo 0) vs $(wc -c < "$DB/span.$i" 2>/dev/null || echo 0) bytes"
done

# ---------------------------------------------------------------------------------------------
# C2. Mutations of COPIES of the real files (Guard 2 matrix rows 1-4, harness rows (a) and (b))
# ---------------------------------------------------------------------------------------------
echo "C2. in-suite mutations of copies"
new_dir; MU="$NEWDIR"
cp "$ORIG_PL" "$MU/orig.pl" 2>/dev/null; cp "$PLUGIN_PL" "$MU/plug.pl" 2>/dev/null
CONTROL="$(parity_verdict "$MU/orig.pl" "$MU/plug.pl")"
row "control: the unmutated copies compare equal (the mutation rows below are meaningful only if this is ok)" "$([[ "$CONTROL" == OK ]] && echo ok)" "$CONTROL"

# mutate <in> <out> <perl-substitution>: applies the edit and requires that it landed.
mutate() {
  perl -0pe "$3" "$1" > "$2" 2>/dev/null
  ! cmp -s "$1" "$2"
}
# expect_red <desc> <orig> <plug> [needle]: the control must be green, the verdict red (and name the needle).
expect_red() {
  local v
  if [[ "$CONTROL" != OK ]]; then row "$1" no "control is not green"; return 0; fi
  v="$(parity_verdict "$2" "$3")"
  if [[ "$v" == RED:* && ( -z "${4:-}" || "$v" == *"$4"* ) ]]; then row "$1" ok; else row "$1" no "$v"; fi
}
expect_ok() {
  local v
  if [[ "$CONTROL" != OK ]]; then row "$1" no "control is not green"; return 0; fi
  v="$(parity_verdict "$2" "$3")"
  if [[ "$v" == OK ]]; then row "$1" ok; else row "$1" no "$v"; fi
}

# 1. one character inside a span, plugin copy only (span 2: `sub charge`)
if mutate "$MU/plug.pl" "$MU/m1.pl" 's/\$USED > \$BUDGET/\$USED >= \$BUDGET/'; then
  expect_red "M1: one character changed inside a span of the plugin copy only" "$MU/orig.pl" "$MU/m1.pl" "differ: 2"
else row "M1: mutation landed" no "edit did not change the copy (or the control copy is missing)"; fi
# 2. the same, original copy only
if mutate "$MU/orig.pl" "$MU/m2.pl" 's/\$USED > \$BUDGET/\$USED >= \$BUDGET/'; then
  expect_red "M2: one character changed inside a span of the original copy only" "$MU/m2.pl" "$MU/plug.pl" "differ: 2"
else row "M2: mutation landed" no "edit did not change the copy (or the control copy is missing)"; fi
# 3. markers removed: from one file, and from both (empty spans on both sides must not compare equal)
if grep -vE '^# (BEGIN|END) SHARED-LEXER$' "$MU/plug.pl" > "$MU/m3a.pl" 2>/dev/null && ! cmp -s "$MU/plug.pl" "$MU/m3a.pl"; then
  expect_red "M3: markers removed from the plugin copy only" "$MU/orig.pl" "$MU/m3a.pl"
  grep -vE '^# (BEGIN|END) SHARED-LEXER$' "$MU/orig.pl" > "$MU/m3b.pl" 2>/dev/null
  expect_red "M3: markers removed from BOTH copies (empty spans on both sides)" "$MU/m3b.pl" "$MU/m3a.pl"
else
  row "M3: markers removed from the plugin copy only" no "no marker lines were removed (or the control copy is missing)"
  row "M3: markers removed from BOTH copies (empty spans on both sides)" no "mutation did not land"
fi
# 3c. one BEGIN dropped (an END is left without its BEGIN)
if mutate "$MU/plug.pl" "$MU/m3c.pl" 's/^# BEGIN SHARED-LEXER\n//m'; then
  expect_red "M3: a single BEGIN marker dropped from the plugin copy" "$MU/orig.pl" "$MU/m3c.pl"
else row "M3c: mutation landed" no "edit did not change the copy"; fi
# 3d. a fourth marker pair added around two lines of filing/plugin logic
if mutate "$MU/plug.pl" "$MU/m3d.pl" 's/^(sub process_command \{)/# BEGIN SHARED-LEXER\nmy \$extra = 1;\n# END SHARED-LEXER\n$1/m'; then
  expect_red "M3: a fourth marker pair added" "$MU/orig.pl" "$MU/m3d.pl"
else row "M3d: mutation landed" no "edit did not change the copy"; fi
# 4. a second divergence after a matching first: span 3 only (spans 1 and 2 match), then spans 2 and 3 together
if mutate "$MU/plug.pl" "$MU/m4a.pl" 's/return \$t->\[\$j\];/return \$t->[\$j] ;/'; then
  expect_red "M4: divergence in the LAST span only, after two matching spans" "$MU/orig.pl" "$MU/m4a.pl" "differ: 3"
  mutate "$MU/m4a.pl" "$MU/m4b.pl" 's/\$USED > \$BUDGET/\$USED >= \$BUDGET/'
  expect_red "M4: a divergence in span 2 AND span 3 reports both (every span is compared)" "$MU/orig.pl" "$MU/m4b.pl" "differ: 2 3"
else
  row "M4: divergence in the LAST span only, after two matching spans" no "edit did not change the copy"
  row "M4: a divergence in span 2 AND span 3 reports both (every span is compared)" no "mutation did not land"
fi
# (b) must-PASS: a change OUTSIDE the markers (inside process_command) compares equal, in either file
if mutate "$MU/plug.pl" "$MU/b1.pl" 's/^(sub process_command \{)/$1  # a change outside the shared spans/m'; then
  expect_ok "HARNESS (b): a change inside process_command of the plugin copy compares equal" "$MU/orig.pl" "$MU/b1.pl"
else row "HARNESS (b): mutation landed (plugin)" no "edit did not change the copy"; fi
if mutate "$MU/orig.pl" "$MU/b2.pl" 's/^(sub process_command \{)/$1  # a change outside the shared spans/m'; then
  expect_ok "HARNESS (b): a change inside process_command of the original copy compares equal" "$MU/b2.pl" "$MU/plug.pl"
else row "HARNESS (b): mutation landed (original)" no "edit did not change the copy"; fi

# ---------------------------------------------------------------------------------------------
# B. Grammar corpus: both lexers' --trace argv lines, plus a literal expectation per row
# ---------------------------------------------------------------------------------------------
echo "B. grammar corpus through both lexers' --trace"
CORPUS_N=0
# trace_of <lexer> <cmdfile>: stderr minus the filing lexer's per-filing detail lines (they start with blanks).
trace_of() { perl "$1" --trace < "$2" 2>&1 >/dev/null | grep -av '^  FILING' || true; }
corpus_row() { # corpus_row <name> <command text> <expected argv trace>
  local name="$1" cmd="$2" want="$3" f o p
  CORPUS_N=$((CORPUS_N + 1))
  f="$WORK/corpus.$CORPUS_N.cmd"
  printf '%s' "$cmd" > "$f"
  o="$(trace_of "$ORIG_PL" "$f")"
  p="$(trace_of "$PLUGIN_PL" "$f")"
  row "corpus [$name]: the original lexer reads the literal expected argv trace" "$([[ "$o" == "$want" ]] && echo ok)" "got: $o"
  row "corpus [$name]: the plugin lexer's argv trace equals the original's" "$([[ -n "$p" && "$p" == "$o" ]] && echo ok)" "plugin: $p"
}
NL=$'\n'
corpus_row "list split on &&" 'ls && terraform destroy' "top: [ls]${NL}top: [terraform] [destroy]"
corpus_row "bash -c unwrapped" "bash -c 'terraform destroy'" "top: [bash] [-c] [terraform destroy]${NL}top>shell-c: [terraform] [destroy]"
corpus_row "quoted text is one word" 'echo "terraform destroy"' 'top: [echo] [terraform destroy]'
corpus_row "substitution lexed once" 'echo $(terraform plan; true)' "top>subst: [terraform] [plan]${NL}top>subst: [true]${NL}"'top: [echo] [$(terraform plan; true)]'
corpus_row "heredoc then a real command" $'cat <<\'EOF\'\nterraform destroy\nEOF\nrm -rf x' "top: [cat]${NL}top: [rm] [-rf] [x]"
corpus_row "comment at word start" 'ls #x; terraform destroy' 'top: [ls]'
corpus_row "mid-word hash is not a comment" 'echo a#b; terraform destroy' "top: [echo] [a#b]${NL}top: [terraform] [destroy]"
corpus_row "pipeline with a redirect" 'terraform plan 2>&1 | tee log' "top: [terraform] [plan]${NL}top: [tee] [log]"
corpus_row "eval string re-lexed" 'eval "rm -rf ~"' "top: [eval] [rm -rf ~]${NL}top>eval: [rm] [-rf] [~]"
corpus_row "case pattern is not a command" 'case x in a) rm -rf /;; esac' 'top: [rm] [-rf] [/]'
corpus_row "arithmetic command, shift is not a heredoc" '(( 1 << 2 )); ls' 'top: [ls]'
corpus_row "backtick substitution" 'echo `terraform plan`' "top>backtick: [terraform] [plan]${NL}"'top: [echo] [`terraform plan`]'
corpus_row "ANSI-C quoting decoded" "r\$'m' -rf ~" 'top: [rm] [-rf] [~]'
corpus_row "backslash-escaped command name" '\rm -rf ~' 'top: [rm] [-rf] [~]'
corpus_row "if/then keywords" 'if true; then terraform destroy; fi' "top: [if] [true]${NL}top: [then] [terraform] [destroy]${NL}top: [fi]"
corpus_row "wrapper words kept" 'sudo -u x terraform destroy' 'top: [sudo] [-u] [x] [terraform] [destroy]'
corpus_row "substitution inside \${...}" 'echo ${X:-$(rm -rf ~)}' "top>subst: [rm] [-rf] [~]${NL}"'top: [echo] [${X:-$(rm -rf ~)}]'
corpus_row "assignment prefix and a brace group" 'x=1 env -i terraform destroy; { ls; }' "top: [x=1] [env] [-i] [terraform] [destroy]${NL}top: [{] [ls]${NL}top: [}]"
corpus_row "redirect dropped from argv, quoted tilde kept" "ls &> out; echo '~'" "top: [ls]${NL}top: [echo] [~]"
corpus_row "((x)) that is not arithmetic" 'echo ((x)) ; ls' "top: [echo]${NL}top: [x]${NL}top: [ls]"
corpus_row "arithmetic expansion and a subshell in a substitution" 'echo $((1+2)) $( (ls) )' "top>subst: [ls]${NL}"'top: [echo] [$((1+2))] [$( (ls) )]'
corpus_row "two commands, newline separated" $'ls\nterraform destroy' "top: [ls]${NL}top: [terraform] [destroy]"

# Bound and error framing: stdout bytes and exit status must match, and match the literal expectation.
err_row() { # err_row <name> <cmdfile> <expected rc> <expected stdout file>
  local name="$1" f="$2" wrc="$3" wout="$4" orc prc
  perl "$ORIG_PL" < "$f" > "$WORK/e.orig.out" 2>/dev/null; orc=$?
  perl "$PLUGIN_PL" < "$f" > "$WORK/e.plug.out" 2>/dev/null; prc=$?
  row "error [$name]: original exits $wrc with the framed cause" \
    "$([[ "$orc" -eq "$wrc" ]] && cmp -s "$WORK/e.orig.out" "$wout" && echo ok)" "rc=$orc"
  row "error [$name]: plugin exits $wrc with byte-identical framing" \
    "$([[ "$prc" -eq "$wrc" ]] && cmp -s "$WORK/e.plug.out" "$wout" && echo ok)" "rc=$prc"
}
printf 'E\0exit2\0' > "$WORK/want.exit2"
printf 'E\0depth\0' > "$WORK/want.depth"
printf '%s' "echo 'x" > "$WORK/err.quote"
err_row "unbalanced single quote" "$WORK/err.quote" 2 "$WORK/want.exit2"
printf 'a\0b' > "$WORK/err.nul"
err_row "NUL byte in the input" "$WORK/err.nul" 2 "$WORK/want.exit2"
printf '%s' 'echo $(ls' > "$WORK/err.subst"
err_row "unterminated substitution" "$WORK/err.subst" 2 "$WORK/want.exit2"
deep='x'; for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do deep="echo \$($deep)"; done
printf '%s' "$deep" > "$WORK/err.depth"
err_row "substitution nested past the depth bound" "$WORK/err.depth" 3 "$WORK/want.depth"

# ---------------------------------------------------------------------------------------------
# Summary and the vacuity floor
# ---------------------------------------------------------------------------------------------
echo "cases=$CASES passes=$passes fails=$fails"
if [[ $((passes + fails)) -ne "$CASES" ]]; then
  printf '[FATAL] anti-vacuity: %s verdicts recorded for %s cases\n' "$((passes + fails))" "$CASES" >&2; exit 1
fi
MIN_CASES=91
if [[ "$CASES" -lt "$MIN_CASES" ]]; then
  printf '[FATAL] anti-vacuity: only %s assertions ran, floor is %s\n' "$CASES" "$MIN_CASES" >&2
  exit 1
fi
[[ "$fails" -eq 0 ]]
