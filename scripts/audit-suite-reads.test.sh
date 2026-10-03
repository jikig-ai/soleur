#!/usr/bin/env bash
# audit-suite-reads.test.sh — Guard 1 of the always-on read recorder (#9307, PR-B / B1).
#
# PROPERTY. scripts/audit-suite-reads.sh never reports a suite `demotable` from an incomplete or
# unstable recording (queue overflow, failed watch, repeat disagreement, sentinel damage), from a
# non-zero exit, from a flagged probe, or from reads outside its cover.
#
# ASSEMBLY. Every verdict flows through the single `verdict()` function. This suite drives it two
# ways: (A) the `verdict` subcommand over SYNTHESIZED event streams (replay), and (B) the REAL reader
# (scripts/lib/inotify-open-recorder.py) and the REAL `record` path over fixture repositories whose
# fake runner emits SUITE_COMMAND / AFFECTED_SELECTED records. Every RED row asserts the exit code AND
# a message substring, so a crash cannot read as RED. Rows follow the Guard 1 mutation matrix in
# knowledge-base/project/plans/archive/20261003-160835-2026-10-02-chore-affected-gate-reprice-recorder-runner-leaf-plan.md
# (rows 1, 1b, 2..17) plus one row per review fix. The inotify arms need only python3 + ctypes (no
# inotify-tools). Section B also needs a network-less namespace tool (`unshare -rn true` or bwrap): the scripts
# job's runner support for that is UNVERIFIED, check with `unshare -rn true` on the runner. Without one the
# section hard-FAILs under CI (a counted skip locally), because a no-netns recording is `unreliable` by design.
#
# AUTHORING (work/SKILL.md): never `producer | grep -q` under pipefail (grep a file or use [[ == ]]);
# capture rc on its own line; verdict helpers are defined AFTER the one subshell that sources the
# script under test; scratch is mktemp-based with an owning EXIT trap. Section B and row 1b SKIP (counted
# in rows, loud) only when python3 ctypes inotify or a netns tool is unavailable, and FAIL under CI.

# shellcheck disable=SC2016  # fixture suite bodies and awk-free literals are single-quoted on purpose
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${AUDIT_SUITE_READS_SCRIPT:-$REPO_ROOT/scripts/audit-suite-reads.sh}"
READER="$REPO_ROOT/scripts/lib/inotify-open-recorder.py"
export TMPDIR="${TMPDIR:-/var/tmp}"
TESTROOT="$(mktemp -d -t audit-suite-reads.XXXXXXXX)" || exit 2

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
assert_fixture_dir "$TESTROOT"
BG_PIDS=""
# shellcheck disable=SC2329  # invoked through the EXIT trap
cleanup() {
  local p
  for p in $BG_PIDS; do kill -CONT "$p" 2>/dev/null; kill "$p" 2>/dev/null; done
  rm -rf -- "$TESTROOT"
}
trap cleanup EXIT INT TERM HUP

# The one place the script under test is SOURCED: read its disqualifier table (entries "name|regex").
DISQ_ENTRIES="$( (
  # shellcheck source=/dev/null
  source "$SCRIPT" >/dev/null 2>&1 || exit 1
  printf '%s\n' "${DISQ_TABLE[@]}"
) 2>/dev/null)"

# ---- verdict helpers (defined AFTER the sourcing above) --------------------------------------------
PASS=0; FAIL=0; cases=0; SKIPPED=0; SKIPPED_ROWS=0; SKIP_CAUSES=""
pass() { PASS=$((PASS + 1)); echo "  [ok] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1" >&2; }

# Instrument self-test: both verdict helpers must move their counters.
_sp=$PASS; _sf=$FAIL
pass "instrument self-test" >/dev/null 2>&1
fail "instrument self-test" >/dev/null 2>&1
if (( PASS != _sp + 1 )) || (( FAIL != _sf + 1 )); then
  echo "[FATAL] instrument self-test failed" >&2; exit 1
fi
PASS=$_sp; FAIL=$_sf

ok_if() { # ok_if <name> <rc-of-condition>
  cases=$((cases + 1))
  if [[ "$2" == 0 ]]; then pass "$1"; else fail "$1"; fi
}
skip_or_fail() { # skip_or_fail <why> <rows the skipped section holds> : a counted skip locally, a failure under CI
  if [[ -n "${CI:-}" ]]; then
    cases=$((cases + 1)); fail "$1 (cannot be skipped under CI)"
    SKIPPED_ROWS=$((SKIPPED_ROWS + $2 - 1)); SKIP_CAUSES="$SKIP_CAUSES [$1: $2 rows, one failing row stands for them]"
  else
    SKIPPED=$((SKIPPED + 1)); SKIPPED_ROWS=$((SKIPPED_ROWS + $2)); SKIP_CAUSES="$SKIP_CAUSES [$1: $2 rows]"
    echo "  [SKIP] $1 ($2 rows not run)"
  fi
}

have_python_inotify() {
  python3 -c 'import ctypes; ctypes.CDLL(None).inotify_init1' >/dev/null 2>&1
}

row_of() { # row_of <table-file> <label> -> the AUDIT_READS row for that label
  awk -F'\t' -v l="label=$2" '$1 == "AUDIT_READS" && $2 == l { print; exit }' "$1"
}

# expect_row <name> <want-rc> <label> <want-verdict> <needle-in-row>
expect_row() {
  local name=$1 wrc=$2 label=$3 wv=$4 needle=$5 row bad=""
  row="$(row_of "$OUT" "$label")"
  [[ "$RC" == "$wrc" ]] || bad="$bad rc=$RC(want $wrc)"
  [[ "$row" == *$'\t'"verdict=$wv"$'\t'* ]] || bad="$bad verdict-not-$wv"
  [[ "$row" == *"$needle"* ]] || bad="$bad missing[$needle]"
  cases=$((cases + 1))
  if [[ -z "$bad" ]]; then pass "$name"; else fail "$name:$bad :: row=[$row]"; fi
}
expect_err() { # expect_err <name> <want-rc> <stderr-needle>
  local bad=""
  [[ "$RC" == "$2" ]] || bad="$bad rc=$RC(want $2)"
  [[ "$(cat "$ERR")" == *"$3"* ]] || bad="$bad stderr-missing[$3]"
  cases=$((cases + 1))
  if [[ -z "$bad" ]]; then pass "$1"; else fail "$1:$bad :: $(head -c 300 "$ERR")"; fi
}

# ---- replay builders ---------------------------------------------------------------------------------
NONCE="n0nce$$x"
FAKE_REV="0123456789abcdef0123456789abcdef01234567"
RUNN=0; WIN=0; WNOTE=""   # WNOTE: the optional 10th meta field (contamination note) emit_win stamps
new_run() {
  RUNN=$((RUNN + 1)); RUN="$TESTROOT/run.$RUNN"
  mkdir -p "$RUN/root/data" "$RUN/root/.audit-sentinels"
  : > "$RUN/events"; printf 'ready\n' > "$RUN/reader.err"
  printf 'NONCE\t%s\nREV\t%s\n' "$NONCE" "$FAKE_REV" > "$RUN/meta"
  WIN=0
}
mksuite() { # mksuite <relpath> <line>...
  local f="$RUN/root/$1"; shift
  mkdir -p "$(dirname "$f")"; printf '%s\n' "$@" > "$f"
}
# emit_win <label> <rep> <rc> <flag> <cover> <files> [event]...   event: path | D:path | C:path | Q | RAW:line
emit_win() {
  local label=$1 rep=$2 rc=$3 flag=$4 cover=$5 files=$6 e
  shift 6
  WIN=$((WIN + 1))
  printf 'W\t%s\t%s\t%s\t%s\t%s\t0.50\t%s\t%s\t%s\n' "$WIN" "$label" "$rep" "$rc" "$flag" "$cover" "$files" "${WNOTE:--}" >> "$RUN/meta"
  printf 'O\t.audit-sentinels/%s-start-%s\n' "$NONCE" "$WIN" >> "$RUN/events"
  for e in "$@"; do
    case "$e" in
      D:*) printf 'D\t%s\n' "${e#D:}" ;;
      C:*) printf 'C\t%s\n' "${e#C:}" ;;
      RAW:*) printf '%s\n' "${e#RAW:}" ;;
      Q) printf 'Q\n' ;;
      *) printf 'O\t%s\n' "$e" ;;
    esac >> "$RUN/events"
  done
  printf 'O\t.audit-sentinels/%s-end-%s\n' "$NONCE" "$WIN" >> "$RUN/events"
}
# pair <slug> <cover> <event>...  : two agreeing recordings of suite <slug>.sh (rc 0)
pair() {
  local slug=$1 cover=$2; shift 2
  emit_win "$slug" 1 0 - "$cover" "$slug.sh" "$@"
  emit_win "$slug" 2 0 - "$cover" "$slug.sh" "$@"
}
run_verdict() {
  OUT="$RUN/out"; ERR="$RUN/err"
  bash "$SCRIPT" verdict --events "$RUN/events" --reader-err "$RUN/reader.err" --meta "$RUN/meta" \
    --root "$RUN/root" ${1+"$@"} >"$OUT" 2>"$ERR"
  RC=$?
}

# ---- reject controls for the three assertion helpers (printf + exit; never through the helpers) ----------
# Each helper is driven once with a deliberately WRONG input and must register exactly one failure (and no
# pass); one right input must register exactly one pass. Counters are then restored exactly, so these drives are
# not rows. A helper that always passes, or one that lost its rc / verdict / needle clause, dies here.
RCDIR="$TESTROOT/rcontrol"; mkdir -p "$RCDIR"
printf 'AUDIT_READS\tlabel=lbl\tverdict=demotable\treason=ok\tfiles=1\n' > "$RCDIR/out"
printf 'a real stderr needle\n' > "$RCDIR/err"
control() { # control <accept|reject> <name> <helper> <args...>
  local kind=$1 name=$2 p0=$PASS f0=$FAIL c0=$cases wp wf
  shift 2
  OUT="$RCDIR/out"; ERR="$RCDIR/err"; RC=0
  "$@" >/dev/null 2>&1
  if [[ "$kind" == reject ]]; then wp=0; wf=1; else wp=1; wf=0; fi
  if (( PASS != p0 + wp || FAIL != f0 + wf || cases != c0 + 1 )); then
    printf '[FATAL] reject-control %s (%s): PASS %s->%s FAIL %s->%s cases %s->%s, want pass+%s fail+%s cases+1\n' \
      "$name" "$kind" "$p0" "$PASS" "$f0" "$FAIL" "$c0" "$cases" "$wp" "$wf" >&2
    exit 1
  fi
  PASS=$p0; FAIL=$f0; cases=$c0
}
control accept "ok_if right input"              ok_if "x" 0
control reject "ok_if wrong rc"                 ok_if "x" 1
control accept "expect_row right input"         expect_row "x" 0 lbl demotable "reason=ok"
control reject "expect_row wrong rc"            expect_row "x" 3 lbl demotable "reason=ok"
control reject "expect_row wrong verdict"       expect_row "x" 0 lbl uncovered "reason=ok"
control reject "expect_row wrong needle"        expect_row "x" 0 lbl demotable "reason=NOT-THERE"
control reject "expect_row missing label"       expect_row "x" 0 nolabel demotable "reason=ok"
control accept "expect_err right input"         expect_err "x" 0 "a real stderr needle"
control reject "expect_err wrong rc"            expect_err "x" 2 "a real stderr needle"
control reject "expect_err wrong needle"        expect_err "x" 0 "a needle that is not there"

echo "== A. replay: verdict() over synthesized streams =="

# Row 0 (positive control): a compliant suite is demotable; the revision is stamped into the row.
new_run
mksuite good.sh 'cat data/a.txt'
pair good 'good.sh|data/a.txt' good.sh data/a.txt
run_verdict
expect_row "row 0: compliant suite is demotable" 0 good demotable "rev=$FAKE_REV"
expect_row "row 0: mode stamped" 0 good demotable "mode=demote"

# Row 1: IN_Q_OVERFLOW inside a suite window; and one only in the gap that follows a window.
new_run
mksuite ovin.sh 'cat data/a.txt'; mksuite ovgap.sh 'cat data/a.txt'; mksuite after.sh 'cat data/a.txt'
emit_win ovin 1 0 - 'ovin.sh|data/a.txt' ovin.sh ovin.sh data/a.txt Q
emit_win ovin 2 0 - 'ovin.sh|data/a.txt' ovin.sh ovin.sh data/a.txt
pair ovgap 'ovgap.sh|data/a.txt' ovgap.sh data/a.txt
printf 'Q\n' >> "$RUN/events"          # lands in the gap after ovgap's second window
pair after 'after.sh|data/a.txt' after.sh data/a.txt
run_verdict
expect_row "row 1: overflow inside window -> unreliable (rc 3)" 3 ovin unreliable "reason=q_overflow"
expect_row "row 1: overflow only in the following gap -> unreliable" 3 ovgap unreliable "reason=q_overflow_gap"
expect_row "row 1: the suite AFTER the gap is unaffected (table still written)" 3 after demotable "reason=ok"

# Row 2: `Failed to watch` on reader stderr -> every suite unreliable. Also: reader never became ready.
new_run
mksuite g1.sh 'cat data/a.txt'; mksuite g2.sh 'cat data/a.txt'
pair g1 'g1.sh|data/a.txt' g1.sh data/a.txt
pair g2 'g2.sh|data/a.txt' g2.sh data/a.txt
printf 'ready\nFailed to watch /x/y\n' > "$RUN/reader.err"
run_verdict
expect_row "row 2: failed watch -> first suite unreliable" 3 g1 unreliable "reason=watch_failed"
expect_row "row 2: failed watch -> second suite unreliable" 3 g2 unreliable "reason=watch_failed"
printf 'nothing\n' > "$RUN/reader.err"
run_verdict
expect_row "row 2b: reader never printed ready -> unreliable" 3 g1 unreliable "reason=reader_not_ready"

# Row 3: a file test outside the cover (the open-event stream cannot see it) -> disqualified.
new_run
mksuite probe.sh 'cat data/a.txt' '[[ -e some/missing/path ]] && echo there'
pair probe 'probe.sh|data/a.txt' probe.sh data/a.txt
run_verdict
expect_row "row 3: [[ -e missing ]] outside the cover -> disqualified" 0 probe disqualified "probe:some/missing/path"
expect_row "row 3: reason is probe" 0 probe disqualified "reason=probe"

# Row 4: every suite is scanned, not just the first one.
new_run
mksuite first.sh 'cat data/a.txt'; mksuite second.sh 'cat data/a.txt' 'test -f nope/x'
mksuite third.sh 'cat data/a.txt' 'ls elsewhere/dir'
pair first 'first.sh|data/a.txt' first.sh data/a.txt
pair second 'second.sh|data/a.txt' second.sh data/a.txt
pair third 'third.sh|data/a.txt' third.sh data/a.txt
run_verdict
expect_row "row 4: compliant first suite stays demotable" 0 first demotable "reason=ok"
expect_row "row 4: probing second suite is disqualified" 0 second disqualified "probe:nope/x"
expect_row "row 4: a later ls probe is disqualified too" 0 third disqualified "probe:elsewhere/dir"

# Row 5: zero suites enumerated, and (separately) zero windows -> exit 4, distinct messages, not usage 2.
new_run
run_verdict
expect_err "row 5: zero suites enumerated -> exit 4" 4 "zero suites enumerated"
new_run
mksuite z.sh 'true'
printf 'W\t1\tz\t1\t0\t-\t0.5\tz.sh\tz.sh\n' >> "$RUN/meta"
run_verdict
expect_err "row 5: zero windows recorded -> exit 4" 4 "zero windows"
bash "$SCRIPT" verdict >/dev/null 2>"$TESTROOT/usage.err"; RC=$?; ERR="$TESTROOT/usage.err"
expect_err "row 5: usage error is exit 2 (not 4)" 2 "usage"

# Row 6: one read outside the cover and nothing else -> exactly uncovered, path listed.
new_run
mksuite unc.sh 'cat data/a.txt data/other.txt'
pair unc 'unc.sh|data/a.txt' unc.sh data/a.txt data/other.txt
run_verdict
expect_row "row 6: read outside cover -> uncovered" 0 unc uncovered "data/other.txt"
expect_row "row 6: reason is reads-outside-cover" 0 unc uncovered "reason=reads-outside-cover"

# Row 7: non-zero exit and exit 124 -> unreliable.
new_run
mksuite rcn.sh 'exit 3'; mksuite rct.sh 'sleep 999'
emit_win rcn 1 3 - 'rcn.sh' rcn.sh rcn.sh
emit_win rct 1 124 - 'rct.sh' rct.sh rct.sh
run_verdict
expect_row "row 7: rc 3 -> unreliable rc" 3 rcn unreliable "reason=rc"
expect_row "row 7: rc 124 -> unreliable timeout" 3 rct unreliable "reason=timeout"

# Row 8: two recordings of one suite disagree on the opened set (the extra read is covered).
new_run
mksuite flaky.sh 'cat data/a.txt'
emit_win flaky 1 0 - 'flaky.sh|data/a.txt|data/b.txt' flaky.sh flaky.sh data/a.txt
emit_win flaky 2 0 - 'flaky.sh|data/a.txt|data/b.txt' flaky.sh flaky.sh data/a.txt data/b.txt
run_verdict
expect_row "row 8: repeat disagreement -> unreliable" 3 flaky unreliable "reason=repeat_disagree"

# Row 9: one fixture per entry of the carried-disqualifier table.
declare_sample() { # declare_sample <entry-name> -> a suite line the entry's regex must match
  case "$1" in
    git-diff) echo 'git diff --stat' ;;           git-log) echo 'git log -1' ;;
    git-show) echo 'git show HEAD' ;;             git-rev-list) echo 'git rev-list HEAD' ;;
    git-merge-base) echo 'git merge-base a b' ;;  git-status) echo 'git status --short' ;;
    git-ls-files) echo 'git ls-files' ;;          git-ls-tree) echo 'git ls-tree HEAD' ;;
    git-other) echo 'git cat-file -p HEAD' ;;
    origin-main) echo 'echo origin/main' ;;       changed-flag) echo 'run --changed' ;;
    base-flag) echo 'run --base HEAD' ;;          net-curl) echo 'curl -s https://x.invalid' ;;
    net-gh) echo 'gh api repos/x' ;;              net-doppler) echo 'doppler run -- x' ;;
    net-ssh) echo 'ssh host true' ;;               clock-date) echo 'now=$(date +%s)' ;;
    clock-epoch) echo 'echo $EPOCHSECONDS' ;;     net-other) echo 'ping -c1 x.invalid' ;;
    *) echo "" ;;
  esac
}
# A SECOND, differently shaped realistic line per entry (options before the verb, other verbs, other tools).
declare_sample2() {
  case "$1" in
    git-diff) echo 'git -C x diff --stat' ;;      git-log) echo 'git --no-pager log -1' ;;
    git-show) echo 'git -C r show HEAD:f' ;;      git-rev-list) echo 'git rev-list --count HEAD' ;;
    git-merge-base) echo 'git -C x merge-base --is-ancestor a b' ;;
    git-status) echo 'git -C x status -s' ;;      git-ls-files) echo 'git -C x ls-files -z' ;;
    git-ls-tree) echo 'git ls-tree -r HEAD' ;;    git-other) echo 'git -C x for-each-ref refs/heads' ;;
    origin-main) echo 'base=origin/main' ;;       changed-flag) echo 'run --changed=x' ;;
    base-flag) echo 'run --base=HEAD' ;;          net-curl) echo 'wget https://x.invalid' ;;
    net-gh) echo 'gh pr list' ;;                  net-doppler) echo 'doppler secrets get X' ;;
    net-ssh) echo 'scp a host:b' ;;               clock-date) echo 'date' ;;
    clock-epoch) echo 'echo $EPOCHREALTIME' ;;    net-other) echo 'npx tsc' ;;
    *) echo "" ;;
  esac
}
n_entries=0; n_missing_sample=0
new_run
declare -a ENTRY_NAMES
ENTRY_NAMES=()
while IFS= read -r entry; do
  [[ -n "$entry" ]] || continue
  name="${entry%%|*}"
  sample="$(declare_sample "$name")"
  if [[ -z "$sample" ]]; then n_missing_sample=$((n_missing_sample + 1)); echo "  no fixture sample for table entry [$name]" >&2; continue; fi
  sample2="$(declare_sample2 "$name")"
  if [[ -z "$sample2" ]]; then n_missing_sample=$((n_missing_sample + 1)); echo "  no SECOND fixture sample for table entry [$name]" >&2; continue; fi
  n_entries=$((n_entries + 1)); ENTRY_NAMES[${#ENTRY_NAMES[@]}]="$name"
  mksuite "rx_$name.sh" 'cat data/a.txt' "$sample"
  pair "rx_$name" "rx_$name.sh|data/a.txt" "rx_$name.sh" data/a.txt
  mksuite "rx2_$name.sh" 'cat data/a.txt' "$sample2"
  pair "rx2_$name" "rx2_$name.sh|data/a.txt" "rx2_$name.sh" data/a.txt
done <<EOF
$DISQ_ENTRIES
EOF
run_verdict
cases=$((cases + 1))
# exactly the pinned table (membership, not just size): a new/removed entry must come with its samples here
EXPECT_ENTRIES="git-diff git-log git-show git-rev-list git-merge-base git-status git-ls-files git-ls-tree git-other origin-main changed-flag base-flag net-curl net-gh net-other net-doppler net-ssh clock-date clock-epoch"
if [[ " ${ENTRY_NAMES[*]} " == " $EXPECT_ENTRIES " ]] && (( n_missing_sample == 0 )); then pass "row 9: the table is exactly the $n_entries pinned entries and each has two fixture samples"
else fail "row 9: table membership/sample coverage (entries=[${ENTRY_NAMES[*]}] missing-sample=$n_missing_sample)"; fi
for name in ${ENTRY_NAMES[@]+"${ENTRY_NAMES[@]}"}; do
  expect_row "row 9: [$name] -> disqualified" 0 "rx_$name" disqualified "regex:$name"
  expect_row "row 9: [$name] second-shape sample -> disqualified" 0 "rx2_$name" disqualified "regex:$name"
done
# deleting a table entry reds its own fixture (scratch copy of the script, landed check by md5 + line count)
mkdir -p "$TESTROOT/mut/scripts/lib"
cp "$READER" "$TESTROOT/mut/scripts/lib/inotify-open-recorder.py"
for name in ${ENTRY_NAMES[@]+"${ENTRY_NAMES[@]}"}; do
  M="$TESTROOT/mut/scripts/audit-suite-reads.sh"
  grep -vF -- "  \"$name|" "$SCRIPT" > "$M"
  before=$(wc -l < "$SCRIPT"); after=$(wc -l < "$M")
  lm=0; [[ $((before - after)) == 1 ]] || lm=1
  [[ "$(md5sum < "$SCRIPT")" != "$(md5sum < "$M")" ]] || lm=1
  ok_if "row 9: deleting [$name] landed (exactly one line, md5 differs)" "$lm"
  OUT="$RUN/out.mut"; ERR="$RUN/err.mut"
  bash "$M" verdict --events "$RUN/events" --reader-err "$RUN/reader.err" --meta "$RUN/meta" --root "$RUN/root" >"$OUT" 2>"$ERR"; RC=$?
  row="$(row_of "$OUT" "rx_$name")"
  mm=0; [[ "$row" != *"regex:$name"* ]] || mm=1
  ok_if "row 9: with [$name] deleted its fixture no longer flags regex:$name" "$mm"
  row="$(row_of "$OUT" "rx2_$name")"
  mm=0; [[ "$row" != *"regex:$name"* ]] || mm=1
  ok_if "row 9: with [$name] deleted its second-shape fixture no longer flags regex:$name" "$mm"
done

# Row 10: size caps, each boundary pair (exactly at the cap passes; one over is disqualified).
build_dirs_run() { # <n data dirs> : reads suite.sh + n distinct d<i>/f files, cover lists them as files
  local n=$1 i cover="d.sh" ev="d.sh"
  new_run; mksuite d.sh 'true'
  for ((i = 1; i <= n; i++)); do cover="$cover|d$i/sub/f"; ev="$ev d$i/sub/f"; done
  # shellcheck disable=SC2086
  pair d "$cover" $ev
}
build_dirs_run 7; run_verdict
expect_row "row 10: 8 second-level dirs (the cap) -> demotable" 0 d demotable "dirs=8"
build_dirs_run 8; run_verdict
expect_row "row 10: 9 second-level dirs -> disqualified broad" 0 d disqualified "reason=broad"
build_files_run() { # <n files> in one cover dir
  local n=$1 i ev="" ; local -a evs
  new_run; mksuite f.sh 'true'
  evs=(f.sh)
  for ((i = 1; i <= n; i++)); do evs[${#evs[@]}]="big/sub/f$i"; done
  pair f 'f.sh|big/' "${evs[@]}"
}
build_files_run 699; run_verdict
expect_row "row 10: 700 files (the cap) -> demotable" 0 f demotable "files=700"
build_files_run 700; run_verdict
expect_row "row 10: 701 files -> disqualified broad" 0 f disqualified "reason=broad"
build_cover_run() { # <n cover edges>
  local n=$1 i cover="c.sh"
  new_run; mksuite c.sh 'true'
  for ((i = 2; i <= n; i++)); do cover="$cover|unread$i.txt"; done
  pair c "$cover" c.sh
}
build_cover_run 14; run_verdict
expect_row "row 10: cover of 14 edges (the cap) -> demotable" 0 c demotable "cover=14"
build_cover_run 15; run_verdict
expect_row "row 10: cover of 15 edges -> disqualified wide-cover" 0 c disqualified "reason=wide-cover"

# Row 11: the same oversized reads/cover in check mode apply no cap; vocabulary is covered/uncovered/unreliable.
build_cover_run 15; run_verdict --mode check
expect_row "row 11: check mode, 15-edge cover -> covered (no cap)" 0 c covered "reason=ok"
build_files_run 700; run_verdict --mode check
expect_row "row 11: check mode, 701 files -> covered (no cap)" 0 f covered "files=701"
build_dirs_run 8; run_verdict --mode check
expect_row "row 11: check mode, 9 dirs -> covered (no cap)" 0 d covered "dirs=9"
cases=$((cases + 1))
if [[ "$(cat "$OUT")" != *demotable* ]] && [[ "$(cat "$OUT")" != *disqualified* ]]; then pass "row 11: check mode never says demotable/disqualified"
else fail "row 11: check-mode output holds demotable/disqualified"; fi
new_run; mksuite k.sh 'git diff' 'cat data/a.txt'; pair k 'k.sh|data/a.txt' k.sh data/a.txt data/zzz
run_verdict --mode check
expect_row "row 11: check mode, read outside cover -> uncovered" 0 k uncovered "data/zzz"
expect_row "row 11: check mode reports the carried disqualifier as info only" 0 k uncovered "regex:git-diff"
new_run; mksuite k.sh 'cat data/a.txt'; emit_win k 1 0 - 'k.sh|data/a.txt' k.sh k.sh data/a.txt Q
run_verdict --mode check
expect_row "row 11: check mode, overflow -> unreliable" 3 k unreliable "reason=q_overflow"

# Row 12 (replay half): a window the recorder refused for load carries the flag.
new_run; mksuite l.sh 'true'
printf 'W\t1\tl\t1\t-\tload_refused\t99.00\tl.sh\tl.sh\n' >> "$RUN/meta"
run_verdict
expect_row "row 12: load_refused flag -> unreliable" 3 l unreliable "reason=load_refused"

# Row 13: a directory created during the suite -> disqualified.
new_run; mksuite mk.sh 'mkdir -p newdir' 'cat data/a.txt'
pair mk 'mk.sh|data/a.txt' mk.sh data/a.txt C:newdir
run_verdict
expect_row "row 13: directory created mid-suite -> disqualified" 0 mk disqualified "reason=created-dir"

# Row 14: back-to-back windows keep their own events; sentinel damage makes the row unreliable.
new_run; mksuite wa.sh 'cat data/a.txt'; mksuite wb.sh 'cat data/b.txt'
pair wa 'wa.sh|data/a.txt' wa.sh data/a.txt
pair wb 'wb.sh|data/b.txt' wb.sh data/b.txt
run_verdict
expect_row "row 14: adjacent window A keeps only its own events" 0 wa demotable "reason=ok"
expect_row "row 14: adjacent window B keeps only its own events" 0 wb demotable "reason=ok"
new_run; mksuite sm.sh 'cat data/a.txt'
emit_win sm 1 0 - 'sm.sh|data/a.txt' sm.sh sm.sh data/a.txt
# drop the end sentinel of window 1
grep -vF -- "-end-1" "$RUN/events" > "$RUN/events.cut"; mv "$RUN/events.cut" "$RUN/events"
run_verdict
expect_row "row 14: missing end sentinel -> unreliable" 3 sm unreliable "reason=sentinel"
new_run; mksuite sd.sh 'cat data/a.txt'
emit_win sd 1 0 - 'sd.sh|data/a.txt' sd.sh sd.sh data/a.txt
printf 'O\t.audit-sentinels/%s-start-1\n' "$NONCE" >> "$RUN/events"   # duplicated start sentinel
run_verdict
expect_row "row 14: duplicated sentinel -> unreliable" 3 sd unreliable "reason=sentinel"
new_run; mksuite sw.sh 'cat data/a.txt'
emit_win sw 1 0 - 'sw.sh|data/a.txt' sw.sh sw.sh data/a.txt "RAW:O"$'\t'".audit-sentinels/${NONCE}-start-9"
run_verdict
expect_row "row 14: a stray sentinel inside a window -> unreliable" 3 sw unreliable "reason=sentinel"
new_run; mksuite mf.sh 'cat data/a.txt'
emit_win mf 1 0 - 'mf.sh|data/a.txt' mf.sh mf.sh data/a.txt "RAW:garbage-line"
run_verdict
expect_row "row 14b: malformed event line -> unreliable" 3 mf unreliable "reason=malformed"

# Row 17 (must-PASS, non-canonical): reads are a strict subset of a differently ordered cover; the only
# file tests are on that cover.
new_run
mksuite sub.sh 'cat data/z.txt data/a.txt' '[[ -f data/a.txt ]] && [ -d data ]'
pair sub 'data/unused.txt|data/a.txt|sub.sh|data/z.txt' data/z.txt data/a.txt sub.sh
run_verdict
expect_row "row 17: strict-subset reads, reordered cover, probes on the cover -> demotable" 0 sub demotable "reason=ok"

# ---- review-fix rows, replay half ---------------------------------------------------------------------
# Row 18: a window start without the previous end marks the stuck window bad and still begins the next one.
new_run; mksuite l1.sh 'cat data/a.txt'; mksuite l2.sh 'cat data/a.txt'; mksuite l3.sh 'cat data/a.txt'
emit_win l1 1 0 - 'l1.sh|data/a.txt' l1.sh l1.sh data/a.txt Q
emit_win l2 1 0 - 'l2.sh|data/a.txt' l2.sh l2.sh data/a.txt
emit_win l3 1 0 - 'l3.sh|data/a.txt' l3.sh l3.sh data/a.txt
grep -vF -- "-end-1" "$RUN/events" > "$RUN/events.cut"; mv "$RUN/events.cut" "$RUN/events"
run_verdict
expect_row "row 18: start-1 O Q start-2..end-2 start-3..end-3 -> l1 unreliable" 3 l1 unreliable "verdict=unreliable"
expect_row "row 18: ... the next window is not swallowed (l2 decided)" 3 l2 demotable "reason=ok"
expect_row "row 18: ... nor the one after it (l3 decided)" 3 l3 demotable "reason=ok"
new_run; mksuite l1.sh 'cat data/a.txt'; mksuite l2.sh 'cat data/a.txt'
emit_win l1 1 0 - 'l1.sh|data/a.txt' l1.sh l1.sh data/a.txt
emit_win l2 1 0 - 'l2.sh|data/a.txt' l2.sh l2.sh data/a.txt
grep -vF -- "-end-1" "$RUN/events" > "$RUN/events.cut"; mv "$RUN/events.cut" "$RUN/events"
run_verdict
expect_row "row 18: without a Q the stuck window is a sentinel fault" 3 l1 unreliable "reason=sentinel"
expect_row "row 18: and the next window is still decided" 3 l2 demotable "reason=ok"

# Row 19: a watched directory moved/deleted (X<TAB>path record) -> unreliable dir-moved; the bare X stays malformed.
new_run; mksuite mv.sh 'mv d1 d2'
emit_win mv 1 0 - 'mv.sh|data/a.txt' mv.sh mv.sh data/a.txt "RAW:X"$'\t'"d1"
run_verdict
expect_row "row 19: X<TAB>path inside a window -> unreliable dir-moved" 3 mv unreliable "reason=dir-moved"
new_run; mksuite mg.sh 'rmdir d1'
pair mg 'mg.sh|data/a.txt' mg.sh data/a.txt
printf 'X\td1\n' >> "$RUN/events"          # lands in the gap after mg's second window
mksuite mh.sh 'true'
pair mh 'mh.sh' mh.sh
run_verdict
expect_row "row 19: X<TAB>path only in the following gap -> the PREVIOUS window is unreliable" 3 mg unreliable "reason=dir-moved"
expect_row "row 19: the suite after the gap is unaffected" 3 mh demotable "reason=ok"
new_run; mksuite mx.sh 'true'
emit_win mx 1 0 - 'mx.sh' mx.sh mx.sh "RAW:X"
run_verdict
expect_row "row 19: a bare X (path with TAB/NEWLINE) stays malformed" 3 mx unreliable "reason=malformed"

# Row 20: contamination notes and a no-network recording.
new_run; mksuite cn.sh 'true'
WNOTE="dirty:data/x.log,y.txt,z" emit_win cn 1 0 contaminated 'cn.sh' cn.sh
run_verdict
expect_row "row 20: contaminated window names its dirty paths" 3 cn unreliable "dirty:data/x.log,y.txt,z"
new_run; mksuite cg.sh 'true'
WNOTE="git-config" emit_win cg 1 0 contaminated 'cg.sh' cg.sh
run_verdict
expect_row "row 20: a changed .git/config reads detail=git-config" 3 cg unreliable "detail=git-config"
expect_row "row 20: ... under reason=contaminated" 3 cg unreliable "reason=contaminated"
new_run; mksuite nn.sh 'cat data/a.txt'
pair nn 'nn.sh|data/a.txt' nn.sh data/a.txt
run_verdict
expect_row "row 20: control - no NETNS line, a decided suite stays demotable" 0 nn demotable "reason=ok"
printf 'NETNS\tunshare\n' >> "$RUN/meta"; run_verdict
expect_row "row 20: control - NETNS=unshare stays demotable" 0 nn demotable "reason=ok"
printf 'NETNS\tnone\n' >> "$RUN/meta"; run_verdict
expect_row "row 20: NETNS=none -> every decided row is unreliable no-netns" 3 nn unreliable "reason=no-netns"

# Row 21: a tracked symlink used as the suite file is disqualified, never followed out of the root.
new_run
printf '[ -f OUTSIDE-FILE-LINE ]\n' > "$RUN/outside.sh"
ln -s "$RUN/outside.sh" "$RUN/root/sl.sh"
pair sl 'sl.sh|data/a.txt' sl.sh data/a.txt
run_verdict
expect_row "row 21: symlinked suite file -> disqualified symlink" 0 sl disqualified "reason=symlink"
cases=$((cases + 1))
if [[ "$(cat "$OUT")" != *OUTSIDE-FILE-LINE* ]]; then pass "row 21: nothing from outside the root leaks into the table"; else fail "row 21: the symlink target was scanned"; fi
# replay meta paths: absolute or .. suite-file paths are refused like `record` refuses them
for badpath in "../outside.sh" "/etc/hostname"; do
  new_run; mksuite bp.sh 'true'
  printf 'W\t1\tbp\t1\t0\t-\t0.5\t-\t%s\n' "$badpath" >> "$RUN/meta"
  printf 'O\t.audit-sentinels/%s-start-1\nO\t.audit-sentinels/%s-end-1\n' "$NONCE" "$NONCE" > "$RUN/events"
  run_verdict
  expect_err "row 21: replay meta suite-file path [$badpath] -> exit 2" 2 "refusing"
done

# Row 22: second-level directory count counts directories only (a depth-2 file lives in its parent directory).
new_run; mksuite d.sh 'true'
cover="d.sh|big/x|big/y"; ev="d.sh big/x big/y"
for i in 1 2 3 4 5 6; do cover="$cover|d$i/sub/f"; ev="$ev d$i/sub/f"; done
# shellcheck disable=SC2086
pair d "$cover" $ev
run_verdict
expect_row "row 22: top-level file + big/x,big/y + 6 nested dirs = 8 directories (cap) -> demotable" 0 d demotable "dirs=8"
new_run; mksuite d.sh 'true'
cover="d.sh"; ev="d.sh"
for i in 1 2 3 4 5 6 7 8 9; do cover="$cover|big/d$i/f"; ev="$ev big/d$i/f"; done
# shellcheck disable=SC2086
pair d "$cover" $ev
run_verdict
expect_row "row 22: big/d1..d9/f is 9 second-level directories + the root -> disqualified broad" 0 d disqualified "reason=broad"

# Row 23: `_v_covered` (probes) and UNCOVERED_AWK (listings) differ on "parent directory of a covered file": pin both.
new_run; mksuite par.sh '[ -d data ] && cat data/a.txt'
pair par 'par.sh|data/a.txt' par.sh data/a.txt
run_verdict
expect_row "row 23: a [ -d data ] probe is covered by cover data/a.txt (parent of a covered file)" 0 par demotable "reason=ok"
new_run; mksuite parl.sh 'cat data/a.txt'
pair parl 'parl.sh|data/a.txt' parl.sh data/a.txt D:data
run_verdict
expect_row "row 23: a listing (D data) of the parent of a covered file is uncovered" 0 parl uncovered "detail=data"

# Row 24: cover near-misses (replay).
new_run; mksuite nm.sh 'cat data/a.txt'
pair nm 'nm.sh|data/a.txt' nm.sh data/a.txt data/a.txt.bak
run_verdict
expect_row "row 24: data/a.txt.bak is not covered by data/a.txt" 0 nm uncovered "data/a.txt.bak"
new_run; mksuite np1.sh '[[ -e data/a ]]' 'cat data/a.txt'
pair np1 'np1.sh|data/a.txt' np1.sh data/a.txt
run_verdict
expect_row "row 24: probe [[ -e data/a ]] (a prefix of the covered file) -> disqualified" 0 np1 disqualified "probe:data/a"
new_run; mksuite np2.sh '[ -d dat ]' 'cat data/a.txt'
pair np2 'np2.sh|data/a.txt' np2.sh data/a.txt
run_verdict
expect_row "row 24: probe [ -d dat ] -> disqualified" 0 np2 disqualified "probe:dat"
new_run; mksuite np3.sh '[[ -e other/x ]]' 'cat data/a.txt'
pair np3 'np3.sh|data/' np3.sh data/a.txt
run_verdict
expect_row "row 24: probe [[ -e other/x ]] with the directory cover data/ -> disqualified" 0 np3 disqualified "probe:other/x"
new_run; mksuite np4.sh '[[ -e data/sub/y ]]' 'cat data/a.txt'
pair np4 'np4.sh|data/' np4.sh data/a.txt
run_verdict
expect_row "row 24: probe under the directory cover data/ stays demotable" 0 np4 demotable "reason=ok"

# Row 25: directory-open (D) events.
new_run; mksuite dsl.sh 'cat data/a.txt' 'for f in other/*; do :; done'
pair dsl 'dsl.sh|data/a.txt' dsl.sh data/a.txt D:other
run_verdict
expect_row "row 25: a D event outside the cover -> uncovered" 0 dsl uncovered "other"
new_run; mksuite dd.sh 'cat data/a.txt'
emit_win dd 1 0 - 'dd.sh|data/a.txt|data/' dd.sh dd.sh data/a.txt
emit_win dd 2 0 - 'dd.sh|data/a.txt|data/' dd.sh dd.sh data/a.txt D:data
run_verdict
expect_row "row 25: two recordings differing only in a D event -> repeat_disagree" 3 dd unreliable "reason=repeat_disagree"
new_run; mksuite dc.sh 'cat data/a.txt'
pair dc 'dc.sh|data/' dc.sh data/a.txt D:data
run_verdict
expect_row "row 25: a D event inside a directory cover is covered" 0 dc demotable "reason=ok"

# Row 26: unresolved probe operand, probes in a later code file, find/stat probes, ./ on the cover, no code file.
new_run; mksuite ur.sh 'cat data/a.txt' '[[ -e "$SOMEVAR" ]] || true'
pair ur 'ur.sh|data/a.txt' ur.sh data/a.txt
run_verdict
expect_row "row 26: an unresolved \$VAR probe operand -> disqualified unresolved-probe" 0 ur disqualified "reason=unresolved-probe"
new_run; mksuite two1.sh 'cat data/a.txt'; mksuite two2.sh 'test -f second/file/probe'
emit_win two 1 0 - 'two1.sh|two2.sh|data/a.txt' 'two1.sh|two2.sh' two1.sh two2.sh data/a.txt
emit_win two 2 0 - 'two1.sh|two2.sh|data/a.txt' 'two1.sh|two2.sh' two1.sh two2.sh data/a.txt
run_verdict
expect_row "row 26: a probe in the SECOND code file is found" 0 two disqualified "probe:second/file/probe"
new_run; mksuite fs.sh 'cat data/a.txt' 'stat other/f' 'find elsewhere -name x'
pair fs 'fs.sh|data/a.txt' fs.sh data/a.txt
run_verdict
expect_row "row 26: a stat probe is found" 0 fs disqualified "probe:other/f"
expect_row "row 26: a find probe is found" 0 fs disqualified "probe:elsewhere"
new_run; mksuite dot.sh '[[ -f ./data/a.txt ]]' 'cat data/a.txt'
pair dot 'dot.sh|data/a.txt' dot.sh data/a.txt
run_verdict
expect_row "row 26: ./data/a.txt probe on the cover stays demotable" 0 dot demotable "reason=ok"
new_run
emit_win nof 1 0 - 'data/a.txt' - data/a.txt
emit_win nof 2 0 - 'data/a.txt' - data/a.txt
run_verdict
expect_row "row 26: a suite with no code file -> disqualified no-suite-file" 0 nof disqualified "reason=no-suite-file"

# Row 27: rule order and the clock/random entries; both flagged AND uncovered -> disqualified, not uncovered.
new_run; mksuite both.sh 'git diff --stat' 'cat data/a.txt data/b.txt'
pair both 'both.sh|data/a.txt' both.sh data/a.txt data/b.txt
run_verdict
expect_row "row 27: flagged AND uncovered -> disqualified (rule order)" 0 both disqualified "regex:git-diff"
cases=$((cases + 1))
if [[ "$(row_of "$OUT" both)" != *"detail=data/b.txt"* && "$(row_of "$OUT" both)" != *"reason=reads-outside-cover"* ]]; then pass "row 27: the uncovered list does not replace the disqualifier"; else fail "row 27: uncovered won over disqualified"; fi
new_run; mksuite rnd.sh 'cat data/a.txt' 'x=$RANDOM'
pair rnd 'rnd.sh|data/a.txt' rnd.sh data/a.txt
run_verdict
expect_row "row 27: \$RANDOM -> disqualified clock-epoch" 0 rnd disqualified "regex:clock-epoch"
new_run; mksuite pft.sh 'cat data/a.txt' "printf '%(%s)T\n' -1"
pair pft 'pft.sh|data/a.txt' pft.sh data/a.txt
run_verdict
expect_row "row 27: printf '%(%s)T' -> disqualified clock-epoch" 0 pft disqualified "regex:clock-epoch"

# Row 27b: verbs and tools beyond the entries' first samples (the widened alternatives, one row each).
xrow() { # xrow <slug> <entry> <suite line>
  new_run; mksuite "$1.sh" 'cat data/a.txt' "$3"
  pair "$1" "$1.sh|data/a.txt" "$1.sh" data/a.txt
  run_verdict
  expect_row "row 27b: [$3] -> disqualified $2" 0 "$1" disqualified "regex:$2"
}
xrow xgist net-gh 'gh gist list'
xrow xnpm net-other 'npm install left-pad'
xrow xnc net-other 'nc -z host 22'
xrow xblame git-other 'git blame -L1,2 f'

# Row 28: the NONCE guard, the `...+N` truncation of the uncovered list.
new_run; mksuite nc.sh 'true'
pair nc 'nc.sh' nc.sh
grep -v '^NONCE' "$RUN/meta" > "$RUN/meta.cut"; mv "$RUN/meta.cut" "$RUN/meta"
run_verdict
expect_err "row 28: meta without a NONCE line -> exit 2" 2 "no NONCE line"
new_run; mksuite tr.sh 'true'
evs=(tr.sh); for i in 1 2 3 4 5 6 7 8 9 10; do evs[${#evs[@]}]="u/f$i"; done
pair tr 'tr.sh' "${evs[@]}"
run_verdict
expect_row "row 28: 10 uncovered reads list 8 paths and the '...+2' remainder" 0 tr uncovered ",...+2"

# Row 29: valued flags as the LAST argument are usage errors (exit 2), never a spin; removed flags are unknown.
for argset in "record --repo" "record --rev" "record --only" "record --mode" "record --max-load" "record --timeout" \
              "record --out" "record --load-wait" "verdict --events" "verdict --reader-err" "verdict --meta" \
              "verdict --root" "verdict --mode"; do
  # shellcheck disable=SC2086
  timeout 5 bash "$SCRIPT" $argset >/dev/null 2>"$TESTROOT/u.err"; RC=$?; ERR="$TESTROOT/u.err"
  expect_err "usage: [$argset] as the last argument -> exit 2 (not a hang)" 2 "needs a value"
done
for argset in "record --reps 3" "record --allow-unresolved-probes" "verdict --allow-unresolved-probes"; do
  # shellcheck disable=SC2086
  timeout 5 bash "$SCRIPT" $argset >/dev/null 2>"$TESTROOT/u.err"; RC=$?; ERR="$TESTROOT/u.err"
  expect_err "usage: removed option [$argset] -> exit 2 unknown" 2 "unknown"
done

echo "== B. real reader and record path over fixture repositories =="

HAVE_INOTIFY=0; have_python_inotify && HAVE_INOTIFY=1
# The header's netns= value must name the tool that is really available (the script tries unshare first).
EXPECT_NETNS=none
if unshare -rn true >/dev/null 2>&1; then EXPECT_NETNS=unshare
elif bwrap --unshare-net --dev-bind / / true >/dev/null 2>&1; then EXPECT_NETNS=bwrap; fi
printf '0.10 0.10 0.10 1/1 1\n' > "$TESTROOT/loadavg.quiet"
printf '99.00 99.00 99.00 1/1 1\n' > "$TESTROOT/loadavg.busy"
mkdir -p "$TESTROOT/rtmp" "$TESTROOT/home"

fx_git() { # fx_git <dir> <git args...> : hermetic git in a fixture
  local d=$1; shift
  assert_fixture_dir "$d"
  env -i HOME="$TESTROOT/home" PATH="$PATH" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    git -C "$d" -c user.name=fx -c user.email=fx@invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"
}
FXN=0
mkfx() { # mkfx -> FX (a git repo with a fake runner)
  FXN=$((FXN + 1)); FX="$TESTROOT/fx.$FXN"
  mkdir -p "$FX/scripts" "$FX/suites" "$FX/data"
  assert_fixture_dir "$FX"
  fx_git "$FX" init -q
  : > "$FX/scripts/fake-enum.tsv"; : > "$FX/scripts/fake-sel.tsv"
  cat > "$FX/scripts/test-all.sh" <<'RUNNER'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  --enumerate-commands)
    if [ -f "$d/fake-enum.hang" ]; then awk '{ print $5 }' /proc/self/stat > "$(cat "$d/fake-enum.hang")"; sleep 61; fi
    cat "$d/fake-enum.tsv" ;;
  --print-selection)
    if [ -f "$d/fake-sel.rc" ]; then echo "selection exploded" >&2; exit "$(cat "$d/fake-sel.rc")"; fi
    cat "$d/fake-sel.tsv" ;;
  *) exit 64 ;;
esac
RUNNER
  echo "fixture a" > "$FX/data/a.txt"; echo "fixture b" > "$FX/data/b.txt"; echo "fixture c" > "$FX/data/c.txt"
}
fx_suite() { # fx_suite <slug> <cover '|'-joined or -> <body line>... : suite file + enum + selection rows
  local slug=$1 cover=$2; shift 2
  printf '#!/usr/bin/env bash\n' > "$FX/suites/$slug.sh"
  printf '%s\n' "$@" >> "$FX/suites/$slug.sh"
  printf 'SUITE_COMMAND\t%s\tbash\tsuites/%s.sh\n' "$slug" "$slug" >> "$FX/scripts/fake-enum.tsv"
  printf 'AFFECTED_SELECTED\t%s\t0\tedge:declared\t%s\n' "$slug" "$cover" >> "$FX/scripts/fake-sel.tsv"
}
fx_commit() {
  fx_git "$FX" add -A
  fx_git "$FX" commit -q -m fixture
  FX_SHA="$(fx_git "$FX" rev-parse HEAD)"
}
RECN=0
REC_ENV=()   # extra env assignments for the next run_record(s), e.g. PATH=shim:$PATH
run_record() { # run_record <extra record args...> : env-controlled, outputs under $TESTROOT/rec.N; --load-wait 0 unless given
  RECN=$((RECN + 1)); REC="$TESTROOT/rec.$RECN"; mkdir -p "$REC"
  OUT="$REC/stdout"; ERR="$REC/stderr"
  env TMPDIR="$TESTROOT/rtmp" SECRET_TOKEN=leak AUDIT_READS_LOADAVG_FILE="${LOADFILE:-$TESTROOT/loadavg.quiet}" \
    ${REC_ENV[@]+"${REC_ENV[@]}"} \
    bash "$SCRIPT" record --repo "$FX" --rev HEAD --out "$REC/out" --load-wait 0 "$@" >"$OUT" 2>"$ERR"
  RC=$?
}
wait_file() { # wait_file <file> : up to 10 s for a non-empty file
  local f=$1 n
  for n in $(seq 1 100); do [[ -s "$f" ]] && return 0; sleep 0.1; done
  return 1
}
group_alive() { # 0 iff some non-zombie process is still in process group $1 (kill -0 -- -pgid, zombies excluded)
  kill -0 -- "-$1" 2>/dev/null || return 1
  ps -eo pgid=,stat= 2>/dev/null | awk -v g="$1" '$1 == g && $2 !~ /^Z/ { f = 1 } END { exit !f }'
}
wait_group_gone() { # wait_group_gone <pgid> : 0 iff the group is gone within 5 s; kills a survivor (our own recorded group)
  local g=$1 n
  for n in $(seq 1 50); do group_alive "$g" || return 0; sleep 0.1; done
  kill -KILL -- "-$g" 2>/dev/null
  return 1
}
pid_alive() { # 0 iff the pid is alive and not a zombie
  local st
  kill -0 "$1" 2>/dev/null || return 1
  st="$(awk '{ print $3 }' "/proc/$1/stat" 2>/dev/null)"
  [[ -n "$st" && "$st" != Z ]]
}
wait_pid_gone() { # 0 iff the pid is gone within 5 s; kills a survivor
  local n
  for n in $(seq 1 50); do pid_alive "$1" || return 0; sleep 0.1; done
  kill -KILL "$1" 2>/dev/null
  return 1
}

# Rows section B holds (asserted when it runs, so a skip is accounted with the REAL number): the core rows
# and the two rows of the queue-overflow block (row 1b), which may skip on its own.
ROWS_B_CORE=99; ROWS_B_1B=2
B_START=$cases; B_INNER_SKIP=0
if (( HAVE_INOTIFY == 0 )); then
  skip_or_fail "section B (real reader + record rows): python3 ctypes inotify unavailable" $((ROWS_B_CORE + ROWS_B_1B))
elif [[ "$EXPECT_NETNS" == none ]]; then
  # a recording without a network namespace is unreliable by design, so no decided row can be produced here;
  # on a runner this needs `unshare -rn true` (or bwrap --unshare-net) to work: UNVERIFIED for the scripts job
  skip_or_fail "section B (record rows): no network-less namespace tool (unshare -rn true / bwrap) works here" $((ROWS_B_CORE + ROWS_B_1B))
else
  # ---- the main fixture: one record run drives rows 1/3/4/6/7/8/13/14/17 live -----------------------
  mkfx
  NETCHECK='[[ "$(grep -c : /proc/net/dev)" -le 1 ]] || exit 14'
  fx_suite okay '^data/a.txt' 'cat data/a.txt >/dev/null' '[[ -f data/a.txt ]] || exit 9'
  fx_suite probe '^data/a.txt' 'cat data/a.txt >/dev/null' '[[ -e some/missing/path ]] || true'
  fx_suite uncov '^data/a.txt' 'cat data/a.txt data/b.txt >/dev/null'
  fx_suite exit3 '' 'exit 3'
  fx_suite slow '' 'sleep 30'
  fx_suite flaky '^data/a.txt|^data/b.txt' 'n=0; [ -f "$HOME/count" ] && n=$(cat "$HOME/count")' 'echo $((n + 1)) > "$HOME/count"' \
    'if [ $((n % 2)) -eq 0 ]; then cat data/a.txt; else cat data/b.txt; fi >/dev/null'
  fx_suite mkdirs '^data/a.txt' 'mkdir "newdir.$$"' 'cat data/a.txt >/dev/null'
  fx_suite junk '^data/a.txt' 'echo x > junk.txt'
  fx_suite sub1 '^data/a.txt' 'cat data/a.txt >/dev/null'
  fx_suite sub2 '^data/b.txt' 'cat data/b.txt >/dev/null'
  fx_suite envck '' '[[ -z "${SECRET_TOKEN:-}" ]] || exit 11' 'case "$HOME" in */scratch/home) ;; *) exit 12 ;; esac' \
    'case "$PATH" in *:*) exit 13 ;; esac' "$NETCHECK"
  fx_commit
  run_record --cover-from-selection --timeout 4
  RC_LIVE_MAIN=$RC
  hdr_line="$(head -n 1 "$OUT")"
  expect_hdr() { # expect_hdr <name> <needle> : the header line of the run just made
    cases=$((cases + 1))
    if [[ "$hdr_line" == *$'\t'"$2"$'\t'* || "$hdr_line" == *$'\t'"$2" ]]; then pass "$1"; else fail "$1 :: header=[$hdr_line]"; fi
  }
  expect_hdr "live: header netns= names the tool that is available ($EXPECT_NETNS)" "netns=$EXPECT_NETNS"
  expect_hdr "live: header stamps reps=2" "reps=2"
  expect_hdr "live: header stamps cover=selection under --cover-from-selection" "cover=selection"
  cases=$((cases + 1))
  if [[ "$RC_LIVE_MAIN" == 3 ]]; then pass "live: table written and exit 3 because rows are unreliable"; else fail "live: expected exit 3, got $RC_LIVE_MAIN :: $(head -c 400 "$ERR")"; fi
  expect_row "live row 0: compliant suite is demotable with the revision stamped" 3 okay demotable "rev=$FX_SHA"
  expect_row "live row 3/4: probing suite (after a compliant one) -> disqualified" 3 probe disqualified "probe:some/missing/path"
  expect_row "live row 6: read outside the cover -> uncovered, path listed" 3 uncov uncovered "data/b.txt"
  expect_row "live row 7: non-zero exit -> unreliable rc" 3 exit3 unreliable "reason=rc"
  expect_row "live row 7: cap hit -> unreliable timeout (rc 124)" 3 slow unreliable "reason=timeout"
  expect_row "live row 8: two recordings disagree -> unreliable" 3 flaky unreliable "reason=repeat_disagree"
  expect_row "live row 13: directory created under the checkout -> disqualified" 3 mkdirs disqualified "reason=created-dir"
  expect_row "live: a suite that dirties the checkout -> unreliable contaminated" 3 junk unreliable "reason=contaminated"
  expect_row "live: the contaminated detail names the dirty path" 3 junk unreliable "dirty:junk.txt"
  expect_row "live row 14: back-to-back suite 1 keeps only its own reads" 3 sub1 demotable "reason=ok"
  expect_row "live row 14: back-to-back suite 2 keeps only its own reads" 3 sub2 demotable "reason=ok"
  expect_row "live: env -i, scratch PATH/HOME, no inherited secret, network-less -> suite exits 0" 3 envck demotable "rc=0"
  cases=$((cases + 1))
  if [[ -z "$(ls -d "$TESTROOT"/rtmp/soleur-audit-reads.* 2>/dev/null)" ]]; then pass "live: checkout directory removed on exit"; else fail "live: leftover checkout under rtmp"; fi

  # ---- row 17 live (must-PASS) + row 15 (cover comes from the audited checkout) ------------------------
  mkfx
  fx_suite sub '^data/c.txt|^data/a.txt|^data/unused.txt' 'cat data/a.txt data/c.txt >/dev/null' '[[ -f data/c.txt ]] && [ -d data ]'
  fx_commit
  printf 'AFFECTED_SELECTED\tsub\t0\tedge:declared\t^zzz-live-tree-only\n' > "$FX/scripts/fake-sel.tsv"   # dirty, uncommitted
  run_record --cover-from-selection
  expect_row "live row 17: strict-subset reads of a reordered cover -> demotable" 0 sub demotable "files=3"
  expect_row "live row 15: cover came from the audited checkout (live-tree mutation ignored)" 0 sub demotable "reason=ok"

  # ---- row 5 live: zero suites -> exit 4, distinct message ------------------------------------------
  mkfx; fx_commit
  run_record --cover-from-selection
  expect_err "live row 5: zero suites enumerated -> exit 4" 4 "zero suites enumerated"
  mkfx; fx_suite okay '^data/a.txt' 'cat data/a.txt >/dev/null'; fx_commit
  run_record --cover-from-selection --only no-such-label
  expect_err "live: --only naming no registration -> exit 2 naming the label" 2 "unknown label(s): no-such-label"
  # --only takes a comma-separated list: the two named suites are audited, the third is not.
  mkfx
  fx_suite oka '^data/a.txt' 'cat data/a.txt >/dev/null'
  fx_suite okb '^data/a.txt' 'cat data/a.txt >/dev/null'
  fx_suite okc '^data/a.txt' 'cat data/a.txt >/dev/null'
  fx_commit
  run_record --cover-from-selection --only oka,okc
  expect_row "live: --only a,c audits the first listed suite" 0 oka demotable "rc=0"
  expect_row "live: --only a,c audits the second listed suite" 0 okc demotable "rc=0"
  cases=$((cases + 1))
  if [[ -z "$(row_of "$OUT" okb)" ]]; then pass "live: --only a,c leaves the unlisted suite out of the table"; else fail "live: unlisted suite okb was audited"; fi

  # ---- row 12 live: load above --max-load -> refusal, rows unreliable ----------------------------------
  mkfx; fx_suite okay '^data/a.txt' 'cat data/a.txt >/dev/null'; fx_commit
  LOADFILE="$TESTROOT/loadavg.busy" run_record --cover-from-selection --max-load 4.0
  expect_row "live row 12: load above --max-load -> refusal, row unreliable" 3 okay unreliable "reason=load_refused"
  LOADFILE="$TESTROOT/loadavg.busy" run_record --cover-from-selection --max-load 200
  expect_row "live row 12: the same load under a higher --max-load is not refused" 0 okay demotable "load=99.00"

  # ---- usage / refusal exits ------------------------------------------------------------------------------
  for argset in "" "frobnicate" "record --only ../x" "record --mode weird" "record --max-load abc" "verdict --mode weird"; do
    # shellcheck disable=SC2086
    bash "$SCRIPT" $argset >/dev/null 2>"$TESTROOT/u.err"; RC=$?; ERR="$TESTROOT/u.err"
    expect_err "usage: [$argset] -> exit 2" 2 "audit-suite-reads"
  done
  # no network-less namespace tool on PATH -> refuse to start (exit 2, named message)
  NB="$TESTROOT/nonet-bin"; mkdir -p "$NB"
  for t in bash git python3 uname mktemp rm grep awk sed sort cat env dirname basename tr cut wc head tail find mkdir tar ls id cmp od tee sleep; do
    p="$(command -v "$t" 2>/dev/null)" && [[ -n "$p" && -x "$p" ]] && ln -sf "$p" "$NB/$t"
  done
  env -i PATH="$NB" HOME="$TESTROOT/home" TMPDIR="$TESTROOT/rtmp" "$NB/bash" "$SCRIPT" record --repo "$FX" >"$TESTROOT/nn.out" 2>"$TESTROOT/nn.err"; RC=$?; ERR="$TESTROOT/nn.err"
  expect_err "refusal: neither unshare nor bwrap -> exit 2, named message" 2 "network-less"

  # ---- row 16: remove the verdict call from `record` -> the real-reader arm goes RED --------------------
  mkfx; fx_suite okay '^data/a.txt' 'cat data/a.txt >/dev/null'; fx_commit
  real_arm_green() { # 0 iff the real record path produced a demotable row
    run_record --cover-from-selection
    [[ "$(row_of "$OUT" okay)" == *$'\t'"verdict=demotable"$'\t'* ]] && [[ "$RC" == 0 ]]
  }
  real_arm_green; g=$?
  ok_if "row 16: pristine script - real-reader arm is green (control)" "$g"
  M="$TESTROOT/mut/scripts/audit-suite-reads.sh"
  anchors=$(grep -c 'RECORD-VERDICT-CALL' "$SCRIPT")
  awk '/RECORD-VERDICT-CALL/ { print ": # verdict call removed by the mutation harness"; next } { print }' "$SCRIPT" > "$M"
  lm=0; [[ "$anchors" == 1 ]] || lm=1
  [[ "$(md5sum < "$SCRIPT")" != "$(md5sum < "$M")" ]] || lm=1
  ok_if "row 16: mutation landed (one anchor, md5 differs)" "$lm"
  SAVED_SCRIPT="$SCRIPT"; SCRIPT="$M"
  real_arm_green; g=$?
  SCRIPT="$SAVED_SCRIPT"
  ok_if "row 16: verdict call removed from record -> the real-reader arm goes RED" "$(( g == 0 ))"

  # ---- cleanup on SIGTERM: no leftover checkout, no leftover suite process group (recorded pgid) ---------
  mkfx; HANGPG="$TESTROOT/hang.pgid"; rm -f "$HANGPG"
  fx_suite hang '' "awk '{ print \$5 }' /proc/self/stat > $HANGPG" "sleep 61.$$" 'true'; fx_commit
  rm -rf -- "$TESTROOT/rtmp"; mkdir -p "$TESTROOT/rtmp"
  env TMPDIR="$TESTROOT/rtmp" AUDIT_READS_LOADAVG_FILE="$TESTROOT/loadavg.quiet" \
    bash "$SCRIPT" record --repo "$FX" --rev HEAD --out "$TESTROOT/term.out" >/dev/null 2>&1 &
  tp=$!; BG_PIDS="$BG_PIDS $tp"
  wait_wf=0; wait_file "$HANGPG" || wait_wf=1
  ok_if "cleanup: the hanging suite started and recorded its process group" "$wait_wf"
  hpg="$(cat "$HANGPG" 2>/dev/null)"
  kill -TERM "$tp" 2>/dev/null
  wait "$tp" 2>/dev/null
  left=0; [[ -z "$(ls -d "$TESTROOT"/rtmp/soleur-audit-reads.* 2>/dev/null)" ]] || left=1
  ok_if "cleanup: SIGTERM removes the checkout directory" "$left"
  left=1; if [[ "$hpg" =~ ^[0-9]+$ ]] && wait_group_gone "$hpg"; then left=0; fi
  ok_if "cleanup: SIGTERM kills the suite's process group (kill -0 -- -$hpg)" "$left"

  # ---- the post-wait group kill: a suite that leaves a background child behind -------------------------
  mkfx; ORPH="$TESTROOT/orphan.pid"; rm -f "$ORPH"
  fx_suite orph '' "sleep 62.$$ &" "echo \$! > $ORPH" 'exit 0'; fx_commit
  run_record --timeout 20
  wait_file "$ORPH" || true
  opid="$(cat "$ORPH" 2>/dev/null)"
  left=1; if [[ "$opid" =~ ^[0-9]+$ ]] && wait_pid_gone "$opid"; then left=0; fi
  ok_if "post-wait: the group kill reaps a background child the suite left behind (pid $opid)" "$left"

  # ---- enumeration is bounded and reachable by the traps ---------------------------------------------------
  mkfx; ENUMPG="$TESTROOT/enum.pgid"; rm -f "$ENUMPG"; printf '%s' "$ENUMPG" > "$FX/scripts/fake-enum.hang"
  fx_suite e1 '^data/a.txt' 'cat data/a.txt >/dev/null'; fx_commit
  run_record --timeout 3
  expect_err "enumerate: a hung runner is cut at --timeout, rc=124 reported, exit 4" 4 "rc=124"
  expect_err "enumerate: the label-listing command is named" 4 "bash scripts/test-all.sh --enumerate-commands all"
  epg="$(cat "$ENUMPG" 2>/dev/null)"
  left=1; if [[ "$epg" =~ ^[0-9]+$ ]] && wait_group_gone "$epg"; then left=0; fi
  ok_if "enumerate: the timed-out runner's process group is gone" "$left"
  rm -f "$ENUMPG"
  rm -rf -- "$TESTROOT/rtmp"; mkdir -p "$TESTROOT/rtmp"
  env TMPDIR="$TESTROOT/rtmp" AUDIT_READS_LOADAVG_FILE="$TESTROOT/loadavg.quiet" \
    bash "$SCRIPT" record --repo "$FX" --rev HEAD --out "$TESTROOT/term2.out" >/dev/null 2>&1 &
  tp=$!; BG_PIDS="$BG_PIDS $tp"
  wait_wf=0; wait_file "$ENUMPG" || wait_wf=1
  ok_if "enumerate: the hanging enumeration started" "$wait_wf"
  epg="$(cat "$ENUMPG" 2>/dev/null)"
  kill -TERM "$tp" 2>/dev/null
  wait "$tp" 2>/dev/null; trc=$?
  ok_if "enumerate: SIGTERM during the enumeration exits 143" "$(( trc != 143 ))"
  left=1; if [[ "$epg" =~ ^[0-9]+$ ]] && wait_group_gone "$epg"; then left=0; fi
  ok_if "enumerate: SIGTERM kills the hung runner's process group" "$left"

  # ---- --only: every label must match, exactly (not by substring); declared labels are refused ----------
  mkfx
  fx_suite oka '^data/a.txt' 'cat data/a.txt >/dev/null'
  fx_suite okab '^data/a.txt' 'cat data/a.txt >/dev/null'
  printf 'SUITE_COMMAND_DECLINED\tdecl\tneeds a thing\n' >> "$FX/scripts/fake-enum.tsv"
  fx_commit
  run_record --only oka,typo
  expect_err "--only: a typo in a list -> exit 2 naming it" 2 "unknown label(s): typo"
  cases=$((cases + 1))
  if [[ -z "$(ls -d "$TESTROOT"/rec.$RECN/out/logs/* 2>/dev/null)" ]]; then pass "--only: nothing was run for the refused list"; else fail "--only: suites ran despite a bad label"; fi
  run_record --only oka,decl
  expect_err "--only: a DECLINED registration -> exit 2 naming it as declined" 2 "declined (not auditable) label(s): decl"
  run_record --only oka --cover-from-selection
  expect_row "--only oka: exact match audits oka" 0 oka demotable "rc=0"
  cases=$((cases + 1))
  if [[ -z "$(row_of "$OUT" okab)" ]]; then pass "--only oka: the label okab (oka is a substring of it) is not audited"; else fail "--only oka: substring matched okab"; fi

  # ---- a failed selection under --cover-from-selection is exit 2, never a silent argv-only cover ----------
  mkfx; fx_suite oka '^data/a.txt' 'true'; printf '5' > "$FX/scripts/fake-sel.rc"; fx_commit
  run_record --cover-from-selection
  expect_err "selection failure: exit 2 naming --print-selection and its rc" 2 "--print-selection failed (rc=5)"
  run_record
  expect_row "no --cover-from-selection: the selection is not consulted, argv cover decides" 0 oka demotable "rc=0"
  expect_hdr_of() { cases=$((cases + 1)); if [[ "$(head -n 1 "$OUT")" == *$'\t'"$1"$'\t'* ]]; then pass "$2"; else fail "$2 :: $(head -n 1 "$OUT")"; fi; }
  expect_hdr_of "cover=argv" "header stamps cover=argv without --cover-from-selection"

  # ---- the ancestry refusal --------------------------------------------------------------------------------
  mkfx; fx_suite oka '^data/a.txt' 'cat data/a.txt >/dev/null'; fx_commit
  fx_git "$FX" checkout -q -b side
  fx_git "$FX" commit -q --allow-empty -m side
  SIDE_SHA="$(fx_git "$FX" rev-parse HEAD)"
  fx_git "$FX" checkout -q -
  run_record --rev "$SIDE_SHA"
  expect_err "ancestry: a revision that is not an ancestor -> exit 2, the edit must be committed first" 2 "must be committed first"

  # ---- load: > (strict) vs >=, the wait, and the refusal message ---------------------------------------------
  mkfx; fx_suite okay '^data/a.txt' 'cat data/a.txt >/dev/null'; fx_commit
  printf '4.00 4.00 4.00 1/1 1\n' > "$TESTROOT/loadavg.equal"; printf '4.01 4.01 4.01 1/1 1\n' > "$TESTROOT/loadavg.above"
  LOADFILE="$TESTROOT/loadavg.equal" run_record --max-load 4.0 --cover-from-selection
  expect_row "load: exactly --max-load is not refused (> not >=)" 0 okay demotable "load=4.00"
  LOADFILE="$TESTROOT/loadavg.above" run_record --max-load 4.0
  expect_row "load: just above --max-load is refused" 3 okay unreliable "reason=load_refused"
  expect_err "load: the refusal message names --max-load and --load-wait" 3 "raise --max-load or --load-wait"
  LOADFILE="$TESTROOT/loadavg.busy" run_record --max-load 4.0 --load-wait 2
  expect_err "load: a refusal after waiting says how long it waited" 3 "after 2s"
  cp "$TESTROOT/loadavg.busy" "$TESTROOT/loadavg.dyn"
  ( sleep 2; cp "$TESTROOT/loadavg.quiet" "$TESTROOT/loadavg.dyn" ) &
  BG_PIDS="$BG_PIDS $!"
  t0=$SECONDS
  LOADFILE="$TESTROOT/loadavg.dyn" run_record --max-load 4.0 --load-wait 30 --cover-from-selection
  t1=$SECONDS
  expect_row "load: load that drops within --load-wait is waited out, the suite is decided" 0 okay demotable "load=0.10"
  ok_if "load: the wait ended when the load dropped (took $((t1 - t0)) s, not the full 30)" "$(( (t1 - t0) >= 25 ))"

  # ---- ignored-but-tracked files must not read as contamination (git add -A -f) ------------------------------
  mkfx
  printf '*.log\ndata/ign.txt\n' > "$FX/.gitignore"; echo "tracked but ignored" > "$FX/data/ign.txt"
  fx_git "$FX" add -f data/ign.txt
  fx_suite ignok '^data/a.txt|^data/ign.txt' 'cat data/a.txt data/ign.txt >/dev/null'
  fx_suite ignmk '^data/a.txt' 'echo x > data/made.log'
  fx_suite ignafter '^data/a.txt|^data/ign.txt' 'cat data/a.txt data/ign.txt >/dev/null'
  fx_commit
  run_record --cover-from-selection
  expect_row "ignored: a clean suite in a repo with a force-added ignored file is decided, not contaminated" 3 ignok demotable "reason=ok"
  expect_row "ignored: a suite that really creates an ignored untracked file IS contaminated" 3 ignmk unreliable "reason=contaminated"
  expect_row "ignored: ... and its detail names the path" 3 ignmk unreliable "dirty:data/made.log"
  expect_row "ignored: the suite after the cleanup still finds the tracked ignored file (decided)" 3 ignafter demotable "reason=ok"

  # ---- the suite cannot steer the harness's own git through .git/config ----------------------------------------
  mkfx; FSM="$TESTROOT/fsm.sentinel"; rm -f "$FSM"
  fx_suite cfg '^data/a.txt' 'cat data/a.txt >/dev/null' "git config core.fsmonitor 'touch $FSM'"
  fx_suite aftercfg '^data/a.txt' 'cat data/a.txt >/dev/null'
  fx_commit
  run_record --cover-from-selection
  expect_row "git-config: a suite rewriting .git/config is unreliable contaminated" 3 cfg unreliable "reason=contaminated"
  expect_row "git-config: ... with detail=git-config" 3 cfg unreliable "detail=git-config"
  cases=$((cases + 1))
  if [[ ! -e "$FSM" ]]; then pass "git-config: the fsmonitor hook the suite planted never ran in the harness"; else fail "git-config: the planted core.fsmonitor hook EXECUTED (sentinel exists)"; fi
  expect_row "git-config: the pristine config was restored (next suite is decided)" 3 aftercfg demotable "reason=ok"

  # ---- a recording without a network namespace is never decided -------------------------------------------------
  mkfx; fx_suite okay '^data/a.txt' 'cat data/a.txt >/dev/null'; fx_commit
  NNS="$TESTROOT/no-netns-shim"; mkdir -p "$NNS"
  printf '#!/bin/sh\nexit 1\n' > "$NNS/unshare"; cp "$NNS/unshare" "$NNS/bwrap"; chmod +x "$NNS/unshare" "$NNS/bwrap"
  REC_ENV=("PATH=$NNS:$PATH" AUDIT_READS_ALLOW_NO_NETNS=1)
  run_record --cover-from-selection
  REC_ENV=()
  hdr_line="$(head -n 1 "$OUT")"
  expect_row "no-netns: every decided row becomes unreliable no-netns" 3 okay unreliable "reason=no-netns"
  expect_hdr "no-netns: the seam run's header says netns=none" "netns=none"

  # ---- a suite that SKIPs with rc 0 did not read what it would read ---------------------------------------------
  mkfx
  fx_suite skipper '^data/a.txt' 'echo "SKIP: npx not on PATH"' 'exit 0'
  fx_suite skipbr '^data/a.txt' 'echo "  [skip] no network"' 'exit 0'
  fx_suite skipped0 '^data/a.txt' 'cat data/a.txt >/dev/null' 'echo "ran 3 tests, skipped 0"' 'echo "Skipped: 0"' 'exit 0'
  fx_commit
  run_record --cover-from-selection
  expect_row "skip: 'SKIP: reason' with rc 0 -> unreliable skipped" 3 skipper unreliable "reason=skipped"
  expect_row "skip: '  [skip] reason' (case-insensitive, bracketed) -> unreliable skipped" 3 skipbr unreliable "reason=skipped"
  expect_row "skip: 'skipped 0 tests' / 'Skipped: 0' are not skip lines (decided)" 3 skipped0 demotable "reason=ok"

  # ---- the run directory is touched per window (a live run must not look stale to sweep_stale) --------------------
  mkfx
  fx_suite aged '^data/a.txt|^.' 'touch -d "3 days ago" "$SOLEUR_SCRATCH_BASE/../.."' 'cat data/a.txt >/dev/null'
  fx_suite fresh '^data/a.txt|^.' "python3 -c 'import os, sys, time; sys.exit(15 if time.time() - os.path.getmtime(os.environ[\"SOLEUR_SCRATCH_BASE\"] + \"/../..\") > 86400 else 0)' || exit 15" 'cat data/a.txt >/dev/null'
  fx_commit
  run_record --cover-from-selection
  expect_row "touch: the run directory is fresh again after each window (sweep_stale would not reap it)" 0 fresh demotable "rc=0"

  # ---- a suite that floods its output keeps a bounded window log ---------------------------------------------------
  mkfx
  fx_suite flood '' "head -c 5000000 /dev/zero | tr '\\0' x"
  fx_commit
  run_record --cover-from-selection
  flood_sz="$(wc -c < "$REC/out/logs/1.log" 2>/dev/null || echo 0)"
  ok_if "log cap: a 5 MB window log is kept at the 4 MiB cap (is $flood_sz bytes)" "$(( flood_sz != 4194304 ))"

  # ---- cover near-misses, live ----------------------------------------------------------------------------------
  mkfx; echo "bak" > "$FX/data/a.txt.bak"
  fx_suite nm1 '^data/a.txt' 'cat data/a.txt data/a.txt.bak >/dev/null'
  fx_suite nm2 '^data/a.txt' 'cat data/a.txt >/dev/null' '[[ -e data/a ]] || true'
  fx_suite nm3 '^data/a.txt' 'cat data/a.txt >/dev/null' '[ -d dat ] || true'
  fx_suite nm4 '^data/' 'cat data/a.txt >/dev/null' '[[ -e other/x ]] || true'
  fx_commit
  run_record --cover-from-selection
  expect_row "live near-miss: data/a.txt.bak is not covered by data/a.txt" 0 nm1 uncovered "data/a.txt.bak"
  expect_row "live near-miss: probe [[ -e data/a ]] -> disqualified" 0 nm2 disqualified "probe:data/a"
  expect_row "live near-miss: probe [ -d dat ] -> disqualified" 0 nm3 disqualified "probe:dat"
  expect_row "live near-miss: probe [[ -e other/x ]] under the directory cover data/ -> disqualified" 0 nm4 disqualified "probe:other/x"

  # ---- a directory deleted-and-restored by the contamination cleanup stays watched -------------------------------
  mkfx; mkdir -p "$FX/data2"; echo "two" > "$FX/data2/f"
  fx_suite breaker '^data/a.txt' 'rm -rf data2'
  fx_suite reader2 '^data2/f|^data/a.txt' 'cat data2/f >/dev/null'
  fx_commit
  run_record --cover-from-selection
  expect_row "restart: the suite that deleted a tracked directory is contaminated" 3 breaker unreliable "reason=contaminated"
  expect_row "restart: after the cleanup restored it, reads under it are still recorded (files=2)" 3 reader2 demotable "files=2"

  # ---- a watched directory moved by the suite (X record) ---------------------------------------------------------
  mkfx; mkdir -p "$FX/d1"; echo "f" > "$FX/d1/f"
  fx_suite mover '^d1/f|^d2/f' 'mv d1 d2' 'cat d2/f >/dev/null' 'mv d2 d1'
  fx_suite aftermv '^d1/f|^data/a.txt' 'cat d1/f >/dev/null'
  fx_commit
  run_record --cover-from-selection
  expect_row "dir-moved: a suite that renames a watched directory and reads through the new name is unreliable" 3 mover unreliable "reason=dir-moved"
  expect_row "dir-moved: the suite after it (watch intact after the restore) is decided" 3 aftermv demotable "reason=ok"

  # ---- directory-open events (D) live ---------------------------------------------------------------------------
  mkfx; mkdir -p "$FX/other"; echo "o" > "$FX/other/x"
  fx_suite lister '^data/a.txt' 'cat data/a.txt >/dev/null' 'for f in other/*; do :; done'
  fx_commit
  run_record --cover-from-selection
  expect_row "live D: listing a directory outside the cover via a glob -> uncovered" 0 lister uncovered "other"

  # ---- fail fast: a reader that is not ready / cannot watch stops the audit before any suite runs -----------------
  STUB="$TESTROOT/stub/scripts"; mkdir -p "$STUB/lib"
  cp "$SCRIPT" "$STUB/audit-suite-reads.sh"
  printf '#!/usr/bin/env python3\nimport sys, time\nsys.stderr.write("ready\\nFailed to watch /x/y\\n")\nsys.stderr.flush()\ntime.sleep(30)\n' > "$STUB/lib/inotify-open-recorder.py"
  mkfx; fx_suite okay '^data/a.txt' 'cat data/a.txt >/dev/null'; fx_commit
  SAVED_SCRIPT="$SCRIPT"; SCRIPT="$STUB/audit-suite-reads.sh"
  run_record
  expect_err "fail-fast: a reader that reports 'Failed to watch' -> exit 3 at once, cause named" 3 "failed to watch: Failed to watch /x/y"
  cases=$((cases + 1))
  if [[ "$(cat "$ERR")" != *"[audit] okay"* ]]; then pass "fail-fast: no suite was run"; else fail "fail-fast: suites ran after the reader failed"; fi
  printf '#!/usr/bin/env python3\nimport sys\nsys.exit(0)\n' > "$STUB/lib/inotify-open-recorder.py"
  run_record
  expect_err "fail-fast: a reader that dies without 'ready' -> exit 3, cause named" 3 "did not become ready"
  SCRIPT="$SAVED_SCRIPT"

  # ---- --out refusals --------------------------------------------------------------------------------------------
  mkfx; fx_suite okay '^data/a.txt' 'cat data/a.txt >/dev/null'; fx_commit
  VICTIM="$TESTROOT/victim.txt"; echo precious > "$VICTIM"
  mkdir -p "$TESTROOT/outsym"; ln -s "$VICTIM" "$TESTROOT/outsym/table.tsv"
  bash "$SCRIPT" record --repo "$FX" --rev HEAD --out "$TESTROOT/outsym" --load-wait 0 >/dev/null 2>"$TESTROOT/o.err"; RC=$?; ERR="$TESTROOT/o.err"
  expect_err "out: an existing --out holding a symlinked table.tsv is refused (exit 2)" 2 "already holds table.tsv"
  cases=$((cases + 1))
  if [[ "$(cat "$VICTIM")" == precious ]]; then pass "out: the symlink target was not overwritten"; else fail "out: the symlink target was overwritten"; fi
  ln -s "$TESTROOT/outsym" "$TESTROOT/outlink"
  bash "$SCRIPT" record --repo "$FX" --rev HEAD --out "$TESTROOT/outlink" --load-wait 0 >/dev/null 2>"$TESTROOT/o.err"; RC=$?; ERR="$TESTROOT/o.err"
  expect_err "out: a --out that is itself a symlink is refused (exit 2)" 2 "is a symlink"
  bash "$SCRIPT" record --repo "$FX" --rev HEAD --out "$TESTROOT/no/such/parent/out" --load-wait 0 >/dev/null 2>"$TESTROOT/o.err"; RC=$?; ERR="$TESTROOT/o.err"
  expect_err "out: a missing parent directory is refused, not created with mkdir -p (exit 2)" 2 "parent directory must exist"
  cases=$((cases + 1))
  if [[ ! -e "$TESTROOT/no" ]]; then pass "out: nothing was created along the refused path"; else fail "out: mkdir -p created $TESTROOT/no"; fi
  bash "$SCRIPT" record --repo "$FX" --rev HEAD --out "$TESTROOT/a/../b" --load-wait 0 >/dev/null 2>"$TESTROOT/o.err"; RC=$?; ERR="$TESTROOT/o.err"
  expect_err "out: a path containing .. is refused by assert_fixture_dir before any mkdir/chmod (exit 2)" 2 "contains .."
  if (( EUID != 0 )) && [[ -d /usr && ! -O /usr ]]; then
    bash "$SCRIPT" record --repo "$FX" --rev HEAD --out /usr --load-wait 0 >/dev/null 2>"$TESTROOT/o.err"; RC=$?; ERR="$TESTROOT/o.err"
    expect_err "out: an existing directory the caller does not own is refused (exit 2)" 2 "directory you own"
  else
    _sr0=$SKIPPED_ROWS
    skip_or_fail "out: no root-owned directory to refuse (or running as root)" 1
    if (( SKIPPED_ROWS > _sr0 )); then B_INNER_SKIP=1; fi
  fi
  # the default out directory is kept on purpose and sweep_stale leaves it alone; stale CHECKOUT runs are swept
  RTD="$TESTROOT/rtmp-sweep"; mkdir -p "$RTD/soleur-audit-reads.stale1" "$RTD/soleur-audit-reads-out.keep1"
  touch -d "3 days ago" "$RTD/soleur-audit-reads.stale1" "$RTD/soleur-audit-reads-out.keep1"
  env TMPDIR="$RTD" AUDIT_READS_LOADAVG_FILE="$TESTROOT/loadavg.quiet" bash "$SCRIPT" record --repo "$FX" --rev HEAD --load-wait 0 >/dev/null 2>&1
  gone=0; [[ ! -d "$RTD/soleur-audit-reads.stale1" ]] || gone=1
  ok_if "sweep: a stale checkout directory (soleur-audit-reads.*) is swept" "$gone"
  kept=0; [[ -d "$RTD/soleur-audit-reads-out.keep1" ]] || kept=1
  ok_if "sweep: a stale kept evidence directory (soleur-audit-reads-out.*) is never swept" "$kept"
  nouts=$(ls -d "$RTD"/soleur-audit-reads-out.* 2>/dev/null | wc -l)
  ok_if "default out: this run's own evidence directory is kept on purpose ($nouts out dirs)" "$(( nouts != 2 ))"
  left=0; [[ -z "$(ls -d "$RTD"/soleur-audit-reads.* 2>/dev/null)" ]] || left=1
  ok_if "default out: the private checkout itself is removed" "$left"
  B_CORE_ROWS=$((cases - B_START + B_INNER_SKIP))
  if (( B_CORE_ROWS != ROWS_B_CORE )); then
    printf '[FATAL] section B core holds %s rows but ROWS_B_CORE says %s: update ROWS_B_CORE (it prices a skip)\n' "$B_CORE_ROWS" "$ROWS_B_CORE" >&2
    exit 2
  fi
  # ---- row 1b: the REAL reader, stopped while more events than max_queued_events arrive -------------------
  B1B_START=$cases
  maxq="$(cat /proc/sys/fs/inotify/max_queued_events 2>/dev/null || echo 0)"
  if ! [[ "$maxq" =~ ^[0-9]+$ ]] || (( maxq <= 0 )) || (( maxq > 100000 )); then
    skip_or_fail "row 1b: max_queued_events=$maxq cannot be saturated by a unit test" "$ROWS_B_1B"
  else
    OV="$TESTROOT/ov"; mkdir -p "$OV/root/many" "$OV/root/.audit-sentinels"
    nfiles=$((maxq + 1000))
    python3 - "$OV/root" "$NONCE" "$nfiles" <<'PYEOF'
import os, sys
root, nonce, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
for i in range(n):
    open(os.path.join(root, "many", "f%d" % i), "w").close()
for k in ("start-1", "end-1"):
    open(os.path.join(root, ".audit-sentinels", "%s-%s" % (nonce, k)), "w").close()
PYEOF
    python3 "$READER" "$OV/root" --exclude .git >"$OV/events" 2>"$OV/reader.err" &
    rp=$!; BG_PIDS="$BG_PIDS $rp"
    for _i in $(seq 1 100); do grep -qx ready "$OV/reader.err" 2>/dev/null && break; sleep 0.1; done
    : < "$OV/root/.audit-sentinels/${NONCE}-start-1"
    kill -STOP "$rp"
    python3 - "$OV/root" "$nfiles" <<'PYEOF'
import os, sys
root, n = sys.argv[1], int(sys.argv[2])
for i in range(n):
    with open(os.path.join(root, "many", "f%d" % i)) as fh:
        pass
PYEOF
    : < "$OV/root/.audit-sentinels/${NONCE}-end-1"
    kill -CONT "$rp"
    for _i in $(seq 1 100); do grep -qx Q "$OV/events" 2>/dev/null && break; sleep 0.1; done
    sleep 0.3
    kill "$rp" 2>/dev/null; wait "$rp" 2>/dev/null
    grep -qx Q "$OV/events"; g=$?
    ok_if "row 1b: the real reader reports IN_Q_OVERFLOW after $nfiles opens with the queue at $maxq" "$g"
    printf 'NONCE\t%s\nREV\t%s\nW\t1\tovl\t1\t0\t-\t0.5\tmany/\t-\n' "$NONCE" "$FAKE_REV" > "$OV/meta"
    RUN="$OV"; bash "$SCRIPT" verdict --events "$OV/events" --reader-err "$OV/reader.err" --meta "$OV/meta" --root "$OV/root" >"$OV/out" 2>"$OV/err"; RC=$?
    OUT="$OV/out"
    expect_row "row 1b: row for the overflowed live recording is unreliable" 3 ovl unreliable "reason=q_overflow"
    if (( cases - B1B_START != ROWS_B_1B )); then
      printf '[FATAL] row 1b holds %s rows but ROWS_B_1B says %s: update ROWS_B_1B (it prices a skip)\n' "$((cases - B1B_START))" "$ROWS_B_1B" >&2
      exit 2
    fi
  fi
fi

echo "== B2. the recorder reader itself (python3 + inotify only) =="
ROWS_R=9
R_START=$cases
if (( HAVE_INOTIFY == 0 )); then
  skip_or_fail "section B2 (reader rows): python3 ctypes inotify unavailable" "$ROWS_R"
else
  RD="$TESTROOT/rd"; mkdir -p "$RD/root/sub" "$RD/root/mv1" "$RD/ext"
  : > "$RD/root/good"; : > "$RD/root/bad"$'\377'
  python3 "$READER" "$RD/root" >"$RD/events" 2>"$RD/err" &
  rp=$!; BG_PIDS="$BG_PIDS $rp"
  for _i in $(seq 1 100); do grep -qx ready "$RD/err" 2>/dev/null && break; sleep 0.1; done
  cat "$RD/root/bad"$'\377' >/dev/null; cat "$RD/root/good" >/dev/null
  rmdir "$RD/root/sub"; mv "$RD/root/mv1" "$RD/root/mv2"; mv "$RD/ext" "$RD/root/ext"
  for _i in $(seq 1 100); do grep -qxF $'O\tgood' "$RD/events" 2>/dev/null && grep -qxF $'X\text' "$RD/events" 2>/dev/null && break; sleep 0.1; done
  g=0; LC_ALL=C grep -qxF -- $'O\tbad\377' "$RD/events" || g=1
  ok_if "reader: a non-UTF-8 file name is recorded byte-exact" "$g"
  g=0; grep -qxF $'O\tgood' "$RD/events" || g=1
  ok_if "reader: the reader survived the undecodable name (a later open is recorded)" "$g"
  g=0; kill -0 "$rp" 2>/dev/null || g=1
  ok_if "reader: still running after the undecodable name" "$g"
  g=0; grep -qxF $'X\tsub' "$RD/events" || g=1
  ok_if "reader: a deleted watched directory is reported (X<TAB>path)" "$g"
  g=0; grep -qxF $'X\tmv1' "$RD/events" || g=1
  ok_if "reader: a renamed watched directory is reported (X<TAB>path)" "$g"
  g=0; grep -qxF $'X\text' "$RD/events" || g=1
  ok_if "reader: a directory moved INTO the watched tree (never watched) is reported (X<TAB>path)" "$g"
  kill "$rp" 2>/dev/null; wait "$rp" 2>/dev/null
  python3 "$READER" "$TESTROOT/does-not-exist" >"$RD/events2" 2>"$RD/err2"; rrc=$?
  ok_if "reader: a nonexistent root exits non-zero (rc=$rrc)" "$(( rrc == 0 ))"
  g=0; ! grep -qx ready "$RD/err2" || g=1
  ok_if "reader: a nonexistent root never prints ready" "$g"
  # the reader exits when its parent dies (captured pids, no -f patterns)
  rm -f "$RD/rd.pid"
  bash -c 'python3 "$1" "$2" >/dev/null 2>"$3" & echo $! > "$4"; wait' _ "$READER" "$RD/root" "$RD/err3" "$RD/rd.pid" &
  pp=$!; BG_PIDS="$BG_PIDS $pp"
  wait_file "$RD/rd.pid" || true
  rpid="$(cat "$RD/rd.pid" 2>/dev/null)"
  for _i in $(seq 1 100); do grep -qx ready "$RD/err3" 2>/dev/null && break; sleep 0.1; done
  kill -KILL "$pp" 2>/dev/null; wait "$pp" 2>/dev/null
  left=1; if [[ "$rpid" =~ ^[0-9]+$ ]] && wait_pid_gone "$rpid"; then left=0; fi
  ok_if "reader: exits by itself when its parent is killed (pid $rpid)" "$left"
fi
if (( HAVE_INOTIFY == 1 )); then
  R_ROWS=$((cases - R_START))
  if (( R_ROWS != ROWS_R )); then
    printf '[FATAL] section B2 holds %s rows but ROWS_R says %s: update ROWS_R (it prices a skip)\n' "$R_ROWS" "$ROWS_R" >&2
    exit 2
  fi
fi

# ---- scratch PATH: a shell FUNCTION named like a tool must not drop the tool from the scratch bin --------
cases=$((cases + 1))
_sb="$TESTROOT/scratch-bin-fn"
_sbo="$( (
  # shellcheck disable=SC2329  # the function exists to SHADOW the real grep for make_scratch_bin; it is never called here
  grep() { echo "shim"; }
  eval "$(sed -n '/^make_scratch_bin()/,/^}/p' "$SCRIPT")"
  make_scratch_bin "$_sb"
  if [[ -x "$_sb/grep" && "$(readlink "$_sb/grep")" == /* ]]; then echo LINKED; else echo MISSING; fi
) 2>&1 )"
if [[ "$_sbo" == "LINKED" ]]; then pass "scratch bin: a shell function named grep does not remove grep from the scratch PATH (type -P)"; else fail "scratch bin: grep $_sbo"; fi

# ---- the REAL runner must enumerate under the scratch PATH (every tool it calls is in the bin) ------------
# The first real run found `ps` missing (runner rc 127, zero suites): a scratch PATH is only as good as the
# tools the runner it hosts actually calls, so drive the real enumerate under it.
cases=$((cases + 1))
_sbr="$TESTROOT/scratch-bin-real"; mkdir -p "$TESTROOT/rtmp-real"
eval "$(sed -n '/^make_scratch_bin()/,/^}/p' "$SCRIPT")"
make_scratch_bin "$_sbr"
_enum_n="$( cd "$REPO_ROOT" && env -i HOME="$TESTROOT/rtmp-real" TMPDIR="$TESTROOT/rtmp-real" PATH="$_sbr" LANG=C bash scripts/test-all.sh --enumerate-commands all 2>"$TESTROOT/enum-real.err" | grep -c $'^SUITE_COMMAND\t' )"
if [[ "$_enum_n" =~ ^[0-9]+$ ]] && (( _enum_n >= 400 )); then
  pass "scratch bin: the real runner enumerates $_enum_n registrations under env -i with only the scratch PATH"
else
  fail "scratch bin: real enumerate under the scratch PATH gave '$_enum_n' registrations; stderr: $(grep -h 'command not found' "$TESTROOT/enum-real.err" | sort -u | head -3 | tr '\n' ';')"
fi

# Tools the runner-reaching suites call (found by the A5 check run: perl and truncate were missing, so three
# suites exited non-zero in the sandbox and produced no evidence). Each one the host has must reach the bin.
cases=$((cases + 1))
_miss=""
for _t in perl truncate setsid ps grep sed awk; do
  if _p="$(type -P "$_t" 2>/dev/null)" && [[ -n "$_p" && ! -x "$_sbr/$_t" ]]; then _miss="$_miss $_t"; fi
done
if [[ -z "$_miss" ]]; then pass "scratch bin: perl, truncate, setsid and the core text tools reach the scratch PATH"; else fail "scratch bin: missing from the scratch bin:$_miss"; fi

echo "== C. script header and floors =="
hdr="$TESTROOT/header.txt"; awk 'NR > 1 && /^#/ { print } /^[^#]/ && NR > 1 { exit }' "$SCRIPT" > "$hdr"
for phrase in "probes of missing files" "directories created mid-run" "window-boundary" "env -i" "unshare" \
              "ISOLATION IS NOT A SANDBOX" "kept on purpose" "bare name matched at any depth" "dir-moved" "git add -A -f"; do
  g=0; grep -qF -- "$phrase" "$hdr" || g=1
  ok_if "header names the blind spot / mechanism: [$phrase]" "$g"
done
bash "$SCRIPT" --help >"$TESTROOT/help.out" 2>&1; RC=$?
g=0; [[ "$RC" == 0 ]] && grep -qF -- "record" "$TESTROOT/help.out" && grep -qF -- "--cover-from-selection" "$TESTROOT/help.out" || g=1
ok_if "--help exits 0 and names record + --cover-from-selection" "$g"

# ---- verdict accounting (reported with printf + exit, never through the pass/fail helpers it guards) ----
echo ""
if (( PASS + FAIL != cases )); then
  printf '[FATAL] verdict mismatch: PASS(%s)+FAIL(%s) != cases(%s) - a row was skipped\n' "$PASS" "$FAIL" "$cases" >&2
  exit 2
fi
# An exact floor: the real row count of a complete run. A section that SKIPs is priced at its REAL row count
# (ROWS_B_CORE / ROWS_B_1B / ROWS_R / a counted one-row skip), so a legitimate skip cannot trip the floor and a
# deleted row still does. Reported with printf + exit, never through pass()/fail().
SKIPPED_ROWS="${SKIPPED_ROWS:-0}"   # bound beside the floor so scripts/guard-vacuity-floor.test.sh's mutant slice (which zeroes only the counters) can construct
MIN_CASES=326
if (( cases + SKIPPED_ROWS < MIN_CASES )); then
  printf '[FATAL] only %s rows ran (+%s rows skipped%s) - below the %s floor; rows were deleted?\n' "$cases" "$SKIPPED_ROWS" "${SKIP_CAUSES:+: $SKIP_CAUSES}" "$MIN_CASES" >&2
  exit 2
fi
echo "$PASS passed, $FAIL failed (skipped sections: $SKIPPED, skipped rows: $SKIPPED_ROWS, rows: $cases)"
if (( FAIL > 0 )); then exit 1; fi
exit 0
